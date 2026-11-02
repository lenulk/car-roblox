--!strict
-- Shared helpers for building Part models, plus the 5 visual upgrade tiers every station follows.
-- Models are built at the origin (pivot = Part "Pivot" at CFrame.new()), plot-aligned:
-- -Z = toward the ring / the front of the garage, +Y = up, ground at Y = 0. Callers place them with PivotTo.

local ModelKit = {}

export type Props = { [string]: any }

export type Tier = {
	level: number,
	name: string, -- "Rusty" | "Fresh" | "Pro" | "Race" | "HiTech"
	body: (base: Color3) -> Color3, -- paint for the station's main body color
	bodyMaterial: Enum.Material,
	bodyReflectance: number,
	metalColor: Color3, -- frames, arms, posts
	metalMaterial: Enum.Material,
	metalReflectance: number,
	trimColor: Color3, -- secondary trim (black rubber, carbon, ...)
	trimMaterial: Enum.Material,
	lights: boolean, -- add LED strips / PointLights
	ledColor: (accent: Color3) -> Color3,
	stripes: boolean, -- racing stripes (Lv4+)
	hologram: boolean, -- ForceField hologram panel + sparkles (Lv5)
	rust: boolean, -- rust patches + dents (Lv1)
}

local function darken(c: Color3, k: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), k)
end

local TIERS: { Tier } = {
	{
		level = 1,
		name = "Rusty",
		body = function(base)
			return darken(base:Lerp(Color3.fromRGB(120, 100, 80), 0.55), 0.25)
		end,
		bodyMaterial = Enum.Material.CorrodedMetal,
		bodyReflectance = 0,
		metalColor = Color3.fromRGB(110, 96, 82),
		metalMaterial = Enum.Material.CorrodedMetal,
		metalReflectance = 0,
		trimColor = Color3.fromRGB(58, 52, 48),
		trimMaterial = Enum.Material.Concrete,
		lights = false,
		ledColor = function(_accent)
			return Color3.fromRGB(255, 220, 160)
		end,
		stripes = false,
		hologram = false,
		rust = true,
	},
	{
		level = 2,
		name = "Fresh",
		body = function(base)
			return base
		end,
		bodyMaterial = Enum.Material.SmoothPlastic,
		bodyReflectance = 0.08,
		metalColor = Color3.fromRGB(150, 156, 166),
		metalMaterial = Enum.Material.Metal,
		metalReflectance = 0.1,
		trimColor = Color3.fromRGB(40, 42, 48),
		trimMaterial = Enum.Material.SmoothPlastic,
		lights = false,
		ledColor = function(_accent)
			return Color3.fromRGB(255, 244, 220)
		end,
		stripes = false,
		hologram = false,
		rust = false,
	},
	{
		level = 3,
		name = "Pro",
		body = function(base)
			return base:Lerp(Color3.new(1, 1, 1), 0.08)
		end,
		bodyMaterial = Enum.Material.SmoothPlastic,
		bodyReflectance = 0.18,
		metalColor = Color3.fromRGB(222, 226, 234),
		metalMaterial = Enum.Material.Metal,
		metalReflectance = 0.45,
		trimColor = Color3.fromRGB(30, 32, 38),
		trimMaterial = Enum.Material.SmoothPlastic,
		lights = true,
		ledColor = function(_accent)
			return Color3.fromRGB(235, 245, 255)
		end,
		stripes = false,
		hologram = false,
		rust = false,
	},
	{
		level = 4,
		name = "Race",
		body = function(_base)
			return Color3.fromRGB(24, 24, 28)
		end,
		bodyMaterial = Enum.Material.SmoothPlastic,
		bodyReflectance = 0.28,
		metalColor = Color3.fromRGB(205, 210, 220),
		metalMaterial = Enum.Material.Metal,
		metalReflectance = 0.5,
		trimColor = Color3.fromRGB(16, 16, 18),
		trimMaterial = Enum.Material.DiamondPlate,
		lights = true,
		ledColor = function(accent)
			return accent
		end,
		stripes = true,
		hologram = false,
		rust = false,
	},
	{
		level = 5,
		name = "HiTech",
		body = function(_base)
			return Color3.fromRGB(34, 38, 52)
		end,
		bodyMaterial = Enum.Material.Glass,
		bodyReflectance = 0.35,
		metalColor = Color3.fromRGB(60, 66, 84),
		metalMaterial = Enum.Material.Metal,
		metalReflectance = 0.55,
		trimColor = Color3.fromRGB(12, 14, 22),
		trimMaterial = Enum.Material.SmoothPlastic,
		lights = true,
		ledColor = function(accent)
			return accent
		end,
		stripes = true,
		hologram = true,
		rust = false,
	},
}

function ModelKit.tier(level: number): Tier
	return TIERS[math.clamp(math.floor(level), 1, #TIERS)]
end

local function apply(p: BasePart, props: Props?)
	if props then
		local any = p :: any
		for k, v in props do
			any[k] = v
		end
	end
end

-- New model with an invisible Pivot part at the origin as PrimaryPart.
function ModelKit.model(name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	local pivot = Instance.new("Part")
	pivot.Name = "Pivot"
	pivot.Size = Vector3.new(1, 1, 1)
	pivot.CFrame = CFrame.new()
	pivot.Anchored = true
	pivot.CanCollide = false
	pivot.CanTouch = false
	pivot.CanQuery = false
	pivot.Transparency = 1
	pivot.CastShadow = false
	pivot.Parent = model
	model.PrimaryPart = pivot
	return model
end

-- Anchored box. `props` overrides anything (Material, Reflectance, CanCollide, Transparency ...).
function ModelKit.part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, props: Props?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.Size = size
	p.CFrame = cf
	p.Color = color
	apply(p, props)
	p.Parent = parent
	return p
end

-- Default WedgePart: slope faces -Z/up (low edge at -Z, tall edge at +Z).
function ModelKit.wedge(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, props: Props?): WedgePart
	local p = Instance.new("WedgePart")
	p.Name = name
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.Size = size
	p.CFrame = cf
	p.Color = color
	apply(p, props)
	p.Parent = parent
	return p
end

local AXIS: { [string]: CFrame } = {
	X = CFrame.new(),
	Y = CFrame.Angles(0, 0, math.pi / 2),
	Z = CFrame.Angles(0, math.pi / 2, 0),
}

-- Cylinder whose length runs along `axis` ("X" | "Y" | "Z") of `cf`.
function ModelKit.cylinder(
	parent: Instance,
	name: string,
	axis: string,
	length: number,
	diameter: number,
	cf: CFrame,
	color: Color3,
	props: Props?
): Part
	local p = ModelKit.part(parent, name, Vector3.new(length, diameter, diameter), cf * AXIS[axis], color, props)
	p.Shape = Enum.PartType.Cylinder
	return p
end

function ModelKit.ball(parent: Instance, name: string, diameter: number, cf: CFrame, color: Color3, props: Props?): Part
	local p = ModelKit.part(parent, name, Vector3.new(diameter, diameter, diameter), cf, color, props)
	p.Shape = Enum.PartType.Ball
	return p
end

-- Marks a part so ThemeService can recolor it. role: "Accent" | "Wall" | "Floor" | "Stripe" | "Roof" | "Trim".
function ModelKit.role(p: BasePart, role: string): BasePart
	p:SetAttribute("ThemeRole", role)
	return p
end

-- Glowing accent strip (Neon, no collision, tagged Accent).
function ModelKit.neon(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3): Part
	local p = ModelKit.part(parent, name, size, cf, color, {
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanTouch = false,
		CastShadow = false,
	})
	ModelKit.role(p, "Accent")
	return p
end

function ModelKit.light(parent: Instance, color: Color3, range: number, brightness: number): PointLight
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
	return l
end

-- Main body part styled by tier.
function ModelKit.body(parent: Instance, name: string, size: Vector3, cf: CFrame, base: Color3, tier: Tier): Part
	return ModelKit.part(parent, name, size, cf, tier.body(base), {
		Material = tier.bodyMaterial,
		Reflectance = tier.bodyReflectance,
	})
end

-- Metal frame part styled by tier.
function ModelKit.metal(parent: Instance, name: string, size: Vector3, cf: CFrame, tier: Tier): Part
	return ModelKit.part(parent, name, size, cf, tier.metalColor, {
		Material = tier.metalMaterial,
		Reflectance = tier.metalReflectance,
	})
end

function ModelKit.trim(parent: Instance, name: string, size: Vector3, cf: CFrame, tier: Tier): Part
	return ModelKit.part(parent, name, size, cf, tier.trimColor, { Material = tier.trimMaterial })
end

-- Lv1 detail: a few small rust/dent patches on a face of `onto` (local offsets inside its size).
function ModelKit.rustPatches(parent: Instance, onto: BasePart, count: number, seed: number)
	local rng = Random.new(seed)
	local s = onto.Size
	for i = 1, count do
		local w = rng:NextNumber(0.3, 0.9)
		local h = rng:NextNumber(0.2, 0.7)
		local x = rng:NextNumber(-s.X / 2 + w, s.X / 2 - w)
		local y = rng:NextNumber(-s.Y / 2 + h, s.Y / 2 - h)
		ModelKit.part(parent, "Rust", Vector3.new(w, h, 0.05), onto.CFrame * CFrame.new(x, y, -s.Z / 2 - 0.02), Color3.fromRGB(122, 70, 38), {
			Material = Enum.Material.Rust,
			CanCollide = false,
			CastShadow = false,
		})
	end
end

-- Lv4+ detail: two racing stripes across the -Z face of `onto`.
function ModelKit.stripes(parent: Instance, onto: BasePart, accent: Color3)
	local s = onto.Size
	for i, x in { -0.12, 0.12 } do
		local stripe = ModelKit.part(
			parent,
			"Stripe",
			Vector3.new(s.X * 0.12, s.Y * 0.96, 0.05),
			onto.CFrame * CFrame.new(x * s.X, 0, -s.Z / 2 - 0.03),
			if i == 1 then accent else Color3.fromRGB(245, 245, 245),
			{ CanCollide = false, CastShadow = false }
		)
		if i == 1 then
			ModelKit.role(stripe, "Stripe")
		end
	end
end

-- Lv5 detail: a translucent hologram screen with a glow and sparkles, standing at `cf`.
function ModelKit.hologram(parent: Instance, cf: CFrame, size: Vector2, accent: Color3): Part
	local screen = ModelKit.part(parent, "Hologram", Vector3.new(size.X, size.Y, 0.05), cf, accent, {
		Material = Enum.Material.ForceField,
		Transparency = 0.1,
		CanCollide = false,
		CanTouch = false,
		CastShadow = false,
	})
	ModelKit.role(screen, "Accent")
	ModelKit.light(screen, accent, 12, 1.2)
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Name = "HoloSparkle"
	sparkle.Rate = 6
	sparkle.Lifetime = NumberRange.new(0.8, 1.4)
	sparkle.Speed = NumberRange.new(0.5, 1.5)
	sparkle.SpreadAngle = Vector2.new(30, 30)
	sparkle.LightEmission = 1
	sparkle.Size = NumberSequence.new(0.18, 0)
	sparkle.Color = ColorSequence.new(accent)
	sparkle.Parent = screen
	return screen
end

-- LED strip that only appears on tiers with lights.
function ModelKit.led(parent: Instance, name: string, size: Vector3, cf: CFrame, tier: Tier, accent: Color3): Part?
	if not tier.lights then
		return nil
	end
	local strip = ModelKit.neon(parent, name, size, cf, tier.ledColor(accent))
	if tier.level < 4 then
		strip:SetAttribute("ThemeRole", nil) -- white LEDs keep their color
	end
	return strip
end

return ModelKit
