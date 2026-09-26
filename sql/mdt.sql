-- XS-MDT Database Schema
-- Run this once before starting the resource

-- ── Upgrade scripts (run these if updating from an older version) ──────────
-- v2.x → v3.0
-- ALTER TABLE mdt_evidence DROP FOREIGN KEY fk_evidence_incident;
-- ALTER TABLE mdt_evidence MODIFY COLUMN incident_id INT DEFAULT NULL;
-- ALTER TABLE mdt_evidence ADD COLUMN IF NOT EXISTS case_id         INT         DEFAULT NULL;
-- ALTER TABLE mdt_evidence ADD COLUMN IF NOT EXISTS evidence_number VARCHAR(20) DEFAULT NULL;
-- ALTER TABLE mdt_evidence ADD COLUMN IF NOT EXISTS status ENUM('booked','checked_out','released','destroyed','lost') DEFAULT 'booked';
-- ALTER TABLE mdt_evidence ADD COLUMN IF NOT EXISTS location        VARCHAR(120) DEFAULT NULL;
-- Five more tables (mdt_cases, mdt_case_links, mdt_case_notes,
-- mdt_evidence_custody, mdt_weapons) come from re-running this file.
-- ALTER TABLE mdt_audit_log ADD COLUMN IF NOT EXISTS citizenid        VARCHAR(50)  DEFAULT NULL;
-- ALTER TABLE mdt_audit_log ADD COLUMN IF NOT EXISTS department       VARCHAR(50)  DEFAULT NULL;
-- ALTER TABLE mdt_audit_log ADD COLUMN IF NOT EXISTS target_citizenid VARCHAR(50)  DEFAULT NULL;
-- ALTER TABLE mdt_audit_log ADD COLUMN IF NOT EXISTS target_name      VARCHAR(100) DEFAULT NULL;
-- Six new tables (mdt_certifications, mdt_ia_cases, mdt_ppr, mdt_fto,
-- mdt_sop, mdt_personnel_log) come from re-running this file. Nothing
-- existing is touched by them.
-- ALTER TABLE mdt_penal_codes ADD COLUMN IF NOT EXISTS title_no   TINYINT UNSIGNED  DEFAULT NULL;
-- ALTER TABLE mdt_penal_codes ADD COLUMN IF NOT EXISTS section_no SMALLINT UNSIGNED DEFAULT NULL;
-- ALTER TABLE mdt_penal_codes ADD COLUMN IF NOT EXISTS subsection VARCHAR(4)        DEFAULT NULL;
-- Then import sql/penal-codes.sql for the new charge book. It uses INSERT
-- IGNORE, so nothing you added yourself is touched. The old 25 default
-- charges stay until you clear them, and this only removes the ones nobody
-- has used on a record:
-- UPDATE mdt_penal_codes SET active = 0 WHERE title_no IS NULL;
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
    -- Parsed out of the code so the book sorts in its own order rather than
    -- alphabetically, which puts 1.10 in front of 1.9.
    `title_no` TINYINT UNSIGNED DEFAULT NULL,
    `section_no` SMALLINT UNSIGNED DEFAULT NULL,
    `subsection` VARCHAR(4) DEFAULT NULL,
    UNIQUE KEY `uk_code` (`code`),
    KEY `idx_category` (`category`),
    KEY `idx_book_order` (`title_no`, `section_no`, `subsection`)
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

-- Penal codes are seeded from sql/penal-codes.sql, which is generated by
-- tools/build-penal.mjs. Import it after this file.

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
    -- Who, by citizenid rather than by name: two officers with the same
    -- display name were indistinguishable in this table.
    `citizenid`        VARCHAR(50)  DEFAULT NULL,
    `department`       VARCHAR(50)  DEFAULT NULL,
    -- Who it was done to, when the action had a subject.
    `target_citizenid` VARCHAR(50)  DEFAULT NULL,
    `target_name`      VARCHAR(100) DEFAULT NULL,
    `created_at`   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_action`  (`action`),
    KEY `idx_citizenid` (`citizenid`),
    KEY `idx_target`    (`target_citizenid`),
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
    -- Nullable since 3.0: evidence is booked when it is collected, and a
    -- report is written later if one is written at all.
    `incident_id` INT DEFAULT NULL,
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
    KEY `idx_case` (`case_id`),
    KEY `idx_evidence_number` (`evidence_number`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── Personnel ───────────────────────────────────────────────────────────────
-- Everything a supervisor manages about an officer. Kept in separate tables
-- rather than columns on mdt_officers because each one is a history: who
-- issued a certification, who opened an IA case, who signed off a phase.

-- Certifications an officer holds. One row per certification so it carries the
-- supervisor who issued it. The list of certifications a department offers is
-- Config.Certifications; this table only records who holds what.
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

-- Internal affairs. Complaints, investigations and commendations all live here
-- so an officer's file reads in one list.
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

-- Performance reviews.
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

-- Field training. One row per trainee per phase.
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

-- Standard operating procedures. Plain documents, grouped by department and
-- category, with a version so a change is visible without a diff.
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

-- Every change a supervisor makes to someone's file. Separate from the general
-- audit log because this one is meant to be read on the officer's own card.
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

-- ── Cases, evidence and weapons ─────────────────────────────────────────────

-- A case is the folder everything else gets filed into. Before 3.0 a case was
-- a free-text string on an incident, so two officers typing CASE-2025-1 and
-- CASE-2025-01 had two different cases and neither of them knew.
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

-- What is attached to a case. One row per link rather than columns per kind,
-- so attaching a new kind of record later needs no schema change.
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

-- Notes on a case, so the story of it is not buried in one officer's report.
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

-- Every hand a piece of evidence passes through. An evidence log that cannot
-- say who had it and when is not worth keeping.
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

-- Registered firearms. Serial numbers are the point: a seized weapon is looked
-- up by serial, and a serial that is not in here is an unregistered one.
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
