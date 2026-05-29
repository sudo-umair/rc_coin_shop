local ESX = exports['es_extended']:getSharedObject()

-- account_id -> coins (in-memory cache for online players)
local balances = {}

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

-- Build a fast lookup of valid catalog items: name -> { price, label }
local catalog = {}
for _, entry in ipairs(Config.Items) do
    catalog[entry.name] = entry
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
            footer = { text = ('coin_shop • %s'):format(os.date('%Y-%m-%d %H:%M:%S')) },
        } },
    }), { ['Content-Type'] = 'application/json' })
end

-- type: purchase | admin_add | admin_remove | admin_set
local function logTransaction(data)
    if Config.Logging.console then
        print(('[coin_shop] %s | account=%s amount=%s balance=%s%s actor=%s'):format(
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

-- Load a balance from the cache, falling back to the DB (and creating the
-- row if missing). Returns the integer balance.
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

-- Persist a balance to the DB and update the cache.
local function persistBalance(accountId, coins)
    balances[accountId] = coins
    MySQL.prepare.await([[
        INSERT INTO coin_shop_balance (account_id, coins) VALUES (?, ?)
        ON DUPLICATE KEY UPDATE coins = VALUES(coins)
    ]], { accountId, coins })
end

-- ============================================================
--  PUBLIC API (also exported)
-- ============================================================

local function GetCoins(accountId)
    return loadBalance(accountId)
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

exports('GetCoins', GetCoins)
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
    local accountId = getAccountId(xPlayer.identifier)
    loadBalance(accountId)
end)

-- We write through on every change, so dropping just frees memory.
AddEventHandler('playerDropped', function()
    local src = source
    local accountId = getAccountIdFromSource(src)
    if not accountId then return end

    -- Only evict if no other online character shares this account.
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

-- ============================================================
--  CLIENT CALLBACKS
-- ============================================================

-- Sends the player's balance + catalog so the client can build the menu.
lib.callback.register('coin_shop:getData', function(source)
    local accountId = getAccountIdFromSource(source)
    if not accountId then return false end

    return {
        balance = loadBalance(accountId),
        currency = Config.CurrencyName,
        items = Config.Items,
    }
end)

-- Handles a purchase. Returns { success = bool, message = string, balance = int }
lib.callback.register('coin_shop:purchase', function(source, itemName, quantity)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return { success = false, message = 'Player not found.' } end

    local entry = catalog[itemName]
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

    -- Make sure the player can actually carry it before charging.
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
        message = ('Purchased %dx %s for %d %s.'):format(quantity, itemName, total, Config.CurrencyName),
        balance = newBalance,
    }
end)

-- ============================================================
--  ADMIN COMMANDS (ACE gated)
-- ============================================================

local function isAllowed(src)
    if src == 0 then return true end -- server console / txAdmin
    return IsPlayerAceAllowed(src, Config.AcePermission)
end

local function notifyAdmin(src, msg, kind)
    if src == 0 then
        print(('[coin_shop] %s'):format(msg))
    else
        TriggerClientEvent('ox_lib:notify', src, { title = 'Coin Shop', description = msg, type = kind or 'inform' })
    end
end

-- Resolve a target argument: a server id (online) or a raw identifier/account id.
-- Returns accountId, displayName.
local function resolveTarget(arg)
    local asId = tonumber(arg)
    if asId then
        local xTarget = ESX.GetPlayerFromId(asId)
        if xTarget then
            return getAccountId(xTarget.identifier), GetPlayerName(asId)
        end
        return nil, nil
    end
    -- Treat as identifier; strip char prefix if present.
    return getAccountId(arg), arg
end

local function adminName(src)
    return src == 0 and 'console' or ('%s (%s)'):format(GetPlayerName(src), src)
end

RegisterCommand('addcoins', function(src, args)
    if not isAllowed(src) then return notifyAdmin(src, 'No permission.', 'error') end
    local accountId, name = resolveTarget(args[1])
    local amount = tonumber(args[2])
    if not accountId or not amount or amount <= 0 then
        return notifyAdmin(src, 'Usage: /addcoins [id|identifier] [amount]', 'error')
    end

    local newBalance = ModifyCoins(accountId, math.floor(amount), {
        type = 'admin_add', actor = adminName(src),
    })
    notifyAdmin(src, ('Added %d %s to %s. New balance: %d.'):format(
        math.floor(amount), Config.CurrencyName, name or accountId, newBalance), 'success')
end, false)

RegisterCommand('removecoins', function(src, args)
    if not isAllowed(src) then return notifyAdmin(src, 'No permission.', 'error') end
    local accountId, name = resolveTarget(args[1])
    local amount = tonumber(args[2])
    if not accountId or not amount or amount <= 0 then
        return notifyAdmin(src, 'Usage: /removecoins [id|identifier] [amount]', 'error')
    end

    local newBalance, reason = ModifyCoins(accountId, -math.floor(amount), {
        type = 'admin_remove', actor = adminName(src),
    })
    if not newBalance then
        if reason == 'insufficient' then
            -- Clamp to zero rather than refusing.
            newBalance = SetCoins(accountId, 0, { type = 'admin_remove', actor = adminName(src) })
        else
            return notifyAdmin(src, 'Failed to remove coins.', 'error')
        end
    end
    notifyAdmin(src, ('Removed %d %s from %s. New balance: %d.'):format(
        math.floor(amount), Config.CurrencyName, name or accountId, newBalance), 'success')
end, false)

RegisterCommand('setcoins', function(src, args)
    if not isAllowed(src) then return notifyAdmin(src, 'No permission.', 'error') end
    local accountId, name = resolveTarget(args[1])
    local amount = tonumber(args[2])
    if not accountId or not amount or amount < 0 then
        return notifyAdmin(src, 'Usage: /setcoins [id|identifier] [amount]', 'error')
    end

    local newBalance = SetCoins(accountId, math.floor(amount), { actor = adminName(src) })
    notifyAdmin(src, ('Set %s balance to %d %s.'):format(
        name or accountId, newBalance, Config.CurrencyName), 'success')
end, false)

RegisterCommand('checkcoins', function(src, args)
    if not isAllowed(src) then return notifyAdmin(src, 'No permission.', 'error') end
    local accountId, name = resolveTarget(args[1])
    if not accountId then
        return notifyAdmin(src, 'Usage: /checkcoins [id|identifier]', 'error')
    end
    notifyAdmin(src, ('%s has %d %s.'):format(
        name or accountId, loadBalance(accountId), Config.CurrencyName), 'inform')
end, false)
