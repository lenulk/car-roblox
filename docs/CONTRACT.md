# Garage Tycoon — Code Contract (Phase 1)

This file is the single agreement every script follows. If code and this file disagree, fix one of them so they match.
Language: Luau, `--!strict` at the top of every file. Rojo 7.4 project (`default.project.json`).

## 1. Instance tree (Rojo)

| Path on disk | In Roblox |
|---|---|
| `src/shared/` | `ReplicatedStorage.Shared` |
| `src/server/` | `ServerScriptService.Server` |
| `src/client/` | `StarterPlayer.StarterPlayerScripts.Client` |
| (empty folder) | `ReplicatedStorage.Models` — optional art overrides, see §8 |

Require shared modules with:
```lua
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Layout = require(Shared.Layout)
local Strings = require(Shared.Config.Strings)
```

## 2. Module patterns

**Server** — every file in `src/server/Services/` is a ModuleScript returning a table with optional
`init()` (set up state, no yielding) and `start()` (connect events, spawn loops). `src/server/Main.server.luau`
requires them in a fixed order, calls every `init()`, then every `start()`. Services may `require` each other directly.

**Client** — every file in `src/client/Controllers/` is a ModuleScript returning a table with `start()`.
`src/client/Main.client.luau` requires all of them and calls `start()` on each inside `task.spawn`.
`src/client/ClientState.luau` holds the latest server snapshot: `ClientState.snapshot`, `ClientState.onChanged(fn)`, `ClientState.lang()`.

## 3. Geometry — `src/shared/Layout.luau`

Use only Layout numbers; never hard-code positions elsewhere.
- Ring road centered at origin, lane radius 95 (inner 80, outer 110). Center island radius 80.
- 4 plots. `Layout.plotCFrame(i)`; plot-local -Z faces the ring. Local footprint X -70..70, Z -60..60.
- Building X -70..70, Z -22..60, height 24, open front at Z = -22.
- `Layout.toWorld(i, localCFrame)`, `Layout.pointToWorld(i, localVector3)`.
- Car CFrames in Layout (QUEUE, BAYS[n].car) are at ground level (Y = 0) with LookVector = nose direction.
- Paths: `Layout.arrivalPath(i, q)`, `Layout.queueToBayPath(i, q, b)`, `Layout.departurePath(i, b)` return world `{Vector3}`.

## 4. Workspace naming (built by MapBuilder)

```
Workspace
  World (Folder)                 ring road, lane markings, center island, fountain, SpawnLocation, grass, lamps
  Plots (Folder)
    Plot1 .. Plot4 (Model)       attributes: PlotIndex (number), OwnerUserId (number, 0 = free; set by PlotService)
      Static (Folder)            always visible: floor, building shell, parking lot lines for queue 1-3, connector road
        Gate (Model)             arch over the entrance; contains Part "SignBoard" with SurfaceGui "SignGui" > TextLabel "OwnerLabel"
        Safe (Model)             PrimaryPart "Body"; Part "CollectPad" (8x0.4x8, Neon, CanCollide=false, on the ground in front of the safe);
                                 BillboardGui "AmountGui" (on Body) > TextLabel "AmountLabel"
        HireBoard (Model)        PrimaryPart "Board" (the notice board on the back wall)
      Unlockables (Folder)       one Model per unlock id (Bay2, Cashier, Shelf1, Parking ...). Bay1 also lives here.
      Buttons (Folder)           one Part per unlock id that is NOT startOwned, named exactly the unlock id.
                                 Size 8x1x8, Neon, Anchored. BillboardGui "PriceGui" > TextLabel "PriceLabel" (Format.money(price))
                                 and TextLabel "NameLabel" with attribute TextKey = "unlock_<id>".
  CustomerCars (Folder)          created by CustomerService
  AmbientTraffic (Folder)        created by TrafficService
  Employees (Folder)             created by EmployeeService
```
Unlockable models are built in place by MapBuilder. UnlockService moves locked ones to `ServerStorage.LockedUnlockables.PlotN`
and parents them back to `PlotN.Unlockables` when bought. Builders must therefore make each unlockable a self-contained Model.

## 5. Attributes

| On | Attribute | Meaning |
|---|---|---|
| Plot Model | `PlotIndex`, `OwnerUserId` | see above |
| Customer car Model | `PlotIndex` number, `OwnerUserId` number, `ProblemId` string, `State` string, `RepairProgress` number 0..1 | State ∈ `Arriving`, `Queued`, `ToBay`, `InBay`, `Leaving` |
| Employee Model | `Role`, `PlotIndex`, `Slot` | Slot ∈ `Bay1`..`Bay4`, `Cashier` |
| Any ProximityPrompt made by the server | `OwnerUserId` number, `ActionKey` string, `ObjectKey` string? | client hides prompts whose owner ≠ local player and localizes ActionText/ObjectText |
| Any TextLabel / TextButton | `TextKey` string, optional `TextArgs` string (comma separated) | client sets `.Text = Strings.get(lang, TextKey, ...TextArgs)` |

## 6. Remotes — `src/shared/Remotes.luau`

Server → client: `DataChanged(snapshot)`, `Notify(key, args?)`, `OpenUI("Hire")`, `Effect(effect, position, text?)`
with effect ∈ `"Unlock" | "Cash" | "Repair"`.
Client → server: `HireEmployee:InvokeServer(role) -> (ok, messageKey)`, `SetSetting:FireServer(key, value)` with key ∈ `"lang"` (`"th"`/`"en"`), `"music"` (boolean),
`RequestSnapshot:FireServer()` (ClientState sends it once at startup so the first snapshot is never missed).

### Snapshot (sent on every change)
```lua
{
  plotIndex = 1,                  -- number? (nil if server full)
  money = 0, safe = 0,            -- wallet / uncollected money in the safe
  starPoints = 0, starLevel = 0,  -- starLevel 0..5
  nextStarAt = 10,                -- star points for next level, nil at max
  carsRepaired = 0,
  unlocks = { Bay1 = true },
  nextUnlockId = "Cashier", nextUnlockPrice = 250,   -- nil when everything is bought
  employees = { { role = "mechanic", level = 1, slot = "Bay1" } },
  freeHireAvailable = true,
  hireOptions = { { role = "mechanic", price = 0, available = true, reasonKey = nil } },
  tutorialStep = 1,               -- 1 repair a car, 2 hire the free employee, 3 buy an unlock, 4 done
  guideTarget = Vector3.new(...), -- world position the guide arrow should point at, nil = hide
  settings = { lang = "th", music = true },
}
```

## 7. Config modules — `src/shared/Config/`

All configs are plain data tables (no services). Exact schemas:

**Game.luau** — tunables
```lua
return {
  STARTING_MONEY = 100,
  DATASTORE_NAME = "GarageTycoon_v1",
  AUTOSAVE_INTERVAL = 60,
  QUEUE_CAPACITY_BASE = 3,          -- Parking unlock raises it to 6
  SPAWN_INTERVAL_BASE = 9,          -- seconds between customers at 0 stars
  SPAWN_INTERVAL_PER_STAR = 0.8,    -- subtracted per star level
  SPAWN_INTERVAL_MIN = 4,
  ROAD_SPEED = 32, LOT_SPEED = 12,  -- studs per second
  TIP_PERCENT = 0.25,
  TIP_WINDOW_FACTOR = 3, TIP_WINDOW_BONUS = 8,  -- tip if repaired within repairTime*FACTOR + BONUS s of reaching the bay
  STAR_THRESHOLDS = { 10, 40, 120, 300, 700 },  -- star points needed for 1..5 stars
  MECHANIC_SPEED = { 0.5, 0.625, 0.75, 0.875, 1 }, -- fraction of player speed by employee level
  CASHIER_COLLECT_INTERVAL = 2,     -- seconds; cashier moves safe -> wallet
}
```
**Problems.luau** — `{ list = {...}, byId = {...} }`, entries `{ id, station, repairTime, basePay, requiresUnlock? }`.
`station = "any"` means any owned bay can fix it.
**Unlocks.luau** — `{ list = {...}, byId = {...} }`, ordered list; purchase order is strictly linear (an unlock can be bought only when the one before it in `list` is owned).
Entries `{ id, price, kind, bay?, station?, shelf?, startOwned? }`, kind ∈ `"Bay" | "Cashier" | "Shelf" | "Parking"`.
**Stations.luau** — `{ byId = { tire = {...}, oil = {...} }, LEVELS = {...} }`; station `{ id, baseCost }`; LEVELS[n] = `{ timeMult, payMult }` for levels 1..5; upgrade cost to level n+1 = `baseCost * UPGRADE_COST_MULT[n]`.
**Employees.luau** — `{ list = {...}, byId = {...} }`, entries `{ id, price, slotKind, requiresUnlock?, shirtColor: Color3, pantsColor: Color3 }`, slotKind ∈ `"Bay" | "Cashier"`.
**CarTypes.luau** — `{ list = {...}, byId = {...} }`, entries `{ id, payMult, weight, size: Vector3 (W,H,L), colors: {Color3} }`.
**Strings.luau** — `{ th = {...}, en = {...}, get = function(lang, key, ...) }`; falls back to th, then to the key itself; `string.format` with the extra args.

## 8. Shared builders

**CarBuilder.luau** — `CarBuilder.build(carTypeId: string, opts: { color: Color3? }?) -> Model`
- Model.PrimaryPart = Part `"Root"`: Anchored, Transparency 1, CanCollide false, size (W, 0.2, L). Root.CFrame is the pivot:
  ground level, centered, LookVector = nose.
- Every other part: Anchored = false, CanCollide = false, CanTouch = false, Massless = true, welded to Root with WeldConstraint.
  So moving the car = `model:PivotTo(cf)` or tweening Root.CFrame.
- Main paint part is named `"Body"`. Attachment `"TopAttachment"` inside Root at the car's roof height + 2 (for billboards).
- If `ReplicatedStorage.Models["Car_" .. carTypeId]` exists, clone it instead, then enforce the same rules (create Root if missing).

## 9. Server service APIs (who implements what)

| Module | Owner | API |
|---|---|---|
| `MapBuilder` | Sonnet | `build()` builds World + 4 plots (§4). `getPlot(i) -> Model`. |
| `TrafficService` | Sonnet | `drive(model, waypoints: {Vector3}, speed, finalCFrame: CFrame?) -> boolean` yields; `start()` runs ambient traffic. |
| `EmployeeService` | Sonnet | `spawn(plotIndex, role, slot, level) -> Model`, `setWorking(model, working: boolean)`, `clearPlot(plotIndex)`. |
| `PlayerData` | Opus | `get(player) -> data?`, `update(player, fn(data))` (marks dirty + pushes snapshot), `onLoaded(fn(player, data))`. |
| `PlotService` | Opus | `getPlotIndex(player) -> number?`, `getOwner(plotIndex) -> Player?`, `onAssigned(fn(player, plotIndex))`, `onReleased(fn(player, plotIndex))`. |
| `UnlockService` | Opus | `isOwned(player, id) -> boolean`, `queueCapacity(player) -> number`, `ownedBays(player) -> {number}`. |
| `CustomerService` | Opus | customer spawning, queue, dispatch, payment. |
| `RepairService` | Opus | repair prompts, mechanic auto-repair. |
| `HireService` | Opus | hire board prompt, `HireEmployee` remote, free first hire. |

## 10. Client controllers (Sonnet)

`HUD`, `Notifications`, `HireMenu`, `Guide`, `Tutorial`, `CarBillboards`, `Localizer`, `PromptFilter`, `Effects`, `Settings`.
UI must work on phones: big touch targets (min 44 px), `UIScale` by viewport size, no keyboard-only actions.

## 11. Rules
- The server decides everything about money; the client only displays and asks.
- No asset IDs that you cannot verify. For sounds use `rbxasset://sounds/electronicpingshort.wav` only.
- No yielding inside `init()`.

---

# Version 2 — complete game (sections 12–20 extend/override the sections above)

## 12. Station & shelf models (`src/server/Models/`)

- `StationModels.build(key, level, accent: Color3, opts?) -> Model` (dispatcher, already written). Keys:
  `tire, oil, lift, paint, wash` (levels 1–5), `diagnostics, engine, dyno, reception` (level 1 only, but must accept any level),
  `shelf` (levels 1–5, `opts.product` ∈ `"battery" | "tires" | "oil" | "rims"`).
- Each builder lives in `src/server/Models/Stations/<Key>.luau` (Tire, Oil, Lift, Paint, Wash, Diagnostics, Engine, Dyno, Shelf, Reception)
  and is `return function(level: number, accent: Color3, opts: {[string]: any}?): Model`.
- Build with `src/shared/ModelKit.luau` (`ModelKit.model(name)` gives the Pivot part at the origin). All parts Anchored.
  The model is **plot-aligned**: origin = the anchor point on the ground (`Layout.STATIONS[key]`), -Z = toward the ring/front,
  +Y up, ground Y = 0 (building floor top is Y = 0.1, so feet/bases start at 0.1).
- Visual tiers come from `ModelKit.tier(level)`: Lv1 Rusty (CorrodedMetal + rust patches), Lv2 Fresh (clean paint), Lv3 Pro (chrome + white LEDs + light),
  Lv4 Race (carbon black + racing stripes + accent LEDs), Lv5 HiTech (gunmetal glass + accent neon + hologram + sparkles).
  Every level must look clearly better than the one before, and the silhouette may grow (extra arms, screens, tool racks…).
- Tag recolorable parts with `ModelKit.role(part, role)`: `Accent` (neon/accent colored), `Stripe`. PointLights inside Accent parts get recolored too.
- Footprints (do not exceed — cars and players must pass):
  | key | anchor | footprint (local X × Z) | notes |
  |---|---|---|---|
  | tire | beside bay 1 | X -3..6, Z -4..4 | machine + tire stack |
  | oil | beside bay 2 | X -3..5, Z -4..4 | drain unit + barrels |
  | lift | **at bay 3's parked car** | X -7..7, Z -9..7 | two-post lift around the car; posts at X ±5.5; car (7 wide, 14–17 long) sits at origin, nose +Z; arms swing under the car; keep X -3.6..3.6 clear above Y 0.4 |
  | paint | **at bay 4's parked car** | X -7..7, Z -11..10 | booth enclosure around the car; front (-Z) fully open (roll-up door raised); walls/roof/filters/lamps |
  | dyno | at bay 3's parked car | floor rollers flush (Y ≤ 0.35) under the wheels at Z ±4.3, X ±3; console tower at local (10, 0, 4) |
  | engine | behind bay 3 | X -5..5, Z -1.5..2.5 | workbench + engine block on a stand |
  | diagnostics | between bay 1 and 2, back | X -2..2, Z -1.5..1.5 | computer cart with screen facing -Z |
  | wash | over the exit lane | X -6..6, Z -3..3, height ≤ 11 | drive-through arch; car (7 wide) passes along Z at X 0; must contain ParticleEmitters named `WashFoam` (Enabled=false) the server turns on while a car is under it |
  | shelf | shelf position | X -4.5..4.5, Z -1.5..1.5, height ≤ 9 | product parts named `Product` with attribute `ProductIndex` 1..N (N = 10 × level); the server hides products above the stock |
  | reception | reception desk | X -3..3, Z -1.5..1.5 | podium/desk facing -Z, receptionist stands behind at +Z 3.5 |
- Art override: `ReplicatedStorage.Models.Station_<key>_Lv<n>` or `Station_<key>` replaces the generated model.

## 13. Remotes v2 (`src/shared/Remotes.luau`)

Server → client: `DataChanged(snapshot)`, `Notify(key, args?)`, `OpenUI(uiName, arg?)`, `Effect(effect, position, text?)`.
uiName ∈ `"Hire" | "Upgrade"(arg = unlockId) | "Tuning" | "Daily" | "Offline"(arg = amount) | "Themes" | "Rebirth" | "Shop"`.
effect ∈ `"Unlock" | "Cash" | "Repair" | "Level" | "Wash" | "Coins"` (`Coins` and `Cash` use `text`).
Client → server (RemoteFunctions return `(ok: boolean, messageKey: string)`; the server also sends a Notify toast, so the client must not):
`HireEmployee(role)`, `UpgradeEmployee(slot)`, `Upgrade(unlockId)`, `ClaimDaily()`, `Rebirth()`, `BuyTheme(themeId)`,
`BuyCar(carId)`, `SelectCar(carId)`, `Customize(carId, category, optionId)`, `UpgradeCar(carId, part)`, `DriveCar(carId, mode?)` (`mode` = nil: connector road; `"track"`: private race track, needs the `RaceTrack` unlock; the car gets attribute
`OnTrack = true`, and `RaceTrackService` publishes `LapStart`, `NextCheckpoint`, `CheckpointCount`, `LastLap`, `BestLap`, `LapCount` as attributes on the car model);
RemoteEvents: `RequestSnapshot()`, `SetSetting(key, value)`, `ReturnCar()`.
Game passes are bought client-side with `MarketplaceService:PromptGamePassPurchase(player, id)`; the server listens for the result.

## 14. Snapshot v2 (adds to §6)

```lua
levels = { Bay1 = 2, Shelf1 = 1, CarWash = 1 },            -- upgrade level of every owned upgradable unlock
upgradeInfo = { [unlockId] = {
    level = 2, maxLevel = 5, cost = 400,                    -- cost nil at max level
    rows = { { labelKey = "stat_speed", now = "x1.18", next = "x1.43" }, ... },  -- display-ready, next nil at max
} },
employees = { { role, level, slot, upgradeCost = 500 } },   -- upgradeCost nil at max (5)
stock = { Shelf1 = { stock = 7, capacity = 10, price = 40 } },
rebirth = { count = 0, multiplier = 1, canRebirth = false, nextMultiplier = 1.5 },
daily = { available = true, streak = 1, reward = 500 },
themes = { current = "Classic", owned = { Classic = true } },
cars = { Sedan = { custom = {...}, upgrades = { engine = 1, gearbox = 1, suspension = 1, brakes = 1, tires = 1 } } },
carStats = { Sedan = { maxSpeed = 70, accel = 1, handling = 1, braking = 1, grip = 1 } },
selectedCar = "Sedan",                                       -- nil until the tuning room is bought
ownedParts = { ["wheel:Turbo"] = true },                      -- "<category>:<optionId>"
gamepasses = { DoubleMoney = false, AutoCollect = false, FastStaff = false },
multiplier = 1,                                              -- total income multiplier (rebirth × pass)
driving = false,
```

## 15. Unlockables v2 (built by MapBuilder; extends §4)

Ordered unlocks (strictly linear): Bay1 (free) → Cashier → Bay2 → Shelf1 → Parking → Reception → Bay3 → Shelf2 → CarWash → Bay4 →
Diagnostics → Shelf3 → EngineBench → Office → Shelf4 → Dyno → TuningRoom.
- `PlotN.Unlockables.<id>` is a Model. For Bay1–4 it holds the bay dressing (overhead sign, lamp, tool board) **and** a child Model `Station`
  = `StationModels.build(stationKey, 1, accent)` pivoted to `Layout.stationCFrame(plot, stationKey)`. Same for `CarWash` (key wash),
  `Diagnostics`, `EngineBench` (key engine), `Dyno`, `Reception` (key reception, pivot `Layout.RECEPTION.desk`), and `Shelf1..4`
  (key shelf, products battery/tires/oil/rims, pivot `Layout.shelfCFrame`).
- Upgradable unlocks (Bay1–4, CarWash, Shelf1–4) also contain an invisible Part `UpgradeAnchor` (1×1×1, Anchored, CanCollide false,
  Transparency 1) at a reachable spot ~3 studs above the floor in front of the station; the server puts the upgrade prompt on it.
- On upgrade the server destroys `Station`, builds the new level, pivots it to the same CFrame, and re-applies the theme.
- `Office` = mezzanine (Layout.MEZZANINE: floor slab at Y 12, stairs along X 62..68 from Z 4 (ground) to Z 28 (Y 12), glass railing,
  office walls, manager desk at Layout.OFFICE.desk). `TuningRoom` = annex behind the back wall (Layout.ANNEX, turntable Part named
  `Turntable` at Layout.TUNING.turntable, Part `TuningTerminal` at Layout.TUNING.terminal, showroom lights, posters).
- The back wall has a doorway (X -8..8). Until TuningRoom is owned it is closed by a roll-up door Model in `Static` with attribute
  `HideWhenOwned = "TuningRoom"` (the server moves it to storage when owned).
- Buttons for new unlocks: Reception → RECEPTION.button, Bay3/4 → BAYS[n].button, Shelf2–4 → SHELVES[n].button, CarWash → WASH_BUTTON,
  Diagnostics/EngineBench/Dyno → DIAGNOSTICS_/ENGINE_/DYNO_BUTTON, Office → OFFICE.button, TuningRoom → TUNING.button.
- Theme roles on map parts: walls `Wall`, building floor `Floor`, roof `Roof`, neon trims `Accent`, wall stripes `Stripe`.

## 16. Config v2 schemas (`src/shared/Config/`)

- **Unlocks** entries `{ id, price, kind, bay?, station?, shelf?, product?, startOwned?, upgradable? }`;
  kind ∈ `Bay | Cashier | Shelf | Parking | Reception | Wash | Addon | Office | TuningRoom`.
- **Stations** `{ byId = { tire, oil, lift, paint, wash = { id, baseCost } }, LEVELS, UPGRADE_COST_MULT, WASH_BONUS = {5 numbers} }`.
- **Shelves** `{ byId = { Shelf1 = { id, product, basePrice, upgradeBase } ... }, LEVELS = { { capacity, priceMult } ×5 }, UPGRADE_COST_MULT, RESTOCK_SECONDS, SHOPPER_INTERVAL }`.
- **Employees** entries `{ id, price, slotKind, bays?, requiresUnlock?, lockedKey?, shirtColor, pantsColor, accessory }`;
  slotKind ∈ `Bay | Cashier | Stock | Reception | Office`; accessory ∈ `cap | mask | badge | apron | headset | tie`;
  `UPGRADE_COST_MULT = {0.5, 1, 2, 4}` (cost to go from level n to n+1 = price × mult[n]).
- **CarTypes** entries `{ id, payMult, weight, minStars, vip?, size: Vector3, colors }` — ids Sedan, Pickup, Sports, Muscle, Truck, Super.
- **PersonalCars** `{ list = { { id, price, stats = { maxSpeed, accel, handling, braking, grip } } }, byId, UPGRADES = { engine = { stat, perLevel } ... }, UPGRADE_ORDER, upgradeCost = function(carPrice, level) }`.
- **Customization** `{ categories = { { id, kind = "color" | "choice", options = { { id, price } } } }, byId, DEFAULTS = { [category] = optionId } }`.
  Categories: paint, material, wheel, rim, caliper, spoiler, kit, hood, tint, neon, headlight, flames, smoke, decal. Color option ids are hex `"RRGGBB"`.
- **Themes** entries `{ id, price, accent: Color3?, wall, floor, roof, stripe: Color3?, uniform: Color3 }` (accent nil = plot's own color).
- **GamePasses** `{ DoubleMoney = { id = 0, value = 2 }, AutoCollect = { id = 0 }, FastStaff = { id = 0, value = 1.25 } }` (id 0 = disabled, hidden in UI).
- **Game** adds `OFFLINE_MAX_MINUTES, OFFLINE_EFFICIENCY, DAILY_BASE, DAILY_MAX_STREAK, REBIRTH_BONUS, DAY_LENGTH_MINUTES, MUSIC_SOUND_ID,
  CASHIER_BONUS, STOCKER_SPEED, RECEPTION_SPAWN_MULT, RECEPTION_TIP_BONUS, MANAGER_SPEED` (5-entry tables by level).
- **Strings**: core keys in `Strings.luau`; extra key tables in `StringsUI.luau` and `StringsTuning.luau` (`return { th = {...}, en = {...} }`)
  are merged by `Strings.luau` at load. Each UI agent owns its own extra file.

DataStore cannot store Color3: every saved color is a hex string `"RRGGBB"`.

## 17. Cars (`src/shared/CarBuilder.luau`, v2)

- `build(carTypeId, opts?)` — customer cars (as §8), now 6 types.
- `buildCustom(carTypeId, custom) -> Model` — same Root/weld rules, applies a customization table (`custom[category] = optionId`,
  missing keys fall back to `Customization.DEFAULTS`). Must work on server and client (used for the live preview).
- Every car has 4 wheel Models `Wheel_FL, Wheel_FR, Wheel_RL, Wheel_RR`, each with PrimaryPart `Hub` (Cylinder along the car's X,
  size = (tireWidth, D, D), at the wheel center); the wheel's parts are welded to Hub, and Hub is welded to Root by a WeldConstraint
  named `WheelWeld` (parented to Hub). Model attributes `WheelDiameter`, `WheelBase`, `TrackWidth`, `RideHeight`.
- Root contains Attachments `DriverSeat` (seat position), `Exhaust1`/`Exhaust2` (with disabled ParticleEmitter `Flame`),
  `SmokeRL`/`SmokeRR` at the rear tire contact patches (disabled ParticleEmitter `TireSmoke`). Headlights carry a SpotLight `HeadlightBeam`.
  Underglow is a Neon Part `Underglow` with a PointLight.

## 18. Vehicles (`src/server/Vehicle/`)

- `VehicleBuilder.make(model, stats) -> Model` turns a `buildCustom` car into a drivable physics car (VehicleSeat named `DriveSeat`
  at `DriverSeat`, wheels on constraints, suspension springs). `VehicleController.attach(model, stats)` drives it from the seat's
  Throttle/Steer, gives network ownership to the seated player, toggles `Flame` (hard throttle) and `TireSmoke` (sliding/hard turns).
  `VehicleController.detach(model)`.
- stats: `maxSpeed` (studs/s), `accel`, `handling`, `braking`, `grip` (multipliers around 1).

## 19. NPCs (`src/server/Npc/`)

- `NpcBuilder.character({ shirt, pants, skin?, accessory? }) -> Model` (may yield) and `NpcBuilder.walkCycle(model) -> { play, stop }`
  (procedural limb swing via Motor6D.Transform; no animation assets).
- `EmployeeService` (v2) same API as §9 plus `setUniform(plotIndex, color)`; the stocker walks between Layout.STOCK.routeA/B,
  the manager stands at Layout.OFFICE.employee (Y 12), the receptionist at Layout.RECEPTION.employee.
- `ShopperService.visit(plotIndex, shelfIndex, onBuy: () -> ())` — a random shopper walks Layout.SHOPPER_PATH, then to
  (shelf X, 0, SHOPPER_SHELF_Z), browses, calls onBuy once, walks back out and is destroyed. Anchored root + tweened movement.

## 20. Client v2 controllers

`Tuning` (personal car room UI + 3D preview), `Upgrade`, `HireMenu` (tabs: hire / my staff with upgrade), `Daily`, `Offline`, `Rebirth`,
`Themes`, `Shop`, `HUD` (adds multiplier badge and side buttons: Daily, Themes, Rebirth, Shop), `Music`, `DriveHUD` (speedometer + Return),
`Effects` (adds Level/Wash/Coins). Strings for UI-only text go in the controller owner's extra Strings file (§16).
