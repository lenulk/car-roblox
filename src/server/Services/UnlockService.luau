--!strict
-- Tycoon purchases. Locked unlockable models wait in ServerStorage; only the next unlock's
-- price pad is shown (strictly linear order from Config.Unlocks.list).

local ServerStorage = game:GetService("ServerStorage")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Layout = require(Shared.Layout)
local Remotes = require(Shared.Remotes)
local Format = require(Shared.Format)
local Strings = require(Shared.Config.Strings)
local Unlocks = require(Shared.Config.Unlocks)
local Game = require(Shared.Config.Game)

local PlayerData = require(script.Parent.PlayerData)
local PlotService = require(script.Parent.PlotService)
local MapBuilder = require(script.Parent.MapBuilder)

local UnlockService = {}

local storageRoot: Folder
local unlockedCallbacks: { (Player, string) -> () } = {}

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
	local storage = storageFor(plotIndex)
	local container = plot:FindFirstChild(kind)
	return (container and container:FindFirstChild(id)) or storage:FindFirstChild(kind .. "_" .. id)
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

function UnlockService.isOwned(player: Player, id: string): boolean
	local data = PlayerData.get(player)
	return data ~= nil and data.unlocks[id] == true
end

function UnlockService.nextUnlock(player: Player): any?
	local data = PlayerData.get(player)
	if not data then
		return nil
	end
	for _, entry in Unlocks.list do
		if not data.unlocks[entry.id] then
			return entry
		end
	end
	return nil
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

local function buttonPosition(plotIndex: number, entry: any): Vector3
	local localPos: Vector3
	if entry.kind == "Bay" then
		localPos = Layout.BAYS[entry.bay].button
	elseif entry.kind == "Shelf" then
		localPos = Layout.SHELVES[entry.shelf].button
	elseif entry.kind == "Cashier" then
		localPos = Layout.CASHIER.button
	else
		localPos = Layout.PARKING_BUTTON
	end
	return Layout.pointToWorld(plotIndex, localPos)
end

function UnlockService.nextButtonPosition(player: Player): Vector3?
	local plotIndex = PlotService.getPlotIndex(player)
	local entry = UnlockService.nextUnlock(player)
	if not plotIndex or not entry then
		return nil
	end
	return buttonPosition(plotIndex, entry)
end

local function refreshButtons(plotIndex: number, player: Player?)
	local nextEntry = if player then UnlockService.nextUnlock(player) else nil
	for _, entry in Unlocks.list do
		if not entry.startOwned then
			if nextEntry and entry.id == nextEntry.id then
				show(plotIndex, "Buttons", entry.id)
			else
				hide(plotIndex, "Buttons", entry.id)
			end
		end
	end
end

local function setPromptOwner(plotIndex: number, userId: number)
	for _, entry in Unlocks.list do
		local button = findStored(plotIndex, "Buttons", entry.id)
		local prompt = button and button:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt:SetAttribute("OwnerUserId", userId)
		end
	end
end

local purchasing: { [Player]: boolean } = {}

local function tryPurchase(player: Player, plotIndex: number, id: string)
	if purchasing[player] or PlotService.getPlotIndex(player) ~= plotIndex then
		return
	end
	local entry = Unlocks.byId[id]
	local nextEntry = UnlockService.nextUnlock(player)
	if not entry or not nextEntry or nextEntry.id ~= id then
		return
	end
	local data = PlayerData.get(player)
	if not data then
		return
	end
	if data.money < entry.price then
		Remotes.get("Notify"):FireClient(player, "notify_not_enough_money", { Format.money(entry.price - data.money) })
		return
	end
	purchasing[player] = true
	if PlayerData.trySpend(player, entry.price) then
		PlayerData.update(player, function(d)
			d.unlocks[id] = true
			if d.tutorialStep == 3 then
				d.tutorialStep = 4
			end
		end)
		local position = buttonPosition(plotIndex, entry)
		show(plotIndex, "Unlockables", id)
		refreshButtons(plotIndex, player)
		Remotes.get("Effect"):FireClient(player, "Unlock", position)
		local name = Strings.get(data.settings.lang, "unlock_" .. id)
		Remotes.get("Notify"):FireClient(player, "notify_unlocked", { name })
		for _, fn in unlockedCallbacks do
			task.spawn(fn, player, id)
		end
	end
	purchasing[player] = nil
end

local function createPrompts(plotIndex: number)
	for _, entry in Unlocks.list do
		local button = findStored(plotIndex, "Buttons", entry.id)
		if button and button:IsA("BasePart") and not button:FindFirstChildOfClass("ProximityPrompt") then
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = Strings.get("th", "prompt_buy")
			prompt.ObjectText = Strings.get("th", "unlock_" .. entry.id) .. " " .. Format.money(entry.price)
			prompt.HoldDuration = 0.25
			prompt.MaxActivationDistance = 12
			prompt.RequiresLineOfSight = false
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt:SetAttribute("OwnerUserId", 0)
			prompt:SetAttribute("ActionKey", "prompt_buy")
			prompt:SetAttribute("ObjectKey", "unlock_" .. entry.id)
			prompt.Parent = button
			local id = entry.id
			prompt.Triggered:Connect(function(player)
				tryPurchase(player, plotIndex, id)
			end)
		end
	end
end

function UnlockService.init()
	local root = Instance.new("Folder")
	root.Name = "LockedUnlockables"
	root.Parent = ServerStorage
	storageRoot = root
end

function UnlockService.start()
	for plotIndex = 1, Layout.PLOT_COUNT do
		createPrompts(plotIndex)
		for _, entry in Unlocks.list do
			hide(plotIndex, "Unlockables", entry.id)
		end
		refreshButtons(plotIndex, nil)
	end

	PlotService.onAssigned(function(player, plotIndex)
		PlayerData.update(player, function(data)
			for _, entry in Unlocks.list do
				if entry.startOwned then
					data.unlocks[entry.id] = true
				end
			end
		end)
		local data = PlayerData.get(player)
		if not data then
			return
		end
		for _, entry in Unlocks.list do
			if data.unlocks[entry.id] then
				show(plotIndex, "Unlockables", entry.id)
			end
		end
		setPromptOwner(plotIndex, player.UserId)
		refreshButtons(plotIndex, player)
	end)

	PlotService.onReleased(function(_player, plotIndex)
		for _, entry in Unlocks.list do
			hide(plotIndex, "Unlockables", entry.id)
		end
		setPromptOwner(plotIndex, 0)
		refreshButtons(plotIndex, nil)
	end)

	PlayerData.addSnapshotField(function(player, _data, snapshot)
		local nextEntry = UnlockService.nextUnlock(player)
		snapshot.nextUnlockId = if nextEntry then nextEntry.id else nil
		snapshot.nextUnlockPrice = if nextEntry then nextEntry.price else nil
	end)
end

return UnlockService
