# rc_coin_shop

An ESX Legacy in-game shop where players buy **ox_inventory** items using **coins**, with admin commands to manage balances. Built on **ox_lib** for the UI.

## Features

- 🪙 **Coin currency** stored in a dedicated DB table, shared **per account** (all of a player's characters share one balance).
- 🛒 **Shop menu** opened with a **rebindable keybind** (default `F5`) or `/coinshop`. Item labels and images are pulled automatically from ox_inventory.
- 🔢 **Quantity selection** with live total-cost validation against balance and inventory space.
- 🛡️ **ACE-gated admin commands** to add/remove/set/check coins.
- 📝 **Logging** to server console, a Discord webhook, and a `coin_shop_transactions` audit table.

## Dependencies

- `es_extended` (ESX Legacy)
- `ox_lib`
- `ox_inventory`
- `oxmysql`

## Installation

1. Drop the `rc_coin_shop` folder into your `resources`.
2. Import the database schema:
   ```sql
   -- sql/coin_shop.sql
   ```
3. Add to `server.cfg`:
   ```cfg
   ensure rc_coin_shop
   ```
4. Grant the admin permission to whoever should manage coins:
   ```cfg
   add_ace group.admin coin_shop.admin allow
   add_principal identifier.fivem:1234567 group.admin
   ```
   (Or assign the principal that txAdmin / your admin group already uses.)
5. Configure items, prices, the keybind, and logging in `config.lua`.

## Usage

### Players
- Press **F5** (rebind under *Settings → Key Bindings → FiveM → "Open Coin Shop"*) or type `/coinshop`.
- Pick an item, enter a quantity, confirm. Coins are deducted and the item is added to your inventory.

### Admins
| Command | Description |
|---|---|
| `/addcoins [id\|identifier] [amount]` | Add coins to a player. |
| `/removecoins [id\|identifier] [amount]` | Remove coins (clamps at 0). |
| `/setcoins [id\|identifier] [amount]` | Set an exact balance. |
| `/checkcoins [id\|identifier]` | Show a player's balance. |

`id` is the online server ID; `identifier` can be a raw license or a `charN:` identifier (the character prefix is stripped automatically since balances are account-wide).

## Exports (server)

```lua
exports.rc_coin_shop:GetCoins(accountId)              -- returns balance
exports.rc_coin_shop:AddCoins(accountId, amount, actor)
exports.rc_coin_shop:RemoveCoins(accountId, amount, actor)
exports.rc_coin_shop:SetCoins(accountId, amount, actor)
```

`accountId` is the license hex (the part after `charN:`). Strip the prefix from an ESX identifier with `identifier:gsub('^char%d+:', '')`.
