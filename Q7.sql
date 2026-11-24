CREATE DATABASE IF NOT EXISTS water_db;
USE water_db;
DROP TABLE IF EXISTS monthly_billing;
DROP TABLE IF EXISTS reading_audit;
DROP TABLE IF EXISTS readings;
DROP TABLE IF EXISTS customers;
CREATE TABLE customers (customer_id INT AUTO_INCREMENT PRIMARY KEY, account_no VARCHAR(20) UNIQUE NOT NULL, full_name VARCHAR(100) NOT NULL);
CREATE TABLE readings (reading_id INT AUTO_INCREMENT PRIMARY KEY, customer_id INT NOT NULL, reading_value INT NOT NULL CHECK(reading_value>=0), read_on DATE NOT NULL, units_used INT NOT NULL DEFAULT 0, bill_amount DECIMAL(10,2) NOT NULL DEFAULT 0, FOREIGN KEY(customer_id) REFERENCES customers(customer_id));
CREATE TABLE reading_audit (audit_id INT AUTO_INCREMENT PRIMARY KEY, reading_id INT NOT NULL, old_value INT, new_value INT, changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);
CREATE TABLE monthly_billing (bill_month DATE PRIMARY KEY, total_units INT DEFAULT 0, total_amount DECIMAL(12,2) DEFAULT 0);
INSERT INTO customers(account_no,full_name) VALUES('W-001','Chanda'),('W-002','Grace'),('W-003','Peter');

DROP FUNCTION IF EXISTS fn_bill_amount;
DELIMITER //
CREATE FUNCTION fn_bill_amount(p_units INT) RETURNS DECIMAL(10,2) DETERMINISTIC
BEGIN IF p_units<=0 THEN RETURN 0; END IF; IF p_units<=10 THEN RETURN p_units*2.00; ELSE RETURN 20 + (p_units-10)*3.00; END IF; END //
DELIMITER ;

DROP PROCEDURE IF EXISTS pr_record_reading;
DELIMITER //
CREATE PROCEDURE pr_record_reading(IN p_cust INT, IN p_val INT, IN p_date DATE)
BEGIN DECLARE v_prev INT; DECLARE v_units INT;
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END; START TRANSACTION;
 SELECT reading_value INTO v_prev FROM readings WHERE customer_id=p_cust ORDER BY read_on DESC, reading_id DESC LIMIT 1;
 IF v_prev IS NOT NULL AND p_val < v_prev THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Reading cannot go backwards'; END IF;
 SET v_units = IFNULL(p_val - IFNULL(v_prev,0), p_val);
 INSERT INTO readings(customer_id,reading_value,read_on,units_used,bill_amount) VALUES(p_cust,p_val,p_date,v_units,fn_bill_amount(v_units)); COMMIT; END //
DELIMITER ;

DROP TRIGGER IF EXISTS trg_reading_audit;
DELIMITER //
CREATE TRIGGER trg_reading_audit AFTER UPDATE ON readings FOR EACH ROW
BEGIN IF OLD.reading_value <> NEW.reading_value THEN INSERT INTO reading_audit(reading_id,old_value,new_value) VALUES(NEW.reading_id,OLD.reading_value,NEW.reading_value); END IF; END //
DELIMITER ;

CALL pr_record_reading(1,100,'2026-11-01');
CALL pr_record_reading(2,200,'2026-11-01');
CALL pr_record_reading(3,50,'2026-11-01');
CALL pr_record_reading(1,115,'2026-11-24');
CALL pr_record_reading(2,230,'2026-11-24');
CALL pr_record_reading(3,70,'2026-11-24');

DROP VIEW IF EXISTS v_high_usage;
CREATE VIEW v_high_usage AS SELECT c.account_no,c.full_name,r.read_on,r.units_used,r.bill_amount FROM readings r JOIN customers c ON c.customer_id=r.customer_id WHERE r.units_used > 20;

CREATE INDEX idx_readings_cust_date ON readings(customer_id, read_on);
EXPLAIN SELECT * FROM readings WHERE customer_id=1 AND read_on BETWEEN '2026-11-01' AND '2026-11-30';

DROP PROCEDURE IF EXISTS pr_refresh_billing;
DELIMITER //
CREATE PROCEDURE pr_refresh_billing(IN p_month DATE)
BEGIN INSERT INTO monthly_billing(bill_month,total_units,total_amount) SELECT p_month, COALESCE(SUM(units_used),0), COALESCE(SUM(bill_amount),0) FROM readings WHERE DATE_FORMAT(read_on,'%Y-%m-01')=p_month ON DUPLICATE KEY UPDATE total_units=VALUES(total_units), total_amount=VALUES(total_amount); END //
DELIMITER ;
SET GLOBAL event_scheduler = ON;
DROP EVENT IF EXISTS ev_billing;
CREATE EVENT ev_billing ON SCHEDULE EVERY 1 MONTH STARTS '2026-12-01 00:15:00' DO CALL pr_refresh_billing(DATE_FORMAT(CURDATE()-INTERVAL 1 MONTH,'%Y-%m-01'));
