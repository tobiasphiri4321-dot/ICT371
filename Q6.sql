CREATE DATABASE IF NOT EXISTS payroll_db;
USE payroll_db;
DROP TABLE IF EXISTS monthly_payroll;
DROP TABLE IF EXISTS payroll_audit;
DROP TABLE IF EXISTS payroll;
DROP TABLE IF EXISTS employees;
CREATE TABLE employees (employee_id INT AUTO_INCREMENT PRIMARY KEY, emp_no VARCHAR(20) UNIQUE NOT NULL, full_name VARCHAR(100) NOT NULL, basic_salary DECIMAL(12,2) NOT NULL CHECK(basic_salary>0));
CREATE TABLE payroll (payroll_id INT AUTO_INCREMENT PRIMARY KEY, employee_id INT NOT NULL, pay_month DATE NOT NULL, gross DECIMAL(12,2) NOT NULL, tax DECIMAL(12,2) NOT NULL, net DECIMAL(12,2) NOT NULL, UNIQUE(employee_id,pay_month), FOREIGN KEY(employee_id) REFERENCES employees(employee_id));
CREATE TABLE payroll_audit (audit_id INT AUTO_INCREMENT PRIMARY KEY, payroll_id INT NOT NULL, old_net DECIMAL(12,2), new_net DECIMAL(12,2), changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);
CREATE TABLE monthly_payroll (pay_month DATE PRIMARY KEY, emp_count INT DEFAULT 0, total_net DECIMAL(12,2) DEFAULT 0);
INSERT INTO employees(emp_no,full_name,basic_salary) VALUES('EMP-001','Chanda',5000),('EMP-002','Grace',4000),('EMP-003','Peter',6000);

DROP FUNCTION IF EXISTS fn_net_pay;
DELIMITER //
CREATE FUNCTION fn_net_pay(p_basic DECIMAL(12,2), p_allow DECIMAL(12,2)) RETURNS DECIMAL(12,2) DETERMINISTIC
BEGIN DECLARE v_gross DECIMAL(12,2); SET v_gross=p_basic+IFNULL(p_allow,0); RETURN v_gross - (v_gross*0.10); END //
DELIMITER ;

DROP PROCEDURE IF EXISTS pr_process_payroll;
DELIMITER //
CREATE PROCEDURE pr_process_payroll(IN p_emp INT, IN p_month DATE, IN p_allow DECIMAL(12,2))
BEGIN DECLARE v_basic DECIMAL(12,2); DECLARE v_gross DECIMAL(12,2); DECLARE v_net DECIMAL(12,2);
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END; START TRANSACTION;
 SELECT basic_salary INTO v_basic FROM employees WHERE employee_id=p_emp FOR UPDATE;
 IF v_basic IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Unknown employee'; END IF;
 IF p_allow<0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Allowance cannot be negative'; END IF;
 SET v_gross=v_basic+IFNULL(p_allow,0); SET v_net=fn_net_pay(v_basic,p_allow);
 INSERT INTO payroll(employee_id,pay_month,gross,tax,net) VALUES(p_emp,p_month,v_gross,v_gross*0.10,v_net); COMMIT; END //
DELIMITER ;

DROP TRIGGER IF EXISTS trg_payroll_audit;
DELIMITER //
CREATE TRIGGER trg_payroll_audit AFTER UPDATE ON payroll FOR EACH ROW
BEGIN IF OLD.net <> NEW.net THEN INSERT INTO payroll_audit(payroll_id,old_net,new_net) VALUES(NEW.payroll_id,OLD.net,NEW.net); END IF; END //
DELIMITER ;

CALL pr_process_payroll(1,'2026-11-01',500);
CALL pr_process_payroll(2,'2026-11-01',300);
CALL pr_process_payroll(3,'2026-11-01',0);
CALL pr_process_payroll(1,'2026-10-01',500);
CALL pr_process_payroll(2,'2026-10-01',300);
CALL pr_process_payroll(3,'2026-10-01',200);

DROP VIEW IF EXISTS v_payroll_summary;
CREATE VIEW v_payroll_summary AS SELECT e.emp_no,e.full_name,p.pay_month,p.gross,p.tax,p.net FROM payroll p JOIN employees e ON e.employee_id=p.employee_id;

CREATE INDEX idx_payroll_emp_month ON payroll(employee_id, pay_month);
EXPLAIN SELECT * FROM payroll WHERE employee_id=1 AND pay_month BETWEEN '2026-01-01' AND '2026-11-01';

DROP PROCEDURE IF EXISTS pr_refresh_monthly_payroll;
DELIMITER //
CREATE PROCEDURE pr_refresh_monthly_payroll(IN p_month DATE)
BEGIN INSERT INTO monthly_payroll(pay_month,emp_count,total_net) SELECT p_month,COUNT(*),COALESCE(SUM(net),0) FROM payroll WHERE pay_month=p_month ON DUPLICATE KEY UPDATE emp_count=VALUES(emp_count), total_net=VALUES(total_net); END //
DELIMITER ;
SET GLOBAL event_scheduler = ON;
DROP EVENT IF EXISTS ev_monthly_payroll;
CREATE EVENT ev_monthly_payroll ON SCHEDULE EVERY 1 MONTH STARTS '2026-12-01 01:00:00' DO CALL pr_refresh_monthly_payroll(DATE_FORMAT(CURDATE()-INTERVAL 1 MONTH,'%Y-%m-01'));
CALL pr_refresh_monthly_payroll('2026-11-01');
