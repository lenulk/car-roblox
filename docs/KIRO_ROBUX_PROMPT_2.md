# Task for Kiro — Robux purchases, round 2: Robux-only items + storefront decorations

Do this ONLY after round 1 (`docs/KIRO_ROBUX_PROMPT_1.md`) is merged: it relies on `Config/Products.luau`,
`PurchaseService.registerKind`, `DebugPurchase`, and the tabbed Shop. Same rules as round 1 (strict Luau, server owns
prices and grants, id 0 = hidden except the Studio TEST path, all strings th + en, no change to `STARTING_MONEY`).
Report what you changed per file and anything you could not do.

## 1. One-time Robux items (new product kind `unlock`)

Add to `Config/Products.luau`:
```lua
Items = { -- one-time: owning it already → still PurchaseGranted, notify "already owned", nothing else changes
  { key = "PaintChrome",  id = 0, robux = 49,  grant = { part = "paint:Chrome" } },
  { key = "PaintGold",    id = 0, robux = 49,  grant = { part = "paint:Gold" } },
  { key = "PaintRainbow", id = 0, robux = 49,  grant = { part = "paint:Rainbow" } },
  { key = "NeonRainbow",  id = 0, robux = 39,  grant = { part = "neon:Rainbow" } },
  { key = "SmokeGalaxy",  id = 0, robux = 39,  grant = { part = "smoke:Galaxy" } },
  { key = "ThemeGold",    id = 0, robux = 149, grant = { theme = "GoldGarage" } },
  { key = "CarHyper",     id = 0, robux = 399, grant = { car = "Hyper" } },
  { key = "StarterPack",  id = 0, robux = 49,  grant = { money = 25000, part = "paint:Gold" }, once = "starterPackBought" },
},
```
- Grant handler `unlock`: sets `data.ownedParts[...] = true`, `data.ownedThemes[...] = true`, adds the car to
  `data.cars` the same way `BuyCar` does, adds money; `once` sets a boolean Data field (add `starterPackBought = false`).
- Config entries for these items get `robuxProduct = "<key>"` and no money price:
  - `Config/Customization.luau`: options Chrome / Gold / Rainbow (paint), Rainbow (neon), Galaxy (smoke).
    Chrome = high Reflectance / Foil-like look; Gold = gold colour + metal; Rainbow paint and Rainbow neon cycle
    hue on the CLIENT (a tag/attribute on the parts + one Heartbeat loop in a client controller, only for cars
    within ~150 studs). Galaxy smoke = purple/blue particle colours with sparkle.
  - `Config/Themes.luau`: `GoldGarage` (black + gold trim, warm lights) — follow how other themes define colours.
  - `Config/PersonalCars.luau` + `CarBuilder`: `Hyper` — stats a little above `Super` (≈ +8% top speed / accel),
    a distinct low wide body with a big rear wing (build it in the CarBuilder style, reuse Super's structure).
- Server: `Customize`, `BuyTheme`, `BuyCar` must REJECT a `robuxProduct` item that is not owned
  (`return false, "notify_robux_only"`). Once owned they behave like any owned item (apply/select for free).
- Client: in Tuning (customize), Themes and the car list, Robux items show a gold border + `utf8.char(0xE002)` price
  instead of the money price; pressing buy prompts the product (or DebugPurchase in Studio). After the snapshot
  shows it owned, it works like a normal owned option.
- Shop gets a **"ของพิเศษ / Special"** tab listing all `Items` (with a preview icon/emoji and "Owned" badge).
- Starter Pack: shown in the Special tab and as a one-time popup right after the tutorial finishes (`tutorialStep`
  reaches the end) — dismissible, never shown again after purchase or after 3 dismissals (store a count in
  `settings` via `SetSetting`, or a new Data field + allow it in `onSetSetting`).

## 2. Storefront decorations (ดึงลูกค้า)

### 2.1 `src/shared/Config/Decor.luau` (new)
```lua
return {
  SLOTS = 6,
  MAX_BONUS = 0.35, -- total spawn-interval reduction cap
  items = {
    -- money
    { id = "Bunting",    price = 2000,   bonus = 0.03 },
    { id = "OpenSign",   price = 6000,   bonus = 0.04 },  -- blinking neon "OPEN"
    { id = "TubeMan",    price = 15000,  bonus = 0.06 },  -- inflatable dancing tube man
    { id = "BalloonArch",price = 30000,  bonus = 0.06 },
    { id = "ClassicStatue", price = 70000, bonus = 0.08 }, -- classic car on a plinth
    { id = "Searchlight",price = 150000, bonus = 0.08 },  -- sky beam, stands out at night
    -- Robux (also listed in Products.Items with grant = { decor = "<id>" })
    { id = "MascotBear", robuxProduct = "DecorBear",     bonus = 0.10 }, -- 99 R$
    { id = "MechRobot",  robuxProduct = "DecorRobot",    bonus = 0.10 }, -- 149 R$
    { id = "NeonDragon", robuxProduct = "DecorDragon",   bonus = 0.12 }, -- 199 R$
    { id = "GoldStatue", robuxProduct = "DecorGold",     bonus = 0.12 }, -- 249 R$
    { id = "Fireworks",  robuxProduct = "DecorFireworks",bonus = 0.08 }, -- 129 R$
  },
}
```
Add the 5 Robux products to `Products.Items` (`grant = { decor = id }`).

### 2.2 Data + server (`src/server/Services/DecorService.luau`, new, in Main ORDER after UnlockService)
- Data: `decorOwned = {}` (id → true), `decorPlaced = {}` (slot number as string "1".."6" → id; string keys so
  `reconcile`/DataStore handle it as a map).
- Remotes (RemoteFunction, return `(ok, messageKey)`): `BuyDecor(id)` (money items only; Robux ones are prompted),
  `PlaceDecor(slot, id?)` (id nil = remove; an item can be in only one slot — placing it elsewhere moves it).
  Validate types, ranges, ownership, busy-lock (copy the `PersonalCarService.guarded` pattern).
- Bonus: `DecorService.bonus(player) = min(MAX_BONUS, sum of bonus of PLACED items)`.
  `CustomerService.spawnInterval` multiplies by `(1 - bonus)` AFTER the existing min clamp (so 4 s can go to 2.6 s),
  and the shopper interval in `ShopService` and `OfflineService` gets the same factor. Snapshot:
  `decor = { owned = {...}, placed = {...}, bonus = n }`.
- Models: built on the SERVER inside the player's plot (so other players see them), rebuilt when placement changes
  and removed when the plot is released (`PlotService.onAssigned` / plot release). Build with Parts in the
  `MapBuilder`/`ModelKit` style, anchored, CanCollide false except a plinth. Each model has `Decor` attribute = id.
- Slots: 6 positions on the grass on both sides of the entrance road in front of the gate (`Layout.GATE`, plot local
  space), 3 per side, clear of the road, sidewalk, lamps, benches and planters already placed by MapBuilder.
  Each empty slot shows a faint outlined pad + small "+" sign; each slot has a ProximityPrompt
  "จัดหน้าร้าน / Decorate" (respect `PromptFilter` conventions so only the owner sees it).

### 2.3 Looks (make the Robux ones clearly special — cute or cool)
Animations run on the CLIENT (one controller `DecorAnimator.luau`, only for models within ~200 studs, 30 Hz):
- TubeMan: segmented body that wiggles/flops with sine waves, arms flail; bright colour.
- OpenSign: neon text blinks; Searchlight: rotating beam (Beam or tall neon part, sways).
- MascotBear (cute): big round bear in a mechanic cap and overalls, waves an arm; does a little jump + confetti
  when a car repair finishes on that plot (listen for the existing repair-done Effect/remote).
- MechRobot (cool): tall robot holding a giant wrench, glowing eyes (Neon), head turns to follow the nearest
  arriving customer car.
- NeonDragon (cool): coiled neon dragon whose colour slowly cycles; puffs of smoke from the nose every few seconds.
- GoldStatue: gold supercar on a rotating plinth with sparkle particles.
- Fireworks: launcher that fires a small firework burst each time a customer arrives at that plot.
Keep part counts modest (≤ ~60 parts per model) and particles light.

### 2.4 UI
- Prompt at a slot opens a **Decor** modal: grid of all items with icon, name, "+X% ลูกค้า" and price
  (money or R$). Owned items show "วาง / Place" (or "ย้ายมาที่นี่ / Move here" if placed elsewhere); a placed slot
  also shows "เก็บ / Remove". Header shows total bonus "ลูกค้ามาเร็วขึ้น 18% / สูงสุด 35%".
- If the plot has no Parking unlock yet and the queue is often full, show a hint line:
  "ซื้อลานจอดรถเพื่อรับลูกค้าได้มากขึ้น".
- Shop gets a **"หน้าร้าน / Storefront"** tab listing the Robux decor (buy only; placing happens at the slots).

## 3. Strings, docs
All new names/descriptions/notifications in StringsUI th + en (`decor_<id>`, `decor_<id>_desc`, `item_<key>`,
`notify_robux_only`, `notify_already_owned`, `decor_title`, `decor_bonus`, `decor_place`, `decor_move`,
`decor_remove`, `decor_hint_parking`, `shop_tab_special`, `shop_tab_storefront`, starter pack texts...).
Update `docs/CONTRACT.md` (remotes `BuyDecor`, `PlaceDecor`; snapshot `decor`; Data `decorOwned`, `decorPlaced`,
`starterPackBought`) and `docs/TODO.md` (create the new Developer Products on Creator Hub).

## 4. Test checklist (Studio) — report results
1. Each Robux item via TEST path → owned, usable; buying again → "already owned", no duplicate.
2. Robux paint can't be applied before purchase (server rejects even if the client is bypassed).
3. Rainbow paint/neon animate; Hyper drives and is a bit faster than Super.
4. Buy + place money decor in all 6 slots; bonus capped at 35%; spawn interval visibly shorter; remove/move work.
5. Robux decor animate as described; bear reacts to a finished repair, fireworks fire on arrival.
6. Rejoin → placement restored; leaving frees the plot and removes the models; no errors in output; FPS fine.
