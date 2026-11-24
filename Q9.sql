CREATE DATABASE IF NOT EXISTS coop_db;
USE coop_db;
DROP TABLE IF EXISTS daily_deliveries;
DROP TABLE IF EXISTS delivery_audit;
DROP TABLE IF EXISTS deliveries;
DROP TABLE IF EXISTS farmers;
CREATE TABLE farmers (farmer_id INT AUTO_INCREMENT PRIMARY KEY, member_no VARCHAR(20) UNIQUE NOT NULL, full_name VARCHAR(100) NOT NULL);
CREATE TABLE deliveries (delivery_id INT AUTO_INCREMENT PRIMARY KEY, farmer_id INT NOT NULL, bags INT NOT NULL CHECK(bags>0), price_per_bag DECIMAL(10,2) NOT NULL CHECK(price_per_bag>0), delivered_on DATE NOT NULL, FOREIGN KEY(farmer_id) REFERENCES farmers(farmer_id));
CREATE TABLE delivery_audit (audit_id INT AUTO_INCREMENT PRIMARY KEY, delivery_id INT NOT NULL, old_bags INT, new_bags INT, changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);
CREATE TABLE daily_deliveries (delivery_date DATE PRIMARY KEY, total_bags INT DEFAULT 0, total_amount DECIMAL(12,2) DEFAULT 0);
INSERT INTO farmers(member_no,full_name) VALUES('F-001','Chanda'),('F-002','Grace'),('F-003','Peter');

DROP FUNCTION IF EXISTS fn_delivery_value;
DELIMITER //
CREATE FUNCTION fn_delivery_value(p_bags INT, p_price DECIMAL(10,2)) RETURNS DECIMAL(12,2) DETERMINISTIC
BEGIN IF p_bags<=0 OR p_price<=0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Invalid bags or price'; END IF; RETURN p_bags*p_price; END //
DELIMITER ;

DROP PROCEDURE IF EXISTS pr_record_delivery;
DELIMITER //
CREATE PROCEDURE pr_record_delivery(IN p_farmer INT, IN p_bags INT, IN p_price DECIMAL(10,2), IN p_date DATE)
BEGIN DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END; START TRANSACTION;
 IF p_bags IS NULL OR p_bags<=0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Bags must be positive'; END IF;
 INSERT INTO deliveries(farmer_id,bags,price_per_bag,delivered_on) VALUES(p_farmer,p_bags,p_price,p_date); COMMIT; END //
DELIMITER ;

DROP TRIGGER IF EXISTS trg_delivery_audit;
DELIMITER //
CREATE TRIGGER trg_delivery_audit AFTER UPDATE ON deliveries FOR EACH ROW
BEGIN IF OLD.bags <> NEW.bags THEN INSERT INTO delivery_audit(delivery_id,old_bags,new_bags) VALUES(NEW.delivery_id,OLD.bags,NEW.bags); END IF; END //
DELIMITER ;

CALL pr_record_delivery(1,10,250,'2026-11-24');
CALL pr_record_delivery(1,15,250,'2026-11-24');
CALL pr_record_delivery(2,20,250,'2026-11-24');
CALL pr_record_delivery(2,5,260,'2026-11-23');
CALL pr_record_delivery(3,12,250,'2026-11-24');
CALL pr_record_delivery(3,8,250,'2026-11-23');

DROP VIEW IF EXISTS v_farmer_totals;
CREATE VIEW v_farmer_totals AS SELECT f.member_no,f.full_name,COALESCE(SUM(d.bags),0) AS total_bags, COALESCE(SUM(d.bags*d.price_per_bag),0) AS total_value FROM farmers f LEFT JOIN deliveries d ON d.farmer_id=f.farmer_id GROUP BY f.farmer_id,f.member_no,f.full_name HAVING total_bags>0;

CREATE INDEX idx_deliveries_farmer_date ON deliveries(farmer_id, delivered_on);
EXPLAIN SELECT * FROM deliveries WHERE farmer_id=1 AND delivered_on BETWEEN '2026-11-01' AND '2026-11-30';

DROP PROCEDURE IF EXISTS pr_refresh_deliveries;
DELIMITER //
CREATE PROCEDURE pr_refresh_deliveries(IN p_day DATE)
BEGIN INSERT INTO daily_deliveries(delivery_date,total_bags,total_amount) SELECT p_day, COALESCE(SUM(bags),0), COALESCE(SUM(bags*price_per_bag),0) FROM deliveries WHERE delivered_on=p_day ON DUPLICATE KEY UPDATE total_bags=VALUES(total_bags), total_amount=VALUES(total_amount); END //
DELIMITER ;
SET GLOBAL event_scheduler = ON;
DROP EVENT IF EXISTS ev_deliveries;
CREATE EVENT ev_deliveries ON SCHEDULE EVERY 1 DAY STARTS '2026-11-25 00:15:00' DO CALL pr_refresh_deliveries(CURDATE()-INTERVAL 1 DAY);
CALL pr_refresh_deliveries('2026-11-24');
