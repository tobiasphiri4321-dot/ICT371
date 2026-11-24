CREATE DATABASE IF NOT EXISTS pharmacy_db;
USE pharmacy_db;
DROP TABLE IF EXISTS daily_sales;
DROP TABLE IF EXISTS stock_audit;
DROP TABLE IF EXISTS sales;
DROP TABLE IF EXISTS medicines;

CREATE TABLE medicines (
    medicine_id INT AUTO_INCREMENT PRIMARY KEY,
    medicine_name VARCHAR(100) NOT NULL UNIQUE,
    unit_price DECIMAL(10,2) NOT NULL CHECK (unit_price > 0),
    stock_qty INT NOT NULL DEFAULT 0 CHECK (stock_qty >= 0)
);
CREATE TABLE sales (
    sale_id INT AUTO_INCREMENT PRIMARY KEY,
    medicine_id INT NOT NULL,
    quantity INT NOT NULL CHECK (quantity > 0),
    unit_price DECIMAL(10,2) NOT NULL CHECK (unit_price > 0),
    sold_on DATE NOT NULL,
    FOREIGN KEY (medicine_id) REFERENCES medicines(medicine_id)
);
CREATE TABLE stock_audit (
    audit_id INT AUTO_INCREMENT PRIMARY KEY,
    medicine_id INT NOT NULL,
    old_qty INT NOT NULL,
    new_qty INT NOT NULL,
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (medicine_id) REFERENCES medicines(medicine_id)
);
CREATE TABLE daily_sales (
    sales_date DATE PRIMARY KEY,
    total_qty INT NOT NULL DEFAULT 0,
    total_amount DECIMAL(12,2) NOT NULL DEFAULT 0.00
);
INSERT INTO medicines (medicine_name, unit_price, stock_qty) VALUES
('Paracetamol 500mg', 5.00, 100),
('Amoxicillin 500mg', 15.50, 50),
('Vitamin C 1000mg', 8.00, 8);

-- (b) FUNCTION
DROP FUNCTION IF EXISTS fn_sale_value;
DELIMITER //
CREATE FUNCTION fn_sale_value(p_medicine_id INT, p_quantity INT)
RETURNS DECIMAL(12,2) READS SQL DATA DETERMINISTIC
BEGIN
    DECLARE v_price DECIMAL(10,2);
    IF p_quantity IS NULL OR p_quantity <= 0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Quantity must be positive'; END IF;
    SELECT unit_price INTO v_price FROM medicines WHERE medicine_id = p_medicine_id;
    IF v_price IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Unknown medicine'; END IF;
    RETURN v_price * p_quantity;
END //
DELIMITER ;

-- (c) PROCEDURE
DROP PROCEDURE IF EXISTS pr_record_sale;
DELIMITER //
CREATE PROCEDURE pr_record_sale(IN p_medicine_id INT, IN p_quantity INT, IN p_sold_on DATE)
BEGIN
    DECLARE v_stock INT; DECLARE v_price DECIMAL(10,2);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    START TRANSACTION;
    SELECT stock_qty, unit_price INTO v_stock, v_price FROM medicines WHERE medicine_id=p_medicine_id FOR UPDATE;
    IF v_price IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Unknown medicine'; END IF;
    IF p_quantity IS NULL OR p_quantity <=0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Quantity must be positive'; END IF;
    IF v_stock < p_quantity THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Insufficient stock'; END IF;
    INSERT INTO sales (medicine_id, quantity, unit_price, sold_on) VALUES (p_medicine_id, p_quantity, v_price, p_sold_on);
    UPDATE medicines SET stock_qty = stock_qty - p_quantity WHERE medicine_id = p_medicine_id;
    COMMIT;
END //
DELIMITER ;

-- (d) TRIGGER
DROP TRIGGER IF EXISTS trg_medicines_stock_audit;
DELIMITER //
CREATE TRIGGER trg_medicines_stock_audit AFTER UPDATE ON medicines FOR EACH ROW
BEGIN
    IF OLD.stock_qty <> NEW.stock_qty THEN
        INSERT INTO stock_audit (medicine_id, old_qty, new_qty, changed_at) VALUES (NEW.medicine_id, OLD.stock_qty, NEW.stock_qty, NOW());
    END IF;
END //
DELIMITER ;

-- Seed 6 sales via procedure
CALL pr_record_sale(1, 10, '2026-11-24');
CALL pr_record_sale(1, 5, '2026-11-24');
CALL pr_record_sale(2, 2, '2026-11-24');
CALL pr_record_sale(2, 3, '2026-11-24');
CALL pr_record_sale(3, 2, '2026-11-24');
CALL pr_record_sale(1, 4, '2026-11-23');

-- (e) VIEW
DROP VIEW IF EXISTS v_low_stock;
CREATE VIEW v_low_stock AS SELECT medicine_id, medicine_name, unit_price, stock_qty AS remaining_stock FROM medicines WHERE stock_qty < 10;
SELECT * FROM v_low_stock;

-- (f) INDEX
CREATE INDEX idx_sales_medicine_date ON sales (medicine_id, sold_on);
EXPLAIN SELECT sale_id, quantity, unit_price, sold_on FROM sales WHERE medicine_id=1 AND sold_on BETWEEN '2026-11-01' AND '2026-11-24';

-- (g) SCHEDULED JOB
DROP PROCEDURE IF EXISTS pr_refresh_sales;
DELIMITER //
CREATE PROCEDURE pr_refresh_sales(IN p_day DATE)
BEGIN
    INSERT INTO daily_sales (sales_date, total_qty, total_amount)
    SELECT p_day, COALESCE(SUM(quantity),0), COALESCE(SUM(quantity*unit_price),0)
    FROM sales WHERE sold_on=p_day
    ON DUPLICATE KEY UPDATE total_qty=VALUES(total_qty), total_amount=VALUES(total_amount);
END //
DELIMITER ;
SET GLOBAL event_scheduler = ON;
DROP EVENT IF EXISTS ev_refresh_daily_sales;
CREATE EVENT ev_refresh_daily_sales ON SCHEDULE EVERY 1 DAY STARTS '2026-11-25 00:15:00' DO CALL pr_refresh_sales(CURDATE() - INTERVAL 1 DAY);
CALL pr_refresh_sales('2026-11-24');
