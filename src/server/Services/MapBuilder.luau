--!strict
-- Builds the whole 3D world from Parts: ring road, center island + monument, 4 garage plots.
-- Names follow docs/CONTRACT.md sections 4 and 15. All geometry comes from Layout.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Layout = require(Shared:WaitForChild("Layout") :: ModuleScript)
local Format = require(Shared:WaitForChild("Format") :: ModuleScript)
local ModelKit = require(Shared:WaitForChild("ModelKit") :: ModuleScript)
local Unlocks: any = require((Shared:WaitForChild("Config") :: Folder):WaitForChild("Unlocks") :: ModuleScript)
local StationModels: any =
	require(script.Parent.Parent:WaitForChild("Models"):WaitForChild("StationModels") :: ModuleScript)

local MapBuilder = {}

type Props = { [string]: any }

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local RGB = Color3.fromRGB

local TWO_PI = math.pi * 2

------------------------------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------------------------------

local ACCENTS: { Color3 } = {
	RGB(255, 140, 30),
	RGB(30, 200, 255),
	RGB(120, 230, 60),
	RGB(230, 60, 200),
}

local C_GRASS = RGB(98, 168, 82)
local C_ISLAND = RGB(120, 190, 96)
local C_ASPHALT = RGB(52, 55, 62)
local C_CURB = RGB(238, 238, 240)
local C_WHITE = RGB(245, 245, 245)
local C_YELLOW = RGB(255, 205, 40)
local C_CONCRETE = RGB(168, 172, 178)
local C_FLOOR = RGB(224, 226, 230)
local C_GRID = RGB(190, 193, 200)
local C_WALL = RGB(236, 238, 242)
local C_ROOF = RGB(70, 74, 84)
local C_DARK = RGB(40, 44, 52)
local C_DARKER = RGB(26, 30, 40)
local C_STEEL = RGB(120, 126, 136)
local C_CHROME = RGB(216, 220, 228)
local C_STONE = RGB(190, 188, 182)
local C_WARM = RGB(255, 236, 175)
local C_TIRE = RGB(24, 24, 27)
local C_GLASS = RGB(150, 205, 235)
local C_WOOD = RGB(150, 104, 66)
local C_LEAF = RGB(70, 150, 70)
local C_POT = RGB(176, 96, 70)

local NEON = Enum.Material.Neon
local METAL = Enum.Material.Metal

-- Heights of the stacked flat layers (avoid z-fighting).
local ROAD_TOP = 0.05
local LOT_TOP = 0.06
local FLOOR_TOP = 0.1
local LINE_THICK = 0.04

local DECAL: Props = { CanCollide = false, CanTouch = false, CastShadow = false }
local NEON_DECO: Props = { Material = NEON, CanCollide = false, CanTouch = false, CastShadow = false }
local CHROME_PROPS: Props = { Material = METAL, Reflectance = 0.4 }
local GLASS_PROPS: Props = { Material = Enum.Material.Glass, Transparency = 0.5, Reflectance = 0.15, CastShadow = false }

local function floorTop(localZ: number): number
	return if localZ >= Layout.BUILDING.frontZ then FLOOR_TOP else LOT_TOP
end

local function merge(a: Props, b: Props?): Props
	local out: Props = {}
	for k, v in a do
		out[k] = v
	end
	if b then
		for k, v in b do
			out[k] = v
		end
	end
	return out
end

local function tag(p: BasePart, role: string): BasePart
	return ModelKit.role(p, role)
end

------------------------------------------------------------------------------------------------
-- Part / GUI helpers
------------------------------------------------------------------------------------------------

local function newPart(
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	props: Props?,
	parent: Instance?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.Size = size
	p.CFrame = cf
	p.Color = color
	if props then
		local any = p :: any
		for k, v in props do
			any[k] = v
		end
	end
	p.Parent = parent
	return p
end

-- Axis a cylinder points along (Roblox cylinders are along local X by default).
local AXIS_ROT: { [string]: CFrame } = {
	X = CF(),
	Y = ANG(0, 0, math.pi / 2),
	Z = ANG(0, math.pi / 2, 0),
}

local function worldCylinder(
	parent: Instance,
	name: string,
	axis: string,
	length: number,
	diameter: number,
	cf: CFrame,
	color: Color3,
	props: Props?
): Part
	return newPart(
		name,
		V3(length, diameter, diameter),
		cf * AXIS_ROT[axis],
		color,
		merge({ Shape = Enum.PartType.Cylinder }, props),
		parent
	)
end

local function worldBall(parent: Instance, name: string, d: number, cf: CFrame, color: Color3, props: Props?): Part
	return newPart(name, V3(d, d, d), cf, color, merge({ Shape = Enum.PartType.Ball }, props), parent)
end

local function newModel(name: string, parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function newFolder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- night = true marks the light for the day/night cycle (attribute NightLight on the Light instance).
local function addPointLight(parent: Instance, color: Color3, range: number, brightness: number, night: boolean?): PointLight
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	if night then
		l:SetAttribute("NightLight", true)
	end
	l.Parent = parent
	return l
end

local function addSpotLight(
	parent: Instance,
	face: Enum.NormalId,
	color: Color3,
	range: number,
	angle: number,
	brightness: number,
	night: boolean?
): SpotLight
	local s = Instance.new("SpotLight")
	s.Face = face
	s.Color = color
	s.Range = range
	s.Angle = angle
	s.Brightness = brightness
	s.Shadows = false
	if night then
		s:SetAttribute("NightLight", true)
	end
	s.Parent = parent
	return s
end

local function addStroke(parent: Instance, thickness: number, color: Color3?): UIStroke
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color or Color3.new(0, 0, 0)
	s.Parent = parent
	return s
end

local function newLabel(
	parent: Instance,
	name: string,
	text: string,
	color: Color3,
	size: UDim2,
	position: UDim2?
): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = position or UDim2.new()
	l.Text = text
	l.TextColor3 = color
	l.TextScaled = true
	l.Font = Enum.Font.GothamBold
	l.Parent = parent
	return l
end

local function newSurfaceGui(part: BasePart, name: string, face: Enum.NormalId, pixelsPerStud: number): SurfaceGui
	local g = Instance.new("SurfaceGui")
	g.Name = name
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = pixelsPerStud
	g.LightInfluence = 0
	g.Parent = part
	return g
end

-- Adds a text GUI to a part face (default Front = -Z). Returns the label.
local function addSignText(
	part: BasePart,
	guiName: string,
	labelName: string,
	text: string,
	textKey: string?,
	ppu: number,
	face: Enum.NormalId?,
	color: Color3?
): TextLabel
	local gui = newSurfaceGui(part, guiName, face or Enum.NormalId.Front, ppu)
	local label = newLabel(gui, labelName, text, color or RGB(255, 255, 255), UDim2.fromScale(1, 1))
	label.Font = Enum.Font.GothamBlack
	addStroke(label, 3, Color3.new(0, 0, 0))
	if textKey then
		label:SetAttribute("TextKey", textKey)
	end
	return label
end

-- Plain text screen (no stroke) for monitors and posters.
local function addScreenText(part: BasePart, guiName: string, text: string, color: Color3, ppu: number, face: Enum.NormalId?)
	local gui = newSurfaceGui(part, guiName, face or Enum.NormalId.Front, ppu)
	local label = newLabel(gui, "Text", text, color, UDim2.fromScale(1, 1))
	label.Font = Enum.Font.GothamBlack
end

------------------------------------------------------------------------------------------------
-- Plot context (everything in plot space goes through Layout.toWorld)
------------------------------------------------------------------------------------------------

type Ctx = {
	index: number,
	accent: Color3,
	P: (parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, props: Props?) -> Part,
	C: (
		parent: Instance,
		name: string,
		axis: string,
		length: number,
		diameter: number,
		cf: CFrame,
		color: Color3,
		props: Props?
	) -> Part,
	-- accent-colored neon, tagged Accent
	A: (parent: Instance, name: string, size: Vector3, cf: CFrame) -> Part,
	-- accent-colored solid trim, tagged Accent
	T: (parent: Instance, name: string, size: Vector3, cf: CFrame) -> Part,
	-- box with a theme role (Wall / Floor / Roof / Stripe)
	R: (parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, role: string, props: Props?) -> Part,
	B: (parent: Instance, name: string, diameter: number, cf: CFrame, color: Color3, props: Props?) -> Part,
}

local function makeCtx(i: number): Ctx
	local accent = ACCENTS[i]
	local ctx: Ctx = {
		index = i,
		accent = accent,
		P = function(parent, name, size, cf, color, props)
			return newPart(name, size, Layout.toWorld(i, cf), color, props, parent)
		end,
		C = function(parent, name, axis, length, diameter, cf, color, props)
			return worldCylinder(parent, name, axis, length, diameter, Layout.toWorld(i, cf), color, props)
		end,
		A = function(parent, name, size, cf)
			local p = newPart(name, size, Layout.toWorld(i, cf), accent, NEON_DECO, parent)
			tag(p, "Accent")
			return p
		end,
		T = function(parent, name, size, cf)
			local p = newPart(name, size, Layout.toWorld(i, cf), accent, nil, parent)
			tag(p, "Accent")
			return p
		end,
		R = function(parent, name, size, cf, color, role, props)
			local p = newPart(name, size, Layout.toWorld(i, cf), color, props, parent)
			tag(p, role)
			return p
		end,
		B = function(parent, name, d, cf, color, props)
			return worldBall(parent, name, d, Layout.toWorld(i, cf), color, props)
		end,
	}
	return ctx
end

-- Rectangle outline (4 thin lines) in plot space.
local function outline(
	ctx: Ctx,
	parent: Instance,
	name: string,
	cx: number,
	cz: number,
	width: number,
	length: number,
	lineW: number,
	y: number,
	color: Color3
)
	local halfW, halfL = width / 2, length / 2
	ctx.P(parent, name, V3(lineW, LINE_THICK, length + lineW), CF(cx - halfW, y, cz), color, DECAL)
	ctx.P(parent, name, V3(lineW, LINE_THICK, length + lineW), CF(cx + halfW, y, cz), color, DECAL)
	ctx.P(parent, name, V3(width - lineW, LINE_THICK, lineW), CF(cx, y, cz - halfL), color, DECAL)
	ctx.P(parent, name, V3(width - lineW, LINE_THICK, lineW), CF(cx, y, cz + halfL), color, DECAL)
end

------------------------------------------------------------------------------------------------
-- World: ground, ring road, island, fountain + monument, decoration
------------------------------------------------------------------------------------------------

local function angularDistance(a: number, b: number): number
	local d = (a - b) % TWO_PI
	if d > math.pi then
		d = TWO_PI - d
	end
	return d
end

-- True if a world position lies on a plot, its connector road, or too close to them.
local function nearPlot(pos: Vector3): boolean
	for i = 1, Layout.PLOT_COUNT do
		local l = Layout.plotCFrame(i):PointToObjectSpace(pos)
		if math.abs(l.X) < 84 and l.Z > -132 and l.Z < 112 then
			return true
		end
	end
	return false
end

local GREENS = { RGB(72, 160, 72), RGB(60, 140, 62), RGB(88, 176, 78) }
local PINES = { RGB(40, 112, 70), RGB(34, 98, 62), RGB(52, 128, 76) }
local TRUNK = RGB(112, 76, 46)

local function boxTree(m: Model, base: CFrame, s: number, rng: Random)
	local leaf: Props = { CanCollide = false }
	newPart("Trunk", V3(1.3 * s, 4.6 * s, 1.3 * s), base * CF(0, 2.3 * s, 0), TRUNK, nil, m)
	newPart("Leaves", V3(6.4 * s, 3.6 * s, 6.4 * s), base * CF(0, 5.6 * s, 0), GREENS[rng:NextInteger(1, 3)], leaf, m)
	newPart(
		"Leaves",
		V3(4.8 * s, 3.4 * s, 4.8 * s),
		base * CF(0, 8.4 * s, 0) * ANG(0, math.rad(30), 0),
		GREENS[rng:NextInteger(1, 3)],
		leaf,
		m
	)
	newPart(
		"Leaves",
		V3(3.0 * s, 2.8 * s, 3.0 * s),
		base * CF(0, 10.8 * s, 0) * ANG(0, math.rad(15), 0),
		GREENS[rng:NextInteger(1, 3)],
		leaf,
		m
	)
end

local function roundTree(m: Model, base: CFrame, s: number, rng: Random)
	local leaf: Props = { CanCollide = false, Material = Enum.Material.Grass }
	newPart("Trunk", V3(1.4 * s, 5.4 * s, 1.4 * s), base * CF(0, 2.7 * s, 0), TRUNK, { Material = Enum.Material.Wood }, m)
	worldBall(m, "Leaves", 8 * s, base * CF(0, 8 * s, 0), GREENS[rng:NextInteger(1, 3)], leaf)
	worldBall(m, "Leaves", 5 * s, base * CF(2.2 * s, 6.4 * s, 1.2 * s), GREENS[rng:NextInteger(1, 3)], leaf)
	worldBall(m, "Leaves", 4.6 * s, base * CF(-2.0 * s, 9.6 * s, -1.0 * s), GREENS[rng:NextInteger(1, 3)], leaf)
end

local function pineTree(m: Model, base: CFrame, s: number, rng: Random)
	local leaf: Props = { CanCollide = false }
	newPart("Trunk", V3(1.2 * s, 5 * s, 1.2 * s), base * CF(0, 2.5 * s, 0), TRUNK, nil, m)
	local layers = { { 8, 3 }, { 6.4, 5.4 }, { 4.8, 7.8 }, { 3.2, 10.2 }, { 1.6, 12.4 } }
	for k, l in layers do
		newPart(
			"Needles",
			V3(l[1] * s, 2.6 * s, l[1] * s),
			base * CF(0, l[2] * s, 0) * ANG(0, (k % 2) * math.rad(45), 0),
			PINES[rng:NextInteger(1, 3)],
			leaf,
			m
		)
	end
end

local function buildTree(parent: Instance, pos: Vector3, scale: number, rng: Random)
	local m = newModel("Tree", parent)
	local base = CF(pos) * ANG(0, rng:NextNumber(0, TWO_PI), 0)
	local kind = rng:NextInteger(1, 10)
	if kind <= 4 then
		boxTree(m, base, scale, rng)
	elseif kind <= 7 then
		roundTree(m, base, scale, rng)
	else
		pineTree(m, base, scale, rng)
	end
end

local function buildLamp(parent: Instance, pos: Vector3, facing: Vector3?)
	local m = newModel("Lamp", parent)
	local base = if facing then CFrame.lookAt(pos, pos + facing) else CF(pos)
	newPart("LampBase", V3(1.4, 0.6, 1.4), base * CF(0, 0.3, 0), C_DARK, nil, m)
	worldCylinder(m, "LampPole", "Y", 11.4, 0.5, base * CF(0, 6.3, 0), RGB(60, 66, 76), { Material = METAL })
	newPart("LampArm", V3(0.35, 0.35, 2.4), base * CF(0, 11.9, -1.0), RGB(60, 66, 76), { Material = METAL }, m)
	newPart("LampCap", V3(2.8, 0.3, 2.8), base * CF(0, 12.2, -2.1), C_DARK, nil, m)
	local head = newPart("LampHead", V3(2.2, 0.5, 2.2), base * CF(0, 11.9, -2.1), C_WARM, NEON_DECO, m)
	addPointLight(head, RGB(255, 226, 160), 30, 1, true)
end

local function buildBench(parent: Instance, cf: CFrame)
	local m = newModel("Bench", parent)
	local wood: Props = { Material = Enum.Material.Wood }
	newPart("Seat", V3(5, 0.4, 1.8), cf * CF(0, 1.5, 0), C_WOOD, wood, m)
	newPart("Back", V3(5, 1.6, 0.3), cf * CF(0, 2.6, 0.8) * ANG(math.rad(-10), 0, 0), C_WOOD, wood, m)
	for _, sx in { -2.2, 2.2 } do
		newPart("Leg", V3(0.4, 1.5, 1.8), cf * CF(sx, 0.75, 0), C_DARK, nil, m)
	end
end

local FLOWER_COLORS = { RGB(255, 90, 120), RGB(255, 210, 60), RGB(250, 250, 250), RGB(190, 120, 255), RGB(255, 150, 60) }

local function buildFlowerBed(parent: Instance, cf: CFrame, rng: Random)
	local m = newModel("FlowerBed", parent)
	newPart("BedBorder", V3(9, 0.9, 3.6), cf * CF(0, 0.45, 0), C_STONE, nil, m)
	newPart("BedSoil", V3(8.2, 0.2, 2.8), cf * CF(0, 0.92, 0), RGB(94, 64, 42), { Material = Enum.Material.Ground }, m)
	for k = -3, 3 do
		local col = FLOWER_COLORS[rng:NextInteger(1, #FLOWER_COLORS)]
		local fz = if k % 2 == 0 then -0.6 else 0.6
		worldBall(m, "Flower", 1.1, cf * CF(k * 1.1, 1.5, fz), col, { CanCollide = false })
	end
	worldBall(m, "Bush", 2.2, cf * CF(0, 1.6, 0), RGB(60, 140, 62), { CanCollide = false })
end

local function buildWelcomeSign(parent: Instance, plotIndex: number)
	local a = Layout.plotAngle(plotIndex)
	local out = V3(math.sin(a), 0, math.cos(a))
	local pos = out * 68
	local base = CFrame.lookAt(pos, pos + out) -- Front (-Z) faces the plot
	local accent = ACCENTS[plotIndex]
	local m = newModel("WelcomeSign" .. plotIndex, parent)
	newPart("SignBase", V3(20, 0.8, 3.2), base * CF(0, 0.4, 0), C_STONE, nil, m)
	for _, sx in { -8.5, 8.5 } do
		newPart("SignPost", V3(1.2, 6.5, 1.2), base * CF(sx, 4.0, 0), C_DARK, nil, m)
	end
	local board = newPart("SignBoard", V3(19, 4.6, 0.8), base * CF(0, 7.2, 0), C_DARKER, nil, m)
	addSignText(board, "SignFront", "Text", "GARAGE TYCOON", nil, 36, Enum.NormalId.Front)
	addSignText(board, "SignBack", "Text", "GARAGE TYCOON", nil, 36, Enum.NormalId.Back)
	for _, dy in { -2.5, 2.5 } do
		newPart("SignTrim", V3(19.6, 0.35, 1.2), base * CF(0, 7.2 + dy, 0), accent, NEON_DECO, m)
	end
	for _, sx in { -9.7, 9.7 } do
		newPart("SignTrim", V3(0.35, 5.35, 1.2), base * CF(sx, 7.2, 0), accent, NEON_DECO, m)
	end
	local glow = newPart("SignGlow", V3(8, 0.3, 0.3), base * CF(0, 0.9, -1.2), accent, NEON_DECO, m)
	addPointLight(glow, accent, 22, 0.8, true)
	-- hedge in front of the base
	newPart("Hedge", V3(20, 1.6, 1.4), base * CF(0, 1.5, 2.8), RGB(56, 132, 60), nil, m)
end

local function buildMonument(world: Folder, at: (number, number, number) -> CFrame)
	local cyan = RGB(120, 215, 255)
	local neonProps: Props = { Material = NEON, CanCollide = false, CastShadow = false }
	-- gear plate on top of the upper bowl
	worldCylinder(world, "MonumentGear", "Y", 0.8, 6, at(0, 8.2, 0), C_CHROME, CHROME_PROPS)
	for k = 0, 9 do
		local a = k * TWO_PI / 10
		newPart(
			"GearTooth",
			V3(1.0, 0.8, 1.2),
			at(math.sin(a) * 3.1, 8.2, math.cos(a) * 3.1) * ANG(0, a, 0),
			C_CHROME,
			CHROME_PROPS,
			world
		)
	end
	local ring = worldCylinder(world, "MonumentGlowRing", "Y", 0.3, 7.4, at(0, 7.9, 0), cyan, neonProps)
	addPointLight(ring, cyan, 40, 1.2, true)
	-- giant wrench: handle, hub and two jaws
	worldCylinder(world, "WrenchHandle", "Y", 11, 1.4, at(0, 14.1, 0), C_CHROME, CHROME_PROPS)
	for _, fz in { -0.72, 0.72 } do
		newPart("WrenchInlay", V3(0.3, 8.5, 0.1), at(0, 14.1, fz), cyan, neonProps, world)
	end
	worldCylinder(world, "WrenchHub", "Z", 1.6, 4, at(0, 20.2, 0), C_CHROME, CHROME_PROPS)
	for _, sx in { -1.7, 1.7 } do
		newPart("WrenchJaw", V3(1.4, 3.6, 1.6), at(sx, 23.0, 0), C_CHROME, CHROME_PROPS, world)
	end
	local bolt = newPart("WrenchBolt", V3(2.0, 0.4, 1.2), at(0, 22.5, 0), cyan, neonProps, world)
	addPointLight(bolt, cyan, 36, 1.4, true)
	-- one glowing orb per garage color circling the wrench
	for i = 1, Layout.PLOT_COUNT do
		local a = Layout.plotAngle(i)
		worldBall(world, "MonumentOrb", 1.3, at(math.sin(a) * 4.6, 12.5, math.cos(a) * 4.6), ACCENTS[i], neonProps)
	end
end

local function buildFountain(world: Folder)
	local center = Layout.RING_CENTER
	local g = Layout.GROUND_Y
	local function at(x: number, y: number, z: number): CFrame
		return CF(center.X + x, g + y, center.Z + z)
	end

	-- Paved plaza
	worldCylinder(world, "Plaza", "Y", 0.2, 46, at(0, -0.04, 0), C_STONE, nil)
	worldCylinder(world, "PlazaInner", "Y", 0.2, 30, at(0, -0.02, 0), RGB(212, 210, 204), nil)

	-- Basin floor + rim
	worldCylinder(world, "BasinFloor", "Y", 1.1, 19.4, at(0, 0.55, 0), RGB(150, 150, 156), nil)
	local rimSegments = 16
	local rimStep = TWO_PI / rimSegments
	local rimR = 9.6
	for k = 0, rimSegments - 1 do
		local a = (k + 0.5) * rimStep
		local pos = at(math.sin(a) * rimR, 1.1, math.cos(a) * rimR).Position
		local cf = CFrame.lookAt(pos, at(0, 1.1, 0).Position)
		newPart("BasinRim", V3(2 * 10.4 * math.tan(rimStep / 2) * 1.12, 2.2, 1.4), cf, C_STONE, nil, world)
	end

	-- Water
	local water = worldCylinder(
		world,
		"Water",
		"Y",
		0.3,
		18,
		at(0, 1.35, 0),
		RGB(70, 180, 255),
		{ Material = NEON, Transparency = 0.5, CanCollide = false, CastShadow = false }
	)
	addPointLight(water, RGB(90, 200, 255), 40, 0.8, true)

	-- Pedestal and tiered bowl (plinth of the monument)
	worldCylinder(world, "PedestalBase", "Y", 1.6, 5.4, at(0, 1.9, 0), C_STONE, nil)
	worldCylinder(world, "PedestalColumn", "Y", 4.2, 2.6, at(0, 4.8, 0), RGB(214, 212, 206), nil)
	worldCylinder(world, "UpperBowl", "Y", 0.7, 8, at(0, 7.2, 0), C_STONE, nil)
	worldCylinder(
		world,
		"UpperWater",
		"Y",
		0.2,
		7,
		at(0, 7.65, 0),
		RGB(70, 180, 255),
		{ Material = NEON, Transparency = 0.45, CanCollide = false, CastShadow = false }
	)
	buildMonument(world, at)

	-- Small neon "droplets" in the basin
	for k = 0, 7 do
		local a = k * TWO_PI / 8
		newPart(
			"Droplet",
			V3(0.5, 0.5, 0.5),
			at(math.sin(a) * 6.2, 2.4 + (k % 2) * 1.2, math.cos(a) * 6.2) * ANG(0, a, math.rad(45)),
			RGB(170, 230, 255),
			NEON_DECO,
			world
		)
	end
end

local function buildRing(world: Folder)
	local innerR = Layout.RING_INNER_RADIUS
	local outerR = Layout.RING_OUTER_RADIUS
	local laneR = Layout.RING_LANE_RADIUS
	local segments = 64
	local step = TWO_PI / segments
	local midR = (innerR + outerR) / 2
	local roadLen = 2 * outerR * math.tan(step / 2) * 1.12

	local innerCurbR = innerR + 0.8
	local outerCurbR = outerR - 0.5
	local innerCurbLen = 2 * (innerR + 1.6) * math.tan(step / 2) * 1.1
	local outerCurbLen = 2 * (outerR + 0.4) * math.tan(step / 2) * 1.1

	local roadFolder = newFolder("RingRoad", world)

	for k = 0, segments - 1 do
		local a = (k + 0.5) * step
		local dx, dz = math.sin(a), math.cos(a)

		local pos = V3(dx * midR, ROAD_TOP - 0.15, dz * midR)
		newPart(
			"Road",
			V3(roadLen, 0.3, outerR - innerR),
			CFrame.lookAt(pos, V3(0, pos.Y, 0)),
			C_ASPHALT,
			nil,
			roadFolder
		)

		local ip = V3(dx * innerCurbR, 0.2, dz * innerCurbR)
		newPart("CurbInner", V3(innerCurbLen, 0.4, 1.6), CFrame.lookAt(ip, V3(0, 0.2, 0)), C_CURB, nil, roadFolder)

		-- outer curb, left open where the connector roads join
		local nearConnector = false
		for i = 1, Layout.PLOT_COUNT do
			if angularDistance(a, Layout.plotAngle(i)) < 0.1 then
				nearConnector = true
			end
		end
		if not nearConnector then
			local op = V3(dx * outerCurbR, 0.2, dz * outerCurbR)
			newPart("CurbOuter", V3(outerCurbLen, 0.4, 1.8), CFrame.lookAt(op, V3(0, 0.2, 0)), C_CURB, nil, roadFolder)
		end
	end

	-- dashed center line (slightly above the road)
	local dashes = 48
	for k = 0, dashes - 1 do
		local a = (k + 0.5) * TWO_PI / dashes
		local pos = V3(math.sin(a) * laneR, ROAD_TOP + LINE_THICK / 2, math.cos(a) * laneR)
		newPart("LaneDash", V3(5, LINE_THICK, 0.6), CFrame.lookAt(pos, V3(0, pos.Y, 0)), C_WHITE, DECAL, roadFolder)
	end
end

local function buildSpawn(world: Folder)
	-- Spawn plaza on the island (fountain occupies the exact center, so we spawn just next to it).
	local spawnZ = 32
	newPart("SpawnPaving", V3(18, 0.2, 18), CF(0, -0.01, spawnZ), C_STONE, nil, world)
	newPart("SpawnPath", V3(7, 0.2, 14), CF(0, -0.01, 22), C_STONE, nil, world)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "SpawnLocation"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.AllowTeamChangeOnTouch = false
	spawn.Size = V3(12, 1, 12)
	spawn.CFrame = CF(0, Layout.GROUND_Y + 0.5 + 0.1, spawnZ)
	spawn.Material = NEON
	spawn.Color = RGB(80, 210, 255)
	spawn.Transparency = 0.5
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.BottomSurface = Enum.SurfaceType.Smooth
	spawn.Parent = world
end

local function buildDecorations(world: Folder)
	local rng = Random.new(20240601)
	local decor = newFolder("Decor", world)
	local reserved: { Vector3 } = { V3(0, 0, 32) }

	-- Street lamps along the outer curb of the ring (between plot connectors), facing the road.
	local lampCount = 20
	for k = 0, lampCount - 1 do
		local a = (k + 0.5) * TWO_PI / lampCount
		local r = Layout.RING_OUTER_RADIUS + 3.5
		buildLamp(decor, V3(math.sin(a) * r, Layout.GROUND_Y, math.cos(a) * r), V3(-math.sin(a), 0, -math.cos(a)))
	end
	-- Street lamps on the island side of the ring.
	for k = 0, 7 do
		local a = (k + 0.5) * TWO_PI / 8
		local r = Layout.RING_INNER_RADIUS - 3.5
		buildLamp(decor, V3(math.sin(a) * r, Layout.GROUND_Y, math.cos(a) * r), V3(math.sin(a), 0, math.cos(a)))
	end

	-- Welcome signs facing each plot.
	for i = 1, Layout.PLOT_COUNT do
		buildWelcomeSign(decor, i)
		local a = Layout.plotAngle(i)
		table.insert(reserved, V3(math.sin(a) * 68, 0, math.cos(a) * 68))
	end

	-- Benches facing flower beds, 8 pairs around the plaza.
	for k = 0, 7 do
		local a = math.rad(22.5) + k * math.pi / 4
		local dx, dz = math.sin(a), math.cos(a)
		local bedPos = V3(dx * 46, 0, dz * 46)
		buildFlowerBed(decor, CFrame.lookAt(bedPos, V3(0, 0, 0)) * ANG(0, math.pi, 0), rng)
		local benchPos = V3(dx * 56, 0, dz * 56)
		buildBench(decor, CFrame.lookAt(benchPos, V3(0, 0, 0)))
		table.insert(reserved, bedPos)
		table.insert(reserved, benchPos)
	end

	-- Trees on the island (keep clear of plaza, spawn, beds, benches, signs and road).
	local placed = 0
	local attempts = 0
	while placed < 24 and attempts < 600 do
		attempts += 1
		local a = rng:NextNumber(0, TWO_PI)
		local r = rng:NextNumber(34, 68)
		local pos = V3(math.sin(a) * r, Layout.GROUND_Y, math.cos(a) * r)
		local ok = true
		for _, rp in reserved do
			local d = V3(pos.X - rp.X, 0, pos.Z - rp.Z).Magnitude
			if d < (if rp.Z == 32 and rp.X == 0 then 20 else 9) then
				ok = false
				break
			end
		end
		if ok then
			buildTree(decor, pos, rng:NextNumber(0.9, 1.4), rng)
			table.insert(reserved, pos)
			placed += 1
		end
	end

	-- Trees outside the ring, away from road, plots and connectors.
	placed = 0
	attempts = 0
	while placed < 40 and attempts < 1500 do
		attempts += 1
		local a = rng:NextNumber(0, TWO_PI)
		local r = rng:NextNumber(126, 380)
		local pos = V3(math.sin(a) * r, Layout.GROUND_Y, math.cos(a) * r)
		if not nearPlot(pos) then
			buildTree(decor, pos, rng:NextNumber(0.9, 1.6), rng)
			placed += 1
		end
	end
end

local function buildWorld(): Folder
	local world = newFolder("World", Workspace)

	newPart(
		"Ground",
		V3(1400, 2, 1400),
		CF(0, Layout.GROUND_Y - 1, 0),
		C_GRASS,
		{ Material = Enum.Material.Grass },
		world
	)
	worldCylinder(
		world,
		"Island",
		"Y",
		0.5,
		Layout.RING_INNER_RADIUS * 2 - 0.4,
		CF(0, Layout.GROUND_Y + 0.04 - 0.25, 0),
		C_ISLAND,
		{ Material = Enum.Material.Grass }
	)

	buildRing(world)
	buildFountain(world)
	buildSpawn(world)
	buildDecorations(world)
	return world
end

------------------------------------------------------------------------------------------------
-- Plot: reusable decor (plot space)
------------------------------------------------------------------------------------------------

local function plant(ctx: Ctx, parent: Instance, x: number, y: number, z: number, s: number)
	ctx.C(parent, "PlantPot", "Y", 1.8 * s, 2.2 * s, CF(x, y + 0.9 * s, z), C_POT, nil)
	ctx.B(parent, "PlantLeaves", 2.8 * s, CF(x, y + 2.9 * s, z), C_LEAF, { CanCollide = false, Material = Enum.Material.Grass })
	ctx.B(
		parent,
		"PlantLeaves",
		1.8 * s,
		CF(x + 0.7 * s, y + 3.9 * s, z - 0.3 * s),
		RGB(92, 178, 80),
		{ CanCollide = false, Material = Enum.Material.Grass }
	)
end

local function bench(ctx: Ctx, parent: Instance, x: number, y: number, z: number, rotY: number)
	local base = CF(x, y, z) * ANG(0, rotY, 0)
	local wood: Props = { Material = Enum.Material.Wood }
	ctx.P(parent, "BenchSeat", V3(5, 0.4, 1.8), base * CF(0, 1.5, 0), C_WOOD, wood)
	ctx.P(parent, "BenchBack", V3(5, 1.6, 0.3), base * CF(0, 2.6, 0.8) * ANG(math.rad(-10), 0, 0), C_WOOD, wood)
	for _, sx in { -2.2, 2.2 } do
		ctx.P(parent, "BenchLeg", V3(0.4, 1.5, 1.8), base * CF(sx, 0.75, 0), C_DARK)
	end
end

local function bikeRack(ctx: Ctx, parent: Instance, x: number, z: number, rotY: number)
	local base = CF(x, 0, z) * ANG(0, rotY, 0)
	ctx.P(parent, "RackBase", V3(8, 0.3, 1.2), base * CF(0, 0.15, 0), C_DARK)
	for k = -1, 1 do
		local hx = k * 2.6
		for _, sx in { -0.8, 0.8 } do
			ctx.P(parent, "RackPost", V3(0.25, 2.4, 0.25), base * CF(hx + sx, 1.5, 0), C_CHROME, CHROME_PROPS)
		end
		ctx.P(parent, "RackTop", V3(1.85, 0.25, 0.25), base * CF(hx, 2.7, 0), C_CHROME, CHROME_PROPS)
	end
end

local function cone(ctx: Ctx, parent: Instance, x: number, z: number)
	ctx.P(parent, "ConeBase", V3(1.6, 0.15, 1.6), CF(x, 0.075, z), RGB(30, 30, 34))
	ctx.C(parent, "ConeBody", "Y", 1.9, 1.0, CF(x, 1.1, z), RGB(255, 120, 20), nil)
	ctx.C(parent, "ConeBand", "Y", 0.35, 1.06, CF(x, 1.3, z), C_WHITE, DECAL)
end

local function tirePile(ctx: Ctx, parent: Instance, x: number, z: number)
	for k = 0, 2 do
		ctx.C(parent, "PileTire", "Y", 1.1, 3.2, CF(x + (k - 1) * 3.3, 0.55, z), C_TIRE, nil)
	end
	for k = 0, 1 do
		ctx.C(parent, "PileTire", "Y", 1.1, 3.2, CF(x + (k - 0.5) * 3.3, 1.65, z + 0.3), C_TIRE, nil)
	end
	ctx.C(parent, "PileTire", "Y", 1.1, 3.2, CF(x, 2.75, z), C_TIRE, nil)
end

local function crate(ctx: Ctx, parent: Instance, x: number, y: number, z: number, s: number, rotY: number)
	ctx.P(parent, "Crate", V3(3 * s, 3 * s, 3 * s), CF(x, y + 1.5 * s, z) * ANG(0, rotY, 0), RGB(176, 130, 80), { Material = Enum.Material.Wood })
end

local function barrel(ctx: Ctx, parent: Instance, x: number, z: number, color: Color3)
	ctx.C(parent, "Barrel", "Y", 3.2, 2.2, CF(x, 1.6, z), color, { Reflectance = 0.1 })
	ctx.C(parent, "BarrelRing", "Y", 0.2, 2.3, CF(x, 2.3, z), C_DARK, nil)
end

-- Painted arrow on the ground (shaft along X, head toward `dir`).
local function paintedArrow(ctx: Ctx, parent: Instance, x: number, z: number, dir: number)
	local y = LOT_TOP + LINE_THICK / 2
	ctx.P(parent, "LotArrow", V3(5, LINE_THICK, 0.6), CF(x, y, z), C_WHITE, DECAL)
	for _, side in { -1, 1 } do
		ctx.P(
			parent,
			"LotArrow",
			V3(2.4, LINE_THICK, 0.6),
			CF(x + dir * 2.0, y, z + side * 0.85) * ANG(0, -side * dir * math.rad(45), 0),
			C_WHITE,
			DECAL
		)
	end
end

local function buildLampPost(ctx: Ctx, parent: Instance, x: number, z: number)
	ctx.P(parent, "LampBase", V3(1.4, 0.5, 1.4), CF(x, LOT_TOP + 0.25, z), C_DARK)
	ctx.C(parent, "LampPole", "Y", 10, 0.45, CF(x, LOT_TOP + 5.5, z), RGB(60, 66, 76), { Material = METAL })
	ctx.P(parent, "LampCap", V3(2.4, 0.3, 2.4), CF(x, LOT_TOP + 10.7, z), C_DARK)
	local head = ctx.P(parent, "LampHead", V3(1.8, 0.5, 1.8), CF(x, LOT_TOP + 10.35, z), C_WARM, NEON_DECO)
	addPointLight(head, RGB(255, 226, 160), 30, 1.2, true)
end

local function parkingSpot(ctx: Ctx, parent: Instance, queueIndex: number)
	local q: Vector3 = Layout.QUEUE[queueIndex].Position
	outline(ctx, parent, "SpotLine", q.X, q.Z, 8.4, 15.4, 0.3, LOT_TOP + LINE_THICK / 2, C_WHITE)
end

------------------------------------------------------------------------------------------------
-- Plot: static parts
------------------------------------------------------------------------------------------------

local function buildGate(ctx: Ctx, static: Folder)
	local gate = newModel("Gate", static)
	local gz = Layout.GATE.Position.Z -- -60

	for _, sx in { -1, 1 } do
		ctx.P(gate, "GateBase", V3(3.6, 0.8, 3.6), CF(sx * 14, 0.4, gz), C_CHROME, { Material = METAL })
		ctx.P(gate, "GatePillar", V3(2.4, 16, 2.4), CF(sx * 14, 8.4, gz), C_DARK)
		ctx.A(gate, "GatePillarNeon", V3(0.35, 14, 0.2), CF(sx * 14, 8.4, gz - 1.3))
	end
	ctx.P(gate, "GateBeam", V3(32, 2.4, 3), CF(0, 16, gz), C_DARK)
	local beamNeon = ctx.A(gate, "GateBeamNeon", V3(31.6, 0.3, 0.2), CF(0, 15.3, gz - 1.6))
	addPointLight(beamNeon, ctx.accent, 25, 0.8, true)

	local board = ctx.P(gate, "SignBoard", V3(24, 5, 0.8), CF(0, 12.3, gz), C_DARKER)
	ctx.A(gate, "SignTrim", V3(24.7, 0.35, 0.4), CF(0, 9.65, gz - 0.5))
	for _, sx in { -1, 1 } do
		ctx.A(gate, "SignTrim", V3(0.35, 5.0, 0.4), CF(sx * 12.15, 12.3, gz - 0.5))
	end
	addSignText(board, "SignGui", "OwnerLabel", "", "plot_free", 40)
	gate.PrimaryPart = board
end

local function buildSafe(ctx: Ctx, static: Folder)
	local safe = newModel("Safe", static)
	local s: CFrame = Layout.SAFE
	local sx, sz = s.Position.X, s.Position.Z
	local cy = FLOOR_TOP

	local body = ctx.P(
		safe,
		"Body",
		V3(4, 5, 4),
		CF(sx, cy + 2.5, sz),
		RGB(46, 50, 58),
		{ Material = METAL, Reflectance = 0.1 }
	)
	safe.PrimaryPart = body
	ctx.P(safe, "SafeDoor", V3(3.2, 4.2, 0.2), CF(sx, cy + 2.5, sz - 2.05), RGB(78, 84, 96), { Material = METAL })
	ctx.A(safe, "SafeBand", V3(4.1, 0.3, 4.1), CF(sx, cy + 4.6, sz))
	ctx.P(safe, "SafeHandle", V3(0.3, 1.8, 0.3), CF(sx + 1.0, cy + 2.4, sz - 2.3), C_CHROME, CHROME_PROPS)
	ctx.C(safe, "SafeDial", "Z", 0.3, 1.3, CF(sx - 0.5, cy + 3.0, sz - 2.25), C_CHROME, CHROME_PROPS)
	ctx.P(safe, "SafeKeypad", V3(0.9, 0.5, 0.1), CF(sx - 0.5, cy + 1.7, sz - 2.2), RGB(90, 255, 140), NEON_DECO)
	for _, fx in { -1.6, 1.6 } do
		ctx.P(safe, "SafeFoot", V3(0.7, 0.3, 0.7), CF(sx + fx, cy + 0.15, sz - 1.6), C_DARKER)
	end

	-- Collect pad on the ground in front (-Z side)
	local pad = ctx.P(
		safe,
		"CollectPad",
		V3(8, 0.4, 8),
		CF(sx, cy + 0.2, sz - 2 - 4 - 0.5),
		ctx.accent,
		{ Material = NEON, Transparency = 0.25, CanCollide = false, CastShadow = false }
	)
	tag(pad, "Accent")
	addPointLight(pad, ctx.accent, 14, 0.8)

	-- Amount display
	local gui = Instance.new("BillboardGui")
	gui.Name = "AmountGui"
	gui.Adornee = body
	gui.StudsOffset = V3(0, 4, 0)
	gui.Size = UDim2.new(0, 160, 0, 50)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 80
	gui.LightInfluence = 0
	gui.Parent = body
	local label = newLabel(gui, "AmountLabel", "$0", RGB(90, 255, 120), UDim2.fromScale(1, 1))
	label.Font = Enum.Font.GothamBlack
	addStroke(label, 2.5, Color3.new(0, 0, 0))
end

local function buildHireBoard(ctx: Ctx, static: Folder)
	local hb = newModel("HireBoard", static)
	local b: CFrame = Layout.HIRE_BOARD
	local bx, bz = b.Position.X, b.Position.Z - 0.6 -- stand just in front of the back wall
	local bc = 5.5

	local cork = RGB(196, 150, 98)
	local wood = RGB(110, 76, 48)
	local board = ctx.P(hb, "Board", V3(10, 6, 0.5), CF(bx, bc, bz), cork)
	hb.PrimaryPart = board

	ctx.P(hb, "Frame", V3(10.8, 0.4, 0.7), CF(bx, bc + 3.2, bz), wood)
	ctx.P(hb, "Frame", V3(10.8, 0.4, 0.7), CF(bx, bc - 3.2, bz), wood)
	for _, sx in { -1, 1 } do
		ctx.P(hb, "Frame", V3(0.4, 6.8, 0.7), CF(bx + sx * 5.2, bc, bz), wood)
		ctx.P(hb, "Leg", V3(0.5, 2.5, 0.5), CF(bx + sx * 4, 1.25 + FLOOR_TOP, bz), wood)
	end

	local plate = ctx.P(hb, "TitlePlate", V3(8, 1.3, 0.4), CF(bx, bc + 4.05, bz), C_DARKER)
	ctx.A(hb, "TitleNeon", V3(8.2, 0.2, 0.3), CF(bx, bc + 3.45, bz - 0.2))
	local gui = newSurfaceGui(plate, "TitleGui", Enum.NormalId.Front, 60)
	local title = newLabel(gui, "TitleLabel", "Hire Board", RGB(255, 255, 255), UDim2.fromScale(1, 1))
	title.Font = Enum.Font.GothamBlack
	title:SetAttribute("TextKey", "object_hire_board")
	addStroke(title, 2, Color3.new(0, 0, 0))

	local notes: { any } = {
		{ -3.4, 6.7, RGB(255, 235, 120), 5 },
		{ -0.9, 4.3, RGB(255, 160, 190), -7 },
		{ 1.5, 6.7, RGB(150, 215, 255), -4 },
		{ 3.6, 4.4, RGB(170, 240, 170), 8 },
		{ -3.7, 4.2, RGB(255, 190, 120), -6 },
	}
	for _, n in notes do
		local nx: number, ny: number, ncol: Color3, roll: number = n[1], n[2], n[3], n[4]
		ctx.P(hb, "Note", V3(2, 2.5, 0.06), CF(bx + nx, ny, bz - 0.28) * ANG(0, 0, math.rad(roll)), ncol, DECAL)
		ctx.P(hb, "NotePin", V3(0.3, 0.3, 0.1), CF(bx + nx, ny + 1.0, bz - 0.33), RGB(220, 40, 40), DECAL)
	end
end

local function buildOutside(ctx: Ctx, static: Folder)
	-- Plot slab + parking lot
	ctx.P(static, "PlotSlab", V3(Layout.PLOT_WIDTH, 0.4, Layout.PLOT_DEPTH), CF(0, -0.18, 0), C_CONCRETE)
	local lotMin = -Layout.PLOT_DEPTH / 2 -- -60
	local lotMax = Layout.BUILDING.frontZ -- -22
	ctx.P(static, "ParkingLot", V3(Layout.PLOT_WIDTH, 0.2, lotMax - lotMin), CF(0, LOT_TOP - 0.1, (lotMin + lotMax) / 2), C_ASPHALT)
	for n = 1, 3 do
		parkingSpot(ctx, static, n)
	end

	-- Connector road: local Z -60 .. CONNECTOR_RING_Z (slightly into the ring), 22 wide
	local ringZ = Layout.CONNECTOR_RING_Z - 2
	local len = lotMin - ringZ
	ctx.P(static, "ConnectorRoad", V3(22, 0.3, len), CF(0, ROAD_TOP - 0.15, (lotMin + ringZ) / 2), C_ASPHALT)
	for _, ex in { -10.5, 10.5 } do
		ctx.P(static, "ConnectorEdge", V3(0.3, LINE_THICK, len - 4), CF(ex, ROAD_TOP + LINE_THICK / 2, (lotMin + ringZ) / 2), C_WHITE, DECAL)
	end
	local z = lotMin - 4
	while z > Layout.CONNECTOR_RING_Z + 4 do
		ctx.P(
			static,
			"ConnectorDash",
			V3(0.5, LINE_THICK, 4),
			CF((Layout.ENTRY_LANE_X + Layout.EXIT_LANE_X) / 2, ROAD_TOP + LINE_THICK / 2, z),
			C_WHITE,
			DECAL
		)
		z -= 8
	end
	-- direction arrows (entry lane heads toward the plot, exit lane toward the ring)
	local arrows: { any } = { { Layout.ENTRY_LANE_X, 1 }, { Layout.EXIT_LANE_X, -1 } }
	for _, a in arrows do
		local ax: number, dir: number = a[1], a[2]
		local az = (lotMin + Layout.CONNECTOR_RING_Z) / 2
		ctx.P(static, "LaneArrow", V3(0.6, LINE_THICK, 5), CF(ax, ROAD_TOP + LINE_THICK / 2, az), C_WHITE, DECAL)
		for _, side in { -1, 1 } do
			ctx.P(
				static,
				"LaneArrow",
				V3(0.6, LINE_THICK, 2.4),
				CF(ax + side * 0.85, ROAD_TOP + LINE_THICK / 2, az + dir * 1.65) * ANG(0, -side * dir * math.rad(45), 0),
				C_WHITE,
				DECAL
			)
		end
	end

	-- Crosswalk stripes where the connector meets the ring (clear of the dashed center line).
	for _, cx in { -9.1, -6.5, -3.9, -1.3, 1.3, 3.9, 6.5, 9.1 } do
		ctx.P(static, "Crosswalk", V3(1.4, LINE_THICK, 5), CF(cx, ROAD_TOP + LINE_THICK / 2, -114), C_WHITE, DECAL)
	end

	-- Painted arrows on the lot lane (cars fan out from the entry lane to both sides).
	for _, ax in { 12, 32 } do
		paintedArrow(ctx, static, ax, Layout.LOT_LANE_Z, 1)
		paintedArrow(ctx, static, -ax, Layout.LOT_LANE_Z, -1)
	end

	-- Lot lamp posts (left pair; the right pair belongs to the Parking unlock).
	buildLampPost(ctx, static, -42, -42)
	buildLampPost(ctx, static, -54, -42)
	buildLampPost(ctx, static, -66.5, -56)
	buildLampPost(ctx, static, 66.5, -56)
	buildLampPost(ctx, static, -66.5, -30)
	buildLampPost(ctx, static, 66.5, -30)
end

-- Planters + benches at the gate, and the side yards beside the building.
local function buildYards(ctx: Ctx, static: Folder)
	-- entrance, just outside the gate
	for _, sx in { -1, 1 } do
		ctx.P(static, "PlanterBox", V3(4.4, 1.0, 4.4), CF(sx * 19, 0.5, -64), C_STONE)
		plant(ctx, static, sx * 19, 1.0, -64, 1.1)
		bench(ctx, static, sx * 27, 0, -64, 0)
	end

	-- east yard: bike rack, bench, plants
	bikeRack(ctx, static, 77, 12, math.pi / 2)
	bench(ctx, static, 77, 0, -12, -math.pi / 2)
	plant(ctx, static, 77, 0, -4, 1)
	plant(ctx, static, 77, 0, -22, 1)

	-- west yard: tire pile, cones, crates, barrels
	tirePile(ctx, static, -78, 8)
	for k = 0, 2 do
		cone(ctx, static, -75, -20 + k * 5)
	end
	crate(ctx, static, -79, 0, 24, 1, 0.2)
	crate(ctx, static, -79, 3, 24, 0.8, -0.3)
	crate(ctx, static, -75.5, 0, 27, 0.9, 0.5)
	barrel(ctx, static, -80, 30, RGB(40, 90, 200))
	barrel(ctx, static, -77, 32, RGB(210, 50, 50))
end

local function buildRoofTop(ctx: Ctx, static: Folder)
	local roofTop = Layout.BUILDING.height + 1.5
	-- AC units
	for _, ax in { 30, 42, 54 } do
		ctx.P(static, "RoofAC", V3(5, 2.4, 4), CF(ax, roofTop + 1.2, 6), RGB(205, 210, 218), { Material = METAL })
		ctx.C(static, "RoofACFan", "Y", 0.2, 3.2, CF(ax, roofTop + 2.5, 6), C_DARK, nil)
		ctx.P(static, "RoofACLouver", V3(4.4, 1.2, 0.1), CF(ax, roofTop + 1.2, 3.95), C_DARK, DECAL)
	end
	-- Solar panels (2 rows x 4), tilted toward the front
	for _, pz in { 22, 38 } do
		for _, px in { -57, -45, -33, -21 } do
			ctx.P(
				static,
				"SolarPanel",
				V3(8.4, 0.25, 5.6),
				CF(px, roofTop + 0.95, pz) * ANG(math.rad(-20), 0, 0),
				RGB(28, 46, 98),
				{ Reflectance = 0.25, Material = Enum.Material.Glass }
			)
			ctx.P(static, "SolarLeg", V3(7.6, 1.5, 0.3), CF(px, roofTop + 0.75, pz + 2.2), C_STEEL, { Material = METAL })
		end
	end
end

local function buildSideFacade(ctx: Ctx, static: Folder)
	local B = Layout.BUILDING
	local height = B.height
	for _, sx in { -1, 1 } do
		-- ribbed (corrugated look) panels on the outer wall face
		for k = 0, 18 do
			ctx.P(
				static,
				"WallRib",
				V3(0.5, 12.4, 1.2),
				CF(sx * (B.maxX + 0.25), 6.6, -16 + k * 4),
				RGB(214, 218, 226),
				{ Material = METAL, Reflectance = 0.1 }
			)
		end
		ctx.R(static, "WallStripe", V3(0.4, 1.4, 80), CF(sx * (B.maxX + 0.2), 13.6, 18), ctx.accent, "Stripe")
		-- gutter under the roof edge and two downpipes
		ctx.P(static, "Gutter", V3(0.8, 0.6, 84), CF(sx * 71.5, height - 0.3, 19), C_STEEL, { Material = METAL })
		for _, pz in { -19, 57 } do
			ctx.C(static, "Downpipe", "Y", height - 0.7, 0.5, CF(sx * 71.5, (height - 0.7) / 2 + 0.1, pz), C_STEEL, { Material = METAL })
		end
	end
end

local function buildFascia(ctx: Ctx, static: Folder)
	local B = Layout.BUILDING
	local height = B.height
	-- thick accent fascia hanging at the front edge of the roof
	ctx.T(static, "RoofFascia", V3(144, 4, 1.4), CF(0, height + 0.6, B.frontZ - 1.4))
	ctx.A(static, "RoofNeonFront", V3(144, 0.4, 0.3), CF(0, height - 1.2, B.frontZ - 2.2))
	-- name sign area
	local plate = ctx.P(static, "FasciaSign", V3(46, 3, 0.3), CF(0, height + 0.8, B.frontZ - 2.25), C_DARKER)
	addSignText(plate, "FasciaGui", "FasciaLabel", "GARAGE", nil, 40)
	for _, dy in { -1.7, 1.7 } do
		ctx.A(static, "FasciaTrim", V3(46.6, 0.2, 0.5), CF(0, height + 0.8 + dy, B.frontZ - 2.3))
	end
	for _, sx in { -1, 1 } do
		ctx.A(static, "FasciaTrim", V3(0.2, 3.4, 0.5), CF(sx * 23.3, height + 0.8, B.frontZ - 2.3))
		-- gear badge beside the sign
		ctx.C(static, "FasciaBadge", "Z", 0.3, 3.2, CF(sx * 29, height + 0.8, B.frontZ - 2.25), C_DARKER, nil)
		ctx.C(static, "FasciaBadgeRim", "Z", 0.2, 2.4, CF(sx * 29, height + 0.8, B.frontZ - 2.45), C_CHROME, CHROME_PROPS)
	end
	-- exterior down-lights under the fascia
	for _, lx in { -56, -28, 0, 28, 56 } do
		ctx.P(static, "FasciaLamp", V3(1.4, 0.3, 1.4), CF(lx, height - 1.55, B.frontZ - 1.4), C_DARK)
		local lens = ctx.P(static, "FasciaLens", V3(1, 0.1, 1), CF(lx, height - 1.75, B.frontZ - 1.4), C_WARM, NEON_DECO)
		addSpotLight(lens, Enum.NormalId.Bottom, RGB(255, 240, 210), 24, 80, 1.6, true)
	end
end

-- Roll-up door that closes the doorway to the annex (server hides it when TuningRoom is owned).
local function buildAnnexDoor(ctx: Ctx, static: Folder)
	local B = Layout.BUILDING
	local wallZ = B.backZ - 1 -- 59, center of the 2 thick back wall
	-- permanent frame (stays after the door is gone)
	for _, sx in { -1, 1 } do
		ctx.T(static, "DoorJamb", V3(1.2, 12, 2.4), CF(sx * 8.2, 6.1, wallZ))
	end
	ctx.T(static, "DoorHeader", V3(17.6, 1, 2.4), CF(0, 11.9, wallZ))

	local door = newModel("AnnexDoor", static)
	door:SetAttribute("HideWhenOwned", "TuningRoom")
	local backing = ctx.P(door, "DoorBacking", V3(16, 11.5, 0.4), CF(0, 5.85, wallZ), RGB(50, 54, 62))
	door.PrimaryPart = backing
	for k = 0, 10 do
		ctx.P(
			door,
			"DoorSlat",
			V3(15.6, 0.9, 0.5),
			CF(0, 0.6 + k * 1.05, wallZ - 0.35),
			RGB(176, 182, 192),
			{ Material = METAL, Reflectance = 0.15 }
		)
	end
	ctx.P(door, "DoorHandle", V3(1.4, 0.3, 0.4), CF(0, 1.5, wallZ - 0.75), C_DARK)
	ctx.P(door, "DoorHazard", V3(15.6, 0.3, 0.1), CF(0, 11.35, wallZ - 0.62), C_YELLOW, DECAL)
	local lamp = ctx.P(door, "DoorLight", V3(0.8, 0.4, 0.2), CF(0, 11.0, wallZ - 0.65), RGB(255, 70, 60), NEON_DECO)
	addPointLight(lamp, RGB(255, 80, 70), 8, 0.6)

	-- interior sign above the doorway
	local plate = ctx.P(static, "AnnexSign", V3(14, 3, 0.3), CF(0, 15.5, B.backZ - 2.15), C_DARKER)
	addSignText(plate, "AnnexGui", "AnnexLabel", "TUNING", "unlock_TuningRoom", 40)
	for _, dy in { -1.7, 1.7 } do
		ctx.A(static, "AnnexSignTrim", V3(14.6, 0.2, 0.4), CF(0, 15.5 + dy, B.backZ - 2.2))
	end
end

local function buildBuilding(ctx: Ctx, static: Folder)
	local accent = ctx.accent
	local B = Layout.BUILDING
	local width = B.maxX - B.minX -- 140
	local depth = B.backZ - B.frontZ -- 82
	local midZ = (B.frontZ + B.backZ) / 2 -- 19
	local height = B.height

	-- Floor with subtle grid
	ctx.R(static, "Floor", V3(width, 0.2, depth), CF(0, 0, midZ), C_FLOOR, "Floor", { Reflectance = 0.08 })
	local gridY = FLOOR_TOP + 0.01
	for _, gx in { -56, -42, -28, -14, 0, 14, 28, 42, 56 } do
		ctx.P(static, "FloorGrid", V3(0.15, 0.02, depth - 0.4), CF(gx, gridY, midZ), C_GRID, DECAL)
	end
	for _, gz in { -8, 6, 20, 34, 48 } do
		ctx.P(static, "FloorGrid", V3(width - 0.4, 0.02, 0.15), CF(0, gridY, gz), C_GRID, DECAL)
	end
	ctx.A(static, "FloorThreshold", V3(width, 0.05, 0.5), CF(0, FLOOR_TOP + 0.025, B.frontZ + 0.25))

	-- Walls: back (split around the annex doorway X -8..8, height 12) + two sides; front is open
	for _, sx in { -1, 1 } do
		ctx.R(static, "BackWall", V3(62, height, 2), CF(sx * 39, height / 2, B.backZ - 1), C_WALL, "Wall")
		ctx.R(static, "SideWall", V3(2, height, depth - 2), CF(sx * (B.maxX - 1), height / 2, midZ - 1), C_WALL, "Wall")
	end
	ctx.R(static, "BackWallLintel", V3(16, height - 12, 2), CF(0, 12 + (height - 12) / 2, B.backZ - 1), C_WALL, "Wall")
	local innerX = B.maxX - 2 -- 68
	local innerZ = B.backZ - 2 -- 58

	-- Baseboards + accent stripes on the inner faces (back wall skips the doorway)
	for _, sx in { -1, 1 } do
		ctx.P(static, "Baseboard", V3(60, 1.2, 0.2), CF(sx * 38, FLOOR_TOP + 0.6, innerZ - 0.1), C_DARK)
		ctx.R(static, "WallStripe", V3(60, 3, 0.2), CF(sx * 38, 4, innerZ - 0.1), accent, "Stripe")
		ctx.A(static, "WallStripeNeon", V3(60, 0.3, 0.25), CF(sx * 38, 5.9, innerZ - 0.15))

		ctx.P(static, "Baseboard", V3(0.2, 1.2, depth - 2), CF(sx * (innerX - 0.1), FLOOR_TOP + 0.6, midZ - 1), C_DARK)
		ctx.R(static, "WallStripe", V3(0.2, 3, depth - 2), CF(sx * (innerX - 0.1), 4, midZ - 1), accent, "Stripe")
		ctx.A(static, "WallStripeNeon", V3(0.25, 0.3, depth - 2), CF(sx * (innerX - 0.15), 5.9, midZ - 1))
	end

	-- Windows (frame + tinted glass sitting on the inner wall faces). The +X side and the back-right
	-- ones are raised above the mezzanine slab.
	local glassProps: Props = {
		Material = Enum.Material.Glass,
		Transparency = 0.3,
		Reflectance = 0.2,
		CanCollide = false,
		CastShadow = false,
	}
	local glassColor = RGB(110, 180, 220)
	local sideWindows: { any } = {
		{ -1, 0, 12.5, 7 },
		{ -1, 22, 12.5, 7 },
		{ -1, 44, 12.5, 7 },
		{ 1, 0, 12.5, 7 },
		{ 1, 22, 17.5, 5 },
		{ 1, 44, 17.5, 5 },
	}
	for _, w in sideWindows do
		local sx: number, wz: number, wy: number, wh: number = w[1], w[2], w[3], w[4]
		ctx.P(static, "WindowFrame", V3(0.15, wh, 14), CF(sx * (innerX - 0.075), wy, wz), C_DARK, DECAL)
		ctx.P(static, "WindowGlass", V3(0.2, wh - 1, 12.4), CF(sx * (innerX - 0.1), wy, wz), glassColor, glassProps)
	end
	local backWindows: { any } = { { -30, 12.5, 7 }, { 30, 17.5, 5 } }
	for _, w in backWindows do
		local wx: number, wy: number, wh: number = w[1], w[2], w[3]
		ctx.P(static, "WindowFrame", V3(14, wh, 0.15), CF(wx, wy, innerZ - 0.075), C_DARK, DECAL)
		ctx.P(static, "WindowGlass", V3(12.4, wh - 1, 0.2), CF(wx, wy, innerZ - 0.1), glassColor, glassProps)
	end

	-- Roof + ceiling lights
	ctx.R(static, "Roof", V3(width + 4, 1.5, depth + 2), CF(0, height + 0.75, midZ), C_ROOF, "Roof")
	for _, lx in { -35, 35 } do
		for _, lz in { 8, 40 } do
			local panel = ctx.P(static, "CeilingLight", V3(18, 0.3, 3), CF(lx, height - 0.15, lz), RGB(255, 250, 235), NEON_DECO)
			addPointLight(panel, RGB(255, 246, 225), 40, 0.7)
		end
	end

	-- Pillars along the open front, with accent bands
	for _, px in { -67, -32, 0, 32, 67 } do
		ctx.P(static, "Pillar", V3(2, height, 2), CF(px, height / 2, B.frontZ + 1), RGB(240, 242, 246))
		ctx.A(static, "PillarBand", V3(2.2, 0.3, 2.2), CF(px, 3, B.frontZ + 1))
		ctx.A(static, "PillarBand", V3(2.2, 0.3, 2.2), CF(px, height - 3, B.frontZ + 1))
	end

	-- Yellow bay outlines in front of each bay car position
	for n = 1, #Layout.BAYS do
		local c: Vector3 = Layout.BAYS[n].car.Position
		outline(ctx, static, "BayLine", c.X, c.Z, 9, 16, 0.3, FLOOR_TOP + LINE_THICK / 2 + 0.005, C_YELLOW)
	end

	buildFascia(ctx, static)
	buildSideFacade(ctx, static)
	buildRoofTop(ctx, static)
	buildAnnexDoor(ctx, static)
end

local function buildStatic(ctx: Ctx, plot: Model): Folder
	local static = newFolder("Static", plot)
	buildOutside(ctx, static)
	buildYards(ctx, static)
	buildBuilding(ctx, static)
	buildGate(ctx, static)
	buildSafe(ctx, static)
	buildHireBoard(ctx, static)
	return static
end

------------------------------------------------------------------------------------------------
-- Plot: unlockables (one self-contained Model per unlock id)
------------------------------------------------------------------------------------------------

-- Station machine as child Model "Station", pivoted to its Layout anchor (world CFrame).
local function addStation(ctx: Ctx, model: Model, key: string, pivot: CFrame, opts: { [string]: any }?)
	local station: Model = StationModels.build(key, 1, ctx.accent, opts)
	station:PivotTo(pivot)
	station.Parent = model
end

-- Invisible anchor for the server's upgrade prompt (plot-local x, z; ~3 studs above the floor).
local function addAnchor(ctx: Ctx, model: Model, x: number, z: number)
	ctx.P(
		model,
		"UpgradeAnchor",
		V3(1, 1, 1),
		CF(x, floorTop(z) + 3, z),
		C_WHITE,
		{ Transparency = 1, CanCollide = false, CanTouch = false, CastShadow = false }
	)
end

-- Overhead sign + ceiling spot light shared by all bays.
local function buildBayOverhead(ctx: Ctx, model: Model, bayIndex: number, unlockId: string): Part
	local x: number = Layout.BAYS[bayIndex].car.Position.X
	local signZ = -12

	for _, sx in { -1, 1 } do
		ctx.P(model, "SignChain", V3(0.25, 4.8, 0.25), CF(x + sx * 5.5, 21.65, signZ), C_STEEL, { Material = METAL })
	end
	local sign = ctx.P(model, "BaySign", V3(14, 3, 0.8), CF(x, 17.8, signZ), C_DARKER)
	addSignText(sign, "SignGui", "SignLabel", unlockId, "unlock_" .. unlockId, 40)
	local strip = ctx.A(model, "BayNeon", V3(14.4, 0.3, 1.0), CF(x, 16.15, signZ))
	addPointLight(strip, ctx.accent, 14, 0.6)
	ctx.A(model, "BayNeonTop", V3(14.4, 0.2, 1.0), CF(x, 19.45, signZ))

	-- Ceiling fixture with a spot light shining on the bay
	local fz = Layout.BAYS[bayIndex].car.Position.Z
	ctx.P(model, "LampFixture", V3(3, 0.5, 3), CF(x, 23.75, fz), C_DARK)
	local lens = ctx.P(model, "LampLens", V3(2.2, 0.1, 2.2), CF(x, 23.45, fz), RGB(255, 250, 235), NEON_DECO)
	addSpotLight(lens, Enum.NormalId.Bottom, RGB(255, 246, 225), 32, 75, 2.5)
	return sign
end

-- Tool board standing behind bays 1 and 2 (bays 3/4 have tall stations there).
local function buildToolBoard(ctx: Ctx, model: Model, bayIndex: number)
	local FT = FLOOR_TOP
	local red = RGB(205, 40, 40)
	local bx: number = Layout.BAYS[bayIndex].car.Position.X
	local bz = 8
	ctx.P(model, "ToolBoard", V3(12, 6, 0.5), CF(bx, FT + 5, bz), RGB(66, 72, 84))
	ctx.A(model, "ToolBoardNeon", V3(12.2, 0.2, 0.3), CF(bx, FT + 8.1, bz - 0.1))
	for _, sx in { -4.5, 4.5 } do
		ctx.P(model, "ToolBoardLeg", V3(0.5, 2, 0.5), CF(bx + sx, FT + 1, bz), C_STEEL)
	end
	local tz = bz - 0.35
	ctx.P(model, "ToolWrench", V3(0.4, 3.4, 0.2), CF(bx - 4.2, FT + 5.2, tz), C_CHROME, CHROME_PROPS)
	ctx.P(model, "ToolWrenchHead", V3(1.1, 0.9, 0.2), CF(bx - 4.2, FT + 7.0, tz), C_CHROME, CHROME_PROPS)
	ctx.P(model, "ToolHammer", V3(0.4, 3.0, 0.2), CF(bx - 2.0, FT + 4.9, tz), RGB(150, 100, 60))
	ctx.P(model, "ToolHammerHead", V3(1.6, 0.8, 0.3), CF(bx - 2.0, FT + 6.5, tz), C_DARK)
	ctx.P(model, "ToolDriverShaft", V3(0.2, 2.2, 0.15), CF(bx + 0.2, FT + 6.0, tz), C_CHROME, CHROME_PROPS)
	ctx.P(model, "ToolDriverHandle", V3(0.6, 1.6, 0.3), CF(bx + 0.2, FT + 4.1, tz), red)
	ctx.P(model, "ToolPliers", V3(0.5, 2.6, 0.2), CF(bx + 2.3, FT + 5.0, tz) * ANG(0, 0, math.rad(12)), RGB(230, 190, 40))
	ctx.P(model, "ToolPliersHead", V3(1.0, 0.9, 0.2), CF(bx + 2.65, FT + 6.4, tz) * ANG(0, 0, math.rad(12)), C_DARK)
	ctx.C(model, "ToolTire", "Z", 0.5, 2.6, CF(bx + 4.3, FT + 4.6, tz), C_TIRE, nil)
	ctx.C(model, "ToolTireRim", "Z", 0.56, 1.2, CF(bx + 4.3, FT + 4.6, tz), C_CHROME, CHROME_PROPS)
end

local function buildBay(ctx: Ctx, parent: Folder, entry: any): Model
	local n: number = entry.bay
	local model = newModel(entry.id, parent)
	local sign = buildBayOverhead(ctx, model, n, entry.id)
	model.PrimaryPart = sign
	if n <= 2 then
		buildToolBoard(ctx, model, n)
	end
	addStation(ctx, model, entry.station, Layout.stationCFrame(ctx.index, entry.station), nil)
	-- upgrade anchor between the bay lane and the machine
	local ax: number = if n <= 2 then Layout.BAYS[n].machine.Position.X else Layout.BAYS[n].car.Position.X
	addAnchor(ctx, model, ax, -12.5)
	return model
end

local function buildCashier(ctx: Ctx, parent: Folder): Model
	local model = newModel("Cashier", parent)
	local c: CFrame = Layout.CASHIER.counter
	local cx, cz = c.Position.X, c.Position.Z
	local FT = FLOOR_TOP
	local topY = FT + 4.1 -- top surface of the counter

	local counter = ctx.P(model, "Counter", V3(14, 3.7, 3), CF(cx, FT + 1.85, cz), RGB(238, 240, 244))
	model.PrimaryPart = counter
	ctx.P(model, "CounterTop", V3(15, 0.4, 3.6), CF(cx, FT + 3.9, cz), RGB(176, 128, 84), { Material = Enum.Material.Wood })
	ctx.T(model, "CounterFront", V3(13.2, 2.2, 0.2), CF(cx, FT + 1.95, cz - 1.55))
	ctx.A(model, "CounterNeon", V3(13.2, 0.15, 0.22), CF(cx, FT + 0.85, cz - 1.56))
	ctx.A(model, "CounterNeon", V3(13.2, 0.15, 0.22), CF(cx, FT + 3.1, cz - 1.56))

	-- Register
	ctx.P(model, "Register", V3(2.6, 1.3, 2), CF(cx + 2.8, topY + 0.65, cz + 0.4), C_DARK)
	ctx.P(model, "RegisterKeys", V3(2.2, 0.15, 1.0), CF(cx + 2.8, topY + 1.37, cz + 0.1) * ANG(math.rad(-15), 0, 0), RGB(200, 204, 212))
	ctx.P(model, "RegisterDrawer", V3(2.2, 0.5, 0.1), CF(cx + 2.8, topY + 0.45, cz - 0.65), C_STEEL)

	-- Monitor with neon screen (faces the customers, -Z)
	ctx.P(model, "MonitorBase", V3(1.6, 0.2, 1.2), CF(cx - 3.2, topY + 0.1, cz + 0.4), C_DARK)
	ctx.P(model, "MonitorNeck", V3(0.35, 1.2, 0.35), CF(cx - 3.2, topY + 0.8, cz + 0.4), C_DARK)
	ctx.P(model, "MonitorBezel", V3(3.2, 2.1, 0.3), CF(cx - 3.2, topY + 2.0, cz + 0.4), C_DARKER)
	ctx.P(model, "MonitorScreen", V3(2.8, 1.7, 0.1), CF(cx - 3.2, topY + 2.0, cz + 0.2), RGB(110, 230, 255), NEON_DECO)

	-- OPEN sign
	ctx.P(model, "OpenLeg", V3(0.2, 0.7, 0.2), CF(cx + 5.8 - 1.0, topY + 0.35, cz - 0.9), C_DARK)
	ctx.P(model, "OpenLeg", V3(0.2, 0.7, 0.2), CF(cx + 5.8 + 1.0, topY + 0.35, cz - 0.9), C_DARK)
	ctx.P(model, "OpenGlow", V3(3.2, 1.3, 0.12), CF(cx + 5.8, topY + 1.35, cz - 0.9 + 0.05), RGB(70, 255, 130), NEON_DECO)
	local openPlate = ctx.P(model, "OpenSign", V3(2.9, 1.0, 0.18), CF(cx + 5.8, topY + 1.35, cz - 0.9 - 0.02), C_DARKER)
	local gui = newSurfaceGui(openPlate, "OpenGui", Enum.NormalId.Front, 60)
	local label = newLabel(gui, "OpenLabel", "OPEN", RGB(90, 255, 140), UDim2.fromScale(1, 1))
	label.Font = Enum.Font.GothamBlack

	-- Floor mat for the cashier + a small plant on the counter's far end
	ctx.P(model, "CashierMat", V3(6, 0.05, 3), CF(cx, FT + 0.025, cz + 5), RGB(60, 64, 74), DECAL)
	ctx.C(model, "CounterPlantPot", "Y", 0.9, 1.1, CF(cx - 6.2, topY + 0.45, cz), C_POT, nil)
	ctx.B(model, "CounterPlant", 1.6, CF(cx - 6.2, topY + 1.4, cz), C_LEAF, { CanCollide = false })
	return model
end

local function buildParking(ctx: Ctx, parent: Folder): Model
	local model = newModel("Parking", parent)
	for n = 4, 6 do
		parkingSpot(ctx, model, n)
	end
	-- two lamp posts in the gaps between the extra spots
	buildLampPost(ctx, model, 42, -42)
	buildLampPost(ctx, model, 54, -42)
	return model
end

local function buildReception(ctx: Ctx, parent: Folder): Model
	local model = newModel("Reception", parent)
	local d: Vector3 = Layout.RECEPTION.desk.Position
	addStation(ctx, model, "reception", Layout.toWorld(ctx.index, CF(d)), nil)
	-- rubber mat with accent border, plants flanking the desk
	ctx.P(model, "ReceptionMat", V3(10, 0.05, 7), CF(d.X, LOT_TOP + 0.03, d.Z + 2.5), RGB(54, 58, 68), DECAL)
	for _, sx in { -1, 1 } do
		ctx.A(model, "ReceptionMatEdge", V3(0.3, 0.06, 7), CF(d.X + sx * 5.15, LOT_TOP + 0.035, d.Z + 2.5))
	end
	-- plants on the far side from the shoppers' walkway (X -11)
	plant(ctx, model, d.X - 7, LOT_TOP, d.Z, 0.9)
	plant(ctx, model, d.X - 7, LOT_TOP, d.Z + 4, 0.9)
	return model
end

-- Wash, Diagnostics, EngineBench, Dyno: just the station model (+ upgrade anchor for the wash).
local function buildStationOnly(ctx: Ctx, parent: Folder, entry: any): Model
	local model = newModel(entry.id, parent)
	addStation(ctx, model, entry.station, Layout.stationCFrame(ctx.index, entry.station), nil)
	if entry.upgradable and entry.kind == "Wash" then
		local w = Layout.WASH_BUTTON
		addAnchor(ctx, model, w.X + 3, w.Z)
	end
	return model
end

local function buildShelf(ctx: Ctx, parent: Folder, entry: any): Model
	local n: number = entry.shelf
	local model = newModel(entry.id, parent)
	addStation(ctx, model, "shelf", Layout.shelfCFrame(ctx.index, n), { product = entry.product })
	local b: Vector3 = Layout.SHELVES[n].button
	addAnchor(ctx, model, b.X, b.Z)
	return model
end

------------------------------------------------------------------------------------------------
-- Office: mezzanine with stairs, glass railing, office room, manager desk, lounge
------------------------------------------------------------------------------------------------

local function monitorChart(screen: BasePart, accent: Color3)
	local gui = newSurfaceGui(screen, "ChartGui", Enum.NormalId.Front, 50)
	local title = newLabel(gui, "ChartTitle", "REVENUE", RGB(150, 190, 230), UDim2.fromScale(0.5, 0.2), UDim2.fromScale(0.05, 0.06))
	title.TextXAlignment = Enum.TextXAlignment.Left
	local pct = newLabel(gui, "ChartValue", "+128%", RGB(90, 255, 130), UDim2.fromScale(0.4, 0.24), UDim2.fromScale(0.55, 0.05))
	pct.Font = Enum.Font.GothamBlack
	local heights = { 0.2, 0.3, 0.27, 0.42, 0.55, 0.7 }
	for k, h in heights do
		local bar = Instance.new("Frame")
		bar.Name = "Bar"
		bar.BorderSizePixel = 0
		bar.BackgroundColor3 = if k == #heights then RGB(90, 255, 130) else accent
		bar.AnchorPoint = Vector2.new(0, 1)
		bar.Position = UDim2.fromScale(0.06 + (k - 1) * 0.15, 0.92)
		bar.Size = UDim2.fromScale(0.11, h)
		bar.Parent = gui
	end
end

-- Straight wall run (axis-aligned) with a solid base, one big glass pane and mullions.
local function glassWallRun(
	ctx: Ctx,
	model: Model,
	x0: number,
	z0: number,
	x1: number,
	z1: number,
	y0: number,
	baseH: number,
	glassH: number,
	panels: number
)
	local alongX = z0 == z1
	local len = if alongX then math.abs(x1 - x0) else math.abs(z1 - z0)
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	local t = 0.5
	ctx.R(model, "OfficeWallBase", if alongX then V3(len, baseH, t) else V3(t, baseH, len), CF(cx, y0 + baseH / 2, cz), C_WALL, "Wall")
	ctx.P(
		model,
		"OfficeGlass",
		if alongX then V3(len, glassH, 0.15) else V3(0.15, glassH, len),
		CF(cx, y0 + baseH + glassH / 2, cz),
		C_GLASS,
		merge(GLASS_PROPS, { Transparency = 0.4 })
	)
	for k = 1, panels - 1 do
		local f = k / panels
		local mx = if alongX then x0 + (x1 - x0) * f else cx
		local mz = if alongX then cz else z0 + (z1 - z0) * f
		ctx.P(model, "OfficeMullion", V3(0.45, glassH, 0.45), CF(mx, y0 + baseH + glassH / 2, mz), C_DARK)
	end
end

-- Glass railing run with chrome posts and top rail.
local function railingRun(ctx: Ctx, model: Model, x0: number, z0: number, x1: number, z1: number, panels: number)
	local alongX = z0 == z1
	local len = if alongX then math.abs(x1 - x0) else math.abs(z1 - z0)
	local pw = len / panels
	for k = 0, panels do
		local f = k / panels
		local px = x0 + (x1 - x0) * f
		local pz = z0 + (z1 - z0) * f
		ctx.P(model, "RailPost", V3(0.3, 3.2, 0.3), CF(px, 13.6, pz), C_CHROME, CHROME_PROPS)
		if k < panels then
			local f2 = (k + 0.5) / panels
			ctx.P(
				model,
				"RailGlass",
				if alongX then V3(pw - 0.3, 2.8, 0.15) else V3(0.15, 2.8, pw - 0.3),
				CF(x0 + (x1 - x0) * f2, 13.5, z0 + (z1 - z0) * f2),
				C_GLASS,
				GLASS_PROPS
			)
		end
	end
	ctx.P(
		model,
		"RailTop",
		if alongX then V3(len + 0.3, 0.25, 0.3) else V3(0.3, 0.25, len + 0.3),
		CF((x0 + x1) / 2, 15.2, (z0 + z1) / 2),
		C_CHROME,
		CHROME_PROPS
	)
end

local function buildStairs(ctx: Ctx, model: Model)
	local M = Layout.MEZZANINE
	local steps = 16
	local rise = (M.floorY - FLOOR_TOP) / steps -- 0.74375
	local run = (M.stairsZ1 - M.stairsZ0) / steps -- 1.5
	local sx = M.stairsX
	for k = 1, steps do
		local top = FLOOR_TOP + k * rise
		local h = top - FLOOR_TOP
		ctx.P(
			model,
			"StairStep",
			V3(6, h, run),
			CF(sx, FLOOR_TOP + h / 2, M.stairsZ0 + (k - 0.5) * run),
			RGB(196, 200, 208),
			{ Material = Enum.Material.Concrete }
		)
	end
	-- landing between the top step and the slab
	ctx.R(model, "StairLanding", V3(6, 1, 2), CF(sx, M.floorY - 0.5, M.stairsZ1 + 1), C_CONCRETE, "Floor", { Material = Enum.Material.Concrete })

	-- handrail on the open (X = stairsX - 3) side: posts every 3rd step, two sloped rails
	local rx = sx - 2.8
	local function stepPoint(k: number, up: number): Vector3
		return V3(rx, FLOOR_TOP + k * rise + up, M.stairsZ0 + (k - 0.5) * run)
	end
	for _, k in { 1, 4, 7, 10, 13, 16 } do
		local p = stepPoint(k, 1.6)
		ctx.P(model, "StairPost", V3(0.25, 3.2, 0.25), CF(p.X, p.Y, p.Z), C_CHROME, CHROME_PROPS)
	end
	for _, up in { 3.2, 1.7 } do
		local a, b = stepPoint(1, up), stepPoint(steps, up)
		local mid = (a + b) / 2
		ctx.P(
			model,
			"StairRail",
			V3(0.28, 0.28, (b - a).Magnitude),
			CFrame.lookAt(mid, b),
			C_CHROME,
			CHROME_PROPS
		)
	end
	-- sloped accent strip along the nosing
	local a, b = stepPoint(1, 0.05), stepPoint(steps, 0.05)
	local mid = (a + b) / 2
	local strip = newPart("StairNeon", V3(0.2, 0.2, (b - a).Magnitude), Layout.toWorld(ctx.index, CFrame.lookAt(mid, b)), ctx.accent, NEON_DECO, model)
	tag(strip, "Accent")
end

local function buildDesk(ctx: Ctx, model: Model)
	local dx, dz = Layout.OFFICE.desk.Position.X, Layout.OFFICE.desk.Position.Z
	local fy = Layout.MEZZANINE.floorY
	local dark = RGB(54, 58, 68)
	-- desk
	ctx.P(model, "DeskTop", V3(8, 0.4, 3), CF(dx, fy + 2.8, dz), RGB(104, 74, 52), { Material = Enum.Material.Wood })
	for _, sx in { -3.8, 3.8 } do
		ctx.P(model, "DeskSide", V3(0.4, 2.6, 3), CF(dx + sx, fy + 1.3, dz), dark)
	end
	ctx.P(model, "DeskFront", V3(7.2, 2.0, 0.3), CF(dx, fy + 1.7, dz - 1.2), dark)
	ctx.A(model, "DeskNeon", V3(8.1, 0.15, 0.1), CF(dx, fy + 2.7, dz - 1.55))
	-- monitor with a chart (faces -Z toward visitors)
	ctx.P(model, "MonitorBase", V3(1.2, 0.15, 1.0), CF(dx - 1.5, fy + 3.075, dz + 0.2), C_DARK)
	ctx.P(model, "MonitorNeck", V3(0.3, 1.0, 0.3), CF(dx - 1.5, fy + 3.65, dz + 0.3), C_DARK)
	ctx.P(model, "MonitorBezel", V3(3.8, 2.4, 0.25), CF(dx - 1.5, fy + 4.9, dz + 0.3), C_DARKER)
	local screen = ctx.P(model, "MonitorScreen", V3(3.5, 2.1, 0.1), CF(dx - 1.5, fy + 4.9, dz + 0.14), RGB(12, 20, 40))
	monitorChart(screen, ctx.accent)
	ctx.P(model, "Keyboard", V3(2.2, 0.1, 0.8), CF(dx - 1.5, fy + 3.05, dz - 0.5), C_DARK)
	-- papers + mug
	ctx.P(model, "Papers", V3(1.4, 0.06, 1.9), CF(dx + 2.4, fy + 3.03, dz - 0.2) * ANG(0, math.rad(12), 0), C_WHITE)
	ctx.C(model, "Mug", "Y", 0.6, 0.55, CF(dx + 3.2, fy + 3.3, dz + 0.5), ctx.accent, nil)
	-- chair (pulled out a little, the manager stands behind the desk)
	local cb = CF(dx - 2.8, fy, dz + 4.4) * ANG(0, math.rad(25), 0)
	ctx.C(model, "ChairBase", "Y", 0.25, 2.2, cb * CF(0, 0.2, 0), C_CHROME, CHROME_PROPS)
	ctx.C(model, "ChairPost", "Y", 1.4, 0.35, cb * CF(0, 0.9, 0), C_STEEL, nil)
	ctx.P(model, "ChairSeat", V3(2.4, 0.5, 2.4), cb * CF(0, 1.8, 0), RGB(36, 40, 50))
	ctx.P(model, "ChairBack", V3(2.4, 2.8, 0.4), cb * CF(0, 3.4, 1.1), RGB(36, 40, 50))
	ctx.T(model, "ChairStripe", V3(0.5, 2.2, 0.1), cb * CF(0, 3.4, 0.85))
end

local function buildTrophyShelf(ctx: Ctx, model: Model, cx: number)
	local fy = Layout.MEZZANINE.floorY
	local z = Layout.BUILDING.backZ - 2 -- inner face of the back wall
	local gold: Props = { Material = METAL, Reflectance = 0.3 }
	local goldC = RGB(255, 200, 40)
	for _, sx in { -3.1, 3.1 } do
		ctx.P(model, "TrophyUpright", V3(0.3, 6.4, 1.4), CF(cx + sx, fy + 3.2, z - 0.7), RGB(70, 76, 90))
	end
	ctx.P(model, "TrophyBack", V3(6.2, 6, 0.15), CF(cx, fy + 3.2, z - 0.08), RGB(40, 44, 54))
	for _, by in { 2.0, 4.0, 6.0 } do
		ctx.P(model, "TrophyBoard", V3(6.2, 0.25, 1.4), CF(cx, fy + by, z - 0.7), RGB(70, 76, 90))
	end
	local spots: { any } = { { -1.6, 4.0, 1.0 }, { 1.4, 4.0, 0.8 }, { -0.4, 6.0, 1.2 }, { 1.8, 2.0, 0.9 } }
	for _, s in spots do
		local tx: number, ty: number, ts: number = s[1], s[2], s[3]
		ctx.P(model, "TrophyBase", V3(0.8 * ts, 0.3, 0.8 * ts), CF(cx + tx, fy + ty + 0.275, z - 0.7), C_DARK)
		ctx.C(model, "TrophyStem", "Y", 0.7 * ts, 0.3, CF(cx + tx, fy + ty + 0.775, z - 0.7), goldC, gold)
		ctx.C(model, "TrophyCup", "Y", 0.9 * ts, 0.9 * ts, CF(cx + tx, fy + ty + 1.55 * ts, z - 0.7), goldC, gold)
	end
end

local function buildLounge(ctx: Ctx, model: Model)
	local fy = Layout.MEZZANINE.floorY
	local fabric = RGB(84, 92, 108)
	ctx.P(model, "LoungeRug", V3(7, 0.05, 8), CF(63, fy + 0.03, 52.5), RGB(70, 80, 100), DECAL)
	ctx.P(model, "SofaSeat", V3(2.8, 1.0, 6), CF(65.8, fy + 1.0, 52.5), fabric)
	ctx.P(model, "SofaBack", V3(0.7, 2.6, 6.8), CF(67.35, fy + 2.0, 52.5), fabric)
	for _, sz in { -3.2, 3.2 } do
		ctx.P(model, "SofaArm", V3(2.8, 1.8, 0.7), CF(65.8, fy + 1.4, 52.5 + sz), fabric)
	end
	for _, sz in { -1.5, 1.5 } do
		ctx.T(model, "SofaCushion", V3(2.0, 0.4, 2.6), CF(65.6, fy + 1.7, 52.5 + sz))
	end
	ctx.P(model, "CoffeeTable", V3(2, 0.25, 3.4), CF(61.8, fy + 1.55, 52.5), RGB(120, 90, 64), { Material = Enum.Material.Wood })
	for _, lz in { -1.3, 1.3 } do
		ctx.P(model, "CoffeeTableLeg", V3(1.6, 1.4, 0.25), CF(61.8, fy + 0.7, 52.5 + lz), C_DARK)
	end
	plant(ctx, model, 60, fy, 56.6, 1.2)
end

local function buildOffice(ctx: Ctx, parent: Folder): Model
	local M = Layout.MEZZANINE
	local fy = M.floorY
	local model = newModel("Office", parent)
	local w = M.maxX - M.minX -- 44
	local d = M.maxZ - M.minZ -- 28
	local cx, cz = (M.minX + M.maxX) / 2, (M.minZ + M.maxZ) / 2

	-- slab (top at floorY) with accent edge strips on the open edges
	local slab = ctx.R(model, "MezzSlab", V3(w, 1, d), CF(cx, fy - 0.5, cz), C_CONCRETE, "Floor", { Material = Enum.Material.Concrete })
	model.PrimaryPart = slab
	ctx.A(model, "MezzEdgeFront", V3(38, 0.3, 0.24), CF(43, fy - 0.5, M.minZ - 0.12))
	ctx.A(model, "MezzEdgeLeft", V3(0.24, 0.3, d), CF(M.minX - 0.12, fy - 0.5, cz))
	for _, lz in { 38, 52 } do
		local strip = ctx.P(model, "MezzUnderLight", V3(30, 0.15, 0.6), CF(46, fy - 1.07, lz), RGB(255, 246, 225), NEON_DECO)
		addPointLight(strip, RGB(255, 240, 215), 22, 0.7)
	end

	-- columns at the open corners / edges
	for _, c in { { 25, 31 }, { 43.5, 31 }, { 25, 44.5 }, { 25, 57 } } do
		local colH = fy - 1 - FLOOR_TOP
		ctx.C(model, "MezzColumn", "Y", colH, 1.2, CF(c[1], FLOOR_TOP + colH / 2, c[2]), RGB(230, 232, 238), nil)
		local band = ctx.C(model, "MezzColumnBand", "Y", 0.3, 1.4, CF(c[1], 3, c[2]), ctx.accent, NEON_DECO)
		tag(band, "Accent")
	end

	-- glass railing: front edge, left edge and the landing side
	railingRun(ctx, model, M.minX, M.minZ + 0.15, 62, M.minZ + 0.15, 6)
	railingRun(ctx, model, M.minX + 0.15, M.minZ, M.minX + 0.15, M.maxZ, 4)
	railingRun(ctx, model, 62.1, M.stairsZ1, 62.1, M.minZ, 1)

	buildStairs(ctx, model)

	-- office room X 26..58, Z 34..58: glass walls on the front, west and east, ceiling at Y 21
	local ox0, ox1, oz0, oz1 = 26, 58, 34, 58
	glassWallRun(ctx, model, ox0, oz0, 53, oz0, fy, 1.2, 7.2, 4) -- front (door gap X 53..58)
	glassWallRun(ctx, model, ox0, oz0, ox0, oz1, fy, 1.2, 7.2, 4) -- west
	glassWallRun(ctx, model, ox1, oz0, ox1, oz1, fy, 1.2, 7.2, 4) -- east
	ctx.R(model, "OfficeBeam", V3(32, 1, 0.5), CF(42, fy + 8.9, oz0), C_WALL, "Wall")
	ctx.R(model, "OfficeBeam", V3(0.5, 1, 24), CF(ox0, fy + 8.9, 46), C_WALL, "Wall")
	ctx.R(model, "OfficeBeam", V3(0.5, 1, 24), CF(ox1, fy + 8.9, 46), C_WALL, "Wall")
	ctx.A(model, "OfficeBeamNeon", V3(32, 0.2, 0.1), CF(42, fy + 8.9, oz0 - 0.3))
	ctx.T(model, "OfficeDoorJamb", V3(0.5, 8.4, 0.7), CF(53, fy + 4.2, oz0))
	ctx.R(model, "OfficeCeiling", V3(32, 0.4, 24), CF(42, fy + 9.2, 46), C_WALL, "Wall")
	ctx.P(model, "OfficeCarpet", V3(32, 0.08, 24), CF(42, fy + 0.02, 46), RGB(52, 74, 92), { CanCollide = false })
	for _, lz in { 40, 50 } do
		local panel = ctx.P(model, "OfficeLight", V3(8, 0.2, 1.4), CF(46, fy + 8.9, lz), RGB(255, 250, 235), NEON_DECO)
		addPointLight(panel, RGB(255, 246, 225), 24, 0.8)
	end

	-- manager desk corner
	buildDesk(ctx, model)
	local sign = ctx.P(model, "ManagerSign", V3(10, 2.4, 0.3), CF(46, fy + 7, Layout.BUILDING.backZ - 2.15), C_DARKER)
	addScreenText(sign, "ManagerGui", "MANAGER", RGB(255, 255, 255), 40)
	for _, dy in { -1.4, 1.4 } do
		ctx.A(model, "ManagerNeon", V3(10.4, 0.2, 0.4), CF(46, fy + 7 + dy, Layout.BUILDING.backZ - 2.2))
	end
	for _, sx in { -5.1, 5.1 } do
		ctx.A(model, "ManagerNeon", V3(0.2, 2.8, 0.4), CF(46 + sx, fy + 7, Layout.BUILDING.backZ - 2.2))
	end
	buildTrophyShelf(ctx, model, 54)
	plant(ctx, model, 29, fy, 55, 1.4)
	ctx.P(model, "FilingCabinet", V3(2, 3.6, 2.2), CF(31.5, fy + 1.8, 56.5), RGB(150, 156, 168), { Material = METAL })
	for _, hy in { 1.3, 2.5 } do
		ctx.P(model, "FilingHandle", V3(1.0, 0.15, 0.1), CF(31.5, fy + hy, 55.35), C_DARK)
	end

	buildLounge(ctx, model)
	return model
end

------------------------------------------------------------------------------------------------
-- TuningRoom: annex behind the back wall with a showroom turntable
------------------------------------------------------------------------------------------------

local function buildTerminal(ctx: Ctx, model: Model)
	local t: Vector3 = Layout.TUNING.terminal
	local body = ctx.P(
		model,
		"TuningTerminal",
		V3(3.4, 4, 1.4),
		CF(t.X, FLOOR_TOP + 2, t.Z),
		RGB(22, 26, 36),
		{ Material = METAL, Reflectance = 0.15 }
	)
	local gui = newSurfaceGui(body, "TerminalGui", Enum.NormalId.Front, 50)
	local bg = Instance.new("Frame")
	bg.Name = "Screen"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = RGB(10, 16, 30)
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local title = newLabel(bg, "Title", "TUNING", RGB(255, 255, 255), UDim2.fromScale(0.84, 0.2), UDim2.fromScale(0.08, 0.1))
	title.Font = Enum.Font.GothamBlack
	local line = Instance.new("Frame")
	line.Name = "Line"
	line.BorderSizePixel = 0
	line.BackgroundColor3 = ctx.accent
	line.Position = UDim2.fromScale(0.08, 0.33)
	line.Size = UDim2.fromScale(0.84, 0.015)
	line.Parent = bg
	local sub = newLabel(bg, "Sub", "CUSTOMIZE", RGB(150, 190, 230), UDim2.fromScale(0.7, 0.08), UDim2.fromScale(0.15, 0.4))
	sub.Font = Enum.Font.GothamBold
	for k = 0, 2 do
		local chip = Instance.new("Frame")
		chip.Name = "Chip"
		chip.BorderSizePixel = 0
		chip.BackgroundColor3 = if k == 0 then ctx.accent else RGB(60, 72, 100)
		chip.Position = UDim2.fromScale(0.08 + k * 0.3, 0.56)
		chip.Size = UDim2.fromScale(0.24, 0.26)
		chip.Parent = bg
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.2, 0)
		corner.Parent = chip
	end
	ctx.P(model, "TerminalPlinth", V3(4.2, 0.4, 2.4), CF(t.X, FLOOR_TOP + 0.2, t.Z), C_DARK)
	ctx.P(model, "TerminalCap", V3(3.8, 0.4, 1.8), CF(t.X, FLOOR_TOP + 4.2, t.Z), C_DARK, { Material = METAL })
	for _, sx in { -1.65, 1.65 } do
		ctx.A(model, "TerminalEdge", V3(0.15, 3.6, 0.1), CF(t.X + sx, FLOOR_TOP + 2, t.Z - 0.75))
	end
	local pad = ctx.A(model, "TerminalPad", V3(5, 0.05, 3.4), CF(t.X, FLOOR_TOP + 0.03, t.Z - 2.2))
	addPointLight(pad, ctx.accent, 10, 0.7)
end

local function buildPoster(ctx: Ctx, model: Model, x: number, kind: string, backFaceZ: number)
	local y = 10
	ctx.P(model, "PosterFrame", V3(6.4, 6.4, 0.2), CF(x, y, backFaceZ - 0.1), C_DARKER)
	local plate = ctx.P(model, "PosterPlate", V3(6, 6, 0.1), CF(x, y, backFaceZ - 0.25), RGB(30, 36, 50))
	if kind == "text" then
		local gui = newSurfaceGui(plate, "PosterGui", Enum.NormalId.Front, 40)
		local l1 = newLabel(gui, "Line1", "TUNE", RGB(255, 255, 255), UDim2.fromScale(0.9, 0.3), UDim2.fromScale(0.05, 0.14))
		l1.Font = Enum.Font.GothamBlack
		local l2 = newLabel(gui, "Line2", "YOUR RIDE", ctx.accent, UDim2.fromScale(0.9, 0.2), UDim2.fromScale(0.05, 0.5))
		l2.Font = Enum.Font.GothamBlack
	else
		ctx.C(model, "PosterRim", "Z", 0.08, 4.4, CF(x, y, backFaceZ - 0.34), C_CHROME, CHROME_PROPS)
		local hub = ctx.C(model, "PosterHub", "Z", 0.1, 1.5, CF(x, y, backFaceZ - 0.4), ctx.accent, NEON_DECO)
		tag(hub, "Accent")
	end
end

local function buildRimRack(ctx: Ctx, model: Model, wallX: number)
	-- wallX = inner face of the left wall; rims face +X
	ctx.P(model, "RimRackPanel", V3(0.3, 8, 12), CF(wallX + 0.15, 7.5, 92), RGB(36, 42, 56))
	for _, ry in { 5.5, 9.5 } do
		for _, rz in { 89.5, 94.5 } do
			ctx.C(model, "RimTire", "X", 0.3, 4.0, CF(wallX + 0.45, ry, rz), C_TIRE, nil)
			ctx.C(model, "RimDisc", "X", 0.3, 2.8, CF(wallX + 0.7, ry, rz), C_CHROME, { Material = METAL, Reflectance = 0.5 })
			local hub = ctx.C(model, "RimHub", "X", 0.3, 0.9, CF(wallX + 0.9, ry, rz), ctx.accent, NEON_DECO)
			tag(hub, "Accent")
		end
	end
	for _, ry in { 3.25, 11.75 } do
		ctx.P(model, "RimShelf", V3(1.0, 0.25, 11), CF(wallX + 0.5, ry, 92), C_STEEL, { Material = METAL })
	end
end

local function buildToolWall(ctx: Ctx, model: Model, wallX: number)
	-- wallX = inner face of the right wall; tools face -X
	local px = wallX - 0.15
	ctx.P(model, "ToolWallPanel", V3(0.3, 7, 12), CF(px, 8, 92), RGB(66, 72, 84))
	ctx.A(model, "ToolWallNeon", V3(0.2, 0.2, 12.4), CF(px - 0.1, 11.6, 92))
	local tx = px - 0.25
	ctx.P(model, "ToolWrench", V3(0.2, 3.4, 0.4), CF(tx, 8.4, 88.5), C_CHROME, CHROME_PROPS)
	ctx.P(model, "ToolWrenchHead", V3(0.2, 0.9, 1.1), CF(tx, 10.3, 88.5), C_CHROME, CHROME_PROPS)
	ctx.P(model, "ToolHammer", V3(0.2, 3.0, 0.4), CF(tx, 8.2, 91), RGB(150, 100, 60))
	ctx.P(model, "ToolHammerHead", V3(0.3, 0.8, 1.6), CF(tx, 9.9, 91), C_DARK)
	ctx.P(model, "ToolPliers", V3(0.2, 2.6, 0.5), CF(tx, 8.2, 93.5) * ANG(math.rad(12), 0, 0), RGB(230, 190, 40))
	ctx.C(model, "ToolTire", "X", 0.4, 2.8, CF(tx, 8.0, 96), C_TIRE, nil)
	-- red tool chest in front of the wall
	ctx.P(model, "ToolChest", V3(2.2, 3.5, 5), CF(wallX - 1.1 - 0.4, FLOOR_TOP + 1.75, 92), RGB(205, 40, 40), { Reflectance = 0.1 })
	ctx.P(model, "ToolChestTop", V3(2.4, 0.2, 5.2), CF(wallX - 1.1 - 0.4, FLOOR_TOP + 3.6, 92), C_DARK)
	for _, hy in { 0.9, 1.8, 2.7 } do
		ctx.P(model, "ToolChestHandle", V3(0.1, 0.2, 2.4), CF(wallX - 2.2 - 0.45, FLOOR_TOP + hy, 92), C_CHROME, CHROME_PROPS)
	end
end

local function buildTuningRoom(ctx: Ctx, parent: Folder): Model
	local A = Layout.ANNEX
	local model = newModel("TuningRoom", parent)
	local w = A.maxX - A.minX -- 60
	local d = A.maxZ - A.minZ -- 44
	local cx, cz = (A.minX + A.maxX) / 2, (A.minZ + A.maxZ) / 2
	local h = A.height
	local wallH = h - FLOOR_TOP
	local tt: Vector3 = Layout.TUNING.turntable.Position
	local rad: number = Layout.TUNING.turntableRadius

	-- floor
	local floor = ctx.R(model, "AnnexFloor", V3(w, 0.4, d), CF(cx, FLOOR_TOP - 0.2, cz), RGB(58, 62, 74), "Floor", { Reflectance = 0.12 })
	model.PrimaryPart = floor

	-- checkered accent around the turntable (light tiles on the dark floor)
	for i = -2, 2 do
		for j = -2, 2 do
			if (i + j) % 2 == 0 then
				ctx.P(model, "CheckerTile", V3(5, 0.02, 5), CF(tt.X + i * 5, FLOOR_TOP + 0.01, tt.Z + j * 5), RGB(220, 224, 232), DECAL)
			end
		end
	end

	-- turntable (top at Y 0.6) with a neon ring
	ctx.C(model, "Turntable", "Y", 0.5, rad * 2, CF(tt.X, 0.35, tt.Z), RGB(38, 42, 54), { Material = METAL, Reflectance = 0.25 })
	local ring = ctx.C(model, "TurntableRing", "Y", 0.3, rad * 2 + 1.8, CF(tt.X, 0.25, tt.Z), ctx.accent, NEON_DECO)
	tag(ring, "Accent")
	addPointLight(ring, ctx.accent, 24, 0.9)

	-- walls (the front wall is the garage's back wall)
	ctx.R(model, "AnnexWall", V3(1, wallH, d), CF(A.minX + 0.5, FLOOR_TOP + wallH / 2, cz), C_WALL, "Wall")
	ctx.R(model, "AnnexWall", V3(1, wallH, d), CF(A.maxX - 0.5, FLOOR_TOP + wallH / 2, cz), C_WALL, "Wall")
	ctx.R(model, "AnnexWall", V3(w, wallH, 1), CF(cx, FLOOR_TOP + wallH / 2, A.maxZ - 0.5), C_WALL, "Wall")
	local innerBack = A.maxZ - 1
	for _, sx in { -1, 1 } do
		local ix = sx * (A.maxX - 1)
		ctx.R(model, "AnnexStripe", V3(0.2, 3, d), CF(ix - sx * 0.1, 4, cz), ctx.accent, "Stripe")
		ctx.A(model, "AnnexStripeNeon", V3(0.25, 0.3, d), CF(ix - sx * 0.125, 5.9, cz))
	end
	ctx.R(model, "AnnexStripe", V3(w - 2, 3, 0.2), CF(cx, 4, innerBack - 0.1), ctx.accent, "Stripe")
	ctx.A(model, "AnnexStripeNeon", V3(w - 2, 0.3, 0.25), CF(cx, 5.9, innerBack - 0.125))

	-- roof with two skylights
	local roofY = h + 0.4
	for _, rx in { -23.5, 23.5 } do
		ctx.R(model, "AnnexRoof", V3(13, 0.8, d), CF(rx, roofY, cz), C_ROOF, "Roof")
	end
	ctx.R(model, "AnnexRoof", V3(14, 0.8, d), CF(0, roofY, cz), C_ROOF, "Roof")
	for _, sx in { -12, 12 } do
		ctx.R(model, "AnnexRoof", V3(10, 0.8, 6), CF(sx, roofY, A.minZ + 3), C_ROOF, "Roof")
		ctx.R(model, "AnnexRoof", V3(10, 0.8, 6), CF(sx, roofY, A.maxZ - 3), C_ROOF, "Roof")
		ctx.P(model, "SkylightGlass", V3(10, 0.2, 32), CF(sx, roofY, cz), RGB(160, 215, 240), merge(GLASS_PROPS, { Transparency = 0.35 }))
		for _, bz in { cz - 8, cz + 8 } do
			ctx.P(model, "SkylightBar", V3(10, 0.3, 0.3), CF(sx, roofY, bz), C_CHROME, CHROME_PROPS)
		end
	end
	-- accent parapet around the exterior edges of the roof
	ctx.T(model, "AnnexParapet", V3(1.2, 1, d + 0.6), CF(A.minX, h + 1.3, cz))
	ctx.T(model, "AnnexParapet", V3(1.2, 1, d + 0.6), CF(A.maxX, h + 1.3, cz))
	ctx.T(model, "AnnexParapet", V3(w + 1.2, 1, 1.2), CF(cx, h + 1.3, A.maxZ))

	-- ceiling light strips under the side roof bands
	for _, lx in { -23.5, 23.5 } do
		local strip = ctx.P(model, "AnnexCeilingLight", V3(0.6, 0.15, 36), CF(lx, h - 0.1, cz), RGB(255, 248, 232), NEON_DECO)
		addPointLight(strip, RGB(255, 244, 225), 30, 0.7)
	end

	-- showroom spotlights aimed at the turntable
	local target = V3(tt.X, 0.6, tt.Z)
	local spots: { Vector3 } = {
		V3(-22, 14.9, 72),
		V3(22, 14.9, 72),
		V3(-22, 14.9, 96),
		V3(22, 14.9, 96),
		V3(0, 14.9, 66),
		V3(0, 14.9, 100),
	}
	for _, sp in spots do
		local aim = CFrame.lookAt(sp, target)
		ctx.P(model, "SpotCan", V3(1.4, 1.4, 2.2), aim, C_DARKER, { Material = METAL })
		local lens = ctx.P(model, "SpotLens", V3(1.1, 1.1, 0.2), aim * CF(0, 0, -1.15), RGB(255, 250, 235), NEON_DECO)
		addSpotLight(lens, Enum.NormalId.Front, RGB(255, 248, 232), 52, 50, 3.2)
	end

	-- terminal, posters, rim rack, tool wall
	buildTerminal(ctx, model)
	buildPoster(ctx, model, -16, "rim", innerBack)
	buildPoster(ctx, model, 0, "text", innerBack)
	buildPoster(ctx, model, 16, "rim", innerBack)
	buildRimRack(ctx, model, A.minX + 1)
	buildToolWall(ctx, model, A.maxX - 1)

	-- exterior TUNING signs (back wall faces +Z, side walls face outward)
	local back = ctx.P(model, "AnnexSignBack", V3(18, 4, 0.5), CF(cx, 11, A.maxZ + 0.25), C_DARKER)
	addSignText(back, "SignGui", "Text", "TUNING", nil, 40, Enum.NormalId.Back)
	for _, dy in { -2.2, 2.2 } do
		local n = ctx.A(model, "AnnexSignNeon", V3(18.6, 0.25, 0.3), CF(cx, 11 + dy, A.maxZ + 0.3))
		if dy > 0 then
			addPointLight(n, ctx.accent, 26, 1, true)
		end
	end
	for _, sx in { -1, 1 } do
		local plate = ctx.P(model, "AnnexSignSide", V3(0.5, 4, 14), CF(sx * (A.maxX + 0.25), 11, cz), C_DARKER)
		addSignText(plate, "SignGui", "Text", "TUNING", nil, 40, if sx > 0 then Enum.NormalId.Right else Enum.NormalId.Left)
		for _, dy in { -2.2, 2.2 } do
			ctx.A(model, "AnnexSignNeon", V3(0.3, 0.25, 14.6), CF(sx * (A.maxX + 0.3), 11 + dy, cz))
		end
	end
	return model
end

------------------------------------------------------------------------------------------------
-- Plot: unlockables dispatcher
------------------------------------------------------------------------------------------------

local function buildUnlockables(ctx: Ctx, plot: Model)
	local folder = newFolder("Unlockables", plot)
	for _, u in Unlocks.list do
		local kind: string = u.kind
		if kind == "Bay" then
			buildBay(ctx, folder, u)
		elseif kind == "Cashier" then
			buildCashier(ctx, folder)
		elseif kind == "Shelf" then
			buildShelf(ctx, folder, u)
		elseif kind == "Parking" then
			buildParking(ctx, folder)
		elseif kind == "Reception" then
			buildReception(ctx, folder)
		elseif kind == "Wash" or kind == "Addon" then
			buildStationOnly(ctx, folder, u)
		elseif kind == "Office" then
			buildOffice(ctx, folder)
		elseif kind == "TuningRoom" then
			buildTuningRoom(ctx, folder)
		else
			warn("[MapBuilder] unknown unlock kind " .. tostring(kind) .. " for " .. tostring(u.id))
		end
	end
end

------------------------------------------------------------------------------------------------
-- Plot: unlock buttons
------------------------------------------------------------------------------------------------

local ADDON_BUTTONS: { [string]: Vector3 } = {
	Diagnostics = Layout.DIAGNOSTICS_BUTTON,
	EngineBench = Layout.ENGINE_BUTTON,
	Dyno = Layout.DYNO_BUTTON,
}

local function buttonPosition(u: any): Vector3?
	local kind: string = u.kind
	if kind == "Bay" then
		return Layout.BAYS[u.bay].button
	elseif kind == "Cashier" then
		return Layout.CASHIER.button
	elseif kind == "Shelf" then
		return Layout.SHELVES[u.shelf].button
	elseif kind == "Parking" then
		return Layout.PARKING_BUTTON
	elseif kind == "Reception" then
		return Layout.RECEPTION.button
	elseif kind == "Wash" then
		return Layout.WASH_BUTTON
	elseif kind == "Addon" then
		return ADDON_BUTTONS[u.id]
	elseif kind == "Office" then
		return Layout.OFFICE.button
	elseif kind == "TuningRoom" then
		return Layout.TUNING.button
	end
	return nil
end

local function buildButtons(ctx: Ctx, plot: Model)
	local accent = ctx.accent
	local folder = newFolder("Buttons", plot)
	for _, u in Unlocks.list do
		if not u.startOwned then
			local pos = buttonPosition(u)
			if pos then
				local y = floorTop(pos.Z) + 0.5
				local btn = ctx.P(
					folder,
					u.id,
					V3(8, 1, 8),
					CF(pos.X, y, pos.Z),
					accent,
					{ Material = NEON, Transparency = 0.15, CanCollide = false, CastShadow = false }
				)
				tag(btn, "Accent")
				addPointLight(btn, accent, 14, 0.8)

				local gui = Instance.new("BillboardGui")
				gui.Name = "PriceGui"
				gui.Adornee = btn
				gui.StudsOffset = V3(0, 4, 0)
				gui.Size = UDim2.new(0, 200, 0, 80)
				gui.MaxDistance = 60
				gui.AlwaysOnTop = false
				gui.LightInfluence = 0
				gui.Parent = btn

				local backing = Instance.new("Frame")
				backing.Name = "Backing"
				backing.Size = UDim2.fromScale(1, 1)
				backing.BackgroundColor3 = RGB(12, 16, 28)
				backing.BackgroundTransparency = 0.35
				backing.BorderSizePixel = 0
				backing.ZIndex = 1
				backing.Parent = gui
				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(0, 14)
				corner.Parent = backing
				addStroke(backing, 3, accent)

				local nameLabel = newLabel(
					gui,
					"NameLabel",
					u.id,
					RGB(255, 255, 255),
					UDim2.new(1, -20, 0.44, 0),
					UDim2.new(0, 10, 0, 4)
				)
				nameLabel.ZIndex = 2
				nameLabel:SetAttribute("TextKey", "unlock_" .. u.id)
				addStroke(nameLabel, 2, Color3.new(0, 0, 0))

				local priceLabel = newLabel(
					gui,
					"PriceLabel",
					Format.money(u.price),
					RGB(90, 255, 110),
					UDim2.new(1, -20, 0.44, 0),
					UDim2.new(0, 10, 0.52, 0)
				)
				priceLabel.Font = Enum.Font.GothamBlack
				priceLabel.ZIndex = 2
				addStroke(priceLabel, 2, Color3.new(0, 0, 0))
			end
		end
	end
end

------------------------------------------------------------------------------------------------
-- Plot assembly
------------------------------------------------------------------------------------------------

local plots: { [number]: Model } = {}
local built = false

local function buildPlot(i: number, plotsFolder: Folder): Model
	local ctx = makeCtx(i)
	local plot = Instance.new("Model")
	plot.Name = "Plot" .. i
	plot:SetAttribute("PlotIndex", i)
	plot:SetAttribute("OwnerUserId", 0)

	buildStatic(ctx, plot)
	buildUnlockables(ctx, plot)
	buildButtons(ctx, plot)

	plot.Parent = plotsFolder
	return plot
end

function MapBuilder.build()
	if built then
		return
	end
	built = true

	buildWorld()

	local plotsFolder = newFolder("Plots", Workspace)
	for i = 1, Layout.PLOT_COUNT do
		plots[i] = buildPlot(i, plotsFolder)
	end
end

function MapBuilder.getPlot(i: number): Model
	return plots[i]
end

function MapBuilder.init()
	MapBuilder.build()
end

return MapBuilder
