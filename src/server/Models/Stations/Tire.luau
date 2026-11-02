--!strict
-- Tire changer station (beside bay 1, docs/CONTRACT.md section 12). Footprint X -3..6, Z -4..4, -Z = front.
-- Lv1 rusty single machine, Lv2 clean + gauges, Lv3 chrome + display + balancer + LEDs, Lv4 carbon + stripes +
-- helper arm + brand panel + tire rack, Lv5 gunmetal glass + neon edges + hologram + sparkles.

local ModelKit = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("ModelKit"))

local RUBBER = Color3.fromRGB(28, 28, 32)
local SIDEWALL = Color3.fromRGB(46, 46, 52)
local YELLOW = Color3.fromRGB(255, 200, 20)
local TAPE = Color3.fromRGB(205, 200, 185)
local BASE_RED = Color3.fromRGB(205, 40, 40)
local BLACK = Color3.fromRGB(8, 14, 20)

-- CFrame at `from` looking at `to`; avoids the degenerate straight-up case.
local function aim(from: Vector3, to: Vector3): CFrame
	local dir = to - from
	local up = if math.abs(dir.Unit.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
	return CFrame.lookAt(from, to, up)
end

-- Box running from a to b (length along the a->b direction).
local function bar(parent: Instance, name: string, a: Vector3, b: Vector3, tx: number, ty: number, color: Color3, props: ModelKit.Props?): Part
	return ModelKit.part(parent, name, Vector3.new(tx, ty, (b - a).Magnitude), aim((a + b) / 2, b), color, props)
end

-- SurfaceGui text on the -Z (Front) face of a part.
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

-- Ring of tube segments around the local X axis of `base` (hose coils).
local function ring(
	parent: Instance,
	name: string,
	base: CFrame,
	radius: number,
	count: number,
	dia: number,
	color: Color3,
	tapeIndex: number?
)
	local len = 2 * radius * math.sin(math.pi / count) * 1.1
	for i = 1, count do
		local a = (i - 1) / count * math.pi * 2
		local pos = base * Vector3.new(0, math.sin(a) * radius, math.cos(a) * radius)
		local tangent = base:VectorToWorldSpace(Vector3.new(0, math.cos(a), -math.sin(a)))
		local cf = aim(pos, pos + tangent)
		ModelKit.cylinder(parent, name, "Z", len, dia, cf, color)
		if tapeIndex == i then
			ModelKit.cylinder(parent, "Tape", "Z", 0.3, dia * 1.4, cf, TAPE, { Material = Enum.Material.Fabric })
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

	-- Rubber tire, optionally with a metal rim disc showing on the open faces.
	local function tire(name: string, cf: CFrame, axis: string, dia: number, thick: number, withRim: boolean)
		ModelKit.cylinder(model, name, axis, thick, dia, cf, RUBBER)
		if withRim then
			ModelKit.cylinder(model, name .. "Rim", axis, thick + 0.04, dia * 0.5, cf, tier.metalColor, metalProps)
		end
	end

	------------------------------------------------------------ base + cabinet
	ModelKit.trim(model, "Base", Vector3.new(5.8, 0.3, 6.8), CFrame.new(0, 0.25, 0.5), tier)
	if lv >= 2 then
		ModelKit.part(model, "EdgeStripe", Vector3.new(5.8, 0.04, 0.3), CFrame.new(0, 0.42, -2.75), YELLOW, { CanCollide = false })
	end

	local cabinet = ModelKit.body(model, "Cabinet", Vector3.new(4.6, 2.6, 4.6), CFrame.new(0, 1.7, 0), BASE_RED, tier)
	ModelKit.trim(model, "Deck", Vector3.new(4.8, 0.2, 4.8), CFrame.new(0, 3.1, 0), tier)

	if tier.rust then
		ModelKit.rustPatches(model, cabinet, 5, 11)
		-- a caved-in dent on the front panel
		ModelKit.part(
			model,
			"Dent",
			Vector3.new(1.0, 0.7, 0.12),
			CFrame.new(1.2, 1.2, -2.33) * CFrame.Angles(0, 0, math.rad(18)),
			Color3.fromRGB(70, 30, 26),
			{ Material = Enum.Material.Metal, CanCollide = false }
		)
	end
	if tier.stripes then
		ModelKit.stripes(model, cabinet, accent)
	end

	-- front vents
	for i = 1, (if lv == 1 then 2 else 3) do
		ModelKit.part(model, "Vent", Vector3.new(2.6, 0.12, 0.06), CFrame.new(0, 0.5 + i * 0.32, -2.35), tier.trimColor, trimProps)
	end

	-- pressure gauges (Lv1-2) or the digital display (Lv3+)
	if lv <= 2 then
		for gi = 1, lv do
			local gx = if gi == 1 then -1.2 else 1.2
			ModelKit.cylinder(model, "GaugeBezel", "Z", 0.08, 1.05, CFrame.new(gx, 2.3, -2.35), tier.trimColor, trimProps)
			ModelKit.cylinder(model, "GaugeFace", "Z", 0.1, 0.9, CFrame.new(gx, 2.3, -2.35), Color3.fromRGB(232, 226, 205), { CanCollide = false })
			ModelKit.part(
				model,
				"GaugeNeedle",
				Vector3.new(0.06, 0.36, 0.04),
				CFrame.new(gx, 2.36, -2.43) * CFrame.Angles(0, 0, math.rad(if gi == 1 then -28 else 35)),
				Color3.fromRGB(200, 30, 30),
				{ CanCollide = false }
			)
		end
	else
		ModelKit.part(model, "DisplayBezel", Vector3.new(2.2, 1.2, 0.1), CFrame.new(0, 2.3, -2.36), tier.trimColor, trimProps)
		local disp = ModelKit.part(model, "Display", Vector3.new(2.0, 1.0, 0.12), CFrame.new(0, 2.3, -2.4), BLACK, { CanCollide = false })
		screen(disp, "PSI 32", if lv >= 4 then accent else Color3.fromRGB(120, 255, 170), BLACK, 0)
	end

	------------------------------------------------------------ pedals
	ModelKit.part(model, "PedalBase", Vector3.new(2.4, 0.36, 1.0), CFrame.new(0, 0.28, -3.4), tier.trimColor, trimProps)
	for i, px in { -0.6, 0.6 } do
		ModelKit.wedge(
			model,
			"Pedal",
			Vector3.new(0.8, 0.34, 0.8),
			CFrame.new(px, 0.63, -3.4),
			if i == 1 then tier.metalColor else Color3.fromRGB(200, 60, 50),
			if i == 1 then metalProps else nil
		)
	end
	ModelKit.cylinder(model, "PedalCable", "Z", 0.8, 0.14, CFrame.new(0, 0.5, -2.55), tier.trimColor, trimProps)

	------------------------------------------------------------ turntable + clamps
	ModelKit.cylinder(model, "Turntable", "Y", 0.3, 3.6, CFrame.new(0, 3.35, 0), tier.trimColor, trimProps)
	if lv == 3 then
		ModelKit.cylinder(model, "ChromeRing", "Y", 0.06, 4.0, CFrame.new(0, 3.24, 0), tier.metalColor, metalProps)
	elseif lv >= 4 then
		local glow = ModelKit.cylinder(model, "GlowRing", "Y", 0.06, 4.05, CFrame.new(0, 3.24, 0), accent, {
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
		})
		ModelKit.role(glow, "Accent")
		if lv >= 5 then
			sparkles(glow, accent, 8)
		end
	end

	for i = 0, 3 do
		local a = math.pi / 4 + i * math.pi / 2
		local cf = CFrame.new(math.cos(a) * 1.55, 3.7, math.sin(a) * 1.55) * CFrame.Angles(0, -a, 0)
		if lv == 1 and i == 2 then
			cf = cf * CFrame.Angles(0, 0, math.rad(14)) -- bent clamp
		end
		ModelKit.metal(model, "Clamp", Vector3.new(0.8, 0.4, 0.5), cf, tier)
		if lv >= 2 then
			ModelKit.part(model, "ClampTooth", Vector3.new(0.25, 0.25, 0.35), cf * CFrame.new(-0.2, 0.3, 0), tier.trimColor, trimProps)
		end
	end

	------------------------------------------------------------ the wheel on the turntable
	local WHEEL_Y = 4.55
	ModelKit.cylinder(model, "WheelTire", "Y", 1.3, 4.2, CFrame.new(0, WHEEL_Y, 0), RUBBER)
	ModelKit.cylinder(model, "WheelSidewall", "Y", 1.32, 3.5, CFrame.new(0, WHEEL_Y, 0), SIDEWALL)
	ModelKit.cylinder(model, "WheelRim", "Y", 1.34, 2.7, CFrame.new(0, WHEEL_Y, 0), tier.metalColor, metalProps)
	local nSpokes = if lv == 1 then 2 elseif lv <= 3 then 3 else 5
	for i = 0, nSpokes - 1 do
		ModelKit.part(
			model,
			"Spoke",
			Vector3.new(2.5, 0.08, 0.28),
			CFrame.new(0, 5.27, 0) * CFrame.Angles(0, i * math.pi / nSpokes, 0),
			tier.metalColor,
			metalProps
		)
	end
	local hub: Part
	if lv >= 4 then
		hub = ModelKit.cylinder(model, "HubCap", "Y", 0.2, 0.8, CFrame.new(0, 5.32, 0), accent, {
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
		})
		ModelKit.role(hub, "Accent")
	else
		hub = ModelKit.cylinder(model, "HubCap", "Y", 0.2, 0.8, CFrame.new(0, 5.32, 0), if lv == 1 then tier.trimColor else BASE_RED, trimProps)
	end
	if lv >= 3 then
		for i = 0, 4 do
			local a = i / 5 * math.pi * 2
			ModelKit.cylinder(model, "LugNut", "Y", 0.14, 0.2, CFrame.new(math.cos(a) * 0.58, 5.31, math.sin(a) * 0.58), tier.metalColor, metalProps)
		end
	end

	------------------------------------------------------------ mast, swing arm, bead tool
	local mastH = if lv >= 5 then 8.0 else 7.0
	local mastTop = 0.4 + mastH
	ModelKit.body(model, "Mast", Vector3.new(0.8, mastH, 0.8), CFrame.new(1.4, 0.4 + mastH / 2, 2.8), BASE_RED, tier)
	ModelKit.metal(model, "Carriage", Vector3.new(1.3, 1.1, 1.3), CFrame.new(1.4, 6.4, 2.8), tier)
	local armA, armB = Vector3.new(1.4, 6.4, 2.8), Vector3.new(1.0, 6.4, 0.9)
	bar(model, "SwingArm", armA, armB, 0.5, 0.5, tier.metalColor, metalProps)
	ModelKit.metal(model, "ToolRod", Vector3.new(0.28, 0.7, 0.28), CFrame.new(1.0, 5.8, 0.9), tier)
	local head = ModelKit.part(
		model,
		"BeadTool",
		Vector3.new(0.55, 0.28, 0.8),
		CFrame.new(1.0, 5.31, 0.9) * CFrame.Angles(0, math.rad(-20), 0),
		if lv == 1 then tier.trimColor elseif lv <= 3 then YELLOW else accent,
		if lv == 1 then trimProps else nil
	)
	if lv >= 4 then
		ModelKit.role(head, "Accent")
	end
	if lv >= 3 then
		ModelKit.cylinder(model, "ToolRoller", "X", 0.5, 0.3, CFrame.new(1.0, 5.28, 1.35), tier.metalColor, metalProps)
	end
	if lv >= 2 then
		ModelKit.wedge(
			model,
			"MastGusset",
			Vector3.new(0.5, 1.8, 0.7),
			CFrame.new(1.4, 1.3, 3.55) * CFrame.Angles(0, math.pi, 0),
			tier.metalColor,
			metalProps
		)
	end

	-- helper arm with a bead-press roller (Lv4+)
	if lv >= 4 then
		ModelKit.body(model, "HelperColumn", Vector3.new(0.6, 5.9, 0.6), CFrame.new(-1.4, 3.35, 2.8), BASE_RED, tier)
		bar(model, "HelperArm", Vector3.new(-1.4, 6.05, 2.8), Vector3.new(-1.0, 6.05, 1.0), 0.4, 0.5, tier.metalColor, metalProps)
		ModelKit.metal(model, "HelperBracket", Vector3.new(0.3, 0.4, 0.3), CFrame.new(-1.0, 5.9, 1.0), tier)
		local roller = ModelKit.cylinder(model, "PressRoller", "X", 0.9, 0.7, CFrame.new(-1.0, 5.55, 1.0), tier.trimColor, trimProps)
		ModelKit.role(roller, "Trim")
	end

	-- brand panel on top of the mast (Lv4+)
	if lv >= 4 then
		local signY = mastTop + 0.5
		local sign = ModelKit.part(model, "BrandPanel", Vector3.new(3.0, 0.8, 0.2), CFrame.new(1.4, signY, 2.8), tier.trimColor, trimProps)
		screen(sign, if lv >= 5 then "TIRE X" else "TIRE PRO", accent, BLACK, 0)
		ModelKit.neon(model, "BrandGlow", Vector3.new(3.0, 0.08, 0.22), CFrame.new(1.4, signY - 0.44, 2.8), accent)
	end

	------------------------------------------------------------ air hose coil on the left side
	local hoseColor = if lv == 1 then Color3.fromRGB(52, 48, 44) else Color3.fromRGB(45, 105, 195)
	local rings = if lv == 1 then 1 elseif lv <= 3 then 2 else 3
	for k = 1, rings do
		ring(model, "HoseCoil", CFrame.new(-2.48 - (k - 1) * 0.18, 1.9, 0), 0.75, 10, 0.22, hoseColor, if lv == 1 and k == 1 then 3 else nil)
	end
	ModelKit.metal(model, "HoseHookTop", Vector3.new(0.65, 0.14, 0.3), CFrame.new(-2.62, 2.84, 0), tier)
	ModelKit.metal(model, "HoseHookBottom", Vector3.new(0.65, 0.12, 0.3), CFrame.new(-2.62, 0.97, 0), tier)

	------------------------------------------------------------ tires: stack / leaning tire / rack
	if lv <= 3 then
		local n = if lv == 1 then 2 else 3
		local sz = if lv == 3 then 2.6 else 2.5
		for i = 1, n do
			local jitter = if lv == 1 and i == 2 then 0.15 else 0
			tire("StackTire", CFrame.new(4.6 + jitter, 0.1 + 0.425 + (i - 1) * 0.85, sz), "Y", 2.5, 0.85, i == n)
		end
	end
	if lv <= 2 then
		local cf = CFrame.new(4.6, 1.35, -1.0)
		if lv == 1 then
			cf = cf * CFrame.Angles(0, 0, math.rad(8))
		end
		tire("LeaningTire", cf, "X", 2.5, 0.85, true)
	end

	if lv >= 4 then
		for _, ux in { 3.5, 5.7 } do
			for _, uz in { 1.1, 3.8 } do
				ModelKit.metal(model, "RackPost", Vector3.new(0.2, 5.0, 0.2), CFrame.new(ux, 2.6, uz), tier)
			end
		end
		for _, y in { 1.0, 2.5, 4.0 } do
			ModelKit.metal(model, "RackShelf", Vector3.new(2.4, 0.12, 2.9), CFrame.new(4.6, y, 2.45), tier)
			tire("RackTire", CFrame.new(4.6, y + 0.46, 2.45), "Y", 2.3, 0.8, true)
			ModelKit.led(model, "RackLED", Vector3.new(2.4, 0.07, 0.07), CFrame.new(4.6, y - 0.06, 0.98), tier, accent)
		end
	end

	------------------------------------------------------------ wheel balancer (Lv3+)
	if lv >= 3 then
		ModelKit.body(model, "BalancerBody", Vector3.new(2.0, 3.4, 1.8), CFrame.new(4.6, 1.8, -0.6), Color3.fromRGB(70, 76, 90), tier)
		ModelKit.cylinder(model, "BalancerShaft", "Z", 1.4, 0.3, CFrame.new(4.6, 2.4, -2.2), tier.metalColor, metalProps)
		tire("BalancerWheel", CFrame.new(4.6, 2.4, -2.4), "Z", 2.2, 0.7, true)
		ModelKit.part(model, "BalancerHood", Vector3.new(2.0, 0.15, 1.7), CFrame.new(4.6, 3.75, -2.0), tier.trimColor, trimProps)
		ModelKit.metal(model, "BalancerNeck", Vector3.new(0.5, 0.3, 0.4), CFrame.new(4.6, 3.6, -0.1), tier)
		local bd = ModelKit.part(
			model,
			"BalancerDisplay",
			Vector3.new(1.6, 0.9, 0.15),
			CFrame.new(4.6, 4.0, -0.3) * CFrame.Angles(math.rad(12), 0, 0),
			BLACK,
			{ CanCollide = false }
		)
		screen(bd, "BAL OK", if lv >= 4 then accent else Color3.fromRGB(120, 255, 170), BLACK, 0)
	end

	------------------------------------------------------------ LEDs, lights, Lv5 extras
	if lv >= 3 then
		local front = ModelKit.led(model, "CabinetLED", Vector3.new(4.4, 0.12, 0.1), CFrame.new(0, 2.92, -2.33), tier, accent)
		if front then
			ModelKit.light(front, ledColor, 14, 0.9)
		end
		ModelKit.led(model, "BaseLED", Vector3.new(5.8, 0.12, 0.06), CFrame.new(0, 0.3, -2.92), tier, accent)
		local mastLed = ModelKit.led(
			model,
			"MastLED",
			Vector3.new(0.08, mastH - 1.2, 0.08),
			CFrame.new(0.96, 0.4 + 0.6 + (mastH - 1.2) / 2, 2.5),
			tier,
			accent
		)
		if mastLed then
			ModelKit.light(mastLed, ledColor, 12, 0.8)
		end
	end

	if lv >= 5 then
		for _, ex in { -2.32, 2.32 } do
			for _, ez in { -2.32, 2.32 } do
				ModelKit.neon(model, "EdgeGlow", Vector3.new(0.1, 2.6, 0.1), CFrame.new(ex, 1.7, ez), accent)
			end
		end
		local holo = ModelKit.hologram(model, CFrame.new(0, 9.4, -0.8), Vector2.new(3.6, 2.0), accent)
		screen(holo, "TIRE READY", accent, BLACK, 1)
	end

	return model
end
