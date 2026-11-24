CREATE DATABASE IF NOT EXISTS scholarship_db;
USE scholarship_db;
DROP TABLE IF EXISTS daily_assessment;
DROP TABLE IF EXISTS application_audit;
DROP TABLE IF EXISTS applications;
DROP TABLE IF EXISTS applicants;
CREATE TABLE applicants (applicant_id INT AUTO_INCREMENT PRIMARY KEY, applicant_no VARCHAR(20) UNIQUE NOT NULL, full_name VARCHAR(100) NOT NULL, gpa DECIMAL(3,2) NOT NULL CHECK(gpa BETWEEN 0 AND 4.0), income DECIMAL(12,2) NOT NULL CHECK(income>=0));
CREATE TABLE applications (application_id INT AUTO_INCREMENT PRIMARY KEY, applicant_id INT NOT NULL, score DECIMAL(5,2) NOT NULL DEFAULT 0, status VARCHAR(20) NOT NULL DEFAULT 'PENDING' CHECK(status IN('PENDING','ELIGIBLE','NOT ELIGIBLE')), applied_on DATE NOT NULL, FOREIGN KEY(applicant_id) REFERENCES applicants(applicant_id));
CREATE TABLE application_audit (audit_id INT AUTO_INCREMENT PRIMARY KEY, application_id INT NOT NULL, old_status VARCHAR(20), new_status VARCHAR(20), changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);
CREATE TABLE daily_assessment (assess_date DATE PRIMARY KEY, assessed_count INT DEFAULT 0, eligible_count INT DEFAULT 0);
INSERT INTO applicants(applicant_no,full_name,gpa,income) VALUES('SCH-001','Chanda',3.80,2000),('SCH-002','Grace',2.50,8000),('SCH-003','Peter',3.20,3000);

DROP FUNCTION IF EXISTS fn_eligibility_score;
DELIMITER //
CREATE FUNCTION fn_eligibility_score(p_gpa DECIMAL(3,2), p_income DECIMAL(12,2)) RETURNS DECIMAL(5,2) DETERMINISTIC
BEGIN RETURN p_gpa*20 + IF(p_income<5000,20,0); END //
DELIMITER ;

DROP PROCEDURE IF EXISTS pr_assess_application;
DELIMITER //
CREATE PROCEDURE pr_assess_application(IN p_app INT)
BEGIN DECLARE v_gpa DECIMAL(3,2); DECLARE v_inc DECIMAL(12,2); DECLARE v_score DECIMAL(5,2); DECLARE v_status VARCHAR(20);
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END; START TRANSACTION;
 SELECT a.gpa,a.income INTO v_gpa,v_inc FROM applications ap JOIN applicants a ON a.applicant_id=ap.applicant_id WHERE ap.application_id=p_app FOR UPDATE;
 IF v_gpa IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Unknown application'; END IF;
 SET v_score=fn_eligibility_score(v_gpa,v_inc); SET v_status=IF(v_score>=70,'ELIGIBLE','NOT ELIGIBLE');
 UPDATE applications SET score=v_score, status=v_status WHERE application_id=p_app; COMMIT; END //
DELIMITER ;

DROP TRIGGER IF EXISTS trg_app_audit;
DELIMITER //
CREATE TRIGGER trg_app_audit AFTER UPDATE ON applications FOR EACH ROW
BEGIN IF OLD.status <> NEW.status THEN INSERT INTO application_audit(application_id,old_status,new_status) VALUES(NEW.application_id,OLD.status,NEW.status); END IF; END //
DELIMITER ;

INSERT INTO applications(applicant_id,applied_on) VALUES(1,'2026-11-24'),(2,'2026-11-24'),(3,'2026-11-24'),(1,'2026-11-23'),(2,'2026-11-23'),(3,'2026-11-23');
CALL pr_assess_application(1);
CALL pr_assess_application(2);
CALL pr_assess_application(3);
CALL pr_assess_application(4);
CALL pr_assess_application(5);
CALL pr_assess_application(6);

DROP VIEW IF EXISTS v_eligible_applicants;
CREATE VIEW v_eligible_applicants AS SELECT a.applicant_no,a.full_name,ap.score,ap.status FROM applications ap JOIN applicants a ON a.applicant_id=ap.applicant_id WHERE ap.status='ELIGIBLE';
SELECT * FROM v_eligible_applicants;

CREATE INDEX idx_apps_applicant_date ON applications(applicant_id, applied_on);
EXPLAIN SELECT * FROM applications WHERE applicant_id=1 AND applied_on BETWEEN '2026-11-01' AND '2026-11-30';

DROP PROCEDURE IF EXISTS pr_refresh_assessment;
DELIMITER //
CREATE PROCEDURE pr_refresh_assessment(IN p_day DATE)
BEGIN INSERT INTO daily_assessment(assess_date,assessed_count,eligible_count) SELECT p_day, COUNT(*), SUM(status='ELIGIBLE') FROM applications WHERE applied_on=p_day ON DUPLICATE KEY UPDATE assessed_count=VALUES(assessed_count), eligible_count=VALUES(eligible_count); END //
DELIMITER ;
SET GLOBAL event_scheduler = ON;
DROP EVENT IF EXISTS ev_assessment;
CREATE EVENT ev_assessment ON SCHEDULE EVERY 1 DAY STARTS '2026-11-25 01:00:00' DO CALL pr_refresh_assessment(CURDATE()-INTERVAL 1 DAY);
CALL pr_refresh_assessment('2026-11-24');
