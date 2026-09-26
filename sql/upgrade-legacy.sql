-- XS-MDT — 1.x to 2.x
-- Only for servers coming from a version older than 2.0. Run the blocks from
-- your version onwards, then sql/upgrade-3.0.sql, then re-run sql/mdt.sql.
--
-- A fresh install needs none of this.

-- 1.0 to 1.1
ALTER TABLE `mdt_officers`    ADD COLUMN IF NOT EXISTS `status`     VARCHAR(20) DEFAULT '10-8';
ALTER TABLE `mdt_citations`   ADD COLUMN IF NOT EXISTS `paid`       TINYINT(1)  DEFAULT 0;
ALTER TABLE `mdt_warrants`    ADD COLUMN IF NOT EXISTS `expires_at` TIMESTAMP   NULL DEFAULT NULL;
ALTER TABLE `mdt_penal_codes` ADD UNIQUE KEY IF NOT EXISTS `uk_code` (`code`);
DELETE FROM `mdt_penal_codes` WHERE `id` NOT IN (SELECT * FROM (SELECT MIN(`id`) FROM `mdt_penal_codes` GROUP BY `code`) t);

-- 1.1 to 1.2
ALTER TABLE `mdt_cad_calls` ADD COLUMN IF NOT EXISTS `priority`  TINYINT     DEFAULT 2;
ALTER TABLE `mdt_arrests`   ADD COLUMN IF NOT EXISTS `tags`      JSON        DEFAULT NULL;
ALTER TABLE `mdt_citations` ADD COLUMN IF NOT EXISTS `tags`      JSON        DEFAULT NULL;
ALTER TABLE `mdt_incidents` ADD COLUMN IF NOT EXISTS `tags`      JSON        DEFAULT NULL;
ALTER TABLE `mdt_incidents` ADD COLUMN IF NOT EXISTS `severity`  VARCHAR(20) DEFAULT NULL;

-- 1.2 to 1.3
ALTER TABLE `mdt_incidents` ADD COLUMN IF NOT EXISTS `linked_arrests`   JSON DEFAULT NULL;
ALTER TABLE `mdt_incidents` ADD COLUMN IF NOT EXISTS `linked_citations` JSON DEFAULT NULL;

-- 1.3 to 1.4
ALTER TABLE `mdt_cad_calls` ADD COLUMN IF NOT EXISTS `call_type` VARCHAR(100) NOT NULL DEFAULT '' AFTER `call_number`;

-- 1.4 to 1.5
ALTER TABLE `mdt_warrants`  ADD COLUMN IF NOT EXISTS `expiry_alert_sent` TINYINT(1)  DEFAULT 0;
ALTER TABLE `mdt_incidents` ADD COLUMN IF NOT EXISTS `case_number`       VARCHAR(50) DEFAULT NULL;

-- 1.5 to 1.6
ALTER TABLE `mdt_incidents` ADD COLUMN IF NOT EXISTS `status`      VARCHAR(20)  NOT NULL DEFAULT 'open';
ALTER TABLE `mdt_incidents` ADD COLUMN IF NOT EXISTS `location`    VARCHAR(255) DEFAULT NULL;
ALTER TABLE `mdt_incidents` ADD COLUMN IF NOT EXISTS `occurred_at` TIMESTAMP    NULL DEFAULT NULL;
ALTER TABLE `mdt_incidents` ADD INDEX IF NOT EXISTS `idx_status` (`status`);
ALTER TABLE `mdt_civilians` ADD COLUMN IF NOT EXISTS `aliases`     JSON         DEFAULT NULL;

-- New tables at 1.5, 1.6 and 2.0 (mdt_shift_log, mdt_licences, mdt_evidence,
-- and the eight medical and fire tables) come from re-running sql/mdt.sql.
