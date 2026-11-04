--!strict
-- Paint booth built AROUND the parked car of bay 4 (docs/CONTRACT.md section 12). Footprint X -7..7, Z -11..10.
-- The car (7 wide, nose +Z) sits at the origin. Side walls stand outside X +-6.5, the back wall + filter bank is behind
-- Z 9, the roof is above Y 10.4 and the front (-Z) is open under a raised roll-up door (header at Y >= 8.55).
-- Nothing is placed inside X -3.6..3.6 between Y 0.4 and 7.5 for Z -8.5..8.5 (robot arms stay above Y 7.55).
-- Lv1 grimy booth with overspray, a boarded and a cracked window; Lv2 clean full booth; Lv3 chrome + display + lights;
-- Lv4 carbon + stripes + roof robot; Lv5 glass walls + neon pinstripes + two robots + hologram colour palette.

local ModelKit = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("ModelKit"))

local PANEL = Color3.fromRGB(230, 232, 236)
local GLASS = Color3.fromRGB(160, 205, 230)
local YELLOW = Color3.fromRGB(255, 200, 20)
local BLACK = Color3.fromRGB(8, 14, 20)
local WHITE = Color3.fromRGB(255, 255, 255)

local WALL_X = 6.75 -- wall centre (0.4 thick: 6.55 .. 6.95)
local WALL_Z0, WALL_Z1 = -10.2, 9.4
local WALL_CZ = (WALL_Z0 + WALL_Z1) / 2 -- -0.4
local WALL_LEN = WALL_Z1 - WALL_Z0 -- 19.6
local WINDOWS: { number } = { -6.2, -0.4, 5.4 }
local WIN_W = 4.4

local CAN_COLORS: { Color3 } = {
	Color3.fromRGB(205, 50, 50),
	Color3.fromRGB(50, 100, 210),
	Color3.fromRGB(60, 170, 80),
	Color3.fromRGB(240, 200, 40),
	Color3.fromRGB(235, 235, 235),
	Color3.fromRGB(240, 130, 30),
	Color3.fromRGB(150, 70, 190),
	Color3.fromRGB(40, 180, 190),
}

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

local function polyHose(parent: Instance, name: string, pts: { Vector3 }, dia: number, color: Color3, props: ModelKit.Props?)
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		ModelKit.cylinder(parent, name, "Z", (b - a).Magnitude, dia, aim((a + b) / 2, b), color, props)
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
	local flat: ModelKit.Props = { CanCollide = false, CastShadow = false }
	local hoseColor = if lv == 1 then Color3.fromRGB(48, 44, 40) else Color3.fromRGB(45, 105, 195)

	------------------------------------------------------------ side walls with windows
	for _, sx in { -1, 1 } do
		local wx = sx * WALL_X
		ModelKit.body(model, "WallLower", Vector3.new(0.4, 3.3, WALL_LEN), CFrame.new(wx, 1.75, WALL_CZ), PANEL, tier)
		ModelKit.body(model, "WallUpper", Vector3.new(0.4, 2.8, WALL_LEN), CFrame.new(wx, 9.0, WALL_CZ), PANEL, tier)
		ModelKit.trim(model, "WallSkirt", Vector3.new(0.5, 0.5, WALL_LEN), CFrame.new(wx, 0.35, WALL_CZ), tier)

		local cursor = WALL_Z0
		for wi, wz in WINDOWS do
			local w0, w1 = wz - WIN_W / 2, wz + WIN_W / 2
			ModelKit.body(model, "WallPillar", Vector3.new(0.4, 4.2, w0 - cursor), CFrame.new(wx, 5.5, (cursor + w0) / 2), PANEL, tier)
			cursor = w1

			if lv == 1 and sx == -1 and wi == 2 then
				-- boarded-up window
				ModelKit.part(model, "Boards", Vector3.new(0.15, 4.2, WIN_W), CFrame.new(sx * 6.78, 5.5, wz), Color3.fromRGB(150, 115, 75), {
					Material = Enum.Material.WoodPlanks,
				})
				ModelKit.part(
					model,
					"BoardCross",
					Vector3.new(0.2, 0.4, 5.0),
					CFrame.new(sx * 6.9, 5.5, wz) * CFrame.Angles(math.rad(25), 0, 0),
					Color3.fromRGB(120, 90, 58),
					{ Material = Enum.Material.WoodPlanks }
				)
			else
				ModelKit.part(model, "Window", Vector3.new(0.1, 4.2, WIN_W), CFrame.new(wx, 5.5, wz), GLASS, {
					Material = Enum.Material.Glass,
					Transparency = 0.5,
					Reflectance = 0.1,
				})
				if lv == 1 and sx == 1 and wi == 1 then
					ModelKit.part(
						model,
						"Crack",
						Vector3.new(0.12, 0.08, 3.6),
						CFrame.new(sx * 6.82, 5.5, wz) * CFrame.Angles(math.rad(22), 0, 0),
						Color3.fromRGB(30, 34, 38),
						flat
					)
				end
			end
			if lv >= 3 then
				ModelKit.metal(model, "SillLow", Vector3.new(0.55, 0.12, WIN_W), CFrame.new(wx, 3.46, wz), tier)
			end
		end
		ModelKit.body(model, "WallPillar", Vector3.new(0.4, 4.2, WALL_Z1 - cursor), CFrame.new(wx, 5.5, (cursor + WALL_Z1) / 2), PANEL, tier)

		-- Lv5: glowing pinstripes above and below the windows
		if lv >= 5 then
			ModelKit.neon(model, "Pinstripe", Vector3.new(0.06, 0.08, 19.4), CFrame.new(sx * 6.97, 3.25, WALL_CZ), accent)
			ModelKit.neon(model, "Pinstripe", Vector3.new(0.06, 0.08, 19.4), CFrame.new(sx * 6.97, 7.75, WALL_CZ), accent)
		end
	end

	------------------------------------------------------------ back wall + exhaust filter bank
	local backWall = ModelKit.body(model, "BackWall", Vector3.new(13.9, 10.3, 0.4), CFrame.new(0, 5.25, 9.6), PANEL, tier)
	if tier.rust then
		ModelKit.rustPatches(model, backWall, 4, 5)
	end

	local filterColor = if lv == 1 then Color3.fromRGB(92, 80, 66) elseif lv <= 3 then Color3.fromRGB(225, 222, 205) elseif lv == 4 then Color3.fromRGB(40, 40, 46) else Color3.fromRGB(30, 36, 52)
	local filterX: { number } = { -4.9, -2.5, -0.1, 2.3 }
	local filterY: { number } = { 1.35, 3.15 }
	for r, fy in filterY do
		for c, fx in filterX do
			if not (lv == 1 and (r + c) % 3 == 0) then -- Lv1: some filters are missing
				ModelKit.part(model, "ExhaustFilter", Vector3.new(2.2, 1.6, 0.25), CFrame.new(fx, fy, 9.25), filterColor, {
					Material = Enum.Material.Fabric,
				})
			end
		end
	end
	if lv >= 2 then
		for _, bx in { -6.0, -3.7, -1.3, 1.1, 3.4 } do
			ModelKit.metal(model, "FilterFrame", Vector3.new(0.1, 3.7, 0.1), CFrame.new(bx, 2.25, 9.2), tier)
		end
		for _, by in { 0.5, 2.25, 4.0 } do
			ModelKit.metal(model, "FilterFrame", Vector3.new(9.5, 0.1, 0.1), CFrame.new(-1.3, by, 9.2), tier)
		end
	end
	if lv >= 4 then
		ModelKit.led(model, "FilterLED", Vector3.new(9.5, 0.08, 0.08), CFrame.new(-1.3, 4.15, 9.2), tier, accent)
		if lv >= 5 then
			ModelKit.led(model, "FilterLED", Vector3.new(9.5, 0.08, 0.08), CFrame.new(-1.3, 0.4, 9.2), tier, accent)
		end
	end

	------------------------------------------------------------ roof, light panels, roof edge
	ModelKit.body(model, "Roof", Vector3.new(14.0, 0.4, 20.6), CFrame.new(0, 10.6, WALL_CZ), PANEL, tier)
	if lv >= 2 then
		ModelKit.trim(model, "RoofEdge", Vector3.new(14.0, 0.2, 0.4), CFrame.new(0, 10.9, -10.5), tier)
		ModelKit.trim(model, "RoofEdge", Vector3.new(14.0, 0.2, 0.4), CFrame.new(0, 10.9, 9.7), tier)
		for _, sx in { -1, 1 } do
			ModelKit.trim(model, "RoofEdge", Vector3.new(0.4, 0.2, 20.6), CFrame.new(sx * 6.8, 10.9, WALL_CZ), tier)
		end
	end
	local lampXs: { number } = { -5.1, -1.7, 1.7, 5.1 }
	for i, lx in lampXs do
		local on = lv >= 2 or i == 2 or i == 4
		local len = if lv == 1 and i == 4 then 7.5 else 15.5
		local lamp = ModelKit.part(model, "RoofLamp", Vector3.new(0.9, 0.12, len), CFrame.new(lx, 10.34, WALL_CZ + (if len < 15 then -4 else 0)), if on then WHITE else Color3.fromRGB(150, 150, 140), {
			Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic,
			CanCollide = false,
			CastShadow = false,
		})
		if lv >= 3 and (i == 2 or i == 3) then
			ModelKit.light(lamp, WHITE, 26, 1.2)
		end
	end
	if lv >= 4 then
		for _, sx in { -1, 1 } do
			ModelKit.led(model, "RoofLED", Vector3.new(0.12, 0.1, 19.8), CFrame.new(sx * 6.35, 10.3, WALL_CZ), tier, accent)
		end
	end

	------------------------------------------------------------ front frame: columns, raised roll-up door, tracks
	for _, sx in { -1, 1 } do
		ModelKit.body(model, "FrontColumn", Vector3.new(0.7, 10.3, 0.7), CFrame.new(sx * 6.65, 5.25, -10.45), PANEL, tier)
		if lv >= 2 or sx == 1 then
			ModelKit.metal(model, "DoorTrack", Vector3.new(0.25, 8.45, 0.35), CFrame.new(sx * 6.1, 4.325, -10.45), tier)
		end
	end
	local housing = ModelKit.body(model, "DoorHousing", Vector3.new(12.6, 1.6, 0.9), CFrame.new(0, 9.6, -10.45), PANEL, tier)
	if tier.rust then
		ModelKit.rustPatches(model, housing, 4, 9)
	end
	if tier.stripes then
		ModelKit.stripes(model, housing, accent)
	end
	for _, sy in { 9.1, 9.5, 9.9 } do
		ModelKit.part(model, "DoorSlat", Vector3.new(12.4, 0.08, 0.04), CFrame.new(0, sy, -10.91), tier.trimColor, trimProps)
	end
	ModelKit.trim(model, "DoorLip", Vector3.new(12.4, 0.25, 0.3), CFrame.new(0, 8.675, -10.6), tier)
	if lv >= 2 then
		ModelKit.part(model, "DoorLipStripe", Vector3.new(12.4, 0.08, 0.04), CFrame.new(0, 8.675, -10.77), YELLOW, flat)
	end
	if lv >= 5 then
		ModelKit.neon(model, "DoorGlow", Vector3.new(12.4, 0.06, 0.06), CFrame.new(0, 8.5, -10.6), accent)
	end

	-- sign / temperature display on the header
	if lv <= 2 then
		local sign = ModelKit.part(model, "WetPaintSign", Vector3.new(2.2, 0.9, 0.1), CFrame.new(4.4, 9.6, -10.95), YELLOW, flat)
		screen(sign, "WET PAINT", BLACK, YELLOW, 0)
	else
		ModelKit.part(model, "DisplayBezel", Vector3.new(2.4, 1.1, 0.08), CFrame.new(4.4, 9.6, -10.92), tier.trimColor, trimProps)
		local disp = ModelKit.part(model, "TempDisplay", Vector3.new(2.2, 0.9, 0.1), CFrame.new(4.4, 9.6, -10.95), BLACK, { CanCollide = false })
		screen(disp, "TEMP 22C", if lv >= 4 then accent else Color3.fromRGB(120, 255, 170), BLACK, 0)
	end

	------------------------------------------------------------ floor: threshold + extraction grates (all below Y 0.2)
	if lv >= 2 then
		ModelKit.part(model, "Threshold", Vector3.new(13.0, 0.04, 0.3), CFrame.new(0, 0.12, -9.8), YELLOW, flat)
		for _, sx in { -1, 1 } do
			ModelKit.part(model, "FloorGrate", Vector3.new(1.0, 0.08, 18.0), CFrame.new(sx * 5.2, 0.14, WALL_CZ - 0.1), tier.trimColor, {
				Material = Enum.Material.DiamondPlate,
				CanCollide = false,
			})
		end
	end

	------------------------------------------------------------ roof air ducts
	local function duct(dx: number, tilt: boolean)
		local base = CFrame.new(dx, 11.6, -1.0)
		if tilt then
			base = base * CFrame.Angles(math.rad(2), 0, 0)
		end
		ModelKit.cylinder(model, "RoofDuct", "Z", 16, 1.6, base, tier.metalColor, metalProps)
		ModelKit.cylinder(model, "DuctFlange", "Z", 0.2, 1.9, CFrame.new(dx, 11.6, -9.0), tier.trimColor, trimProps)
		ModelKit.ball(model, "DuctElbow", 1.7, CFrame.new(dx, 11.6, 7.0), tier.metalColor, metalProps)
		ModelKit.cylinder(model, "DuctRiser", "Y", 3.0, 1.6, CFrame.new(dx, 13.1, 7.0), tier.metalColor, metalProps)
		local hood = ModelKit.cylinder(model, "DuctHood", "Y", 0.25, 2.4, CFrame.new(dx, 14.7, 7.0), tier.trimColor, trimProps)
		for i, bz in { -7.0, -3.0, 1.0, 5.0 } do
			if not (lv == 1 and i == 2) then
				if lv >= 5 then
					local band = ModelKit.cylinder(model, "DuctBand", "Z", 0.12, 1.78, CFrame.new(dx, 11.6, bz), accent, {
						Material = Enum.Material.Neon,
						CanCollide = false,
						CastShadow = false,
					})
					ModelKit.role(band, "Accent")
				elseif lv >= 2 then
					ModelKit.cylinder(model, "DuctBand", "Z", 0.18, 1.75, CFrame.new(dx, 11.6, bz), tier.trimColor, trimProps)
				end
			end
		end
		if lv >= 5 then
			local glow = ModelKit.cylinder(model, "HoodGlow", "Y", 0.08, 2.5, CFrame.new(dx, 14.55, 7.0), accent, {
				Material = Enum.Material.Neon,
				CanCollide = false,
				CastShadow = false,
			})
			ModelKit.role(glow, "Accent")
			sparkles(hood, accent, 8)
		end
	end
	duct(-3.5, lv == 1)
	if lv >= 4 then
		duct(3.5, false)
	end
	if lv == 1 then
		for _, rz in { -4.0, 3.0 } do
			ModelKit.part(model, "Rust", Vector3.new(0.6, 0.04, 1.2), CFrame.new(-3.5, 12.41, rz), Color3.fromRGB(122, 70, 38), {
				Material = Enum.Material.CorrodedMetal,
				CanCollide = false,
				CastShadow = false,
			})
		end
	end

	------------------------------------------------------------ spray gun on a hook (left front pillar)
	ModelKit.metal(model, "GunPeg", Vector3.new(0.5, 0.1, 0.1), CFrame.new(-6.3, 5.3, -9.3), tier)
	ModelKit.cylinder(model, "GunBarrel", "Z", 1.0, 0.26, CFrame.new(-6.2, 5.1, -9.3), tier.metalColor, metalProps)
	ModelKit.part(model, "GunGrip", Vector3.new(0.2, 0.75, 0.26), CFrame.new(-6.2, 4.65, -9.7), tier.trimColor, trimProps)
	ModelKit.part(model, "GunTrigger", Vector3.new(0.06, 0.2, 0.1), CFrame.new(-6.2, 4.85, -9.5), tier.metalColor, metalProps)
	ModelKit.cylinder(model, "GunNozzle", "Z", 0.25, 0.14, CFrame.new(-6.2, 5.1, -8.7), tier.metalColor, metalProps)
	local cup = ModelKit.cylinder(model, "GunCup", "Y", 0.55, 0.5, CFrame.new(-6.2, 4.72, -8.95), if lv == 1 then Color3.fromRGB(150, 130, 120) else accent, nil)
	if lv >= 2 then
		ModelKit.role(cup, "Accent")
	end
	polyHose(
		model,
		"GunHose",
		{ Vector3.new(-6.2, 4.3, -9.7), Vector3.new(-6.0, 2.0, -9.9), Vector3.new(-5.3, 0.3, -9.4) },
		0.12,
		hoseColor,
		nil
	)

	------------------------------------------------------------ paint can shelf (back-right corner, X 3.8..6.4)
	local boardYs: { number } = if lv == 1 then { 1.6, 3.2 } else { 1.4, 2.8, 4.2 }
	for _, ux in { 3.85, 6.35 } do
		ModelKit.metal(model, "ShelfPost", Vector3.new(0.15, 5.0, 0.15), CFrame.new(ux, 2.6, 8.15), tier)
	end
	local lidProps: ModelKit.Props = if lv >= 5 then { Material = Enum.Material.Neon } else metalProps
	local canIndex = 0
	local canXs: { number } = { 4.4, 5.1, 5.8 }
	for bi, by in boardYs do
		ModelKit.metal(model, "ShelfBoard", Vector3.new(2.6, 0.12, 1.2), CFrame.new(5.1, by, 8.7), tier)
		local count = if lv == 1 then (if bi == 1 then 2 else 1) elseif lv == 2 and bi == 3 then 2 else 3
		for ci = 1, count do
			canIndex += 1
			local cx = canXs[ci]
			local color = CAN_COLORS[(canIndex - 1) % #CAN_COLORS + 1]
			ModelKit.cylinder(model, "PaintCan", "Y", 0.8, 0.65, CFrame.new(cx, by + 0.46, 8.7), color, nil)
			ModelKit.cylinder(model, "CanLid", "Y", 0.05, 0.7, CFrame.new(cx, by + 0.885, 8.7), tier.metalColor, lidProps)
		end
		if lv >= 3 then
			ModelKit.led(model, "ShelfLED", Vector3.new(2.6, 0.05, 0.05), CFrame.new(5.1, by - 0.08, 8.1), tier, accent)
		end
	end

	------------------------------------------------------------ Lv1: overspray marks
	if tier.rust then
		local rng = Random.new(7)
		local splat: { Color3 } = {
			Color3.fromRGB(200, 50, 50),
			Color3.fromRGB(50, 100, 200),
			Color3.fromRGB(60, 170, 80),
			Color3.fromRGB(240, 200, 40),
		}
		for i = 1, 6 do
			local side = if i % 2 == 0 then 1 else -1
			ModelKit.cylinder(
				model,
				"Overspray",
				"X",
				0.04,
				rng:NextNumber(0.8, 1.9),
				CFrame.new(side * 6.975, rng:NextNumber(1.0, 2.2), rng:NextNumber(-9.0, 8.0)),
				splat[(i - 1) % #splat + 1],
				flat
			)
		end
		for i = 1, 2 do
			local side = if i % 2 == 0 then 1 else -1
			ModelKit.cylinder(
				model,
				"Overspray",
				"X",
				0.04,
				rng:NextNumber(0.8, 1.4),
				CFrame.new(side * 6.525, rng:NextNumber(0.9, 2.2), rng:NextNumber(-8.0, 8.0)),
				splat[(i + 1) % #splat + 1],
				flat
			)
			ModelKit.cylinder(
				model,
				"FloorSplat",
				"Y",
				0.02,
				rng:NextNumber(1.0, 1.6),
				CFrame.new(side * 5.5, 0.11, rng:NextNumber(-8.0, 8.0)),
				splat[(i + 2) % #splat + 1],
				flat
			)
		end
	end

	------------------------------------------------------------ Lv4+: roof gantry robot(s) with spray nozzle (Y >= 7.55)
	local function robot(rz: number, flip: number)
		ModelKit.metal(model, "RobotTrolley", Vector3.new(1.4, 0.6, 1.6), CFrame.new(0, 9.75, rz), tier)
		local glowJoint = lv >= 5
		local function joint(name: string, d: number, p: Vector3)
			if glowJoint then
				local j = ModelKit.ball(model, name, d, CFrame.new(p), accent, {
					Material = Enum.Material.Neon,
					CanCollide = false,
					CastShadow = false,
				})
				ModelKit.role(j, "Accent")
			else
				ModelKit.ball(model, name, d, CFrame.new(p), tier.trimColor, trimProps)
			end
		end
		local shoulder = Vector3.new(0, 9.2, rz)
		local elbow = Vector3.new(1.7 * flip, 8.6, rz + 0.7)
		local wrist = Vector3.new(2.3 * flip, 8.0, rz + 1.6)
		joint("RobotShoulder", 0.9, shoulder)
		bar(model, "RobotUpperArm", shoulder, elbow, 0.4, 0.4, tier.body(PANEL), { Material = tier.bodyMaterial, Reflectance = tier.bodyReflectance })
		joint("RobotElbow", 0.6, elbow)
		bar(model, "RobotLowerArm", elbow, wrist, 0.3, 0.3, tier.metalColor, metalProps)
		joint("RobotWrist", 0.4, wrist)
		ModelKit.cylinder(model, "RobotNozzle", "Y", 0.3, 0.2, CFrame.new(wrist.X, 7.85, wrist.Z), tier.metalColor, metalProps)
		local tip = ModelKit.ball(model, "RobotTip", 0.18, CFrame.new(wrist.X, 7.68, wrist.Z), accent, {
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
		})
		ModelKit.role(tip, "Accent")
	end
	if lv >= 4 then
		ModelKit.metal(model, "RobotRail", Vector3.new(0.4, 0.3, 15.0), CFrame.new(0, 10.2, WALL_CZ), tier)
		robot(-3.0, 1)
	end
	if lv >= 5 then
		robot(3.0, -1)
	end

	------------------------------------------------------------ Lv5: roof fins + hologram colour palette
	if lv >= 5 then
		for _, sx in { -1, 1 } do
			ModelKit.wedge(model, "RoofFin", Vector3.new(0.6, 1.4, 2.0), CFrame.new(sx * 6.65, 11.5, -9.6), tier.trimColor, trimProps)
		end
		ModelKit.hologram(model, CFrame.new(-5.0, 7.0, -9.7), Vector2.new(2.2, 3.0), accent)
		local swatches: { Color3 } = {
			Color3.fromRGB(235, 60, 60),
			Color3.fromRGB(245, 140, 40),
			Color3.fromRGB(245, 215, 60),
			Color3.fromRGB(70, 200, 100),
			Color3.fromRGB(70, 130, 240),
			Color3.fromRGB(170, 90, 230),
		}
		for i, c in swatches do
			local col = (i - 1) % 2
			local row = (i - 1) // 2
			ModelKit.part(model, "ColorSwatch", Vector3.new(0.5, 0.5, 0.06), CFrame.new(-5.6 + col * 1.2, 6.1 + row * 0.9, -9.78), c, {
				Material = Enum.Material.Neon,
				CanCollide = false,
				CastShadow = false,
			})
		end
	end

	return model
end
