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
Client → server: `HireEmployee:InvokeServer(role) -> (ok, messageKey)`, `SetSetting:FireServer(key, value)` with key ∈ `"lang"` (`"th"`/`"en"`), `"music"` (boolean).

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
