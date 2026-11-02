--!strict
-- Builds the whole 3D world from Parts: ring road, center island + fountain, 4 garage plots.
-- Names follow docs/CONTRACT.md section 4. All geometry comes from Layout.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Layout = require(Shared:WaitForChild("Layout") :: ModuleScript)
local Format = require(Shared:WaitForChild("Format") :: ModuleScript)
local Unlocks: any = require((Shared:WaitForChild("Config") :: Folder):WaitForChild("Unlocks") :: ModuleScript)

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

local NEON = Enum.Material.Neon
local METAL = Enum.Material.Metal

-- Heights of the stacked flat layers (avoid z-fighting).
local ROAD_TOP = 0.05
local LOT_TOP = 0.06
local FLOOR_TOP = 0.1
local LINE_THICK = 0.04

-- Props for flat decals / thin decorations.
local DECAL: Props = { CanCollide = false, CanTouch = false, CastShadow = false }
local NEON_DECO: Props = { Material = NEON, CanCollide = false, CanTouch = false, CastShadow = false }

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

-- World-space cylinder: length along `axis`, diameter across.
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

local function addPointLight(parent: Instance, color: Color3, range: number, brightness: number): PointLight
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
	return l
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

-- Adds a front-facing (-Z) text GUI to a part. Returns the label.
local function addSignText(part: BasePart, guiName: string, labelName: string, text: string, textKey: string?, ppu: number): TextLabel
	local gui = newSurfaceGui(part, guiName, Enum.NormalId.Front, ppu)
	local label = newLabel(gui, labelName, text, RGB(255, 255, 255), UDim2.fromScale(1, 1))
	label.Font = Enum.Font.GothamBlack
	addStroke(label, 3, Color3.new(0, 0, 0))
	if textKey then
		label:SetAttribute("TextKey", textKey)
	end
	return label
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
}

local function makeCtx(i: number): Ctx
	local ctx: Ctx = {
		index = i,
		accent = ACCENTS[i],
		P = function(parent, name, size, cf, color, props)
			return newPart(name, size, Layout.toWorld(i, cf), color, props, parent)
		end,
		C = function(parent, name, axis, length, diameter, cf, color, props)
			return worldCylinder(parent, name, axis, length, diameter, Layout.toWorld(i, cf), color, props)
		end,
	}
	return ctx
end

------------------------------------------------------------------------------------------------
-- World: ground, ring road, island, fountain, decoration
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
		if math.abs(l.X) < 84 and l.Z > -132 and l.Z < 74 then
			return true
		end
	end
	return false
end

local function buildTree(parent: Instance, pos: Vector3, scale: number, rng: Random)
	local m = newModel("Tree", parent)
	local base = CF(pos) * ANG(0, rng:NextNumber(0, TWO_PI), 0)
	local s = scale
	newPart("Trunk", V3(1.3 * s, 4.6 * s, 1.3 * s), base * CF(0, 2.3 * s, 0), RGB(112, 76, 46), nil, m)
	local greens = { RGB(72, 160, 72), RGB(60, 140, 62), RGB(88, 176, 78) }
	local leaf: Props = { CanCollide = false }
	newPart("Leaves", V3(6.4 * s, 3.6 * s, 6.4 * s), base * CF(0, 5.6 * s, 0), greens[rng:NextInteger(1, 3)], leaf, m)
	newPart(
		"Leaves",
		V3(4.8 * s, 3.4 * s, 4.8 * s),
		base * CF(0, 8.4 * s, 0) * ANG(0, math.rad(30), 0),
		greens[rng:NextInteger(1, 3)],
		leaf,
		m
	)
	newPart(
		"Leaves",
		V3(3.0 * s, 2.8 * s, 3.0 * s),
		base * CF(0, 10.8 * s, 0) * ANG(0, math.rad(15), 0),
		greens[rng:NextInteger(1, 3)],
		leaf,
		m
	)
end

local function buildLamp(parent: Instance, pos: Vector3)
	local m = newModel("Lamp", parent)
	local base = CF(pos)
	newPart("LampBase", V3(1.4, 0.6, 1.4), base * CF(0, 0.3, 0), C_DARK, nil, m)
	worldCylinder(m, "LampPole", "Y", 11.4, 0.5, base * CF(0, 6.3, 0), RGB(60, 66, 76), { Material = METAL })
	newPart("LampCap", V3(2.8, 0.3, 2.8), base * CF(0, 12.2, 0), C_DARK, nil, m)
	local head = newPart("LampHead", V3(2.2, 0.5, 2.2), base * CF(0, 11.8, 0), C_WARM, NEON_DECO, m)
	addPointLight(head, RGB(255, 226, 160), 30, 1)
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
	addPointLight(water, RGB(90, 200, 255), 40, 0.8)

	-- Center pedestal, tiered bowl and glowing pillar
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
	local pillar = worldCylinder(
		world,
		"GlowPillar",
		"Y",
		7,
		1.3,
		at(0, 11.4, 0),
		RGB(120, 215, 255),
		{ Material = NEON, Transparency = 0.15, CanCollide = false }
	)
	addPointLight(pillar, RGB(120, 215, 255), 45, 1.2)
	newPart("PillarCap", V3(2.2, 0.5, 2.2), at(0, 15.2, 0), C_CHROME, { Material = METAL }, world)

	-- Small neon "droplets" arcing around the pillar
	for k = 0, 7 do
		local a = k * TWO_PI / 8
		newPart(
			"Droplet",
			V3(0.5, 0.5, 0.5),
			at(math.sin(a) * 2.6, 9.2 - (k % 2) * 1.2, math.cos(a) * 2.6) * ANG(0, a, math.rad(45)),
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

		-- asphalt segment (tangent box, overlapping neighbours)
		local pos = V3(dx * midR, ROAD_TOP - 0.15, dz * midR)
		newPart(
			"Road",
			V3(roadLen, 0.3, outerR - innerR),
			CFrame.lookAt(pos, V3(0, pos.Y, 0)),
			C_ASPHALT,
			nil,
			roadFolder
		)

		-- inner curb
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
		newPart(
			"LaneDash",
			V3(5, LINE_THICK, 0.6),
			CFrame.lookAt(pos, V3(0, pos.Y, 0)),
			C_WHITE,
			DECAL,
			roadFolder
		)
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

	-- Street lamps along the outer curb of the ring (between plot connectors).
	local lampCount = 20
	for k = 0, lampCount - 1 do
		local a = (k + 0.5) * TWO_PI / lampCount
		local r = Layout.RING_OUTER_RADIUS + 3.5
		buildLamp(decor, V3(math.sin(a) * r, Layout.GROUND_Y, math.cos(a) * r))
	end
	-- Street lamps on the island side of the ring.
	for k = 0, 7 do
		local a = (k + 0.5) * TWO_PI / 8
		local r = Layout.RING_INNER_RADIUS - 3.5
		buildLamp(decor, V3(math.sin(a) * r, Layout.GROUND_Y, math.cos(a) * r))
	end

	-- Trees on the island (keep clear of plaza, spawn and road).
	local placed = 0
	local attempts = 0
	while placed < 24 and attempts < 400 do
		attempts += 1
		local a = rng:NextNumber(0, TWO_PI)
		local r = rng:NextNumber(34, 68)
		local pos = V3(math.sin(a) * r, Layout.GROUND_Y, math.cos(a) * r)
		local dSpawn = (Vector3.new(pos.X, 0, pos.Z) - V3(0, 0, 28)).Magnitude
		if dSpawn > 20 then
			buildTree(decor, pos, rng:NextNumber(0.9, 1.4), rng)
			placed += 1
		end
	end

	-- Trees outside the ring, away from road, plots and connectors.
	placed = 0
	attempts = 0
	while placed < 46 and attempts < 1500 do
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

	-- Grass ground (top surface at GROUND_Y) and the island disk.
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
-- Plot: static parts
------------------------------------------------------------------------------------------------

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

local function parkingSpot(ctx: Ctx, parent: Instance, queueIndex: number)
	local q: Vector3 = Layout.QUEUE[queueIndex].Position
	outline(ctx, parent, "SpotLine", q.X, q.Z, 8.4, 15.4, 0.3, LOT_TOP + LINE_THICK / 2, C_WHITE)
end

local function buildGate(ctx: Ctx, static: Folder)
	local accent = ctx.accent
	local gate = newModel("Gate", static)
	local gz = Layout.GATE.Position.Z -- -60

	for _, sx in { -1, 1 } do
		ctx.P(gate, "GateBase", V3(3.6, 0.8, 3.6), CF(sx * 14, 0.4, gz), C_CHROME, { Material = METAL })
		ctx.P(gate, "GatePillar", V3(2.4, 16, 2.4), CF(sx * 14, 8.4, gz), C_DARK)
		ctx.P(gate, "GatePillarNeon", V3(0.35, 14, 0.2), CF(sx * 14, 8.4, gz - 1.3), accent, NEON_DECO)
	end
	ctx.P(gate, "GateBeam", V3(32, 2.4, 3), CF(0, 16, gz), C_DARK)
	local beamNeon = ctx.P(gate, "GateBeamNeon", V3(31.6, 0.3, 0.2), CF(0, 15.3, gz - 1.6), accent, NEON_DECO)
	addPointLight(beamNeon, accent, 25, 0.8)

	local board = ctx.P(gate, "SignBoard", V3(24, 5, 0.8), CF(0, 12.3, gz), C_DARKER)
	-- accent trim around the board (front face is toward -Z)
	ctx.P(gate, "SignTrim", V3(24.7, 0.35, 0.4), CF(0, 9.65, gz - 0.5), accent, NEON_DECO)
	for _, sx in { -1, 1 } do
		ctx.P(gate, "SignTrim", V3(0.35, 5.0, 0.4), CF(sx * 12.15, 12.3, gz - 0.5), accent, NEON_DECO)
	end
	addSignText(board, "SignGui", "OwnerLabel", "", "plot_free", 40)
	gate.PrimaryPart = board
end

local function buildSafe(ctx: Ctx, static: Folder)
	local accent = ctx.accent
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
	ctx.P(safe, "SafeBand", V3(4.1, 0.3, 4.1), CF(sx, cy + 4.6, sz), accent, NEON_DECO)
	ctx.P(safe, "SafeHandle", V3(0.3, 1.8, 0.3), CF(sx + 1.0, cy + 2.4, sz - 2.3), C_CHROME, { Material = METAL, Reflectance = 0.4 })
	ctx.C(safe, "SafeDial", "Z", 0.3, 1.3, CF(sx - 0.5, cy + 3.0, sz - 2.25), C_CHROME, { Material = METAL, Reflectance = 0.4 })
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
		accent,
		{ Material = NEON, Transparency = 0.25, CanCollide = false, CastShadow = false }
	)
	addPointLight(pad, accent, 14, 0.8)

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
	local accent = ctx.accent
	local hb = newModel("HireBoard", static)
	local b: CFrame = Layout.HIRE_BOARD
	local bx, bz = b.Position.X, b.Position.Z - 0.6 -- stand just in front of the back wall
	local bc = 5.5

	local cork = RGB(196, 150, 98)
	local wood = RGB(110, 76, 48)
	local board = ctx.P(hb, "Board", V3(10, 6, 0.5), CF(bx, bc, bz), cork)
	hb.PrimaryPart = board

	-- wooden frame
	ctx.P(hb, "Frame", V3(10.8, 0.4, 0.7), CF(bx, bc + 3.2, bz), wood)
	ctx.P(hb, "Frame", V3(10.8, 0.4, 0.7), CF(bx, bc - 3.2, bz), wood)
	for _, sx in { -1, 1 } do
		ctx.P(hb, "Frame", V3(0.4, 6.8, 0.7), CF(bx + sx * 5.2, bc, bz), wood)
		ctx.P(hb, "Leg", V3(0.5, 2.5, 0.5), CF(bx + sx * 4, 1.25 + FLOOR_TOP, bz), wood)
	end

	-- title plate
	local plate = ctx.P(hb, "TitlePlate", V3(8, 1.3, 0.4), CF(bx, bc + 4.05, bz), C_DARKER)
	ctx.P(hb, "TitleNeon", V3(8.2, 0.2, 0.3), CF(bx, bc + 3.45, bz - 0.2), accent, NEON_DECO)
	local gui = newSurfaceGui(plate, "TitleGui", Enum.NormalId.Front, 60)
	local title = newLabel(gui, "TitleLabel", "Hire Board", RGB(255, 255, 255), UDim2.fromScale(1, 1))
	title.Font = Enum.Font.GothamBlack
	title:SetAttribute("TextKey", "object_hire_board")
	addStroke(title, 2, Color3.new(0, 0, 0))

	-- paper notes
	local notes: { any } = {
		{ -3.4, 6.7, RGB(255, 235, 120), 5 },
		{ -0.9, 4.3, RGB(255, 160, 190), -7 },
		{ 1.5, 6.7, RGB(150, 215, 255), -4 },
		{ 3.6, 4.4, RGB(170, 240, 170), 8 },
		{ -3.7, 4.2, RGB(255, 190, 120), -6 },
	}
	for _, n in notes do
		local nx: number, ny: number, ncol: Color3, roll: number = n[1], n[2], n[3], n[4] -- n is `any`
		ctx.P(
			hb,
			"Note",
			V3(2, 2.5, 0.06),
			CF(bx + nx, ny, bz - 0.28) * ANG(0, 0, math.rad(roll)),
			ncol,
			DECAL
		)
		ctx.P(
			hb,
			"NotePin",
			V3(0.3, 0.3, 0.1),
			CF(bx + nx, ny + 1.0, bz - 0.33),
			RGB(220, 40, 40),
			DECAL
		)
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
	ctx.P(static, "Floor", V3(width, 0.2, depth), CF(0, 0, midZ), C_FLOOR, { Reflectance = 0.08 })
	local gridY = FLOOR_TOP + 0.01
	for _, gx in { -56, -42, -28, -14, 0, 14, 28, 42, 56 } do
		ctx.P(static, "FloorGrid", V3(0.15, 0.02, depth - 0.4), CF(gx, gridY, midZ), C_GRID, DECAL)
	end
	for _, gz in { -8, 6, 20, 34, 48 } do
		ctx.P(static, "FloorGrid", V3(width - 0.4, 0.02, 0.15), CF(0, gridY, gz), C_GRID, DECAL)
	end
	ctx.P(static, "FloorThreshold", V3(width, 0.05, 0.5), CF(0, FLOOR_TOP + 0.025, B.frontZ + 0.25), accent, NEON_DECO)

	-- Walls: back + two sides (front is open)
	ctx.P(static, "BackWall", V3(width, height, 2), CF(0, height / 2, B.backZ - 1), C_WALL)
	for _, sx in { -1, 1 } do
		ctx.P(static, "SideWall", V3(2, height, depth - 2), CF(sx * (B.maxX - 1), height / 2, midZ - 1), C_WALL)
	end
	local innerX = B.maxX - 2 -- 68
	local innerZ = B.backZ - 2 -- 58

	-- Baseboards + accent stripes on the inner faces
	ctx.P(static, "Baseboard", V3(width - 4, 1.2, 0.2), CF(0, FLOOR_TOP + 0.6, innerZ - 0.1), C_DARK)
	ctx.P(static, "WallStripe", V3(width - 4, 3, 0.2), CF(0, 4, innerZ - 0.1), accent)
	ctx.P(static, "WallStripeNeon", V3(width - 4, 0.3, 0.25), CF(0, 5.9, innerZ - 0.15), accent, NEON_DECO)
	for _, sx in { -1, 1 } do
		ctx.P(static, "Baseboard", V3(0.2, 1.2, depth - 2), CF(sx * (innerX - 0.1), FLOOR_TOP + 0.6, midZ - 1), C_DARK)
		ctx.P(static, "WallStripe", V3(0.2, 3, depth - 2), CF(sx * (innerX - 0.1), 4, midZ - 1), accent)
		ctx.P(static, "WallStripeNeon", V3(0.25, 0.3, depth - 2), CF(sx * (innerX - 0.15), 5.9, midZ - 1), accent, NEON_DECO)
	end

	-- Windows (frame + tinted glass sitting on the inner wall faces)
	local glassProps: Props = {
		Material = Enum.Material.Glass,
		Transparency = 0.3,
		Reflectance = 0.2,
		CanCollide = false,
		CastShadow = false,
	}
	local glassColor = RGB(110, 180, 220)
	for _, sx in { -1, 1 } do
		for _, wz in { 0, 22, 44 } do
			ctx.P(static, "WindowFrame", V3(0.15, 7, 14), CF(sx * (innerX - 0.075), 12.5, wz), C_DARK, DECAL)
			ctx.P(static, "WindowGlass", V3(0.2, 6, 12.4), CF(sx * (innerX - 0.1), 12.5, wz), glassColor, glassProps)
		end
	end
	for _, wx in { -30, 0, 30 } do
		ctx.P(static, "WindowFrame", V3(14, 7, 0.15), CF(wx, 12.5, innerZ - 0.075), C_DARK, DECAL)
		ctx.P(static, "WindowGlass", V3(12.4, 6, 0.2), CF(wx, 12.5, innerZ - 0.1), glassColor, glassProps)
	end

	-- Roof with neon trim on the front edge, ceiling lights
	ctx.P(static, "Roof", V3(width + 4, 1.5, depth + 2), CF(0, height + 0.75, midZ), C_ROOF)
	ctx.P(static, "RoofNeonFront", V3(width + 4, 0.5, 0.3), CF(0, height + 0.75, B.frontZ - 1.15), accent, NEON_DECO)
	for _, lx in { -35, 35 } do
		for _, lz in { 8, 40 } do
			local panel = ctx.P(
				static,
				"CeilingLight",
				V3(18, 0.3, 3),
				CF(lx, height - 0.15, lz),
				RGB(255, 250, 235),
				NEON_DECO
			)
			addPointLight(panel, RGB(255, 246, 225), 40, 0.7)
		end
	end

	-- Pillars along the open front, with accent bands
	for _, px in { -67, -32, 0, 32, 67 } do
		ctx.P(static, "Pillar", V3(2, height, 2), CF(px, height / 2, B.frontZ + 1), RGB(240, 242, 246))
		ctx.P(static, "PillarBand", V3(2.2, 0.3, 2.2), CF(px, 3, B.frontZ + 1), accent, NEON_DECO)
		ctx.P(static, "PillarBand", V3(2.2, 0.3, 2.2), CF(px, height - 3, B.frontZ + 1), accent, NEON_DECO)
	end

	-- Yellow bay outlines in front of each bay car position
	for n = 1, #Layout.BAYS do
		local c: Vector3 = Layout.BAYS[n].car.Position
		outline(ctx, static, "BayLine", c.X, c.Z, 9, 16, 0.3, FLOOR_TOP + LINE_THICK / 2 + 0.005, C_YELLOW)
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
	-- dashed center line between the entry and exit lane
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
end

local function buildStatic(ctx: Ctx, plot: Model): Folder
	local static = newFolder("Static", plot)
	buildOutside(ctx, static)
	buildBuilding(ctx, static)
	buildGate(ctx, static)
	buildSafe(ctx, static)
	buildHireBoard(ctx, static)
	return static
end

------------------------------------------------------------------------------------------------
-- Plot: unlockables (one self-contained Model per unlock id)
------------------------------------------------------------------------------------------------

-- Overhead sign + ceiling spot light shared by both bays.
local function buildBayOverhead(ctx: Ctx, model: Model, bayIndex: number, unlockId: string): Part
	local accent = ctx.accent
	local x: number = Layout.BAYS[bayIndex].car.Position.X
	local signZ = -12

	for _, sx in { -1, 1 } do
		ctx.P(model, "SignChain", V3(0.25, 4.8, 0.25), CF(x + sx * 5.5, 21.65, signZ), C_STEEL, { Material = METAL })
	end
	local sign = ctx.P(model, "BaySign", V3(14, 3, 0.8), CF(x, 17.8, signZ), C_DARKER)
	addSignText(sign, "SignGui", "SignLabel", unlockId, "unlock_" .. unlockId, 40)
	local strip = ctx.P(model, "BayNeon", V3(14.4, 0.3, 1.0), CF(x, 16.15, signZ), accent, NEON_DECO)
	addPointLight(strip, accent, 14, 0.6)

	-- Ceiling fixture with a spot light shining on the bay
	local fx = x
	local fz = Layout.BAYS[bayIndex].car.Position.Z
	ctx.P(model, "LampFixture", V3(3, 0.5, 3), CF(fx, 23.75, fz), C_DARK)
	local lens = ctx.P(model, "LampLens", V3(2.2, 0.1, 2.2), CF(fx, 23.45, fz), RGB(255, 250, 235), NEON_DECO)
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Bottom
	spot.Angle = 75
	spot.Range = 32
	spot.Brightness = 2.5
	spot.Color = RGB(255, 246, 225)
	spot.Shadows = false
	spot.Parent = lens
	return sign
end

local function buildBay1(ctx: Ctx, parent: Folder): Model
	local accent = ctx.accent
	local model = newModel("Bay1", parent)
	local m: CFrame = Layout.BAYS[1].machine
	local mx, mz = m.Position.X, m.Position.Z
	local FT = FLOOR_TOP
	local red = RGB(205, 40, 40)
	local redProps: Props = { Reflectance = 0.1 }
	local chromeProps: Props = { Material = METAL, Reflectance = 0.4 }

	-- Tire changer
	ctx.P(model, "MachineBase", V3(3.8, 0.3, 3.8), CF(mx, FT + 0.15, mz), C_DARK)
	ctx.P(model, "MachineBody", V3(2.4, 2.0, 2.4), CF(mx, FT + 1.3, mz), red, redProps)
	ctx.P(model, "MachineStripe", V3(2.5, 0.2, 0.1), CF(mx, FT + 2.1, mz - 1.25), accent, NEON_DECO)
	ctx.C(model, "Turntable", "Y", 0.3, 3.2, CF(mx, FT + 2.45, mz), C_CHROME, chromeProps)
	ctx.C(model, "MountedTire", "Y", 0.9, 2.9, CF(mx, FT + 3.05, mz), C_TIRE, nil)
	ctx.C(model, "MountedRim", "Y", 0.96, 1.8, CF(mx, FT + 3.05, mz), C_CHROME, chromeProps)
	ctx.P(model, "Mast", V3(0.9, 5.6, 0.9), CF(mx, FT + 3.1, mz + 1.6), red, redProps)
	ctx.P(model, "Arm", V3(0.7, 0.7, 3.4), CF(mx, FT + 5.5, mz + 0.0), C_CHROME, chromeProps)
	ctx.P(model, "ArmHead", V3(0.8, 1.2, 0.8), CF(mx, FT + 4.8, mz - 1.0), C_DARK)
	ctx.C(model, "ArmTool", "Y", 1.0, 0.3, CF(mx, FT + 4.0, mz - 1.0), C_CHROME, chromeProps)

	-- Stack of 3 tires next to it
	for k = 0, 2 do
		ctx.C(model, "StackTire", "Y", 1.0, 3.0, CF(mx + 4.4, FT + 0.5 + k * 1.0, mz + 0.5), C_TIRE, nil)
	end
	ctx.C(model, "StackRim", "Y", 0.1, 1.7, CF(mx + 4.4, FT + 3.05, mz + 0.5), C_CHROME, chromeProps)

	-- Tool board standing behind the bay
	local bx = Layout.BAYS[1].car.Position.X
	local bz = 8
	ctx.P(model, "ToolBoard", V3(12, 6, 0.5), CF(bx, FT + 5, bz), RGB(66, 72, 84))
	ctx.P(model, "ToolBoardNeon", V3(12.2, 0.2, 0.3), CF(bx, FT + 8.1, bz - 0.1), accent, NEON_DECO)
	for _, sx in { -4.5, 4.5 } do
		ctx.P(model, "ToolBoardLeg", V3(0.5, 2, 0.5), CF(bx + sx, FT + 1, bz), C_STEEL)
	end
	local tz = bz - 0.35
	-- wrench
	ctx.P(model, "ToolWrench", V3(0.4, 3.4, 0.2), CF(bx - 4.2, FT + 5.2, tz), C_CHROME, chromeProps)
	ctx.P(model, "ToolWrenchHead", V3(1.1, 0.9, 0.2), CF(bx - 4.2, FT + 7.0, tz), C_CHROME, chromeProps)
	-- hammer
	ctx.P(model, "ToolHammer", V3(0.4, 3.0, 0.2), CF(bx - 2.0, FT + 4.9, tz), RGB(150, 100, 60))
	ctx.P(model, "ToolHammerHead", V3(1.6, 0.8, 0.3), CF(bx - 2.0, FT + 6.5, tz), C_DARK)
	-- screwdriver
	ctx.P(model, "ToolDriverShaft", V3(0.2, 2.2, 0.15), CF(bx + 0.2, FT + 6.0, tz), C_CHROME, chromeProps)
	ctx.P(model, "ToolDriverHandle", V3(0.6, 1.6, 0.3), CF(bx + 0.2, FT + 4.1, tz), red)
	-- pliers
	ctx.P(model, "ToolPliers", V3(0.5, 2.6, 0.2), CF(bx + 2.3, FT + 5.0, tz) * ANG(0, 0, math.rad(12)), RGB(230, 190, 40))
	ctx.P(model, "ToolPliersHead", V3(1.0, 0.9, 0.2), CF(bx + 2.65, FT + 6.4, tz) * ANG(0, 0, math.rad(12)), C_DARK)
	-- spare tire hanging
	ctx.C(model, "ToolTire", "Z", 0.5, 2.6, CF(bx + 4.3, FT + 4.6, tz), C_TIRE, nil)
	ctx.C(model, "ToolTireRim", "Z", 0.56, 1.2, CF(bx + 4.3, FT + 4.6, tz), C_CHROME, chromeProps)

	local sign = buildBayOverhead(ctx, model, 1, "Bay1")
	model.PrimaryPart = sign
	return model
end

local function buildBay2(ctx: Ctx, parent: Folder): Model
	local model = newModel("Bay2", parent)
	local m: CFrame = Layout.BAYS[2].machine
	local mx, mz = m.Position.X, m.Position.Z
	local FT = FLOOR_TOP
	local yellow = RGB(255, 200, 20)
	local chromeProps: Props = { Material = METAL, Reflectance = 0.4 }
	local hose = RGB(18, 18, 20)

	-- Stand
	ctx.P(model, "StandBase", V3(3.6, 0.3, 3.6), CF(mx, FT + 0.15, mz), C_DARK)
	for _, lx in { -1.4, 1.4 } do
		for _, lz in { -1.4, 1.4 } do
			ctx.P(model, "StandLeg", V3(0.4, 2.8, 0.4), CF(mx + lx, FT + 1.7, mz + lz), C_STEEL, { Material = METAL })
		end
	end
	ctx.P(model, "StandTop", V3(3.6, 0.3, 3.6), CF(mx, FT + 3.25, mz), C_DARK)

	-- Yellow drain drum
	ctx.C(model, "OilDrum", "Y", 3.2, 2.8, CF(mx, FT + 5.0, mz), yellow, { Reflectance = 0.1 })
	ctx.C(model, "DrumBand", "Y", 0.25, 2.9, CF(mx, FT + 4.1, mz), RGB(200, 140, 10), nil)
	ctx.C(model, "DrumBand", "Y", 0.25, 2.9, CF(mx, FT + 5.9, mz), RGB(200, 140, 10), nil)
	ctx.C(model, "DrumLid", "Y", 0.2, 2.3, CF(mx, FT + 6.7, mz), C_DARK, nil)
	ctx.C(model, "DrumFunnel", "Y", 0.5, 1.2, CF(mx, FT + 7.0, mz), hose, nil)
	ctx.C(model, "DrumGauge", "Z", 0.3, 1.0, CF(mx, FT + 5.2, mz - 1.45), RGB(245, 245, 245), nil)
	ctx.P(model, "DrumGaugeNeedle", V3(0.08, 0.4, 0.05), CF(mx, FT + 5.3, mz - 1.62), RGB(230, 40, 40), DECAL)

	-- Black hose reaching toward the car
	ctx.C(model, "HoseTube", "X", 3.2, 0.4, CF(mx - 3.0, FT + 4.4, mz), hose, nil)
	ctx.C(model, "HoseTube", "Y", 3.0, 0.4, CF(mx - 4.4, FT + 2.9, mz), hose, nil)
	ctx.P(model, "HoseNozzle", V3(0.6, 0.7, 0.6), CF(mx - 4.4, FT + 1.25, mz), C_CHROME, chromeProps)

	-- Oil barrels (blue / red)
	local barrels: { any } = {
		{ 4.2, -1.6, RGB(40, 90, 200) },
		{ 4.2, 1.2, RGB(210, 50, 50) },
		{ 6.6, -0.2, RGB(40, 90, 200) },
	}
	for _, b in barrels do
		local bx: number, bz: number, bcol: Color3 = b[1], b[2], b[3]
		ctx.C(model, "Barrel", "Y", 3.2, 2.2, CF(mx + bx, FT + 1.6, mz + bz), bcol, { Reflectance = 0.1 })
		ctx.C(model, "BarrelRing", "Y", 0.2, 2.3, CF(mx + bx, FT + 0.9, mz + bz), C_DARK, nil)
		ctx.C(model, "BarrelRing", "Y", 0.2, 2.3, CF(mx + bx, FT + 2.3, mz + bz), C_DARK, nil)
		ctx.C(model, "BarrelLid", "Y", 0.1, 1.2, CF(mx + bx, FT + 3.22, mz + bz), C_CHROME, chromeProps)
	end

	local sign = buildBayOverhead(ctx, model, 2, "Bay2")
	model.PrimaryPart = sign
	return model
end

local function buildCashier(ctx: Ctx, parent: Folder): Model
	local accent = ctx.accent
	local model = newModel("Cashier", parent)
	local c: CFrame = Layout.CASHIER.counter
	local cx, cz = c.Position.X, c.Position.Z
	local FT = FLOOR_TOP
	local topY = FT + 4.1 -- top surface of the counter

	local counter = ctx.P(model, "Counter", V3(14, 3.7, 3), CF(cx, FT + 1.85, cz), RGB(238, 240, 244))
	model.PrimaryPart = counter
	ctx.P(model, "CounterTop", V3(15, 0.4, 3.6), CF(cx, FT + 3.9, cz), RGB(176, 128, 84), { Material = Enum.Material.Wood })
	ctx.P(model, "CounterFront", V3(13.2, 2.2, 0.2), CF(cx, FT + 1.95, cz - 1.55), accent)
	ctx.P(model, "CounterNeon", V3(13.2, 0.15, 0.22), CF(cx, FT + 0.85, cz - 1.56), accent, NEON_DECO)
	ctx.P(model, "CounterNeon", V3(13.2, 0.15, 0.22), CF(cx, FT + 3.1, cz - 1.56), accent, NEON_DECO)

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

	-- Floor mat for the cashier
	ctx.P(model, "CashierMat", V3(6, 0.05, 3), CF(cx, FT + 0.025, cz + 5), RGB(60, 64, 74), DECAL)
	return model
end

local function buildShelf1(ctx: Ctx, parent: Folder): Model
	local accent = ctx.accent
	local model = newModel("Shelf1", parent)
	local s: CFrame = Layout.SHELVES[1].shelf
	local sx, sz = s.Position.X, s.Position.Z
	local FT = FLOOR_TOP
	local frame = RGB(125, 131, 142)
	local frameProps: Props = { Material = METAL }

	for _, ux in { -4.3, 4.3 } do
		for _, uz in { -1.1, 1.1 } do
			ctx.P(model, "ShelfUpright", V3(0.4, 8.2, 0.4), CF(sx + ux, FT + 4.1, sz + uz), frame, frameProps)
		end
	end
	local back = ctx.P(model, "ShelfBack", V3(8.8, 8.0, 0.12), CF(sx, FT + 4.1, sz + 1.35), RGB(70, 76, 86))
	model.PrimaryPart = back

	local levels = { 2.2, 4.8, 7.4 }
	local xs = { -3.4, -1.7, 0, 1.7, 3.4 }
	for _, ly in levels do
		ctx.P(model, "ShelfBoard", V3(9, 0.3, 2.8), CF(sx, FT + ly, sz), frame, frameProps)
		ctx.P(model, "PriceStrip", V3(9, 0.4, 0.12), CF(sx, FT + ly - 0.02, sz - 1.46), accent)
		for _, bx in xs do
			local by = FT + ly + 0.15 + 0.55
			ctx.P(model, "Battery", V3(1.5, 1.1, 1.1), CF(sx + bx, by, sz - 0.4), RGB(34, 38, 46))
			ctx.P(model, "BatteryTerminal", V3(0.28, 0.2, 0.28), CF(sx + bx - 0.4, by + 0.65, sz - 0.4), RGB(210, 36, 36))
			ctx.P(model, "BatteryTerminal", V3(0.28, 0.2, 0.28), CF(sx + bx + 0.4, by + 0.65, sz - 0.4), RGB(60, 62, 70))
		end
	end
	return model
end

local function buildLampPost(ctx: Ctx, model: Model, x: number, z: number)
	ctx.P(model, "LampBase", V3(1.4, 0.5, 1.4), CF(x, LOT_TOP + 0.25, z), C_DARK)
	ctx.C(model, "LampPole", "Y", 10, 0.45, CF(x, LOT_TOP + 5.5, z), RGB(60, 66, 76), { Material = METAL })
	ctx.P(model, "LampCap", V3(2.4, 0.3, 2.4), CF(x, LOT_TOP + 10.7, z), C_DARK)
	local head = ctx.P(model, "LampHead", V3(1.8, 0.5, 1.8), CF(x, LOT_TOP + 10.35, z), C_WARM, NEON_DECO)
	addPointLight(head, RGB(255, 226, 160), 30, 1.2)
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

local function buildUnlockables(ctx: Ctx, plot: Model)
	local folder = newFolder("Unlockables", plot)
	buildBay1(ctx, folder)
	buildBay2(ctx, folder)
	buildCashier(ctx, folder)
	buildShelf1(ctx, folder)
	buildParking(ctx, folder)
end

------------------------------------------------------------------------------------------------
-- Plot: unlock buttons
------------------------------------------------------------------------------------------------

local function buttonPosition(u: any): Vector3?
	if u.kind == "Bay" then
		return Layout.BAYS[u.bay].button
	elseif u.kind == "Cashier" then
		return Layout.CASHIER.button
	elseif u.kind == "Shelf" then
		return Layout.SHELVES[u.shelf].button
	elseif u.kind == "Parking" then
		return Layout.PARKING_BUTTON
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
