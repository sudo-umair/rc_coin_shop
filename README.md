# rc_coin_shop

An ESX Legacy in-game shop where players buy **ox_inventory** items using **coins**, with a fully **custom NUI** (Royal City gold/dark theme) for both players and admins. ox_lib is used only as the client↔server transport — all visuals are custom.

## Features

- 🪙 **Coin currency** stored in a dedicated DB table, shared **per account** (all of a player's characters share one balance).
- 🛒 **Custom shop UI** opened with a **rebindable keybind** (default `F5`) or `/coinshop` — searchable, category-filtered item grid with quantity selection and live total cost.
- 🛠️ **Admin tab (in the same UI)** — visible only to ACE-verified admins:
  - **Manage Items:** add / edit / remove catalog items at runtime (DB-driven), pick the item from an ox_inventory autocomplete, set price, label/category/description/image overrides, enable/disable, and sort order.
  - **Manage Coins:** search **all registered players** (online and offline) with their balances and known identifiers (Steam, Discord, FiveM, license…), and add / remove / set coins — or target any server id / identifier manually. Online players show full live identifiers; offline players show whatever was captured the last time they joined.
- 🔢 **Server-enforced validation** — purchases check the catalog, balance, and inventory space; all admin actions re-check ACE server-side.
- 🛡️ **Admin coin commands** as well as the UI: `/addcoins /removecoins /setcoins /checkcoins`.
- 📝 **Logging** to server console, a `coin_shop_transactions` audit table, and rich Discord embeds — purchases and admin coin changes route to separate webhooks, with per-event colours and an optional @mention of the involved player. Delivery is queued and rate-limit (429) aware.
- 🧾 **Identifier capture** — every player's identifiers are recorded on join into `coin_shop_identifiers`, so the admin coin manager can show Steam/Discord/etc. even for offline players.

> The catalog lives in the `coin_shop_items` table and starts **empty** — build it from the Admin → Manage Items tab. Labels and images default to ox_inventory unless you override them.

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
   (Already running an older version? Re-import the file — it's idempotent and adds the new `coin_shop_identifiers` table.)
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
5. Configure the keybind, currency name, branding, and logging in `config.lua`. The item catalog is managed in-game (no config editing needed).

## Usage

### Players
- Press **F5** (rebind under *Settings → Key Bindings → FiveM → "Open Coin Shop"*) or type `/coinshop`.
- Browse/search items, click **Buy**, choose a quantity, confirm. Coins are deducted and the item is added to your inventory.

### Admins (UI)
- Open the shop and click the **Admin** tab (only shown if you have the ACE permission).
- **Manage Items** — add new items (type/select an ox_inventory item, set price + optional overrides), edit or delete existing ones, toggle visibility, reorder.
- **Manage Coins** — search online players and add/remove/set their balance, or type any server id / identifier into the Target field.

### Players (commands)
| Command | Description |
|---|---|
| `/coinshop` | Open the shop UI. Also bound to a rebindable keybind (default **F5**, set via `Config.OpenKey`) under *Settings → Key Bindings → FiveM → "Open Coin Shop"*. |

### Admins (commands)
ACE-gated by `Config.AcePermission` (`coin_shop.admin`). Also runnable from the server console.

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
