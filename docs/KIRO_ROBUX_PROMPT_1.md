# Task for Kiro — Robux purchases, round 1: purchase backend + Robux shop

Project: Roblox garage tycoon, Rojo 7.7, Luau `--!strict`. Read `docs/CONTRACT.md` first.
src/shared → ReplicatedStorage.Shared, src/server → ServerScriptService.Server, src/client → StarterPlayerScripts.Client.
All UI is built in code (no StarterGui). Reply in your report what you changed per file, and anything you could not do.

Round 2 (later, separate prompt) adds Robux-only cosmetics and storefront decorations. In this round, build the
backend so round 2 can plug new product kinds in without rewriting it (see §1.3 "grant handlers").

## Rules
- No secrets, no HTTP. The server owns every price and every grant; the client only sends ids / prompts purchases.
- `MarketplaceService.ProcessReceipt` is assigned in exactly ONE place (the new PurchaseService).
- Every id in config may be `0` = not created yet → the item is hidden in the shop (same convention as `Config/GamePasses.luau`).
- Every user-facing string goes through `Config/StringsUI.luau`, in BOTH `th` and `en`.
- Do not change `Game.STARTING_MONEY` (it is temporarily 1,000,000 for testing; the user reverts it).
- Follow existing patterns: services have `init`/`start` and are listed in the ORDER table in `src/server/Main.server.luau`;
  client controllers in `src/client/Controllers/` auto-load and must expose `start()`; UI uses `src/client/Theme.luau`
  (`Theme.modal`, `Theme.button`, `Theme.label`, `Theme.colors`, ...) and `Localizer.bind` / `Localizer.t`.
- Mutate player data only through `PlayerData.update(player, fn)` / `PlayerData.addMoney`.

## 1. Server

### 1.1 `src/shared/Config/Products.luau` (new)
```lua
return {
  -- Studio only: products/passes with id 0 are still shown, and buying them runs the real grant code through
  -- the DebugPurchase remote instead of MarketplaceService (so everything is testable before ids exist).
  DEBUG_FAKE_IN_STUDIO = true,

  CashPacks = {   -- amount = max(minimum, floor(incomePerMinute * minutes)), rounded (see 1.4)
    { key = "CashS",  id = 0, robux = 25,  minutes = 10,  minimum = 5000 },
    { key = "CashM",  id = 0, robux = 75,  minutes = 35,  minimum = 20000 },
    { key = "CashL",  id = 0, robux = 200, minutes = 100, minimum = 60000 },
    { key = "CashXL", id = 0, robux = 500, minutes = 280, minimum = 180000 },
  },
  Boosts = {
    { key = "Boost2x", id = 0, robux = 35, minutes = 15, mult = 2 },  -- stacks: buying again adds time
  },
  Instant = {
    { key = "InstantRepair", id = 0, robux = 15 },  -- finishes every repair in progress
  },
}
```
`robux` is only a fallback label; the real price shown comes from `MarketplaceService:GetProductInfo(id, Enum.InfoType.Product).PriceInRobux` (client, cached, pcall).
Build `byKey` and `byId` lookups at the bottom of the module.

### 1.2 `Config/GamePasses.luau`
Keep DoubleMoney, AutoCollect, FastStaff. Add `VIP = { id = 0, dailyMult = 1.5 }` and put it in `order`.
VIP effects: daily reward x `dailyMult` (`DailyService`), and a gold "VIP" BillboardGui above the owner's head (server
adds it on CharacterAdded; small, AlwaysOnTop=false, MaxDistance ~60). Also apply `FastStaff` in `OfflineService`'s
staff-speed estimate (it is applied live in `RepairService` but missing offline).
In Studio with `DEBUG_FAKE_IN_STUDIO`, passes with id 0 are shown too and the fake purchase sets the in-memory
ownership in GamePassService (not saved) — add `GamePassService.debugGrant(player, key)`.

### 1.3 `src/server/Services/PurchaseService.luau` (new, add to Main ORDER after GamePassService)
- `PurchaseService.registerKind(kind, handler)` where handler is `(player, data, entry) -> (ok: boolean, notifyKey: string?, args: {any}?)`.
  It runs INSIDE `PlayerData.update`, so it must only mutate `data` (plus call side-effect services after). Round 1 kinds:
  `cash`, `boost`, `instantRepair`. Map every product in `Config/Products` to its kind when building the lookup.
- `ProcessReceipt(receiptInfo)`:
  1. `player = Players:GetPlayerByUserId(receiptInfo.PlayerId)`; if nil or `PlayerData.get(player)` is nil (not loaded) → `NotProcessedYet`.
  2. Unknown ProductId → warn and `NotProcessedYet`.
  3. If `data.receipts[receiptInfo.PurchaseId]` exists → `PurchaseGranted` (already given).
  4. In one `PlayerData.update`: run the grant handler, then store `data.receipts[PurchaseId] = os.time()`.
     Prune `receipts` to the newest 200 entries.
  5. `PlayerData.saveNow(player)` (new, see 1.6). If it returns false → `NotProcessedYet` (Roblox retries; step 3
     then returns Granted because the receipt is in memory; if the server dies, the save never happened so the
     retry on another server grants again — this is correct).
  6. Success → fire `Notify` (key from the handler, e.g. `notify_cash_bought` with the formatted amount),
     an `Effect` (reuse the purchase/coin effect used elsewhere), `SoundFx` "purchase" on the client side as other
     purchases do, and return `PurchaseGranted`.
  Wrap the whole thing in pcall; on error → `NotProcessedYet`.
- Remote `DebugPurchase` (RemoteEvent, args: `key: string`): accepted ONLY if `RunService:IsStudio()` and
  `Products.DEBUG_FAKE_IN_STUDIO`. Runs steps 4–6 with a fake PurchaseId `"debug-" .. os.clock()`; for a pass key
  calls `GamePassService.debugGrant`.

### 1.4 Grant handlers
- **cash**: `amount = max(minimum, floor(incomePerMinute * minutes))`, rounded to 2 significant digits
  (e.g. 12,437 → 12,000). `incomePerMinute` = `OfflineService.estimatePerSecond(player) * 60 * EconomyService.multiplier(player)`
  (expose `estimatePerSecond`; it is currently local). Add to wallet with `data.money += amount` and `totalEarned`
  is NOT increased (it is bought, not earned). Also export the current amounts to the client: snapshot field
  `cashPacks = { CashS = n, ... }`, recomputed at most every 20 s per player (cache), so the shop can show "+$12,000".
- **boost**: `data.boostUntil = math.max(data.boostUntil, os.time()) + minutes * 60`.
  `EconomyService.multiplier(player)` multiplies in `mult` while `os.time() < boostUntil` (live income + daily only).
  `OfflineService` must NOT include the boost: add an optional `excludeBoost` arg to `multiplier` and pass it there.
  Snapshot: `boostEndsAt = data.boostUntil` and `serverTime = os.time()` so the client can count down.
  `snapshot.multiplier` already drives the HUD badge — it must reflect the boost while active; when the boost
  ends, push a snapshot (a `task.delay` until expiry, guarded against stale timers).
- **instantRepair**: add `RepairService.finishAll(player): number` that completes every active job of that player
  through the existing `finish(job)` path (so pay, stars, effects all happen normally). If it returns 0 (nothing was
  being repaired) the purchase is still granted but give the CashS amount instead and notify
  `notify_instant_repair_none`. The client shop disables this button when the snapshot says nothing is repairing:
  add snapshot field `repairsActive: number` (pushed when a job starts / finishes).

### 1.5 PlayerData fields (add to the `Data` type and `defaultData`; `reconcile` fills them for old saves)
`receipts = {}` (map PurchaseId → os.time), `boostUntil = 0`.

### 1.6 `PlayerData.saveNow(player): boolean`
Synchronous save of the profile (reuse `save`, but return whether it succeeded; return false if `canSave` is false
or there is no DataStore — EXCEPT in Studio without API access, where it returns true so testing works).

## 2. Client

### 2.1 Shop (`src/client/Controllers/Shop.luau`, rewrite)
- Always available (remove the early return when no pass is configured; HUD's 🛒 button is always visible —
  update `HUD.luau` `anyGamePass()` usage). In live games, hide rows whose id is 0; in Studio with
  `DEBUG_FAKE_IN_STUDIO` show them with a small "TEST" tag.
- `Theme.modal` ~ 640 × 560 (scale with `Theme.isCompact` like other modals). Tabs across the top:
  **แพ็กเงิน / Cash**, **บูสต์ / Boosts**, **Game Pass**. (Round 2 will add "Special" and "Storefront" tabs:
  build tabs from a list so adding one is one entry.) Remember the last tab during the session.
- Card grid (2 columns, 1 on compact): icon/emoji, name, description, value line, price button.
  - Cash card value: `+$12K` from `snapshot.cashPacks[key]` (`Format.money`). Bigger packs get a ribbon
    ("ยอดนิยม" on M, "คุ้มสุด" on XL).
  - Boost card: shows remaining time when active ("เหลือ 12:34").
  - Instant repair: disabled + hint when `repairsActive == 0`.
  - Pass cards: "มีแล้ว / Owned" badge when owned (from `snapshot.gamepasses`), button hidden.
  - Price button: Robux glyph `utf8.char(0xE002)` + price, green.
- Click → `MarketplaceService:PromptProductPurchase(player, id)` / `PromptGamePassPurchase`, or in Studio with id 0
  → `Remotes.get("DebugPurchase"):FireServer(key)`. Debounce 1 s per button.
- Keep the `OpenUI("Shop", tab?)` hook; the optional arg selects the tab.

### 2.2 HUD
- The multiplier badge (`setMultiplier`) shows a countdown under "x2" while a boost is active
  (computed from `boostEndsAt - serverTime` offset by local clock). Tapping the badge opens the Shop on the Boost tab.
- When money is not enough for something (the existing `notify_not_enough_money` toast), add a small "เติมเงิน / Get cash"
  button on that toast that opens the Shop on the Cash tab. If the Notifications controller can't take buttons easily,
  skip this and say so in the report.

### 2.3 Strings (th + en) — at least
`shop_tab_cash, shop_tab_boost, shop_tab_pass, shop_cash_S..XL (names), shop_cash_desc, shop_popular, shop_best_value,
shop_boost_name, shop_boost_desc, shop_boost_left, shop_instant_name, shop_instant_desc, shop_instant_none,
pass_VIP, pass_VIP_desc, notify_cash_bought, notify_boost_bought, notify_instant_done, notify_instant_repair_none,
shop_test_tag, notify_get_cash`. Thai text natural and short (mobile).

## 3. Docs
- Update `docs/CONTRACT.md`: new remote `DebugPurchase`, snapshot fields `cashPacks, boostEndsAt, serverTime,
  repairsActive`, Data fields `receipts, boostUntil`, PurchaseService.
- Update `docs/TODO.md`: "Create Developer Products CashS/M/L/XL, Boost2x, InstantRepair and Game Pass VIP on Creator
  Hub; paste ids into Config/Products.luau and Config/GamePasses.luau".

## 4. Test checklist (Studio, Play solo) — report results
1. Shop opens from 🛒, all tabs render, compact (phone) layout fits.
2. Buy each cash pack via the TEST path → money increases by the shown amount, toast shows.
3. Buy Boost twice → badge shows x2 with ~30:00 countdown; income doubles; offline estimate ignores it.
4. Instant repair with a car in a bay → finishes and pays; with no car → button disabled.
5. Buy VIP (TEST) → gold tag above head, daily reward x1.5.
6. Rejoin (with API access on) → receipts and boostUntil persisted; no error spam in output.
