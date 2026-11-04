--!strict
-- Builds cars out of Parts (CONTRACT.md sections 8 and 17). No meshes, no asset ids.
-- Car space: Root is at the origin on the ground, nose = -Z (LookVector), +X = right side, +Y = up.
-- The caller moves the finished car with model:PivotTo(cf).
--
--   CarBuilder.build(carTypeId, opts?)        customer car: default customization, lower detail, random paint
--   CarBuilder.buildCustom(carTypeId, custom) personal car: full detail, wheels as Wheel_FL/FR/RL/RR models, FX attachments
--   CarBuilder.recolor(model, color)
--
-- The bodies live in src/shared/CarParts/ (Designs = the six cars, Wheels, Custom = spoilers/kits/decals, Kit = part helpers).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared: any = script.Parent
local CarTypes: any = require(Shared.Config.CarTypes)
local Kit: any = require(Shared.CarParts.Kit)
local Wheels: any = require(Shared.CarParts.Wheels)
local Designs: any = require(Shared.CarParts.Designs)
local Custom: any = require(Shared.CarParts.Custom)

local CarBuilder = {}

type Props = { [string]: any }

local V3 = Vector3.new
local RGB = Color3.fromRGB

------------------------------------------------------------------------------------------------
-- Customization config (optional: falls back to built-in defaults)
------------------------------------------------------------------------------------------------

local FALLBACK_DEFAULTS: { [string]: string } = {
	paint = "E8E8EC",
	material = "Gloss",
	wheel = "Classic",
	rim = "D8DBE2",
	caliper = "9EA3AD",
	spoiler = "None",
	kit = "Stock",
	hood = "Stock",
	tint = "Clear",
	neon = "None",
	headlight = "FFF4D0",
	flames = "Off",
	smoke = "None",
	decal = "None",
}

local okCust, customizationModule = pcall(function()
	return require(Shared.Config.Customization)
end)
local Customization: any = if okCust then customizationModule else nil

local DEFAULTS: { [string]: string } = FALLBACK_DEFAULTS
if Customization and type(Customization.DEFAULTS) == "table" then
	DEFAULTS = Customization.DEFAULTS
end

local function hexToColor(hex: string): Color3
	if Customization and type(Customization.hexToColor) == "function" then
		local ok, c = pcall(Customization.hexToColor, hex)
		if ok and typeof(c) == "Color3" then
			return c
		end
	end
	local ok, c = pcall(Color3.fromHex, "#" .. hex)
	if ok then
		return c
	end
	return Color3.new(1, 1, 1)
end

-- defaults overlaid with the caller's choices (string values only)
local function resolveCustom(custom: { [string]: string }?): { [string]: string }
	local out: { [string]: string } = {}
	for k, v in FALLBACK_DEFAULTS do
		out[k] = v
	end
	for k, v in DEFAULTS do
		out[k] = v
	end
	if custom then
		for k, v in custom do
			if type(v) == "string" then
				out[k] = v
			end
		end
	end
	return out
end

local WHEEL_STYLES: { [string]: boolean } = {
	Classic = true,
	Sport = true,
	Turbo = true,
	Mesh = true,
	OffRoad = true,
	DeepDish = true,
	Spinner = true,
	NeonRim = true,
}

-- default wheel of customer cars (build()), kept cheap
local CUSTOMER_WHEEL: { [string]: string } = {
	Sedan = "Classic",
	Pickup = "Classic",
	Muscle = "Sport",
	Truck = "Classic",
	Sports = "Sport",
	Super = "Sport",
}

-- body material -> (color, props)
local function paintFor(material: string, base: Color3): (Color3, Props)
	if material == "Matte" then
		return base, { Material = Enum.Material.SmoothPlastic, Reflectance = 0 }
	elseif material == "Metallic" then
		return base, { Material = Enum.Material.Metal, Reflectance = 0.25 }
	elseif material == "Pearl" then
		return base:Lerp(RGB(255, 255, 255), 0.15), { Material = Enum.Material.SmoothPlastic, Reflectance = 0.35 }
	elseif material == "Carbon" then
		return RGB(28, 28, 32), { Material = Enum.Material.DiamondPlate, Reflectance = 0.15 }
	elseif material == "Chrome" then
		return base:Lerp(RGB(220, 225, 235), 0.5), { Material = Enum.Material.Metal, Reflectance = 0.6 }
	elseif material == "Neon" then
		return base, { Material = Enum.Material.Neon }
	end
	return base, { Material = Enum.Material.SmoothPlastic, Reflectance = 0.18 } -- Gloss
end

local function glassFor(tint: string): (Color3, number)
	if tint == "Smoke" then
		return RGB(22, 28, 36), 0.2
	elseif tint == "Black" then
		return RGB(8, 9, 12), 0.05
	end
	return RGB(40, 55, 75), 0.35 -- Clear
end

------------------------------------------------------------------------------------------------
-- FX attachments
------------------------------------------------------------------------------------------------

local function makeFlame(att: Attachment, blue: boolean)
	local e = Instance.new("ParticleEmitter")
	e.Name = "Flame"
	e.Enabled = false
	e.Color = if blue
		then ColorSequence.new(RGB(170, 225, 255), RGB(40, 100, 255))
		else ColorSequence.new(RGB(255, 210, 70), RGB(255, 80, 10))
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Lifetime = NumberRange.new(0.12, 0.25)
	e.Speed = NumberRange.new(10, 16)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	e.Rate = 120
	e.SpreadAngle = Vector2.new(5, 5)
	e.EmissionDirection = Enum.NormalId.Back -- +Z = out of the tailpipe
	e.Parent = att
end

local function makeSmoke(att: Attachment, color: Color3)
	local e = Instance.new("ParticleEmitter")
	e.Name = "TireSmoke"
	e.Enabled = false
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(color)
	e.LightEmission = 0.1
	e.Lifetime = NumberRange.new(1.5)
	e.Rate = 60
	e.Speed = NumberRange.new(3, 7)
	e.SpreadAngle = Vector2.new(30, 30)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-40, 40)
	e.Acceleration = V3(0, 1.5, 0)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 6) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	e.Parent = att
end

local function makeAttachment(root: BasePart, name: string, pos: Vector3): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.Position = pos
	a.Parent = root
	return a
end

------------------------------------------------------------------------------------------------
-- Procedural cars
------------------------------------------------------------------------------------------------

local function stringHash(s: string): number
	local h = 0
	for i = 1, #s do
		h = (h * 31 + string.byte(s, i)) % 100003
	end
	return h
end

local function buildProcedural(
	id: string,
	def: any,
	custom: { [string]: string },
	paintBase: Color3,
	detail: boolean,
	full: boolean
): Model
	local size: Vector3 = def.size
	local W, H, L = size.X, size.Y, size.Z
	local params = Designs.PARAMS[id] or Designs.PARAMS.Sedan

	local model = Instance.new("Model")
	model.Name = id

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Anchored = true
	root.Transparency = 1
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.CastShadow = false
	root.TopSurface = Enum.SurfaceType.Smooth
	root.BottomSurface = Enum.SurfaceType.Smooth
	root.Size = V3(W, 0.2, L)
	root.CFrame = CFrame.new()
	root.Parent = model
	model.PrimaryPart = root

	local top = Instance.new("Attachment")
	top.Name = "TopAttachment"
	top.Position = V3(0, H + 2, 0)
	top.Parent = root

	-- context shared by all part builders ------------------------------------------------------------
	local wheelStyle = custom.wheel
	if not WHEEL_STYLES[wheelStyle] then
		wheelStyle = "Classic"
	end
	local offroad = wheelStyle == "OffRoad"
	local paintColor, paintProps = paintFor(custom.material, paintBase)
	local glassColor, glassT = glassFor(custom.tint)

	local ctx: any = {
		id = id,
		W = W,
		H = H,
		L = L,
		Wb = W - 1.4,
		model = model,
		root = root,
		detail = detail,
		beams = full,
		custom = custom,
		wheelStyle = wheelStyle,
		D = params.kD * L * (if offroad then 1.12 else 1),
		TW = params.tw + (if offroad then 0.15 else 0),
		axF = params.axF * L,
		axR = params.axR * L,
		paintColor = paintColor,
		paintProps = paintProps,
		glassColor = glassColor,
		glassProps = { Material = Enum.Material.Glass, Transparency = glassT, Reflectance = 0.1 } :: Props,
		headColor = hexToColor(custom.headlight),
		rimColor = hexToColor(custom.rim),
		caliperColor = hexToColor(custom.caliper),
		hoodStyle = custom.hood,
		plateText = string.format("GT-%04d", math.random(0, 9999)),
		numberText = tostring(stringHash(id .. custom.paint) % 99 + 1),
	}
	ctx.wx = W / 2 - ctx.TW / 2
	if custom.neon ~= "None" then
		ctx.neonColor = hexToColor(custom.neon)
	end

	-- body, customization, wheels ---------------------------------------------------------------------
	local P = Designs.build(ctx)
	Custom.apply(ctx, P)

	local corners: { { name: string, sx: number, z: number } } = {
		{ name = "Wheel_FL", sx = -1, z = ctx.axF },
		{ name = "Wheel_FR", sx = 1, z = ctx.axF },
		{ name = "Wheel_RL", sx = -1, z = ctx.axR },
		{ name = "Wheel_RR", sx = 1, z = ctx.axR },
	}
	for _, c in corners do
		local wm: Model = Wheels.build(ctx, c.name, c.sx, c.sx * ctx.wx, c.z)
		wm.Parent = model
	end

	-- root attachments ---------------------------------------------------------------------------------
	makeAttachment(root, "DriverSeat", P.driverPos)

	local exhaustPos: { Vector3 } = ctx.exhaust or { V3(-W * 0.2, 0.6, L / 2 + 0.7), V3(W * 0.2, 0.6, L / 2 + 0.7) }
	local flames = custom.flames
	for i = 1, 2 do
		local att = makeAttachment(root, "Exhaust" .. i, exhaustPos[i])
		if flames == "Orange" or flames == "Blue" then
			makeFlame(att, flames == "Blue")
		end
	end

	local smokeColor = if custom.smoke ~= "None" then hexToColor(custom.smoke) else RGB(255, 255, 255)
	makeSmoke(makeAttachment(root, "SmokeRL", V3(-ctx.wx, 0.15, ctx.axR)), smokeColor)
	makeSmoke(makeAttachment(root, "SmokeRR", V3(ctx.wx, 0.15, ctx.axR)), smokeColor)

	-- welds + attributes -------------------------------------------------------------------------------
	Kit.weldAll(model, root)

	model:SetAttribute("WheelDiameter", ctx.D)
	model:SetAttribute("WheelBase", ctx.axR - ctx.axF)
	model:SetAttribute("TrackWidth", 2 * ctx.wx)
	model:SetAttribute("RideHeight", P.gc)
	return model
end

------------------------------------------------------------------------------------------------
-- Art override
------------------------------------------------------------------------------------------------

local function recolorParts(model: Model, color: Color3)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and (d.Name == "Body" or d.Name == "BodyPanel") then
			d.Color = color
		end
	end
end

-- Enforces the Root / weld rules on an artist-made model. withVehicleData adds wheel attributes + DriverSeat if missing.
local function finalizeArt(model: Model, carTypeId: string, color: Color3?, withVehicleData: boolean): Model
	model.Name = carTypeId

	local root: BasePart? = model.PrimaryPart
	if root == nil then
		local cf, size = model:GetBoundingBox()
		local r = Instance.new("Part")
		r.Name = "Root"
		r.TopSurface = Enum.SurfaceType.Smooth
		r.BottomSurface = Enum.SurfaceType.Smooth
		r.Size = V3(size.X, 0.2, size.Z)
		r.CFrame = CFrame.new(cf.Position - cf.UpVector * (size.Y / 2)) * cf.Rotation
		r.Transparency = 1
		r.Parent = model
		model.PrimaryPart = r
		root = r
	end
	local rootPart = root :: BasePart
	if rootPart.Name == "Root" then
		rootPart.Transparency = 1
	end

	for _, d in model:GetDescendants() do
		if d:IsA("WeldConstraint") then
			d:Destroy()
		elseif d:IsA("BasePart") and d ~= rootPart then
			d.Anchored = false
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = true
		end
	end

	rootPart.Anchored = true
	rootPart.CanCollide = false
	rootPart.CanTouch = false
	rootPart.CanQuery = false
	rootPart.Massless = true

	local bbCF, bbSize = model:GetBoundingBox()
	if rootPart:FindFirstChild("TopAttachment") == nil then
		local att = Instance.new("Attachment")
		att.Name = "TopAttachment"
		att.Position = rootPart.CFrame:PointToObjectSpace(bbCF.Position + bbCF.UpVector * (bbSize.Y / 2 + 2))
		att.Parent = rootPart
	end

	Kit.weldAll(model, rootPart)

	if withVehicleData then
		local hasWheels = true
		for _, n in { "Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR" } do
			local wm = model:FindFirstChild(n)
			if wm == nil or not wm:IsA("Model") or wm.PrimaryPart == nil then
				hasWheels = false
			end
		end
		if hasWheels then
			local fl = (model:FindFirstChild("Wheel_FL") :: Model).PrimaryPart :: BasePart
			local fr = (model:FindFirstChild("Wheel_FR") :: Model).PrimaryPart :: BasePart
			local rl = (model:FindFirstChild("Wheel_RL") :: Model).PrimaryPart :: BasePart
			local relFL = rootPart.CFrame:PointToObjectSpace(fl.Position)
			local relFR = rootPart.CFrame:PointToObjectSpace(fr.Position)
			local relRL = rootPart.CFrame:PointToObjectSpace(rl.Position)
			if model:GetAttribute("WheelDiameter") == nil then
				model:SetAttribute("WheelDiameter", math.max(fl.Size.Y, fl.Size.Z))
			end
			if model:GetAttribute("WheelBase") == nil then
				model:SetAttribute("WheelBase", math.abs(relRL.Z - relFL.Z))
			end
			if model:GetAttribute("TrackWidth") == nil then
				model:SetAttribute("TrackWidth", math.abs(relFR.X - relFL.X))
			end
		else
			-- no usable wheel models: estimate from the bounding box (VehicleBuilder falls back for art without wheels)
			if model:GetAttribute("WheelDiameter") == nil then
				model:SetAttribute("WheelDiameter", 0.22 * bbSize.Z)
			end
			if model:GetAttribute("WheelBase") == nil then
				model:SetAttribute("WheelBase", 0.6 * bbSize.Z)
			end
			if model:GetAttribute("TrackWidth") == nil then
				model:SetAttribute("TrackWidth", math.max(bbSize.X - 1.2, 1))
			end
		end
		if model:GetAttribute("RideHeight") == nil then
			model:SetAttribute("RideHeight", 0.5)
		end
		if rootPart:FindFirstChild("DriverSeat") == nil then
			makeAttachment(rootPart, "DriverSeat", V3(-bbSize.X * 0.22, bbSize.Y * 0.4, 0))
		end
	end

	if color then
		recolorParts(model, color)
	end
	return model
end

local function findArt(id: string): Model?
	local models = ReplicatedStorage:FindFirstChild("Models")
	if models then
		local art = models:FindFirstChild("Car_" .. id)
		if art and art:IsA("Model") then
			return art
		end
	end
	return nil
end

------------------------------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------------------------------

-- Paint color of a built car (its "Body" part, else any "BodyPanel"); nil when the model has neither.
function CarBuilder.bodyColor(model: Model): Color3?
	local fallback: Color3? = nil
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			if d.Name == "Body" then
				return d.Color
			elseif d.Name == "BodyPanel" and fallback == nil then
				fallback = d.Color
			end
		end
	end
	return fallback
end

function CarBuilder.recolor(model: Model, color: Color3)
	recolorParts(model, color)
end

local function resolveType(carTypeId: string): (string, any)
	local def = CarTypes.byId[carTypeId]
	if def == nil then
		return "Sedan", CarTypes.byId.Sedan
	end
	return carTypeId, def
end

function CarBuilder.build(carTypeId: string, opts: { color: Color3? }?): Model
	local id, def = resolveType(carTypeId)
	local color: Color3? = if opts then opts.color else nil

	local art = findArt(id)
	if art then
		return finalizeArt(art:Clone(), id, color, false)
	end

	local colors: { Color3 } = def.colors
	local paintColor: Color3 = color or colors[math.random(1, #colors)]
	local custom = resolveCustom(nil)
	custom.wheel = CUSTOMER_WHEEL[id] or "Classic"
	return buildProcedural(id, def, custom, paintColor, false, false)
end

function CarBuilder.buildCustom(carTypeId: string, custom: { [string]: string }?): Model
	local id, def = resolveType(carTypeId)
	local resolved = resolveCustom(custom)
	local paintColor = hexToColor(resolved.paint)

	local art = findArt(id)
	if art then
		return finalizeArt(art:Clone(), id, paintColor, true)
	end

	return buildProcedural(id, def, resolved, paintColor, true, true)
end

return CarBuilder
