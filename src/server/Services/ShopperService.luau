--!strict
-- ShopperService: walk-in customers for the parts shelves. A random shopper walks in from the gate,
-- browses a shelf, triggers onBuy once, shows a happy bag pop and walks back out. Visual only; the caller
-- (ShopService) decides what a purchase means.

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Layout: any = require(Shared:WaitForChild("Layout") :: ModuleScript)

local NpcBuilder: any = require(script.Parent.Parent:WaitForChild("Npc"):WaitForChild("NpcBuilder") :: ModuleScript)

local MAX_SHOPPERS_PER_PLOT = 6
local WALK_SPEED = 7
local FLOOR_INSIDE = 0.1
local FLOOR_LOT = 0.06

local ShopperService = {}

local rng = Random.new()
local live: { [number]: { [Model]: boolean } } = {}
local pending: { [number]: number } = {}
local generation: { [number]: number } = {}

----------------------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------------------

local function getShoppersRoot(): Folder
	local root = Workspace:FindFirstChild("Shoppers")
	if root == nil or not root:IsA("Folder") then
		root = Instance.new("Folder")
		root.Name = "Shoppers"
		root.Parent = Workspace
	end
	return root :: Folder
end

local function getPlotFolder(plotIndex: number): Folder
	local root = getShoppersRoot()
	local plotName = "Plot" .. tostring(plotIndex)
	local folder = root:FindFirstChild(plotName)
	if folder == nil or not folder:IsA("Folder") then
		folder = Instance.new("Folder")
		folder.Name = plotName
		folder.Parent = root
	end
	return folder :: Folder
end

-- World floor point for a plot-local (x, z): 0.1 inside the building, 0.06 on the lot.
local function floorPoint(plotIndex: number, x: number, z: number): Vector3
	local y = if z >= Layout.BUILDING.frontZ then FLOOR_INSIDE else FLOOR_LOT
	return Layout.pointToWorld(plotIndex, Vector3.new(x, y, z))
end

local function currentGeneration(plotIndex: number): number
	return generation[plotIndex] or 0
end

-- Small "🛍️" pop above the head for about a second.
local function showBagPop(head: BasePart)
	local gui = Instance.new("BillboardGui")
	gui.Name = "BuyPop"
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(0, 0)
	gui.StudsOffset = Vector3.new(0, 2.4, 0)
	gui.MaxDistance = 80
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = "🛍️"
	label.Parent = gui
	gui.Parent = head

	TweenService:Create(gui, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(56, 56) }):Play()
	task.delay(0.75, function()
		if gui.Parent == nil then
			return
		end
		local fade = TweenService:Create(label, TweenInfo.new(0.25), { TextTransparency = 1 })
		fade:Play()
		task.delay(0.25, function()
			gui:Destroy()
		end)
	end)
end

----------------------------------------------------------------------------------------------------
-- One visit
----------------------------------------------------------------------------------------------------

local function runVisit(plotIndex: number, shelfIndex: number, onBuy: () -> ())
	local visitGeneration = currentGeneration(plotIndex)
	local created, result = pcall(NpcBuilder.randomShopper)
	pending[plotIndex] = math.max(0, (pending[plotIndex] or 1) - 1)
	if not created or typeof(result) ~= "Instance" then
		warn("[ShopperService] could not create a shopper: " .. tostring(result))
		return
	end
	local model = result :: Model
	if currentGeneration(plotIndex) ~= visitGeneration then
		model:Destroy()
		return
	end

	local set = live[plotIndex]
	if set == nil then
		set = {}
		live[plotIndex] = set
	end
	local registry = set :: { [Model]: boolean }
	registry[model] = true
	model.Destroying:Connect(function()
		registry[model] = nil
	end)

	local function alive(): boolean
		return model.Parent ~= nil and currentGeneration(plotIndex) == visitGeneration
	end
	local function stopped(): boolean
		return not alive()
	end

	-- Route: gate -> aisle -> shelf row -> in front of the chosen shelf.
	local route: { Vector3 } = {}
	local pathPoints: { Vector3 } = Layout.SHOPPER_PATH
	for _, p in pathPoints do
		table.insert(route, floorPoint(plotIndex, p.X, p.Z))
	end
	local lastLocal = pathPoints[#pathPoints]
	local shelfX: number = Layout.SHELVES[shelfIndex].shelf.Position.X
	if math.abs(shelfX - lastLocal.X) > 1 then
		table.insert(route, floorPoint(plotIndex, shelfX, lastLocal.Z))
	end
	table.insert(route, floorPoint(plotIndex, shelfX, Layout.SHOPPER_SHELF_Z))

	local ok, err = pcall(function()
		NpcBuilder.place(model, route[1], route[2] - route[1])
		model.Parent = getPlotFolder(plotIndex)

		local walk = NpcBuilder.walkCycle(model)
		local idle = NpcBuilder.idle(model)
		local browse = NpcBuilder.work(model, "reach")

		if not NpcBuilder.walkPath(model, walk, route, WALK_SPEED, stopped) then
			return
		end

		-- Face the shelf (+Z of the plot) and browse.
		local shelfDirection = Layout.plotCFrame(plotIndex):VectorToWorldSpace(Vector3.new(0, 0, 1))
		if not NpcBuilder.turnTo(model, shelfDirection, 0.4, stopped) then
			return
		end
		browse.play()
		task.wait(rng:NextNumber(1.5, 2.5))
		browse.stop()
		if not alive() then
			return
		end

		local bought, buyError = pcall(onBuy)
		if not bought then
			warn("[ShopperService] onBuy failed: " .. tostring(buyError))
		end
		local head = model:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			showBagPop(head)
		end
		idle.play()
		idle.wave(0.9)
		task.wait(1)
		if not alive() then
			return
		end
		idle.stop()

		-- Back out the way we came (we are standing on the last route point).
		local back: { Vector3 } = {}
		for i = #route - 1, 1, -1 do
			table.insert(back, route[i])
		end
		NpcBuilder.walkPath(model, walk, back, WALK_SPEED, stopped)
	end)
	if not ok then
		warn("[ShopperService] visit failed: " .. tostring(err))
	end
	registry[model] = nil
	model:Destroy()
end

----------------------------------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------------------------------

--[[
	A shopper walks in, browses shelf `shelfIndex`, calls onBuy() once, and leaves. Returns immediately
	(the visit runs in its own thread). Ignored while 6 shoppers of the plot are already around.
]]
function ShopperService.visit(plotIndex: number, shelfIndex: number, onBuy: () -> ())
	if Layout.SHELVES[shelfIndex] == nil then
		return
	end
	local count = pending[plotIndex] or 0
	local set = live[plotIndex]
	if set then
		for _ in set do
			count += 1
		end
	end
	if count >= MAX_SHOPPERS_PER_PLOT then
		return
	end
	pending[plotIndex] = (pending[plotIndex] or 0) + 1
	task.spawn(runVisit, plotIndex, shelfIndex, onBuy)
end

-- Removes every shopper of the plot. Their onBuy is not called afterwards.
function ShopperService.clearPlot(plotIndex: number)
	generation[plotIndex] = currentGeneration(plotIndex) + 1
	local set = live[plotIndex]
	if set then
		local models: { Model } = {}
		for model in set do
			table.insert(models, model)
		end
		for _, model in models do
			model:Destroy()
		end
	end
	local root = Workspace:FindFirstChild("Shoppers")
	local folder = if root then root:FindFirstChild("Plot" .. tostring(plotIndex)) else nil
	if folder then
		for _, child in folder:GetChildren() do
			child:Destroy()
		end
	end
end

function ShopperService.start()
	getShoppersRoot()
end

return ShopperService
