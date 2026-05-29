Config = {}

-- ============================================================
--  GENERAL
-- ============================================================

-- Name shown next to amounts in the UI (e.g. "150 Coins")
Config.CurrencyName = 'Coins'

-- Title shown at the top of the shop UI
Config.ShopTitle = 'Coin Shop'

-- Default key to open the shop. Players can rebind this in
-- GTA Settings > Key Bindings > FiveM. Use a key name FiveM understands
-- (e.g. 'F5', 'F6', 'F7', 'INSERT', 'HOME'). See:
-- https://docs.fivem.net/docs/game-references/input-mapper-parameter-ids/
Config.OpenKey = 'F5'

-- ============================================================
--  BRANDING / THEME  (matches mGarage + ac_scoreboard)
-- ============================================================
Config.Branding = {
    serverName = 'Royal RP',     -- shown in the UI header
    logo = 'logo.png',           -- file inside html/ ; used as header mark + bg watermark
    showBackgroundLogo = true,   -- faint watermark behind the panel
    accent = '#CCAA00',          -- primary gold accent
    accentHover = '#e0be00',     -- brighter gold for hover/active
}

-- ============================================================
--  ADMIN
-- ============================================================

-- ACE permission required for: the in-UI Admin tab, item management,
-- and the /addcoins /removecoins /setcoins /checkcoins commands.
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
-- The catalog is stored in the `coin_shop_items` table and managed
-- entirely from the in-game Admin tab (add / update / remove items).
-- It starts empty; add items via the UI. Labels and images are pulled
-- from ox_inventory unless overridden per item.

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
        color   = 13413120,           -- decimal embed colour (#CCAA00 gold)
    },
}
