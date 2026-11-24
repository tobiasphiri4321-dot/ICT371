CREATE DATABASE IF NOT EXISTS clinic_db;
USE clinic_db;
DROP TABLE IF EXISTS daily_appointments;
DROP TABLE IF EXISTS appointment_audit;
DROP TABLE IF EXISTS appointments;
DROP TABLE IF EXISTS patients;
DROP TABLE IF EXISTS doctors;
CREATE TABLE doctors (doctor_id INT AUTO_INCREMENT PRIMARY KEY, full_name VARCHAR(100) NOT NULL);
CREATE TABLE patients (patient_id INT AUTO_INCREMENT PRIMARY KEY, full_name VARCHAR(100) NOT NULL);
CREATE TABLE appointments (appointment_id INT AUTO_INCREMENT PRIMARY KEY, doctor_id INT NOT NULL, patient_id INT NOT NULL, appointment_date DATE NOT NULL, start_time TIME NOT NULL, end_time TIME NOT NULL, status VARCHAR(20) NOT NULL DEFAULT 'BOOKED' CHECK(status IN('BOOKED','CANCELLED','DONE')), fee DECIMAL(10,2) NOT NULL CHECK(fee>0), CHECK(end_time>start_time), FOREIGN KEY(doctor_id) REFERENCES doctors(doctor_id), FOREIGN KEY(patient_id) REFERENCES patients(patient_id));
CREATE TABLE appointment_audit (audit_id INT AUTO_INCREMENT PRIMARY KEY, appointment_id INT NOT NULL, old_status VARCHAR(20), new_status VARCHAR(20), changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, FOREIGN KEY(appointment_id) REFERENCES appointments(appointment_id));
CREATE TABLE daily_appointments (appt_date DATE PRIMARY KEY, total_count INT DEFAULT 0, total_fees DECIMAL(12,2) DEFAULT 0);
INSERT INTO doctors(full_name) VALUES('Dr. Mwale'),('Dr. Banda'),('Dr. Phiri');
INSERT INTO patients(full_name) VALUES('Chanda Mwale'),('Grace Banda'),('Peter Phiri');

DROP FUNCTION IF EXISTS fn_is_doctor_free;
DELIMITER //
CREATE FUNCTION fn_is_doctor_free(p_doctor INT, p_date DATE, p_start TIME, p_end TIME) RETURNS INT READS SQL DATA DETERMINISTIC
BEGIN DECLARE v_cnt INT; SELECT COUNT(*) INTO v_cnt FROM appointments WHERE doctor_id=p_doctor AND appointment_date=p_date AND status='BOOKED' AND start_time < p_end AND end_time > p_start; RETURN IF(v_cnt=0,1,0); END //
DELIMITER ;

DROP PROCEDURE IF EXISTS pr_book_appointment;
DELIMITER //
CREATE PROCEDURE pr_book_appointment(IN p_doc INT, IN p_pat INT, IN p_date DATE, IN p_start TIME, IN p_end TIME, IN p_fee DECIMAL(10,2))
BEGIN
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END; START TRANSACTION;
 IF p_fee IS NULL OR p_fee<=0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Invalid fee'; END IF;
 IF p_end<=p_start THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='End must be after start'; END IF;
 IF fn_is_doctor_free(p_doc,p_date,p_start,p_end)=0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Doctor already booked'; END IF;
 INSERT INTO appointments(doctor_id,patient_id,appointment_date,start_time,end_time,fee) VALUES(p_doc,p_pat,p_date,p_start,p_end,p_fee);
 COMMIT; END //
DELIMITER ;

DROP TRIGGER IF EXISTS trg_appt_status;
DELIMITER //
CREATE TRIGGER trg_appt_status AFTER UPDATE ON appointments FOR EACH ROW
BEGIN IF OLD.status <> NEW.status THEN INSERT INTO appointment_audit(appointment_id,old_status,new_status) VALUES(NEW.appointment_id,OLD.status,NEW.status); END IF; END //
DELIMITER ;

CALL pr_book_appointment(1,1,'2026-11-25','09:00','09:30',50);
CALL pr_book_appointment(1,2,'2026-11-25','09:30','10:00',50);
CALL pr_book_appointment(2,1,'2026-11-25','09:00','09:30',60);
CALL pr_book_appointment(2,3,'2026-11-24','10:00','10:30',60);
CALL pr_book_appointment(3,2,'2026-11-24','11:00','11:30',40);
CALL pr_book_appointment(3,3,'2026-11-25','11:00','11:30',40);

DROP VIEW IF EXISTS v_today_appointments;
CREATE VIEW v_today_appointments AS SELECT a.appointment_id,d.full_name AS doctor,p.full_name AS patient,a.start_time,a.end_time,a.status FROM appointments a JOIN doctors d ON d.doctor_id=a.doctor_id JOIN patients p ON p.patient_id=a.patient_id WHERE a.appointment_date=CURRENT_DATE AND a.status='BOOKED';

CREATE INDEX idx_appt_doctor_date ON appointments(doctor_id, appointment_date, start_time);
EXPLAIN SELECT * FROM appointments WHERE doctor_id=1 AND appointment_date='2026-11-25';

DROP PROCEDURE IF EXISTS pr_refresh_daily_appts;
DELIMITER //
CREATE PROCEDURE pr_refresh_daily_appts(IN p_day DATE)
BEGIN INSERT INTO daily_appointments(appt_date,total_count,total_fees) SELECT p_day, COUNT(*), COALESCE(SUM(fee),0) FROM appointments WHERE appointment_date=p_day AND status<>'CANCELLED' ON DUPLICATE KEY UPDATE total_count=VALUES(total_count), total_fees=VALUES(total_fees); END //
DELIMITER ;
SET GLOBAL event_scheduler = ON;
DROP EVENT IF EXISTS ev_daily_appts;
CREATE EVENT ev_daily_appts ON SCHEDULE EVERY 1 DAY STARTS '2026-11-25 00:20:00' DO CALL pr_refresh_daily_appts(CURDATE()-INTERVAL 1 DAY);
