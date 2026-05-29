local isOpen = false

local function openShop()
    if isOpen then return end

    local data = lib.callback.await('rc_coin_shop:getShop', false)
    if not data then
        SendNUIMessage({ action = 'toast', data = { type = 'error', message = 'Shop unavailable.' } })
        return
    end

    isOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = data })
end

local function closeShop()
    if not isOpen then return end
    isOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

-- ============================================================
--  NUI -> client bridge
--  Each callback forwards to the server and returns the result to the UI.
-- ============================================================

RegisterNUICallback('close', function(_, cb)
    closeShop()
    cb('ok')
end)

RegisterNUICallback('purchase', function(data, cb)
    local result = lib.callback.await('rc_coin_shop:purchase', false, data.name, data.quantity)
    cb(result or { success = false, message = 'Request failed.' })
end)

RegisterNUICallback('admin:getItems', function(_, cb)
    cb(lib.callback.await('rc_coin_shop:admin:getItems', false) or false)
end)

RegisterNUICallback('admin:saveItem', function(data, cb)
    cb(lib.callback.await('rc_coin_shop:admin:saveItem', false, data) or { success = false, message = 'Request failed.' })
end)

RegisterNUICallback('admin:deleteItem', function(data, cb)
    cb(lib.callback.await('rc_coin_shop:admin:deleteItem', false, data.id) or { success = false, message = 'Request failed.' })
end)

RegisterNUICallback('admin:getPlayers', function(data, cb)
    cb(lib.callback.await('rc_coin_shop:admin:getPlayers', false, data.search) or false)
end)

RegisterNUICallback('admin:modifyCoins', function(data, cb)
    cb(lib.callback.await('rc_coin_shop:admin:modifyCoins', false, data) or { success = false, message = 'Request failed.' })
end)

-- ============================================================
--  server -> client (toasts + live balance refresh)
-- ============================================================

RegisterNetEvent('rc_coin_shop:toast', function(kind, message)
    SendNUIMessage({ action = 'toast', data = { type = kind, message = message } })
end)

RegisterNetEvent('rc_coin_shop:balanceUpdate', function(balance)
    SendNUIMessage({ action = 'setBalance', data = { balance = balance } })
end)

-- ============================================================
--  open command + rebindable keybind
--  The mapping appears under Settings > Key Bindings > FiveM.
-- ============================================================

RegisterCommand('coinshop', function()
    openShop()
end, false)

RegisterKeyMapping('coinshop', 'Open Coin Shop', 'keyboard', Config.OpenKey)

-- Safety: release focus if the resource stops while the UI is open.
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and isOpen then
        SetNuiFocus(false, false)
    end
end)
