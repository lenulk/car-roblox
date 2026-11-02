--!strict
-- EmployeeService: visual NPC staff only (no game logic). Characters come from NpcBuilder, stand at their
-- post with procedural idle animations, work (hammer / spray) when told to, and the stocker walks
-- between the shelves. The root part is anchored; movement is done by writing its CFrame.

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Layout: any = require(Shared:WaitForChild("Layout") :: ModuleScript)
local ConfigFolder = Shared:WaitForChild("Config")
local Employees: any = require(ConfigFolder:WaitForChild("Employees") :: ModuleScript)

local NpcBuilder = require(script.Parent.Parent:WaitForChild("Npc"):WaitForChild("NpcBuilder") :: ModuleScript)

local SKIN_TONES = {
	Color3.fromRGB(255, 219, 172),
	Color3.fromRGB(241, 194, 125),
	Color3.fromRGB(224, 172, 105),
	Color3.fromRGB(198, 134, 66),
	Color3.fromRGB(141, 85, 36),
	Color3.fromRGB(255, 204, 153),
}
local HAIR_COLORS = {
	Color3.fromRGB(35, 28, 24),
	Color3.fromRGB(80, 52, 30),
	Color3.fromRGB(140, 90, 40),
	Color3.fromRGB(222, 184, 90),
	Color3.fromRGB(60, 60, 70),
	Color3.fromRGB(170, 60, 40),
}
-- Star / level colors for levels 1..5.
local LEVEL_COLORS = {
	Color3.fromRGB(205, 205, 215),
	Color3.fromRGB(120, 225, 130),
	Color3.fromRGB(100, 175, 255),
	Color3.fromRGB(195, 130, 255),
	Color3.fromRGB(255, 205, 60),
}

local FLOOR_INSIDE = 0.1 -- building floor top
local FLOOR_LOT = 0.06 -- parking lot / sidewalk top
local STOCK_SPEED = 6
local STOCK_PAUSE = 2
local DEFAULT_ACCESSORY: { [string]: string } = {
	mechanic = "cap",
	painter = "mask",
	cashier = "badge",
	stocker = "apron",
	receptionist = "headset",
	manager = "tie",
}
-- Hair per role: 0 none, 1 short, 2 long, 3 ponytail, 4 bun, nil = random.
local HAIR_STYLE: { [string]: number } = {
	mechanic = 1,
	painter = 0,
	manager = 1,
	receptionist = 3,
}
local WORK_STYLE: { [string]: string } = {
	mechanic = "hammer",
	painter = "spray",
	cashier = "reach",
	stocker = "reach",
}

type State = {
	model: Model,
	root: BasePart,
	plotIndex: number,
	role: string,
	slot: string,
	baseCF: CFrame,
	working: boolean,
	alive: boolean,
	idle: NpcBuilder.IdleController,
	walk: NpcBuilder.WalkController,
	work: NpcBuilder.Controller,
	emitter: ParticleEmitter?,
	yawTween: Tween?,
	thread: thread?,
}

local EmployeeService = {}

local rng = Random.new()
local states: { [Model]: State } = {}
local uniforms: { [number]: Color3 } = {}
local plotGeneration: { [number]: number } = {}

----------------------------------------------------------------------------------------------------
-- Folders and posts
----------------------------------------------------------------------------------------------------

local function getEmployeesRoot(): Folder
	local root = Workspace:FindFirstChild("Employees")
	if root == nil or not root:IsA("Folder") then
		root = Instance.new("Folder")
		root.Name = "Employees"
		root.Parent = Workspace
	end
	return root :: Folder
end

local function getPlotFolder(plotIndex: number): Folder
	local root = getEmployeesRoot()
	local plotName = "Plot" .. tostring(plotIndex)
	local folder = root:FindFirstChild(plotName)
	if folder == nil or not folder:IsA("Folder") then
		folder = Instance.new("Folder")
		folder.Name = plotName
		folder.Parent = root
	end
	return folder :: Folder
end

-- Floor height under a plot-local position (0.1 inside, 0.06 on the lot, mezzanine = its own Y).
local function floorYForLocal(localPos: Vector3): number
	if localPos.Y > 5 then
		return localPos.Y
	end
	if localPos.Z >= Layout.BUILDING.frontZ then
		return FLOOR_INSIDE
	end
	return FLOOR_LOT
end

local function worldFloorPoint(plotIndex: number, localPos: Vector3): Vector3
	local y = floorYForLocal(localPos)
	return Layout.pointToWorld(plotIndex, Vector3.new(localPos.X, y, localPos.Z))
end

-- Returns the slot actually used, the floor position and the look direction (world) of an employee post.
local function resolvePost(plotIndex: number, slot: string): (string, Vector3, Vector3)
	local localCF: CFrame
	local lookTarget: Vector3? = nil
	local usedSlot = slot
	if slot == "Cashier" then
		localCF = Layout.CASHIER.employee
	elseif slot == "Stock" then
		localCF = Layout.STOCK.employee
	elseif slot == "Reception" then
		localCF = Layout.RECEPTION.employee
	elseif slot == "Office" then
		localCF = Layout.OFFICE.employee
	else
		local number = tonumber(string.match(slot, "^Bay(%d+)$"))
		local bay = if number then Layout.BAYS[number] else nil
		if bay == nil then
			warn("[EmployeeService] unknown slot: " .. tostring(slot) .. ", using Bay1")
			usedSlot = "Bay1"
			bay = Layout.BAYS[1]
		end
		localCF = bay.employee
		lookTarget = Layout.toWorld(plotIndex, bay.car).Position
	end
	local floorPos = worldFloorPoint(plotIndex, localCF.Position)
	local look = Layout.toWorld(plotIndex, localCF).LookVector
	if lookTarget then
		local toCar = Vector3.new(lookTarget.X - floorPos.X, 0, lookTarget.Z - floorPos.Z)
		if toCar.Magnitude > 0.01 then
			look = toCar.Unit
		end
	end
	return usedSlot, floorPos, look
end

----------------------------------------------------------------------------------------------------
-- Billboard and effects
----------------------------------------------------------------------------------------------------

local function levelColor(level: number): Color3
	return LEVEL_COLORS[math.clamp(math.floor(level), 1, #LEVEL_COLORS)]
end

local function starsText(level: number): string
	return string.rep("★", math.clamp(math.floor(level), 0, 5))
end

local function buildBillboard(head: BasePart, role: string, level: number)
	local gui = Instance.new("BillboardGui")
	gui.Name = "NameGui"
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(112, 44)
	gui.StudsOffset = Vector3.new(0, 2.3, 0)
	gui.MaxDistance = 60
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0

	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.Size = UDim2.fromScale(1, 1)
	pill.BackgroundColor3 = Color3.fromRGB(20, 24, 36)
	pill.BackgroundTransparency = 0.4
	pill.BorderSizePixel = 0
	pill.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 9)
	corner.Parent = pill

	local roleLabel = Instance.new("TextLabel")
	roleLabel.Name = "RoleLabel"
	roleLabel.BackgroundTransparency = 1
	roleLabel.Position = UDim2.fromScale(0.04, 0.04)
	roleLabel.Size = UDim2.fromScale(0.92, 0.5)
	roleLabel.Font = Enum.Font.GothamBold
	roleLabel.TextScaled = true
	roleLabel.TextColor3 = Color3.new(1, 1, 1)
	roleLabel.TextStrokeTransparency = 0.6
	roleLabel.Text = role -- placeholder, the client localizes via TextKey
	roleLabel:SetAttribute("TextKey", "role_" .. role)
	roleLabel.Parent = pill

	local levelLabel = Instance.new("TextLabel")
	levelLabel.Name = "LevelLabel"
	levelLabel.BackgroundTransparency = 1
	levelLabel.Position = UDim2.fromScale(0.04, 0.54)
	levelLabel.Size = UDim2.fromScale(0.36, 0.4)
	levelLabel.Font = Enum.Font.GothamMedium
	levelLabel.TextScaled = true
	levelLabel.TextXAlignment = Enum.TextXAlignment.Right
	levelLabel.TextColor3 = Color3.fromRGB(255, 235, 140)
	levelLabel.TextStrokeTransparency = 0.6
	levelLabel.Text = "Lv " .. tostring(level)
	levelLabel.Parent = pill

	local starsLabel = Instance.new("TextLabel")
	starsLabel.Name = "StarsLabel"
	starsLabel.BackgroundTransparency = 1
	starsLabel.Position = UDim2.fromScale(0.44, 0.54)
	starsLabel.Size = UDim2.fromScale(0.52, 0.4)
	starsLabel.Font = Enum.Font.GothamBold
	starsLabel.TextScaled = true
	starsLabel.TextXAlignment = Enum.TextXAlignment.Left
	starsLabel.TextColor3 = levelColor(level)
	starsLabel.TextStrokeTransparency = 0.6
	starsLabel.Text = starsText(level)
	starsLabel.Parent = pill

	gui.Parent = head
end

-- Sparks (mechanic / others) or paint mist (painter) coming from the tool tip at the right hand.
local function buildEmitter(model: Model, role: string): ParticleEmitter?
	local hand = model:FindFirstChild("RightHand")
	if hand == nil or not hand:IsA("BasePart") then
		return nil
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "WorkAttachment"
	attachment.Position = Vector3.new(0, -0.2, -1.0)
	attachment.Parent = hand

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "WorkSparks"
	emitter.Enabled = false
	if role == "painter" then
		emitter.EmissionDirection = Enum.NormalId.Front
		emitter.Rate = 26
		emitter.Lifetime = NumberRange.new(0.5, 0.9)
		emitter.Speed = NumberRange.new(3, 5)
		emitter.SpreadAngle = Vector2.new(22, 22)
		emitter.Acceleration = Vector3.new(0, 0, 0)
		emitter.LightEmission = 0.25
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25),
			NumberSequenceKeypoint.new(1, 1.1),
		})
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Color = ColorSequence.new(Color3.fromRGB(235, 245, 255), Color3.fromRGB(120, 190, 255))
	else
		emitter.Rate = 14
		emitter.Lifetime = NumberRange.new(0.25, 0.5)
		emitter.Speed = NumberRange.new(4, 8)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Acceleration = Vector3.new(0, -8, 0)
		emitter.LightEmission = 1
		emitter.Size = NumberSequence.new(0.35, 0)
		emitter.Color = ColorSequence.new(Color3.fromRGB(255, 240, 150), Color3.fromRGB(255, 140, 40))
	end
	emitter.Parent = attachment
	return emitter
end

----------------------------------------------------------------------------------------------------
-- Behaviors
----------------------------------------------------------------------------------------------------

local function cancelTween(tween: Tween?)
	if tween then
		tween:Cancel()
	end
end

local function waitAlive(state: State, seconds: number)
	local startedAt = os.clock()
	while state.alive and os.clock() - startedAt < seconds do
		task.wait(0.1)
	end
end

local function turnBy(state: State, yaw: number, seconds: number)
	cancelTween(state.yawTween)
	local tween = TweenService:Create(
		state.root,
		TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{ CFrame = state.baseCF * CFrame.Angles(0, yaw, 0) }
	)
	state.yawTween = tween
	tween:Play()
end

-- Stationary staff: small turns now and then; the receptionist waves.
local function stationLoop(state: State)
	while state.alive do
		task.wait(rng:NextNumber(4, 9))
		if not state.alive then
			break
		end
		if not state.working then
			if state.role == "receptionist" and rng:NextNumber() < 0.6 then
				state.idle.wave(2.4)
				waitAlive(state, 2.6)
			else
				turnBy(state, math.rad(rng:NextNumber(-12, 12)), 1.3)
			end
		end
	end
end

-- Stocker: walk to one end of the shelves, face them (+Z), work 2 s, walk to the other end, repeat.
local function stockLoop(state: State)
	local plotIndex = state.plotIndex
	local pointA = worldFloorPoint(plotIndex, Layout.STOCK.routeA)
	local pointB = worldFloorPoint(plotIndex, Layout.STOCK.routeB)
	local shelfDirection = Layout.plotCFrame(plotIndex):VectorToWorldSpace(Vector3.new(0, 0, 1))
	local function stopped(): boolean
		return not state.alive
	end
	local toB = true
	while state.alive do
		state.work.stop()
		state.idle.stop()
		local arrived = NpcBuilder.walkPath(state.model, state.walk, { if toB then pointB else pointA }, STOCK_SPEED, stopped)
		if not arrived or not state.alive then
			break
		end
		NpcBuilder.turnTo(state.model, shelfDirection, 0.4, stopped)
		if not state.alive then
			break
		end
		state.work.play()
		waitAlive(state, STOCK_PAUSE + rng:NextNumber() * 0.3)
		toB = not toB
	end
end

local function cleanup(state: State)
	state.alive = false
	cancelTween(state.yawTween)
	state.yawTween = nil
	local thread = state.thread
	state.thread = nil
	if thread and thread ~= coroutine.running() then
		pcall(task.cancel, thread)
	end
	states[state.model] = nil
end

----------------------------------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------------------------------

--[[
	Creates an employee character at the given slot. YIELDS (character creation hits the web service),
	so call it from a yieldable thread. Replaces an existing employee in the same slot.
]]
function EmployeeService.spawn(plotIndex: number, role: string, slot: string, level: number): Model
	local def = Employees.byId[role]
	if def == nil then
		warn("[EmployeeService] unknown role: " .. tostring(role))
	end
	local roleShirt: Color3 = if def then def.shirtColor else Color3.fromRGB(120, 120, 130)
	local pants: Color3 = if def then def.pantsColor else Color3.fromRGB(40, 40, 50)
	local accessory: string? = if def then def.accessory else DEFAULT_ACCESSORY[role]
	local usedSlot, floorPos, look = resolvePost(plotIndex, slot)
	local generation = plotGeneration[plotIndex] or 0

	local model = NpcBuilder.character({
		shirt = uniforms[plotIndex] or roleShirt,
		pants = pants,
		skin = SKIN_TONES[rng:NextInteger(1, #SKIN_TONES)],
		accessory = accessory,
		hair = HAIR_COLORS[rng:NextInteger(1, #HAIR_COLORS)],
		hairStyle = HAIR_STYLE[role],
	})
	local root = model.PrimaryPart :: BasePart
	local head = model:FindFirstChild("Head") :: BasePart

	NpcBuilder.place(model, floorPos, look)
	buildBillboard(head, role, level)
	local emitter = buildEmitter(model, role)

	model.Name = role .. "_" .. usedSlot
	model:SetAttribute("Role", role)
	model:SetAttribute("PlotIndex", plotIndex)
	model:SetAttribute("Slot", usedSlot)
	model:SetAttribute("Level", level)

	-- The plot was cleared while the character was being created: hand back a model that never appears.
	if (plotGeneration[plotIndex] or 0) ~= generation then
		model:Destroy()
		return model
	end

	local folder = getPlotFolder(plotIndex)
	for _, existing in folder:GetChildren() do
		if existing:GetAttribute("Slot") == usedSlot then
			existing:Destroy()
		end
	end

	local state: State = {
		model = model,
		root = root,
		plotIndex = plotIndex,
		role = role,
		slot = usedSlot,
		baseCF = root.CFrame,
		working = false,
		alive = true,
		idle = NpcBuilder.idle(model),
		walk = NpcBuilder.walkCycle(model),
		work = NpcBuilder.work(model, WORK_STYLE[role] or "reach"),
		emitter = emitter,
		yawTween = nil,
		thread = nil,
	}
	states[model] = state
	model.Destroying:Connect(function()
		cleanup(state)
	end)
	model.Parent = folder

	state.idle.play()
	if usedSlot == "Stock" then
		state.thread = task.spawn(stockLoop, state)
	else
		state.thread = task.spawn(stationLoop, state)
	end
	return model
end

function EmployeeService.setWorking(model: Model, working: boolean)
	local state = states[model]
	if state == nil or state.working == working or state.slot == "Stock" then
		return
	end
	state.working = working

	-- Face the work (the car) again.
	cancelTween(state.yawTween)
	state.yawTween = nil
	if state.root.Parent ~= nil then
		turnBy(state, 0, 0.35)
	end

	if state.emitter then
		state.emitter.Enabled = working
	end
	if working then
		state.idle.stop()
		if state.role == "mechanic" then
			NpcBuilder.setTool(model, if rng:NextNumber() < 0.6 then "hammer" else "wrench")
		elseif state.role == "painter" then
			NpcBuilder.setTool(model, "spray")
		end
		state.work.play()
	else
		state.work.stop()
		NpcBuilder.setTool(model, nil)
		state.idle.play()
	end
end

function EmployeeService.setLevel(model: Model, level: number)
	model:SetAttribute("Level", level)
	local label = model:FindFirstChild("LevelLabel", true)
	if label and label:IsA("TextLabel") then
		label.Text = "Lv " .. tostring(level)
	end
	local stars = model:FindFirstChild("StarsLabel", true)
	if stars and stars:IsA("TextLabel") then
		stars.Text = starsText(level)
		stars.TextColor3 = levelColor(level)
	end
end

-- Recolors the shirt of every employee of the plot; nil restores each role's own shirt color.
function EmployeeService.setUniform(plotIndex: number, color: Color3?)
	uniforms[plotIndex] = color :: any
	local root = Workspace:FindFirstChild("Employees")
	local folder = if root then root:FindFirstChild("Plot" .. tostring(plotIndex)) else nil
	if folder == nil then
		return
	end
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			local def = Employees.byId[child:GetAttribute("Role")]
			local shirt: Color3? = color
			if shirt == nil then
				shirt = if def then def.shirtColor else nil
			end
			if shirt then
				NpcBuilder.applyShirt(child, shirt)
			end
		end
	end
end

function EmployeeService.clearPlot(plotIndex: number)
	plotGeneration[plotIndex] = (plotGeneration[plotIndex] or 0) + 1
	local root = Workspace:FindFirstChild("Employees")
	if root == nil then
		return
	end
	local folder = root:FindFirstChild("Plot" .. tostring(plotIndex))
	if folder == nil then
		return
	end
	for _, child in folder:GetChildren() do
		child:Destroy()
	end
end

function EmployeeService.start()
	getEmployeesRoot()
end

return EmployeeService
