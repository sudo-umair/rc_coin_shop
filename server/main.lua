local ESX = exports['es_extended']:getSharedObject()

-- account_id -> coins (in-memory cache for online players)
local balances = {}

-- catalog cache: id -> row, plus an ordered list
local items = {}

-- ============================================================
--  HELPERS
-- ============================================================

-- Strip the multicharacter prefix (`char1:`, `char2:`...) so all of a
-- player's characters resolve to one account-wide balance.
local function getAccountId(identifier)
    if not identifier then return nil end
    return (identifier:gsub('^char%d+:', ''))
end

local function getAccountIdFromSource(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return nil end
    return getAccountId(xPlayer.identifier)
end

local function isAdmin(src)
    if src == 0 then return true end -- server console / txAdmin
    return IsPlayerAceAllowed(src, Config.AcePermission)
end

-- ox_inventory item registry (label + image fallbacks)
local function oxItems()
    return exports.ox_inventory:Items()
end

local function resolveLabel(row)
    if row.label and row.label ~= '' then return row.label end
    local ox = oxItems()[row.name]
    return ox and ox.label or row.name
end

local function resolveImage(row)
    if row.image and row.image ~= '' then return row.image end
    return ('nui://ox_inventory/web/images/%s.png'):format(row.name)
end

-- Display shape sent to the NUI.
local function toDisplay(row)
    return {
        id = row.id,
        name = row.name,
        label = resolveLabel(row),
        price = row.price,
        category = (row.category and row.category ~= '') and row.category or 'General',
        description = row.description or '',
        image = resolveImage(row),
        enabled = row.enabled == 1 or row.enabled == true,
        sort_order = row.sort_order,
        -- raw override values, used to prefill the admin edit form
        rawLabel = row.label or '',
        rawImage = row.image or '',
        rawCategory = row.category or '',
    }
end

-- All online server ids belonging to one account (multichar aware).
local function sourcesForAccount(accountId)
    local list = {}
    for _, playerId in ipairs(GetPlayers()) do
        local xPlayer = ESX.GetPlayerFromId(tonumber(playerId))
        if xPlayer and getAccountId(xPlayer.identifier) == accountId then
            list[#list + 1] = tonumber(playerId)
        end
    end
    return list
end

local function toast(src, kind, message)
    if src and src ~= 0 then
        TriggerClientEvent('rc_coin_shop:toast', src, kind, message)
    else
        print(('[rc_coin_shop] %s'):format(message))
    end
end

-- ============================================================
--  CATALOG
-- ============================================================

local function loadCatalog()
    local rows = MySQL.query.await('SELECT * FROM coin_shop_items ORDER BY sort_order ASC, id ASC') or {}
    items = {}
    for _, row in ipairs(rows) do
        items[row.id] = row
    end
    print(('[rc_coin_shop] Loaded %d catalog item(s).'):format(#rows))
end

-- Ordered display list. `onlyEnabled` for the player shop.
local function catalogList(onlyEnabled)
    local list = {}
    for _, row in pairs(items) do
        if not onlyEnabled or (row.enabled == 1 or row.enabled == true) then
            list[#list + 1] = toDisplay(row)
        end
    end
    table.sort(list, function(a, b)
        if a.sort_order ~= b.sort_order then return a.sort_order < b.sort_order end
        return a.id < b.id
    end)
    return list
end

-- ============================================================
--  LOGGING
-- ============================================================

local function logDiscord(title, description)
    local d = Config.Logging.discord
    if not d.enabled or d.webhook == '' then return end

    PerformHttpRequest(d.webhook, function() end, 'POST', json.encode({
        username = d.botName,
        avatar_url = d.avatar ~= '' and d.avatar or nil,
        embeds = { {
            title = title,
            description = description,
            color = d.color,
            footer = { text = ('rc_coin_shop • %s'):format(os.date('%Y-%m-%d %H:%M:%S')) },
        } },
    }), { ['Content-Type'] = 'application/json' })
end

-- type: purchase | admin_add | admin_remove | admin_set
local function logTransaction(data)
    if Config.Logging.console then
        print(('[rc_coin_shop] %s | account=%s amount=%s balance=%s%s actor=%s'):format(
            data.type,
            data.account_id,
            data.amount,
            data.balance_after,
            data.item and (' item=%sx%s'):format(data.item, data.quantity) or '',
            data.actor or 'system'
        ))
    end

    if Config.Logging.database then
        MySQL.insert([[
            INSERT INTO coin_shop_transactions
                (account_id, character_identifier, type, amount, balance_after, item, quantity, actor)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            data.account_id, data.character_identifier, data.type, data.amount,
            data.balance_after, data.item, data.quantity, data.actor,
        })
    end

    if Config.Logging.discord.enabled then
        logDiscord(('Coin %s'):format(data.type), data.description or (
            ('**Account:** %s\n**Amount:** %s\n**New balance:** %s'):format(
                data.account_id, data.amount, data.balance_after)))
    end
end

-- ============================================================
--  BALANCE CORE
-- ============================================================

local function loadBalance(accountId)
    if not accountId then return 0 end
    if balances[accountId] ~= nil then return balances[accountId] end

    local row = MySQL.single.await('SELECT coins FROM coin_shop_balance WHERE account_id = ?', { accountId })
    if row then
        balances[accountId] = row.coins
    else
        MySQL.insert.await('INSERT IGNORE INTO coin_shop_balance (account_id, coins) VALUES (?, 0)', { accountId })
        balances[accountId] = 0
    end
    return balances[accountId]
end

local function persistBalance(accountId, coins)
    balances[accountId] = coins
    MySQL.prepare.await([[
        INSERT INTO coin_shop_balance (account_id, coins) VALUES (?, ?)
        ON DUPLICATE KEY UPDATE coins = VALUES(coins)
    ]], { accountId, coins })

    -- Refresh any open UI for this account's online characters.
    for _, src in ipairs(sourcesForAccount(accountId)) do
        TriggerClientEvent('rc_coin_shop:balanceUpdate', src, coins)
    end
end

-- Returns the new balance, or nil + reason on failure.
local function ModifyCoins(accountId, delta, meta)
    if not accountId then return nil, 'no_account' end
    local current = loadBalance(accountId)
    local newBalance = current + delta
    if newBalance < 0 then return nil, 'insufficient' end

    persistBalance(accountId, newBalance)

    if meta then
        logTransaction({
            account_id = accountId,
            character_identifier = meta.character_identifier,
            type = meta.type,
            amount = delta,
            balance_after = newBalance,
            item = meta.item,
            quantity = meta.quantity,
            actor = meta.actor,
        })
    end

    return newBalance
end

local function SetCoins(accountId, amount, meta)
    if not accountId or amount < 0 then return nil, 'invalid' end
    local current = loadBalance(accountId)
    persistBalance(accountId, amount)

    if meta then
        logTransaction({
            account_id = accountId,
            character_identifier = meta.character_identifier,
            type = meta.type or 'admin_set',
            amount = amount - current,
            balance_after = amount,
            actor = meta.actor,
        })
    end
    return amount
end

exports('GetCoins', function(accountId) return loadBalance(accountId) end)
exports('AddCoins', function(accountId, amount, actor)
    return ModifyCoins(accountId, math.abs(amount), { type = 'admin_add', actor = actor })
end)
exports('RemoveCoins', function(accountId, amount, actor)
    return ModifyCoins(accountId, -math.abs(amount), { type = 'admin_remove', actor = actor })
end)
exports('SetCoins', function(accountId, amount, actor)
    return SetCoins(accountId, amount, { actor = actor })
end)

-- ============================================================
--  CACHE LIFECYCLE
-- ============================================================

RegisterNetEvent('esx:playerLoaded', function(playerId, xPlayer)
    loadBalance(getAccountId(xPlayer.identifier))
end)

AddEventHandler('playerDropped', function()
    local src = source
    local accountId = getAccountIdFromSource(src)
    if not accountId then return end
    for _, playerId in ipairs(GetPlayers()) do
        if tonumber(playerId) ~= src then
            local other = ESX.GetPlayerFromId(tonumber(playerId))
            if other and getAccountId(other.identifier) == accountId then
                return
            end
        end
    end
    balances[accountId] = nil
end)

CreateThread(function()
    Wait(500)
    loadCatalog()
end)

-- ============================================================
--  PLAYER CALLBACKS
-- ============================================================

lib.callback.register('rc_coin_shop:getShop', function(source)
    local accountId = getAccountIdFromSource(source)
    if not accountId then
        print(('[rc_coin_shop] getShop: no ESX player for source %s'):format(source))
        return false
    end

    local ok, balance = pcall(loadBalance, accountId)
    if not ok then
        print(('[rc_coin_shop] getShop: DB error for account %s -> %s'):format(accountId, balance))
        print('[rc_coin_shop] Did you import sql/coin_shop.sql?')
        return false
    end

    return {
        balance = balance,
        currency = Config.CurrencyName,
        title = Config.ShopTitle,
        maxQuantity = Config.MaxPurchaseQuantity,
        isAdmin = isAdmin(source),
        items = catalogList(true),
        branding = Config.Branding,
    }
end)

lib.callback.register('rc_coin_shop:purchase', function(source, itemName, quantity)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return { success = false, message = 'Player not found.' } end

    -- Find the catalog row by name (enabled only).
    local entry
    for _, row in pairs(items) do
        if row.name == itemName and (row.enabled == 1 or row.enabled == true) then
            entry = row
            break
        end
    end
    if not entry then
        return { success = false, message = 'That item is not for sale.' }
    end

    quantity = tonumber(quantity)
    if not quantity or quantity < 1 or quantity % 1 ~= 0 then
        return { success = false, message = 'Invalid quantity.' }
    end
    if quantity > Config.MaxPurchaseQuantity then
        return { success = false, message = ('Maximum %s per purchase.'):format(Config.MaxPurchaseQuantity) }
    end

    local accountId = getAccountId(xPlayer.identifier)
    local total = entry.price * quantity
    local balance = loadBalance(accountId)

    if balance < total then
        return { success = false, message = ('Not enough %s. Need %d, you have %d.'):format(
            Config.CurrencyName, total, balance), balance = balance }
    end

    if not exports.ox_inventory:CanCarryItem(source, itemName, quantity) then
        return { success = false, message = 'You can\'t carry that many.', balance = balance }
    end

    local added = exports.ox_inventory:AddItem(source, itemName, quantity)
    if not added then
        return { success = false, message = 'Failed to add item to inventory.', balance = balance }
    end

    local newBalance = ModifyCoins(accountId, -total, {
        type = 'purchase',
        character_identifier = xPlayer.identifier,
        item = itemName,
        quantity = quantity,
        actor = GetPlayerName(source),
    })

    return {
        success = true,
        message = ('Purchased %dx %s for %d %s.'):format(quantity, resolveLabel(entry), total, Config.CurrencyName),
        balance = newBalance,
    }
end)

-- ============================================================
--  ADMIN CALLBACKS (ACE gated, server-enforced)
-- ============================================================

-- Full catalog (incl. disabled) + the ox_inventory item list for the picker.
lib.callback.register('rc_coin_shop:admin:getItems', function(source)
    if not isAdmin(source) then return false end

    local oxList = {}
    for name, data in pairs(oxItems()) do
        oxList[#oxList + 1] = { name = name, label = data.label or name }
    end
    table.sort(oxList, function(a, b) return a.name < b.name end)

    return { items = catalogList(false), oxItems = oxList }
end)

-- Create or update an item. data = { id?, name, label, price, category, description, image, enabled, sort_order }
lib.callback.register('rc_coin_shop:admin:saveItem', function(source, data)
    if not isAdmin(source) then return { success = false, message = 'No permission.' } end
    if type(data) ~= 'table' then return { success = false, message = 'Invalid data.' } end

    local name = tostring(data.name or ''):gsub('%s', '')
    local price = tonumber(data.price)
    if name == '' then return { success = false, message = 'Item name is required.' } end
    if not price or price < 0 then return { success = false, message = 'Price must be 0 or greater.' } end
    if not oxItems()[name] then
        return { success = false, message = ('"%s" is not a registered ox_inventory item.'):format(name) }
    end

    local label = (data.label and data.label ~= '') and data.label or nil
    local category = (data.category and data.category ~= '') and data.category or nil
    local description = (data.description and data.description ~= '') and data.description or nil
    local image = (data.image and data.image ~= '') and data.image or nil
    local enabled = (data.enabled == false) and 0 or 1
    local sortOrder = tonumber(data.sort_order) or 0

    if data.id then
        MySQL.update.await([[
            UPDATE coin_shop_items
            SET name=?, label=?, price=?, category=?, description=?, image=?, enabled=?, sort_order=?
            WHERE id=?
        ]], { name, label, math.floor(price), category, description, image, enabled, sortOrder, data.id })
    else
        -- Reject duplicate item name.
        local exists = MySQL.scalar.await('SELECT id FROM coin_shop_items WHERE name = ?', { name })
        if exists then
            return { success = false, message = ('"%s" is already in the catalog.'):format(name) }
        end
        MySQL.insert.await([[
            INSERT INTO coin_shop_items (name, label, price, category, description, image, enabled, sort_order)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ]], { name, label, math.floor(price), category, description, image, enabled, sortOrder })
    end

    loadCatalog()
    return { success = true, message = 'Item saved.', items = catalogList(false) }
end)

lib.callback.register('rc_coin_shop:admin:deleteItem', function(source, id)
    if not isAdmin(source) then return { success = false, message = 'No permission.' } end
    id = tonumber(id)
    if not id then return { success = false, message = 'Invalid item.' } end

    MySQL.update.await('DELETE FROM coin_shop_items WHERE id = ?', { id })
    loadCatalog()
    return { success = true, message = 'Item removed.', items = catalogList(false) }
end)

-- Online players (for the coin manager), with balances. Optional name/id filter.
lib.callback.register('rc_coin_shop:admin:getPlayers', function(source, search)
    if not isAdmin(source) then return false end
    search = search and tostring(search):lower() or ''

    local list = {}
    for _, playerId in ipairs(GetPlayers()) do
        local sid = tonumber(playerId)
        local xPlayer = ESX.GetPlayerFromId(sid)
        if xPlayer then
            local name = GetPlayerName(sid) or ('Player %s'):format(sid)
            if search == '' or tostring(sid) == search or name:lower():find(search, 1, true) then
                local accountId = getAccountId(xPlayer.identifier)
                list[#list + 1] = {
                    id = sid,
                    name = name,
                    character = xPlayer.getName and xPlayer.getName() or nil,
                    identifier = xPlayer.identifier,
                    balance = loadBalance(accountId),
                }
            end
        end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end)

-- ============================================================
--  UNIFIED COIN MODIFICATION (shared by UI + commands)
-- ============================================================

-- Resolve a target argument: a server id (online) or a raw identifier/account id.
local function resolveTarget(arg)
    local asId = tonumber(arg)
    if asId then
        local xTarget = ESX.GetPlayerFromId(asId)
        if xTarget then
            return getAccountId(xTarget.identifier), GetPlayerName(asId)
        end
        return nil, nil
    end
    if type(arg) == 'string' and arg ~= '' then
        return getAccountId(arg), arg
    end
    return nil, nil
end

-- mode = 'add' | 'remove' | 'set'. Returns ok(bool), message(string), newBalance(int|nil)
local function doModify(actorName, target, mode, amount)
    local accountId, name = resolveTarget(target)
    amount = tonumber(amount)
    if not accountId then return false, 'Target not found.' end
    if not amount or amount < 0 or amount % 1 ~= 0 then return false, 'Amount must be a whole number ≥ 0.' end
    amount = math.floor(amount)

    local newBalance
    if mode == 'add' then
        newBalance = ModifyCoins(accountId, amount, { type = 'admin_add', actor = actorName })
    elseif mode == 'remove' then
        newBalance = ModifyCoins(accountId, -amount, { type = 'admin_remove', actor = actorName })
        if not newBalance then -- clamp to zero rather than refusing
            newBalance = SetCoins(accountId, 0, { type = 'admin_remove', actor = actorName })
        end
    elseif mode == 'set' then
        newBalance = SetCoins(accountId, amount, { actor = actorName })
    else
        return false, 'Invalid mode.'
    end

    if not newBalance then return false, 'Failed to modify coins.' end
    return true, ('%s now has %d %s.'):format(name or accountId, newBalance, Config.CurrencyName), newBalance
end

-- UI entry point.
lib.callback.register('rc_coin_shop:admin:modifyCoins', function(source, payload)
    if not isAdmin(source) then return { success = false, message = 'No permission.' } end
    if type(payload) ~= 'table' then return { success = false, message = 'Invalid data.' } end

    local actorName = source == 0 and 'console' or ('%s (%s)'):format(GetPlayerName(source), source)
    local ok, message = doModify(actorName, payload.target, payload.mode, payload.amount)
    return { success = ok, message = message }
end)

-- ============================================================
--  ADMIN COMMANDS (ACE gated)
-- ============================================================

local function adminName(src)
    return src == 0 and 'console' or ('%s (%s)'):format(GetPlayerName(src), src)
end

local function coinCommand(mode, usage)
    return function(src, args)
        if not isAdmin(src) then return toast(src, 'error', 'No permission.') end
        if not args[1] or not args[2] then return toast(src, 'error', usage) end
        local ok, message = doModify(adminName(src), args[1], mode, args[2])
        toast(src, ok and 'success' or 'error', message)
    end
end

RegisterCommand('addcoins', coinCommand('add', 'Usage: /addcoins [id|identifier] [amount]'), false)
RegisterCommand('removecoins', coinCommand('remove', 'Usage: /removecoins [id|identifier] [amount]'), false)
RegisterCommand('setcoins', coinCommand('set', 'Usage: /setcoins [id|identifier] [amount]'), false)

RegisterCommand('checkcoins', function(src, args)
    if not isAdmin(src) then return toast(src, 'error', 'No permission.') end
    local accountId, name = resolveTarget(args[1])
    if not accountId then return toast(src, 'error', 'Usage: /checkcoins [id|identifier]') end
    toast(src, 'inform', ('%s has %d %s.'):format(name or accountId, loadBalance(accountId), Config.CurrencyName))
end, false)
