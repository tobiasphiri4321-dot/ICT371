CREATE DATABASE IF NOT EXISTS library_db;
USE library_db;
DROP TABLE IF EXISTS overdue_summary;
DROP TABLE IF EXISTS loan_audit;
DROP TABLE IF EXISTS loans;
DROP TABLE IF EXISTS books;
CREATE TABLE books (book_id INT AUTO_INCREMENT PRIMARY KEY, title VARCHAR(150) NOT NULL);
CREATE TABLE loans (loan_id INT AUTO_INCREMENT PRIMARY KEY, book_id INT NOT NULL, borrower_name VARCHAR(100) NOT NULL, borrowed_on DATE NOT NULL, due_on DATE NOT NULL, returned_on DATE NULL, fine_amount DECIMAL(10,2) NOT NULL DEFAULT 0.00, CHECK(due_on>=borrowed_on), CHECK(returned_on IS NULL OR returned_on>=borrowed_on), FOREIGN KEY(book_id) REFERENCES books(book_id));
CREATE TABLE loan_audit (audit_id INT AUTO_INCREMENT PRIMARY KEY, loan_id INT NOT NULL, old_returned_on DATE NULL, new_returned_on DATE NULL, changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, FOREIGN KEY(loan_id) REFERENCES loans(loan_id));
CREATE TABLE overdue_summary (snapshot_date DATE PRIMARY KEY, overdue_count INT NOT NULL DEFAULT 0, total_fine DECIMAL(12,2) NOT NULL DEFAULT 0.00);
INSERT INTO books (title) VALUES ('Database Systems'),('Introduction to SQL'),('Data Structures');

-- (b) FUNCTION - K2 per day overdue
DROP FUNCTION IF EXISTS fn_loan_fine;
DELIMITER //
CREATE FUNCTION fn_loan_fine(p_loan_id INT, p_as_of DATE) RETURNS DECIMAL(10,2) READS SQL DATA DETERMINISTIC
BEGIN
    DECLARE v_due DATE; DECLARE v_returned DATE; DECLARE v_end DATE; DECLARE v_days INT;
    SELECT due_on, returned_on INTO v_due, v_returned FROM loans WHERE loan_id=p_loan_id;
    IF v_due IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Unknown loan'; END IF;
    IF v_returned IS NOT NULL THEN SET v_end=LEAST(p_as_of, v_returned); ELSE SET v_end=p_as_of; END IF;
    SET v_days=DATEDIFF(v_end, v_due);
    IF v_days<0 THEN SET v_days=0; END IF;
    RETURN v_days*2.00;
END //
DELIMITER ;

-- (c) PROCEDURE
DROP PROCEDURE IF EXISTS pr_return_loan;
DELIMITER //
CREATE PROCEDURE pr_return_loan(IN p_loan_id INT, IN p_returned_on DATE)
BEGIN
    DECLARE v_borrowed DATE; DECLARE v_returned DATE; DECLARE v_fine DECIMAL(10,2);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    START TRANSACTION;
    SELECT borrowed_on, returned_on INTO v_borrowed, v_returned FROM loans WHERE loan_id=p_loan_id FOR UPDATE;
    IF v_borrowed IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Unknown loan'; END IF;
    IF v_returned IS NOT NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Already returned'; END IF;
    IF p_returned_on < v_borrowed THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Return before borrowed'; END IF;
    SET v_fine=fn_loan_fine(p_loan_id, p_returned_on);
    UPDATE loans SET returned_on=p_returned_on, fine_amount=v_fine WHERE loan_id=p_loan_id;
    COMMIT;
END //
DELIMITER ;

-- (d) TRIGGER
DROP TRIGGER IF EXISTS trg_loans_return_audit;
DELIMITER //
CREATE TRIGGER trg_loans_return_audit AFTER UPDATE ON loans FOR EACH ROW
BEGIN
    IF NOT (OLD.returned_on <=> NEW.returned_on) THEN
        INSERT INTO loan_audit (loan_id, old_returned_on, new_returned_on) VALUES (NEW.loan_id, OLD.returned_on, NEW.returned_on);
    END IF;
END //
DELIMITER ;

INSERT INTO loans (book_id, borrower_name, borrowed_on, due_on, returned_on, fine_amount) VALUES
(1,'Chanda Mwale','2026-11-01','2026-11-08',NULL,0),
(1,'Grace Banda','2026-11-10','2026-11-17',NULL,0),
(2,'Peter Phiri','2026-11-01','2026-11-08','2026-11-08',0),
(2,'Mary Zulu','2026-11-01','2026-11-08','2026-11-12',8.00),
(3,'John Tembo','2026-11-15','2026-11-22',NULL,0),
(3,'Sarah Lungu','2026-11-15','2026-11-22',NULL,0);

-- (e) VIEW
DROP VIEW IF EXISTS v_overdue_loans;
CREATE VIEW v_overdue_loans AS
SELECT l.loan_id, b.title AS book_title, l.borrower_name, l.due_on, fn_loan_fine(l.loan_id, CURRENT_DATE) AS fine_as_of_today
FROM loans l JOIN books b ON b.book_id=l.book_id WHERE l.returned_on IS NULL AND l.due_on < CURRENT_DATE;
SELECT * FROM v_overdue_loans;

-- (f) INDEX
CREATE INDEX idx_loans_book_unreturned ON loans (book_id, returned_on);
EXPLAIN SELECT loan_id, borrower_name, due_on FROM loans WHERE book_id=1 AND returned_on IS NULL;

-- (g) JOB
DROP PROCEDURE IF EXISTS pr_refresh_overdue;
DELIMITER //
CREATE PROCEDURE pr_refresh_overdue(IN p_as_of DATE)
BEGIN
    INSERT INTO overdue_summary (snapshot_date, overdue_count, total_fine)
    SELECT p_as_of, COUNT(*), COALESCE(SUM(fn_loan_fine(loan_id, p_as_of)),0)
    FROM loans WHERE returned_on IS NULL AND due_on < p_as_of
    ON DUPLICATE KEY UPDATE overdue_count=VALUES(overdue_count), total_fine=VALUES(total_fine);
END //
DELIMITER ;
SET GLOBAL event_scheduler = ON;
DROP EVENT IF EXISTS ev_refresh_overdue;
CREATE EVENT ev_refresh_overdue ON SCHEDULE EVERY 1 DAY STARTS '2026-11-25 00:10:00' DO CALL pr_refresh_overdue(CURRENT_DATE);
CALL pr_refresh_overdue(CURRENT_DATE);
