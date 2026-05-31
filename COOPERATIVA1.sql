DROP DATABASE IF EXISTS cooperativa;
CREATE DATABASE cooperativa;
USE cooperativa;

SET SQL_SAFE_UPDATES = 0;

-- ======================
-- SEGURIDAD
-- ======================
CREATE TABLE usuario (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    password VARCHAR(128) NOT NULL,   -- Ajustado para SHA-512
    activo BOOLEAN DEFAULT TRUE,
    intentos_fallidos INT DEFAULT 0,
    bloqueado BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    created_by INT,
    updated_by INT,
    estado BOOLEAN DEFAULT TRUE
);

CREATE TABLE rol (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(50) UNIQUE
);

CREATE TABLE permiso (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(50) UNIQUE
);

CREATE TABLE usuario_rol (
    usuario_id INT,
    rol_id INT,
    PRIMARY KEY(usuario_id, rol_id),
    FOREIGN KEY (usuario_id) REFERENCES usuario(id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY (rol_id) REFERENCES rol(id)
        ON DELETE CASCADE ON UPDATE CASCADE
);

-- ======================
-- CLIENTES
-- ======================
CREATE TABLE socio (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nombres VARCHAR(150),
    apellidos VARCHAR(150),
    dpi VARCHAR(20) UNIQUE,
    fecha_nacimiento DATE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    created_by INT,
    updated_by INT,
    estado BOOLEAN DEFAULT TRUE
);

-- ======================
-- CUENTAS
-- ======================
CREATE TABLE tipo_cuenta (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(50) UNIQUE
);

CREATE TABLE estado_cuenta (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(50) UNIQUE
);

CREATE TABLE cuenta (
    id INT AUTO_INCREMENT PRIMARY KEY,
    socio_id INT,
    numero_cuenta VARCHAR(50) UNIQUE,   -- Ajustado para UUID
    tipo_cuenta_id INT,
    estado_id INT,
    saldo DECIMAL(10,2) CHECK (saldo >= 0),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    created_by INT,
    updated_by INT,
    estado BOOLEAN DEFAULT TRUE,
    FOREIGN KEY (socio_id) REFERENCES socio(id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    FOREIGN KEY (tipo_cuenta_id) REFERENCES tipo_cuenta(id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    FOREIGN KEY (estado_id) REFERENCES estado_cuenta(id)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE INDEX idx_cuenta_socio ON cuenta(socio_id);

-- ======================
-- TRANSACCIONES
-- ======================
CREATE TABLE tipo_transaccion (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(50) UNIQUE
);

CREATE TABLE transaccion (
    id INT AUTO_INCREMENT PRIMARY KEY,
    cuenta_id INT,
    tipo_transaccion_id INT,
    monto DECIMAL(10,2),
    saldo_post DECIMAL(10,2),
    tipo_dc CHAR(1),
    transferencia_id INT NULL,
    created_by INT,
    fecha TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (cuenta_id) REFERENCES cuenta(id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    FOREIGN KEY (tipo_transaccion_id) REFERENCES tipo_transaccion(id)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE INDEX idx_transaccion_cuenta ON transaccion(cuenta_id);

CREATE TABLE transferencia (
    id INT AUTO_INCREMENT PRIMARY KEY,
    cuenta_origen INT,
    cuenta_destino INT,
    monto DECIMAL(10,2),
    fecha TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (cuenta_origen) REFERENCES cuenta(id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    FOREIGN KEY (cuenta_destino) REFERENCES cuenta(id)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

-- ======================
-- TRIGGERS
-- ======================
DELIMITER //

CREATE TRIGGER trg_no_saldo_negativo
BEFORE UPDATE ON cuenta
FOR EACH ROW
BEGIN
    IF NEW.saldo < 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'No se permite saldo negativo';
    END IF;
END;
//

-- ======================
-- PROCEDIMIENTOS
-- ======================

-- CREAR SOCIO
CREATE PROCEDURE sp_crear_socio(
    IN p_nombres VARCHAR(150),
    IN p_apellidos VARCHAR(150),
    IN p_dpi VARCHAR(20),
    IN p_fecha DATE,
    IN p_usuario INT
)
BEGIN
    IF TIMESTAMPDIFF(YEAR, p_fecha, CURDATE()) < 18 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Debe ser mayor de edad';
    END IF;

    INSERT INTO socio(nombres, apellidos, dpi, fecha_nacimiento, created_by)
    VALUES(p_nombres, p_apellidos, p_dpi, p_fecha, p_usuario);
END;
//

-- APERTURA CUENTA
CREATE PROCEDURE sp_apertura_cuenta(
    IN p_socio INT,
    IN p_tipo INT,
    IN p_estado INT,
    IN p_saldo DECIMAL(10,2),
    IN p_usuario INT
)
BEGIN
    IF p_saldo < 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Saldo inválido';
    END IF;

    INSERT INTO cuenta(
        socio_id, numero_cuenta, tipo_cuenta_id,
        estado_id, saldo, created_by
    )
    VALUES(
        p_socio,
        CONCAT('CTA-', SUBSTRING(UUID(),1,8)),   -- UUID recortado
        p_tipo,
        p_estado,
        p_saldo,
        p_usuario
    );
END;
//

-- DEPOSITAR
CREATE PROCEDURE sp_depositar(
    IN p_cuenta INT,
    IN p_monto DECIMAL(10,2),
    IN p_usuario INT
)
BEGIN
    DECLARE saldo_actual DECIMAL(10,2);

    START TRANSACTION;

    SELECT saldo INTO saldo_actual
    FROM cuenta
    WHERE id = p_cuenta
    FOR UPDATE;

    IF saldo_actual IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cuenta no existe';
    END IF;

    UPDATE cuenta
    SET saldo = saldo + p_monto,
        updated_by = p_usuario
    WHERE id = p_cuenta;

    INSERT INTO transaccion
    (cuenta_id, tipo_transaccion_id, monto, saldo_post, tipo_dc, created_by)
    VALUES (p_cuenta, 1, p_monto, saldo_actual + p_monto, 'C', p_usuario);

    COMMIT;
END;
//

-- RETIRAR
CREATE PROCEDURE sp_retirar(
    IN p_cuenta INT,
    IN p_monto DECIMAL(10,2),
    IN p_usuario INT
)
BEGIN
    DECLARE saldo_actual DECIMAL(10,2);

    START TRANSACTION;

    SELECT saldo INTO saldo_actual
    FROM cuenta
    WHERE id = p_cuenta
    FOR UPDATE;

    IF saldo_actual < p_monto THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Fondos insuficientes';
    END IF;

    UPDATE cuenta
    SET saldo = saldo - p_monto
    WHERE id = p_cuenta;

    INSERT INTO transaccion
    VALUES (NULL, p_cuenta, 2, p_monto, saldo_actual - p_monto, 'D', NULL, p_usuario, NOW());

    COMMIT;
END;
//

-- TRANSFERIR
CREATE PROCEDURE sp_transferir(
    IN p_origen INT,
    IN p_destino INT,
    IN p_monto DECIMAL(10,2),
    IN p_usuario INT
)
BEGIN
    DECLARE saldo_origen DECIMAL(10,2);
    DECLARE v_id INT;

    START TRANSACTION;

    SELECT saldo INTO saldo_origen
    FROM cuenta
    WHERE id = p_origen
    FOR UPDATE;

    SELECT saldo FROM cuenta
    WHERE id = p_destino
    FOR UPDATE;

    IF saldo_origen < p_monto THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Fondos insuficientes';
    END IF;

    UPDATE cuenta SET saldo = saldo - p_monto WHERE id = p_origen;
    UPDATE cuenta SET saldo = saldo + p_monto WHERE id = p_destino;

    INSERT INTO transferencia(cuenta_origen, cuenta_destino, monto)
    VALUES(p_origen, p_destino, p_monto);

    SET v_id = LAST_INSERT_ID();

    INSERT INTO transaccion
    VALUES (NULL, p_origen, 2, p_monto, saldo_origen - p_monto, 'D', v_id, p_usuario, NOW());

    INSERT INTO transaccion
    VALUES (NULL, p_destino, 1, p_monto,
        (SELECT saldo FROM cuenta WHERE id = p_destino),
        'C', v_id, p_usuario, NOW());

    COMMIT;
END;
//

DELIMITER ;


-- ======================
-- TABLA HISTÓRICA PARTICIONADA
-- ======================

CREATE TABLE transaccion_hist (
    id INT AUTO_INCREMENT,
    cuenta_id INT,
    tipo_transaccion_id INT,
    monto DECIMAL(10,2),
    saldo_post DECIMAL(10,2),
    tipo_dc CHAR(1),
    transferencia_id INT NULL,
    created_by INT,
    fecha TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    anio INT,
    PRIMARY KEY (id, anio)   -- Clave primaria compuesta para permitir particionamiento
)
PARTITION BY RANGE (anio) (
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION p2025 VALUES LESS THAN (2026),
    PARTITION p2026 VALUES LESS THAN (2027),
    PARTITION pmax VALUES LESS THAN MAXVALUE
);

-- ======================
-- TRIGGER PARA LLENAR EL AÑO
-- ======================
DELIMITER //
CREATE TRIGGER trg_set_anio_hist
BEFORE INSERT ON transaccion_hist
FOR EACH ROW
BEGIN
    SET NEW.anio = YEAR(NEW.fecha);
END;
//
DELIMITER ;

-- ======================
-- TRIGGER PARA COPIAR DATOS DESDE TRANSACCION
-- ======================
DELIMITER //
CREATE TRIGGER trg_copy_to_hist
AFTER INSERT ON transaccion
FOR EACH ROW
BEGIN
    INSERT INTO transaccion_hist (
        cuenta_id, tipo_transaccion_id, monto, saldo_post,
        tipo_dc, transferencia_id, created_by, fecha, anio
    )
    VALUES (
        NEW.cuenta_id, NEW.tipo_transaccion_id, NEW.monto,
        NEW.saldo_post, NEW.tipo_dc, NEW.transferencia_id,
        NEW.created_by, NEW.fecha, YEAR(NEW.fecha)
    );
END;
//
DELIMITER ;