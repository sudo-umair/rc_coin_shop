-- ============================================================
--  coin_shop - database schema
--  Run this once against your ESX database.
-- ============================================================

-- Account-wide coin balances. `account_id` is the license hex shared
-- by all characters of one player (the part after `charN:`).
CREATE TABLE IF NOT EXISTS `coin_shop_balance` (
  `account_id` VARCHAR(64) NOT NULL,
  `coins` INT(11) NOT NULL DEFAULT 0,
  `updated_at` TIMESTAMP NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`account_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- Audit log of every coin change.
CREATE TABLE IF NOT EXISTS `coin_shop_transactions` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `account_id` VARCHAR(64) NOT NULL,
  `character_identifier` VARCHAR(64) DEFAULT NULL,
  `type` VARCHAR(20) NOT NULL,            -- purchase | admin_add | admin_remove | admin_set
  `amount` INT(11) NOT NULL,              -- signed delta applied to the balance
  `balance_after` INT(11) NOT NULL,
  `item` VARCHAR(64) DEFAULT NULL,        -- purchases only
  `quantity` INT(11) DEFAULT NULL,        -- purchases only
  `actor` VARCHAR(128) DEFAULT NULL,      -- who triggered it (admin name/id, or player)
  `created_at` TIMESTAMP NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_account` (`account_id`),
  KEY `idx_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
