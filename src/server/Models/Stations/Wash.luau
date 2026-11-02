--!strict
-- Drive-through car wash arch (docs/CONTRACT.md section 12, key "wash", levels 1-5).
-- Plot-aligned: the car (7 wide) drives along Z through X = 0, -Z = front. The arch stands on the parking lot (top Y = 0.06).
-- Footprint X -6..6, Z -3..3, height <= 11. Posts at X +-5.2..6.0, clear width > 10, clear height >= 8.
-- Contains several disabled ParticleEmitters named "WashFoam" that the server enables while a car is under the arch.

local ModelKit = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("ModelKit"))

local G = 0.06 -- parking lot surface
local PLINTH_H = 0.3
local FLOOR_Y = G + PLINTH_H -- top of the plinths = 0.36
local BEAM_BOTTOM = 8.9
local BEAM_H = 1.7
local BEAM_MID = BEAM_BOTTOM + BEAM_H / 2 -- 9.75
local POST_H = BEAM_BOTTOM - FLOOR_Y -- 8.54
local POST_MID = FLOOR_Y + POST_H / 2
local SPRAY_Y = 8.3
local SPRAY_Z = -2.15

local WHITE = Color3.fromRGB(244, 246, 250)
local BLUE = Color3.fromRGB(46, 122, 222)
local BRASS = Color3.fromRGB(205, 170, 70)
local RUST = Color3.fromRGB(122, 70, 38)

-- Soap bubbles that the server turns on while a car is washed.
local function foam(parent: BasePart, dir: Enum.NormalId, spread: number)
	local e = Instance.new("ParticleEmitter")
	e.Name = "WashFoam"
	e.Enabled = false
	e.Rate = 40
	e.Lifetime = NumberRange.new(1, 2)
	e.Speed = NumberRange.new(3, 6)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(0.5, 1.2),
		NumberSequenceKeypoint.new(1, 0.8),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.7, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(185, 225, 255))
	e.LightEmission = 0.3
	e.SpreadAngle = Vector2.new(spread, spread)
	e.Acceleration = Vector3.new(0, -6, 0)
	e.EmissionDirection = dir
	e.Parent = parent
end

local function sparkle(parent: BasePart, color: Color3)
	local e = Instance.new("ParticleEmitter")
	e.Name = "Sparkle"
	e.Rate = 10
	e.Lifetime = NumberRange.new(1, 2)
	e.Speed = NumberRange.new(1, 3)
	e.SpreadAngle = Vector2.new(180, 180)
	e.LightEmission = 1
	e.Size = NumberSequence.new(0.25, 0)
	e.Color = ColorSequence.new(color)
	e.Parent = parent
end

-- Text on one face of a part (readable from that side).
local function addText(part: BasePart, face: Enum.NormalId, text: string, color: Color3, pxPerStud: number)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Gui"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pxPerStud
	gui.LightInfluence = 0
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.Parent = gui
end

return function(level: number, accent: Color3, opts: { [string]: any }?): Model
	local tier = ModelKit.tier(level)
	local lv = tier.level
	local model = ModelKit.model("Station")
	local base: Color3 = if lv == 2 then BLUE else accent
	local ledColor = tier.ledColor(accent)
	local metalProps: { [string]: any } = {
		Material = tier.metalMaterial,
		Reflectance = tier.metalReflectance,
		CanCollide = false,
	}

	local function bodyPart(name: string, size: Vector3, cf: CFrame): Part
		return ModelKit.body(model, name, size, cf, base, tier)
	end
	-- Posts / rails: chrome at Lv3, painted body otherwise.
	local function framePart(name: string, size: Vector3, cf: CFrame): Part
		if lv == 3 then
			return ModelKit.metal(model, name, size, cf, tier)
		end
		return bodyPart(name, size, cf)
	end
	local function led(name: string, size: Vector3, cf: CFrame): Part?
		return ModelKit.led(model, name, size, cf, tier, accent)
	end

	-- Brush palette per level.
	local brushA: Color3, brushB: Color3
	local glowA = false
	local accentA = false
	if lv == 1 then
		brushA, brushB = Color3.fromRGB(128, 112, 92), Color3.fromRGB(100, 88, 72)
	elseif lv == 2 then
		brushA, brushB = Color3.fromRGB(70, 160, 255), WHITE
	elseif lv == 3 then
		brushA, brushB = accent, WHITE
		accentA = true
	elseif lv == 4 then
		brushA, brushB = accent, Color3.fromRGB(30, 30, 34)
		accentA = true
	else
		brushA, brushB = accent, Color3.fromRGB(20, 24, 36)
		glowA = true
	end
	local coreColor = if lv == 1 then Color3.fromRGB(70, 62, 54) else Color3.fromRGB(60, 62, 70)

	-- One bristle band; the "A" color may glow / be recolorable.
	local function band(name: string, axis: string, length: number, diameter: number, cf: CFrame, useA: boolean): Part
		local color = if useA then brushA else brushB
		local p: Part
		if useA and glowA then
			p = ModelKit.cylinder(model, name, axis, length, diameter, cf, color, {
				Material = Enum.Material.Neon,
				CanCollide = false,
				CanTouch = false,
				CastShadow = false,
			})
			ModelKit.role(p, "Accent")
		else
			p = ModelKit.cylinder(model, name, axis, length, diameter, cf, color, {
				Material = Enum.Material.Fabric,
				CanCollide = false,
				CanTouch = false,
			})
			if useA and accentA then
				ModelKit.role(p, "Accent")
			end
		end
		return p
	end

	------------------------------------------------------------------ ground
	ModelKit.part(
		model,
		"WetFloor",
		Vector3.new(9.4, 0.04, 5.8),
		CFrame.new(0, G + 0.02, 0),
		tier.trimColor,
		{ Material = tier.trimMaterial, Reflectance = if lv >= 5 then 0.2 else 0, CanCollide = false }
	)
	for _, s in { -1, 1 } do
		ModelKit.trim(model, "Plinth", Vector3.new(1.2, PLINTH_H, 5.8), CFrame.new(s * 5.4, G + PLINTH_H / 2, 0), tier)
		if lv >= 2 then
			-- wheel guide rails
			ModelKit.part(
				model,
				"GuideRail",
				Vector3.new(0.3, 0.22, 5.4),
				CFrame.new(s * 4.1, G + 0.11, 0),
				if lv == 2 then WHITE else tier.metalColor,
				{ Material = tier.metalMaterial, Reflectance = tier.metalReflectance, CanCollide = false }
			)
		end
	end

	------------------------------------------------------------------ arch legs, guards, rails, gussets
	local frontPosts: { Part } = {}
	for _, s in { -1, 1 } do
		for _, z in { -2.5, 2.5 } do
			local post = framePart("Post", Vector3.new(0.8, POST_H, 0.9), CFrame.new(s * 5.6, POST_MID, z))
			if z < 0 then
				table.insert(frontPosts, post)
			end
			-- gusset under the beam (wedge, right angle at the post/beam corner)
			ModelKit.wedge(
				model,
				"Gusset",
				Vector3.new(0.6, 1.1, 1.1),
				CFrame.new(s * (5.2 - 0.55), BEAM_BOTTOM - 0.55, z)
					* CFrame.Angles(0, s * math.pi / 2, 0)
					* CFrame.Angles(0, 0, math.pi),
				tier.metalColor,
				{ Material = tier.metalMaterial, Reflectance = tier.metalReflectance }
			)
		end

		-- splash guard / side wall
		local guardH = if lv >= 5 then POST_H elseif lv == 4 then 4.0 else 3.2
		local guard = framePart("SideGuard", Vector3.new(0.3, guardH, 4.1), CFrame.new(s * 5.85, FLOOR_Y + guardH / 2, 0))
		if lv >= 5 then
			guard.Transparency = 0.45
			guard.CanCollide = false
		end
		-- horizontal rail that carries the brush brackets
		framePart("BrushRail", Vector3.new(0.5, 0.5, 4.1), CFrame.new(s * 5.5, 8.0, 0))

		if lv == 4 then
			local st = ModelKit.part(
				model,
				"Stripe",
				Vector3.new(0.04, 0.35, 4.1),
				CFrame.new(s * 5.69, FLOOR_Y + guardH * 0.55, 0),
				accent,
				{ CanCollide = false, CastShadow = false }
			)
			ModelKit.role(st, "Stripe")
			ModelKit.part(
				model,
				"Stripe",
				Vector3.new(0.04, 0.12, 4.1),
				CFrame.new(s * 5.69, FLOOR_Y + guardH * 0.55 + 0.35, 0),
				WHITE,
				{ CanCollide = false, CastShadow = false }
			)
		elseif lv >= 5 then
			ModelKit.neon(model, "EdgeNeon", Vector3.new(0.1, 0.1, 4.1), CFrame.new(s * 5.68, FLOOR_Y + guardH, 0), accent)
			ModelKit.neon(model, "EdgeNeon", Vector3.new(0.1, 0.1, 4.1), CFrame.new(s * 5.68, FLOOR_Y + 0.15, 0), accent)
		end

		if lv == 2 then
			-- white bands on the blue posts
			for _, z in { -2.5, 2.5 } do
				ModelKit.part(
					model,
					"PostBand",
					Vector3.new(0.84, 0.6, 0.94),
					CFrame.new(s * 5.6, 1.3, z),
					WHITE,
					{ Reflectance = 0.1 }
				)
				ModelKit.part(
					model,
					"PostBand",
					Vector3.new(0.84, 0.6, 0.94),
					CFrame.new(s * 5.6, 7.2, z),
					WHITE,
					{ Reflectance = 0.1 }
				)
			end
		end
	end

	------------------------------------------------------------------ top beam
	local beam = bodyPart("Beam", Vector3.new(12, BEAM_H, 5.6), CFrame.new(0, BEAM_MID, 0))
	if lv == 1 then
		ModelKit.rustPatches(model, beam, 4, 17)
		-- rust streaks on the front posts
		for i, post in frontPosts do
			for j, y in { 1.2, 3.6, 6.2 } do
				local dx = if (i + j) % 2 == 0 then 0.12 else -0.12
				ModelKit.part(
					model,
					"Rust",
					Vector3.new(0.45, 0.6, 0.06),
					CFrame.new(post.Position.X + dx, y, -2.97),
					RUST,
					{ Material = Enum.Material.Rust, CanCollide = false, CastShadow = false }
				)
			end
		end
	elseif lv == 2 then
		ModelKit.part(
			model,
			"BeamBand",
			Vector3.new(12.04, 0.16, 5.64),
			CFrame.new(0, BEAM_BOTTOM + 0.25, 0),
			WHITE,
			{ Reflectance = 0.1 }
		)
		-- soap bubbles on top
		local bubbles = {
			{ -4.6, 10.65, -1.2, 0.6 },
			{ -3.9, 10.62, 0.9, 0.5 },
			{ -4.9, 10.6, 1.6, 0.4 },
			{ 4.2, 10.65, -0.8, 0.6 },
			{ 4.9, 10.62, 1.3, 0.45 },
		}
		for _, b in bubbles do
			ModelKit.ball(
				model,
				"Bubble",
				b[4],
				CFrame.new(b[1], b[2], b[3]),
				Color3.fromRGB(190, 230, 255),
				{ Material = Enum.Material.Glass, Transparency = 0.35, CanCollide = false, CastShadow = false }
			)
		end
	elseif lv == 3 then
		ModelKit.metal(model, "BeamCap", Vector3.new(12.1, 0.12, 5.7), CFrame.new(0, BEAM_BOTTOM + BEAM_H + 0.06, 0), tier)
		ModelKit.metal(model, "BeamBand", Vector3.new(12.04, 0.16, 5.64), CFrame.new(0, BEAM_BOTTOM + 0.25, 0), tier)
	elseif lv == 4 then
		-- racing stripes running over the roof of the arch
		local roofY = BEAM_BOTTOM + BEAM_H + 0.02
		local st = ModelKit.part(
			model,
			"Stripe",
			Vector3.new(1.4, 0.04, 5.6),
			CFrame.new(-1.0, roofY, 0),
			accent,
			{ CanCollide = false, CastShadow = false }
		)
		ModelKit.role(st, "Stripe")
		ModelKit.part(
			model,
			"Stripe",
			Vector3.new(0.5, 0.04, 5.6),
			CFrame.new(0.5, roofY, 0),
			WHITE,
			{ CanCollide = false, CastShadow = false }
		)
		ModelKit.stripes(model, frontPosts[1], accent)
		ModelKit.stripes(model, frontPosts[2], accent)
	else
		ModelKit.neon(model, "RoofNeon", Vector3.new(12.05, 0.1, 0.1), CFrame.new(0, BEAM_BOTTOM + BEAM_H, -2.78), accent)
		ModelKit.neon(model, "RoofNeon", Vector3.new(12.05, 0.1, 0.1), CFrame.new(0, BEAM_BOTTOM + BEAM_H, 2.78), accent)
		ModelKit.stripes(model, frontPosts[1], accent)
		ModelKit.stripes(model, frontPosts[2], accent)
		sparkle(beam, accent)
	end

	------------------------------------------------------------------ "CAR WASH" sign (front and back)
	local signBg: Color3, signText: Color3
	if lv == 1 then
		signBg, signText = Color3.fromRGB(88, 76, 60), Color3.fromRGB(205, 190, 150)
	elseif lv == 2 then
		signBg, signText = WHITE, BLUE
	elseif lv == 3 then
		signBg, signText = Color3.fromRGB(22, 30, 52), Color3.fromRGB(255, 255, 255)
	elseif lv == 4 then
		signBg, signText = Color3.fromRGB(14, 14, 16), accent
	else
		signBg, signText = Color3.fromRGB(8, 12, 24), accent
	end
	local tilt = if lv == 1 then CFrame.Angles(0, 0, math.rad(-2.5)) else CFrame.new()
	for _, side in { -1, 1 } do
		local cf = CFrame.new(0, BEAM_MID, side * 2.86) * (if side > 0 then CFrame.Angles(0, math.pi, 0) else CFrame.new()) * tilt
		local panel = ModelKit.part(
			model,
			"SignBoard",
			Vector3.new(8.8, 1.3, 0.12),
			cf,
			signBg,
			{ Material = if lv == 1 then Enum.Material.Metal else Enum.Material.SmoothPlastic, CanCollide = false }
		)
		if lv >= 5 then
			local holo = ModelKit.hologram(
				model,
				CFrame.new(0, BEAM_MID, side * 2.96) * (if side > 0 then CFrame.Angles(0, math.pi, 0) else CFrame.new()),
				Vector2.new(8.4, 1.2),
				accent
			)
			holo.Name = "HoloSign"
			addText(holo, Enum.NormalId.Front, "CAR WASH", signText, 50)
		else
			addText(panel, Enum.NormalId.Front, "CAR WASH", signText, 50)
		end
		if lv == 2 then
			ModelKit.part(model, "SignTrim", Vector3.new(8.9, 0.1, 0.14), cf * CFrame.new(0, 0.7, 0), BLUE, { CanCollide = false })
			ModelKit.part(model, "SignTrim", Vector3.new(8.9, 0.1, 0.14), cf * CFrame.new(0, -0.7, 0), BLUE, { CanCollide = false })
		end
	end

	-- digital "WASH" displays on the beam ends (Lv3 + Lv4)
	if lv == 3 or lv == 4 then
		local texts = { "WASH", "READY" }
		for i, x in { -5.2, 5.2 } do
			local d = ModelKit.part(
				model,
				"Display",
				Vector3.new(1.35, 0.8, 0.1),
				CFrame.new(x, BEAM_MID, -2.86),
				Color3.fromRGB(8, 10, 12),
				{ CanCollide = false }
			)
			local color = if lv == 3 then Color3.fromRGB(120, 255, 150) else accent
			addText(d, Enum.NormalId.Front, texts[i], color, 40)
		end
	end

	------------------------------------------------------------------ LEDs (Lv3+)
	if tier.lights then
		local under = led("UnderLED", Vector3.new(10.4, 0.1, 0.18), CFrame.new(0, BEAM_BOTTOM - 0.04, -2.5))
		if under then
			ModelKit.light(under, ledColor, 14, 1)
		end
		led("UnderLED", Vector3.new(10.4, 0.1, 0.18), CFrame.new(0, BEAM_BOTTOM - 0.04, 2.5))
		for _, s in { -1, 1 } do
			local floorLed = led("FloorLED", Vector3.new(0.14, 0.05, 5.4), CFrame.new(s * 4.35, G + 0.04, 0))
			if floorLed then
				ModelKit.light(floorLed, ledColor, 9, 0.8)
			end
			for _, z in { -2.9, 2.9 } do
				led("PostLED", Vector3.new(0.1, 7.6, 0.14), CFrame.new(s * 5.14, 4.6, z))
			end
			-- warning beacon on the beam end
			local beacon = ModelKit.cylinder(
				model,
				"Beacon",
				"Y",
				0.4,
				0.5,
				CFrame.new(s * 5.4, 10.8, 0),
				if lv >= 4 then accent else Color3.fromRGB(255, 190, 40),
				{ Material = Enum.Material.Neon, CanCollide = false, CastShadow = false }
			)
			if lv >= 4 then
				ModelKit.role(beacon, "Accent")
			end
			ModelKit.light(beacon, if lv >= 4 then accent else Color3.fromRGB(255, 190, 40), 8, 1)
		end
	end
	if lv >= 5 then
		-- neon rings framing the tunnel mouth (front and back)
		for _, z in { -2.9, 2.9 } do
			ModelKit.neon(model, "RingNeon", Vector3.new(10.28, 0.12, 0.12), CFrame.new(0, 8.5, z), accent)
			for _, s in { -1, 1 } do
				ModelKit.neon(
					model,
					"RingNeon",
					Vector3.new(1.13, 0.12, 0.12),
					CFrame.new(s * 4.72, 8.1, z) * CFrame.Angles(0, 0, -s * math.pi / 4),
					accent
				)
			end
		end
	end

	------------------------------------------------------------------ side brushes (vertical, rotating)
	local brushZ: { number } = if lv >= 4 then { -1.3, 0, 1.3 } else { 0 }
	local brushDiam = if lv >= 4 then 1.2 else 1.4
	local bandOffsets = { -2.5, -1.25, 0, 1.25, 2.5 }
	for _, s in { -1, 1 } do
		for _, z in brushZ do
			local bx = s * 4.9
			local core = ModelKit.cylinder(
				model,
				"BrushCore",
				"Y",
				6.2,
				0.6,
				CFrame.new(bx, 4.5, z),
				coreColor,
				{ Material = Enum.Material.Metal, CanCollide = false }
			)
			core:SetAttribute("Spin", 4 * s)
			for i, dy in bandOffsets do
				local b = band("Bristles", "Y", 1.1, brushDiam, CFrame.new(bx, 4.5 + dy, z), i % 2 == 1)
				b:SetAttribute("Spin", 4 * s)
			end
			-- mounting: pedestal, top hub, bracket on the rail
			ModelKit.trim(model, "BrushPedestal", Vector3.new(0.5, 0.94, 0.5), CFrame.new(bx, 0.83, z), tier)
			ModelKit.cylinder(model, "BrushHub", "Y", 0.3, 0.9, CFrame.new(bx, 7.75, z), tier.metalColor, metalProps)
			framePart("BrushBracket", Vector3.new(1.4, 0.4, 0.8), CFrame.new(s * 5.3, 8.0, z))
		end
	end

	------------------------------------------------------------------ top brush (horizontal along X)
	local topY, topZ = 7.2, -0.3
	local topCore = ModelKit.cylinder(
		model,
		"TopBrushCore",
		"X",
		8.0,
		0.6,
		CFrame.new(0, topY, topZ),
		coreColor,
		{ Material = Enum.Material.Metal, CanCollide = false }
	)
	topCore:SetAttribute("Spin", 5)
	local bandCount = if lv <= 2 then 5 else 7
	local bandStep = 6.6 / (bandCount - 1)
	for i = 1, bandCount do
		local x = -3.3 + (i - 1) * bandStep
		local b = band("TopBristles", "X", bandStep * 0.92, 1.5, CFrame.new(x, topY, topZ), i % 2 == 1)
		b:SetAttribute("Spin", 5)
	end
	for _, s in { -1, 1 } do
		ModelKit.metal(model, "TopBrushHanger", Vector3.new(0.3, 1.7, 0.3), CFrame.new(s * 4.05, 8.05, topZ), tier).CanCollide =
			false
	end

	------------------------------------------------------------------ dryer hood (behind the top brush)
	local hood = bodyPart("DryerHood", Vector3.new(9.4, 0.4, 2.0), CFrame.new(0, 8.7, 1.7))
	hood.CanCollide = false
	-- flipped wedge: flat face up against the hood, lip hanging at the front
	local lip = ModelKit.wedge(
		model,
		"DryerLip",
		Vector3.new(9.4, 0.4, 0.8),
		CFrame.new(0, 8.3, 1.1) * CFrame.Angles(math.pi, 0, 0),
		tier.metalColor,
		{ Material = tier.metalMaterial, Reflectance = tier.metalReflectance, CanCollide = false }
	)
	lip.CanCollide = false
	if lv == 2 then
		for _, x in { -3, 0, 3 } do
			ModelKit.part(model, "Vent", Vector3.new(2.4, 0.04, 1.2), CFrame.new(x, 8.48, 1.9), Color3.fromRGB(40, 60, 90), { CanCollide = false })
		end
	elseif lv >= 3 then
		for _, x in { -3, 0, 3 } do
			ModelKit.cylinder(
				model,
				"DryerFan",
				"Y",
				0.08,
				2.0,
				CFrame.new(x, 8.46, 1.9),
				Color3.fromRGB(26, 28, 34),
				{ Material = Enum.Material.Metal, CanCollide = false }
			)
			ModelKit.ball(model, "DryerHub", 0.5, CFrame.new(x, 8.44, 1.9), tier.metalColor, {
				Material = tier.metalMaterial,
				Reflectance = tier.metalReflectance,
				CanCollide = false,
			})
		end
	end
	if lv >= 5 then
		sparkle(hood, accent)
	end

	------------------------------------------------------------------ spray bars with WashFoam nozzles
	ModelKit.cylinder(model, "SprayBar", "X", 9.4, 0.26, CFrame.new(0, SPRAY_Y, SPRAY_Z), tier.metalColor, metalProps)
	local topN = ({ 2, 3, 4, 4, 5 })[lv]
	local sideRows = ({ 1, 2, 2, 3, 3 })[lv]
	for i = 1, topN do
		local x = -3.5 + (i - 1) * (7.0 / (topN - 1))
		local nozzle = ModelKit.part(
			model,
			"Nozzle",
			Vector3.new(0.22, 0.22, 0.22),
			CFrame.new(x, SPRAY_Y - 0.2, SPRAY_Z),
			BRASS,
			{ Material = Enum.Material.Metal, CanCollide = false }
		)
		foam(nozzle, Enum.NormalId.Bottom, 20)
	end
	for _, s in { -1, 1 } do
		ModelKit.cylinder(model, "SprayRiser", "Y", SPRAY_Y - 0.9, 0.26, CFrame.new(s * 4.7, (SPRAY_Y + 0.9) / 2, SPRAY_Z), tier.metalColor, metalProps)
		ModelKit.ball(model, "SprayElbow", 0.38, CFrame.new(s * 4.7, SPRAY_Y, SPRAY_Z), tier.metalColor, metalProps)
		local dir = if s > 0 then Enum.NormalId.Left else Enum.NormalId.Right
		for j = 1, sideRows do
			local nozzle = ModelKit.part(
				model,
				"Nozzle",
				Vector3.new(0.22, 0.22, 0.22),
				CFrame.new(s * 4.5, 1.8 + (j - 1) * 1.9, SPRAY_Z),
				BRASS,
				{ Material = Enum.Material.Metal, CanCollide = false }
			)
			foam(nozzle, dir, 18)
		end
	end

	------------------------------------------------------------------ Lv1 clutter: puddle, bucket, mop
	if lv == 1 then
		ModelKit.cylinder(
			model,
			"Puddle",
			"Y",
			0.03,
			3.2,
			CFrame.new(1.5, G + 0.05, 0.8),
			Color3.fromRGB(110, 150, 170),
			{ Material = Enum.Material.Glass, Transparency = 0.35, CanCollide = false }
		)
		ModelKit.cylinder(
			model,
			"Bucket",
			"Y",
			0.7,
			0.9,
			CFrame.new(-5.4, FLOOR_Y + 0.35, 2.0),
			Color3.fromRGB(150, 60, 50),
			{ Material = Enum.Material.CorrodedMetal, CanCollide = false }
		)
		ModelKit.cylinder(
			model,
			"MopHandle",
			"Y",
			2.6,
			0.1,
			CFrame.new(-5.2, FLOOR_Y + 1.4, 1.7) * CFrame.Angles(0, 0, math.rad(10)),
			Color3.fromRGB(130, 100, 60),
			{ Material = Enum.Material.Wood, CanCollide = false }
		)
	end

	return model
end
