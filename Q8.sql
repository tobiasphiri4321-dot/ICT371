CREATE DATABASE IF NOT EXISTS fleet_db;
USE fleet_db;
DROP TABLE IF EXISTS monthly_maintenance;
DROP TABLE IF EXISTS maintenance_audit;
DROP TABLE IF EXISTS maintenance;
DROP TABLE IF EXISTS vehicles;
CREATE TABLE vehicles (vehicle_id INT AUTO_INCREMENT PRIMARY KEY, reg_no VARCHAR(20) UNIQUE NOT NULL, model VARCHAR(50) NOT NULL, last_service_km INT DEFAULT 0);
CREATE TABLE maintenance (maintenance_id INT AUTO_INCREMENT PRIMARY KEY, vehicle_id INT NOT NULL, service_km INT NOT NULL, service_date DATE NOT NULL, cost DECIMAL(10,2) NOT NULL CHECK(cost>=0), FOREIGN KEY(vehicle_id) REFERENCES vehicles(vehicle_id));
CREATE TABLE maintenance_audit (audit_id INT AUTO_INCREMENT PRIMARY KEY, maintenance_id INT NOT NULL, old_cost DECIMAL(10,2), new_cost DECIMAL(10,2), changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);
CREATE TABLE monthly_maintenance (service_month DATE PRIMARY KEY, service_count INT DEFAULT 0, total_cost DECIMAL(12,2) DEFAULT 0);
INSERT INTO vehicles(reg_no,model,last_service_km) VALUES('ABC-123','Toyota Hiace',50000),('DEF-456','Nissan Caravan',80000),('GHI-789','Mitsubishi Rosa',120000);

DROP FUNCTION IF EXISTS fn_next_service_km;
DELIMITER //
CREATE FUNCTION fn_next_service_km(p_vehicle INT) RETURNS INT READS SQL DATA DETERMINISTIC
BEGIN DECLARE v_last INT; SELECT COALESCE(MAX(service_km),0) INTO v_last FROM maintenance WHERE vehicle_id=p_vehicle; IF v_last=0 THEN SELECT last_service_km INTO v_last FROM vehicles WHERE vehicle_id=p_vehicle; END IF; RETURN v_last+10000; END //
DELIMITER ;

DROP PROCEDURE IF EXISTS pr_log_maintenance;
DELIMITER //
CREATE PROCEDURE pr_log_maintenance(IN p_vehicle INT, IN p_km INT, IN p_date DATE, IN p_cost DECIMAL(10,2))
BEGIN DECLARE v_last INT;
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END; START TRANSACTION;
 SELECT COALESCE(MAX(service_km),0) INTO v_last FROM maintenance WHERE vehicle_id=p_vehicle;
 IF p_km <= v_last THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Service KM must increase'; END IF;
 INSERT INTO maintenance(vehicle_id,service_km,service_date,cost) VALUES(p_vehicle,p_km,p_date,p_cost);
 UPDATE vehicles SET last_service_km=p_km WHERE vehicle_id=p_vehicle; COMMIT; END //
DELIMITER ;

DROP TRIGGER IF EXISTS trg_maint_audit;
DELIMITER //
CREATE TRIGGER trg_maint_audit AFTER UPDATE ON maintenance FOR EACH ROW
BEGIN IF OLD.cost <> NEW.cost THEN INSERT INTO maintenance_audit(maintenance_id,old_cost,new_cost) VALUES(NEW.maintenance_id,OLD.cost,NEW.cost); END IF; END //
DELIMITER ;

CALL pr_log_maintenance(1,60000,'2026-11-10',1500);
CALL pr_log_maintenance(1,70000,'2026-11-20',1200);
CALL pr_log_maintenance(2,90000,'2026-11-12',2000);
CALL pr_log_maintenance(2,100000,'2026-11-22',1800);
CALL pr_log_maintenance(3,130000,'2026-11-15',2500);
CALL pr_log_maintenance(3,140000,'2026-11-24',2200);

DROP VIEW IF EXISTS v_due_maintenance;
CREATE VIEW v_due_maintenance AS SELECT v.reg_no, v.model, fn_next_service_km(v.vehicle_id) AS next_service_km FROM vehicles v;

CREATE INDEX idx_maint_vehicle_date ON maintenance(vehicle_id, service_date);
EXPLAIN SELECT * FROM maintenance WHERE vehicle_id=1 AND service_date BETWEEN '2026-01-01' AND '2026-11-30';

DROP PROCEDURE IF EXISTS pr_refresh_maint;
DELIMITER //
CREATE PROCEDURE pr_refresh_maint(IN p_month DATE)
BEGIN INSERT INTO monthly_maintenance(service_month,service_count,total_cost) SELECT p_month,COUNT(*),COALESCE(SUM(cost),0) FROM maintenance WHERE DATE_FORMAT(service_date,'%Y-%m-01')=p_month ON DUPLICATE KEY UPDATE service_count=VALUES(service_count), total_cost=VALUES(total_cost); END //
DELIMITER ;
SET GLOBAL event_scheduler = ON;
DROP EVENT IF EXISTS ev_maint;
CREATE EVENT ev_maint ON SCHEDULE EVERY 1 MONTH STARTS '2026-12-01 00:15:00' DO CALL pr_refresh_maint(DATE_FORMAT(CURDATE()-INTERVAL 1 MONTH,'%Y-%m-01'));
