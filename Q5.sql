CREATE DATABASE IF NOT EXISTS hostel_db;
USE hostel_db;
DROP TABLE IF EXISTS occupancy_summary;
DROP TABLE IF EXISTS allocation_audit;
DROP TABLE IF EXISTS allocations;
DROP TABLE IF EXISTS students;
DROP TABLE IF EXISTS rooms;
CREATE TABLE rooms (room_id INT AUTO_INCREMENT PRIMARY KEY, room_no VARCHAR(20) UNIQUE NOT NULL, capacity INT NOT NULL CHECK(capacity>0));
CREATE TABLE students (student_id INT AUTO_INCREMENT PRIMARY KEY, student_number VARCHAR(20) UNIQUE NOT NULL, full_name VARCHAR(100) NOT NULL);
CREATE TABLE allocations (allocation_id INT AUTO_INCREMENT PRIMARY KEY, student_id INT NOT NULL, room_id INT NOT NULL, allocated_on DATE NOT NULL, vacated_on DATE NULL, FOREIGN KEY(student_id) REFERENCES students(student_id), FOREIGN KEY(room_id) REFERENCES rooms(room_id), CHECK(vacated_on IS NULL OR vacated_on>=allocated_on));
CREATE TABLE allocation_audit (audit_id INT AUTO_INCREMENT PRIMARY KEY, allocation_id INT NOT NULL, old_vacated DATE, new_vacated DATE, changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);
CREATE TABLE occupancy_summary (snapshot_date DATE PRIMARY KEY, occupied_beds INT DEFAULT 0, total_beds INT DEFAULT 0);
INSERT INTO rooms(room_no,capacity) VALUES('A101',2),('A102',2),('B201',4);
INSERT INTO students(student_number,full_name) VALUES('STU-001','Chanda'),('STU-002','Grace'),('STU-003','Peter');

DROP FUNCTION IF EXISTS fn_room_occupancy;
DELIMITER //
CREATE FUNCTION fn_room_occupancy(p_room INT) RETURNS INT READS SQL DATA DETERMINISTIC
BEGIN DECLARE v_cnt INT; SELECT COUNT(*) INTO v_cnt FROM allocations WHERE room_id=p_room AND vacated_on IS NULL; RETURN v_cnt; END //
DELIMITER ;

DROP PROCEDURE IF EXISTS pr_allocate_room;
DELIMITER //
CREATE PROCEDURE pr_allocate_room(IN p_stu INT, IN p_room INT, IN p_date DATE)
BEGIN DECLARE v_cap INT; DECLARE v_occ INT; DECLARE v_exists INT;
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END; START TRANSACTION;
 SELECT capacity INTO v_cap FROM rooms WHERE room_id=p_room FOR UPDATE;
 IF v_cap IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Unknown room'; END IF;
 SELECT COUNT(*) INTO v_exists FROM allocations WHERE student_id=p_stu AND vacated_on IS NULL;
 IF v_exists>0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Student already allocated'; END IF;
 SET v_occ=fn_room_occupancy(p_room);
 IF v_occ>=v_cap THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Room full'; END IF;
 INSERT INTO allocations(student_id,room_id,allocated_on) VALUES(p_stu,p_room,p_date); COMMIT; END //
DELIMITER ;

DROP TRIGGER IF EXISTS trg_alloc_vacate;
DELIMITER //
CREATE TRIGGER trg_alloc_vacate AFTER UPDATE ON allocations FOR EACH ROW
BEGIN IF NOT (OLD.vacated_on <=> NEW.vacated_on) THEN INSERT INTO allocation_audit(allocation_id,old_vacated,new_vacated) VALUES(NEW.allocation_id,OLD.vacated_on,NEW.vacated_on); END IF; END //
DELIMITER ;

CALL pr_allocate_room(1,1,'2026-11-24');
CALL pr_allocate_room(2,1,'2026-11-24');
CALL pr_allocate_room(3,2,'2026-11-24');

DROP VIEW IF EXISTS v_available_rooms;
CREATE VIEW v_available_rooms AS SELECT r.room_id,r.room_no,r.capacity, r.capacity - (SELECT COUNT(*) FROM allocations a WHERE a.room_id=r.room_id AND a.vacated_on IS NULL) AS free_beds FROM rooms r HAVING free_beds>0;
SELECT * FROM v_available_rooms;

CREATE INDEX idx_alloc_room_active ON allocations(room_id, vacated_on);
EXPLAIN SELECT * FROM allocations WHERE room_id=1 AND vacated_on IS NULL;

DROP PROCEDURE IF EXISTS pr_refresh_occupancy;
DELIMITER //
CREATE PROCEDURE pr_refresh_occupancy(IN p_day DATE)
BEGIN INSERT INTO occupancy_summary(snapshot_date,occupied_beds,total_beds) SELECT p_day, (SELECT COUNT(*) FROM allocations WHERE allocated_on<=p_day AND (vacated_on IS NULL OR vacated_on>p_day)), (SELECT COALESCE(SUM(capacity),0) FROM rooms) ON DUPLICATE KEY UPDATE occupied_beds=VALUES(occupied_beds), total_beds=VALUES(total_beds); END //
DELIMITER ;
SET GLOBAL event_scheduler = ON;
DROP EVENT IF EXISTS ev_occupancy;
CREATE EVENT ev_occupancy ON SCHEDULE EVERY 1 DAY STARTS '2026-11-25 00:30:00' DO CALL pr_refresh_occupancy(CURDATE()-INTERVAL 1 DAY);
