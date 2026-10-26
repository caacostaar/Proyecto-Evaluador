-- ============================================================
-- ProyectoPro - Evaluador Financiero de Proyectos
-- Base de Datos SaaS Multi-Tenant
-- Arquitectura: Schema compartido (saas_master) + Schema por empresa
-- ============================================================

-- ============================================================
-- SCHEMA MAESTRO (saas_master)
-- Gestión de empresas, usuarios y suscripciones
-- ============================================================

CREATE SCHEMA IF NOT EXISTS saas_master DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE saas_master;

-- ------------------------------------------------------------
-- Planes de suscripción
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS planes (
    id             CHAR(36)        NOT NULL DEFAULT (UUID()),
    nombre         VARCHAR(100)    NOT NULL,
    codigo         VARCHAR(50)     NOT NULL UNIQUE,
    descripcion    TEXT,
    precio_mensual DECIMAL(12,2)   NOT NULL DEFAULT 0.00,
    precio_anual   DECIMAL(12,2)   NOT NULL DEFAULT 0.00,
    max_proyectos  INT             NOT NULL DEFAULT 5,
    max_usuarios   INT             NOT NULL DEFAULT 3,
    max_costos     INT             NOT NULL DEFAULT 100,
    activo         TINYINT(1)      NOT NULL DEFAULT 1,
    creado_en      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    INDEX idx_codigo (codigo)
) ENGINE=InnoDB;

INSERT INTO planes (nombre, codigo, descripcion, precio_mensual, precio_anual, max_proyectos, max_usuarios, max_costos) VALUES
('Básico',        'basico',        'Ideal para freelancers y pequeños consultores',        49900.00,    499000.00,   3,   2,   50),
('Profesional',   'profesional',   'Para empresas consultoras medianas',                  149900.00,  1499000.00,  10,   5,  200),
('Empresarial',   'empresarial',   'Para grandes firmas de consultoría',                  399900.00,  3999000.00,  50,  20, 1000),
('Enterprise',    'enterprise',    'Ilimitado con soporte dedicado',                      999900.00,  9999000.00, -1,  -1,   -1);

-- ------------------------------------------------------------
-- Empresas (tenants)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS empresas (
    id              CHAR(36)        NOT NULL DEFAULT (UUID()),
    nit             VARCHAR(30)     NOT NULL UNIQUE,
    razon_social    VARCHAR(200)    NOT NULL,
    email_contacto  VARCHAR(150)    NOT NULL,
    telefono        VARCHAR(30),
    ciudad          VARCHAR(100),
    pais            VARCHAR(100)    NOT NULL DEFAULT 'Colombia',
    plan_id         CHAR(36)        NOT NULL,
    schema_name     VARCHAR(64)     NOT NULL UNIQUE COMMENT 'Schema MySQL para esta empresa: co_<nit_sin_puntos>',
    estado          ENUM('activo','suspendido','cancelado','trial') NOT NULL DEFAULT 'trial',
    trial_hasta     DATE,
    creado_en       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    actualizado_en  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    FOREIGN KEY fk_empresa_plan (plan_id) REFERENCES planes(id),
    INDEX idx_nit (nit),
    INDEX idx_estado (estado)
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- Perfiles de acceso
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS perfiles (
    id          CHAR(36)    NOT NULL DEFAULT (UUID()),
    codigo      VARCHAR(50) NOT NULL UNIQUE,
    nombre      VARCHAR(100) NOT NULL,
    descripcion TEXT,
    nivel       INT         NOT NULL DEFAULT 1 COMMENT '1=menor acceso, 4=mayor acceso',
    PRIMARY KEY (id),
    INDEX idx_codigo (codigo)
) ENGINE=InnoDB;

INSERT INTO perfiles (codigo, nombre, descripcion, nivel) VALUES
('usuario_final', 'Usuario Final',   'Consulta proyectos y genera reportes. No puede modificar parámetros restringidos.',          1),
('preventa',      'Preventa',        'Crea y modifica proyectos, ajusta factores de sensibilidad para cotizaciones.',               2),
('administrador', 'Administrador',   'Gestión completa de proyectos, usuarios del tenant y todos los parámetros.',                  3),
('super_admin',   'Super Admin',     'Acceso total a la plataforma, gestión de tenants, planes y configuración global.',            4);

-- ------------------------------------------------------------
-- Usuarios
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS usuarios (
    id              CHAR(36)        NOT NULL DEFAULT (UUID()),
    empresa_id      CHAR(36)        NOT NULL,
    perfil_id       CHAR(36)        NOT NULL,
    nombre          VARCHAR(200)    NOT NULL,
    email           VARCHAR(150)    NOT NULL,
    password_hash   VARCHAR(255)    NOT NULL,
    activo          TINYINT(1)      NOT NULL DEFAULT 1,
    ultimo_acceso   DATETIME,
    creado_en       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    actualizado_en  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_email_empresa (email, empresa_id),
    FOREIGN KEY fk_usuario_empresa (empresa_id) REFERENCES empresas(id) ON DELETE CASCADE,
    FOREIGN KEY fk_usuario_perfil  (perfil_id)  REFERENCES perfiles(id),
    INDEX idx_email (email),
    INDEX idx_empresa (empresa_id)
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- Suscripciones y facturación
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS suscripciones (
    id              CHAR(36)        NOT NULL DEFAULT (UUID()),
    empresa_id      CHAR(36)        NOT NULL,
    plan_id         CHAR(36)        NOT NULL,
    periodicidad    ENUM('mensual','anual') NOT NULL DEFAULT 'mensual',
    fecha_inicio    DATE            NOT NULL,
    fecha_fin       DATE,
    monto           DECIMAL(12,2)   NOT NULL,
    moneda          VARCHAR(3)      NOT NULL DEFAULT 'COP',
    estado          ENUM('activa','vencida','cancelada','pendiente_pago') NOT NULL DEFAULT 'activa',
    payu_order_id   VARCHAR(100)    COMMENT 'ID de orden en PayU Colombia',
    creado_en       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    FOREIGN KEY fk_suscripcion_empresa (empresa_id) REFERENCES empresas(id),
    FOREIGN KEY fk_suscripcion_plan    (plan_id)    REFERENCES planes(id),
    INDEX idx_empresa_estado (empresa_id, estado)
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- Pagos (PayU Colombia)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pagos (
    id                  CHAR(36)        NOT NULL DEFAULT (UUID()),
    suscripcion_id      CHAR(36)        NOT NULL,
    empresa_id          CHAR(36)        NOT NULL,
    monto               DECIMAL(12,2)   NOT NULL,
    moneda              VARCHAR(3)      NOT NULL DEFAULT 'COP',
    referencia_payu     VARCHAR(100)    COMMENT 'Reference code PayU',
    transaction_id      VARCHAR(100)    COMMENT 'Transaction ID PayU',
    estado_payu         VARCHAR(50)     COMMENT 'APPROVED, DECLINED, ERROR, PENDING',
    respuesta_completa  JSON            COMMENT 'Respuesta completa de PayU',
    fecha_pago          DATETIME,
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    FOREIGN KEY fk_pago_suscripcion (suscripcion_id) REFERENCES suscripciones(id),
    INDEX idx_empresa_pago (empresa_id),
    INDEX idx_referencia (referencia_payu)
) ENGINE=InnoDB;


-- ============================================================
-- TEMPLATE SCHEMA POR EMPRESA
-- Se crea uno por cada tenant: co_<nit_sin_puntos>
-- Ejemplo: co_9001234567
-- ============================================================

-- El siguiente bloque es un TEMPLATE. En producción se ejecuta
-- dinámicamente al crear un nuevo tenant, reemplazando
-- `empresa_schema` por el schema_name real.

CREATE SCHEMA IF NOT EXISTS empresa_schema DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE empresa_schema;

-- ------------------------------------------------------------
-- Proyectos
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS proyectos (
    id                  CHAR(36)        NOT NULL DEFAULT (UUID()),
    nit_empresa         VARCHAR(30)     NOT NULL COMMENT 'NIT del cliente del proyecto',
    nombre_empresa      VARCHAR(200)    NOT NULL,
    nombre_proyecto     VARCHAR(200)    NOT NULL,
    id_proyecto_usuario VARCHAR(50)     COMMENT 'ID asignado por el usuario',
    fecha_inicio        DATE            NOT NULL,
    tiempo_contrato     INT             NOT NULL DEFAULT 12 COMMENT 'Duración en meses',
    plazo_pago          INT             NOT NULL DEFAULT 30  COMMENT 'Días para pago',
    tipo_moneda         VARCHAR(3)      NOT NULL DEFAULT 'COP',
    estado              ENUM('borrador','activo','cerrado','archivado') NOT NULL DEFAULT 'borrador',
    creado_por          CHAR(36)        COMMENT 'usuario_id del saas_master',
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    actualizado_en      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    INDEX idx_nit_empresa    (nit_empresa),
    INDEX idx_nombre_proyecto (nombre_proyecto),
    INDEX idx_estado         (estado)
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- Costos del proyecto (13 categorías)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS costos (
    id              CHAR(36)        NOT NULL DEFAULT (UUID()),
    proyecto_id     CHAR(36)        NOT NULL,
    costo_id_usuario VARCHAR(50)    NOT NULL COMMENT 'ID definido por el usuario, ej: C-001',
    familia         VARCHAR(100)    NOT NULL COMMENT 'Agrupación de negocio, ej: Hardware, Servicios',
    clase           VARCHAR(100)    NOT NULL DEFAULT '' COMMENT 'Sub-agrupación, ej: Servidores',
    descripcion     TEXT            NOT NULL,
    categoria       ENUM(
        'ingreso',
        'ingreso_instalacion',
        'opex_efectivo',
        'opex_no_efectivo',
        'gasto_instalacion',
        'costo_indirecto',
        'costo_impositivo',
        'depreciacion',
        'gasto_financiero',
        'capex_instalacion',
        'capex_efectivo',
        'capex_no_efectivo',
        'salvamento'
    ) NOT NULL COMMENT 'Posición en el estado financiero',
    valor           DECIMAL(18,2)   NOT NULL DEFAULT 0.00 COMMENT 'Valor mensual o total según categoría',
    fecha_inicio    DATE            NOT NULL COMMENT 'Mes de inicio del costo',
    duracion        INT             NOT NULL DEFAULT 1    COMMENT 'Duración en meses; 1=un solo periodo para CAPEX',
    moneda          VARCHAR(3)      NOT NULL DEFAULT 'COP',
    notas           TEXT,
    activo          TINYINT(1)      NOT NULL DEFAULT 1,
    creado_en       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    actualizado_en  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    FOREIGN KEY fk_costo_proyecto (proyecto_id) REFERENCES proyectos(id) ON DELETE CASCADE,
    INDEX idx_proyecto_categoria (proyecto_id, categoria),
    INDEX idx_proyecto_familia   (proyecto_id, familia)
) ENGINE=InnoDB;

COMMENT ON TABLE costos IS
'Mapeo de categorías al estado financiero:
  INGRESOS:          ingreso, ingreso_instalacion
  EGRESOS (EBITDA):  opex_efectivo, opex_no_efectivo, gasto_instalacion, costo_indirecto, costo_impositivo
  DEPRECIACION:      depreciacion
  GASTOS FINANC.:    gasto_financiero
  CAPEX:             capex_instalacion, capex_efectivo, capex_no_efectivo
  SALVAMENTO:        salvamento
  CALCULADO AUTO:    Ingreso Calculado = (CAPEX+OPEX) / n_meses * FM * FS';

-- ------------------------------------------------------------
-- Indicadores macroeconómicos (por mes y proyecto)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS indicadores_macroeconomicos (
    id              CHAR(36)        NOT NULL DEFAULT (UUID()),
    proyecto_id     CHAR(36)        NOT NULL,
    periodo         DATE            NOT NULL COMMENT 'Primer día del mes',
    trm             DECIMAL(10,4)   COMMENT 'TRM COP/USD',
    ipc             DECIMAL(8,4)    COMMENT 'IPC mensual %',
    inflacion       DECIMAL(8,4)    COMMENT 'Inflación mensual %',
    dtf             DECIMAL(8,4)    COMMENT 'DTF E.A. %',
    ibr             DECIMAL(8,4)    COMMENT 'IBR nominal mes vencido %',
    devaluacion     DECIMAL(8,4)    COMMENT 'Devaluación mensual %',
    creado_en       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    actualizado_en  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_proyecto_periodo (proyecto_id, periodo),
    FOREIGN KEY fk_macro_proyecto (proyecto_id) REFERENCES proyectos(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- WACC mensual (COP y USD)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS wacc_mensual (
    id              CHAR(36)        NOT NULL DEFAULT (UUID()),
    proyecto_id     CHAR(36)        NOT NULL,
    periodo         DATE            NOT NULL,
    wacc_cop        DECIMAL(8,4)    COMMENT 'WACC en COP %',
    wacc_usd        DECIMAL(8,4)    COMMENT 'WACC en USD %',
    creado_en       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    actualizado_en  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_proyecto_periodo (proyecto_id, periodo),
    FOREIGN KEY fk_wacc_proyecto (proyecto_id) REFERENCES proyectos(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- Parámetros impositivos (por mes y proyecto)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS parametros_impositivos (
    id              CHAR(36)        NOT NULL DEFAULT (UUID()),
    proyecto_id     CHAR(36)        NOT NULL,
    periodo         DATE            NOT NULL,
    renta           DECIMAL(8,4)    COMMENT 'Impuesto de renta %',
    iva             DECIMAL(8,4)    COMMENT 'IVA %',
    retencion       DECIMAL(8,4)    COMMENT 'Retención en la fuente %',
    ica             DECIMAL(8,4)    COMMENT 'Impuesto de industria y comercio %',
    gmf             DECIMAL(8,4)    COMMENT 'Gravamen movimientos financieros 4x1000',
    creado_en       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    actualizado_en  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_proyecto_periodo (proyecto_id, periodo),
    FOREIGN KEY fk_impositivos_proyecto (proyecto_id) REFERENCES proyectos(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- Parámetros de negocio (por mes y proyecto)
-- Factor Multiplicador y Factor de Sensibilidad son clave
-- para el cálculo automático del Ingreso
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS parametricas_negocio (
    id                      CHAR(36)        NOT NULL DEFAULT (UUID()),
    proyecto_id             CHAR(36)        NOT NULL,
    periodo                 DATE            NOT NULL,
    margen_objetivo         DECIMAL(8,4)    COMMENT 'Margen objetivo del proyecto %',
    crecimiento_ingresos    DECIMAL(8,4)    COMMENT 'Crecimiento esperado de ingresos mensual %',
    vida_util_activos       INT             COMMENT 'Vida útil promedio de activos en meses',
    tasa_descuento          DECIMAL(8,4)    COMMENT 'Tasa de descuento para VPN %',
    factor_multiplicador    DECIMAL(8,4)    NOT NULL DEFAULT 1.3000
        COMMENT 'FM: Markup sobre costos base. Default 1.30 = 30% por encima del costo',
    factor_sensibilidad     DECIMAL(8,4)    NOT NULL DEFAULT 1.0000
        COMMENT 'FS: Ajuste de sensibilidad. Solo modificable por Administrador/Super Admin/Preventa',
    creado_en               DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    actualizado_en          DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_proyecto_periodo (proyecto_id, periodo),
    FOREIGN KEY fk_negocio_proyecto (proyecto_id) REFERENCES proyectos(id) ON DELETE CASCADE
) ENGINE=InnoDB;

COMMENT ON TABLE parametricas_negocio IS
'Fórmula Ingreso Calculado mensual:
  Ingreso_mes_i = ((CAPEX_total + OPEX_acumulado) / n_meses) * factor_multiplicador[i] * factor_sensibilidad[i]

  Restricción de acceso a factor_sensibilidad:
  - Solo pueden modificar: administrador, super_admin, preventa
  - usuario_final: solo lectura';

-- ------------------------------------------------------------
-- Auditoría de cambios sensibles
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS auditoria (
    id              CHAR(36)        NOT NULL DEFAULT (UUID()),
    usuario_id      CHAR(36)        NOT NULL COMMENT 'ID del usuario que realizó la acción',
    tabla           VARCHAR(100)    NOT NULL,
    registro_id     CHAR(36)        NOT NULL,
    accion          ENUM('INSERT','UPDATE','DELETE') NOT NULL,
    datos_anterior  JSON,
    datos_nuevo     JSON,
    ip_address      VARCHAR(45),
    user_agent      TEXT,
    creado_en       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    INDEX idx_usuario   (usuario_id),
    INDEX idx_tabla     (tabla),
    INDEX idx_creado_en (creado_en)
) ENGINE=InnoDB;


-- ============================================================
-- VISTAS ÚTILES
-- ============================================================

-- Vista: resumen de costos por proyecto y categoría
CREATE OR REPLACE VIEW v_costos_resumen AS
SELECT
    p.id            AS proyecto_id,
    p.nombre_proyecto,
    c.categoria,
    COUNT(*)        AS num_items,
    SUM(c.valor)    AS valor_total,
    MIN(c.fecha_inicio) AS primer_mes,
    MAX(DATE_ADD(c.fecha_inicio, INTERVAL c.duracion - 1 MONTH)) AS ultimo_mes
FROM proyectos p
JOIN costos c ON c.proyecto_id = p.id AND c.activo = 1
GROUP BY p.id, p.nombre_proyecto, c.categoria;

-- Vista: totales CAPEX y OPEX por proyecto (base para la fórmula de ingreso)
CREATE OR REPLACE VIEW v_proyecto_capex_opex AS
SELECT
    proyecto_id,
    SUM(CASE WHEN categoria IN ('capex_instalacion','capex_efectivo','capex_no_efectivo')
             THEN valor * duracion ELSE 0 END) AS total_capex,
    SUM(CASE WHEN categoria IN ('opex_efectivo','opex_no_efectivo','gasto_instalacion',
                                 'costo_indirecto','costo_impositivo','depreciacion','gasto_financiero')
             THEN valor * duracion ELSE 0 END) AS total_opex
FROM costos
WHERE activo = 1
GROUP BY proyecto_id;


-- ============================================================
-- PROCEDIMIENTOS ALMACENADOS
-- ============================================================

DELIMITER $$

-- Crea el schema y las tablas para un nuevo tenant
CREATE PROCEDURE IF NOT EXISTS saas_master.crear_tenant(
    IN p_empresa_id    CHAR(36),
    IN p_schema_name   VARCHAR(64)
)
BEGIN
    DECLARE sql_stmt TEXT;

    -- Crear schema
    SET sql_stmt = CONCAT('CREATE SCHEMA IF NOT EXISTS `', p_schema_name,
                          '` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci');
    PREPARE stmt FROM sql_stmt;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;

    -- En producción: ejecutar el DDL del schema empresa_schema
    -- contra el nuevo schema usando dynamic SQL o un script externo

    -- Registrar schema_name en la empresa
    UPDATE saas_master.empresas
    SET schema_name = p_schema_name
    WHERE id = p_empresa_id;

    SELECT CONCAT('Tenant creado: ', p_schema_name) AS resultado;
END$$

DELIMITER ;


-- ============================================================
-- DATOS DE PRUEBA (ambiente de desarrollo)
-- ============================================================

-- Empresa demo
INSERT INTO saas_master.empresas (id, nit, razon_social, email_contacto, plan_id, schema_name, estado) VALUES
('11111111-1111-1111-1111-111111111111',
 '900123456-7',
 'Consultora Demo S.A.S.',
 'admin@consultora-demo.co',
 (SELECT id FROM saas_master.planes WHERE codigo = 'profesional'),
 'co_9001234567',
 'activo');

-- Usuario administrador demo (password: Demo1234! → hash bcrypt)
INSERT INTO saas_master.usuarios (empresa_id, perfil_id, nombre, email, password_hash) VALUES
('11111111-1111-1111-1111-111111111111',
 (SELECT id FROM saas_master.perfiles WHERE codigo = 'administrador'),
 'Carlos Administrador',
 'admin@consultora-demo.co',
 '$2b$12$placeholderHashBcryptAdmin');

-- Usuario final demo
INSERT INTO saas_master.usuarios (empresa_id, perfil_id, nombre, email, password_hash) VALUES
('11111111-1111-1111-1111-111111111111',
 (SELECT id FROM saas_master.perfiles WHERE codigo = 'usuario_final'),
 'Ana Usuario Final',
 'ana@consultora-demo.co',
 '$2b$12$placeholderHashBcryptUser');
