-- XS-MDT — database schema
-- Run this once, then sql/penal-codes.sql for the charge book.
CREATE TABLE IF NOT EXISTS `mdt_apparatus` (
    `id`         INT AUTO_INCREMENT PRIMARY KEY,
    `unit_id`    VARCHAR(32)  NOT NULL,
    `type`       VARCHAR(32)  NOT NULL DEFAULT 'engine',
    `station`    VARCHAR(64)  DEFAULT NULL,
    `status`     VARCHAR(24)  NOT NULL DEFAULT 'in_service',
    `notes`      TEXT         DEFAULT NULL,
    `created_at` TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY `uq_unit` (`unit_id`),
    KEY `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

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
    `updated_at` TIMESTAMP NULL DEFAULT NULL,
    KEY `idx_citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mdt_audit_log` (
    `id`           INT AUTO_INCREMENT PRIMARY KEY,
    `action`       VARCHAR(100) NOT NULL,
    `officer_name` VARCHAR(100) NOT NULL,
    `details`      TEXT DEFAULT NULL,
    `citizenid`        VARCHAR(50)  DEFAULT NULL,
    `department`       VARCHAR(50)  DEFAULT NULL,
    `target_citizenid` VARCHAR(50)  DEFAULT NULL,
    `target_name`      VARCHAR(100) DEFAULT NULL,
    `created_at`   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_action`  (`action`),
    KEY `idx_citizenid` (`citizenid`),
    KEY `idx_target`    (`target_citizenid`),
    KEY `idx_officer` (`officer_name`),
    KEY `idx_created` (`created_at`)
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

CREATE TABLE IF NOT EXISTS `mdt_cameras` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `camera_code` VARCHAR(20) NOT NULL UNIQUE,
    `label` VARCHAR(120) NOT NULL,
    `area` VARCHAR(80) DEFAULT NULL,
    `kind` ENUM('fixed', 'traffic', 'atm', 'transit', 'private') DEFAULT 'fixed',
    `coords` JSON DEFAULT NULL,
    `heading` FLOAT DEFAULT 0,
    `pitch` FLOAT DEFAULT -12,
    `status` ENUM('online', 'offline', 'maintenance') DEFAULT 'online',
    `notes` TEXT DEFAULT NULL,
    `added_by` VARCHAR(50) DEFAULT NULL,
    `added_by_name` VARCHAR(100) DEFAULT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY `idx_area` (`area`),
    KEY `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mdt_cases` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `case_number` VARCHAR(20) NOT NULL UNIQUE,
    `title` VARCHAR(200) NOT NULL,
    `summary` TEXT DEFAULT NULL,
    `status` ENUM('open', 'active', 'cold', 'closed') DEFAULT 'open',
    `lead_citizenid` VARCHAR(50) DEFAULT NULL,
    `lead_name` VARCHAR(100) DEFAULT NULL,
    `department` VARCHAR(50) DEFAULT NULL,
    `created_by` VARCHAR(50) NOT NULL,
    `created_by_name` VARCHAR(100) NOT NULL,
    `closed_at` TIMESTAMP NULL DEFAULT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY `idx_status` (`status`),
    KEY `idx_department` (`department`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mdt_case_links` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `case_id` INT NOT NULL,
    `kind` VARCHAR(20) NOT NULL,
    `ref_id` VARCHAR(60) NOT NULL,
    `label` VARCHAR(200) DEFAULT NULL,
    `added_by` VARCHAR(50) NOT NULL,
    `added_by_name` VARCHAR(100) NOT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY `uk_case_ref` (`case_id`, `kind`, `ref_id`),
    KEY `idx_case` (`case_id`),
    CONSTRAINT `fk_link_case` FOREIGN KEY (`case_id`)
        REFERENCES `mdt_cases` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mdt_case_notes` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `case_id` INT NOT NULL,
    `body` TEXT NOT NULL,
    `author` VARCHAR(50) NOT NULL,
    `author_name` VARCHAR(100) NOT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_case` (`case_id`),
    CONSTRAINT `fk_note_case` FOREIGN KEY (`case_id`)
        REFERENCES `mdt_cases` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mdt_certifications` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid` VARCHAR(50) NOT NULL,
    `cert` VARCHAR(60) NOT NULL,
    `issued_by` VARCHAR(50) NOT NULL,
    `issued_by_name` VARCHAR(100) NOT NULL,
    `issued_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY `uk_officer_cert` (`citizenid`, `cert`),
    KEY `idx_citizenid` (`citizenid`)
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

CREATE TABLE IF NOT EXISTS `mdt_evidence` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `incident_id` INT DEFAULT NULL,
    `arrest_id` INT DEFAULT NULL,
    `case_id` INT DEFAULT NULL,
    `evidence_number` VARCHAR(20) DEFAULT NULL,
    `status` ENUM('booked', 'checked_out', 'released', 'destroyed', 'lost') DEFAULT 'booked',
    `location` VARCHAR(120) DEFAULT NULL,
    `kind` VARCHAR(10) NOT NULL,
    `label` VARCHAR(120) NOT NULL,
    `detail` TEXT DEFAULT NULL,
    `photo` TEXT DEFAULT NULL,
    `logged_by` VARCHAR(50) NOT NULL,
    `logged_by_name` VARCHAR(100) NOT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_incident` (`incident_id`),
    KEY `idx_arrest` (`arrest_id`),
    KEY `idx_case` (`case_id`),
    KEY `idx_evidence_number` (`evidence_number`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mdt_evidence_custody` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `evidence_id` INT NOT NULL,
    `action` VARCHAR(20) NOT NULL,
    `detail` VARCHAR(255) DEFAULT NULL,
    `officer_citizenid` VARCHAR(50) NOT NULL,
    `officer_name` VARCHAR(100) NOT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_evidence` (`evidence_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mdt_fire_incidents` (
    `id`               INT AUTO_INCREMENT PRIMARY KEY,
    `incident_type`    VARCHAR(64)  NOT NULL,
    `address`          VARCHAR(255) NOT NULL,
    `alarm_level`      TINYINT      NOT NULL DEFAULT 1,
    `cause`            VARCHAR(64)  NOT NULL DEFAULT 'undetermined',
    `structure_type`   VARCHAR(64)  DEFAULT NULL,
    `narrative`        TEXT         DEFAULT NULL,
    `units_responded`  LONGTEXT     DEFAULT NULL,
    `personnel`        LONGTEXT     DEFAULT NULL,
    `casualties`       LONGTEXT     DEFAULT NULL,
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

CREATE TABLE IF NOT EXISTS `mdt_footage` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `footage_number` VARCHAR(20) NOT NULL UNIQUE,
    `source` ENUM('camera', 'dashcam', 'bodycam') DEFAULT 'camera',
    `camera_id` INT DEFAULT NULL,
    `camera_code` VARCHAR(20) DEFAULT NULL,
    `unit_citizenid` VARCHAR(50) DEFAULT NULL,
    `unit_name` VARCHAR(100) DEFAULT NULL,
    `case_id` INT DEFAULT NULL,
    `label` VARCHAR(200) NOT NULL,
    `detail` TEXT DEFAULT NULL,
    `recorded_at` TIMESTAMP NULL DEFAULT NULL,
    `duration` INT DEFAULT NULL,
    `status` ENUM('requested', 'available', 'archived', 'purged') DEFAULT 'available',
    `logged_by` VARCHAR(50) NOT NULL,
    `logged_by_name` VARCHAR(100) NOT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_case` (`case_id`),
    KEY `idx_source` (`source`),
    KEY `idx_camera` (`camera_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mdt_fto` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid` VARCHAR(50) NOT NULL,
    `trainee_name` VARCHAR(100) NOT NULL,
    `phase` VARCHAR(40) NOT NULL,
    `status` ENUM('in_progress', 'passed', 'failed') DEFAULT 'in_progress',
    `hours` DECIMAL(6,1) DEFAULT 0,
    `trainer_id` VARCHAR(50) DEFAULT NULL,
    `trainer_name` VARCHAR(100) DEFAULT NULL,
    `notes` TEXT DEFAULT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY `idx_citizenid` (`citizenid`),
    KEY `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

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

CREATE TABLE IF NOT EXISTS `mdt_ia_cases` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `case_number` VARCHAR(20) NOT NULL UNIQUE,
    `citizenid` VARCHAR(50) NOT NULL,
    `officer_name` VARCHAR(100) NOT NULL,
    `kind` ENUM('complaint', 'investigation', 'commendation') DEFAULT 'complaint',
    `title` VARCHAR(200) NOT NULL,
    `detail` TEXT DEFAULT NULL,
    `outcome` TEXT DEFAULT NULL,
    `status` ENUM('open', 'investigating', 'sustained', 'unfounded', 'closed') DEFAULT 'open',
    `opened_by` VARCHAR(50) NOT NULL,
    `opened_by_name` VARCHAR(100) NOT NULL,
    `closed_at` TIMESTAMP NULL DEFAULT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY `idx_citizenid` (`citizenid`),
    KEY `idx_status` (`status`)
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

CREATE TABLE IF NOT EXISTS `mdt_medical` (
    `citizenid`   VARCHAR(50) PRIMARY KEY,
    `blood_type`  VARCHAR(8)  DEFAULT NULL,
    `allergies`   LONGTEXT    DEFAULT NULL,
    `conditions`  LONGTEXT    DEFAULT NULL,
    `medications` LONGTEXT    DEFAULT NULL,
    `dnr`         TINYINT(1)  NOT NULL DEFAULT 0,
    `organ_donor` TINYINT(1)  NOT NULL DEFAULT 0,
    `notes`       TEXT        DEFAULT NULL,
    `updated_at`  TIMESTAMP   DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

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

CREATE TABLE IF NOT EXISTS `mdt_narc_log` (
    `id`                INT AUTO_INCREMENT PRIMARY KEY,
    `drug`              VARCHAR(64)  NOT NULL,
    `amount`            DECIMAL(10,2) NOT NULL DEFAULT 0,
    `unit`              VARCHAR(16)  NOT NULL DEFAULT 'mg',
    `action`            VARCHAR(16)  NOT NULL,
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

CREATE TABLE IF NOT EXISTS `mdt_officers` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid` VARCHAR(50) NOT NULL UNIQUE,
    `name` VARCHAR(100) DEFAULT NULL,
    `badge` VARCHAR(20) NOT NULL UNIQUE,
    `callsign` VARCHAR(20) DEFAULT NULL,
    `rank` VARCHAR(50) DEFAULT 'Officer',
    `department` VARCHAR(50) DEFAULT 'LSPD',
    `status` VARCHAR(20) DEFAULT '10-8',
    `notes` TEXT DEFAULT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mdt_pcr` (
    `id`                INT AUTO_INCREMENT PRIMARY KEY,
    `patient_citizenid` VARCHAR(50)  NOT NULL,
    `patient_name`      VARCHAR(100) NOT NULL,
    `chief_complaint`   VARCHAR(255) NOT NULL,
    `narrative`         TEXT         DEFAULT NULL,
    `injuries`          LONGTEXT     DEFAULT NULL,
    `treatments`        LONGTEXT     DEFAULT NULL,
    `vitals`            LONGTEXT     DEFAULT NULL,
    `disposition`       VARCHAR(32)  NOT NULL DEFAULT 'treated_released',
    `transported_to`    VARCHAR(100) DEFAULT NULL,
    `priority`          TINYINT      NOT NULL DEFAULT 3,
    `status`            VARCHAR(16)  NOT NULL DEFAULT 'open',
    `medic_citizenid`   VARCHAR(50)  NOT NULL,
    `medic_name`        VARCHAR(100) NOT NULL,
    `created_at`        TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_patient` (`patient_citizenid`),
    KEY `idx_medic`   (`medic_citizenid`),
    KEY `idx_status`  (`status`),
    KEY `idx_created` (`created_at`)
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
    `title_no` TINYINT UNSIGNED DEFAULT NULL,
    `section_no` SMALLINT UNSIGNED DEFAULT NULL,
    `subsection` VARCHAR(4) DEFAULT NULL,
    UNIQUE KEY `uk_code` (`code`),
    KEY `idx_category` (`category`),
    KEY `idx_book_order` (`title_no`, `section_no`, `subsection`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mdt_personnel_log` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid` VARCHAR(50) NOT NULL,
    `field` VARCHAR(40) NOT NULL,
    `old_value` VARCHAR(255) DEFAULT NULL,
    `new_value` VARCHAR(255) DEFAULT NULL,
    `changed_by` VARCHAR(50) NOT NULL,
    `changed_by_name` VARCHAR(100) NOT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mdt_ppr` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid` VARCHAR(50) NOT NULL,
    `period` VARCHAR(60) DEFAULT NULL,
    `rating` TINYINT DEFAULT 3,
    `strengths` TEXT DEFAULT NULL,
    `improve` TEXT DEFAULT NULL,
    `notes` TEXT DEFAULT NULL,
    `reviewed_by` VARCHAR(50) NOT NULL,
    `reviewed_by_name` VARCHAR(100) NOT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

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

CREATE TABLE IF NOT EXISTS `mdt_sop` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `department` VARCHAR(50) NOT NULL,
    `category` VARCHAR(60) DEFAULT 'General',
    `title` VARCHAR(200) NOT NULL,
    `body` MEDIUMTEXT NOT NULL,
    `version` VARCHAR(20) DEFAULT '1.0',
    `pinned` TINYINT(1) DEFAULT 0,
    `updated_by` VARCHAR(50) DEFAULT NULL,
    `updated_by_name` VARCHAR(100) DEFAULT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY `idx_department` (`department`)
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

CREATE TABLE IF NOT EXISTS `mdt_weapons` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `serial` VARCHAR(30) NOT NULL UNIQUE,
    `model` VARCHAR(80) NOT NULL,
    `class` VARCHAR(40) DEFAULT NULL,
    `owner_citizenid` VARCHAR(50) DEFAULT NULL,
    `owner_name` VARCHAR(100) DEFAULT NULL,
    `status` ENUM('registered', 'stolen', 'seized', 'destroyed', 'unregistered') DEFAULT 'registered',
    `registered_at` DATE DEFAULT NULL,
    `notes` TEXT DEFAULT NULL,
    `added_by` VARCHAR(50) DEFAULT NULL,
    `added_by_name` VARCHAR(100) DEFAULT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY `idx_owner` (`owner_citizenid`),
    KEY `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
