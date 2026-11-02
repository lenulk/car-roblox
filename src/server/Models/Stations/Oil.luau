--!strict
-- Oil change / drain station (beside bay 2, docs/CONTRACT.md section 12). Footprint X -3..5, Z -4..4, -Z = front.
-- Lv1 rusty with a leak + taped hose, Lv2 clean full set, Lv3 chrome + flow meter + LEDs, Lv4 carbon + stripes +
-- dispenser boom + banner, Lv5 glass tank with glowing oil core, pump tower, hologram and sparkles.

local ModelKit = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("ModelKit"))

local YELLOW = Color3.fromRGB(255, 200, 20)
local BLUE = Color3.fromRGB(50, 90, 200)
local RED = Color3.fromRGB(205, 50, 45)
local OIL = Color3.fromRGB(34, 22, 10)
local TAPE = Color3.fromRGB(205, 200, 185)
local BLACK = Color3.fromRGB(8, 14, 20)

local function aim(from: Vector3, to: Vector3): CFrame
	local dir = to - from
	local up = if math.abs(dir.Unit.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
	return CFrame.lookAt(from, to, up)
end

local function bar(parent: Instance, name: string, a: Vector3, b: Vector3, tx: number, ty: number, color: Color3, props: ModelKit.Props?): Part
	return ModelKit.part(parent, name, Vector3.new(tx, ty, (b - a).Magnitude), aim((a + b) / 2, b), color, props)
end

local function screen(part: BasePart, text: string, textColor: Color3, bg: Color3, bgTransparency: number)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Display"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = bg
	label.BackgroundTransparency = bgTransparency
	label.Text = text
	label.TextColor3 = textColor
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = gui
	gui.Parent = part
end

local function sparkles(part: BasePart, color: Color3, rate: number)
	local e = Instance.new("ParticleEmitter")
	e.Name = "Sparkle"
	e.Rate = rate
	e.Lifetime = NumberRange.new(0.8, 1.6)
	e.Speed = NumberRange.new(0.6, 1.8)
	e.SpreadAngle = Vector2.new(180, 180)
	e.LightEmission = 1
	e.Size = NumberSequence.new(0.2, 0)
	e.Color = ColorSequence.new(color)
	e.Parent = part
end

-- Ring of tube segments around the local X axis of `base`; `skip` leaves one segment out (broken rim).
local function ring(parent: Instance, name: string, base: CFrame, radius: number, count: number, dia: number, color: Color3, props: ModelKit.Props?, skip: number?)
	local len = 2 * radius * math.sin(math.pi / count) * 1.1
	for i = 1, count do
		if i ~= skip then
			local a = (i - 1) / count * math.pi * 2
			local pos = base * Vector3.new(0, math.sin(a) * radius, math.cos(a) * radius)
			local tangent = base:VectorToWorldSpace(Vector3.new(0, math.cos(a), -math.sin(a)))
			ModelKit.cylinder(parent, name, "Z", len, dia, aim(pos, pos + tangent), color, props)
		end
	end
end

-- Hose through a list of points with round joints; optional tape wraps on the given segment indices.
local function polyHose(parent: Instance, name: string, pts: { Vector3 }, dia: number, color: Color3, props: ModelKit.Props?, tapeSegs: { number }?)
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local cf = aim((a + b) / 2, b)
		ModelKit.cylinder(parent, name, "Z", (b - a).Magnitude, dia, cf, color, props)
		if tapeSegs and table.find(tapeSegs, i) then
			ModelKit.cylinder(parent, "Tape", "Z", 0.3, dia * 1.5, cf, TAPE, { Material = Enum.Material.Fabric })
		end
		if i > 1 then
			ModelKit.ball(parent, name .. "Joint", dia, CFrame.new(a), color, props)
		end
	end
end

return function(level: number, accent: Color3, opts: { [string]: any }?): Model
	local model = ModelKit.model("Station")
	local tier = ModelKit.tier(level)
	local lv = tier.level
	local ledColor = tier.ledColor(accent)
	local metalProps: ModelKit.Props = { Material = tier.metalMaterial, Reflectance = tier.metalReflectance }
	local trimProps: ModelKit.Props = { Material = tier.trimMaterial }
	local hoseColor = if lv == 1 then Color3.fromRGB(48, 44, 40) else Color3.fromRGB(28, 28, 30)

	local function rust(cf: CFrame, w: number, h: number)
		ModelKit.part(model, "Rust", Vector3.new(w, h, 0.05), cf, Color3.fromRGB(122, 70, 38), {
			Material = Enum.Material.Rust,
			CanCollide = false,
			CastShadow = false,
		})
	end

	------------------------------------------------------------ floor pad
	ModelKit.trim(model, "Pad", Vector3.new(7.8, 0.1, 7.8), CFrame.new(1, 0.15, 0), tier)
	if lv >= 2 then
		local hz: ModelKit.Props = { CanCollide = false, CastShadow = false }
		ModelKit.part(model, "PadStripe", Vector3.new(7.8, 0.04, 0.25), CFrame.new(1, 0.21, -3.75), YELLOW, hz)
		ModelKit.part(model, "PadStripe", Vector3.new(7.8, 0.04, 0.25), CFrame.new(1, 0.21, 3.75), YELLOW, hz)
		ModelKit.part(model, "PadStripe", Vector3.new(0.25, 0.04, 7.3), CFrame.new(-2.75, 0.21, 0), YELLOW, hz)
		ModelKit.part(model, "PadStripe", Vector3.new(0.25, 0.04, 7.3), CFrame.new(4.75, 0.21, 0), YELLOW, hz)
	else
		-- Lv1: oil spill on the floor
		ModelKit.cylinder(model, "OilSpill", "Y", 0.03, 1.7, CFrame.new(2.0, 0.215, 0.6), OIL, { Reflectance = 0.3, CanCollide = false })
	end

	------------------------------------------------------------ telescopic drain stand + funnel pan
	local DX, DZ = -1.5, -1.9
	ModelKit.metal(model, "StandLegX", Vector3.new(2.2, 0.25, 0.4), CFrame.new(DX, 0.625, DZ), tier)
	ModelKit.metal(model, "StandLegZ", Vector3.new(0.4, 0.25, 2.2), CFrame.new(DX, 0.625, DZ), tier)
	for _, s in { -1, 1 } do
		ModelKit.cylinder(model, "StandWheel", "Z", 0.2, 0.5, CFrame.new(DX + s * 1.0, 0.35, DZ), tier.trimColor, trimProps)
		ModelKit.cylinder(model, "StandWheel", "X", 0.2, 0.5, CFrame.new(DX, 0.35, DZ + s * 1.0), tier.trimColor, trimProps)
	end
	if lv == 1 then
		ModelKit.cylinder(model, "StandPole", "Y", 3.3, 0.5, CFrame.new(DX, 2.4, DZ), tier.metalColor, metalProps)
	else
		ModelKit.cylinder(model, "StandPoleLow", "Y", 2.0, 0.5, CFrame.new(DX, 1.75, DZ), tier.metalColor, metalProps)
		ModelKit.cylinder(model, "StandPoleUp", "Y", 1.7, 0.34, CFrame.new(DX, 3.2, DZ), tier.metalColor, metalProps)
		ModelKit.cylinder(model, "StandCollar", "Y", 0.3, 0.64, CFrame.new(DX, 2.75, DZ), tier.trimColor, trimProps)
		if lv >= 3 then
			ModelKit.ball(model, "LockKnob", 0.34, CFrame.new(DX + 0.42, 2.75, DZ), if lv >= 4 then accent else YELLOW)
		end
	end
	ModelKit.cylinder(model, "StandNeck", "Y", 0.2, 0.5, CFrame.new(DX, 4.15, DZ), tier.metalColor, metalProps)
	ModelKit.cylinder(model, "FunnelPlate", "Y", 0.12, 2.4, CFrame.new(DX, 4.28, DZ), tier.metalColor, metalProps)
	ring(
		model,
		"FunnelRim",
		CFrame.new(DX, 4.45, DZ) * CFrame.Angles(0, 0, math.pi / 2),
		1.2,
		if lv == 1 then 8 else 12,
		0.3,
		tier.metalColor,
		metalProps,
		if lv == 1 then 5 else nil
	)
	ModelKit.cylinder(model, "FunnelHole", "Y", 0.04, 0.7, CFrame.new(DX, 4.36, DZ), BLACK)
	ModelKit.cylinder(model, "FunnelSpout", "X", 0.6, 0.36, CFrame.new(DX + 0.95, 4.34, DZ), tier.metalColor, metalProps)
	if lv >= 4 then
		local glow = ModelKit.cylinder(model, "FunnelGlow", "Y", 0.05, 2.6, CFrame.new(DX, 4.2, DZ), accent, {
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
		})
		ModelKit.role(glow, "Accent")
	end
	if lv == 1 then
		rust(CFrame.new(DX + 0.1, 2.4, DZ - 0.26), 0.3, 0.9)
	end

	------------------------------------------------------------ collection tank on wheels
	local CX, CZ = 1.9, -1.9
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			ModelKit.cylinder(model, "CartWheel", "X", 0.3, 0.6, CFrame.new(CX + sx * 1.35, 0.4, CZ + sz * 1.3), tier.trimColor, trimProps)
		end
	end
	ModelKit.trim(model, "CartPlate", Vector3.new(3.2, 0.25, 3.2), CFrame.new(CX, 0.675, CZ), tier)
	local tankColor = tier.body(YELLOW)
	local tankProps: ModelKit.Props = { Material = tier.bodyMaterial, Reflectance = tier.bodyReflectance }
	if lv >= 5 then
		tankProps.Transparency = 0.35
	end
	ModelKit.cylinder(model, "Tank", "Y", 3.0, 2.8, CFrame.new(CX, 2.3, CZ), tankColor, tankProps)
	ModelKit.cylinder(model, "TankDome", "Y", 0.25, 2.2, CFrame.new(CX, 3.92, CZ), tier.metalColor, metalProps)
	ModelKit.cylinder(model, "TankCap", "Y", 0.25, 0.8, CFrame.new(CX, 4.17, CZ), tier.trimColor, trimProps)
	if lv >= 4 then
		for _, by in { 1.4, 3.2 } do
			local band = ModelKit.cylinder(model, "TankBand", "Y", 0.1, 2.88, CFrame.new(CX, by, CZ), accent, {
				Material = Enum.Material.Neon,
				CanCollide = false,
				CastShadow = false,
			})
			ModelKit.role(band, "Accent")
		end
	else
		ModelKit.cylinder(model, "TankBand", "Y", 0.16, 2.9, CFrame.new(CX, 3.2, CZ), tier.metalColor, metalProps)
		if lv >= 2 then
			ModelKit.cylinder(model, "TankBand", "Y", 0.16, 2.9, CFrame.new(CX, 1.4, CZ), tier.metalColor, metalProps)
		end
	end
	if lv >= 5 then
		local core = ModelKit.cylinder(model, "OilCore", "Y", 2.6, 2.3, CFrame.new(CX, 2.3, CZ), accent, {
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
		})
		ModelKit.role(core, "Accent")
		ModelKit.light(core, accent, 14, 1)
	end
	-- push handle
	for _, hx in { -0.9, 0.9 } do
		ModelKit.metal(model, "HandlePost", Vector3.new(0.15, 2.0, 0.15), CFrame.new(CX + hx, 1.8, -0.7), tier)
	end
	ModelKit.cylinder(model, "HandleGrip", "X", 2.0, 0.18, CFrame.new(CX, 2.8, -0.7), tier.trimColor, trimProps)

	-- sight glass with oil level
	local fill = 0.4 + lv * 0.3
	ModelKit.part(model, "SightGlass", Vector3.new(0.35, 2.0, 0.12), CFrame.new(CX + 1.0, 2.2, -2.95), Color3.fromRGB(170, 210, 235), {
		Material = Enum.Material.Glass,
		Transparency = 0.5,
		CanCollide = false,
	})
	ModelKit.part(model, "SightOil", Vector3.new(0.2, fill, 0.1), CFrame.new(CX + 1.0, 1.2 + fill / 2, -2.96), if lv == 1 then Color3.fromRGB(70, 48, 22) else Color3.fromRGB(150, 90, 20), {
		CanCollide = false,
	})
	ModelKit.metal(model, "SightFrame", Vector3.new(0.5, 0.12, 0.2), CFrame.new(CX + 1.0, 3.24, -2.95), tier)
	ModelKit.metal(model, "SightFrame", Vector3.new(0.5, 0.12, 0.2), CFrame.new(CX + 1.0, 1.14, -2.95), tier)

	if tier.rust then
		rust(CFrame.new(CX - 0.5, 1.8, -3.23), 0.7, 0.5)
		rust(CFrame.new(CX + 0.1, 3.0, -3.29), 0.5, 0.4)
		-- patched crack with tape + dent
		ModelKit.part(model, "TankTape", Vector3.new(1.3, 0.3, 0.1), CFrame.new(CX - 0.3, 2.3, -3.3) * CFrame.Angles(0, 0, math.rad(20)), TAPE, {
			Material = Enum.Material.Fabric,
			CanCollide = false,
		})
		ModelKit.part(model, "Dent", Vector3.new(0.8, 0.8, 0.1), CFrame.new(CX - 0.1, 1.2, -3.3), Color3.fromRGB(80, 60, 20), {
			Material = Enum.Material.Metal,
			CanCollide = false,
		})
	end

	-- hose from funnel to tank (taped at Lv1)
	polyHose(
		model,
		"DrainHose",
		{ Vector3.new(-0.25, 4.34, DZ), Vector3.new(0.2, 4.8, DZ), Vector3.new(1.1, 4.7, DZ), Vector3.new(CX, 4.4, CZ) },
		0.22,
		hoseColor,
		nil,
		if lv == 1 then { 2, 3 } else nil
	)

	-- flow meter column (Lv3+)
	if lv >= 3 then
		local meter = ModelKit.body(model, "MeterColumn", Vector3.new(1.5, 2.0, 0.5), CFrame.new(CX - 0.5, 1.8, -3.35), Color3.fromRGB(70, 76, 90), tier)
		if tier.stripes then
			ModelKit.stripes(model, meter, accent)
		end
		ModelKit.part(model, "MeterBezel", Vector3.new(1.3, 0.8, 0.06), CFrame.new(CX - 0.5, 2.35, -3.62), tier.trimColor, trimProps)
		local disp = ModelKit.part(model, "MeterDisplay", Vector3.new(1.2, 0.7, 0.08), CFrame.new(CX - 0.5, 2.35, -3.67), BLACK, { CanCollide = false })
		screen(disp, "OIL 4.2L", if lv >= 4 then accent else Color3.fromRGB(255, 200, 80), BLACK, 0)
		local led = ModelKit.led(model, "CartLED", Vector3.new(3.2, 0.08, 0.06), CFrame.new(CX, 0.7, CZ - 1.62), tier, accent)
		if led then
			ModelKit.light(led, ledColor, 14, 0.9)
		end
	end

	------------------------------------------------------------ barrels (blue / red)
	local function barrel(x: number, z: number, base: Color3, tilt: boolean)
		local col = if lv == 1 then base:Lerp(Color3.fromRGB(110, 90, 70), 0.5) else base
		local props: ModelKit.Props = {
			Material = if lv == 1 then Enum.Material.CorrodedMetal else Enum.Material.Metal,
			Reflectance = if lv >= 3 then 0.15 else 0,
		}
		local cf = CFrame.new(x, 1.4, z)
		if tilt then
			cf = cf * CFrame.Angles(0, 0, math.rad(9))
		end
		ModelKit.cylinder(model, "Barrel", "Y", 2.4, 1.8, cf, col, props)
		for _, ry in { -0.6, 0.6 } do
			if lv >= 5 then
				local rib = ModelKit.cylinder(model, "BarrelRib", "Y", 0.14, 1.92, cf * CFrame.new(0, ry, 0), accent, {
					Material = Enum.Material.Neon,
					CanCollide = false,
				})
				ModelKit.role(rib, "Accent")
			else
				ModelKit.cylinder(model, "BarrelRib", "Y", 0.14, 1.9, cf * CFrame.new(0, ry, 0), col, props)
			end
		end
		ModelKit.cylinder(model, "BarrelTop", "Y", 0.06, 1.5, cf * CFrame.new(0, 1.2, 0), tier.trimColor, trimProps)
		ModelKit.cylinder(model, "BarrelBung", "Y", 0.08, 0.3, cf * CFrame.new(0.4, 1.25, 0), tier.metalColor, metalProps)
		local label = ModelKit.part(model, "BarrelLabel", Vector3.new(0.7, 0.7, 0.05), cf * CFrame.new(0, 0.1, -0.92), if lv >= 4 then accent else Color3.fromRGB(235, 230, 215), {
			CanCollide = false,
		})
		if lv >= 4 then
			ModelKit.role(label, "Accent")
		end
	end
	barrel(-2.0, 2.7, BLUE, false)
	barrel(-0.1, 2.7, RED, lv == 1)
	if lv >= 3 then
		barrel(1.8, 2.7, BLUE, false)
	end

	------------------------------------------------------------ filter rack
	local rackH = if lv == 1 then 3.0 elseif lv == 2 then 3.8 else 4.4
	for _, px in { 3.75, 4.85 } do
		for _, pz in { -3.15, -0.25 } do
			ModelKit.metal(model, "RackPost", Vector3.new(0.12, rackH, 0.12), CFrame.new(px, 0.1 + rackH / 2, pz), tier)
		end
	end
	local shelfYs = if lv == 1 then { 1.5 } elseif lv == 2 then { 1.2, 2.6 } else { 1.0, 2.2, 3.4 }
	local filterColors = { Color3.fromRGB(235, 120, 25), Color3.fromRGB(45, 95, 205), Color3.fromRGB(230, 230, 235), Color3.fromRGB(235, 120, 25) }
	for _, sy in shelfYs do
		ModelKit.metal(model, "RackShelf", Vector3.new(1.2, 0.1, 3.0), CFrame.new(4.3, sy, -1.7), tier)
		local zs = if lv == 1 then { -2.5, -1.4 } else { -2.7, -2.0, -1.3, -0.6 }
		for i, fz in zs do
			ModelKit.cylinder(model, "OilFilter", "Y", 0.7, 0.55, CFrame.new(4.3, sy + 0.4, fz), filterColors[i], nil)
		end
		if lv >= 3 then
			ModelKit.led(model, "RackLED", Vector3.new(0.06, 0.06, 3.0), CFrame.new(3.7, sy - 0.05, -1.7), tier, accent)
		end
	end
	if lv == 1 then
		rust(CFrame.new(3.75, 1.0, -3.22), 0.1, 0.5)
	end

	------------------------------------------------------------ drip tray with grate
	ModelKit.metal(model, "TrayFloor", Vector3.new(3.0, 0.12, 1.6), CFrame.new(-0.8, 0.26, 0.6), tier)
	for _, tz in { -0.75, 0.75 } do
		ModelKit.metal(model, "TrayWall", Vector3.new(3.0, 0.28, 0.1), CFrame.new(-0.8, 0.46, 0.6 + tz), tier)
	end
	for _, tx in { -1.45, 1.45 } do
		ModelKit.metal(model, "TrayWall", Vector3.new(0.1, 0.28, 1.6), CFrame.new(-0.8 + tx, 0.46, 0.6), tier)
	end
	if lv == 1 then
		ModelKit.cylinder(model, "TrayDrip", "Y", 0.02, 1.0, CFrame.new(-0.8, 0.33, 0.6), OIL, { CanCollide = false })
		ModelKit.part(model, "TraySlat", Vector3.new(0.1, 0.05, 1.4), CFrame.new(-1.3, 0.5, 0.6), tier.trimColor, trimProps)
	else
		for i = -2, 2 do
			ModelKit.part(model, "TraySlat", Vector3.new(0.1, 0.05, 1.4), CFrame.new(-0.8 + i * 0.5, 0.5, 0.6), tier.trimColor, trimProps)
		end
		ModelKit.cylinder(model, "OilCan", "Y", 0.8, 0.5, CFrame.new(-1.6, 0.93, 0.6), if lv >= 4 then accent else YELLOW, nil)
		bar(model, "OilCanSpout", Vector3.new(-1.6, 1.3, 0.6), Vector3.new(-1.25, 1.6, 0.6), 0.12, 0.12, tier.metalColor, metalProps)
	end

	------------------------------------------------------------ hose reel
	local RX, RZ = 4.0, 2.4
	ModelKit.trim(model, "ReelBase", Vector3.new(1.8, 0.2, 2.8), CFrame.new(RX, 0.3, RZ), tier)
	for _, bx in { 3.3, 4.7 } do
		ModelKit.metal(model, "ReelBracket", Vector3.new(0.2, 3.1, 0.5), CFrame.new(bx, 1.95, RZ), tier)
	end
	ModelKit.cylinder(model, "ReelAxle", "X", 1.6, 0.2, CFrame.new(RX, 3.0, RZ), tier.metalColor, metalProps)
	for _, fx in { 3.5, 4.5 } do
		ModelKit.cylinder(model, "ReelFlange", "X", 0.12, 2.5, CFrame.new(fx, 3.0, RZ), tier.metalColor, metalProps)
	end
	ModelKit.cylinder(model, "ReelHose", "X", 0.8, 1.9, CFrame.new(RX, 3.0, RZ), hoseColor, nil)
	if lv >= 2 then
		for _, bx in { 3.75, 4.0, 4.25 } do
			ModelKit.cylinder(model, "ReelWrap", "X", 0.05, 1.94, CFrame.new(bx, 3.0, RZ), Color3.fromRGB(70, 72, 78), nil)
		end
		bar(model, "ReelCrank", Vector3.new(4.85, 3.0, RZ), Vector3.new(4.85, 3.0, RZ + 0.7), 0.1, 0.1, tier.metalColor, metalProps)
		ModelKit.ball(model, "CrankKnob", 0.24, CFrame.new(4.85, 3.0, RZ + 0.75), if lv >= 4 then accent else Color3.fromRGB(200, 50, 45))
	end
	polyHose(
		model,
		"ReelHoseOut",
		{ Vector3.new(RX, 2.05, 2.1), Vector3.new(3.5, 1.2, 1.5), Vector3.new(3.1, 0.3, 1.5), Vector3.new(2.95, 0.28, 1.0) },
		0.18,
		hoseColor,
		nil,
		if lv == 1 then { 3 } else nil
	)
	ModelKit.cylinder(model, "HoseNozzle", "Z", 0.7, 0.25, CFrame.new(2.95, 0.35, 0.7), if lv >= 4 then accent else YELLOW, nil)
	ModelKit.part(model, "NozzleGrip", Vector3.new(0.2, 0.45, 0.2), CFrame.new(2.95, 0.55, 0.95), tier.trimColor, trimProps)

	------------------------------------------------------------ Lv4+: overhead dispenser boom + brand banner
	if lv >= 4 then
		ModelKit.metal(model, "RackTop", Vector3.new(1.2, 0.12, 3.0), CFrame.new(4.3, 4.5, -1.7), tier)
		ModelKit.metal(model, "BoomPedestal", Vector3.new(0.4, 0.5, 0.4), CFrame.new(4.3, 4.8, -1.7), tier)
		bar(model, "DispenserBoom", Vector3.new(4.3, 5.05, -1.7), Vector3.new(0.15, 5.05, -1.7), 0.3, 0.3, tier.metalColor, metalProps)
		polyHose(
			model,
			"BoomHose",
			{ Vector3.new(0.15, 4.95, -1.7), Vector3.new(0.15, 4.2, -1.4), Vector3.new(0.15, 3.8, -1.0) },
			0.16,
			hoseColor,
			nil,
			nil
		)
		local gun = ModelKit.cylinder(model, "BoomNozzle", "Y", 0.6, 0.3, CFrame.new(0.15, 3.5, -1.0), accent, nil)
		ModelKit.role(gun, "Accent")

		for _, px in { -2.6, 2.8 } do
			ModelKit.metal(model, "BannerPost", Vector3.new(0.2, 4.4, 0.2), CFrame.new(px, 2.4, 3.85), tier)
		end
		local banner = ModelKit.part(model, "BrandBanner", Vector3.new(6.0, 1.2, 0.15), CFrame.new(0.1, 4.2, 3.85), tier.trimColor, trimProps)
		screen(banner, if lv >= 5 then "OIL X" else "OIL PRO", accent, BLACK, 0)
		ModelKit.neon(model, "BannerGlow", Vector3.new(6.0, 0.08, 0.2), CFrame.new(0.1, 3.56, 3.85), accent)
	end

	------------------------------------------------------------ Lv5: fluid pump tower + hologram
	if lv >= 5 then
		ModelKit.trim(model, "TowerBase", Vector3.new(1.0, 0.5, 1.0), CFrame.new(4.3, 0.45, 0.5), tier)
		ModelKit.body(model, "TowerColumn", Vector3.new(0.7, 5.0, 0.7), CFrame.new(4.3, 3.2, 0.5), YELLOW, tier)
		for _, ty in { 2.0, 4.2 } do
			ModelKit.neon(model, "TowerBand", Vector3.new(0.76, 0.12, 0.76), CFrame.new(4.3, ty, 0.5), accent)
		end
		local gauge = ModelKit.part(model, "TowerGauge", Vector3.new(0.5, 0.5, 0.08), CFrame.new(4.3, 3.2, 0.11), BLACK, { CanCollide = false })
		screen(gauge, "92%", accent, BLACK, 0)
		local head = ModelKit.ball(model, "TowerHead", 0.9, CFrame.new(4.3, 6.1, 0.5), accent, {
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
		})
		ModelKit.role(head, "Accent")
		ModelKit.light(head, accent, 14, 1)
		sparkles(head, accent, 10)

		local holo = ModelKit.hologram(model, CFrame.new(1.0, 7.4, -1.9), Vector2.new(3.4, 1.8), accent)
		screen(holo, "OIL 92%", accent, BLACK, 1)
	end

	return model
end
