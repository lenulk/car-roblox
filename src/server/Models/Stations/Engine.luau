--!strict
-- Engine workbench (docs/CONTRACT.md section 12, key "engine"). Accepts any level, always styled as Lv3 (Pro).
-- Footprint X -5..5, Z -1.5..2.5; the front faces -Z. Left: rolling tool chest. Middle: engine block on a rotating stand
-- (crank axis along Z, pulleys + belt face the player). Right: sturdy workbench with pegboard, vise, tray and a lamp.

local ModelKit = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("ModelKit"))

local F = 0.1 -- building floor top

return function(level: number, accent: Color3, opts: { [string]: any }?): Model
	local tier = ModelKit.tier(3)
	local model = ModelKit.model("Station")
	local ledColor = tier.ledColor(accent)
	local dark = Color3.fromRGB(34, 36, 42)
	local steel = Color3.fromRGB(96, 104, 116)
	local rubber = Color3.fromRGB(28, 28, 32)
	local chromeProps: { [string]: any } = { Material = tier.metalMaterial, Reflectance = tier.metalReflectance }

	local function box(name: string, size: Vector3, pos: Vector3, color: Color3, props: { [string]: any }?): Part
		return ModelKit.part(model, name, size, CFrame.new(pos), color, props)
	end
	local function chrome(name: string, size: Vector3, pos: Vector3): Part
		return ModelKit.metal(model, name, size, CFrame.new(pos), tier)
	end
	local function cyl(name: string, axis: string, length: number, diameter: number, pos: Vector3, color: Color3, props: { [string]: any }?): Part
		return ModelKit.cylinder(model, name, axis, length, diameter, CFrame.new(pos), color, props)
	end

	------------------------------------------------------------ rolling tool chest (left)
	local chestX, chestZ = -3.8, 1.6
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			cyl("ChestWheel", "X", 0.18, 0.4, Vector3.new(chestX + sx * 1.0, F + 0.2, chestZ + sz * 0.6), rubber, {})
			box("ChestFork", Vector3.new(0.3, 0.22, 0.3), Vector3.new(chestX + sx * 1.0, F + 0.5, chestZ + sz * 0.6), tier.metalColor, chromeProps)
		end
	end
	local chest = ModelKit.body(model, "ToolChest", Vector3.new(2.4, 3.1, 1.8), CFrame.new(chestX, 2.2, chestZ), accent, tier)
	ModelKit.role(chest, "Accent")
	ModelKit.metal(model, "ChestLid", Vector3.new(2.5, 0.14, 1.9), CFrame.new(chestX, 3.82, chestZ), tier)
	for i = 1, 5 do
		local y = 0.95 + (i - 1) * 0.58
		box("DrawerFront", Vector3.new(2.1, 0.5, 0.05), Vector3.new(chestX, y + 0.25, chestZ - 0.92), Color3.fromRGB(240, 244, 250), { Reflectance = 0.12 })
		cyl("DrawerHandle", "X", 1.1, 0.08, Vector3.new(chestX, y + 0.32, chestZ - 1.0), tier.metalColor, chromeProps)
	end
	ModelKit.neon(model, "ChestAccentLED", Vector3.new(2.3, 0.06, 0.04), CFrame.new(chestX, 3.7, chestZ - 0.93), accent)
	-- side handle
	for _, sx in { -1, 1 } do
		cyl("ChestSideBar", "Z", 1.0, 0.08, Vector3.new(chestX + sx * 1.3, 3.0, chestZ), tier.metalColor, chromeProps)
	end
	-- hammer resting on the chest
	cyl("HammerHandle", "X", 1.1, 0.12, Vector3.new(chestX + 0.3, 3.95, chestZ - 0.3), Color3.fromRGB(150, 100, 56), { Material = Enum.Material.Wood })
	box("HammerHead", Vector3.new(0.5, 0.3, 0.3), Vector3.new(chestX - 0.35, 4.03, chestZ - 0.3), steel, chromeProps)

	------------------------------------------------------------ engine stand (middle)
	local cx = -0.6
	-- drip pan under the engine
	box("DripPan", Vector3.new(2.2, 0.1, 2.0), Vector3.new(cx, F + 0.05, -0.1), Color3.fromRGB(70, 74, 84), { Material = Enum.Material.Metal })
	cyl("OilPuddle", "Y", 0.02, 0.9, Vector3.new(cx + 0.2, F + 0.11, -0.3), Color3.fromRGB(34, 26, 14), { Material = Enum.Material.Glass, Reflectance = 0.2, CanCollide = false })
	-- cross base with casters
	chrome("StandLegX", Vector3.new(2.8, 0.18, 0.3), Vector3.new(cx, 0.42, 1.1))
	chrome("StandLegZ", Vector3.new(0.3, 0.18, 2.8), Vector3.new(cx, 0.42, 1.1))
	for _, p in { Vector3.new(cx - 1.4, 0, 1.1), Vector3.new(cx + 1.4, 0, 1.1), Vector3.new(cx, 0, -0.15), Vector3.new(cx, 0, 2.35) } do
		cyl("StandWheel", "X", 0.14, 0.3, Vector3.new(p.X, F + 0.15, p.Z), rubber, {})
	end
	cyl("StandColumn", "Y", 1.9, 0.5, Vector3.new(cx, 1.45, 1.9), tier.metalColor, chromeProps)
	box("StandCollar", Vector3.new(0.7, 0.2, 0.7), Vector3.new(cx, 0.6, 1.9), dark, nil)
	-- support wedge at the column foot (right angle toward the column, bottom)
	ModelKit.wedge(model, "StandGusset", Vector3.new(0.2, 0.7, 0.7), CFrame.new(cx, 0.86, 1.3), dark, {})
	cyl("StandHub", "Z", 0.3, 0.6, Vector3.new(cx, 2.5, 1.75), tier.metalColor, chromeProps)
	-- rotation hand wheel behind the column
	cyl("TurnRod", "Z", 0.5, 0.15, Vector3.new(cx, 2.5, 2.1), tier.metalColor, chromeProps)
	cyl("TurnWheel", "Z", 0.1, 0.9, Vector3.new(cx, 2.5, 2.3), dark, {})
	for _, deg in { 0, 90 } do
		ModelKit.part(model, "TurnSpoke", Vector3.new(0.8, 0.08, 0.06), CFrame.new(cx, 2.5, 2.37) * CFrame.Angles(0, 0, math.rad(deg)), tier.metalColor, chromeProps)
	end
	ModelKit.ball(model, "TurnKnob", 0.22, CFrame.new(cx + 0.4, 2.5, 2.4), Color3.fromRGB(230, 60, 50), {})

	------------------------------------------------------------ engine block
	local ez = 0.2 -- block center Z (spans -0.95 .. 1.35)
	box("EngineBlock", Vector3.new(1.7, 1.2, 2.3), Vector3.new(cx, 2.3, ez), steel, { Material = Enum.Material.Metal, Reflectance = 0.25 })
	box("OilPan", Vector3.new(1.4, 0.5, 1.9), Vector3.new(cx, 1.45, ez + 0.1), Color3.fromRGB(58, 62, 70), { Material = Enum.Material.Metal, Reflectance = 0.2 })
	ModelKit.wedge(model, "OilPanRamp", Vector3.new(1.4, 0.35, 0.45), CFrame.new(cx, 1.55, ez - 1.07) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(58, 62, 70), { Material = Enum.Material.Metal })
	ModelKit.ball(model, "DrainBolt", 0.2, CFrame.new(cx, 1.17, ez + 0.5), tier.metalColor, chromeProps)
	chrome("CylinderHead", Vector3.new(1.75, 0.4, 2.3), Vector3.new(cx, 3.1, ez))
	local cover = ModelKit.body(model, "ValveCover", Vector3.new(1.3, 0.3, 2.0), CFrame.new(cx, 3.45, ez), accent, tier)
	ModelKit.role(cover, "Accent")
	cyl("OilCap", "Y", 0.16, 0.34, Vector3.new(cx, 3.68, ez - 0.7), tier.metalColor, chromeProps)
	for i = 1, 4 do
		local z = ez - 0.75 + (i - 1) * 0.5
		box("IgnitionCoil", Vector3.new(0.28, 0.36, 0.28), Vector3.new(cx, 3.8, z), dark, nil)
		local capPart = cyl("CoilCap", "Y", 0.1, 0.2, Vector3.new(cx, 4.03, z), accent, { Material = Enum.Material.Neon, CanCollide = false })
		ModelKit.role(capPart, "Accent")
		cyl("SparkPlugWire", "X", 0.5, 0.05, Vector3.new(cx + 0.35, 3.7, z), rubber, {})
	end
	-- intake manifold (left) and exhaust manifold (right)
	cyl("IntakePlenum", "Z", 2.0, 0.5, Vector3.new(cx - 1.35, 3.2, ez), tier.metalColor, chromeProps)
	for i = 1, 4 do
		cyl("IntakeRunner", "X", 0.6, 0.26, Vector3.new(cx - 1.0, 3.1, ez - 0.75 + (i - 1) * 0.5), tier.metalColor, chromeProps)
	end
	cyl("ExhaustCollector", "Z", 2.0, 0.4, Vector3.new(cx + 1.2, 2.95, ez), Color3.fromRGB(150, 90, 60), { Material = Enum.Material.Metal })
	for i = 1, 4 do
		cyl("ExhaustRunner", "X", 0.5, 0.22, Vector3.new(cx + 0.95, 3.05, ez - 0.75 + (i - 1) * 0.5), Color3.fromRGB(150, 90, 60), { Material = Enum.Material.Metal })
	end
	-- oil filter, dipstick
	cyl("OilFilter", "X", 0.6, 0.5, Vector3.new(cx + 1.15, 1.95, ez - 0.35), Color3.fromRGB(240, 130, 30), {})
	cyl("Dipstick", "Y", 1.2, 0.05, Vector3.new(cx - 0.75, 3.1, ez + 1.0), Color3.fromRGB(230, 200, 60), {})
	ModelKit.ball(model, "DipstickRing", 0.16, CFrame.new(cx - 0.75, 3.75, ez + 1.0), Color3.fromRGB(230, 200, 60), {})
	-- rear flange / bell housing
	cyl("RearPlate", "Z", 0.15, 1.3, Vector3.new(cx, 2.5, 1.43), steel, { Material = Enum.Material.Metal })
	cyl("Flywheel", "Z", 0.25, 1.0, Vector3.new(cx, 2.5, 1.58), tier.metalColor, chromeProps)

	-- front cover, pulleys and belt (facing -Z)
	box("TimingCover", Vector3.new(1.6, 1.5, 0.12), Vector3.new(cx, 2.45, -1.01), Color3.fromRGB(58, 62, 70), nil)
	local fz = -1.12
	local pulleys = {
		{ cx, 1.95, 0.7 },
		{ cx - 0.45, 2.75, 0.45 },
		{ cx + 0.45, 2.75, 0.35 },
	}
	for i, p in pulleys do
		cyl("Pulley", "Z", 0.12, p[3], Vector3.new(p[1], p[2], fz), tier.metalColor, chromeProps)
		cyl("PulleyBolt", "Z", 0.14, 0.14 + i * 0.01, Vector3.new(p[1], p[2], fz - 0.02), dark, {})
	end
	for i = 1, #pulleys do
		local a, b = pulleys[i], pulleys[i % #pulleys + 1]
		local dx, dy = b[1] - a[1], b[2] - a[2]
		local len = math.sqrt(dx * dx + dy * dy)
		ModelKit.part(
			model,
			"Belt",
			Vector3.new(len, 0.05, 0.14),
			CFrame.new((a[1] + b[1]) / 2, (a[2] + b[2]) / 2, fz) * CFrame.Angles(0, 0, math.atan2(dy, dx)),
			rubber,
			{ CanCollide = false }
		)
	end

	------------------------------------------------------------ workbench (right)
	local bx, bz = 3.2, 1.65
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			chrome("BenchLeg", Vector3.new(0.3, 2.7, 0.3), Vector3.new(bx + sx * 1.65, F + 1.35, bz + sz * 0.62))
		end
		chrome("BenchSideRail", Vector3.new(0.12, 0.3, 1.5), Vector3.new(bx + sx * 1.65, 2.5, bz))
	end
	box("BenchTop", Vector3.new(3.8, 0.3, 1.7), Vector3.new(bx, 2.95, bz), Color3.fromRGB(176, 130, 80), { Material = Enum.Material.Wood })
	chrome("BenchTopEdge", Vector3.new(3.84, 0.06, 0.06), Vector3.new(bx, 3.0, bz - 0.87))
	chrome("BenchLowerShelf", Vector3.new(3.4, 0.12, 1.3), Vector3.new(bx, 0.85, bz))
	ModelKit.neon(model, "BenchAccentLED", Vector3.new(3.5, 0.06, 0.04), CFrame.new(bx, 2.72, bz - 0.88), accent)
	-- items on the lower shelf
	cyl("OilBarrel", "Y", 0.9, 0.7, Vector3.new(bx - 1.0, 1.36, bz), Color3.fromRGB(40, 90, 200), { Material = Enum.Material.Metal })
	cyl("OilBarrelBand", "Y", 0.1, 0.74, Vector3.new(bx - 1.0, 1.36, bz), Color3.fromRGB(240, 240, 245), {})
	box("PartsCrate", Vector3.new(1.2, 0.6, 0.9), Vector3.new(bx + 0.7, 1.22, bz), Color3.fromRGB(150, 110, 70), { Material = Enum.Material.WoodPlanks })

	-- pegboard with hanging tools
	box("Pegboard", Vector3.new(3.8, 2.1, 0.1), Vector3.new(bx, 4.2, 2.45), Color3.fromRGB(70, 74, 84), nil)
	local toolColors = { Color3.fromRGB(235, 70, 60), Color3.fromRGB(250, 200, 50), Color3.fromRGB(60, 150, 240), Color3.fromRGB(80, 200, 110), Color3.fromRGB(240, 240, 245) }
	for i = 1, 5 do
		local x = bx - 1.5 + (i - 1) * 0.75
		box("ToolShaft", Vector3.new(0.14, 1.0 + (i % 2) * 0.3, 0.08), Vector3.new(x, 4.2, 2.36), tier.metalColor, chromeProps)
		cyl("ToolHead", "Z", 0.1, 0.38, Vector3.new(x, 4.75 + (i % 2) * 0.15, 2.36), toolColors[i], {})
		box("ToolGrip", Vector3.new(0.18, 0.4, 0.1), Vector3.new(x, 3.8 - (i % 2) * 0.1, 2.36), toolColors[i], nil)
	end
	local pegLed = ModelKit.led(model, "PegLED", Vector3.new(3.6, 0.05, 0.05), CFrame.new(bx, 3.2, 2.3), tier, accent)
	if pegLed then
		ModelKit.light(pegLed, ledColor, 12, 1)
	end

	-- vise
	box("ViseBase", Vector3.new(0.8, 0.3, 0.6), Vector3.new(bx + 1.35, 3.25, bz + 0.5), Color3.fromRGB(60, 90, 160), { Material = Enum.Material.Metal })
	box("ViseJaw", Vector3.new(0.7, 0.35, 0.18), Vector3.new(bx + 1.35, 3.55, bz + 0.38), steel, chromeProps)
	box("ViseJawMove", Vector3.new(0.7, 0.35, 0.18), Vector3.new(bx + 1.35, 3.55, bz + 0.1), steel, chromeProps)
	cyl("ViseScrew", "Z", 0.7, 0.1, Vector3.new(bx + 1.35, 3.45, bz - 0.15), tier.metalColor, chromeProps)
	cyl("ViseHandle", "X", 0.6, 0.07, Vector3.new(bx + 1.35, 3.45, bz - 0.5), dark, {})

	-- parts tray with bolts
	box("TrayBottom", Vector3.new(1.3, 0.06, 0.8), Vector3.new(bx - 0.2, 3.13, bz - 0.2), tier.trimColor, nil)
	for _, w in { { 1.3, 0.06, 0, -0.4 }, { 1.3, 0.06, 0, 0.4 }, { 0.06, 0.8, -0.65, 0 }, { 0.06, 0.8, 0.65, 0 } } do
		-- (w1,w2) = footprint of the wall, (w3,w4) = offset from the tray center
		box("TrayWall", Vector3.new(w[1], 0.16, w[2]), Vector3.new(bx - 0.2 + w[3], 3.2, bz - 0.2 + w[4]), tier.trimColor, nil)
	end
	for i = 1, 4 do
		ModelKit.ball(
			model,
			"Bolt",
			0.14,
			CFrame.new(bx - 0.6 + i * 0.22, 3.2, bz - 0.2 + ((i % 2) - 0.5) * 0.3),
			tier.metalColor,
			chromeProps
		)
	end
	-- torque wrench lying on the bench
	cyl("TorqueWrench", "X", 1.4, 0.1, Vector3.new(bx - 1.0, 3.15, bz + 0.4), tier.metalColor, chromeProps)
	cyl("TorqueGrip", "X", 0.6, 0.16, Vector3.new(bx - 1.45, 3.15, bz + 0.4), Color3.fromRGB(235, 70, 60), {})
	cyl("TorqueHead", "Y", 0.14, 0.32, Vector3.new(bx - 0.3, 3.15, bz + 0.4), tier.metalColor, chromeProps)

	-- articulated desk lamp
	local lx, lz = bx - 1.6, bz + 0.55
	cyl("LampBase", "Y", 0.12, 0.6, Vector3.new(lx, 3.16, lz), dark, {})
	cyl("LampArm1", "Y", 1.1, 0.07, Vector3.new(lx, 3.7, lz), tier.metalColor, chromeProps)
	ModelKit.ball(model, "LampJoint", 0.16, CFrame.new(lx, 4.25, lz), tier.metalColor, chromeProps)
	ModelKit.cylinder(model, "LampArm2", "X", 0.9, 0.07, CFrame.new(lx + 0.4, 4.35, lz) * CFrame.Angles(0, 0, math.rad(12)), tier.metalColor, chromeProps)
	ModelKit.wedge(model, "LampShade", Vector3.new(0.5, 0.35, 0.5), CFrame.new(lx + 0.9, 4.2, lz) * CFrame.Angles(0, math.pi, 0), accent, {})
	local bulb = ModelKit.ball(model, "LampBulb", 0.22, CFrame.new(lx + 0.9, 4.1, lz), Color3.fromRGB(255, 236, 190), { Material = Enum.Material.Neon, CanCollide = false })
	ModelKit.light(bulb, Color3.fromRGB(255, 236, 200), 14, 1.4)

	return model
end
