--!strict
-- EmployeeService: visual NPC staff only (no game logic). Characters are anchored at their post,
-- idle with small yaw turns, and bob + throw sparks while "working".

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Layout: any = require(Shared:WaitForChild("Layout") :: ModuleScript)
local ConfigFolder = Shared:WaitForChild("Config")
local Employees: any = require(ConfigFolder:WaitForChild("Employees") :: ModuleScript)

local SKIN_TONES = {
	Color3.fromRGB(255, 219, 172),
	Color3.fromRGB(241, 194, 125),
	Color3.fromRGB(224, 172, 105),
	Color3.fromRGB(198, 134, 66),
	Color3.fromRGB(141, 85, 36),
	Color3.fromRGB(255, 204, 153),
}
local SHOE_COLOR = Color3.fromRGB(35, 35, 40)
local FALLBACK_HIP_HEIGHT = 2

local IDLE_YAW_DEGREES = 8
local BOB_HEIGHT = 0.3
local BOB_TIME = 0.4

local SHIRT_PARTS = { "UpperTorso", "LowerTorso", "LeftUpperArm", "RightUpperArm" }
local PANTS_PARTS = { "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg" }
local SHOE_PARTS = { "LeftFoot", "RightFoot" }

type State = {
	model: Model,
	root: BasePart,
	baseCF: CFrame,
	working: boolean,
	emitter: ParticleEmitter?,
	idleTween: Tween?,
	bobTween: Tween?,
}

local EmployeeService = {}

local rng = Random.new()
local states: { [Model]: State } = setmetatable({}, { __mode = "k" }) :: any

----------------------------------------------------------------------------------------------------
-- Character construction
----------------------------------------------------------------------------------------------------

local function newPart(name: string, size: Vector3, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.Massless = true
	part.Parent = parent
	return part
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

-- Simple blocky figure used when CreateHumanoidModelFromDescription fails. Uses R15 part names so the
-- same outfit/accessory code works. Root center sits 3 studs above the feet.
local function buildFallback(skin: Color3): Model
	local model = Instance.new("Model")
	model.Name = "Employee"

	local root = newPart("HumanoidRootPart", Vector3.new(2, 2, 1), skin, model)
	root.Transparency = 1
	root.Anchored = true
	root.CFrame = CFrame.new(0, 3, 0)
	model.PrimaryPart = root

	local function limb(name: string, size: Vector3, offset: Vector3)
		local part = newPart(name, size, skin, model)
		part.CFrame = root.CFrame * CFrame.new(offset)
		weld(root, part)
	end
	limb("UpperTorso", Vector3.new(2, 2, 1), Vector3.new(0, 0, 0))
	limb("Head", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 1.6, 0))
	limb("LeftUpperArm", Vector3.new(0.8, 2, 0.8), Vector3.new(-1.4, 0, 0))
	limb("RightUpperArm", Vector3.new(0.8, 2, 0.8), Vector3.new(1.4, 0, 0))
	limb("LeftUpperLeg", Vector3.new(0.9, 2, 0.9), Vector3.new(-0.5, -2, 0))
	limb("RightUpperLeg", Vector3.new(0.9, 2, 0.9), Vector3.new(0.5, -2, 0))
	return model
end

local function buildCharacter(skin: Color3): (Model, boolean)
	local ok, result = pcall(function()
		local desc = Instance.new("HumanoidDescription")
		desc.HeadColor = skin
		desc.TorsoColor = skin
		desc.LeftArmColor = skin
		desc.RightArmColor = skin
		desc.LeftLegColor = skin
		desc.RightLegColor = skin
		local character = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
		desc:Destroy()
		return character
	end)
	if ok and result ~= nil then
		local character = result :: Model
		if character:FindFirstChild("HumanoidRootPart") and character:FindFirstChild("Head") then
			return character, true
		end
		character:Destroy()
	else
		warn("[EmployeeService] CreateHumanoidModelFromDescription failed, using fallback figure: " .. tostring(result))
	end
	return buildFallback(skin), false
end

local function paint(model: Model, names: { string }, color: Color3)
	for _, name in names do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			part.Color = color
		end
	end
end

local function addCosmetics(model: Model, head: BasePart, torso: BasePart?, role: string, shirt: Color3)
	-- Face (only if the description produced none).
	if head:FindFirstChildOfClass("Decal") == nil then
		local frontZ = -head.Size.Z / 2
		local dark = Color3.fromRGB(30, 30, 35)
		for _, side in { -1, 1 } do
			local eye = newPart("Eye", Vector3.new(0.14, 0.2, 0.05), dark, model)
			eye.CFrame = head.CFrame * CFrame.new(side * head.Size.X * 0.2, head.Size.Y * 0.05, frontZ)
			weld(head, eye)
		end
		local smile = newPart("Smile", Vector3.new(head.Size.X * 0.35, 0.07, 0.05), dark, model)
		smile.CFrame = head.CFrame * CFrame.new(0, -head.Size.Y * 0.2, frontZ)
		weld(head, smile)
	end

	if role == "cashier" then
		-- Name badge on the chest.
		if torso then
			local badge = newPart("NameBadge", Vector3.new(0.55, 0.3, 0.08), Color3.fromRGB(250, 250, 250), model)
			badge.CFrame = torso.CFrame * CFrame.new(0.45, torso.Size.Y * 0.25, -torso.Size.Z / 2 - 0.04)
			weld(torso, badge)
		end
	else
		-- Cap in the shirt color: round crown + brim.
		local crown = newPart("CapCrown", Vector3.new(0.4, head.Size.X * 1.1, head.Size.Z * 1.1), shirt, model)
		crown.Shape = Enum.PartType.Cylinder
		crown.CFrame = head.CFrame * CFrame.new(0, head.Size.Y / 2, 0) * CFrame.Angles(0, 0, math.pi / 2)
		weld(head, crown)
		local brim = newPart("CapBrim", Vector3.new(head.Size.X * 0.85, 0.1, 0.55), shirt:Lerp(Color3.new(0, 0, 0), 0.2), model)
		brim.CFrame = head.CFrame * CFrame.new(0, head.Size.Y / 2 - 0.05, -head.Size.Z / 2 - 0.2)
		weld(head, brim)
	end
end

local function buildBillboard(head: BasePart, role: string, level: number)
	local gui = Instance.new("BillboardGui")
	gui.Name = "NameGui"
	gui.Adornee = head
	gui.Size = UDim2.new(0, 120, 0, 36)
	gui.StudsOffset = Vector3.new(0, 3, 0)
	gui.MaxDistance = 50
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0

	local roleLabel = Instance.new("TextLabel")
	roleLabel.Name = "RoleLabel"
	roleLabel.BackgroundTransparency = 1
	roleLabel.Size = UDim2.new(1, 0, 0.6, 0)
	roleLabel.Position = UDim2.new(0, 0, 0, 0)
	roleLabel.Font = Enum.Font.GothamBold
	roleLabel.TextScaled = true
	roleLabel.TextColor3 = Color3.new(1, 1, 1)
	roleLabel.TextStrokeTransparency = 0.4
	roleLabel.Text = role -- placeholder, the client localizes via TextKey
	roleLabel:SetAttribute("TextKey", "role_" .. role)
	roleLabel.Parent = gui

	local levelLabel = Instance.new("TextLabel")
	levelLabel.Name = "LevelLabel"
	levelLabel.BackgroundTransparency = 1
	levelLabel.Size = UDim2.new(1, 0, 0.4, 0)
	levelLabel.Position = UDim2.new(0, 0, 0.6, 0)
	levelLabel.Font = Enum.Font.GothamMedium
	levelLabel.TextScaled = true
	levelLabel.TextColor3 = Color3.fromRGB(255, 235, 140)
	levelLabel.TextStrokeTransparency = 0.5
	levelLabel.Text = "Lv " .. tostring(level)
	levelLabel.Parent = gui

	gui.Parent = head
end

local function buildEmitter(model: Model): ParticleEmitter?
	local isFallback = model:FindFirstChild("RightHand") == nil
	local hand = model:FindFirstChild("RightHand") or model:FindFirstChild("RightUpperArm")
	if hand == nil or not hand:IsA("BasePart") then
		return nil
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "WorkAttachment"
	attachment.Position = if isFallback then Vector3.new(0, -1, 0) else Vector3.new(0, -0.3, 0)
	attachment.Parent = hand

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "WorkSparks"
	emitter.Enabled = false
	emitter.Rate = 14
	emitter.Lifetime = NumberRange.new(0.25, 0.5)
	emitter.Speed = NumberRange.new(4, 8)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -8, 0)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new(0.35, 0)
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 240, 150), Color3.fromRGB(255, 140, 40))
	emitter.Parent = attachment
	return emitter
end

----------------------------------------------------------------------------------------------------
-- Motion
----------------------------------------------------------------------------------------------------

local function cancelTween(tween: Tween?)
	if tween then
		tween:Cancel()
	end
end

local function idleLoop(state: State)
	while state.model.Parent ~= nil do
		task.wait(2.5 + rng:NextNumber() * 3)
		if state.model.Parent == nil then
			break
		end
		if not state.working then
			local yaw = math.rad(rng:NextNumber(-IDLE_YAW_DEGREES, IDLE_YAW_DEGREES))
			local tween = TweenService:Create(
				state.root,
				TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ CFrame = state.baseCF * CFrame.Angles(0, yaw, 0) }
			)
			state.idleTween = tween
			tween:Play()
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------------------------------

local function getEmployeesFolder(plotIndex: number): Folder
	local root = Workspace:FindFirstChild("Employees")
	if root == nil or not root:IsA("Folder") then
		root = Instance.new("Folder")
		root.Name = "Employees"
		root.Parent = Workspace
	end
	local plotName = "Plot" .. tostring(plotIndex)
	local folder = root:FindFirstChild(plotName)
	if folder == nil or not folder:IsA("Folder") then
		folder = Instance.new("Folder")
		folder.Name = plotName
		folder.Parent = root
	end
	return folder :: Folder
end

--[[
	Creates an employee character at the given slot. YIELDS (character creation hits the web service),
	so call it from a yieldable thread. Replaces an existing employee in the same slot.
]]
function EmployeeService.spawn(plotIndex: number, role: string, slot: string, level: number): Model
	local def = Employees.byId[role]
	local shirt: Color3 = if def then def.shirtColor else Color3.fromRGB(120, 120, 130)
	local pants: Color3 = if def then def.pantsColor else Color3.fromRGB(40, 40, 50)
	if def == nil then
		warn("[EmployeeService] unknown role: " .. tostring(role))
	end

	-- World placement (ground level) and facing.
	local worldCF: CFrame
	local slotNumber: number? = nil
	if slot == "Cashier" then
		worldCF = Layout.toWorld(plotIndex, Layout.CASHIER.employee)
	else
		slotNumber = tonumber(string.match(slot, "^Bay(%d+)$"))
		local bay = if slotNumber then Layout.BAYS[slotNumber] else nil
		if bay == nil then
			warn("[EmployeeService] unknown slot: " .. tostring(slot) .. ", using Bay1")
			slotNumber = 1
			bay = Layout.BAYS[1]
		end
		worldCF = Layout.toWorld(plotIndex, bay.employee)
		local carPos: Vector3 = Layout.toWorld(plotIndex, bay.car).Position
		local standPos = worldCF.Position
		local toCar = Vector3.new(carPos.X - standPos.X, 0, carPos.Z - standPos.Z)
		if toCar.Magnitude > 0.01 then
			worldCF = CFrame.lookAt(standPos, standPos + toCar)
		end
	end

	local skin = SKIN_TONES[rng:NextInteger(1, #SKIN_TONES)]
	local model, isRealCharacter = buildCharacter(skin)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	local head = model:FindFirstChild("Head") :: BasePart
	local humanoid = model:FindFirstChildOfClass("Humanoid")

	-- Outfit.
	paint(model, SHIRT_PARTS, shirt)
	paint(model, PANTS_PARTS, pants)
	if isRealCharacter then
		paint(model, SHOE_PARTS, SHOE_COLOR)
	end

	-- Never fall, never get pushed, never block players.
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.BreakJointsOnDeath = false
		humanoid.RequiresNeck = false
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
		end
	end
	root.Anchored = true

	-- Feet on the ground: root center = hip height + half root height.
	local hip = FALLBACK_HIP_HEIGHT
	if humanoid and humanoid.HipHeight > 0 then
		hip = humanoid.HipHeight
	end
	local baseCF = worldCF + Vector3.new(0, Layout.GROUND_Y + hip + root.Size.Y / 2, 0)
	model.PrimaryPart = root
	model:PivotTo(baseCF)

	-- Accessories are placed after the pivot so their offsets use the final head/torso positions.
	local torso = model:FindFirstChild("UpperTorso")
	addCosmetics(model, head, if torso and torso:IsA("BasePart") then torso else nil, role, shirt)
	buildBillboard(head, role, level)
	local emitter = buildEmitter(model)

	model.Name = role .. "_" .. slot
	model:SetAttribute("Role", role)
	model:SetAttribute("PlotIndex", plotIndex)
	model:SetAttribute("Slot", slot)
	model:SetAttribute("Level", level)

	local folder = getEmployeesFolder(plotIndex)
	for _, existing in folder:GetChildren() do
		if existing:GetAttribute("Slot") == slot then
			existing:Destroy()
		end
	end
	model.Parent = folder

	local state: State = {
		model = model,
		root = root,
		baseCF = baseCF,
		working = false,
		emitter = emitter,
		idleTween = nil,
		bobTween = nil,
	}
	states[model] = state
	model.Destroying:Connect(function()
		cancelTween(state.idleTween)
		cancelTween(state.bobTween)
		states[model] = nil
	end)
	task.spawn(idleLoop, state)

	return model
end

function EmployeeService.setWorking(model: Model, working: boolean)
	local state = states[model]
	if state == nil or state.working == working then
		return
	end
	state.working = working

	cancelTween(state.idleTween)
	state.idleTween = nil
	cancelTween(state.bobTween)
	state.bobTween = nil
	state.root.CFrame = state.baseCF

	if state.emitter then
		state.emitter.Enabled = working
	end
	if working then
		local tween = TweenService:Create(
			state.root,
			TweenInfo.new(BOB_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ CFrame = state.baseCF + Vector3.new(0, BOB_HEIGHT, 0) }
		)
		state.bobTween = tween
		tween:Play()
	end
end

function EmployeeService.setLevel(model: Model, level: number)
	model:SetAttribute("Level", level)
	local label = model:FindFirstChild("LevelLabel", true)
	if label and label:IsA("TextLabel") then
		label.Text = "Lv " .. tostring(level)
	end
end

function EmployeeService.clearPlot(plotIndex: number)
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

return EmployeeService
