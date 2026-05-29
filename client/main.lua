local oxItems = exports.ox_inventory:Items()

-- Resolve an item's display label + inventory image from ox_inventory.
local function getItemDisplay(name, override)
    local data = oxItems[name]
    return {
        label = override or (data and data.label) or name,
        image = ('nui://ox_inventory/web/images/%s.png'):format(name),
    }
end

local function buyItem(entry, label)
    local input = lib.inputDialog(('Buy %s'):format(label), {
        {
            type = 'number',
            label = 'Quantity',
            description = ('%d %s each'):format(entry.price, Config.CurrencyName),
            default = 1,
            min = 1,
            max = Config.MaxPurchaseQuantity,
            required = true,
        },
    })

    if not input or not input[1] then return end
    local quantity = math.floor(tonumber(input[1]) or 0)
    if quantity < 1 then return end

    local result = lib.callback.await('coin_shop:purchase', false, entry.name, quantity)
    if not result then return end

    lib.notify({
        title = Config.ShopTitle,
        description = result.message,
        type = result.success and 'success' or 'error',
    })
end

local function openShop()
    local data = lib.callback.await('coin_shop:getData', false)
    if not data then
        return lib.notify({ title = Config.ShopTitle, description = 'Shop unavailable.', type = 'error' })
    end

    -- Group items by category (items with no category go under "General").
    local groups, order = {}, {}
    for _, entry in ipairs(data.items) do
        local cat = entry.category or 'General'
        if not groups[cat] then
            groups[cat] = {}
            order[#order + 1] = cat
        end
        groups[cat][#groups[cat] + 1] = entry
    end

    local options = {
        {
            title = ('Balance: %d %s'):format(data.balance, data.currency),
            icon = 'coins',
            readOnly = true,
        },
    }

    for _, cat in ipairs(order) do
        for _, entry in ipairs(groups[cat]) do
            local display = getItemDisplay(entry.name, entry.label)
            options[#options + 1] = {
                title = display.label,
                description = ('%d %s each  •  %s'):format(entry.price, data.currency, cat),
                image = display.image,
                onSelect = function() buyItem(entry, display.label) end,
            }
        end
    end

    lib.registerContext({
        id = 'coin_shop_menu',
        title = ('%s'):format(Config.ShopTitle),
        options = options,
    })
    lib.showContext('coin_shop_menu')
end

-- Command + rebindable keybind. The mapping appears under
-- Settings > Key Bindings > FiveM so players can change it.
RegisterCommand('coinshop', function()
    openShop()
end, false)

RegisterKeyMapping('coinshop', 'Open Coin Shop', 'keyboard', Config.OpenKey)
