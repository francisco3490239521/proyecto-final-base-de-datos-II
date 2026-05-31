USE cooperativa;
-- SUBIR DATOS A LA BASE COOPERATIVA 


USE cooperativa;

-- ======================
-- DATOS DE SEGURIDAD
-- ======================
INSERT INTO rol (nombre) VALUES ('Administrador'), ('Cajero'), ('Socio');
INSERT INTO permiso (nombre) VALUES ('CrearCuenta'), ('Depositar'), ('Retirar'), ('Transferir');

-- Usuario con contraseña encriptada
INSERT INTO usuario (username, password, created_by)
VALUES ('karina', SHA2('MiPasswordSeguro', 512), 1);

-- Asignar rol al usuario
INSERT INTO usuario_rol (usuario_id, rol_id) VALUES (1, 1);

-- ======================
-- DATOS DE CLIENTES
-- ======================
CALL sp_crear_socio('Juan', 'Pérez', '9876543210101', '1990-05-12', 1);
CALL sp_crear_socio('María', 'López', '1234567890102', '1992-07-20', 1);

-- ======================
-- DATOS DE CUENTAS
-- ======================
INSERT INTO tipo_cuenta (nombre) VALUES ('Ahorro'), ('Corriente');
INSERT INTO estado_cuenta (nombre) VALUES ('Activa'), ('Inactiva');

-- Apertura de cuentas
CALL sp_apertura_cuenta(1, 1, 1, 1000.00, 1); -- Cuenta de Juan
CALL sp_apertura_cuenta(2, 2, 1, 500.00, 1);  -- Cuenta de María

-- ======================
-- TIPOS DE TRANSACCIÓN
-- ======================
INSERT INTO tipo_transaccion (nombre) VALUES ('Depósito'), ('Retiro'), ('Transferencia');

-- ======================
-- PRUEBAS DE OPERACIONES
-- ======================
-- Depositar en cuenta de Juan
CALL sp_depositar(1, 200.00, 1);

-- Retirar de cuenta de María
CALL sp_retirar(2, 100.00, 1);

-- Transferir de Juan a María
CALL sp_transferir(1, 2, 150.00, 1);

-- ======================
-- VERIFICACIÓN
-- ======================
SELECT * FROM cuenta;
SELECT * FROM usuario;
SELECT * FROM transaccion;
SELECT * FROM transferencia;
SELECT * FROM transaccion_hist;