CREATE DATABASE IF NOT EXISTS university_db;
USE university_db;
DROP TABLE IF EXISTS daily_collections;
DROP TABLE IF EXISTS payment_audit;
DROP TABLE IF EXISTS payments;
DROP TABLE IF EXISTS students;

CREATE TABLE students (student_id INT AUTO_INCREMENT PRIMARY KEY, student_number VARCHAR(20) NOT NULL UNIQUE, full_name VARCHAR(100) NOT NULL, fee_due DECIMAL(12,2) NOT NULL CHECK (fee_due >= 0));
CREATE TABLE payments (payment_id INT AUTO_INCREMENT PRIMARY KEY, student_id INT NOT NULL, amount DECIMAL(12,2) NOT NULL CHECK (amount > 0), paid_on DATE NOT NULL, FOREIGN KEY (student_id) REFERENCES students(student_id));
CREATE TABLE payment_audit (audit_id INT AUTO_INCREMENT PRIMARY KEY, payment_id INT NOT NULL, student_id INT NOT NULL, amount DECIMAL(12,2) NOT NULL, logged_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, FOREIGN KEY (payment_id) REFERENCES payments(payment_id), FOREIGN KEY (student_id) REFERENCES students(student_id));
CREATE TABLE daily_collections (collection_date DATE PRIMARY KEY, payment_count INT NOT NULL DEFAULT 0, total_amount DECIMAL(12,2) NOT NULL DEFAULT 0.00);
INSERT INTO students (student_number, full_name, fee_due) VALUES ('STU-001','Chanda Mwale',5000),('STU-002','Grace Banda',3000),('STU-003','Peter Phiri',4000);

-- (b) FUNCTION
DROP FUNCTION IF EXISTS fn_fee_balance;
DELIMITER //
CREATE FUNCTION fn_fee_balance(p_student_id INT) RETURNS DECIMAL(12,2) READS SQL DATA DETERMINISTIC
BEGIN
    DECLARE v_fee DECIMAL(12,2); DECLARE v_paid DECIMAL(12,2);
    SELECT fee_due INTO v_fee FROM students WHERE student_id=p_student_id;
    IF v_fee IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Unknown student'; END IF;
    SELECT COALESCE(SUM(amount),0) INTO v_paid FROM payments WHERE student_id=p_student_id;
    RETURN v_fee - v_paid;
END //
DELIMITER ;

-- (c) PROCEDURE
DROP PROCEDURE IF EXISTS pr_receive_payment;
DELIMITER //
CREATE PROCEDURE pr_receive_payment(IN p_student_id INT, IN p_amount DECIMAL(12,2), IN p_paid_on DATE)
BEGIN
    DECLARE v_balance DECIMAL(12,2);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    START TRANSACTION;
    IF p_amount IS NULL OR p_amount <=0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Amount must be positive'; END IF;
    SET v_balance = fn_fee_balance(p_student_id);
    IF p_amount > v_balance THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Payment exceeds balance - no credit allowed'; END IF;
    INSERT INTO payments (student_id, amount, paid_on) VALUES (p_student_id, p_amount, p_paid_on);
    COMMIT;
END //
DELIMITER ;

-- (d) TRIGGER
DROP TRIGGER IF EXISTS trg_payments_audit;
DELIMITER //
CREATE TRIGGER trg_payments_audit AFTER INSERT ON payments FOR EACH ROW
BEGIN
    INSERT INTO payment_audit (payment_id, student_id, amount, logged_at) VALUES (NEW.payment_id, NEW.student_id, NEW.amount, NOW());
END //
DELIMITER ;

CALL pr_receive_payment(1,1000,'2026-11-24');
CALL pr_receive_payment(1,1500,'2026-11-24');
CALL pr_receive_payment(1,500,'2026-11-23');
CALL pr_receive_payment(2,1000,'2026-11-24');
CALL pr_receive_payment(2,1000,'2026-11-23');
CALL pr_receive_payment(2,500,'2026-11-23');

-- (e) VIEW
DROP VIEW IF EXISTS v_fee_balances;
CREATE VIEW v_fee_balances AS
SELECT s.student_number, s.full_name, s.fee_due - COALESCE(SUM(p.amount),0) AS outstanding_balance
FROM students s LEFT JOIN payments p ON p.student_id=s.student_id
GROUP BY s.student_id, s.student_number, s.full_name, s.fee_due HAVING outstanding_balance > 0;
SELECT * FROM v_fee_balances;

-- (f) INDEX
CREATE INDEX idx_payments_student_date ON payments (student_id, paid_on);
EXPLAIN SELECT payment_id, amount, paid_on FROM payments WHERE student_id=1 AND paid_on BETWEEN '2026-11-01' AND '2026-11-24';

-- (g) JOB
DROP PROCEDURE IF EXISTS pr_refresh_collections;
DELIMITER //
CREATE PROCEDURE pr_refresh_collections(IN p_day DATE)
BEGIN
    INSERT INTO daily_collections (collection_date, payment_count, total_amount)
    SELECT p_day, COUNT(*), COALESCE(SUM(amount),0) FROM payments WHERE paid_on=p_day
    ON DUPLICATE KEY UPDATE payment_count=VALUES(payment_count), total_amount=VALUES(total_amount);
END //
DELIMITER ;
SET GLOBAL event_scheduler = ON;
DROP EVENT IF EXISTS ev_refresh_daily_collections;
CREATE EVENT ev_refresh_daily_collections ON SCHEDULE EVERY 1 DAY STARTS '2026-11-25 01:00:00' DO CALL pr_refresh_collections(CURDATE() - INTERVAL 1 DAY);
CALL pr_refresh_collections('2026-11-24');
