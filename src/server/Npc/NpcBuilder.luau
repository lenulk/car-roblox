--!strict
-- NpcBuilder: charming R15 characters built from colors and small welded Parts (no asset ids), plus a
-- animation controls (walk / idle / work / held poses) whose state the clients play (see Shared/NpcAnim),
-- and anchored-root movement helpers (place / walkPath / turnTo). Server only.
--
-- Facing convention: a character's front is its root's -Z, so yaw = atan2(-look.X, -look.Z).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local NpcAnim = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("NpcAnim") :: ModuleScript)

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

-- Shopper extras (all small welded parts; nothing changes body size or foot height).

local function addGlasses(model: Model, head: BasePart, sunglasses: boolean)
	local frameColor = if sunglasses then INK else Color3.fromRGB(70, 60, 56)
	local lensColor = if sunglasses then Color3.fromRGB(30, 34, 44) else Color3.fromRGB(190, 225, 245)
	for _, side in { -1, 1 } do
		attach(model, head, "GlassesFrame", V3(0.4, 0.34, 0.04), frameColor, CF(side * 0.24, 0.08, FACE_Z - 0.035))
		local lens = attach(model, head, "GlassesLens", V3(0.3, 0.24, 0.04), lensColor, CF(side * 0.24, 0.08, FACE_Z - 0.06))
		lens.Transparency = if sunglasses then 0.15 else 0.55
		bar(model, head, "GlassesArm", V3(side * 0.44, 0.1, FACE_Z - 0.03), V3(side * 0.62, 0.1, -0.35), 0.05, frameColor)
	end
	attach(model, head, "GlassesBridge", V3(0.12, 0.05, 0.05), frameColor, CF(0, 0.12, FACE_Z - 0.05))
end

local function addScarf(model: Model, torso: BasePart, color: Color3)
	local dark = darker(color, 0.25)
	local topY = torso.Size.Y / 2 - 0.12
	attach(model, torso, "ScarfWrap", V3(torso.Size.X * 0.78, 0.4, torso.Size.Z + 0.22), color, CF(0, topY, 0))
	attach(model, torso, "ScarfBand", V3(torso.Size.X * 0.8, 0.1, torso.Size.Z + 0.26), dark, CF(0, topY - 0.08, 0))
	attach(model, torso, "ScarfTail", V3(0.38, 0.95, 0.08), color, CF(0.35, topY - 0.55, -torso.Size.Z / 2 - 0.14))
	attach(model, torso, "ScarfTailEnd", V3(0.38, 0.12, 0.09), dark, CF(0.35, topY - 1.0, -torso.Size.Z / 2 - 0.14))
end

local function addBeanie(model: Model, head: BasePart, color: Color3)
	local dark = darker(color, 0.25)
	attach(model, head, "BeanieDome", V3(1.5, 1.5, 1.5), color, CF(0, 0.3, 0.08), Enum.PartType.Ball)
	attach(model, head, "BeanieFold", V3(0.3, 1.46, 1.46), dark, CF(0, 0.2, 0.06) * CFrame.Angles(0, 0, math.pi / 2), Enum.PartType.Cylinder)
	attach(model, head, "BeanieBobble", V3(0.34, 0.34, 0.34), dark, CF(0, 1.05, 0.08), Enum.PartType.Ball)
end

-- Hood pulled up over the head (tinted like the shirt so theme recolors keep matching).
local function addHood(model: Model, head: BasePart, torso: BasePart)
	local shell = attach(model, head, "HoodShell", V3(1.5, 1.5, 1.5), WHITE, CF(0, 0.1, 0.2), Enum.PartType.Ball)
	shell:SetAttribute("Tint", "shirt")
	local rim = attach(model, head, "HoodRim", V3(1.0, 0.1, 0.1), WHITE, CF(0, 0.58, -0.6))
	rim:SetAttribute("Tint", "shirtDark")
	local drape = attach(model, torso, "HoodDrape", V3(1.35, 0.5, 0.4), WHITE, CF(0, torso.Size.Y / 2 - 0.1, torso.Size.Z / 2 + 0.12))
	drape:SetAttribute("Tint", "shirt")
end

local function addStripes(model: Model, torso: BasePart)
	for _, y in { 0.15, -0.3 } do
		local stripe = attach(model, torso, "ShirtStripe", V3(torso.Size.X + 0.04, 0.2, torso.Size.Z + 0.04), WHITE, CF(0, y, 0))
		stripe:SetAttribute("Tint", "shirtDark")
	end
end

local function addChestPocket(model: Model, torso: BasePart)
	local z = -torso.Size.Z / 2 - 0.03
	local pocket = attach(model, torso, "ChestPocket", V3(0.5, 0.5, 0.06), WHITE, CF(torso.Size.X * 0.22, 0.25, z))
	pocket:SetAttribute("Tint", "shirtDark")
	local flap = attach(model, torso, "ChestPocketFlap", V3(0.5, 0.1, 0.07), WHITE, CF(torso.Size.X * 0.22, 0.47, z - 0.005))
	flap:SetAttribute("Tint", "shirtDark")
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

-- Weighted shopper traits. Traits of the same group never appear together (one hat, one thing in the
-- right hand ...), and most shoppers get none or one so the crowd stays mostly plain.
local SHOPPER_TRAITS: { { id: string, weight: number, group: string } } = {
	{ id = "cap", weight = 18, group = "head" },
	{ id = "beanie", weight = 9, group = "head" },
	{ id = "hood", weight = 8, group = "head" },
	{ id = "glasses", weight = 14, group = "face" },
	{ id = "scarf", weight = 8, group = "neck" },
	{ id = "shorts", weight = 9, group = "legs" },
	{ id = "longSleeves", weight = 9, group = "sleeves" },
	{ id = "stripes", weight = 9, group = "pattern" },
	{ id = "chestPocket", weight = 7, group = "pattern" },
	{ id = "tote", weight = 12, group = "hand" },
	{ id = "phone", weight = 9, group = "hand" },
	{ id = "pocket", weight = 7, group = "hand" },
	{ id = "backpack", weight = 9, group = "back" },
}

local function rollTraits(): { [string]: boolean }
	local roll = rng:NextNumber()
	local count = if roll < 0.35 then 0 elseif roll < 0.8 then 1 else 2
	local picked: { [string]: boolean } = {}
	local usedGroups: { [string]: boolean } = {}
	for _ = 1, count do
		local total = 0
		for _, trait in SHOPPER_TRAITS do
			if not usedGroups[trait.group] then
				total += trait.weight
			end
		end
		if total <= 0 then
			break
		end
		local target = rng:NextNumber() * total
		for _, trait in SHOPPER_TRAITS do
			if not usedGroups[trait.group] then
				target -= trait.weight
				if target <= 0 then
					picked[trait.id] = true
					usedGroups[trait.group] = true
					break
				end
			end
		end
	end
	return picked
end

function NpcBuilder.randomShopper(): Model
	local shirt = pick(SHIRT_COLORS)
	local traits = rollTraits()
	local accessory: string? = nil
	if traits.cap then
		accessory = "cap"
	end
	local hairStyle = if rng:NextNumber() < 0.08 then 0 else rng:NextInteger(1, 4)
	if traits.hood then
		hairStyle = 0 -- the hood covers the hair
	end
	local model = NpcBuilder.character({
		shirt = shirt,
		pants = pick(PANTS_COLORS),
		skin = pick(SKIN_TONES),
		accessory = accessory,
		hair = pick(HAIR_COLORS),
		hairStyle = hairStyle,
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

	local head = getPart(model, "Head")
	local torso = getPart(model, "UpperTorso")
	if head and torso then
		if traits.glasses then
			addGlasses(model, head, rng:NextNumber() < 0.35)
		end
		if traits.beanie then
			addBeanie(model, head, pick(SHIRT_COLORS))
		end
		if traits.hood then
			addHood(model, head, torso)
		end
		if traits.scarf then
			addScarf(model, torso, pick(SHIRT_COLORS))
		end
		if traits.stripes then
			addStripes(model, torso)
		end
		if traits.chestPocket then
			addChestPocket(model, torso)
		end
	end
	if traits.shorts then
		-- Bare calves: the lower legs take the skin color (upper legs keep the pants color).
		local skinAttr: any = model:GetAttribute("NpcSkin")
		local skin = if typeof(skinAttr) == "Color3" then (skinAttr :: Color3) else DEFAULT_SKIN
		for _, name in { "LeftLowerLeg", "RightLowerLeg" } do
			local part = getPart(model, name)
			if part then
				part.Color = skin
			end
		end
	end
	if traits.longSleeves then
		model:SetAttribute("NpcLongSleeves", true)
	end
	if traits.tote then
		addTote(model, pick(SHIRT_COLORS))
	end
	if traits.backpack then
		addBackpack(model, pick(SHIRT_COLORS))
	end
	if traits.phone then
		model:SetAttribute("NpcQuirk", "phone")
	elseif traits.pocket then
		model:SetAttribute("NpcQuirk", "pocket")
	end
	-- Re-tint the new shirt-colored pieces (hood, stripes, pocket) and long sleeves.
	NpcBuilder.applyShirt(model, shirt)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
		end
	end
	return model
end

----------------------------------------------------------------------------------------------------
-- Animation state: published as model Attributes, played by the clients (Shared/NpcAnim, NpcAnimator).
-- Joint Transforms written on the server never reach the clients, so nothing is posed here. The server
-- only keeps the hammer-blow timer, on the same clock the clients animate with.
----------------------------------------------------------------------------------------------------

type Layer = {
	rig: Rig,
	kind: string, -- "walk" | "idle" | "work"
	style: string,
	targetAttr: string,
	target: number,
	t0: number, -- server time the layer's clock started (idle / work)
	playedAt: number, -- server time the layer was last switched on
}

type Rig = {
	model: Model,
	dead: boolean,
	hammer: Layer?, -- the "hammer" work layer, if any
	onStrike: (() -> ())?,
	strikeIndex: number?,
}

local SPEED_STEP = 0.25 -- AnimSpeed / AnimLean are rounded so a steady walk does not spam attribute updates
local LEAN_STEP = 0.01
local STRIKE_FADE_IN = 0.11 -- the work pose is mostly blended in after this long

local rigs: { [Model]: Rig } = {}
local strikeRigs: { [Rig]: boolean } = {}
local strikeConnection: RBXScriptConnection? = nil

local function getRig(model: Model): Rig
	local existing = rigs[model]
	if existing then
		return existing
	end
	local rig: Rig = {
		model = model,
		dead = false,
		hammer = nil,
		onStrike = nil,
		strikeIndex = nil,
	}
	rigs[model] = rig
	CollectionService:AddTag(model, NpcAnim.TAG)
	model.Destroying:Connect(function()
		rig.dead = true
		strikeRigs[rig] = nil
		rigs[model] = nil
	end)
	return rig
end

-- Blow detection for the hammer pose: same phase formula as NpcAnim, evaluated on the shared server clock.
local function strikeStep()
	local now = Workspace:GetServerTimeNow()
	for rig in strikeRigs do
		local layer = rig.hammer
		local onStrike = rig.onStrike
		if rig.dead or layer == nil or onStrike == nil then
			strikeRigs[rig] = nil
			continue
		end
		if layer.target > 0 and now - layer.playedAt > STRIKE_FADE_IN then
			local index = math.floor((now - layer.t0) * NpcAnim.HAMMER_RATE - NpcAnim.HAMMER_STRIKE_PHASE)
			local previous = rig.strikeIndex
			rig.strikeIndex = index
			if previous ~= nil and index > previous then
				pcall(onStrike)
			end
		else
			rig.strikeIndex = nil
		end
	end
	if next(strikeRigs) == nil and strikeConnection then
		strikeConnection:Disconnect()
		strikeConnection = nil
	end
end

local function refreshStrike(rig: Rig)
	local layer = rig.hammer
	if rig.dead or layer == nil or layer.target <= 0 or rig.onStrike == nil then
		strikeRigs[rig] = nil
		rig.strikeIndex = nil
		return
	end
	strikeRigs[rig] = true
	if strikeConnection == nil then
		strikeConnection = RunService.Heartbeat:Connect(strikeStep)
	end
end

local function newLayer(model: Model, kind: string, style: string): Layer
	local rig = getRig(model)
	local targetAttr = "AnimWalk"
	local t0Attr: string? = nil
	if kind == "idle" then
		targetAttr = "AnimIdle"
		t0Attr = "AnimIdleT0"
	elseif kind == "work" then
		targetAttr = "AnimWork_" .. style
		t0Attr = "AnimWorkT0_" .. style
	end
	local now = Workspace:GetServerTimeNow()
	local layer: Layer = {
		rig = rig,
		kind = kind,
		style = style,
		targetAttr = targetAttr,
		target = 0,
		t0 = now - rng:NextNumber() * 10, -- random start phase so a crowd does not move in lockstep
		playedAt = now,
	}
	if t0Attr then
		model:SetAttribute(t0Attr, layer.t0)
	end
	model:SetAttribute(targetAttr, 0)
	if kind == "work" and style == "hammer" then
		rig.hammer = layer
	end
	return layer
end

local function setTarget(layer: Layer, target: number)
	local rig = layer.rig
	if rig.dead then
		return
	end
	if target > 0 and layer.target <= 0 then
		layer.playedAt = Workspace:GetServerTimeNow()
	end
	layer.target = target
	rig.model:SetAttribute(layer.targetAttr, target)
	if layer == rig.hammer then
		refreshStrike(rig)
	end
end

local function roundTo(value: number, step: number): number
	return math.floor(value / step + 0.5) * step
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
			if not layer.rig.dead then
				model:SetAttribute("AnimSpeed", roundTo(math.max(0, speed), SPEED_STEP))
			end
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
			if layer.rig.dead then
				return
			end
			model:SetAttribute("AnimWaveDur", duration or 2)
			model:SetAttribute("AnimWaveAt", Workspace:GetServerTimeNow())
		end,
	}
end

-- Working arm motion. style: "hammer" (default, strike), "spray" (sweeping arm), "reach" (browse / stock shelves).
function NpcBuilder.work(model: Model, style: string?): Controller
	local chosen = "hammer"
	for _, known in NpcAnim.WORK_STYLES do
		if known == style then
			chosen = known
		end
	end
	local layer = newLayer(model, "work", chosen)
	return {
		play = function()
			setTarget(layer, 1)
		end,
		stop = function()
			setTarget(layer, 0)
		end,
	}
end

-- Holds a cardboard box in front of the chest with both arms (true) or puts it away (false).
function NpcBuilder.setCarry(model: Model, carrying: boolean)
	for _, child in model:GetChildren() do
		if child:GetAttribute("NpcCarry") == true then
			child:Destroy()
		end
	end
	local rig = getRig(model)
	if rig.dead then
		return
	end
	model:SetAttribute("AnimCarry", carrying)
	local torso = getPart(model, "UpperTorso")
	if not carrying or torso == nil then
		return
	end
	local offset = CF(0, -0.35, -1.25)
	local box = attach(model, torso, "CarryBox", V3(1.9, 1.3, 1.4), Color3.fromRGB(196, 154, 108), offset)
	local tape = attach(model, torso, "CarryBoxTape", V3(0.35, 1.32, 1.42), Color3.fromRGB(225, 200, 150), offset)
	box:SetAttribute("NpcCarry", true)
	tape:SetAttribute("NpcCarry", true)
end

--[[
	Turns the head (Neck, plus a little Waist) toward a world position; nil stops looking. The turn is
	blended in and out and limited to about +-1 rad. Targets behind or beside the character are ignored.
	Call it again whenever the target moves (it follows smoothly, so a low update rate is fine).
]]
function NpcBuilder.lookAt(model: Model, worldPos: Vector3?)
	local rig = rigs[model]
	if rig == nil then
		if worldPos == nil then
			return
		end
		rig = getRig(model)
	end
	if rig.dead then
		return
	end
	model:SetAttribute("AnimLook", worldPos)
end

-- Holds an arm pose that fades in and out: "phone" (right hand, with a small phone), "pocket", or nil.
function NpcBuilder.setHold(model: Model, kind: string?)
	for _, child in model:GetChildren() do
		if child:GetAttribute("NpcHold") == true then
			child:Destroy()
		end
	end
	local rig = getRig(model)
	if rig.dead then
		return
	end
	model:SetAttribute("AnimHold", kind)
	local hand = getPart(model, "RightHand")
	if kind == "phone" and hand then
		local body = attach(model, hand, "PhoneBody", V3(0.46, 0.8, 0.07), Color3.fromRGB(28, 28, 34), CF(0, -0.2, -0.25))
		local screen = attach(model, hand, "PhoneScreen", V3(0.38, 0.68, 0.03), Color3.fromRGB(120, 190, 255), CF(0, -0.2, -0.3))
		screen.Material = Enum.Material.Neon
		body:SetAttribute("NpcHold", true)
		screen:SetAttribute("NpcHold", true)
	end
end

-- Bends the character forward from the waist and knees (0 = upright, 1 = full bend), smoothly.
function NpcBuilder.setStoop(model: Model, amount: number)
	local rig = getRig(model)
	if rig.dead then
		return
	end
	model:SetAttribute("AnimStoop", math.clamp(amount, 0, 1))
end

-- Registers a function that runs each time the "hammer" work pose lands a blow (nil removes it).
function NpcBuilder.setStrikeHandler(model: Model, handler: (() -> ())?)
	local rig = getRig(model)
	if rig.dead then
		return
	end
	rig.onStrike = handler
	refreshStrike(rig)
end

----------------------------------------------------------------------------------------------------
-- Movement helpers (anchored root, yields on Heartbeat)
----------------------------------------------------------------------------------------------------

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

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
	-- PivotTo moves every part explicitly, so this also works before the model is parented.
	model:PivotTo(CF(floorPos + V3(0, NpcBuilder.rootHeight(model), 0)) * CFrame.Angles(0, yaw, 0))
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

-- Turn lean (radians) for the clients; rounded so a steady walk publishes nothing.
local function setLean(model: Model, lean: number)
	model:SetAttribute("AnimLean", roundTo(lean, LEAN_STEP))
end

local AVOID_INTERVAL = 0.25 -- seconds between sidestep checks (walkPath's `avoid` callback)
local AVOID_MAX = 1.2 -- largest sidestep, studs
local AVOID_RELEASE_DISTANCE = 4 -- the sidestep fades out over the last studs of the final leg
local CORNER_RADIUS = 2 -- studs cut off each sharp corner
local CORNER_SLOW_DISTANCE = 5 -- studs before a sharp corner over which the walk eases down
local CORNER_ANGLE_MIN = math.rad(12) -- corners gentler than this are left straight (no extra waypoints)

-- Replaces each interior corner of `points` with two waypoints that cut the corner (so the path curves
-- instead of hinging), and returns a per-waypoint speed factor (<1 right before a sharp turn). The very
-- first and last points are kept exact so the walk still starts/ends precisely where asked.
local function smoothCorners(startPos: Vector3, points: { Vector3 }): ({ Vector3 }, { number })
	local route: { Vector3 } = {}
	local slow: { number } = {}
	local previous = startPos
	local count = #points
	for i, point in points do
		local nextPoint = points[i + 1]
		if i < count and nextPoint then
			local inVec = V3(point.X - previous.X, 0, point.Z - previous.Z)
			local outVec = V3(nextPoint.X - point.X, 0, nextPoint.Z - point.Z)
			local inLen, outLen = inVec.Magnitude, outVec.Magnitude
			if inLen > CORNER_RADIUS * 2 and outLen > CORNER_RADIUS * 2 then
				local angle = math.abs(angleDiff(math.atan2(-outVec.X, -outVec.Z), math.atan2(-inVec.X, -inVec.Z)))
				if angle > CORNER_ANGLE_MIN then
					local cut = CORNER_RADIUS / inLen
					table.insert(route, point - inVec * cut)
					table.insert(slow, math.clamp(1 - angle / math.pi, 0.45, 1))
					local cutOut = CORNER_RADIUS / outLen
					table.insert(route, point + outVec * cutOut)
					table.insert(slow, 1)
					previous = point
					continue
				end
			end
		end
		table.insert(route, point)
		table.insert(slow, 1)
		previous = point
	end
	return route, slow
end

--[[
	Walks the character along floor-level world points at ~`speed` studs/s with its walk cycle, turning
	smoothly to face the movement and easing to a stop at the last point. Corners are cut into short
	curves and the walk slows a little before a sharp one; the character leans into turns while moving
	and only snaps its final facing after it has fully stopped. Yields until it arrives.
	Returns true on arrival, false when `shouldStop()` became true or the model was destroyed.
]]
local function walkPathRun(
	model: Model,
	walk: WalkController,
	points: { Vector3 },
	speed: number,
	shouldStop: (() -> boolean)?,
	avoid: ((Vector3, Vector3) -> number)?
): boolean
	local root = getRoot(model)
	if root == nil or #points == 0 then
		return false
	end
	local rootHeight = NpcBuilder.rootHeight(model)
	local startCF = root.CFrame
	local pos = startCF.Position - V3(0, rootHeight, 0)
	local yaw = yawOf(startCF)
	-- Corners become short arcs; `slow` holds a speed factor per waypoint (<1 on the sharper bends).
	local route, slow = smoothCorners(pos, points)

	local function aborted(): boolean
		return model.Parent == nil or (shouldStop ~= nil and shouldStop())
	end
	-- Sidestep: `offset` studs to the walker's right of the real path position `pos` (0 when not avoiding).
	local offset = 0
	local offsetGoal = 0
	local avoidTimer = rng:NextNumber() * AVOID_INTERVAL -- staggered so walkers do not all check on one frame
	local function setCFrame()
		local rotation = CFrame.Angles(0, yaw, 0)
		local shift = rotation.RightVector * offset
		root.CFrame = CF(pos.X + shift.X, pos.Y + rootHeight, pos.Z + shift.Z) * rotation
	end

	-- Turn on the spot first when the first leg points far away from where we face.
	local first = route[1]
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
	local last = #route
	local accel = math.max(speed, 1) * 5

	while index <= last do
		local dt = math.min(RunService.Heartbeat:Wait(), 0.1)
		if aborted() then
			walk.stop()
			setLean(model, 0)
			return false
		end
		local target = route[index]
		local delta = target - pos
		local flat = V3(delta.X, 0, delta.Z)
		local flatDist = flat.Magnitude
		local isLast = index == last
		if flatDist < (if isLast then 0.05 else 0.4) then
			if isLast then
				pos = V3(target.X, target.Y, target.Z)
				offset = 0 -- always finish exactly on the requested point
				setCFrame()
			end
			index += 1
			continue
		end

		-- The corner slowdown only applies in the last stretch before the bend, not along the whole leg.
		local factor = slow[index]
		if factor < 1 then
			factor = 1 - (1 - factor) * math.clamp(1 - flatDist / CORNER_SLOW_DISTANCE, 0, 1)
		end
		local wanted = speed * factor
		if isLast then
			wanted = speed * math.clamp(flatDist / (speed * 0.5), 0.25, 1)
		end
		velocity += math.clamp(wanted - velocity, -accel * dt, accel * dt)
		local stepLength = math.min(velocity * dt, flatDist)
		pos += delta * (stepLength / math.max(delta.Magnitude, 1e-4))

		local desired = math.atan2(-flat.X, -flat.Z)
		local turnRate = angleDiff(desired, yaw)
		yaw += turnRate * (1 - math.exp(-10 * dt))
		if avoid then
			-- Ask the caller for a sidestep a few times per second, then ease toward it every frame.
			avoidTimer -= dt
			if avoidTimer <= 0 then
				avoidTimer = AVOID_INTERVAL
				local ok, value = pcall(avoid, pos, flat / flatDist)
				offsetGoal = if ok and type(value) == "number" then math.clamp(value, -AVOID_MAX, AVOID_MAX) else 0
			end
			local goal = offsetGoal
			if isLast then
				goal *= smooth(flatDist / AVOID_RELEASE_DISTANCE) -- back to the path before the final stop
			end
			offset += (goal - offset) * (1 - math.exp(-(if isLast then 9 else 4) * dt))
		end
		setCFrame()
		walk.setSpeed(velocity)
		-- Lean into the turn while actually turning at speed; upright on straight stretches.
		setLean(model, math.clamp(turnRate * 0.25, -0.1, 0.1) * math.clamp(velocity / math.max(speed, 0.1), 0, 1))
	end

	walk.stop()
	setLean(model, 0)
	return true
end

--[[
	Walks the character along floor-level world points, then (if `finalLook` is given) turns to face it
	only after coming to a full stop — avoids the "robot spins the instant it arrives" look. Same return
	convention as the underlying walk.
	Optional `avoid(position, forward)`: called about 4 times a second with the walker's path position and
	unit heading; it returns a sidestep in studs (positive = to the walker's right, clamped to +-1.2). The
	body shifts sideways smoothly and is back on the path before the last point, which is reached exactly.
]]
function NpcBuilder.walkPath(
	model: Model,
	walk: WalkController,
	points: { Vector3 },
	speed: number,
	shouldStop: (() -> boolean)?,
	finalLook: Vector3?,
	avoid: ((Vector3, Vector3) -> number)?
): boolean
	if not walkPathRun(model, walk, points, speed, shouldStop, avoid) then
		return false
	end
	if finalLook then
		return NpcBuilder.turnTo(model, finalLook, nil, shouldStop)
	end
	return true
end

return NpcBuilder
