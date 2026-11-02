--!strict
-- Chassis dyno (docs/CONTRACT.md section 12, key "dyno"). Accepts any level, always styled as Lv4 (Race) with accent glow.
-- Built around the car parked at the origin (nose +Z): four roller pits flush in a diamond-plate floor plate under the
-- wheels (Z +-4.3, X +-3, everything on the plate stays at Y <= 0.35), yellow safety edges, a console tower at local
-- (10, 0, 4) with a big "HP 512" screen, and a fan on wheels near the car's nose.

local ModelKit = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("ModelKit"))

local F = 0.1 -- building floor top
local PLATE_TOP = 0.3 -- diamond plate surface

local YELLOW = Color3.fromRGB(245, 200, 30)
local BLACK = Color3.fromRGB(20, 20, 22)
local WHITE = Color3.fromRGB(245, 247, 250)

local function label(
	parent: Instance,
	content: string,
	pos: UDim2,
	size: UDim2,
	color: Color3,
	align: Enum.TextXAlignment
)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Position = pos
	t.Size = size
	t.Text = content
	t.TextColor3 = color
	t.TextScaled = true
	t.Font = Enum.Font.GothamBlack
	t.TextXAlignment = align
	t.Parent = parent
end

return function(level: number, accent: Color3, opts: { [string]: any }?): Model
	local tier = ModelKit.tier(4)
	local model = ModelKit.model("Station")
	local ledColor = tier.ledColor(accent)
	local metalProps: { [string]: any } = { Material = tier.metalMaterial, Reflectance = tier.metalReflectance }

	local function box(name: string, size: Vector3, cf: CFrame, color: Color3, props: { [string]: any }?): Part
		return ModelKit.part(model, name, size, cf, color, props)
	end

	------------------------------------------------------------ floor plate, ramp, safety edges
	ModelKit.part(
		model,
		"DynoPlate",
		Vector3.new(10, PLATE_TOP - F, 12.8),
		CFrame.new(0, (PLATE_TOP + F) / 2, 0),
		Color3.fromRGB(104, 108, 116),
		{ Material = Enum.Material.DiamondPlate, Reflectance = 0.1 }
	)
	ModelKit.wedge(
		model,
		"EntryRamp",
		Vector3.new(10, PLATE_TOP - F, 1.2),
		CFrame.new(0, (PLATE_TOP + F) / 2, -6.4 - 0.6),
		Color3.fromRGB(104, 108, 116),
		{ Material = Enum.Material.DiamondPlate }
	)
	local edgeY = PLATE_TOP + 0.01
	box("SafetyEdge", Vector3.new(10, 0.02, 0.35), CFrame.new(0, edgeY, -6.225), YELLOW, { CanCollide = false })
	box("SafetyEdge", Vector3.new(10, 0.02, 0.35), CFrame.new(0, edgeY, 6.225), YELLOW, { CanCollide = false })
	box("SafetyEdge", Vector3.new(0.35, 0.02, 12.1), CFrame.new(-4.825, edgeY, 0), YELLOW, { CanCollide = false })
	box("SafetyEdge", Vector3.new(0.35, 0.02, 12.1), CFrame.new(4.825, edgeY, 0), YELLOW, { CanCollide = false })
	for _, z in { -6.225, 6.225 } do
		for i = 1, 5 do
			box("HazardDash", Vector3.new(0.5, 0.025, 0.36), CFrame.new(-3.6 + (i - 1) * 1.8, edgeY, z), BLACK, { CanCollide = false })
		end
	end
	-- accent center lines
	ModelKit.neon(model, "PlateNeon", Vector3.new(0.1, 0.02, 11.6), CFrame.new(0, edgeY, 0), accent)
	ModelKit.neon(model, "PlateNeon", Vector3.new(9.2, 0.02, 0.1), CFrame.new(0, edgeY, 0), accent)
	-- tie-down anchors
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			ModelKit.cylinder(model, "TieDown", "Y", 0.07, 0.5, CFrame.new(sx * 4.2, edgeY + 0.02, sz * 5.4), tier.metalColor, metalProps)
		end
	end

	------------------------------------------------------------ roller pits (two rollers per wheel)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local px, pz = sx * 3, sz * 4.3
			box("RollerPit", Vector3.new(2.9, 0.01, 1.7), CFrame.new(px, PLATE_TOP + 0.005, pz), BLACK, { CanCollide = false })
			for _, dz in { -0.42, 0.42 } do
				ModelKit.cylinder(model, "Roller", "X", 2.3, 0.34, CFrame.new(px, 0.17, pz + dz), tier.metalColor, metalProps)
				for _, dx in { -0.7, 0.7 } do
					ModelKit.cylinder(
						model,
						"RollerGrip",
						"X",
						0.15,
						0.35,
						CFrame.new(px + dx, 0.175, pz + dz),
						Color3.fromRGB(40, 42, 48),
						{ Material = Enum.Material.Metal }
					)
				end
			end
		end
	end
	-- wheel chocks in front of the front wheels (flipped so the tall edge touches the tire)
	for _, sx in { -1, 1 } do
		ModelKit.wedge(
			model,
			"WheelChock",
			Vector3.new(1.0, 0.5, 0.7),
			CFrame.new(sx * 3, PLATE_TOP + 0.25, 5.6) * CFrame.Angles(0, math.pi, 0),
			YELLOW,
			{ CanCollide = false }
		)
	end

	------------------------------------------------------------ console tower at local (10, 0, 4), angled toward the car
	local ccf = CFrame.new(10, 0, 4) * CFrame.Angles(0, math.rad(25), 0)
	local function C(name: string, size: Vector3, lx: number, ly: number, lz: number, color: Color3, props: { [string]: any }?): Part
		return ModelKit.part(model, name, size, ccf * CFrame.new(lx, ly, lz), color, props)
	end

	ModelKit.trim(model, "ConsolePlinth", Vector3.new(3.0, 0.5, 2.4), ccf * CFrame.new(0, 0.35, 0), tier)
	local cabinet = ModelKit.body(model, "ConsoleCabinet", Vector3.new(2.4, 2.4, 1.8), ccf * CFrame.new(0, 1.8, 0), accent, tier)
	ModelKit.stripes(model, cabinet, accent)
	for i = 1, 4 do
		C("Vent", Vector3.new(1.4, 0.07, 0.04), 0, 0.95 + i * 0.22, -0.93, BLACK, { CanCollide = false })
	end
	for _, s in { -1, 1 } do
		local strip = ModelKit.neon(model, "ConsoleNeon", Vector3.new(0.07, 2.2, 0.07), ccf * CFrame.new(s * 1.2, 1.8, -0.9), accent)
		strip.Name = "ConsoleNeon"
	end
	local glow = ModelKit.neon(model, "ConsoleUnderglow", Vector3.new(2.8, 0.06, 2.2), ccf * CFrame.new(0, 0.13, 0), accent)
	ModelKit.light(glow, ledColor, 12, 1.2)

	-- sloped control panel (wedge: low edge in front, rising toward the back)
	ModelKit.wedge(model, "ControlPanel", Vector3.new(2.4, 0.9, 1.4), ccf * CFrame.new(0, 3.45, -0.1), BLACK, { Material = Enum.Material.SmoothPlastic, Reflectance = 0.15 })
	local slope = math.atan2(0.9, 1.4)
	local function onSlope(x: number, t: number, lift: number): CFrame
		return ccf * CFrame.new(x, 3.0 + 0.9 * t, -0.8 + 1.4 * t) * CFrame.Angles(-slope, 0, 0) * CFrame.new(0, lift, 0)
	end
	local buttonColors = {
		Color3.fromRGB(80, 255, 120),
		Color3.fromRGB(255, 200, 40),
		Color3.fromRGB(80, 170, 255),
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(80, 255, 120),
		Color3.fromRGB(255, 200, 40),
	}
	for i, bc in buttonColors do
		local col = (i - 1) % 3
		local row = (i - 1) // 3
		ModelKit.cylinder(
			model,
			"Button",
			"Y",
			0.08,
			0.2,
			onSlope(-0.35 + col * 0.35, 0.3 + row * 0.25, 0.05),
			bc,
			{ Material = Enum.Material.Neon, CanCollide = false }
		)
	end
	ModelKit.cylinder(model, "DialKnob", "Y", 0.16, 0.45, onSlope(0.85, 0.5, 0.08), Color3.fromRGB(60, 62, 70), metalProps)
	ModelKit.cylinder(model, "EmergencyStop", "Y", 0.16, 0.4, onSlope(-0.85, 0.45, 0.08), Color3.fromRGB(220, 40, 40), { Material = Enum.Material.SmoothPlastic })

	-- neck + screen housing
	C("ConsoleNeck", Vector3.new(1.2, 1.4, 0.7), 0, 4.45, 0.3, tier.trimColor, { Material = tier.trimMaterial })
	local housing = C("ScreenHousing", Vector3.new(3.6, 2.3, 0.4), 0, 6.4, 0.2, Color3.fromRGB(16, 16, 20), { Reflectance = 0.2 })
	housing.Name = "ScreenHousing"
	ModelKit.wedge(model, "ScreenVisor", Vector3.new(3.7, 0.35, 0.6), ccf * CFrame.new(0, 7.72, -0.05), BLACK, {})
	local screen = C("Screen", Vector3.new(3.2, 1.9, 0.04), 0, 6.4, -0.02, Color3.fromRGB(8, 14, 20), { CanCollide = false })
	local corners = { { 3.4, 0.07, 0, 7.37 }, { 3.4, 0.07, 0, 5.43 }, { 0.07, 1.98, -1.7, 6.4 }, { 0.07, 1.98, 1.7, 6.4 } }
	for _, c in corners do
		ModelKit.neon(model, "ScreenNeon", Vector3.new(c[1], c[2], 0.07), ccf * CFrame.new(c[3], c[4], -0.04), accent)
	end
	local beacon = ModelKit.cylinder(model, "Beacon", "Y", 0.3, 0.3, ccf * CFrame.new(1.5, 7.95, 0.2), accent, { Material = Enum.Material.Neon, CanCollide = false })
	ModelKit.role(beacon, "Accent")
	ModelKit.light(beacon, accent, 10, 1)

	-- screen content: "HP 512"
	local gui = Instance.new("SurfaceGui")
	gui.Name = "ScreenGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 100
	gui.LightInfluence = 0
	gui.Brightness = 1.3
	gui.Parent = screen
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(8, 14, 20)
	bg.BorderSizePixel = 0
	bg.Parent = gui
	label(bg, "HP 512", UDim2.fromScale(0.05, 0.04), UDim2.fromScale(0.9, 0.52), accent, Enum.TextXAlignment.Center)
	label(bg, "TQ 480", UDim2.fromScale(0.05, 0.58), UDim2.fromScale(0.42, 0.18), WHITE, Enum.TextXAlignment.Left)
	label(bg, "7200 RPM", UDim2.fromScale(0.5, 0.58), UDim2.fromScale(0.45, 0.18), WHITE, Enum.TextXAlignment.Right)
	local meter = Instance.new("Frame")
	meter.Position = UDim2.fromScale(0.05, 0.8)
	meter.Size = UDim2.fromScale(0.9, 0.13)
	meter.BackgroundTransparency = 1
	meter.Parent = bg
	for i = 1, 12 do
		local seg = Instance.new("Frame")
		seg.Position = UDim2.fromScale((i - 1) / 12, 0)
		seg.Size = UDim2.fromScale(1 / 12 - 0.01, 1)
		seg.BorderSizePixel = 0
		seg.BackgroundColor3 = Color3.fromRGB(70, 230, 120):Lerp(Color3.fromRGB(255, 60, 50), (i - 1) / 11)
		seg.Parent = meter
	end

	-- cable conduit from the tower to the plate
	for i = 0, 2 do
		ModelKit.cylinder(
			model,
			"Conduit",
			"X",
			1.1,
			0.22,
			CFrame.new(5.5 + i * 1.2, F + 0.12, 3.2),
			Color3.fromRGB(40, 42, 48),
			{ Material = Enum.Material.Metal, CanCollide = false }
		)
		ModelKit.part(model, "ConduitClamp", Vector3.new(0.12, 0.3, 0.3), CFrame.new(5.5 + i * 1.2 + 0.55, F + 0.14, 3.2), tier.metalColor, metalProps)
	end

	------------------------------------------------------------ fan on wheels (near the car's nose, blowing toward the car)
	local fcf = CFrame.new(6.9, 0, 6.2) * CFrame.Angles(0, math.rad(60), 0)
	local function Fp(name: string, size: Vector3, local_cf: CFrame, color: Color3, props: { [string]: any }?): Part
		return ModelKit.part(model, name, size, fcf * local_cf, color, props)
	end
	for _, sx in { -1, 1 } do
		Fp("FanRail", Vector3.new(0.25, 0.15, 1.7), CFrame.new(sx * 0.8, 0.4, 0), tier.metalColor, metalProps)
		for _, sz in { -1, 1 } do
			ModelKit.cylinder(model, "FanWheel", "X", 0.14, 0.3, fcf * CFrame.new(sx * 0.8, F + 0.15, sz * 0.7), Color3.fromRGB(28, 28, 32), {})
		end
	end
	Fp("FanCross", Vector3.new(1.6, 0.15, 0.2), CFrame.new(0, 0.4, 0), tier.metalColor, metalProps)
	ModelKit.cylinder(model, "FanPole", "Y", 2.0, 0.22, fcf * CFrame.new(0, 1.45, 0), tier.metalColor, metalProps)
	Fp("FanYokeBar", Vector3.new(2.4, 0.1, 0.14), CFrame.new(0, 2.45, 0), tier.metalColor, metalProps)
	local headY = 3.5
	for _, sx in { -1, 1 } do
		Fp("FanYokeArm", Vector3.new(0.1, 1.1, 0.12), CFrame.new(sx * 1.22, 2.95, 0), tier.metalColor, metalProps)
		Fp("FanShroudSide", Vector3.new(0.14, 2.0, 0.55), CFrame.new(sx * 1.08, headY, 0), BLACK, {})
		Fp("FanShroudEdge", Vector3.new(2.3, 0.14, 0.55), CFrame.new(0, headY + sx * 1.07, 0), BLACK, {})
	end
	local guard = ModelKit.cylinder(model, "FanGuard", "Z", 0.04, 2.0, fcf * CFrame.new(0, headY, -0.27), tier.metalColor, {
		Material = Enum.Material.Metal,
		Transparency = 0.65,
		CanCollide = false,
	})
	guard.Reflectance = 0.3
	Fp("FanGuardBar", Vector3.new(2.0, 0.05, 0.05), CFrame.new(0, headY, -0.29), tier.metalColor, metalProps)
	Fp("FanGuardBar", Vector3.new(0.05, 2.0, 0.05), CFrame.new(0, headY, -0.29), tier.metalColor, metalProps)
	for k = 0, 3 do
		local blade = Fp(
			"FanBlade",
			Vector3.new(0.4, 0.9, 0.04),
			CFrame.new(0, headY, -0.05) * CFrame.Angles(0, 0, math.rad(k * 90)) * CFrame.new(0, 0.55, 0) * CFrame.Angles(0, math.rad(20), 0),
			accent,
			{ CanCollide = false }
		)
		ModelKit.role(blade, "Accent")
	end
	ModelKit.cylinder(model, "FanMotor", "Z", 0.5, 0.6, fcf * CFrame.new(0, headY, 0.2), Color3.fromRGB(50, 52, 60), { Material = Enum.Material.Metal })
	local hub = ModelKit.ball(model, "FanHub", 0.4, fcf * CFrame.new(0, headY, -0.1), accent, { Material = Enum.Material.Neon, CanCollide = false })
	ModelKit.role(hub, "Accent")

	return model
end
