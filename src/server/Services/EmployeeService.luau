--!strict
-- EmployeeService: visual NPC staff only (no game logic). Characters come from NpcBuilder, stand at their
-- post with procedural idle animations, work (hammer / spray) when told to, and the stocker carries
-- crates from the stock pile to the shelf ShopService asks for. The root part is anchored; movement is
-- done by writing its CFrame.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Layout: any = require(Shared:WaitForChild("Layout") :: ModuleScript)
local ConfigFolder = Shared:WaitForChild("Config")
local Employees: any = require(ConfigFolder:WaitForChild("Employees") :: ModuleScript)
local Game: any = require(ConfigFolder:WaitForChild("Game") :: ModuleScript)
local SoundFx: any = require(Shared:WaitForChild("SoundFx") :: ModuleScript)

local NpcBuilder: any = require(script.Parent.Parent:WaitForChild("Npc"):WaitForChild("NpcBuilder") :: ModuleScript)

type Controller = { play: () -> (), stop: () -> () }
type IdleController = { play: () -> (), stop: () -> (), wave: (number?) -> () }
type WalkController = { play: () -> (), stop: () -> (), setSpeed: (number) -> () }

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
local STOCK_SPEED = 6 -- walk speed at stocker level 1, scaled by Game.STOCKER_SPEED
local STOCK_PAUSE = 2
local STOCK_PICKUP = 0.8
local STOCK_STOOP_SECONDS = 0.45 -- bend down with the crate before letting go
-- Front-desk staff (cashier / receptionist) notice players walking up.
local GREET_CHECK_INTERVAL = 0.5
local GREET_LOOK_RANGE = 18 -- start looking at the nearest player
local GREET_LOOK_RELEASE = 22 -- stop looking beyond this (hysteresis so the head does not flicker)
local GREET_WAVE_RANGE = 10
local GREET_WAVE_COOLDOWN = 25
local GREET_ROLES: { [string]: boolean } = { cashier = true, receptionist = true }
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
	idle: IdleController,
	walk: WalkController,
	work: Controller,
	emitter: ParticleEmitter?,
	tool: string?, -- tool in hand while working ("hammer" | "wrench" | "spray")
	spraySound: Sound?, -- looping spray sound while a painter works
	workTarget: Vector3?, -- world point the worker looks at while working (the car in the bay)
	lookingAtPlayer: boolean,
	lastWave: number,
	yawTween: Tween?,
	thread: thread?,
}

local EmployeeService = {}

local rng = Random.new()
local states: { [Model]: State } = {}
local uniforms: { [number]: Color3 } = {}
local plotGeneration: { [number]: number } = {}

-- Set by ShopService: which shelf (index) has items waiting for the stocker, and the hand-over.
type StockHandler = { target: (number) -> number?, deliver: (number, number) -> () }
local stockHandler: StockHandler? = nil

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

-- One emitter per NPC, reused for its whole life (it lives under the hand, so it goes with the model):
--  * mechanic: short sparks, fired with Emit() on each hammer blow (never runs on its own)
--  * painter: thin paint mist, enabled only while spraying (setWorking)
-- Other roles get none.
local function buildEmitter(model: Model, role: string): ParticleEmitter?
	if role ~= "mechanic" and role ~= "painter" then
		return nil
	end
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
		emitter.Rate = 0 -- burst only, see the strike handler in spawn()
		emitter.Lifetime = NumberRange.new(0.2, 0.3)
		emitter.Speed = NumberRange.new(5, 9)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Acceleration = Vector3.new(0, -25, 0)
		emitter.LightEmission = 1
		emitter.Size = NumberSequence.new(0.3, 0)
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

local function stockWalkSpeed(state: State): number
	local level = state.model:GetAttribute("Level")
	local speeds = Game.STOCKER_SPEED
	local factor = speeds[if type(level) == "number" then math.clamp(math.floor(level), 1, #speeds) else 1] / speeds[1]
	return STOCK_SPEED * factor
end

local function stockTarget(plotIndex: number): number?
	local handler = stockHandler
	if handler == nil then
		return nil
	end
	local ok, result = pcall(handler.target, plotIndex)
	return if ok and type(result) == "number" and Layout.SHELVES[result] then result else nil
end

-- Stocker: when a shelf has items waiting, walk to the stock pile, pick up a crate, carry it to that
-- shelf and put it on (ShopService adds the stock at that moment). Otherwise wait at the post.
local function stockLoop(state: State)
	local plotIndex = state.plotIndex
	local model = state.model
	local post = worldFloorPoint(plotIndex, Layout.STOCK.employee.Position)
	local postLook = Layout.toWorld(plotIndex, Layout.STOCK.employee).LookVector
	local aisle = worldFloorPoint(plotIndex, Layout.STOCK.aisle)
	local pickup = worldFloorPoint(plotIndex, Layout.STOCK.pickup)
	local backDirection = Layout.plotCFrame(plotIndex):VectorToWorldSpace(Vector3.new(0, 0, 1))
	local function stopped(): boolean
		return not state.alive
	end
	local atPost = true
	while state.alive do
		local shelfIndex = stockTarget(plotIndex)
		if shelfIndex == nil then
			if not atPost then
				state.work.stop()
				if not NpcBuilder.walkPath(model, state.walk, { aisle, post }, stockWalkSpeed(state), stopped) then
					break
				end
				NpcBuilder.turnTo(model, postLook, 0.4, stopped)
				atPost = true
			end
			state.idle.play()
			waitAlive(state, 1)
			continue
		end
		atPost = false
		state.idle.stop()
		state.work.stop()

		-- Fetch a crate.
		local speed = stockWalkSpeed(state)
		if not NpcBuilder.walkPath(model, state.walk, { aisle, pickup }, speed, stopped) then
			break
		end
		NpcBuilder.turnTo(model, backDirection, 0.35, stopped)
		if not state.alive then
			break
		end
		state.work.play()
		waitAlive(state, STOCK_PICKUP)
		state.work.stop()
		NpcBuilder.setCarry(model, true)

		-- Carry it to the shelf.
		local shelfX = Layout.SHELVES[shelfIndex].shelf.Position.X
		local front = worldFloorPoint(plotIndex, Vector3.new(shelfX, 0, Layout.STOCK.routeA.Z))
		if not NpcBuilder.walkPath(model, state.walk, { aisle, front }, stockWalkSpeed(state), stopped) then
			break
		end
		NpcBuilder.turnTo(model, backDirection, 0.35, stopped)
		if not state.alive then
			break
		end

		-- Put it on the shelf: bend down with the crate first, then let go.
		NpcBuilder.setStoop(model, 1)
		waitAlive(state, STOCK_STOOP_SECONDS)
		NpcBuilder.setCarry(model, false)
		SoundFx.play(state.root, "crateDrop")
		state.work.play()
		waitAlive(state, 0.5)
		local handler = stockHandler
		if handler and state.alive then
			local ok, err = pcall(handler.deliver, plotIndex, shelfIndex)
			if not ok then
				warn("[EmployeeService] stock delivery failed: " .. tostring(err))
			end
		end
		NpcBuilder.setStoop(model, 0)
		waitAlive(state, STOCK_PAUSE - 0.5 + rng:NextNumber() * 0.3)
		state.work.stop()
	end
end

local function cleanup(state: State)
	state.alive = false
	SoundFx.release(state.spraySound)
	state.spraySound = nil
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
		tool = nil,
		spraySound = nil,
		workTarget = nil,
		lookingAtPlayer = false,
		lastWave = -math.huge,
		yawTween = nil,
		thread = nil,
	}
	-- Mechanics look at the car in their bay while working.
	local bayNumber = tonumber(string.match(usedSlot, "^Bay(%d+)$"))
	local bay = if bayNumber then Layout.BAYS[bayNumber] else nil
	if bay then
		state.workTarget = Layout.toWorld(plotIndex, bay.car).Position + Vector3.new(0, 3, 0)
	end
	-- Sparks only on the hammer's blow, reusing this NPC's single emitter.
	if role == "mechanic" and emitter then
		local sparks: ParticleEmitter = emitter
		NpcBuilder.setStrikeHandler(model, function()
			sparks:Emit(rng:NextInteger(3, 5))
			SoundFx.play(state.root, if state.tool == "wrench" then "wrench" else "hammerStrike")
		end)
	end
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

-- Sets the painter's mist color: `tint` (the car being sprayed) when given, else the uniform's own
-- shirt color. Safe to call whether or not the painter is currently working.
local function applySprayTint(state: State, tint: Color3?)
	local emitter = state.emitter
	if emitter == nil or state.role ~= "painter" then
		return
	end
	local color = tint
	if color == nil then
		local shirt: any = state.model:GetAttribute("NpcShirt")
		if typeof(shirt) == "Color3" then
			color = shirt :: Color3
		end
	end
	if color then
		emitter.Color = ColorSequence.new((color :: Color3):Lerp(Color3.new(1, 1, 1), 0.45), color :: Color3)
	end
end

-- `tint`: paint color of the car being worked on, used for the painter's spray mist (nil falls back to
-- the uniform's shirt color). Ignored for other roles. Call it with the new car's color every time a job
-- starts: if the NPC is still working (job handed straight over), only the tint is refreshed.
function EmployeeService.setWorking(model: Model, working: boolean, tint: Color3?)
	local state = states[model]
	if state == nil or state.slot == "Stock" then
		return
	end
	if state.working == working then
		if working then
			applySprayTint(state, tint)
		end
		return
	end
	state.working = working

	-- Face the work (the car) again.
	cancelTween(state.yawTween)
	state.yawTween = nil
	if state.root.Parent ~= nil then
		turnBy(state, 0, 0.35)
	end

	-- Paint mist only while spraying (mechanic sparks are fired per blow instead).
	if state.emitter and state.role == "painter" then
		if working then
			applySprayTint(state, tint)
		end
		state.emitter.Enabled = working
	end
	state.lookingAtPlayer = false
	NpcBuilder.lookAt(model, if working then state.workTarget else nil)
	if working then
		state.idle.stop()
		if state.role == "mechanic" then
			state.tool = if rng:NextNumber() < 0.6 then "hammer" else "wrench"
			NpcBuilder.setTool(model, state.tool)
		elseif state.role == "painter" then
			state.tool = "spray"
			NpcBuilder.setTool(model, "spray")
			state.spraySound = SoundFx.attach(state.root, "spray")
		end
		state.work.play()
	else
		state.work.stop()
		state.tool = nil
		NpcBuilder.setTool(model, nil)
		state.idle.play()
		if state.role == "painter" then
			SoundFx.release(state.spraySound)
			state.spraySound = nil
		end
	end
end

function EmployeeService.setStockHandler(target: (number) -> number?, deliver: (number, number) -> ())
	stockHandler = { target = target, deliver = deliver }
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

-- Cashier / receptionist notice players: look at the nearest one in range, wave once when they come
-- close (with a cooldown). One low-rate loop serves every plot and every NPC.
local function greetStep()
	local positions: { Vector3 } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local playerRoot = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if playerRoot and playerRoot:IsA("BasePart") then
			table.insert(positions, playerRoot.Position)
		end
	end
	local now = os.clock()
	for _, state in states do
		if state.alive and not state.working and GREET_ROLES[state.role] then
			local here = state.root.Position
			local nearest: Vector3? = nil
			local nearestDistance = math.huge
			for _, position in positions do
				local distance = (position - here).Magnitude
				if distance < nearestDistance then
					nearestDistance = distance
					nearest = position
				end
			end
			local limit = if state.lookingAtPlayer then GREET_LOOK_RELEASE else GREET_LOOK_RANGE
			if nearest ~= nil and nearestDistance <= limit then
				state.lookingAtPlayer = true
				NpcBuilder.lookAt(state.model, nearest + Vector3.new(0, 1.5, 0))
				if nearestDistance <= GREET_WAVE_RANGE and now - state.lastWave >= GREET_WAVE_COOLDOWN then
					state.lastWave = now
					state.idle.wave(1.5)
					SoundFx.play(state.root, "greet")
				end
			elseif state.lookingAtPlayer then
				state.lookingAtPlayer = false
				NpcBuilder.lookAt(state.model, nil)
			end
		end
	end
end

function EmployeeService.start()
	getEmployeesRoot()
	task.spawn(function()
		while true do
			task.wait(GREET_CHECK_INTERVAL)
			local ok, err = pcall(greetStep)
			if not ok then
				warn("[EmployeeService] greet check failed: " .. tostring(err))
			end
		end
	end)
end

return EmployeeService
