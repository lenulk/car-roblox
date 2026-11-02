--!strict
-- Diagnostics computer cart (docs/CONTRACT.md section 12, key "diagnostics"). Accepts any level, always styled as Lv3 (Pro).
-- Footprint X -2..2, Z -1.5..1.5. The screen faces -Z. Rolling cart with monitor, keyboard, OBD box + scanner cable,
-- drawer unit, push handle and accent LEDs.

local ModelKit = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("ModelKit"))

local F = 0.1 -- building floor top
local TRAY_TOP = 2.8 -- top surface of the upper tray

local function bar(parent: Instance, idx: number, count: number, h: number, color: Color3)
	local f = Instance.new("Frame")
	f.Name = "Bar" .. idx
	f.AnchorPoint = Vector2.new(0, 1)
	f.Position = UDim2.fromScale((idx - 1) / count + 0.008, 1)
	f.Size = UDim2.fromScale(1 / count - 0.016, h)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Parent = parent
end

local function text(parent: Instance, content: string, pos: UDim2, size: UDim2, color: Color3, xAlign: Enum.TextXAlignment)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Position = pos
	t.Size = size
	t.Text = content
	t.TextColor3 = color
	t.TextScaled = true
	t.Font = Enum.Font.GothamBold
	t.TextXAlignment = xAlign
	t.Parent = parent
end

return function(level: number, accent: Color3, opts: { [string]: any }?): Model
	local tier = ModelKit.tier(3) -- level is ignored on purpose: one Lv3-quality object
	local model = ModelKit.model("Station")
	local ledColor = tier.ledColor(accent)
	local dark = Color3.fromRGB(26, 28, 34)
	local rubber = Color3.fromRGB(30, 30, 34)

	------------------------------------------------------------ chassis
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local x, z = sx * 1.55, sz * 1.05
			-- caster: swivel plate, two fork plates, wheel
			ModelKit.metal(model, "CasterPlate", Vector3.new(0.4, 0.06, 0.4), CFrame.new(x, 0.57, z), tier)
			for _, fx in { -1, 1 } do
				ModelKit.metal(model, "CasterFork", Vector3.new(0.04, 0.3, 0.26), CFrame.new(x + fx * 0.12, 0.41, z), tier)
			end
			ModelKit.cylinder(model, "Wheel", "X", 0.16, 0.44, CFrame.new(x, F + 0.22, z), rubber, { Material = Enum.Material.Plastic })
			-- corner post
			ModelKit.metal(model, "Post", Vector3.new(0.16, 2.0, 0.16), CFrame.new(sx * 1.65, 1.6, sz * 1.05), tier)
		end
	end

	-- lower tray and upper tray
	ModelKit.metal(model, "LowerTray", Vector3.new(3.6, 0.15, 2.4), CFrame.new(0, 1.0, 0), tier)
	ModelKit.metal(model, "LowerLip", Vector3.new(3.6, 0.12, 0.06), CFrame.new(0, 1.12, -1.2), tier)
	ModelKit.metal(model, "LowerLip", Vector3.new(3.6, 0.12, 0.06), CFrame.new(0, 1.12, 1.2), tier)
	ModelKit.body(model, "UpperTray", Vector3.new(3.9, 0.2, 2.8), CFrame.new(0, 2.7, 0), accent, tier)
	ModelKit.metal(model, "UpperLip", Vector3.new(3.9, 0.14, 0.06), CFrame.new(0, 2.84, -1.4), tier)
	ModelKit.metal(model, "UpperLip", Vector3.new(3.9, 0.14, 0.06), CFrame.new(0, 2.84, 1.4), tier)
	for _, sx in { -1, 1 } do
		ModelKit.metal(model, "UpperLip", Vector3.new(0.06, 0.14, 2.8), CFrame.new(sx * 1.95, 2.84, 0), tier)
	end

	-- accent LED lip on the front of the cart + white underglow
	ModelKit.neon(model, "AccentLED", Vector3.new(3.7, 0.07, 0.06), CFrame.new(0, 2.6, -1.43), accent)
	local under = ModelKit.led(model, "UnderLED", Vector3.new(3.2, 0.05, 2.0), CFrame.new(0, 0.9, 0), tier, accent)
	if under then
		ModelKit.light(under, ledColor, 8, 0.8)
	end

	-- push handle at the back
	for _, sx in { -1, 1 } do
		ModelKit.cylinder(model, "HandlePost", "Y", 1.0, 0.13, CFrame.new(sx * 1.5, 3.3, 1.3), tier.metalColor, {
			Material = tier.metalMaterial,
			Reflectance = tier.metalReflectance,
		})
	end
	ModelKit.cylinder(model, "HandleBar", "X", 3.1, 0.15, CFrame.new(0, 3.82, 1.3), rubber, {})

	------------------------------------------------------------ drawer unit under the tray
	ModelKit.body(model, "DrawerUnit", Vector3.new(1.3, 0.9, 1.8), CFrame.new(-0.75, 2.15, 0), accent, tier)
	for _, y in { 2.33, 1.93 } do
		ModelKit.part(
			model,
			"DrawerFront",
			Vector3.new(1.15, 0.34, 0.04),
			CFrame.new(-0.75, y, -0.92),
			Color3.fromRGB(240, 244, 250),
			{ Reflectance = 0.15 }
		)
		ModelKit.cylinder(model, "DrawerHandle", "X", 0.5, 0.07, CFrame.new(-0.75, y, -0.98), tier.metalColor, {
			Material = tier.metalMaterial,
			Reflectance = tier.metalReflectance,
		})
	end

	------------------------------------------------------------ monitor on a stand
	ModelKit.cylinder(model, "MonitorFoot", "Y", 0.1, 1.1, CFrame.new(0, TRAY_TOP + 0.05, 0.85), tier.trimColor, {})
	ModelKit.cylinder(model, "MonitorColumn", "Y", 1.4, 0.2, CFrame.new(0, TRAY_TOP + 0.8, 0.85), tier.metalColor, {
		Material = tier.metalMaterial,
		Reflectance = tier.metalReflectance,
	})
	ModelKit.part(model, "MonitorBracket", Vector3.new(0.5, 0.7, 0.2), CFrame.new(0, 4.2, 0.71), dark, {})
	ModelKit.part(model, "MonitorFrame", Vector3.new(3.0, 1.9, 0.22), CFrame.new(0, 4.45, 0.5), dark, { Reflectance = 0.1 })
	-- chin wedge under the monitor (sloped plastic)
	ModelKit.wedge(model, "MonitorChin", Vector3.new(3.0, 0.25, 0.3), CFrame.new(0, 3.37, 0.42), dark, {})
	local screen = ModelKit.part(
		model,
		"Screen",
		Vector3.new(2.7, 1.55, 0.03),
		CFrame.new(0, 4.5, 0.375),
		Color3.fromRGB(10, 28, 34),
		{ Material = Enum.Material.SmoothPlastic, CanCollide = false }
	)
	local power = ModelKit.neon(model, "PowerLED", Vector3.new(0.3, 0.05, 0.03), CFrame.new(0, 3.61, 0.375), accent)
	ModelKit.light(power, accent, 6, 0.8)
	-- status beacon on top of the monitor
	local beacon = ModelKit.ball(model, "Beacon", 0.22, CFrame.new(1.2, 5.5, 0.5), accent, { Material = Enum.Material.Neon, CanCollide = false })
	ModelKit.role(beacon, "Accent")
	ModelKit.cylinder(model, "BeaconBase", "Y", 0.1, 0.3, CFrame.new(1.2, 5.4, 0.5), tier.metalColor, {})

	-- screen content: cute engine graph
	local gui = Instance.new("SurfaceGui")
	gui.Name = "ScreenGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 100
	gui.LightInfluence = 0
	gui.Brightness = 1.2
	gui.Parent = screen
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(10, 28, 34)
	bg.BorderSizePixel = 0
	bg.Parent = gui
	text(bg, "ENGINE CHECK", UDim2.fromScale(0.05, 0.04), UDim2.fromScale(0.9, 0.2), Color3.fromRGB(120, 255, 200), Enum.TextXAlignment.Left)
	local graph = Instance.new("Frame")
	graph.Position = UDim2.fromScale(0.05, 0.28)
	graph.Size = UDim2.fromScale(0.9, 0.46)
	graph.BackgroundColor3 = Color3.fromRGB(6, 18, 22)
	graph.BorderSizePixel = 0
	graph.Parent = bg
	local heights = { 0.35, 0.5, 0.4, 0.7, 0.55, 0.85, 0.6, 0.75, 0.45, 0.65, 0.5, 0.8 }
	for i, h in heights do
		bar(graph, i, #heights, h, Color3.fromRGB(70, 230, 150):Lerp(accent, i / #heights * 0.6))
	end
	text(bg, "RPM 2400   ^_^  ALL OK", UDim2.fromScale(0.05, 0.78), UDim2.fromScale(0.9, 0.17), Color3.fromRGB(235, 250, 255), Enum.TextXAlignment.Left)

	------------------------------------------------------------ keyboard + mouse + pen cup on the upper tray
	local kx, kz = -0.35, -0.7
	ModelKit.part(model, "KeyboardBase", Vector3.new(2.0, 0.08, 0.75), CFrame.new(kx, TRAY_TOP + 0.04, kz), dark, {})
	for i = 1, 4 do
		ModelKit.part(
			model,
			"KeyRow",
			Vector3.new(1.84, 0.04, 0.11),
			CFrame.new(kx, TRAY_TOP + 0.1, kz - 0.28 + (i - 1) * 0.145),
			Color3.fromRGB(226, 230, 238),
			{}
		)
	end
	ModelKit.part(model, "SpaceBar", Vector3.new(0.9, 0.04, 0.1), CFrame.new(kx, TRAY_TOP + 0.1, kz + 0.28), Color3.fromRGB(190, 196, 208), {})
	ModelKit.part(model, "Mouse", Vector3.new(0.3, 0.1, 0.5), CFrame.new(0.95, TRAY_TOP + 0.05, kz), dark, {})
	ModelKit.part(model, "MouseButton", Vector3.new(0.12, 0.02, 0.18), CFrame.new(0.95, TRAY_TOP + 0.11, kz - 0.1), tier.metalColor, {})
	-- pen cup with pens
	ModelKit.cylinder(model, "PenCup", "Y", 0.5, 0.36, CFrame.new(-1.55, TRAY_TOP + 0.25, 1.0), tier.trimColor, {})
	for i, c in { Color3.fromRGB(220, 60, 60), Color3.fromRGB(60, 120, 230), Color3.fromRGB(250, 210, 60) } do
		ModelKit.cylinder(
			model,
			"Pen",
			"Y",
			0.7,
			0.04,
			CFrame.new(-1.55 + (i - 2) * 0.07, TRAY_TOP + 0.6, 1.0) * CFrame.Angles(0, 0, math.rad((i - 2) * 12)),
			c,
			{}
		)
	end

	------------------------------------------------------------ OBD box on the lower tray
	local obd = ModelKit.part(model, "OBDBox", Vector3.new(1.1, 0.3, 0.7), CFrame.new(0.85, 1.225, -0.1), dark, {})
	ModelKit.wedge(model, "OBDHood", Vector3.new(1.0, 0.12, 0.4), CFrame.new(0.85, 1.43, -0.22), Color3.fromRGB(44, 48, 58), {})
	ModelKit.part(model, "OBDPort", Vector3.new(0.5, 0.18, 0.2), CFrame.new(0.85, 1.22, -0.55), Color3.fromRGB(60, 62, 70), {})
	ModelKit.part(model, "LEDGreen", Vector3.new(0.1, 0.04, 0.1), CFrame.new(0.55, 1.4, 0.05), Color3.fromRGB(80, 255, 120), {
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	ModelKit.part(model, "LEDRed", Vector3.new(0.1, 0.04, 0.1), CFrame.new(0.75, 1.4, 0.05), Color3.fromRGB(255, 70, 60), {
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	local obdGui = Instance.new("SurfaceGui")
	obdGui.Face = Enum.NormalId.Top
	obdGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	obdGui.PixelsPerStud = 60
	obdGui.LightInfluence = 0
	obdGui.Parent = obd
	text(obdGui, "OBD II", UDim2.fromScale(0.5, 0.55), UDim2.fromScale(0.45, 0.35), Color3.fromRGB(240, 240, 250), Enum.TextXAlignment.Center)

	------------------------------------------------------------ scanner (handheld) + coiled cable
	local sx, sy, sz = 1.45, TRAY_TOP + 0.09, -0.7
	ModelKit.part(model, "ScannerBody", Vector3.new(0.55, 0.18, 1.0), CFrame.new(sx, sy, sz), Color3.fromRGB(232, 168, 40), { Material = Enum.Material.SmoothPlastic })
	ModelKit.wedge(model, "ScannerNose", Vector3.new(0.55, 0.18, 0.3), CFrame.new(sx, sy, sz - 0.65) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(232, 168, 40), {})
	ModelKit.part(model, "ScannerScreen", Vector3.new(0.4, 0.02, 0.4), CFrame.new(sx, sy + 0.1, sz + 0.1), Color3.fromRGB(100, 230, 190), {
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	ModelKit.part(model, "ScannerGrip", Vector3.new(0.4, 0.16, 0.3), CFrame.new(sx, sy, sz + 0.55), dark, {})

	local cablePts = {
		Vector3.new(0.85, 1.22, -0.7),
		Vector3.new(1.05, 1.12, -1.3),
		Vector3.new(1.7, 1.22, -1.45),
		Vector3.new(1.85, 1.9, -1.45),
		Vector3.new(1.85, 2.65, -1.45),
		Vector3.new(1.7, 2.9, -1.35),
		Vector3.new(sx, sy, sz - 0.8),
	}
	for i = 1, #cablePts - 1 do
		local a, b = cablePts[i], cablePts[i + 1]
		ModelKit.cylinder(model, "Cable", "Z", (b - a).Magnitude + 0.05, 0.07, CFrame.lookAt(a:Lerp(b, 0.5), b), dark, {})
	end

	------------------------------------------------------------ small details
	-- wrench resting on the lower tray
	ModelKit.part(model, "WrenchHandle", Vector3.new(0.14, 0.05, 1.1), CFrame.new(-1.3, 1.1, 0.5) * CFrame.Angles(0, math.rad(20), 0), tier.metalColor, {
		Material = tier.metalMaterial,
		Reflectance = tier.metalReflectance,
	})
	ModelKit.cylinder(model, "WrenchHead", "Y", 0.06, 0.34, CFrame.new(-1.3 - 0.19, 1.1, 0.5 - 0.52), tier.metalColor, {
		Material = tier.metalMaterial,
		Reflectance = tier.metalReflectance,
	})
	return model
end
