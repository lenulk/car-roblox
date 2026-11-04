--!strict
-- Storefront decorations: six decor slots on the grass beside the entrance road in front of each garage.
-- Players buy decorations (BuyDecor for money; Robux ones are granted by PurchaseService), place them in slots
-- (PlaceDecor) and every placed item shortens the time between customers (DecorService.bonus).
-- The 3D models are built here on the server (inside the plot, so other players see them) and animated by the
-- client controller DecorAnimator. Data: decorOwned (id -> true), decorPlaced ("1".."6" -> id).

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Layout = require(Shared.Layout)
local Remotes = require(Shared.Remotes)
local Format = require(Shared.Format)
local Strings = require(Shared.Config.Strings)
local Decor = require(Shared.Config.Decor)

local PlayerData = require(script.Parent.PlayerData)
local PlotService = require(script.Parent.PlotService)
local UnlockService = require(script.Parent.UnlockService)
local MapBuilder = require(script.Parent.MapBuilder)
local DecorModels = require(script.Parent.Parent:WaitForChild("Models"):WaitForChild("DecorModels") :: ModuleScript)

local DecorService = {}

-- Slot positions, plot-local. 1-3 on the left of the connector road (x < 0), 4-6 on the right; clear of the road
-- (x -11..11), the gate planters/benches (z -64), the lamps and the ring crosswalk.
local SLOT_X = 24
local SLOT_Z = { -76, -90, -104 }
local QUEUE_FULL_WINDOW = 180 -- seconds
local QUEUE_FULL_COUNT = 3 -- spawn attempts that found the queue full inside the window = "often full"

type Slot = {
	anchor: BasePart,
	pad: Model,
	prompt: ProximityPrompt,
	itemId: string?,
	model: Model?,
}

local slotsByPlot: { [number]: { Slot } } = {}
local itemFolders: { [number]: Folder } = {}
local padFolders: { [number]: Folder } = {}
local arrivals: { [number]: number } = {}
local queueFullTimes: { [number]: { number } } = {}
local queueFullShown: { [number]: boolean } = {}
local busy: { [Player]: boolean } = {}

local function notify(player: Player, key: string, args: { any }?)
	Remotes.get("Notify"):FireClient(player, key, args)
end

local function langOf(player: Player): string
	local data = PlayerData.get(player)
	return if data then data.settings.lang else "th"
end

local function slotPosition(slot: number): Vector3
	local side = if slot <= 3 then -1 else 1
	return Vector3.new(side * SLOT_X, 0, SLOT_Z[(slot - 1) % 3 + 1])
end

-- world frame of a slot: the model's front (-Z) faces the road
local function slotFrame(plotIndex: number, slot: number): CFrame
	local position = slotPosition(slot)
	local yaw = if position.X < 0 then -math.pi / 2 else math.pi / 2
	return Layout.toWorld(plotIndex, CFrame.new(position) * CFrame.Angles(0, yaw, 0))
end

----------------------------------------------------------------------------------------------------
-- Bonus
----------------------------------------------------------------------------------------------------

-- Total reduction of the customer spawn interval (0 .. MAX_BONUS) from the decorations placed AND owned.
function DecorService.bonus(player: Player): number
	local data = PlayerData.get(player)
	if not data then
		return 0
	end
	local placed: { [string]: string } = {}
	for slotKey, id in data.decorPlaced do
		if data.decorOwned[id] == true then
			placed[slotKey] = id
		end
	end
	return Decor.totalBonus(placed)
end

local function queueOftenFull(plotIndex: number): boolean
	local times = queueFullTimes[plotIndex]
	if not times then
		return false
	end
	local now = os.clock()
	local count = 0
	for _, t in times do
		if now - t <= QUEUE_FULL_WINDOW then
			count += 1
		end
	end
	return count >= QUEUE_FULL_COUNT
end

-- CustomerService: a customer could not be spawned because the queue was full.
function DecorService.noteQueueFull(plotIndex: number)
	local times = queueFullTimes[plotIndex]
	if not times then
		times = {}
		queueFullTimes[plotIndex] = times
	end
	local list = times :: { number }
	local now = os.clock()
	table.insert(list, now)
	while #list > 0 and now - list[1] > QUEUE_FULL_WINDOW do
		table.remove(list, 1)
	end
	local often = queueOftenFull(plotIndex)
	if often ~= (queueFullShown[plotIndex] == true) then
		queueFullShown[plotIndex] = often
		local owner = PlotService.getOwner(plotIndex)
		if owner then
			PlayerData.push(owner)
		end
	end
end

-- CustomerService: a customer car just started driving to this plot (the Fireworks decoration fires).
function DecorService.noteArrival(plotIndex: number)
	local count = (arrivals[plotIndex] or 0) + 1
	arrivals[plotIndex] = count
	local slots = slotsByPlot[plotIndex]
	if not slots then
		return
	end
	for _, slot in slots do
		if slot.model and slot.itemId == "Fireworks" then
			slot.model:SetAttribute("Arrivals", count)
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Slots (pads, prompts, models)
----------------------------------------------------------------------------------------------------

local PAD_COLOR = Color3.fromRGB(255, 255, 255)

local function neonPart(parent: Instance, name: string, size: Vector3, cf: CFrame, transparency: number): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = PAD_COLOR
	p.Transparency = transparency
	p.Size = size
	p.CFrame = cf
	p.Parent = parent
	return p
end

-- Faint outlined pad + a small "+" sign on a post. Built once per slot, shown only while the slot is empty.
local function buildPad(frame: CFrame): Model
	local pad = Instance.new("Model")
	pad.Name = "DecorPad"
	local function at(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, z)
	end
	local base = Instance.new("Part")
	base.Name = "PadBase"
	base.Anchored = true
	base.CanCollide = false
	base.CanTouch = false
	base.CanQuery = false
	base.CastShadow = false
	base.Material = Enum.Material.SmoothPlastic
	base.Color = PAD_COLOR
	base.Transparency = 0.86
	base.Size = Vector3.new(10, 0.12, 10)
	base.CFrame = at(0, 0.07, 0)
	base.Parent = pad
	pad.PrimaryPart = base
	for _, sz in { -4.9, 4.9 } do
		neonPart(pad, "PadEdge", Vector3.new(10, 0.14, 0.2), at(0, 0.1, sz), 0.55)
	end
	for _, sx in { -4.9, 4.9 } do
		neonPart(pad, "PadEdge", Vector3.new(0.2, 0.14, 10), at(sx, 0.1, 0), 0.55)
	end
	-- small post with a "+" board, facing the road (-Z of the frame)
	local post = Instance.new("Part")
	post.Name = "PlusPost"
	post.Anchored = true
	post.CanCollide = false
	post.CanTouch = false
	post.CanQuery = false
	post.Material = Enum.Material.Metal
	post.Color = Color3.fromRGB(70, 74, 86)
	post.Size = Vector3.new(0.3, 2.6, 0.3)
	post.CFrame = at(0, 1.3, 0)
	post.Parent = pad
	local board = Instance.new("Part")
	board.Name = "PlusBoard"
	board.Anchored = true
	board.CanCollide = false
	board.CanTouch = false
	board.CanQuery = false
	board.CastShadow = false
	board.Material = Enum.Material.SmoothPlastic
	board.Color = Color3.fromRGB(24, 28, 40)
	board.Size = Vector3.new(1.9, 1.9, 0.2)
	board.CFrame = at(0, 3.4, 0)
	board.Parent = pad
	local gui = Instance.new("SurfaceGui")
	gui.Name = "PlusGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Name = "Plus"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = "+"
	label.TextColor3 = Color3.fromRGB(120, 230, 150)
	label.Parent = gui
	return pad
end

local function buildPlotSlots(plotIndex: number)
	local plot = MapBuilder.getPlot(plotIndex)
	local root = Instance.new("Folder")
	root.Name = "StorefrontDecor"
	root.Parent = plot
	local padFolder = Instance.new("Folder")
	padFolder.Name = "Pads"
	padFolder.Parent = root
	local itemFolder = Instance.new("Folder")
	itemFolder.Name = "Items"
	itemFolder.Parent = root
	local anchorFolder = Instance.new("Folder")
	anchorFolder.Name = "Anchors"
	anchorFolder.Parent = root
	padFolders[plotIndex] = padFolder
	itemFolders[plotIndex] = itemFolder

	local slots: { Slot } = {}
	for slotIndex = 1, Decor.SLOTS do
		local frame = slotFrame(plotIndex, slotIndex)
		local anchor = Instance.new("Part")
		anchor.Name = "DecorSlot" .. slotIndex
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanTouch = false
		anchor.CanQuery = false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(4, 1, 4)
		anchor.CFrame = frame * CFrame.new(0, 0.5, 0)
		anchor.Parent = anchorFolder

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = Strings.get("th", "prompt_decorate")
		prompt.ObjectText = Strings.get("th", "object_storefront")
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt.Enabled = false
		-- PromptFilter (client) hides prompts whose OwnerUserId is not the local player; 0 = nobody
		prompt:SetAttribute("OwnerUserId", 0)
		prompt:SetAttribute("ActionKey", "prompt_decorate")
		prompt:SetAttribute("ObjectKey", "object_storefront")
		prompt.Parent = anchor
		prompt.Triggered:Connect(function(player)
			if PlotService.getOwner(plotIndex) == player and PlayerData.get(player) then
				Remotes.get("OpenUI"):FireClient(player, "Decor", slotIndex)
			end
		end)

		local slot: Slot = { anchor = anchor, pad = buildPad(frame), prompt = prompt, itemId = nil, model = nil }
		table.insert(slots, slot)
	end
	slotsByPlot[plotIndex] = slots
end

local function clearSlotModel(slot: Slot)
	if slot.model then
		slot.model:Destroy()
		slot.model = nil
	end
	slot.itemId = nil
end

-- Brings the plot's slots in line with its owner's data (models, pads, prompts).
local function refreshPlot(plotIndex: number)
	local slots = slotsByPlot[plotIndex]
	if not slots then
		return
	end
	local owner = PlotService.getOwner(plotIndex)
	local data = if owner then PlayerData.get(owner) else nil
	for slotIndex, slot in slots do
		local wanted: string? = nil
		if data then
			local id = data.decorPlaced[tostring(slotIndex)]
			if id ~= nil and data.decorOwned[id] == true and Decor.byId[id] ~= nil then
				wanted = id
			end
		end
		if slot.itemId ~= wanted then
			clearSlotModel(slot)
			if wanted then
				local model = DecorModels.build(wanted, slotFrame(plotIndex, slotIndex))
				if model then
					model:SetAttribute("PlotIndex", plotIndex)
					model:SetAttribute("Slot", slotIndex)
					model:SetAttribute("Arrivals", arrivals[plotIndex] or 0)
					model.Parent = itemFolders[plotIndex] -- parent last: clients receive the finished model
					slot.model = model
					slot.itemId = wanted
				end
			end
		end
		slot.pad.Parent = if owner and wanted == nil then padFolders[plotIndex] else nil
		slot.prompt:SetAttribute("OwnerUserId", if owner then owner.UserId else 0)
		slot.prompt.Enabled = owner ~= nil
	end
end

local function clearPlot(plotIndex: number)
	local slots = slotsByPlot[plotIndex]
	if not slots then
		return
	end
	for _, slot in slots do
		clearSlotModel(slot)
		slot.pad.Parent = nil
		slot.prompt:SetAttribute("OwnerUserId", 0)
		slot.prompt.Enabled = false
	end
	arrivals[plotIndex] = nil
	queueFullTimes[plotIndex] = nil
	queueFullShown[plotIndex] = nil
end

----------------------------------------------------------------------------------------------------
-- Remotes
----------------------------------------------------------------------------------------------------

local function buyDecor(player: Player, id: any): (boolean, string)
	local data = PlayerData.get(player)
	local item = if type(id) == "string" then Decor.byId[id] else nil
	if not data or not item or busy[player] then
		return false, "notify_decor_invalid"
	end
	busy[player] = true
	local ok, result, key = pcall(function(): (boolean, string)
		local name = Strings.get(langOf(player), "decor_" .. item.id)
		if data.decorOwned[item.id] then
			notify(player, "notify_already_owned", { name })
			return true, "notify_already_owned"
		end
		local price = item.price
		if item.robuxProduct or price == nil then
			-- Robux decorations are granted by PurchaseService only
			notify(player, "notify_robux_only")
			return false, "notify_robux_only"
		end
		local cost: number = price :: number
		if data.money < cost then
			notify(player, "notify_not_enough_money", { Format.money(cost - data.money) })
			return false, "notify_not_enough_money"
		end
		PlayerData.update(player, function(d)
			d.money -= cost
			d.decorOwned[item.id] = true
		end)
		notify(player, "notify_decor_bought", { name })
		return true, "notify_decor_bought"
	end)
	busy[player] = nil
	if not ok then
		warn("[DecorService] BuyDecor failed: " .. tostring(result))
		return false, "notify_decor_invalid"
	end
	return result, key
end

local function placeDecor(player: Player, slotArg: any, id: any): (boolean, string)
	local data = PlayerData.get(player)
	local plotIndex = PlotService.getPlotIndex(player)
	if not data or not plotIndex or busy[player] then
		return false, "notify_decor_invalid"
	end
	if type(slotArg) ~= "number" or slotArg % 1 ~= 0 or slotArg < 1 or slotArg > Decor.SLOTS then
		return false, "notify_decor_invalid"
	end
	local slot = slotArg :: number
	local item: Decor.DecorItem? = nil
	if id ~= nil then
		item = if type(id) == "string" then Decor.byId[id] else nil
		if item == nil or data.decorOwned[(item :: Decor.DecorItem).id] ~= true then
			return false, "notify_decor_invalid"
		end
	end
	busy[player] = true
	local slotKey = tostring(slot)
	local placeId: string? = if item then (item :: Decor.DecorItem).id else nil
	local ok, err = pcall(function()
		if placeId then
			local name = Strings.get(langOf(player), "decor_" .. placeId)
			PlayerData.update(player, function(d)
				-- an item can only be in one slot: placing it again moves it
				local others: { string } = {}
				for key, placed in d.decorPlaced do
					if placed == placeId and key ~= slotKey then
						table.insert(others, key)
					end
				end
				for _, key in others do
					d.decorPlaced[key] = nil
				end
				d.decorPlaced[slotKey] = placeId
			end)
			notify(player, "notify_decor_placed", { name })
		else
			local current = data.decorPlaced[slotKey]
			PlayerData.update(player, function(d)
				d.decorPlaced[slotKey] = nil
			end)
			if current then
				notify(player, "notify_decor_removed", { Strings.get(langOf(player), "decor_" .. current) })
			end
		end
		refreshPlot(plotIndex)
	end)
	busy[player] = nil
	if not ok then
		warn("[DecorService] PlaceDecor failed: " .. tostring(err))
		return false, "notify_decor_invalid"
	end
	return true, if placeId then "notify_decor_placed" else "notify_decor_removed"
end

----------------------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------------------

function DecorService.start()
	for plotIndex = 1, Layout.PLOT_COUNT do
		buildPlotSlots(plotIndex)
	end

	Remotes.get("BuyDecor").OnServerInvoke = buyDecor
	Remotes.get("PlaceDecor").OnServerInvoke = placeDecor

	PlotService.onAssigned(function(_player, plotIndex)
		refreshPlot(plotIndex)
	end)
	PlotService.onReleased(function(_player, plotIndex)
		clearPlot(plotIndex)
	end)
	Players.PlayerRemoving:Connect(function(player)
		busy[player] = nil
	end)

	PlayerData.addSnapshotField(function(player, data, snapshot)
		local plotIndex = PlotService.getPlotIndex(player)
		snapshot.decor = {
			owned = table.clone(data.decorOwned),
			placed = table.clone(data.decorPlaced),
			bonus = DecorService.bonus(player),
			queueFull = plotIndex ~= nil and queueOftenFull(plotIndex) and not UnlockService.isOwned(player, "Parking"),
		}
	end)
end

return DecorService
