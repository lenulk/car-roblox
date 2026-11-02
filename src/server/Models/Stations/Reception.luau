--!strict
-- Reception podium / desk (docs/CONTRACT.md section 12, key "reception"). Accepts any level, always styled as Lv3 (Pro).
-- Stands on the parking lot (surface Y = 0.06). Footprint X -3..3, Z -1.5..1.5, front faces -Z; the receptionist stands
-- at +Z 3.5, so nothing is built beyond Z +1.5. Rounded counter, logo panel with gear emblem, service bell,
-- small "WELCOME" sign, tablet, tip jar, plant pot, brochure holder and a stool behind the counter.

local ModelKit = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("ModelKit"))

local G = 0.06 -- parking lot surface

local function addText(part: BasePart, face: Enum.NormalId, content: string, color: Color3, pxPerStud: number)
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
	label.Text = content
	label.TextColor3 = color
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.Parent = gui
end

return function(level: number, accent: Color3, opts: { [string]: any }?): Model
	local tier = ModelKit.tier(3)
	local model = ModelKit.model("Station")
	local ledColor = tier.ledColor(accent)
	local WHITE = Color3.fromRGB(242, 245, 250)
	local DARK = Color3.fromRGB(24, 28, 36)
	local metalProps: { [string]: any } = { Material = tier.metalMaterial, Reflectance = tier.metalReflectance }
	local TOP = 3.56 -- counter top surface

	local function box(name: string, size: Vector3, pos: Vector3, color: Color3, props: { [string]: any }?): Part
		return ModelKit.part(model, name, size, CFrame.new(pos), color, props)
	end

	------------------------------------------------------------ mat, kick, counter body with rounded ends
	box("FloorMat", Vector3.new(6.0, 0.04, 2.9), Vector3.new(0, G + 0.02, 0), Color3.fromRGB(44, 48, 58), { CanCollide = false })
	ModelKit.trim(model, "Kick", Vector3.new(4.8, 0.3, 1.0), CFrame.new(0, G + 0.17, -0.8), tier)
	for _, s in { -1, 1 } do
		ModelKit.cylinder(model, "KickCap", "Y", 0.3, 1.0, CFrame.new(s * 2.4, G + 0.17, -0.8), tier.trimColor, { Material = tier.trimMaterial })
	end
	local bodyBox = ModelKit.body(model, "CounterBody", Vector3.new(4.8, 3.04, 1.0), CFrame.new(0, 1.88, -0.8), accent, tier)
	ModelKit.role(bodyBox, "Accent")
	for _, s in { -1, 1 } do
		local cap = ModelKit.cylinder(
			model,
			"CounterEnd",
			"Y",
			3.04,
			1.0,
			CFrame.new(s * 2.4, 1.88, -0.8),
			tier.body(accent),
			{ Material = tier.bodyMaterial, Reflectance = tier.bodyReflectance }
		)
		ModelKit.role(cap, "Accent")
	end

	-- top slab (white) with chrome rim and rounded ends
	box("CounterTop", Vector3.new(4.8, 0.16, 1.2), Vector3.new(0, TOP - 0.08, -0.8), WHITE, { Reflectance = 0.15 })
	for _, s in { -1, 1 } do
		ModelKit.cylinder(model, "CounterTopEnd", "Y", 0.16, 1.2, CFrame.new(s * 2.4, TOP - 0.08, -0.8), WHITE, { Reflectance = 0.15 })
	end
	ModelKit.metal(model, "TopRim", Vector3.new(4.8, 0.05, 0.06), CFrame.new(0, TOP - 0.17, -1.4), tier)
	ModelKit.metal(model, "TopRimBack", Vector3.new(4.8, 0.05, 0.06), CFrame.new(0, TOP - 0.17, -0.2), tier)

	-- logo panel on the front with gear emblem
	local panel = box("LogoPanel", Vector3.new(3.8, 1.5, 0.08), Vector3.new(0, 1.9, -1.34), DARK, { Reflectance = 0.1 })
	addText(panel, Enum.NormalId.Front, "GARAGE", Color3.fromRGB(255, 255, 255), 40)
	-- keep the text on the right part of the panel and the gear on the left
	local gui = panel:FindFirstChildOfClass("SurfaceGui")
	if gui then
		local main = gui:FindFirstChildOfClass("TextLabel")
		if main then
			main.Position = UDim2.fromScale(0.32, 0.08)
			main.Size = UDim2.fromScale(0.64, 0.58)
		end
		local sub = Instance.new("TextLabel")
		sub.BackgroundTransparency = 1
		sub.Position = UDim2.fromScale(0.32, 0.68)
		sub.Size = UDim2.fromScale(0.64, 0.22)
		sub.Text = "REPAIR & WASH"
		sub.TextColor3 = accent
		sub.TextScaled = true
		sub.Font = Enum.Font.GothamBold
		sub.Parent = gui
	end
	local gx, gy, gz = -1.25, 1.9, -1.4
	local gear = ModelKit.cylinder(model, "GearEmblem", "Z", 0.06, 0.9, CFrame.new(gx, gy, gz), accent, { Material = Enum.Material.Neon, CanCollide = false, CastShadow = false })
	ModelKit.role(gear, "Accent")
	for k = 0, 7 do
		local tooth = ModelKit.neon(
			model,
			"GearTooth",
			Vector3.new(0.2, 0.28, 0.06),
			CFrame.new(gx, gy, gz) * CFrame.Angles(0, 0, math.rad(k * 45)) * CFrame.new(0, 0.5, 0),
			accent
		)
		tooth.CanCollide = false
	end
	ModelKit.cylinder(model, "GearHole", "Z", 0.04, 0.4, CFrame.new(gx, gy, gz - 0.02), DARK, { CanCollide = false })

	-- LEDs: accent edge under the top, white kick light
	local edge = ModelKit.neon(model, "AccentLED", Vector3.new(4.8, 0.06, 0.06), CFrame.new(0, TOP - 0.28, -1.34), accent)
	ModelKit.light(edge, accent, 10, 0.9)
	local kickLed = ModelKit.led(model, "KickLED", Vector3.new(4.6, 0.05, 0.05), CFrame.new(0, G + 0.36, -1.32), tier, accent)
	if kickLed then
		ModelKit.light(kickLed, ledColor, 8, 0.7)
	end

	------------------------------------------------------------ right wing going back
	ModelKit.body(model, "Wing", Vector3.new(1.0, 3.0, 1.5), CFrame.new(2.0, 1.56, 0.45), accent, tier).Name = "Wing"
	box("WingTop", Vector3.new(1.2, 0.12, 1.7), Vector3.new(2.0, 3.12, 0.45), WHITE, { Reflectance = 0.15 })
	ModelKit.metal(model, "WingRim", Vector3.new(1.2, 0.05, 0.06), CFrame.new(2.0, 3.0, 1.32), tier)
	-- pen holder on the wing
	ModelKit.cylinder(model, "PenCup", "Y", 0.4, 0.3, CFrame.new(2.0, 3.38, 0.9), DARK, {})
	for i, c in { Color3.fromRGB(220, 60, 60), Color3.fromRGB(60, 120, 230) } do
		ModelKit.cylinder(model, "Pen", "Y", 0.55, 0.04, CFrame.new(2.0 + (i - 1.5) * 0.08, 3.62, 0.9) * CFrame.Angles(0, 0, math.rad((i - 1.5) * 20)), c, {})
	end

	------------------------------------------------------------ service bell
	ModelKit.cylinder(model, "BellBase", "Y", 0.08, 0.9, CFrame.new(0.7, TOP + 0.04, -0.8), tier.metalColor, metalProps)
	local dome = ModelKit.ball(model, "ServiceBell", 0.7, CFrame.new(0.7, TOP + 0.18, -0.8), Color3.fromRGB(240, 200, 80), { Material = Enum.Material.Metal, Reflectance = 0.5 })
	dome:SetAttribute("Interactable", true)
	ModelKit.ball(model, "BellKnob", 0.16, CFrame.new(0.7, TOP + 0.56, -0.8), tier.metalColor, metalProps)

	------------------------------------------------------------ small "WELCOME" sign on a stand (leaning back)
	local sx, sz = -1.7, -0.55
	box("SignBase", Vector3.new(2.0, 0.1, 0.5), Vector3.new(sx, TOP + 0.05, sz), DARK, nil)
	for _, dx in { -0.8, 0.8 } do
		ModelKit.wedge(model, "SignBrace", Vector3.new(0.1, 0.5, 0.35), CFrame.new(sx + dx, TOP + 0.35, sz + 0.28) * CFrame.Angles(0, math.pi, 0), tier.metalColor, metalProps)
	end
	local board = ModelKit.part(
		model,
		"WelcomeSign",
		Vector3.new(2.2, 0.7, 0.1),
		CFrame.new(sx, TOP + 0.5, sz) * CFrame.Angles(math.rad(12), 0, 0),
		Color3.fromRGB(250, 246, 235),
		{ CanCollide = false }
	)
	addText(board, Enum.NormalId.Front, "WELCOME", accent, 50)
	addText(board, Enum.NormalId.Back, "WELCOME", accent, 50)
	local trimTop = ModelKit.neon(model, "SignLED", Vector3.new(2.2, 0.05, 0.06), CFrame.new(sx, TOP + 0.5, sz) * CFrame.Angles(math.rad(12), 0, 0) * CFrame.new(0, 0.37, -0.01), accent)
	trimTop.CanCollide = false

	------------------------------------------------------------ tablet (screen toward the receptionist)
	ModelKit.cylinder(model, "TabletStand", "Y", 0.5, 0.15, CFrame.new(1.4, TOP + 0.25, -0.6), tier.metalColor, metalProps)
	local tabCf = CFrame.new(1.4, TOP + 0.75, -0.6) * CFrame.Angles(0, math.pi, 0) * CFrame.Angles(math.rad(-12), 0, 0)
	ModelKit.part(model, "TabletBody", Vector3.new(0.95, 0.7, 0.06), tabCf, DARK, { Reflectance = 0.1 })
	ModelKit.part(model, "TabletScreen", Vector3.new(0.82, 0.58, 0.02), tabCf * CFrame.new(0, 0, -0.035), Color3.fromRGB(70, 200, 255), { Material = Enum.Material.Neon, CanCollide = false })
	local sticker = ModelKit.ball(model, "TabletLogo", 0.22, tabCf * CFrame.new(0, 0, 0.04), accent, { Material = Enum.Material.Neon, CanCollide = false })
	ModelKit.role(sticker, "Accent")

	------------------------------------------------------------ tip jar
	ModelKit.cylinder(
		model,
		"TipJar",
		"Y",
		0.7,
		0.6,
		CFrame.new(-0.55, TOP + 0.35, -0.9),
		Color3.fromRGB(200, 230, 245),
		{ Material = Enum.Material.Glass, Transparency = 0.5, CanCollide = false }
	)
	ModelKit.cylinder(model, "TipJarLid", "Y", 0.08, 0.64, CFrame.new(-0.55, TOP + 0.74, -0.9), tier.metalColor, metalProps)
	for i = 1, 3 do
		ModelKit.cylinder(
			model,
			"Coin",
			"Y",
			0.05,
			0.34,
			CFrame.new(-0.55 + (i - 2) * 0.04, TOP + 0.06 + i * 0.07, -0.9),
			Color3.fromRGB(245, 205, 70),
			{ Material = Enum.Material.Metal, Reflectance = 0.3, CanCollide = false }
		)
	end

	------------------------------------------------------------ plant pot (right end of the counter)
	local px, pz = 2.4, -0.75
	local pot = ModelKit.cylinder(model, "PlantPot", "Y", 0.6, 0.85, CFrame.new(px, TOP + 0.3, pz), Color3.fromRGB(196, 100, 64), { Material = Enum.Material.Concrete })
	pot.Name = "PlantPot"
	ModelKit.cylinder(model, "PotRim", "Y", 0.1, 0.95, CFrame.new(px, TOP + 0.62, pz), Color3.fromRGB(176, 86, 52), { Material = Enum.Material.Concrete })
	ModelKit.cylinder(model, "Soil", "Y", 0.05, 0.75, CFrame.new(px, TOP + 0.64, pz), Color3.fromRGB(70, 48, 32), { Material = Enum.Material.Ground })
	local greens = { Color3.fromRGB(70, 170, 90), Color3.fromRGB(90, 190, 100), Color3.fromRGB(50, 150, 80) }
	for k = 0, 5 do
		local leaf = ModelKit.part(
			model,
			"Leaf",
			Vector3.new(0.3, 1.0, 0.18),
			CFrame.new(px, TOP + 0.66, pz) * CFrame.Angles(0, math.rad(k * 60), 0) * CFrame.Angles(math.rad(28), 0, 0) * CFrame.new(0, 0.5, 0),
			greens[k % 3 + 1],
			{ Material = Enum.Material.Grass, CanCollide = false }
		)
		leaf.Shape = Enum.PartType.Ball
	end

	------------------------------------------------------------ brochure holder
	local bx, bz = 0.0, -0.45
	ModelKit.wedge(model, "BrochureHolder", Vector3.new(1.2, 0.5, 0.4), CFrame.new(bx, TOP + 0.25, bz) * CFrame.Angles(0, math.pi, 0), tier.metalColor, metalProps)
	local paper = { Color3.fromRGB(255, 120, 120), Color3.fromRGB(255, 220, 90), Color3.fromRGB(120, 200, 255) }
	for i, c in paper do
		ModelKit.part(model, "Brochure", Vector3.new(0.3, 0.45, 0.03), CFrame.new(bx + (i - 2) * 0.36, TOP + 0.48, bz - 0.04) * CFrame.Angles(math.rad(-15), 0, 0), c, { CanCollide = false })
	end

	------------------------------------------------------------ stool behind the counter
	local stx, stz = -1.0, 0.95
	ModelKit.cylinder(model, "StoolBase", "Y", 0.08, 0.9, CFrame.new(stx, G + 0.04, stz), tier.trimColor, {})
	ModelKit.cylinder(model, "StoolPole", "Y", 2.16, 0.16, CFrame.new(stx, 1.2, stz), tier.metalColor, metalProps)
	ModelKit.cylinder(model, "StoolFootRing", "Y", 0.05, 0.8, CFrame.new(stx, 0.9, stz), tier.metalColor, metalProps)
	ModelKit.cylinder(model, "StoolSeatBase", "Y", 0.1, 0.8, CFrame.new(stx, 2.3, stz), tier.trimColor, {})
	local seat = ModelKit.cylinder(model, "StoolSeat", "Y", 0.2, 0.95, CFrame.new(stx, 2.45, stz), accent, { Material = Enum.Material.Fabric })
	ModelKit.role(seat, "Accent")

	return model
end
