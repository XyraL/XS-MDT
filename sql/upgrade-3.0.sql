-- XS-MDT — 2.x to 3.0
-- Only for servers that already ran an older version. A fresh install needs
-- sql/mdt.sql and sql/penal-codes.sql, not this.
--
-- Run this, then re-run sql/mdt.sql for the new tables, then import
-- sql/penal-codes.sql.

ALTER TABLE `mdt_evidence` DROP FOREIGN KEY `fk_evidence_incident`;
ALTER TABLE `mdt_evidence` MODIFY COLUMN `incident_id` INT DEFAULT NULL;
ALTER TABLE `mdt_evidence` ADD COLUMN IF NOT EXISTS `case_id`         INT          DEFAULT NULL;
ALTER TABLE `mdt_evidence` ADD COLUMN IF NOT EXISTS `evidence_number` VARCHAR(20)  DEFAULT NULL;
ALTER TABLE `mdt_evidence` ADD COLUMN IF NOT EXISTS `status` ENUM('booked','checked_out','released','destroyed','lost') DEFAULT 'booked';
ALTER TABLE `mdt_evidence` ADD COLUMN IF NOT EXISTS `location`        VARCHAR(120) DEFAULT NULL;

ALTER TABLE `mdt_audit_log` ADD COLUMN IF NOT EXISTS `citizenid`        VARCHAR(50)  DEFAULT NULL;
ALTER TABLE `mdt_audit_log` ADD COLUMN IF NOT EXISTS `department`       VARCHAR(50)  DEFAULT NULL;
ALTER TABLE `mdt_audit_log` ADD COLUMN IF NOT EXISTS `target_citizenid` VARCHAR(50)  DEFAULT NULL;
ALTER TABLE `mdt_audit_log` ADD COLUMN IF NOT EXISTS `target_name`      VARCHAR(100) DEFAULT NULL;

ALTER TABLE `mdt_penal_codes` ADD COLUMN IF NOT EXISTS `title_no`   TINYINT UNSIGNED  DEFAULT NULL;
ALTER TABLE `mdt_penal_codes` ADD COLUMN IF NOT EXISTS `section_no` SMALLINT UNSIGNED DEFAULT NULL;
ALTER TABLE `mdt_penal_codes` ADD COLUMN IF NOT EXISTS `subsection` VARCHAR(4)        DEFAULT NULL;

-- Optional. Your old charges stay active alongside the new book until you run
-- this, which retires the ones that came with 2.x and leaves anything you
-- added yourself.
-- UPDATE `mdt_penal_codes` SET `active` = 0 WHERE `title_no` IS NULL;
