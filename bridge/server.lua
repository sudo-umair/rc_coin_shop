-----------------------------------------------------------------------------
-- Framework bridge — uniform player API over ESX and QBCore
--
-- Exposes (server-side global):
--   Bridge.Framework                 -> 'esx' | 'qb' | 'none'
--   Bridge.GetAccountIdentifier(src) -> account-wide identifier or nil
--                                       (ESX: xPlayer.identifier, QB: license)
--   Bridge.GetCharacterIdentifier(src) -> per-character identifier or nil
--                                       (ESX: xPlayer.identifier, QB: citizenid)
--   Bridge.GetCharacterName(src)     -> RP character name or nil
--   Bridge.OnPlayerLoaded(cb)        -> cb(playerId) when a character loads
--   Bridge.GetAllCharacters()        -> { { identifier, firstname, lastname }, ... }
--                                       every registered character in the DB
-----------------------------------------------------------------------------

Bridge = {
    Framework = 'none',
}

local ESX, QBCore

local function tryDetectFramework()
    local wantEsx = Config.Framework == 'esx' or Config.Framework == 'auto'
    local wantQb  = Config.Framework == 'qb' or Config.Framework == 'auto'

    if wantEsx and GetResourceState('es_extended') == 'started' then
        ESX = exports['es_extended']:getSharedObject()
        Bridge.Framework = 'esx'
        return true
    end

    if wantQb and GetResourceState('qb-core') == 'started' then
        QBCore = exports['qb-core']:GetCoreObject()
        Bridge.Framework = 'qb'
        return true
    end

    return false
end

-- the framework may start after rc_coin_shop — keep retrying for a while
CreateThread(function()
    for _ = 1, 60 do
        if tryDetectFramework() then
            print(('[rc_coin_shop] framework: %s'):format(Bridge.Framework))
            return
        end
        Wait(1000)
    end
    print('[rc_coin_shop] WARNING: no framework detected — the shop cannot resolve player accounts')
end)

-----------------------------------------------------------------------------

-- Account-wide identifier: shared by all of a player's characters, so coin
-- balances follow the account. The multichar prefix (char1:...) is stripped
-- by the caller.
function Bridge.GetAccountIdentifier(src)
    if Bridge.Framework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(src)
        return xPlayer and xPlayer.identifier or nil
    elseif Bridge.Framework == 'qb' then
        local player = QBCore.Functions.GetPlayer(src)
        return player and player.PlayerData.license or nil
    end
    return nil
end

-- Per-character identifier, used for transaction logging.
function Bridge.GetCharacterIdentifier(src)
    if Bridge.Framework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(src)
        return xPlayer and xPlayer.identifier or nil
    elseif Bridge.Framework == 'qb' then
        local player = QBCore.Functions.GetPlayer(src)
        return player and player.PlayerData.citizenid or nil
    end
    return nil
end

function Bridge.GetCharacterName(src)
    if Bridge.Framework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer and xPlayer.getName then
            return xPlayer.getName()
        end
    elseif Bridge.Framework == 'qb' then
        local player = QBCore.Functions.GetPlayer(src)
        if player then
            local info = player.PlayerData.charinfo
            return ('%s %s'):format(info.firstname, info.lastname)
        end
    end
    return nil
end

-- Both frameworks trigger their loaded event server-side, so plain
-- AddEventHandler is enough (and clients can't spoof it).
function Bridge.OnPlayerLoaded(cb)
    AddEventHandler('esx:playerLoaded', function(playerId)
        cb(playerId)
    end)
    AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
        cb(player.PlayerData.source)
    end)
end

-- Every registered character from the framework's own table, for the offline
-- part of the admin player list. Returns {} when the query fails (e.g. the
-- framework tables live in another database).
function Bridge.GetAllCharacters()
    if Bridge.Framework == 'esx' then
        local ok, rows = pcall(MySQL.query.await, 'SELECT identifier, firstname, lastname FROM users')
        if ok and rows then return rows end
    elseif Bridge.Framework == 'qb' then
        local ok, rows = pcall(MySQL.query.await, 'SELECT license, charinfo FROM players')
        if ok and rows then
            local out = {}
            for _, r in ipairs(rows) do
                local info = r.charinfo and json.decode(r.charinfo) or {}
                out[#out + 1] = {
                    identifier = r.license,
                    firstname  = info.firstname,
                    lastname   = info.lastname,
                }
            end
            return out
        end
    end
    return {}
end
