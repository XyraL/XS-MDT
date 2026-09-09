-- XSMDT Database Schema
-- Run this once before starting the resource

-- ── Upgrade scripts (run these if updating from an older version) ──────────
-- v1.0 → v1.1
-- ALTER TABLE mdt_officers    ADD COLUMN   IF NOT EXISTS status     VARCHAR(20) DEFAULT '10-8';
-- ALTER TABLE mdt_citations   ADD COLUMN   IF NOT EXISTS paid       TINYINT(1)  DEFAULT 0;
-- ALTER TABLE mdt_warrants    ADD COLUMN   IF NOT EXISTS expires_at TIMESTAMP   NULL DEFAULT NULL;
-- ALTER TABLE mdt_penal_codes ADD UNIQUE KEY IF NOT EXISTS uk_code (code);
-- DELETE FROM mdt_penal_codes WHERE id NOT IN (SELECT * FROM (SELECT MIN(id) FROM mdt_penal_codes GROUP BY code) t);
-- v1.1 → v1.2
-- ALTER TABLE mdt_cad_calls ADD COLUMN IF NOT EXISTS priority          TINYINT      DEFAULT 2;
-- ALTER TABLE mdt_arrests   ADD COLUMN IF NOT EXISTS tags              JSON         DEFAULT NULL;
-- ALTER TABLE mdt_citations ADD COLUMN IF NOT EXISTS tags              JSON         DEFAULT NULL;
-- ALTER TABLE mdt_incidents ADD COLUMN IF NOT EXISTS tags              JSON         DEFAULT NULL;
-- ALTER TABLE mdt_incidents ADD COLUMN IF NOT EXISTS severity          VARCHAR(20)  DEFAULT NULL;
-- v1.2 → v1.3
-- ALTER TABLE mdt_incidents ADD COLUMN IF NOT EXISTS linked_arrests    JSON         DEFAULT NULL;
-- ALTER TABLE mdt_incidents ADD COLUMN IF NOT EXISTS linked_citations  JSON         DEFAULT NULL;
-- v1.3 → v1.4
-- ALTER TABLE mdt_cad_calls ADD COLUMN IF NOT EXISTS call_type VARCHAR(100) NOT NULL DEFAULT '' AFTER call_number;
-- v1.4 → v1.5
-- ALTER TABLE mdt_warrants  ADD COLUMN IF NOT EXISTS expiry_alert_sent TINYINT(1)  DEFAULT 0;
-- ALTER TABLE mdt_incidents ADD COLUMN IF NOT EXISTS case_number       VARCHAR(50)  DEFAULT NULL;
-- CREATE TABLE IF NOT EXISTS mdt_shift_log ... (see below)
-- v1.6 → v2.0
-- CREATE TABLE IF NOT EXISTS mdt_evidence ... (see below)
-- v1.5 → v1.6
-- ALTER TABLE mdt_incidents ADD COLUMN IF NOT EXISTS status      VARCHAR(20)  NOT NULL DEFAULT 'open';
-- ALTER TABLE mdt_incidents ADD COLUMN IF NOT EXISTS location    VARCHAR(255) DEFAULT NULL;
-- ALTER TABLE mdt_incidents ADD COLUMN IF NOT EXISTS occurred_at TIMESTAMP    NULL DEFAULT NULL;
-- ALTER TABLE mdt_incidents ADD INDEX IF NOT EXISTS idx_status (status);
-- ALTER TABLE mdt_civilians ADD COLUMN IF NOT EXISTS aliases     JSON         DEFAULT NULL;
-- CREATE TABLE IF NOT EXISTS mdt_licences ... (see below)

CREATE TABLE IF NOT EXISTS `mdt_officers` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid` VARCHAR(50) NOT NULL UNIQUE,
    `badge` VARCHAR(20) NOT NULL UNIQUE,
    `callsign` VARCHAR(20) DEFAULT NULL,
    `rank` VARCHAR(50) DEFAULT 'Officer',
    `department` VARCHAR(50) DEFAULT 'LSPD',
    `status` VARCHAR(20) DEFAULT '10-8',
    `notes` TEXT DEFAULT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mdt_civilians` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid` VARCHAR(50) NOT NULL UNIQUE,
    `firstname` VARCHAR(50) NOT NULL,
    `lastname` VARCHAR(50) NOT NULL,
    `dob` VARCHAR(20) DEFAULT NULL,
    `gender` VARCHAR(20) DEFAULT NULL,
    `address` VARCHAR(255) DEFAULT NULL,
    `phone` VARCHAR(20) DEFAULT NULL,
    `image` TEXT DEFAULT NULL,
    `flags` JSON DEFAULT NULL,
    `notes` TEXT DEFAULT NULL,
    `aliases` JSON DEFAULT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY `idx_name` (`lastname`, `firstname`),
    KEY `idx_citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mdt_warrants` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid` VARCHAR(50) NOT NULL,
    `charges` JSON NOT NULL,
    `description` TEXT DEFAULT NULL,
    `issued_by` VARCHAR(50) NOT NULL,
    `issued_by_name` VARCHAR(100) NOT NULL,
    `status` ENUM('active', 'cleared', 'expired') DEFAULT 'active',
    `cleared_by` VARCHAR(50) DEFAULT NULL,
    `cleared_at` TIMESTAMP NULL DEFAULT NULL,
    `expires_at` TIMESTAMP NULL DEFAULT NULL,
    `expiry_alert_sent` TINYINT(1) DEFAULT 0,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_citizenid` (`citizenid`),
    KEY `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mdt_bolos` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `type` ENUM('person', 'vehicle') NOT NULL,
    `description` TEXT NOT NULL,
    `reason` TEXT NOT NULL,
    `plate` VARCHAR(20) DEFAULT NULL,
    `image` TEXT DEFAULT NULL,
    `issued_by` VARCHAR(50) NOT NULL,
    `issued_by_name` VARCHAR(100) NOT NULL,
    `active` TINYINT(1) DEFAULT 1,
    `cleared_by` VARCHAR(50) DEFAULT NULL,
    `cleared_at` TIMESTAMP NULL DEFAULT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_active` (`active`),
    KEY `idx_type` (`type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mdt_citations` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid` VARCHAR(50) NOT NULL,
    `officer_citizenid` VARCHAR(50) NOT NULL,
    `officer_name` VARCHAR(100) NOT NULL,
    `charges` JSON NOT NULL,
    `fine` INT DEFAULT 0,
    `location` VARCHAR(255) DEFAULT NULL,
    `notes` TEXT DEFAULT NULL,
    `paid` TINYINT(1) DEFAULT 0,
    `tags` JSON DEFAULT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mdt_arrests` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid` VARCHAR(50) NOT NULL,
    `officer_citizenid` VARCHAR(50) NOT NULL,
    `officer_name` VARCHAR(100) NOT NULL,
    `charges` JSON NOT NULL,
    `fine` INT DEFAULT 0,
    `jail_time` INT DEFAULT 0,
    `narrative` TEXT DEFAULT NULL,
    `location` VARCHAR(255) DEFAULT NULL,
    `tags` JSON DEFAULT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mdt_incidents` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `title` VARCHAR(255) NOT NULL,
    `narrative` TEXT NOT NULL,
    `involved_civilians` JSON DEFAULT NULL,
    `involved_officers` JSON DEFAULT NULL,
    `linked_arrests` JSON DEFAULT NULL,
    `linked_citations` JSON DEFAULT NULL,
    `case_number` VARCHAR(50) DEFAULT NULL,
    `severity` VARCHAR(20) DEFAULT NULL,
    `tags` JSON DEFAULT NULL,
    `status` VARCHAR(20) NOT NULL DEFAULT 'open',
    `location` VARCHAR(255) DEFAULT NULL,
    `occurred_at` TIMESTAMP NULL DEFAULT NULL,
    `created_by` VARCHAR(50) NOT NULL,
    `created_by_name` VARCHAR(100) NOT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY `idx_created_by` (`created_by`),
    KEY `idx_case_number` (`case_number`),
    KEY `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mdt_penal_codes` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `category` VARCHAR(100) NOT NULL,
    `code` VARCHAR(20) NOT NULL,
    `name` VARCHAR(255) NOT NULL,
    `type` ENUM('infraction', 'misdemeanor', 'felony') NOT NULL,
    `fine_amount` INT DEFAULT 0,
    `jail_time` INT DEFAULT 0,
    `description` TEXT DEFAULT NULL,
    `active` TINYINT(1) DEFAULT 1,
    UNIQUE KEY `uk_code` (`code`),
    KEY `idx_category` (`category`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mdt_cad_calls` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `call_number` VARCHAR(20) NOT NULL UNIQUE,
    `call_type` VARCHAR(100) NOT NULL,
    `description` TEXT NOT NULL,
    `location` VARCHAR(255) NOT NULL,
    `coords` JSON DEFAULT NULL,
    `units` JSON DEFAULT NULL,
    `primary_unit` VARCHAR(50) DEFAULT NULL,
    `status` ENUM('pending', 'active', 'enroute', 'onscene', 'completed', 'cancelled') DEFAULT 'pending',
    `caller_id` VARCHAR(50) DEFAULT NULL,
    `caller_name` VARCHAR(100) DEFAULT NULL,
    `notes` JSON DEFAULT NULL,
    `priority` TINYINT DEFAULT 2,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mdt_bodycam` (
    `id`           INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid`    VARCHAR(50)  NOT NULL,
    `officer_name` VARCHAR(100) NOT NULL,
    `action`       VARCHAR(100) NOT NULL,
    `details`      TEXT         DEFAULT NULL,
    `created_at`   TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_citizenid` (`citizenid`),
    KEY `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Seed default penal codes
INSERT IGNORE INTO `mdt_penal_codes` (`category`, `code`, `name`, `type`, `fine_amount`, `jail_time`) VALUES
-- Traffic
('Traffic', '12500(a) VC', 'Driving Without a License', 'infraction', 1000, 0),
('Traffic', '22350 VC', 'Speeding', 'infraction', 500, 0),
('Traffic', '23152(a) VC', 'Driving Under the Influence', 'misdemeanor', 2500, 10),
('Traffic', '23153(a) VC', 'DUI Causing Injury', 'felony', 5000, 30),
('Traffic', '20001 VC', 'Hit and Run (Felony)', 'felony', 3000, 20),
('Traffic', '20002 VC', 'Hit and Run (Misdemeanor)', 'misdemeanor', 1500, 0),
('Traffic', '2800.2 VC', 'Evading a Peace Officer', 'felony', 3500, 25),
('Traffic', '10851 VC', 'Vehicle Theft', 'felony', 4000, 30),
-- Crimes Against Persons
('Crimes Against Persons', '187 PC', 'Murder', 'felony', 0, 120),
('Crimes Against Persons', '664/187 PC', 'Attempted Murder', 'felony', 0, 60),
('Crimes Against Persons', '245(a)(1) PC', 'Assault with a Deadly Weapon', 'felony', 5000, 40),
('Crimes Against Persons', '240 PC', 'Assault', 'misdemeanor', 1000, 5),
('Crimes Against Persons', '242 PC', 'Battery', 'misdemeanor', 1500, 5),
('Crimes Against Persons', '207 PC', 'Kidnapping', 'felony', 0, 60),
('Crimes Against Persons', '261 PC', 'Rape', 'felony', 0, 120),
-- Crimes Against Property
('Crimes Against Property', '211 PC', 'Robbery', 'felony', 0, 40),
('Crimes Against Property', '212.5 PC', 'Home Invasion Robbery', 'felony', 0, 60),
('Crimes Against Property', '459 PC', 'Burglary', 'felony', 3000, 25),
('Crimes Against Property', '487 PC', 'Grand Theft', 'felony', 2500, 15),
('Crimes Against Property', '488 PC', 'Petty Theft', 'misdemeanor', 750, 0),
('Crimes Against Property', '594 PC', 'Vandalism', 'misdemeanor', 1000, 5),
-- Weapons
('Weapons', '25400 PC', 'Carrying a Concealed Weapon', 'misdemeanor', 2000, 10),
('Weapons', '26350 PC', 'Open Carry (Unloaded)', 'misdemeanor', 1000, 5),
('Weapons', '417 PC', 'Brandishing a Weapon', 'misdemeanor', 1500, 5),
('Weapons', '12022.5 PC', 'Using a Firearm During a Felony', 'felony', 0, 30),
-- Narcotics
('Narcotics', '11350 HS', 'Possession of a Controlled Substance', 'misdemeanor', 1500, 5),
('Narcotics', '11351 HS', 'Possession for Sale', 'felony', 5000, 30),
('Narcotics', '11352 HS', 'Transportation/Sale of Controlled Substance', 'felony', 7500, 45),
('Narcotics', '11357 HS', 'Possession of Marijuana (Over Limit)', 'infraction', 500, 0),
-- Against Government
('Against Government', '69 PC', 'Obstruction of Justice', 'misdemeanor', 1000, 5),
('Against Government', '148(a)(1) PC', 'Resisting Arrest', 'misdemeanor', 1500, 5),
('Against Government', '647(b) PC', 'Disorderly Conduct', 'misdemeanor', 500, 0),
('Against Government', '13523 PC', 'Impersonating an Officer', 'felony', 3000, 20),
('Against Government', '32 PC', 'Accessory After the Fact', 'felony', 2000, 15),
('Against Government', '182 PC', 'Criminal Conspiracy', 'felony', 3000, 20);

-- ── Department Bulletins ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `mdt_bulletins` (
    `id`              INT AUTO_INCREMENT PRIMARY KEY,
    `title`           VARCHAR(200)    NOT NULL,
    `body`            TEXT            NOT NULL,
    `priority`        VARCHAR(20)     DEFAULT 'normal',
    `pinned`          TINYINT(1)      DEFAULT 0,
    `created_by`      VARCHAR(50)     NOT NULL,
    `created_by_name` VARCHAR(100),
    `expires_at`      DATETIME        DEFAULT NULL,
    `is_archived`     TINYINT(1)      DEFAULT 0,
    `created_at`      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_active (`is_archived`, `expires_at`, `pinned`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── Shift Log ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `mdt_shift_log` (
    `id`               INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid`        VARCHAR(50)  NOT NULL,
    `officer_name`     VARCHAR(100) NOT NULL,
    `badge`            VARCHAR(20)  DEFAULT NULL,
    `clock_in`         TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `clock_out`        TIMESTAMP    NULL DEFAULT NULL,
    `duration_minutes` INT          DEFAULT NULL,
    KEY `idx_citizenid` (`citizenid`),
    KEY `idx_clock_in`  (`clock_in`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── Audit Log ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `mdt_audit_log` (
    `id`           INT AUTO_INCREMENT PRIMARY KEY,
    `action`       VARCHAR(100) NOT NULL,
    `officer_name` VARCHAR(100) NOT NULL,
    `details`      TEXT DEFAULT NULL,
    `created_at`   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_action`  (`action`),
    KEY `idx_officer` (`officer_name`),
    KEY `idx_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ═══════════════════════════════════════════════════════════════════════════
--  EMS  (v1.5.0)
-- ═══════════════════════════════════════════════════════════════════════════

-- ── Patient Care Reports ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `mdt_pcr` (
    `id`                INT AUTO_INCREMENT PRIMARY KEY,
    `patient_citizenid` VARCHAR(50)  NOT NULL,
    `patient_name`      VARCHAR(100) NOT NULL,
    `chief_complaint`   VARCHAR(255) NOT NULL,
    `narrative`         TEXT         DEFAULT NULL,
    `injuries`          LONGTEXT     DEFAULT NULL,   -- JSON array
    `treatments`        LONGTEXT     DEFAULT NULL,   -- JSON array
    `vitals`            LONGTEXT     DEFAULT NULL,   -- JSON object
    `disposition`       VARCHAR(32)  NOT NULL DEFAULT 'treated_released',
    `transported_to`    VARCHAR(100) DEFAULT NULL,
    `priority`          TINYINT      NOT NULL DEFAULT 3,   -- 1 critical … 4 minor
    `status`            VARCHAR(16)  NOT NULL DEFAULT 'open',
    `medic_citizenid`   VARCHAR(50)  NOT NULL,
    `medic_name`        VARCHAR(100) NOT NULL,
    `created_at`        TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_patient` (`patient_citizenid`),
    KEY `idx_medic`   (`medic_citizenid`),
    KEY `idx_status`  (`status`),
    KEY `idx_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── Medical record (one row per civilian) ───────────────────────────────────
CREATE TABLE IF NOT EXISTS `mdt_medical` (
    `citizenid`   VARCHAR(50) PRIMARY KEY,
    `blood_type`  VARCHAR(8)  DEFAULT NULL,
    `allergies`   LONGTEXT    DEFAULT NULL,   -- JSON array
    `conditions`  LONGTEXT    DEFAULT NULL,   -- JSON array
    `medications` LONGTEXT    DEFAULT NULL,   -- JSON array
    `dnr`         TINYINT(1)  NOT NULL DEFAULT 0,
    `organ_donor` TINYINT(1)  NOT NULL DEFAULT 0,
    `notes`       TEXT        DEFAULT NULL,
    `updated_at`  TIMESTAMP   DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── Dated medical history entries ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `mdt_medical_history` (
    `id`               INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid`        VARCHAR(50)  NOT NULL,
    `entry_type`       VARCHAR(32)  NOT NULL DEFAULT 'note',
    `entry`            TEXT         NOT NULL,
    `author_citizenid` VARCHAR(50)  NOT NULL,
    `author_name`      VARCHAR(100) NOT NULL,
    `created_at`       TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_citizenid` (`citizenid`),
    KEY `idx_created`   (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── Controlled substance log ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `mdt_narc_log` (
    `id`                INT AUTO_INCREMENT PRIMARY KEY,
    `drug`              VARCHAR(64)  NOT NULL,
    `amount`            DECIMAL(10,2) NOT NULL DEFAULT 0,
    `unit`              VARCHAR(16)  NOT NULL DEFAULT 'mg',
    `action`            VARCHAR(16)  NOT NULL,   -- drawn | administered | wasted
    `patient_citizenid` VARCHAR(50)  DEFAULT NULL,
    `patient_name`      VARCHAR(100) DEFAULT NULL,
    `witness_name`      VARCHAR(100) DEFAULT NULL,
    `notes`             TEXT         DEFAULT NULL,
    `medic_citizenid`   VARCHAR(50)  NOT NULL,
    `medic_name`        VARCHAR(100) NOT NULL,
    `pcr_id`            INT          DEFAULT NULL,
    `created_at`        TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_medic`   (`medic_citizenid`),
    KEY `idx_drug`    (`drug`),
    KEY `idx_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ═══════════════════════════════════════════════════════════════════════════
--  FIRE  (v1.5.0)
-- ═══════════════════════════════════════════════════════════════════════════

-- ── Fire incident reports ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `mdt_fire_incidents` (
    `id`               INT AUTO_INCREMENT PRIMARY KEY,
    `incident_type`    VARCHAR(64)  NOT NULL,
    `address`          VARCHAR(255) NOT NULL,
    `alarm_level`      TINYINT      NOT NULL DEFAULT 1,
    `cause`            VARCHAR(64)  NOT NULL DEFAULT 'undetermined',
    `structure_type`   VARCHAR(64)  DEFAULT NULL,
    `narrative`        TEXT         DEFAULT NULL,
    `units_responded`  LONGTEXT     DEFAULT NULL,   -- JSON array
    `personnel`        LONGTEXT     DEFAULT NULL,   -- JSON array
    `casualties`       LONGTEXT     DEFAULT NULL,   -- JSON array
    `damage_estimate`  INT          NOT NULL DEFAULT 0,
    `acres_burned`     DECIMAL(10,2) NOT NULL DEFAULT 0,
    `water_used`       INT          NOT NULL DEFAULT 0,
    `status`           VARCHAR(16)  NOT NULL DEFAULT 'open',
    `created_by`       VARCHAR(50)  NOT NULL,
    `created_by_name`  VARCHAR(100) NOT NULL,
    `created_at`       TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_creator` (`created_by`),
    KEY `idx_status`  (`status`),
    KEY `idx_type`    (`incident_type`),
    KEY `idx_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── Hazmat ──────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `mdt_hazmat` (
    `id`                INT AUTO_INCREMENT PRIMARY KEY,
    `substance`         VARCHAR(128) NOT NULL,
    `un_number`         VARCHAR(16)  DEFAULT NULL,
    `hazard_class`      VARCHAR(32)  DEFAULT NULL,
    `location`          VARCHAR(255) NOT NULL,
    `quantity`          VARCHAR(64)  DEFAULT NULL,
    `containment`       VARCHAR(32)  NOT NULL DEFAULT 'ongoing',
    `evacuation_radius` INT          NOT NULL DEFAULT 0,
    `injuries`          INT          NOT NULL DEFAULT 0,
    `narrative`         TEXT         DEFAULT NULL,
    `status`            VARCHAR(16)  NOT NULL DEFAULT 'active',
    `incident_id`       INT          DEFAULT NULL,
    `created_by`        VARCHAR(50)  NOT NULL,
    `created_by_name`   VARCHAR(100) NOT NULL,
    `created_at`        TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_status`   (`status`),
    KEY `idx_incident` (`incident_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── Apparatus roster ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `mdt_apparatus` (
    `id`         INT AUTO_INCREMENT PRIMARY KEY,
    `unit_id`    VARCHAR(32)  NOT NULL,          -- e.g. "Engine 12"
    `type`       VARCHAR(32)  NOT NULL DEFAULT 'engine',
    `station`    VARCHAR(64)  DEFAULT NULL,
    `status`     VARCHAR(24)  NOT NULL DEFAULT 'in_service',
    `notes`      TEXT         DEFAULT NULL,
    `created_at` TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY `uq_unit` (`unit_id`),
    KEY `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── Apparatus inspection log ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `mdt_apparatus_log` (
    `id`               INT AUTO_INCREMENT PRIMARY KEY,
    `apparatus_id`     INT          NOT NULL,
    `check_type`       VARCHAR(32)  NOT NULL DEFAULT 'daily',
    `result`           VARCHAR(16)  NOT NULL DEFAULT 'pass',
    `mileage`          INT          NOT NULL DEFAULT 0,
    `notes`            TEXT         DEFAULT NULL,
    `author_citizenid` VARCHAR(50)  NOT NULL,
    `author_name`      VARCHAR(100) NOT NULL,
    `created_at`       TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_apparatus` (`apparatus_id`),
    KEY `idx_created`   (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Licence status.
--
-- Qbox already stores whether a character HOLDS a licence, in
-- players.metadata.licences. It has no concept of one being suspended, of who
-- suspended it, or of why — which is most of what an officer actually needs to
-- know at a traffic stop. This table holds that layer.
--
-- A citizen with no row here is treated as valid, so the table only ever
-- carries exceptions rather than a row per person per licence.
CREATE TABLE IF NOT EXISTS `mdt_licences` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid` VARCHAR(50) NOT NULL,
    `type` VARCHAR(30) NOT NULL,
    `status` VARCHAR(20) NOT NULL DEFAULT 'valid',
    `reason` TEXT DEFAULT NULL,
    `expires_at` TIMESTAMP NULL DEFAULT NULL,
    `changed_by` VARCHAR(50) DEFAULT NULL,
    `changed_by_name` VARCHAR(100) DEFAULT NULL,
    `changed_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY `uk_citizen_type` (`citizenid`, `type`),
    KEY `idx_citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Evidence attached to incident reports: photos, items and notes, each stamped
-- with who logged it and when. Rows go with their report — the foreign key
-- cascades on delete.
CREATE TABLE IF NOT EXISTS `mdt_evidence` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `incident_id` INT NOT NULL,
    `kind` VARCHAR(10) NOT NULL,
    `label` VARCHAR(120) NOT NULL,
    `detail` TEXT DEFAULT NULL,
    `photo` TEXT DEFAULT NULL,
    `logged_by` VARCHAR(50) NOT NULL,
    `logged_by_name` VARCHAR(100) NOT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_incident` (`incident_id`),
    CONSTRAINT `fk_evidence_incident` FOREIGN KEY (`incident_id`)
        REFERENCES `mdt_incidents` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
