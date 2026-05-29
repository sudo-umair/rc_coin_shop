Config = {}

-- ============================================================
--  GENERAL
-- ============================================================

-- Name shown next to amounts in menus/notifications (e.g. "150 Coins")
Config.CurrencyName = 'Coins'

-- Title shown at the top of the shop menu
Config.ShopTitle = 'Coin Shop'

-- Default key to open the shop. Players can rebind this in
-- GTA Settings > Key Bindings > FiveM. Use a key name FiveM understands
-- (e.g. 'F5', 'F6', 'F7', 'INSERT', 'HOME'). See:
-- https://docs.fivem.net/docs/game-references/input-mapper-parameter-ids/
Config.OpenKey = 'F5'

-- ============================================================
--  ADMIN
-- ============================================================

-- ACE permission required to run /addcoins /removecoins /setcoins /checkcoins.
-- Grant it in server.cfg, e.g:
--   add_ace group.admin coin_shop.admin allow
--   add_principal identifier.fivem:1234567 group.admin
Config.AcePermission = 'coin_shop.admin'

-- ============================================================
--  PURCHASING
-- ============================================================

-- Hard cap on how many of a single item can be bought in one purchase.
Config.MaxPurchaseQuantity = 100

-- ============================================================
--  ITEM CATALOG
-- ============================================================
-- Each entry:
--   name     = ox_inventory item name (must exist in ox_inventory's items)
--   price    = coins per single unit
--   category = optional grouping label shown as a sub-menu
--   label    = optional override; if nil the ox_inventory label is used
--
-- Labels and images are pulled automatically from ox_inventory.
Config.Items = {
    { name = 'bread',       price = 25,   category = 'Food & Drink' },
    { name = 'water',       price = 20,   category = 'Food & Drink' },
    { name = 'burger',      price = 50,   category = 'Food & Drink' },

    { name = 'lockpick',    price = 150,  category = 'Tools' },
    { name = 'phone',       price = 500,  category = 'Tools' },
    { name = 'radio',       price = 350,  category = 'Tools' },

    { name = 'bandage',     price = 100,  category = 'Medical' },
    { name = 'medikit',     price = 750,  category = 'Medical' },
}

-- ============================================================
--  LOGGING
-- ============================================================
Config.Logging = {
    -- Print every purchase / admin coin change to the server console.
    console = true,

    -- Record every coin change in the coin_shop_transactions table.
    database = true,

    -- Send a Discord embed on each purchase / admin coin change.
    discord = {
        enabled = false,
        webhook = '',                 -- paste your webhook URL here
        botName = 'Coin Shop',
        avatar  = '',                 -- optional avatar image URL
        color   = 3066993,            -- decimal embed colour (green)
    },
}
