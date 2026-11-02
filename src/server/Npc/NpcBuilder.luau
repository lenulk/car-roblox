--!strict
-- NpcBuilder: charming R15 characters built from colors and small welded Parts (no asset ids), plus a
-- procedural animation system driven by Motor6D.Transform (walk / idle / work), and anchored-root
-- movement helpers (place / walkPath / turnTo). Server only.
--
-- Facing convention: a character's front is its root's -Z, so yaw = atan2(-look.X, -look.Z).
-- Joint sign convention used by the poses (Euler X on a hanging limb): positive swings it forward (-Z).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local NpcBuilder = {}

export type NpcOptions = {
	shirt: Color3,
	pants: Color3,
	skin: Color3?,
	accessory: string?, -- cap | mask | badge | apron | headset | tie
	hair: Color3?,
	hairStyle: number?, -- 0 none, 1 short, 2 long, 3 ponytail, 4 bun (random 1..4 when nil)
}

export type WalkController = { play: () -> (), stop: () -> (), setSpeed: (number) -> () }
export type Controller = { play: () -> (), stop: () -> () }
export type IdleController = { play: () -> (), stop: () -> (), wave: (number?) -> () }

local rng = Random.new()

local V3 = Vector3.new
local CF = CFrame.new
local IDENTITY = CFrame.new()
local SMOOTH = Enum.Material.SmoothPlastic
local TWO_PI = math.pi * 2

local DEFAULT_SKIN = Color3.fromRGB(241, 194, 125)
local SHOE_COLOR = Color3.fromRGB(38, 38, 44)
local INK = Color3.fromRGB(32, 32, 40)
local WHITE = Color3.fromRGB(250, 250, 250)
local BLACK = Color3.new(0, 0, 0)

local FACE_Z = -0.645 -- just in front of the head's face plane
local DEFAULT_ROOT_HEIGHT = 3

----------------------------------------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------------------------------------

local function getPart(model: Model, name: string): BasePart?
	local found = model:FindFirstChild(name)
	if found and found:IsA("BasePart") then
		return found
	end
	return nil
end

local function angleDiff(target: number, current: number): number
	return ((target - current + math.pi) % TWO_PI) - math.pi
end

local function yawOf(cf: CFrame): number
	local _, yaw, _ = cf:ToEulerAnglesYXZ()
	return yaw
end

-- Creates a small unanchored part welded to `base` at `offset` (relative to base). Weld with explicit
-- C0 keeps the offset correct no matter where the parts currently are.
local function attach(
	model: Model,
	base: BasePart,
	name: string,
	size: Vector3,
	color: Color3,
	offset: CFrame,
	shape: Enum.PartType?,
	material: Enum.Material?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape or Enum.PartType.Block
	part.Size = size
	part.Color = color
	part.Material = material or SMOOTH
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.Massless = true
	part.CFrame = base.CFrame * offset
	local weld = Instance.new("Weld")
	weld.Part0 = base
	weld.Part1 = part
	weld.C0 = offset
	weld.Parent = part
	part.Parent = model
	return part
end

-- A thin bar from point a to point b (both in `base`-local coordinates).
local function bar(model: Model, base: BasePart, name: string, a: Vector3, b: Vector3, thick: number, color: Color3): Part
	local d = b - a
	local len = math.max(d.Magnitude, 0.01)
	local up = if math.abs(d.Y) > len * 0.98 then V3(0, 0, 1) else V3(0, 1, 0)
	local cf = CFrame.lookAt((a + b) / 2, b, up)
	return attach(model, base, name, V3(thick, thick, len), color, cf)
end

local function darker(color: Color3, amount: number): Color3
	return color:Lerp(BLACK, amount)
end

----------------------------------------------------------------------------------------------------
-- Base rig: real R15 (cached template) or a blocky fallback with the same part / joint names
----------------------------------------------------------------------------------------------------

local REQUIRED_PARTS = {
	"HumanoidRootPart", "LowerTorso", "UpperTorso", "Head",
	"LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot",
}

local function isValidRig(model: Model): boolean
	for _, name in REQUIRED_PARTS do
		if getPart(model, name) == nil then
			return false
		end
	end
	if model:FindFirstChildOfClass("Humanoid") == nil then
		return false
	end
	for _, jointName in { "LeftHip", "RightHip", "LeftShoulder", "RightShoulder", "Waist", "Neck" } do
		if model:FindFirstChild(jointName, true) == nil then
			return false
		end
	end
	return true
end

local function stripExtras(model: Model)
	for _, child in model:GetChildren() do
		if
			child:IsA("Clothing")
			or child:IsA("BodyColors")
			or child:IsA("ShirtGraphic")
			or child:IsA("Accessory")
			or child:IsA("BaseScript")
		then
			child:Destroy()
		end
	end
end

local function tryCreateReal(): Model?
	local ok, result = pcall(function()
		local description = Instance.new("HumanoidDescription")
		local created = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
		description:Destroy()
		return created
	end)
	if ok and typeof(result) == "Instance" and (result :: Instance):IsA("Model") then
		local created = result :: Model
		if isValidRig(created) then
			stripExtras(created)
			return created
		end
		created:Destroy()
		warn("[NpcBuilder] R15 model from description was incomplete, using fallback rig")
	else
		warn("[NpcBuilder] CreateHumanoidModelFromDescription failed, using fallback rig: " .. tostring(result))
	end
	return nil
end

-- Blocky figure with R15 part names and Motor6D joints. Root center is 3 studs above the feet
-- (HipHeight 2 + half root height 1).
local function buildFallback(): Model
	local model = Instance.new("Model")
	model.Name = "Npc"

	local function mk(name: string, size: Vector3, center: Vector3): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.Color = DEFAULT_SKIN
		part.Material = SMOOTH
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Anchored = false
		part.CanCollide = false
		part.CanTouch = false
		part.Massless = true
		part.CFrame = CF(center)
		part.Parent = model
		return part
	end

	local root = mk("HumanoidRootPart", V3(2, 2, 1), V3(0, 0, 0))
	root.Transparency = 1
	root.Anchored = true
	model.PrimaryPart = root

	local lowerTorso = mk("LowerTorso", V3(2, 0.4, 1), V3(0, -0.8, 0))
	local upperTorso = mk("UpperTorso", V3(2, 1.6, 1), V3(0, 0.2, 0))
	local head = mk("Head", V3(1.25, 1.25, 1.25), V3(0, 1.64, 0))

	local function joint(name: string, part0: BasePart, part1: BasePart, position: Vector3)
		local motor = Instance.new("Motor6D")
		motor.Name = name
		motor.Part0 = part0
		motor.Part1 = part1
		motor.C0 = part0.CFrame:Inverse() * CF(position)
		motor.C1 = part1.CFrame:Inverse() * CF(position)
		motor.Parent = part1
	end

	joint("Root", root, lowerTorso, V3(0, -0.8, 0))
	joint("Waist", lowerTorso, upperTorso, V3(0, -0.6, 0))
	joint("Neck", upperTorso, head, V3(0, 1.0, 0))

	for _, side in { "Left", "Right" } do
		local sx = if side == "Left" then -1 else 1
		local upperArm = mk(side .. "UpperArm", V3(0.8, 0.9, 0.8), V3(sx * 1.4, 0.3, 0))
		local lowerArm = mk(side .. "LowerArm", V3(0.75, 0.8, 0.75), V3(sx * 1.4, -0.55, 0))
		local hand = mk(side .. "Hand", V3(0.8, 0.3, 0.8), V3(sx * 1.4, -1.1, 0))
		joint(side .. "Shoulder", upperTorso, upperArm, V3(sx * 1.4, 0.75, 0))
		joint(side .. "Elbow", upperArm, lowerArm, V3(sx * 1.4, -0.15, 0))
		joint(side .. "Wrist", lowerArm, hand, V3(sx * 1.4, -0.95, 0))

		local upperLeg = mk(side .. "UpperLeg", V3(1, 0.9, 1), V3(sx * 0.52, -1.45, 0))
		local lowerLeg = mk(side .. "LowerLeg", V3(0.9, 0.8, 0.9), V3(sx * 0.52, -2.3, 0))
		local foot = mk(side .. "Foot", V3(1, 0.3, 1.1), V3(sx * 0.52, -2.85, -0.05))
		joint(side .. "Hip", lowerTorso, upperLeg, V3(sx * 0.52, -1.0, 0))
		joint(side .. "Knee", upperLeg, lowerLeg, V3(sx * 0.52, -1.9, 0))
		joint(side .. "Ankle", lowerLeg, foot, V3(sx * 0.52, -2.7, 0))
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = 2
	humanoid.Parent = model
	return model
end

local template: Model? = nil
local templateLoading = false
local templateFailedAt = -math.huge
local TEMPLATE_RETRY_SECONDS = 60

-- May yield (first call talks to the web service). Later calls clone the cached template.
local function createBase(): Model
	if template == nil and not templateLoading and os.clock() - templateFailedAt > TEMPLATE_RETRY_SECONDS then
		templateLoading = true
		local created = tryCreateReal()
		templateLoading = false
		if created then
			template = created
		else
			templateFailedAt = os.clock()
		end
	else
		while templateLoading do
			task.wait(0.05)
		end
	end
	local source = template
	if source then
		return source:Clone() :: Model
	end
	return buildFallback()
end

----------------------------------------------------------------------------------------------------
-- Cosmetics
----------------------------------------------------------------------------------------------------

local function addFace(model: Model, head: BasePart)
	if head:FindFirstChildOfClass("Decal") ~= nil then
		return
	end
	for _, side in { -1, 1 } do
		attach(model, head, "Eye", V3(0.14, 0.22, 0.06), INK, CF(side * 0.24, 0.08, FACE_Z))
		attach(model, head, "EyeShine", V3(0.06, 0.06, 0.03), WHITE, CF(side * 0.24 + 0.03, 0.14, FACE_Z - 0.045))
		local cheek = attach(model, head, "Cheek", V3(0.22, 0.12, 0.04), Color3.fromRGB(255, 140, 150), CF(side * 0.4, -0.08, FACE_Z + 0.005))
		cheek.Transparency = 0.55
		attach(model, head, "SmileCorner", V3(0.12, 0.06, 0.05), INK, CF(side * 0.2, -0.16, FACE_Z) * CFrame.Angles(0, 0, side * 0.5))
	end
	attach(model, head, "Smile", V3(0.32, 0.06, 0.05), INK, CF(0, -0.2, FACE_Z))
end

local function addHair(model: Model, head: BasePart, color: Color3, style: number, hasCap: boolean, noFringe: boolean)
	if style == 0 then
		return
	end
	local function piece(name: string, size: Vector3, offset: CFrame, shape: Enum.PartType?)
		return attach(model, head, name, size, color, offset, shape)
	end
	if not hasCap then
		piece("HairTop", V3(1.4, 1.4, 1.4), CF(0, 0.28, 0.1), Enum.PartType.Ball)
		if not noFringe then
			piece("HairFringe", V3(1.05, 0.2, 0.2), CF(0, 0.5, -0.58))
		end
		if style == 4 then
			piece("HairBun", V3(0.55, 0.55, 0.55), CF(0, 0.92, 0.2), Enum.PartType.Ball)
		end
	end
	if style == 2 then
		piece("HairBack", V3(1.3, 1.5, 0.28), CF(0, -0.35, 0.7))
		piece("HairSideL", V3(0.22, 1.1, 0.5), CF(-0.66, -0.1, 0.3))
		piece("HairSideR", V3(0.22, 1.1, 0.5), CF(0.66, -0.1, 0.3))
	elseif style == 3 then
		piece("HairTie", V3(0.45, 0.45, 0.45), CF(0, 0.15, 0.75), Enum.PartType.Ball)
		piece("HairTail", V3(0.32, 1.0, 0.32), CF(0, -0.33, 0.9) * CFrame.Angles(-0.3, 0, 0))
	end
end

local function addCap(model: Model, head: BasePart, color: Color3)
	local crown = attach(model, head, "CapCrown", V3(0.5, 1.42, 1.42), color, CF(0, 0.5, 0.02) * CFrame.Angles(0, 0, math.pi / 2), Enum.PartType.Cylinder)
	crown:SetAttribute("Tint", "shirt")
	local button = attach(model, head, "CapButton", V3(0.17, 0.17, 0.17), color, CF(0, 0.78, 0.02), Enum.PartType.Ball)
	button:SetAttribute("Tint", "shirt")
	local brim = attach(model, head, "CapBrim", V3(1.1, 0.08, 0.62), darker(color, 0.2), CF(0, 0.33, -0.86) * CFrame.Angles(math.rad(-8), 0, 0))
	brim:SetAttribute("Tint", "shirtDark")
end

local function addMask(model: Model, head: BasePart, hairTop: boolean)
	local gray = Color3.fromRGB(95, 100, 112)
	local yellow = Color3.fromRGB(240, 200, 60)
	attach(model, head, "RespiratorBody", V3(0.75, 0.42, 0.38), gray, CF(0, -0.27, -0.7))
	for _, side in { -1, 1 } do
		attach(model, head, "RespiratorFilter", V3(0.22, 0.32, 0.32), yellow, CF(side * 0.36, -0.3, -0.82) * CFrame.Angles(0, math.pi / 2, 0), Enum.PartType.Cylinder)
	end
	attach(model, head, "RespiratorStrap", V3(0.09, 1.34, 1.34), INK, CF(0, -0.13, 0) * CFrame.Angles(0, 0, math.pi / 2), Enum.PartType.Cylinder)
	-- Goggles pushed up onto the forehead.
	local band = if hairTop then 1.58 else 1.38
	attach(model, head, "GoggleBand", V3(0.2, band, band), INK, CF(0, 0.42, 0) * CFrame.Angles(0, 0, math.pi / 2), Enum.PartType.Cylinder)
	local lensZ = if hairTop then -0.8 else -0.7
	for _, side in { -1, 1 } do
		local lens = attach(model, head, "GoggleLens", V3(0.14, 0.42, 0.42), Color3.fromRGB(130, 210, 255), CF(side * 0.3, 0.42, lensZ) * CFrame.Angles(0, math.pi / 2, 0), Enum.PartType.Cylinder)
		lens.Transparency = 0.25
	end
end

local function addHeadset(model: Model, head: BasePart, hairTop: boolean)
	local dark = Color3.fromRGB(35, 38, 46)
	local centerY = if hairTop then 0.28 else 0.0
	local radius = if hairTop then 0.77 else 0.68
	-- Band: arc of bars over the head.
	local previous: Vector3? = nil
	for _, degrees in { 10, 50, 90, 130, 170 } do
		local a = math.rad(degrees)
		local point = V3(math.cos(a) * radius, centerY + math.sin(a) * radius, 0.04)
		if previous then
			bar(model, head, "HeadsetBand", previous, point, 0.1, dark)
		end
		previous = point
	end
	for _, side in { -1, 1 } do
		local endY = centerY + math.sin(math.rad(10)) * radius
		local endX = math.cos(math.rad(10)) * radius
		bar(model, head, "HeadsetArm", V3(side * endX, endY, 0.04), V3(side * 0.7, 0.04, 0.04), 0.09, dark)
		attach(model, head, "HeadsetCup", V3(0.22, 0.5, 0.5), dark, CF(side * 0.72, 0.0, 0.04), Enum.PartType.Cylinder)
		local pad = attach(model, head, "HeadsetPad", V3(0.06, 0.38, 0.38), Color3.fromRGB(255, 120, 170), CF(side * 0.84, 0.0, 0.04), Enum.PartType.Cylinder)
		pad.Material = Enum.Material.Neon
	end
	bar(model, head, "MicBoom", V3(-0.74, -0.08, 0.0), V3(-0.46, -0.4, -0.6), 0.07, dark)
	attach(model, head, "MicTip", V3(0.17, 0.17, 0.17), Color3.fromRGB(235, 235, 240), CF(-0.45, -0.41, -0.63), Enum.PartType.Ball)
end

local function addBadge(model: Model, torso: BasePart)
	local z = -torso.Size.Z / 2 - 0.03
	local x = torso.Size.X * 0.22
	local y = torso.Size.Y * 0.2
	attach(model, torso, "NameBadge", V3(0.5, 0.32, 0.06), WHITE, CF(x, y, z))
	attach(model, torso, "NameBadgeStripe", V3(0.5, 0.09, 0.065), Color3.fromRGB(60, 140, 235), CF(x, y + 0.115, z - 0.002))
	attach(model, torso, "NameBadgeLine", V3(0.34, 0.04, 0.065), Color3.fromRGB(110, 115, 130), CF(x, y - 0.04, z - 0.002))
end

local function addApron(model: Model, torso: BasePart)
	local apron = Color3.fromRGB(150, 105, 62)
	local dark = darker(apron, 0.25)
	local z = -torso.Size.Z / 2 - 0.05
	attach(model, torso, "ApronPanel", V3(1.5, 1.7, 0.1), apron, CF(0, -0.25, z))
	attach(model, torso, "ApronPocket", V3(0.8, 0.45, 0.06), dark, CF(0, -0.5, z - 0.06))
	attach(model, torso, "ApronBelt", V3(torso.Size.X + 0.1, 0.12, torso.Size.Z + 0.1), dark, CF(0, -0.1, 0))
	for _, side in { -1, 1 } do
		attach(model, torso, "ApronStrap", V3(0.12, 0.55, 0.06), dark, CF(side * 0.45, 0.55, z))
	end
end

local function addTie(model: Model, torso: BasePart, jacket: Color3)
	local z = -torso.Size.Z / 2 - 0.02
	attach(model, torso, "ShirtPanel", V3(0.62, 1.1, 0.04), WHITE, CF(0, 0.2, z))
	for _, side in { -1, 1 } do
		bar(model, torso, "Lapel", V3(side * 0.42, 0.78, z - 0.03), V3(side * 0.12, -0.25, z - 0.03), 0.12, jacket:Lerp(WHITE, 0.14))
	end
	local red = Color3.fromRGB(196, 38, 54)
	attach(model, torso, "TieKnot", V3(0.22, 0.18, 0.07), red, CF(0, 0.6, z - 0.03))
	attach(model, torso, "TieBlade", V3(0.2, 0.8, 0.06), red, CF(0, 0.12, z - 0.04))
	attach(model, torso, "TieClip", V3(0.16, 0.04, 0.07), Color3.fromRGB(225, 200, 110), CF(0, 0.3, z - 0.05))
end

local function addTote(model: Model, color: Color3)
	local hand = getPart(model, "RightHand")
	if hand == nil then
		return
	end
	local dark = darker(color, 0.3)
	attach(model, hand, "BagBody", V3(0.85, 0.9, 0.38), color, CF(0.1, -0.95, 0))
	attach(model, hand, "BagStripe", V3(0.87, 0.14, 0.4), dark, CF(0.1, -0.7, 0))
	bar(model, hand, "BagHandle", V3(-0.2, -0.45, 0), V3(0.1, -0.15, 0), 0.05, dark)
	bar(model, hand, "BagHandle", V3(0.4, -0.45, 0), V3(0.1, -0.15, 0), 0.05, dark)
end

local function addBackpack(model: Model, color: Color3)
	local torso = getPart(model, "UpperTorso")
	if torso == nil then
		return
	end
	local dark = darker(color, 0.3)
	local back = torso.Size.Z / 2 + 0.25
	attach(model, torso, "PackBody", V3(1.25, 1.35, 0.5), color, CF(0, 0.1, back))
	attach(model, torso, "PackPocket", V3(0.8, 0.5, 0.2), dark, CF(0, -0.2, back + 0.3))
	for _, side in { -1, 1 } do
		attach(model, torso, "PackStrap", V3(0.16, 1.3, 0.06), dark, CF(side * 0.55, 0.1, -torso.Size.Z / 2 - 0.03))
	end
end

----------------------------------------------------------------------------------------------------
-- Outfit colors
----------------------------------------------------------------------------------------------------

-- Recolors the shirt (and the cap, jacket etc. that follow it) of a character made by NpcBuilder.
function NpcBuilder.applyShirt(model: Model, shirt: Color3)
	model:SetAttribute("NpcShirt", shirt)
	local accessory: any = model:GetAttribute("NpcAccessory")
	local skinAttr: any = model:GetAttribute("NpcSkin")
	local skin = if typeof(skinAttr) == "Color3" then (skinAttr :: Color3) else DEFAULT_SKIN
	local longSleeves = model:GetAttribute("NpcLongSleeves") == true
	local body = shirt
	if accessory == "tie" then
		body = darker(shirt, 0.22) -- jacket
	end
	for _, name in { "UpperTorso", "LeftUpperArm", "RightUpperArm" } do
		local part = getPart(model, name)
		if part then
			part.Color = body
		end
	end
	for _, name in { "LeftLowerArm", "RightLowerArm" } do
		local part = getPart(model, name)
		if part then
			part.Color = if longSleeves then body else skin
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local tint: any = d:GetAttribute("Tint")
			if tint == "shirt" then
				d.Color = shirt
			elseif tint == "shirtDark" then
				d.Color = darker(shirt, 0.2)
			end
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Character
----------------------------------------------------------------------------------------------------

--[[
	Builds a complete NPC model (unparented, root anchored, nothing collides). MAY YIELD the first time
	(creates an R15 rig through the web service, then reuses a cached clone).
]]
function NpcBuilder.character(opts: NpcOptions): Model
	local model = createBase()
	model.Name = "Npc"
	stripExtras(model)

	local skin = opts.skin or DEFAULT_SKIN
	local accessory = opts.accessory

	local root = getPart(model, "HumanoidRootPart") :: BasePart
	local head = getPart(model, "Head") :: BasePart
	local torso = getPart(model, "UpperTorso") :: BasePart
	model.PrimaryPart = root
	root.Anchored = true

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.BreakJointsOnDeath = false
		humanoid.RequiresNeck = false
	end

	-- Body colors.
	for _, name in { "Head", "LeftHand", "RightHand" } do
		local part = getPart(model, name)
		if part then
			part.Color = skin
		end
	end
	for _, name in { "LowerTorso", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg" } do
		local part = getPart(model, name)
		if part then
			part.Color = opts.pants
		end
	end
	for _, name in { "LeftFoot", "RightFoot" } do
		local part = getPart(model, name)
		if part then
			part.Color = SHOE_COLOR
		end
	end

	model:SetAttribute("NpcSkin", skin)
	model:SetAttribute("NpcAccessory", accessory)
	model:SetAttribute("NpcLongSleeves", accessory == "mask" or accessory == "tie")
	local rootHeight = DEFAULT_ROOT_HEIGHT
	if humanoid and humanoid.HipHeight > 0 then
		rootHeight = humanoid.HipHeight + root.Size.Y / 2
	end
	model:SetAttribute("NpcRootHeight", rootHeight)

	-- Face, hair, accessory.
	addFace(model, head)
	local hairTop = false
	if opts.hair then
		local style = opts.hairStyle or rng:NextInteger(1, 4)
		local hasCap = accessory == "cap"
		addHair(model, head, opts.hair, style, hasCap, accessory == "mask")
		hairTop = style ~= 0 and not hasCap
	end
	if accessory == "cap" then
		addCap(model, head, opts.shirt)
	elseif accessory == "mask" then
		addMask(model, head, hairTop)
	elseif accessory == "badge" then
		addBadge(model, torso)
	elseif accessory == "apron" then
		addApron(model, torso)
	elseif accessory == "headset" then
		addHeadset(model, head, hairTop)
	elseif accessory == "tie" then
		addTie(model, torso, darker(opts.shirt, 0.22))
	end
	NpcBuilder.applyShirt(model, opts.shirt)

	-- Nothing collides, nothing is touched.
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
		end
	end
	root.Anchored = true
	return model
end

-- Holds a small tool in the right hand: "hammer", "wrench", "spray", or nil to remove it.
function NpcBuilder.setTool(model: Model, kind: string?)
	for _, child in model:GetChildren() do
		if child:GetAttribute("NpcTool") == true then
			child:Destroy()
		end
	end
	local hand = getPart(model, "RightHand")
	if kind == nil or hand == nil then
		return
	end
	local parts: { Part } = {}
	-- Tools extend along the hand's -Z, so with the arm raised forward they point up.
	if kind == "hammer" then
		table.insert(parts, attach(model, hand, "ToolHandle", V3(0.16, 0.16, 1.3), Color3.fromRGB(150, 100, 55), CF(0, -0.2, -0.3)))
		table.insert(parts, attach(model, hand, "ToolHead", V3(0.75, 0.36, 0.36), Color3.fromRGB(120, 126, 138), CF(0, -0.2, -0.95), nil, Enum.Material.Metal))
	elseif kind == "wrench" then
		local steel = Color3.fromRGB(165, 170, 182)
		table.insert(parts, attach(model, hand, "ToolHandle", V3(0.16, 0.12, 1.25), steel, CF(0, -0.2, -0.3), nil, Enum.Material.Metal))
		table.insert(parts, attach(model, hand, "ToolJawBase", V3(0.52, 0.14, 0.14), steel, CF(0, -0.2, -0.85), nil, Enum.Material.Metal))
		for _, side in { -1, 1 } do
			table.insert(parts, attach(model, hand, "ToolJaw", V3(0.14, 0.14, 0.36), steel, CF(side * 0.19, -0.2, -1.0), nil, Enum.Material.Metal))
		end
	elseif kind == "spray" then
		table.insert(parts, attach(model, hand, "ToolCan", V3(0.9, 0.42, 0.42), Color3.fromRGB(200, 205, 215), CF(0, -0.2, -0.4) * CFrame.Angles(0, math.pi / 2, 0), Enum.PartType.Cylinder))
		table.insert(parts, attach(model, hand, "ToolCanBand", V3(0.4, 0.44, 0.44), Color3.fromRGB(70, 160, 240), CF(0, -0.2, -0.4) * CFrame.Angles(0, math.pi / 2, 0), Enum.PartType.Cylinder))
		table.insert(parts, attach(model, hand, "ToolNozzle", V3(0.14, 0.14, 0.18), Color3.fromRGB(220, 60, 60), CF(0, -0.2, -0.95)))
	end
	for _, part in parts do
		part:SetAttribute("NpcTool", true)
	end
end

function NpcBuilder.rootHeight(model: Model): number
	local value: any = model:GetAttribute("NpcRootHeight")
	if type(value) == "number" then
		return value :: number
	end
	return DEFAULT_ROOT_HEIGHT
end

----------------------------------------------------------------------------------------------------
-- Shoppers
----------------------------------------------------------------------------------------------------

local SKIN_TONES = {
	Color3.fromRGB(255, 219, 172),
	Color3.fromRGB(241, 194, 125),
	Color3.fromRGB(224, 172, 105),
	Color3.fromRGB(198, 134, 66),
	Color3.fromRGB(141, 85, 36),
	Color3.fromRGB(255, 204, 153),
	Color3.fromRGB(110, 70, 40),
}
local HAIR_COLORS = {
	Color3.fromRGB(35, 28, 24),
	Color3.fromRGB(80, 52, 30),
	Color3.fromRGB(140, 90, 40),
	Color3.fromRGB(222, 184, 90),
	Color3.fromRGB(170, 60, 40),
	Color3.fromRGB(60, 60, 70),
	Color3.fromRGB(235, 235, 240),
	Color3.fromRGB(225, 90, 150),
}
local SHIRT_COLORS = {
	Color3.fromRGB(235, 90, 80),
	Color3.fromRGB(250, 170, 60),
	Color3.fromRGB(245, 220, 90),
	Color3.fromRGB(110, 200, 110),
	Color3.fromRGB(70, 190, 190),
	Color3.fromRGB(90, 150, 240),
	Color3.fromRGB(150, 110, 230),
	Color3.fromRGB(240, 130, 190),
	Color3.fromRGB(245, 245, 245),
	Color3.fromRGB(120, 130, 150),
}
local PANTS_COLORS = {
	Color3.fromRGB(50, 70, 120),
	Color3.fromRGB(40, 40, 48),
	Color3.fromRGB(110, 90, 70),
	Color3.fromRGB(80, 100, 85),
	Color3.fromRGB(150, 150, 160),
	Color3.fromRGB(120, 60, 70),
}

local function pick<T>(list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

function NpcBuilder.randomShopper(): Model
	local shirt = pick(SHIRT_COLORS)
	local accessory: string? = nil
	if rng:NextNumber() < 0.28 then
		accessory = "cap"
	end
	local model = NpcBuilder.character({
		shirt = shirt,
		pants = pick(PANTS_COLORS),
		skin = pick(SKIN_TONES),
		accessory = accessory,
		hair = pick(HAIR_COLORS),
		hairStyle = if rng:NextNumber() < 0.08 then 0 else rng:NextInteger(1, 4),
	})
	model.Name = "Shopper"

	-- A cap in its own color instead of the shirt color.
	if accessory == "cap" then
		local capColor = pick(SHIRT_COLORS)
		for _, name in { "CapCrown", "CapButton", "CapBrim" } do
			local part = getPart(model, name)
			if part then
				part:SetAttribute("Tint", nil)
				part.Color = if name == "CapBrim" then darker(capColor, 0.2) else capColor
			end
		end
	end

	local roll = rng:NextNumber()
	if roll < 0.35 then
		addTote(model, pick(SHIRT_COLORS))
	elseif roll < 0.55 then
		addBackpack(model, pick(SHIRT_COLORS))
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
		end
	end
	return model
end

----------------------------------------------------------------------------------------------------
-- Procedural animation: layers (walk / idle / work) blended per model, one shared Heartbeat
----------------------------------------------------------------------------------------------------

type Pose = { [string]: Vector3 }

type Rig = {
	model: Model,
	joints: { [string]: Motor6D },
	layers: { Layer },
	acc: Pose,
	dead: boolean,
}

type Layer = {
	rig: Rig,
	kind: string, -- "walk" | "idle" | "work"
	style: string,
	weight: number,
	target: number,
	time: number,
	rate: number, -- time units per second (walk: radians of gait phase)
	speed: number, -- walk speed in studs / second
	waveStart: number,
	waveUntil: number,
}

local JOINT_NAMES = {
	"Root", "Waist", "Neck",
	"LeftShoulder", "RightShoulder", "LeftElbow", "RightElbow",
	"LeftHip", "RightHip", "LeftKnee", "RightKnee", "LeftAnkle", "RightAnkle",
}
local JOINT_SET: { [string]: boolean } = {}
for _, name in JOINT_NAMES do
	JOINT_SET[name] = true
end
local POSE_KEYS: { string } = table.clone(JOINT_NAMES)
table.insert(POSE_KEYS, "RootPos")

local FADE_SECONDS = 0.22
local CYCLE_LENGTH = 7 -- studs travelled per full gait cycle (two steps)
local DEFAULT_WALK_SPEED = 7
local HIP_AMP = 0.55
local KNEE_AMP = 0.95
local ARM_AMP = 0.5

local rigs: { [Model]: Rig } = {}
local activeRigs: { [Rig]: boolean } = {}
local connection: RBXScriptConnection? = nil
local scratch: Pose = {}

local function getRig(model: Model): Rig
	local existing = rigs[model]
	if existing then
		return existing
	end
	local joints: { [string]: Motor6D } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") and JOINT_SET[d.Name] and joints[d.Name] == nil then
			joints[d.Name] = d
		end
	end
	local rig: Rig = { model = model, joints = joints, layers = {}, acc = {}, dead = false }
	rigs[model] = rig
	model.Destroying:Connect(function()
		rig.dead = true
		activeRigs[rig] = nil
		rigs[model] = nil
	end)
	return rig
end

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function poseWalk(layer: Layer, t: number, pose: Pose)
	local amp = math.clamp(layer.speed / 6, 0, 1.25)
	local s, c = math.sin(t), math.cos(t)
	local hipL = HIP_AMP * amp * s
	local hipR = -hipL
	local kneeL = -(KNEE_AMP * amp * math.max(0, c) + 0.06 * amp)
	local kneeR = -(KNEE_AMP * amp * math.max(0, -c) + 0.06 * amp)
	pose.LeftHip = V3(hipL, 0, 0)
	pose.RightHip = V3(hipR, 0, 0)
	pose.LeftKnee = V3(kneeL, 0, 0)
	pose.RightKnee = V3(kneeR, 0, 0)
	pose.LeftAnkle = V3(-(hipL + kneeL) * 0.6, 0, 0)
	pose.RightAnkle = V3(-(hipR + kneeR) * 0.6, 0, 0)
	pose.LeftShoulder = V3(-ARM_AMP * amp * s, 0, -0.06)
	pose.RightShoulder = V3(ARM_AMP * amp * s, 0, 0.06)
	pose.LeftElbow = V3(0.2 + 0.45 * amp * math.max(0, -s), 0, 0)
	pose.RightElbow = V3(0.2 + 0.45 * amp * math.max(0, s), 0, 0)
	pose.Root = V3(0, -0.08 * amp * s, 0.03 * amp * s)
	pose.Waist = V3(-0.04 * amp, 0.16 * amp * s, -0.03 * amp * s)
	pose.Neck = V3(0.03 - 0.02 * amp * math.cos(2 * t), -0.08 * amp * s, 0)
	pose.RootPos = V3(0, amp * (0.07 * math.cos(2 * t) - 0.03), 0)
end

local function poseIdle(layer: Layer, t: number, pose: Pose)
	local breath = math.sin(t * 2.1)
	local sway = math.sin(t * 0.9)
	pose.RootPos = V3(0, 0.02 * breath, 0)
	pose.Root = V3(0, 0.03 * math.sin(t * 0.5), 0.02 * sway)
	pose.Waist = V3(0.01 + 0.015 * breath, 0.04 * math.sin(t * 0.6 + 1), -0.02 * sway)
	pose.Neck = V3(0.02 * math.sin(t * 0.8), 0.2 * (math.sin(t * 0.37) + 0.5 * math.sin(t * 0.91)), 0)
	local armSwing = 0.04 * math.sin(t * 1.3)
	pose.LeftShoulder = V3(armSwing, 0, -0.07 - 0.02 * breath)
	pose.LeftElbow = V3(0.12 + 0.02 * breath, 0, 0)
	local rightShoulder = V3(-armSwing, 0, 0.07 + 0.02 * breath)
	local rightElbow = V3(0.12 + 0.02 * breath, 0, 0)

	if layer.waveUntil > t then
		local e = smooth(math.min((t - layer.waveStart) / 0.35, (layer.waveUntil - t) / 0.35))
		rightShoulder = rightShoulder:Lerp(V3(0.1, 0, 2.3), e)
		rightElbow = rightElbow:Lerp(V3(0, 0, 0.25 + 0.55 * math.sin((t - layer.waveStart) * 12)), e)
		pose.Neck = pose.Neck:Lerp(V3(0, 0, 0.06), e)
	end
	pose.RightShoulder = rightShoulder
	pose.RightElbow = rightElbow
end

local function poseWork(layer: Layer, t: number, pose: Pose)
	local style = layer.style
	if style == "spray" then
		local sweep = math.sin(t * 2.4)
		pose.RightShoulder = V3(1.45, 0, 0.4 * sweep)
		pose.RightElbow = V3(0.15, 0, 0)
		pose.LeftShoulder = V3(0.15, 0, -0.25)
		pose.LeftElbow = V3(0.95, 0, 0)
		pose.Waist = V3(-0.05, 0.14 * sweep, 0)
		pose.Neck = V3(-0.05, -0.1 * sweep, 0)
		pose.Root = V3(0, -0.04 * sweep, 0.02 * sweep)
		pose.RootPos = V3(0, 0.01 * math.sin(t * 2.1), 0)
	elseif style == "reach" then
		local k = math.sin(t * 2.2)
		pose.RightShoulder = V3(1.25 + 0.25 * k, 0, 0.12)
		pose.RightElbow = V3(0.55 + 0.25 * math.sin(t * 2.2 + 1), 0, 0)
		pose.LeftShoulder = V3(0.25, 0, -0.1)
		pose.LeftElbow = V3(0.6 + 0.1 * math.sin(t * 1.5), 0, 0)
		pose.Waist = V3(-0.06 + 0.02 * k, 0.1 * math.sin(t * 1.1), 0)
		pose.Neck = V3(-0.08, 0.35 * math.sin(t * 1.1), 0)
		pose.RootPos = V3(0, 0.01 * math.sin(t * 2.1), 0)
		pose.Root = V3(0, 0.03 * math.sin(t * 1.1), 0)
	else
		-- hammer: slow wind-up, fast strike, short pause
		local p = (t * 1.15) % 1
		local u: number
		if p < 0.65 then
			u = smooth(p / 0.65)
		else
			local q = (p - 0.65) / 0.35
			u = 1 - q * q
		end
		local down = 1 - u
		pose.RightShoulder = V3(0.5 + 1.2 * u, 0, 0.1)
		pose.RightElbow = V3(0.35 + 0.7 * u, 0, 0)
		pose.LeftShoulder = V3(0.6 + 0.1 * down, 0, -0.12)
		pose.LeftElbow = V3(0.9 + 0.1 * down, 0, 0)
		pose.Waist = V3(-(0.05 + 0.12 * down), 0.04 * math.sin(t * 0.7), 0)
		pose.Neck = V3(-0.1 + 0.05 * u, 0, 0)
		pose.RootPos = V3(0, -0.05 * down, 0)
		pose.LeftHip = V3(-0.12, 0, -0.05)
		pose.RightHip = V3(0.12, 0, 0.05)
		pose.LeftKnee = V3(-0.1, 0, 0)
		pose.RightKnee = V3(-0.1, 0, 0)
	end
end

local function writeIdentity(rig: Rig)
	for _, motor in rig.joints do
		motor.Transform = IDENTITY
	end
end

local function updateRig(rig: Rig, dt: number)
	if rig.dead then
		activeRigs[rig] = nil
		return
	end
	local acc = rig.acc
	for _, key in POSE_KEYS do
		acc[key] = Vector3.zero
	end
	local sumWeight = 0
	local anyLive = false

	for _, layer in rig.layers do
		local weight = layer.weight
		local target = layer.target
		if weight ~= target then
			if weight < target then
				weight = math.min(target, weight + dt / FADE_SECONDS)
			else
				weight = math.max(target, weight - dt / FADE_SECONDS)
			end
			layer.weight = weight
		end
		if weight > 0 or target > 0 then
			anyLive = true
			layer.time += dt * layer.rate
			if weight > 0 then
				for _, key in POSE_KEYS do
					scratch[key] = Vector3.zero
				end
				if layer.kind == "walk" then
					poseWalk(layer, layer.time, scratch)
				elseif layer.kind == "idle" then
					poseIdle(layer, layer.time, scratch)
				else
					poseWork(layer, layer.time, scratch)
				end
				sumWeight += weight
				for _, key in POSE_KEYS do
					acc[key] += scratch[key] * weight
				end
			end
		end
	end

	if not anyLive then
		writeIdentity(rig)
		activeRigs[rig] = nil
		return
	end

	local norm = if sumWeight > 1 then 1 / sumWeight else 1
	for name, motor in rig.joints do
		local v = acc[name] * norm
		if name == "Root" then
			motor.Transform = CF(acc.RootPos * norm) * CFrame.Angles(v.X, v.Y, v.Z)
		else
			motor.Transform = CFrame.Angles(v.X, v.Y, v.Z)
		end
	end
end

local function step(dt: number)
	dt = math.min(dt, 0.1)
	for rig in activeRigs do
		updateRig(rig, dt)
	end
	if next(activeRigs) == nil and connection then
		connection:Disconnect()
		connection = nil
	end
end

local function activate(rig: Rig)
	activeRigs[rig] = true
	if connection == nil then
		connection = RunService.Heartbeat:Connect(step)
	end
end

local function newLayer(model: Model, kind: string, style: string): Layer
	local rig = getRig(model)
	local layer: Layer = {
		rig = rig,
		kind = kind,
		style = style,
		weight = 0,
		target = 0,
		time = rng:NextNumber() * 10,
		rate = 1,
		speed = DEFAULT_WALK_SPEED,
		waveStart = -1,
		waveUntil = -1,
	}
	if kind == "walk" then
		layer.rate = TWO_PI * layer.speed / CYCLE_LENGTH
	end
	table.insert(rig.layers, layer)
	return layer
end

local function setTarget(layer: Layer, target: number)
	local rig = layer.rig
	if rig.dead then
		return
	end
	layer.target = target
	if target > 0 or layer.weight > 0 then
		activate(rig)
	end
end

--[[
	Procedural walk. setSpeed takes the travel speed in studs per second (default 7): it sets the step
	rate and the swing size. stop() fades out, and the joints return to CFrame.new() once no layer is left.
]]
function NpcBuilder.walkCycle(model: Model): WalkController
	local layer = newLayer(model, "walk", "")
	return {
		play = function()
			setTarget(layer, 1)
		end,
		stop = function()
			setTarget(layer, 0)
		end,
		setSpeed = function(speed: number)
			layer.speed = math.max(0, speed)
			layer.rate = TWO_PI * layer.speed / CYCLE_LENGTH
		end,
	}
end

-- Gentle breathing, weight shifting, arm sway and head looks. wave(seconds) raises the right hand.
function NpcBuilder.idle(model: Model): IdleController
	local layer = newLayer(model, "idle", "")
	return {
		play = function()
			setTarget(layer, 1)
		end,
		stop = function()
			setTarget(layer, 0)
		end,
		wave = function(duration: number?)
			layer.waveStart = layer.time
			layer.waveUntil = layer.time + (duration or 2)
		end,
	}
end

-- Working arm motion. style: "hammer" (default, strike), "spray" (sweeping arm), "reach" (browse / stock shelves).
function NpcBuilder.work(model: Model, style: string?): Controller
	local layer = newLayer(model, "work", style or "hammer")
	return {
		play = function()
			setTarget(layer, 1)
		end,
		stop = function()
			setTarget(layer, 0)
		end,
	}
end

----------------------------------------------------------------------------------------------------
-- Movement helpers (anchored root, yields on Heartbeat)
----------------------------------------------------------------------------------------------------

local function getRoot(model: Model): BasePart?
	local root = model.PrimaryPart
	if root == nil then
		root = getPart(model, "HumanoidRootPart")
	end
	return root
end

-- Puts the character with its feet at floorPos, facing `look` (flattened); keeps its yaw when look is nil.
function NpcBuilder.place(model: Model, floorPos: Vector3, look: Vector3?)
	local root = getRoot(model)
	if root == nil then
		return
	end
	local yaw = yawOf(root.CFrame)
	if look then
		local flat = V3(look.X, 0, look.Z)
		if flat.Magnitude > 1e-3 then
			yaw = math.atan2(-flat.X, -flat.Z)
		end
	end
	root.CFrame = CF(floorPos + V3(0, NpcBuilder.rootHeight(model), 0)) * CFrame.Angles(0, yaw, 0)
end

--[[
	Rotates the character in place to face `look` (smoothstep). Yields. Returns false if stopped/destroyed.
]]
function NpcBuilder.turnTo(model: Model, look: Vector3, duration: number?, shouldStop: (() -> boolean)?): boolean
	local root = getRoot(model)
	if root == nil then
		return false
	end
	local flat = V3(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		return true
	end
	local target = math.atan2(-flat.X, -flat.Z)
	local startCF = root.CFrame
	local startYaw = yawOf(startCF)
	local position = startCF.Position
	local diff = angleDiff(target, startYaw)
	local total = duration or math.max(0.2, math.abs(diff) / 4)
	local elapsed = 0
	while elapsed < total do
		local dt = RunService.Heartbeat:Wait()
		elapsed += dt
		if model.Parent == nil or (shouldStop ~= nil and shouldStop()) then
			return false
		end
		root.CFrame = CF(position) * CFrame.Angles(0, startYaw + diff * smooth(elapsed / total), 0)
	end
	root.CFrame = CF(position) * CFrame.Angles(0, target, 0)
	return true
end

--[[
	Walks the character along floor-level world points at ~`speed` studs/s with its walk cycle, turning
	smoothly to face the movement and easing to a stop at the last point. Yields until it arrives.
	Returns true on arrival, false when `shouldStop()` became true or the model was destroyed.
]]
function NpcBuilder.walkPath(
	model: Model,
	walk: WalkController,
	points: { Vector3 },
	speed: number,
	shouldStop: (() -> boolean)?
): boolean
	local root = getRoot(model)
	if root == nil or #points == 0 then
		return false
	end
	local rootHeight = NpcBuilder.rootHeight(model)
	local startCF = root.CFrame
	local pos = startCF.Position - V3(0, rootHeight, 0)
	local yaw = yawOf(startCF)

	local function aborted(): boolean
		return model.Parent == nil or (shouldStop ~= nil and shouldStop())
	end
	local function setCFrame()
		root.CFrame = CF(pos.X, pos.Y + rootHeight, pos.Z) * CFrame.Angles(0, yaw, 0)
	end

	-- Turn on the spot first when the first leg points far away from where we face.
	local first = points[1]
	local firstDir = V3(first.X - pos.X, 0, first.Z - pos.Z)
	if firstDir.Magnitude > 0.2 then
		local desired = math.atan2(-firstDir.X, -firstDir.Z)
		local guard = 0
		while math.abs(angleDiff(desired, yaw)) > 0.5 and guard < 1 do
			local dt = RunService.Heartbeat:Wait()
			guard += dt
			if aborted() then
				return false
			end
			yaw += angleDiff(desired, yaw) * (1 - math.exp(-14 * dt))
			setCFrame()
		end
	end

	walk.setSpeed(0)
	walk.play()
	local velocity = 0
	local index = 1
	local last = #points
	local accel = math.max(speed, 1) * 5

	while index <= last do
		local dt = math.min(RunService.Heartbeat:Wait(), 0.1)
		if aborted() then
			walk.stop()
			return false
		end
		local target = points[index]
		local delta = target - pos
		local flat = V3(delta.X, 0, delta.Z)
		local flatDist = flat.Magnitude
		local isLast = index == last
		if flatDist < (if isLast then 0.05 else 0.4) then
			if isLast then
				pos = V3(target.X, target.Y, target.Z)
				setCFrame()
			end
			index += 1
			continue
		end

		local wanted = speed
		if isLast then
			wanted = speed * math.clamp(flatDist / (speed * 0.5), 0.25, 1)
		end
		velocity += math.clamp(wanted - velocity, -accel * dt, accel * dt)
		local stepLength = math.min(velocity * dt, flatDist)
		pos += delta * (stepLength / math.max(delta.Magnitude, 1e-4))

		local desired = math.atan2(-flat.X, -flat.Z)
		yaw += angleDiff(desired, yaw) * (1 - math.exp(-10 * dt))
		setCFrame()
		walk.setSpeed(velocity)
	end

	walk.stop()
	return true
end

return NpcBuilder
