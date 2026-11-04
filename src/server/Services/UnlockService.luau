--!strict
-- Tycoon purchases and station/shelf upgrades. Locked unlockables wait in ServerStorage; every
-- unowned unlock's price pad is shown (nextUnlock is only the guide's suggestion, in
-- Config.Unlocks.list order). Upgrading swaps the unlockable's "Station" model for the next level's model.

local ServerStorage = game:GetService("ServerStorage")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Layout = require(Shared.Layout)
local Remotes = require(Shared.Remotes)
local Format = require(Shared.Format)
local Strings = require(Shared.Config.Strings)
local Unlocks = require(Shared.Config.Unlocks)
local Stations = require(Shared.Config.Stations)
local Shelves = require(Shared.Config.Shelves)
local Game = require(Shared.Config.Game)

local PlayerData = require(script.Parent.PlayerData)
local PlotService = require(script.Parent.PlotService)
local MapBuilder = require(script.Parent.MapBuilder)
local ThemeService = require(script.Parent.ThemeService)
local StationModels = require(script.Parent.Parent:WaitForChild("Models"):WaitForChild("StationModels"))

local UnlockService = {}

local MAX_LEVEL = 5

local storageRoot: Folder
local unlockedCallbacks: { (Player, string) -> () } = {}
local upgradedCallbacks: { (Player, string, number) -> () } = {}

local function storageFor(plotIndex: number): Folder
	local name = "Plot" .. plotIndex
	local folder = storageRoot:FindFirstChild(name)
	if not folder then
		local newFolder = Instance.new("Folder")
		newFolder.Name = name
		newFolder.Parent = storageRoot
		folder = newFolder
	end
	return folder :: Folder
end

local function findStored(plotIndex: number, kind: string, id: string): Instance?
	local plot = MapBuilder.getPlot(plotIndex)
	local container = plot:FindFirstChild(kind)
	return (container and container:FindFirstChild(id)) or storageFor(plotIndex):FindFirstChild(kind .. "_" .. id)
end

local function hide(plotIndex: number, kind: string, id: string)
	local item = findStored(plotIndex, kind, id)
	if item then
		item.Name = kind .. "_" .. id
		item.Parent = storageFor(plotIndex)
	end
end

local function show(plotIndex: number, kind: string, id: string)
	local item = findStored(plotIndex, kind, id)
	local container = MapBuilder.getPlot(plotIndex):FindFirstChild(kind)
	if item and container then
		item.Name = id
		item.Parent = container
	end
end

-- Static pieces tagged HideWhenOwned = <unlockId> (e.g. the annex door).
local hideWhenOwned: { [number]: { { item: Instance, parent: Instance, id: string } } } = {}

local function collectHideWhenOwned(plotIndex: number)
	local list = {}
	local static = MapBuilder.getPlot(plotIndex):FindFirstChild("Static")
	if static then
		for _, d in static:GetDescendants() do
			local id = d:GetAttribute("HideWhenOwned")
			if type(id) == "string" and d.Parent then
				table.insert(list, { item = d, parent = d.Parent :: Instance, id = id })
			end
		end
	end
	hideWhenOwned[plotIndex] = list
end

local function refreshHideWhenOwned(plotIndex: number, player: Player?)
	local data = if player then PlayerData.get(player) else nil
	for _, entry in hideWhenOwned[plotIndex] or {} do
		local owned = data ~= nil and data.unlocks[entry.id] == true
		entry.item.Parent = if owned then storageFor(plotIndex) else entry.parent
	end
end

function UnlockService.isOwned(player: Player, id: string): boolean
	local data = PlayerData.get(player)
	return data ~= nil and data.unlocks[id] == true
end

function UnlockService.level(player: Player, id: string): number
	local data = PlayerData.get(player)
	if not data or not data.unlocks[id] then
		return 0
	end
	return data.levels[id] or 1
end

-- Level of the bay/wash that holds this station id (0 if not owned).
function UnlockService.stationLevel(player: Player, stationId: string): number
	for _, entry in Unlocks.list do
		if entry.station == stationId then
			return UnlockService.level(player, entry.id)
		end
	end
	return 0
end

-- First unowned unlock in list order (guide arrow / tutorial). `anytime` unlocks are only suggested
-- once everything else is owned.
function UnlockService.nextUnlock(player: Player): any?
	local data = PlayerData.get(player)
	if not data then
		return nil
	end
	local fallback: any = nil
	for _, entry in Unlocks.list do
		if not data.unlocks[entry.id] and not (entry :: any).personal then
			if not (entry :: any).anytime then
				return entry
			end
			fallback = fallback or entry
		end
	end
	return fallback
end

function UnlockService.queueCapacity(player: Player): number
	return if UnlockService.isOwned(player, "Parking") then Game.QUEUE_CAPACITY_PARKING else Game.QUEUE_CAPACITY_BASE
end

-- Owned bays as { [bayIndex] = stationId } plus a sorted list of bay indices.
function UnlockService.ownedBays(player: Player): ({ [number]: string }, { number })
	local stations: { [number]: string } = {}
	local order: { number } = {}
	local data = PlayerData.get(player)
	if data then
		for _, entry in Unlocks.list do
			if entry.kind == "Bay" and data.unlocks[entry.id] then
				stations[entry.bay] = entry.station
				table.insert(order, entry.bay)
			end
		end
	end
	table.sort(order)
	return stations, order
end

function UnlockService.onUnlocked(fn: (Player, string) -> ())
	table.insert(unlockedCallbacks, fn)
end

function UnlockService.onUpgraded(fn: (Player, string, number) -> ())
	table.insert(upgradedCallbacks, fn)
end

local function buttonPosition(plotIndex: number, entry: any): Vector3
	local p: Vector3
	local kind = entry.kind
	if kind == "Bay" then
		p = Layout.BAYS[entry.bay].button
	elseif kind == "Shelf" then
		p = Layout.SHELVES[entry.shelf].button
	elseif kind == "Cashier" then
		p = Layout.CASHIER.button
	elseif kind == "Reception" then
		p = Layout.RECEPTION.button
	elseif kind == "Wash" then
		p = Layout.WASH_BUTTON
	elseif kind == "Addon" then
		p = if entry.station == "diagnostics"
			then Layout.DIAGNOSTICS_BUTTON
			elseif entry.station == "engine" then Layout.ENGINE_BUTTON
			else Layout.DYNO_BUTTON
	elseif kind == "Office" then
		p = Layout.OFFICE.button
	elseif kind == "TuningRoom" then
		p = Layout.TUNING.button
	elseif kind == "RaceTrack" then
		p = Layout.TRACK.button
	else
		p = Layout.PARKING_BUTTON
	end
	return Layout.pointToWorld(plotIndex, p)
end

function UnlockService.nextButtonPosition(player: Player): Vector3?
	local plotIndex = PlotService.getPlotIndex(player)
	local entry = UnlockService.nextUnlock(player)
	if not plotIndex or not entry then
		return nil
	end
	return buttonPosition(plotIndex, entry)
end

-- True if the unlock's `requires` (if any) is owned.
local function requirementMet(data: PlayerData.Data, entry: any): boolean
	return entry.requires == nil or data.unlocks[entry.requires] == true
end

local function refreshButtons(plotIndex: number, player: Player?)
	local data = if player then PlayerData.get(player) else nil
	for _, entry in Unlocks.list do
		if not entry.startOwned then
			if data and not data.unlocks[entry.id] and requirementMet(data, entry) then
				show(plotIndex, "Buttons", entry.id)
			else
				hide(plotIndex, "Buttons", entry.id)
			end
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Upgrades
----------------------------------------------------------------------------------------------------

local function stationKey(entry: any): (string?, { [string]: any }?)
	if entry.kind == "Shelf" then
		return "shelf", { product = entry.product }
	elseif entry.station then
		return entry.station, nil
	elseif entry.kind == "Reception" then
		return "reception", nil
	end
	return nil, nil
end

-- Cost to go from `level` to level + 1 (nil at max or not upgradable).
function UnlockService.upgradeCost(id: string, level: number): number?
	local entry = Unlocks.byId[id]
	if not entry or not entry.upgradable or level >= MAX_LEVEL or level < 1 then
		return nil
	end
	if entry.kind == "Shelf" then
		return math.floor(Shelves.byId[id].upgradeBase * Shelves.UPGRADE_COST_MULT[level])
	end
	local station = Stations.byId[entry.station]
	return if station then math.floor(station.baseCost * Stations.UPGRADE_COST_MULT[level]) else nil
end

local function mult(x: number): string
	return string.format("x%.2f", x)
end

local function percent(x: number): string
	return string.format("+%d%%", math.floor(x * 100 + 0.5))
end

-- Display rows for the upgrade window (labels are Strings keys).
local function upgradeRows(id: string, level: number): { { labelKey: string, now: string, next: string? } }
	local entry = Unlocks.byId[id]
	local hasNext = level < MAX_LEVEL
	if entry.kind == "Shelf" then
		local shelf = Shelves.byId[id]
		local now, nxt = Shelves.LEVELS[level], Shelves.LEVELS[math.min(level + 1, MAX_LEVEL)]
		return {
			{ labelKey = "stat_capacity", now = tostring(now.capacity), next = if hasNext then tostring(nxt.capacity) else nil },
			{
				labelKey = "stat_price",
				now = Format.money(math.floor(shelf.basePrice * now.priceMult)),
				next = if hasNext then Format.money(math.floor(shelf.basePrice * nxt.priceMult)) else nil,
			},
		}
	elseif entry.kind == "Wash" then
		return {
			{
				labelKey = "stat_wash",
				now = percent(Stations.WASH_BONUS[level]),
				next = if hasNext then percent(Stations.WASH_BONUS[level + 1]) else nil,
			},
		}
	end
	local now, nxt = Stations.LEVELS[level], Stations.LEVELS[math.min(level + 1, MAX_LEVEL)]
	return {
		{ labelKey = "stat_speed", now = mult(1 / now.timeMult), next = if hasNext then mult(1 / nxt.timeMult) else nil },
		{ labelKey = "stat_pay", now = mult(now.payMult), next = if hasNext then mult(nxt.payMult) else nil },
	}
end

-- Rebuilds the "Station" model inside an unlockable for the given level.
function UnlockService.rebuildStation(plotIndex: number, id: string, level: number)
	local entry = Unlocks.byId[id]
	local key, opts = stationKey(entry)
	local holder = findStored(plotIndex, "Unlockables", id)
	if not key or not holder then
		return
	end
	local old = holder:FindFirstChild("Station")
	local pivot: CFrame
	if old and old:IsA("Model") then
		pivot = old:GetPivot()
		old:Destroy()
	elseif entry.kind == "Shelf" then
		pivot = Layout.shelfCFrame(plotIndex, entry.shelf)
	elseif entry.kind == "Reception" then
		pivot = Layout.toWorld(plotIndex, CFrame.new(Layout.RECEPTION.desk.Position))
	else
		pivot = Layout.stationCFrame(plotIndex, key)
	end
	local model = StationModels.build(key, level, ThemeService.accentFor(plotIndex), opts)
	model:PivotTo(pivot)
	model.Parent = holder
	ThemeService.applyTo(plotIndex, model)
end

local function upgradePosition(plotIndex: number, id: string): Vector3
	local holder = findStored(plotIndex, "Unlockables", id)
	local anchor = holder and holder:FindFirstChild("UpgradeAnchor", true)
	if anchor and anchor:IsA("BasePart") then
		return anchor.Position
	end
	return buttonPosition(plotIndex, Unlocks.byId[id])
end

local upgrading: { [Player]: boolean } = {}

local function tryUpgrade(player: Player, id: any): (boolean, string)
	local entry = if type(id) == "string" then Unlocks.byId[id] else nil
	local plotIndex = PlotService.getPlotIndex(player)
	local data = PlayerData.get(player)
	if not entry or not entry.upgradable or not plotIndex or not data or not data.unlocks[entry.id] or upgrading[player] then
		return false, "notify_max_level"
	end
	local level = data.levels[entry.id] or 1
	local cost = UnlockService.upgradeCost(entry.id, level)
	if not cost then
		Remotes.get("Notify"):FireClient(player, "notify_max_level")
		return false, "notify_max_level"
	end
	if data.money < cost then
		Remotes.get("Notify"):FireClient(player, "notify_not_enough_money", { Format.money(cost - data.money) })
		return false, "notify_not_enough_money"
	end
	upgrading[player] = true
	local newLevel = level + 1
	PlayerData.update(player, function(d)
		d.money -= cost
		d.levels[entry.id] = newLevel
	end)
	-- money is already spent: an error below must not leave the player locked out of upgrades
	local ok, err = pcall(function()
		UnlockService.rebuildStation(plotIndex, entry.id, newLevel)
		Remotes.get("Effect"):FireClient(player, "Level", upgradePosition(plotIndex, entry.id))
		Remotes.get("Notify"):FireClient(player, "notify_upgraded", { Strings.get(data.settings.lang, "unlock_" .. entry.id), newLevel })
		for _, fn in upgradedCallbacks do
			task.spawn(fn, player, entry.id, newLevel)
		end
	end)
	upgrading[player] = nil
	if not ok then
		warn("[UnlockService] upgrade " .. entry.id .. " failed after charging: " .. tostring(err))
	end
	return true, "notify_upgraded"
end

----------------------------------------------------------------------------------------------------
-- Purchases
----------------------------------------------------------------------------------------------------

local purchasing: { [Player]: boolean } = {}

local function tryPurchase(player: Player, plotIndex: number, id: string)
	if purchasing[player] or PlotService.getPlotIndex(player) ~= plotIndex then
		return
	end
	local entry = Unlocks.byId[id]
	local data = PlayerData.get(player)
	if not entry or entry.startOwned or not data or data.unlocks[id] or not requirementMet(data, entry) then
		return
	end
	if data.money < entry.price then
		Remotes.get("Notify"):FireClient(player, "notify_not_enough_money", { Format.money(entry.price - data.money) })
		return
	end
	purchasing[player] = true
	-- The tutorial only advances when the suggested unlock is bought (not e.g. the anytime TuningRoom).
	local suggested = UnlockService.nextUnlock(player)
	local wasSuggested = suggested ~= nil and suggested.id == id
	PlayerData.update(player, function(d)
		d.money -= entry.price
		d.unlocks[id] = true
		if entry.upgradable then
			d.levels[id] = 1
		end
		if d.tutorialStep == 3 and wasSuggested then
			d.tutorialStep = 4
		end
	end)
	-- money is already spent: an error below must not leave the player locked out of purchases
	local ok, err = pcall(function()
		UnlockService.rebuildStation(plotIndex, id, 1)
		show(plotIndex, "Unlockables", id)
		refreshButtons(plotIndex, player)
		refreshHideWhenOwned(plotIndex, player)
		Remotes.get("Effect"):FireClient(player, "Unlock", buttonPosition(plotIndex, entry))
		Remotes.get("Notify"):FireClient(player, "notify_unlocked", { Strings.get(data.settings.lang, "unlock_" .. id) })
		for _, fn in unlockedCallbacks do
			task.spawn(fn, player, id)
		end
	end)
	purchasing[player] = nil
	if not ok then
		warn("[UnlockService] purchase " .. id .. " failed after charging: " .. tostring(err))
	end
end

local function newPrompt(parent: Instance, actionKey: string, objectKey: string, hold: number): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = Strings.get("th", actionKey)
	prompt.ObjectText = Strings.get("th", objectKey)
	prompt.HoldDuration = hold
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt:SetAttribute("OwnerUserId", 0)
	prompt:SetAttribute("ActionKey", actionKey)
	prompt:SetAttribute("ObjectKey", objectKey)
	prompt.Parent = parent
	return prompt
end

local allPrompts: { [number]: { ProximityPrompt } } = {}

local function createPrompts(plotIndex: number)
	local prompts = {}
	allPrompts[plotIndex] = prompts
	for _, entry in Unlocks.list do
		local id = entry.id
		local button = findStored(plotIndex, "Buttons", id)
		if button and button:IsA("BasePart") then
			local prompt = newPrompt(button, "prompt_buy", "unlock_" .. id, 0.25)
			prompt.Triggered:Connect(function(player)
				tryPurchase(player, plotIndex, id)
			end)
			table.insert(prompts, prompt)
		end
		if entry.upgradable then
			local holder = findStored(plotIndex, "Unlockables", id)
			local anchor = holder and holder:FindFirstChild("UpgradeAnchor", true)
			if anchor and anchor:IsA("BasePart") then
				local prompt = newPrompt(anchor, "prompt_upgrade", "unlock_" .. id, 0)
				prompt.Triggered:Connect(function(player)
					if PlotService.getPlotIndex(player) == plotIndex and UnlockService.isOwned(player, id) then
						Remotes.get("OpenUI"):FireClient(player, "Upgrade", id)
					end
				end)
				table.insert(prompts, prompt)
			end
		end
	end
end

local function setPromptOwner(plotIndex: number, userId: number)
	for _, prompt in allPrompts[plotIndex] or {} do
		prompt:SetAttribute("OwnerUserId", userId)
	end
end

-- Shows everything the player owns (at the right levels). Used on join.
function UnlockService.restorePlot(player: Player, plotIndex: number)
	local data = PlayerData.get(player)
	if not data then
		return
	end
	for _, entry in Unlocks.list do
		if data.unlocks[entry.id] then
			if entry.upgradable then
				local level = data.levels[entry.id] or 1
				UnlockService.rebuildStation(plotIndex, entry.id, level)
			end
			show(plotIndex, "Unlockables", entry.id)
		else
			hide(plotIndex, "Unlockables", entry.id)
		end
	end
	setPromptOwner(plotIndex, player.UserId)
	refreshButtons(plotIndex, player)
	refreshHideWhenOwned(plotIndex, player)
end

function UnlockService.resetPlot(plotIndex: number)
	for _, entry in Unlocks.list do
		hide(plotIndex, "Unlockables", entry.id)
		if entry.upgradable then
			UnlockService.rebuildStation(plotIndex, entry.id, 1)
		end
	end
	setPromptOwner(plotIndex, 0)
	refreshButtons(plotIndex, nil)
	refreshHideWhenOwned(plotIndex, nil)
end

function UnlockService.init()
	local root = Instance.new("Folder")
	root.Name = "LockedUnlockables"
	root.Parent = ServerStorage
	storageRoot = root
end

function UnlockService.start()
	Remotes.get("Upgrade").OnServerInvoke = tryUpgrade

	for plotIndex = 1, Layout.PLOT_COUNT do
		createPrompts(plotIndex)
		collectHideWhenOwned(plotIndex)
		for _, entry in Unlocks.list do
			hide(plotIndex, "Unlockables", entry.id)
		end
		refreshButtons(plotIndex, nil)
		refreshHideWhenOwned(plotIndex, nil)
	end

	PlotService.onAssigned(function(player, plotIndex)
		PlayerData.update(player, function(data)
			for _, entry in Unlocks.list do
				if entry.startOwned then
					data.unlocks[entry.id] = true
					if entry.upgradable and not data.levels[entry.id] then
						data.levels[entry.id] = 1
					end
				end
			end
		end)
		UnlockService.restorePlot(player, plotIndex)
	end)

	PlotService.onReleased(function(_player, plotIndex)
		UnlockService.resetPlot(plotIndex)
	end)

	PlayerData.addSnapshotField(function(player, data, snapshot)
		local nextEntry = UnlockService.nextUnlock(player)
		snapshot.nextUnlockId = if nextEntry then nextEntry.id else nil
		snapshot.nextUnlockPrice = if nextEntry then nextEntry.price else nil
		local levels = {}
		local info = {}
		for _, entry in Unlocks.list do
			if entry.upgradable and data.unlocks[entry.id] then
				local level = data.levels[entry.id] or 1
				levels[entry.id] = level
				info[entry.id] = {
					level = level,
					maxLevel = MAX_LEVEL,
					cost = UnlockService.upgradeCost(entry.id, level),
					rows = upgradeRows(entry.id, level),
				}
			end
		end
		snapshot.levels = levels
		snapshot.upgradeInfo = info
	end)
end

return UnlockService
