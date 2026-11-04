--!strict
-- Two-post car lift built AROUND the parked car of bay 3 (docs/CONTRACT.md section 12). Footprint X -7..7, Z -9..7.
-- Posts at X +-5.5, car (7 wide, nose +Z) sits at the origin. Everything stays out of X -3.6..3.6 above Y 0.4 (arms and
-- pads are at floor level, Y < 0.5; the overhead beam, hydraulics and hologram sit above Y 8.5).
-- Lv1 old two-post lift without beam, Lv2 beam + full set, Lv3 chrome + LED columns + display + tool chest,
-- Lv4 carbon posts + stripes + floor mat + air-tool boom, Lv5 glass posts + neon edges + hologram + sparkles.

local ModelKit = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("ModelKit"))

local STEEL = Color3.fromRGB(60, 110, 200)
local YELLOW = Color3.fromRGB(255, 200, 20)
local RUBBER = Color3.fromRGB(22, 22, 26)
local TAPE = Color3.fromRGB(205, 200, 185)
local BLACK = Color3.fromRGB(8, 14, 20)
local TOOL_RED = Color3.fromRGB(190, 40, 40)

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
	local flat: ModelKit.Props = { CanCollide = false, CastShadow = false }
	local hoseColor = if lv == 1 then Color3.fromRGB(48, 44, 40) else Color3.fromRGB(26, 26, 28)
	local hazard = if lv == 1 then Color3.fromRGB(180, 150, 40) else YELLOW

	local POSTH = if lv == 1 then 10.0 elseif lv == 5 then 11.6 else 11.0 -- height above Y 0.4
	local TOP = 0.4 + POSTH

	------------------------------------------------------------ floor mat (Lv4+), under the car, below Y 0.2
	if lv >= 4 then
		ModelKit.part(model, "FloorMat", Vector3.new(13.4, 0.08, 15.0), CFrame.new(0, 0.14, -0.5), tier.trimColor, {
			Material = tier.trimMaterial,
			CanCollide = false,
		})
		for _, ez in { -7.9, 6.9 } do
			ModelKit.neon(model, "MatGlow", Vector3.new(13.4, 0.03, 0.12), CFrame.new(0, 0.185, ez), accent)
		end
		for _, ex in { -6.6, 6.6 } do
			ModelKit.neon(model, "MatGlow", Vector3.new(0.12, 0.03, 15.0), CFrame.new(ex, 0.185, -0.5), accent)
		end
	end

	------------------------------------------------------------ the two posts
	for _, sx in { -1, 1 } do
		-- base plate with a yellow edge
		ModelKit.trim(model, "BasePlate", Vector3.new(2.6, 0.3, 3.2), CFrame.new(sx * 5.6, 0.25, 0), tier)
		if lv >= 2 then
			ModelKit.part(model, "PlateStripe", Vector3.new(2.6, 0.04, 0.2), CFrame.new(sx * 5.6, 0.42, -1.45), YELLOW, flat)
		end

		local post = ModelKit.body(model, "Post", Vector3.new(1.2, POSTH, 1.5), CFrame.new(sx * 5.5, 0.4 + POSTH / 2, 0), STEEL, tier)
		ModelKit.trim(model, "PostCap", Vector3.new(1.5, 0.35, 1.8), CFrame.new(sx * 5.5, TOP + 0.175, 0), tier)
		if tier.rust then
			-- patches sized to the narrow post (ModelKit.rustPatches would overhang a 1.2 wide face)
			for _, r in { { -0.2, 4.6, 0.4, 0.6 }, { 0.2, 7.8, 0.3, 0.45 }, { -0.15, 9.2, 0.5, 0.3 }, { 0.15, 2.4, 0.3, 0.5 } } do
				ModelKit.part(
					model,
					"Rust",
					Vector3.new(r[3], r[4], 0.05),
					CFrame.new(sx * 5.5 + r[1] * sx, r[2], -0.77),
					Color3.fromRGB(122, 70, 38),
					{ Material = Enum.Material.CorrodedMetal, CanCollide = false, CastShadow = false }
				)
			end
			ModelKit.part(
				model,
				"Dent",
				Vector3.new(0.7, 0.5, 0.1),
				CFrame.new(sx * 5.5 + 0.1, 3.0, -0.79) * CFrame.Angles(0, 0, math.rad(25)),
				Color3.fromRGB(50, 70, 100),
				{ Material = Enum.Material.Metal, CanCollide = false }
			)
		end
		if tier.stripes then
			ModelKit.stripes(model, post, accent)
		end

		-- gussets (wedges) bracing the post against the floor
		ModelKit.wedge(model, "Gusset", Vector3.new(0.5, 1.8, 1.0), CFrame.new(sx * 5.5, 1.3, -1.25), STEEL:Lerp(tier.metalColor, 0.5), metalProps)
		if lv >= 2 then
			ModelKit.wedge(
				model,
				"Gusset",
				Vector3.new(0.5, 1.8, 1.0),
				CFrame.new(sx * 5.5, 1.3, 1.25) * CFrame.Angles(0, math.pi, 0),
				STEEL:Lerp(tier.metalColor, 0.5),
				metalProps
			)
			local railLen = POSTH - 1.8
			ModelKit.part(model, "CarriageRail", Vector3.new(0.12, railLen, 0.9), CFrame.new(sx * 4.84, 0.9 + railLen / 2, 0), tier.trimColor, trimProps)
		end

		-- carriage (lowered, arms attach here)
		ModelKit.metal(model, "Carriage", Vector3.new(0.7, 2.2, 1.9), CFrame.new(sx * 4.55, 1.2, 0), tier)
		if lv >= 2 then
			ModelKit.part(model, "CarriageCap", Vector3.new(0.72, 0.1, 1.92), CFrame.new(sx * 4.55, 2.33, 0), YELLOW, flat)
		end

		-- safety stripes high on the post front
		for i = 0, (if lv == 1 then 1 else 2) do
			ModelKit.part(model, "HazardBar", Vector3.new(1.22, 0.28, 0.1), CFrame.new(sx * 5.5, 6.0 + i * 0.65, -0.8), hazard, flat)
		end

		-- four low swing arms, two per post, reaching under the car at floor level
		for _, sz in { -1, 1 } do
			local pivot = Vector3.new(sx * 4.5, 0.2, sz * 0.95)
			local pad = Vector3.new(sx * 2.45, 0.2, sz * 2.3)
			if lv == 1 and sx == -1 and sz == 1 then
				pad = Vector3.new(sx * 2.8, 0.2, sz * 1.9) -- bent arm
			end
			local t0 = pivot:Lerp(pad, 0.3)
			local t1 = pivot:Lerp(pad, 0.62)
			bar(model, "ArmOuter", pivot, t1, 0.9, 0.2, tier.metalColor, metalProps)
			bar(model, "ArmInner", Vector3.new(t0.X, 0.26, t0.Z), Vector3.new(pad.X, 0.26, pad.Z), 0.6, 0.12, tier.metalColor, metalProps)
			ModelKit.cylinder(model, "ArmPivot", "Y", 0.35, 0.7, CFrame.new(pivot.X, 0.275, pivot.Z), tier.trimColor, trimProps)
			ModelKit.cylinder(model, "LiftPad", "Y", 0.16, 1.0, CFrame.new(pad.X, 0.38, pad.Z), RUBBER)
			if lv >= 2 then
				bar(model, "ArmStripe", Vector3.new(pivot.X, 0.305, pivot.Z), Vector3.new(t0.X, 0.305, t0.Z), 0.3, 0.02, hazard, flat)
			end
			if lv >= 4 then
				local halo = ModelKit.cylinder(model, "PadGlow", "Y", 0.03, 1.2, CFrame.new(pad.X, 0.3, pad.Z), accent, {
					Material = Enum.Material.Neon,
					CanCollide = false,
					CastShadow = false,
				})
				ModelKit.role(halo, "Accent")
			end
		end

		-- LED column lights on the inner post face (Lv3+)
		if lv >= 3 then
			local led = ModelKit.led(model, "PostLED", Vector3.new(0.1, POSTH - 2.2, 0.14), CFrame.new(sx * 4.85, 1.4 + (POSTH - 2.2) / 2, -0.62), tier, accent)
			if led then
				ModelKit.light(led, ledColor, 16, 0.9)
			end
		end

		-- Lv5: neon front edges + sparkles on the post top
		if lv >= 5 then
			for _, ex in { -0.6, 0.6 } do
				ModelKit.neon(model, "EdgeGlow", Vector3.new(0.08, POSTH - 0.4, 0.08), CFrame.new(sx * 5.5 + ex, 0.4 + POSTH / 2, -0.76), accent)
			end
			local capGlow = ModelKit.neon(model, "CapGlow", Vector3.new(1.0, 0.1, 1.3), CFrame.new(sx * 5.5, TOP + 0.4, 0), accent)
			sparkles(capGlow, accent, 6)
		end
	end

	------------------------------------------------------------ overhead beam (Lv2+, Y >= 10, spans X +-6)
	if lv >= 2 then
		local beam = ModelKit.body(model, "Crossbar", Vector3.new(12.0, 0.8, 1.2), CFrame.new(0, TOP - 0.4, 0), STEEL, tier)
		if tier.stripes then
			ModelKit.stripes(model, beam, accent)
		end
		ModelKit.part(model, "LimitSwitch", Vector3.new(0.6, 0.4, 0.6), CFrame.new(0, TOP - 1.0, 0), YELLOW, flat)
		local plate = ModelKit.part(model, "LoadPlate", Vector3.new(1.6, 0.5, 0.05), CFrame.new(-3.2, TOP - 0.4, -0.63), YELLOW, flat)
		screen(plate, "4T MAX", BLACK, YELLOW, 0)
		if lv >= 3 then
			for _, lz in { -0.35, 0.35 } do
				local led = ModelKit.led(model, "BeamLED", Vector3.new(9.0, 0.1, 0.18), CFrame.new(0, TOP - 0.85, lz), tier, accent)
				if led and lz < 0 then
					ModelKit.light(led, ledColor, 22, 1.1)
				end
			end
		end
		if lv >= 5 then
			ModelKit.neon(model, "BeamGlow", Vector3.new(11.0, 0.08, 0.1), CFrame.new(0, TOP - 0.82, -0.65), accent)
		end
	end

	------------------------------------------------------------ hydraulics: power unit by the right post + lines
	ModelKit.body(model, "HydUnit", Vector3.new(1.6, 1.6, 1.4), CFrame.new(5.5, 0.9, -2.7), Color3.fromRGB(80, 90, 105), tier)
	ModelKit.cylinder(model, "HydMotor", "X", 0.7, 1.0, CFrame.new(6.65, 1.1, -2.7), tier.metalColor, metalProps)
	ModelKit.cylinder(model, "HydPump", "Y", 0.6, 0.6, CFrame.new(5.5, 2.0, -2.7), if lv >= 4 then accent else tier.metalColor, if lv >= 4 then nil else metalProps)
	ModelKit.cylinder(model, "HydGaugeFace", "Z", 0.1, 0.5, CFrame.new(5.5, 1.3, -3.42), Color3.fromRGB(232, 226, 205), flat)
	polyHose(
		model,
		"HydLine",
		{ Vector3.new(5.0, 1.75, -2.6), Vector3.new(4.7, 2.7, -1.6), Vector3.new(4.55, 2.4, -0.5) },
		0.18,
		hoseColor,
		nil,
		if lv == 1 then { 1 } else nil
	)
	if lv == 1 then
		ModelKit.cylinder(model, "OilLeak", "Y", 0.02, 1.6, CFrame.new(5.5, 0.115, -3.8), Color3.fromRGB(30, 22, 12), { Reflectance = 0.3, CanCollide = false })
	end
	if lv >= 3 then
		-- overhead loop: up both posts and across the beam top
		for _, sx in { -1, 1 } do
			ModelKit.cylinder(model, "HydRiser", "Y", TOP + 0.12 - 2.4, 0.16, CFrame.new(sx * 4.65, 2.4 + (TOP + 0.12 - 2.4) / 2, -0.55), hoseColor, nil)
			ModelKit.ball(model, "HydElbow", 0.2, CFrame.new(sx * 4.65, TOP + 0.12, -0.55), hoseColor, nil)
		end
		ModelKit.cylinder(model, "HydCross", "X", 9.3, 0.2, CFrame.new(0, TOP + 0.12, -0.55), hoseColor, nil)
	end

	------------------------------------------------------------ control box on the right post
	do
		local boxColor = Color3.fromRGB(235, 190, 30)
		ModelKit.body(model, "ControlBox", Vector3.new(1.1, 1.5, 0.5), CFrame.new(5.5, 4.5, -1.0), boxColor, tier)
		ModelKit.cylinder(model, "StopButton", "Z", 0.12, if lv == 1 then 0.4 else 0.3, CFrame.new(5.5, 4.0, -1.3), Color3.fromRGB(200, 40, 40), nil)
		if lv >= 2 then
			ModelKit.cylinder(model, "UpButton", "Z", 0.1, 0.3, CFrame.new(5.2, 4.0, -1.28), Color3.fromRGB(40, 180, 70), nil)
			ModelKit.cylinder(model, "DownButton", "Z", 0.1, 0.3, CFrame.new(5.8, 4.0, -1.28), Color3.fromRGB(235, 190, 30), nil)
		end
		if lv >= 3 then
			local disp = ModelKit.part(model, "ControlDisplay", Vector3.new(0.9, 0.5, 0.05), CFrame.new(5.5, 4.85, -1.28), BLACK, { CanCollide = false })
			screen(disp, "LIFT OK", if lv >= 4 then accent else Color3.fromRGB(120, 255, 170), BLACK, 0)
		end
	end

	------------------------------------------------------------ tool chest (Lv3+)
	if lv >= 3 then
		for _, wx in { -1, 1 } do
			for _, wz in { -1, 1 } do
				ModelKit.cylinder(model, "ChestWheel", "X", 0.2, 0.5, CFrame.new(-5.5 + wx * 1.0, 0.35, -6.0 + wz * 0.6), RUBBER)
			end
		end
		local chest = ModelKit.body(model, "ToolChest", Vector3.new(2.4, 2.6, 1.6), CFrame.new(-5.5, 2.0, -6.0), TOOL_RED, tier)
		ModelKit.trim(model, "ChestLid", Vector3.new(2.5, 0.15, 1.7), CFrame.new(-5.5, 3.375, -6.0), tier)
		if tier.stripes then
			ModelKit.stripes(model, chest, accent)
		end
		for _, dy in { 1.2, 1.9, 2.6 } do
			ModelKit.part(model, "DrawerLine", Vector3.new(2.2, 0.06, 0.06), CFrame.new(-5.5, dy, -6.85), tier.trimColor, trimProps)
			ModelKit.metal(model, "DrawerHandle", Vector3.new(1.2, 0.12, 0.1), CFrame.new(-5.5, dy + 0.35, -6.88), tier)
		end
		if lv >= 5 then
			ModelKit.neon(model, "ChestGlow", Vector3.new(2.4, 0.06, 0.06), CFrame.new(-5.5, 3.2, -6.83), accent)
		end
	end

	------------------------------------------------------------ air-tool booms on the posts (Lv4+: left, Lv5: both)
	local function boom(sx: number)
		local x = sx * 5.5
		ModelKit.cylinder(model, "BoomKnuckle", "Y", 0.4, 0.6, CFrame.new(x, 7.0, 0.9), tier.trimColor, trimProps)
		bar(model, "BoomArm", Vector3.new(x, 7.0, 0.9), Vector3.new(x, 7.0, 4.8), 0.3, 0.3, tier.metalColor, metalProps)
		ModelKit.ball(model, "BoomJoint", 0.4, CFrame.new(x, 7.0, 4.8), tier.metalColor, metalProps)
		polyHose(
			model,
			"BoomHose",
			{ Vector3.new(x, 6.85, 4.8), Vector3.new(x, 5.6, 5.1), Vector3.new(x, 4.6, 4.5) },
			0.14,
			Color3.fromRGB(45, 105, 195),
			nil,
			nil
		)
		local gun = ModelKit.cylinder(model, "ImpactGun", "Z", 0.9, 0.45, CFrame.new(x, 4.4, 4.2), accent, nil)
		ModelKit.role(gun, "Accent")
		ModelKit.part(model, "GunGrip", Vector3.new(0.22, 0.6, 0.22), CFrame.new(x, 4.0, 4.45), tier.trimColor, trimProps)
	end
	if lv >= 4 then
		boom(-1)
	end
	if lv >= 5 then
		boom(1)
	end

	------------------------------------------------------------ Lv5 hologram
	if lv >= 5 then
		local holo = ModelKit.hologram(model, CFrame.new(0, 9.8, -3.0), Vector2.new(5.5, 2.0), accent)
		screen(holo, "LIFT READY", accent, BLACK, 1)
	end

	return model
end
