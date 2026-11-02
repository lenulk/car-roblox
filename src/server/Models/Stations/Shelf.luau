--!strict
-- Parts shelf (docs/CONTRACT.md section 12, key "shelf", levels 1-5). opts.product in "battery" | "tires" | "oil" | "rims".
-- Footprint X -4.5..4.5, Z -1.5..1.5 (back against +Z), height <= 9, products face -Z.
-- EVERY part of a product item is named "Product" and carries attributes ProductIndex (1..10*level) and
-- BaseTransparency (its intended Transparency). Items fill bottom row first, viewer-left (+X) to viewer-right (-X),
-- so hiding the highest indexes empties the shelf from the top-right.
-- Nothing else in the model is named "Product".

local ModelKit = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("ModelKit"))

local F = 0.1 -- building floor top
local WOOD = Color3.fromRGB(128, 92, 58)
local WOOD_LIGHT = Color3.fromRGB(152, 112, 72)
local WHITE = Color3.fromRGB(244, 246, 250)

-- Level layout: columns x rows = 10 * level items.
local COLS = { 5, 5, 6, 8, 10 }
local ROWS = { 2, 4, 5, 5, 5 }
local ROW_SPACE = { 2.4, 2.0, 1.6, 1.45, 1.45 } -- distance between shelf boards
local DEPTH = { 1.8, 2.4, 2.8, 3.0, 3.0 } -- shelf depth (Z), back is always at Z = 1.5

local PLATE: { [string]: string } = { battery = "BATTERIES", tires = "TIRES", oil = "MOTOR OIL", rims = "RIMS" }
local HEADER: { [string]: string } = { battery = "POWER CELLS", tires = "TIRE PRO", oil = "OIL KING", rims = "SHINY RIMS" }
local AD: { [string]: string } = { battery = "POWER UP!", tires = "GRIP MAX", oil = "SMOOTH RUN", rims = "BLING RIMS" }

local LABELS = {
	Color3.fromRGB(235, 70, 60),
	Color3.fromRGB(250, 200, 50),
	Color3.fromRGB(60, 150, 240),
	Color3.fromRGB(80, 200, 110),
}
local OIL_COLORS = {
	Color3.fromRGB(255, 196, 40),
	Color3.fromRGB(230, 60, 50),
	Color3.fromRGB(50, 130, 235),
	Color3.fromRGB(70, 190, 90),
	Color3.fromRGB(255, 130, 40),
}
local RIM_STYLES = {
	{ Color3.fromRGB(218, 223, 232), Color3.fromRGB(42, 44, 52) },
	{ Color3.fromRGB(232, 192, 72), Color3.fromRGB(70, 56, 30) },
	{ Color3.fromRGB(205, 70, 70), Color3.fromRGB(40, 40, 46) },
	{ Color3.fromRGB(100, 160, 235), Color3.fromRGB(30, 36, 50) },
}

local function tag(p: BasePart, idx: number)
	p.Name = "Product"
	p:SetAttribute("ProductIndex", idx)
	p:SetAttribute("BaseTransparency", p.Transparency)
end

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

---------------------------------------------------------------------- products
local function battery(model: Model, idx: number, x: number, y: number, z: number, pitch: number, rs: number)
	local bw = math.min(pitch * 0.82, 1.4)
	local bh = math.min(0.95, rs - 0.4)
	local bd = 0.7
	local cz = z + bd / 2
	tag(
		ModelKit.part(model, "Product", Vector3.new(bw, bh, bd), CFrame.new(x, y + bh / 2, cz), Color3.fromRGB(26, 26, 30), { CanCollide = false }),
		idx
	)
	tag(
		ModelKit.part(
			model,
			"Product",
			Vector3.new(bw * 0.78, bh * 0.5, 0.04),
			CFrame.new(x, y + bh * 0.45, cz - bd / 2 - 0.015),
			LABELS[(idx % #LABELS) + 1],
			{ CanCollide = false }
		),
		idx
	)
	tag(
		ModelKit.cylinder(
			model,
			"Product",
			"Y",
			0.14,
			0.16,
			CFrame.new(x - bw * 0.28, y + bh + 0.06, cz - bd * 0.15),
			Color3.fromRGB(210, 40, 40),
			{ CanCollide = false }
		),
		idx
	)
	tag(
		ModelKit.cylinder(
			model,
			"Product",
			"Y",
			0.14,
			0.16,
			CFrame.new(x + bw * 0.28, y + bh + 0.06, cz - bd * 0.15),
			Color3.fromRGB(70, 70, 78),
			{ CanCollide = false }
		),
		idx
	)
end

local function tire(model: Model, idx: number, x: number, y: number, z: number, pitch: number, rs: number)
	local td = math.min(1.25, rs - 0.4)
	local tw = math.min(pitch * 0.78, 0.6)
	local cf = CFrame.new(x, y + td / 2, z + td / 2)
	tag(ModelKit.cylinder(model, "Product", "X", tw, td, cf, Color3.fromRGB(28, 28, 30), { CanCollide = false }), idx)
	tag(
		ModelKit.cylinder(
			model,
			"Product",
			"X",
			tw + 0.06,
			td * 0.6,
			cf,
			Color3.fromRGB(212, 216, 224),
			{ Material = Enum.Material.Metal, Reflectance = 0.5, CanCollide = false }
		),
		idx
	)
	tag(
		ModelKit.cylinder(model, "Product", "X", tw + 0.1, td * 0.2, cf, Color3.fromRGB(70, 72, 80), { CanCollide = false }),
		idx
	)
end

local function oil(model: Model, idx: number, x: number, y: number, z: number, pitch: number, rs: number)
	local bh = math.min(1.0, rs - 0.55)
	local d = math.min(pitch * 0.72, 0.62)
	local cz = z + d / 2
	local color = OIL_COLORS[(idx % #OIL_COLORS) + 1]
	tag(ModelKit.cylinder(model, "Product", "Y", bh, d, CFrame.new(x, y + bh / 2, cz), color, { CanCollide = false }), idx)
	tag(
		ModelKit.cylinder(
			model,
			"Product",
			"Y",
			bh * 0.38,
			d + 0.02,
			CFrame.new(x, y + bh * 0.48, cz),
			Color3.fromRGB(246, 242, 228),
			{ CanCollide = false }
		),
		idx
	)
	tag(
		ModelKit.cylinder(
			model,
			"Product",
			"Y",
			0.14,
			d * 0.42,
			CFrame.new(x, y + bh + 0.07, cz),
			Color3.fromRGB(40, 40, 46),
			{ CanCollide = false }
		),
		idx
	)
end

-- Rims hang from a hook rail at railY.
local function rim(model: Model, idx: number, x: number, railY: number, z: number, pitch: number, rs: number)
	local rd = math.min(1.05, rs - 0.5, pitch * 0.95)
	local cy = railY - rd / 2 + 0.02
	local style = RIM_STYLES[(idx % #RIM_STYLES) + 1]
	local cz = z + 0.1
	tag(
		ModelKit.cylinder(
			model,
			"Product",
			"Z",
			0.1,
			rd,
			CFrame.new(x, cy, cz),
			style[1],
			{ Material = Enum.Material.Metal, Reflectance = 0.55, CanCollide = false }
		),
		idx
	)
	tag(
		ModelKit.cylinder(model, "Product", "Z", 0.06, rd * 0.72, CFrame.new(x, cy, cz - 0.04), style[2], { CanCollide = false }),
		idx
	)
	for _, deg in { 45, -45 } do
		tag(
			ModelKit.part(
				model,
				"Product",
				Vector3.new(rd * 0.7, 0.07, 0.05),
				CFrame.new(x, cy, cz - 0.075) * CFrame.Angles(0, 0, math.rad(deg)),
				style[1],
				{ Material = Enum.Material.Metal, Reflectance = 0.5, CanCollide = false }
			),
			idx
		)
	end
end

return function(level: number, accent: Color3, opts: { [string]: any }?): Model
	local tier = ModelKit.tier(level)
	local lv = tier.level
	local model = ModelKit.model("Station")

	local product = "battery"
	if opts ~= nil and type(opts.product) == "string" and PLATE[opts.product :: string] ~= nil then
		product = opts.product :: string
	end

	local cols, rows, rs, depth = COLS[lv], ROWS[lv], ROW_SPACE[lv], DEPTH[lv]
	local pitch = 8.4 / cols
	local y1 = F + 0.5 -- top of the lowest board
	local topY = y1 + (rows - 1) * rs + rs -- underside/top of the top board
	local frontZ = 1.5 - depth
	local zc = 1.5 - depth / 2
	local ledColor = tier.ledColor(accent)

	------------------------------------------------------------ frame helpers
	local function frame(name: string, size: Vector3, cf: CFrame): Part
		if lv == 1 then
			return ModelKit.part(model, name, size, cf, WOOD, { Material = Enum.Material.Wood })
		elseif lv == 4 then
			return ModelKit.body(model, name, size, cf, accent, tier)
		end
		return ModelKit.metal(model, name, size, cf, tier)
	end
	local function board(name: string, size: Vector3, cf: CFrame): Part
		if lv == 1 then
			return ModelKit.part(model, name, size, cf, WOOD_LIGHT, { Material = Enum.Material.Wood })
		elseif lv == 2 then
			return ModelKit.part(model, name, size, cf, Color3.fromRGB(226, 230, 236), { Material = Enum.Material.Metal, Reflectance = 0.1 })
		elseif lv == 3 then
			return ModelKit.part(model, name, size, cf, Color3.fromRGB(236, 240, 246), { Material = Enum.Material.Metal, Reflectance = 0.3 })
		elseif lv == 4 then
			return ModelKit.trim(model, name, size, cf, tier)
		end
		return ModelKit.part(
			model,
			name,
			size,
			cf,
			Color3.fromRGB(150, 200, 235),
			{ Material = Enum.Material.Glass, Transparency = 0.5, Reflectance = 0.2 }
		)
	end

	------------------------------------------------------------ carcass
	local kick = frame("Kickplate", Vector3.new(8.9, 0.4, depth), CFrame.new(0, F + 0.2, zc))
	local back = frame("BackPanel", Vector3.new(8.6, topY - F, 0.1), CFrame.new(0, (topY + F) / 2, 1.45))
	if lv == 5 then
		back.Material = Enum.Material.Glass
		back.Color = Color3.fromRGB(60, 80, 110)
		back.Transparency = 0.5
	elseif lv == 3 then
		back.Color = Color3.fromRGB(236, 240, 246)
	elseif lv == 1 then
		back.Color = Color3.fromRGB(98, 70, 44)
		ModelKit.rustPatches(model, back, 5, 7)
	end
	for _, s in { -1, 1 } do
		frame("SideUpright", Vector3.new(0.2, topY - F, depth), CFrame.new(s * 4.4, (topY + F) / 2, zc))
	end
	frame("TopBoard", Vector3.new(9.0, 0.25, depth), CFrame.new(0, topY - 0.125, zc))

	if lv >= 4 then
		ModelKit.stripes(model, kick, accent)
	end

	------------------------------------------------------------ boards, lips, LEDs, brackets
	for r = 1, rows do
		local y = y1 + (r - 1) * rs
		board("Board", Vector3.new(8.6, 0.12, depth), CFrame.new(0, y - 0.06, zc))

		if lv == 2 then
			local lip = ModelKit.part(
				model,
				"Lip",
				Vector3.new(8.6, 0.22, 0.08),
				CFrame.new(0, y - 0.01, frontZ - 0.04),
				accent,
				{ Material = Enum.Material.SmoothPlastic }
			)
			ModelKit.role(lip, "Accent")
		elseif lv ~= 5 then
			frame("Lip", Vector3.new(8.6, 0.22, 0.08), CFrame.new(0, y - 0.01, frontZ - 0.04))
		end

		if lv <= 3 then
			for _, s in { -1, 1 } do
				ModelKit.wedge(
					model,
					"Bracket",
					Vector3.new(0.4, 0.5, 0.5),
					CFrame.new(s * (4.3 - 0.25), y - 0.12 - 0.25, zc)
						* CFrame.Angles(0, s * math.pi / 2, 0)
						* CFrame.Angles(0, 0, math.pi),
					if lv == 1 then Color3.fromRGB(122, 70, 38) else tier.metalColor,
					{
						Material = if lv == 1 then Enum.Material.CorrodedMetal else tier.metalMaterial,
						Reflectance = tier.metalReflectance,
					}
				)
			end
		end

		if tier.lights then
			local strip: Part?
			if lv == 5 then
				strip = ModelKit.led(model, "EdgeNeon", Vector3.new(8.6, 0.07, 0.07), CFrame.new(0, y - 0.06, frontZ - 0.03), tier, accent)
			else
				strip = ModelKit.led(model, "LipLED", Vector3.new(8.4, 0.05, 0.05), CFrame.new(0, y - 0.15, frontZ - 0.05), tier, accent)
			end
			if strip and (r == 1 or r == rows) then
				ModelKit.light(strip, ledColor, 9, 0.7)
			end
		end

		-- hook rails for the rims
		if product == "rims" then
			ModelKit.cylinder(
				model,
				"HookRail",
				"X",
				8.4,
				0.07,
				CFrame.new(0, y + rs - 0.35, frontZ + 0.32),
				tier.metalColor,
				{ Material = tier.metalMaterial, Reflectance = tier.metalReflectance }
			)
		end
	end

	------------------------------------------------------------ top: signs by level
	local nameText = PLATE[product]
	if lv == 1 then
		-- leaning cardboard sign
		local sign = ModelKit.part(
			model,
			"CardboardSign",
			Vector3.new(2.4, 0.7, 0.06),
			CFrame.new(0.8, topY + 0.4, 1.3) * CFrame.Angles(0, 0, math.rad(-5)),
			Color3.fromRGB(190, 150, 100),
			{ Material = Enum.Material.Cardboard, CanCollide = false }
		)
		addText(sign, Enum.NormalId.Front, nameText, Color3.fromRGB(70, 40, 20), 40)
	elseif lv == 2 then
		local plate = ModelKit.part(
			model,
			"NamePlate",
			Vector3.new(3.2, 0.42, 0.06),
			CFrame.new(0, topY - 0.25, frontZ - 0.04),
			WHITE,
			{ CanCollide = false }
		)
		addText(plate, Enum.NormalId.Front, nameText, Color3.fromRGB(46, 122, 222), 50)
	elseif lv == 3 then
		local display = ModelKit.part(
			model,
			"PriceDisplay",
			Vector3.new(3.0, 0.42, 0.06),
			CFrame.new(0, topY - 0.25, frontZ - 0.04),
			Color3.fromRGB(8, 10, 12),
			{ CanCollide = false }
		)
		addText(display, Enum.NormalId.Front, nameText .. " $", Color3.fromRGB(120, 255, 150), 50)
		local top = ModelKit.led(model, "TopLED", Vector3.new(8.4, 0.05, 0.05), CFrame.new(0, topY - 0.28, frontZ - 0.02), tier, accent)
		if top then
			ModelKit.light(top, ledColor, 10, 0.8)
		end
	elseif lv == 4 then
		local header = ModelKit.part(
			model,
			"HeaderSign",
			Vector3.new(8.6, 1.0, 0.25),
			CFrame.new(0, topY + 0.55, frontZ + 0.2),
			Color3.fromRGB(14, 14, 16),
			{ Material = Enum.Material.SmoothPlastic, Reflectance = 0.2 }
		)
		addText(header, Enum.NormalId.Front, HEADER[product], accent, 60)
		ModelKit.neon(model, "HeaderNeon", Vector3.new(8.6, 0.06, 0.28), CFrame.new(0, topY + 1.07, frontZ + 0.2), accent)
		ModelKit.neon(model, "HeaderNeon", Vector3.new(8.6, 0.06, 0.28), CFrame.new(0, topY + 0.03, frontZ + 0.2), accent)
		for _, s in { -1, 1 } do
			ModelKit.led(model, "SideLED", Vector3.new(0.06, topY - F - 0.6, 0.06), CFrame.new(s * 4.3, (topY + F) / 2, frontZ - 0.02), tier, accent)
		end
	else
		-- projector + hologram product ad
		ModelKit.cylinder(model, "Projector", "Y", 0.3, 0.7, CFrame.new(0, topY + 0.15, frontZ + 0.6), tier.metalColor, {
			Material = tier.metalMaterial,
			Reflectance = tier.metalReflectance,
		})
		local ring = ModelKit.cylinder(
			model,
			"ProjectorRing",
			"Y",
			0.06,
			0.9,
			CFrame.new(0, topY + 0.32, frontZ + 0.6),
			accent,
			{ Material = Enum.Material.Neon, CanCollide = false, CastShadow = false }
		)
		ModelKit.role(ring, "Accent")
		local holo = ModelKit.hologram(model, CFrame.new(0, topY + 0.65, frontZ + 0.6), Vector2.new(5.4, 0.9), accent)
		holo.Name = "HoloAd"
		addText(holo, Enum.NormalId.Front, AD[product], Color3.fromRGB(255, 255, 255), 60)
		for _, s in { -1, 1 } do
			ModelKit.led(model, "SideNeon", Vector3.new(0.06, topY - F, 0.06), CFrame.new(s * 4.52, (topY + F) / 2, frontZ - 0.02), tier, accent)
		end
	end

	------------------------------------------------------------ products
	local idx = 0
	for r = 1, rows do
		local y = y1 + (r - 1) * rs
		for c = 1, cols do
			idx += 1
			local x = ((cols + 1) / 2 - c) * pitch
			local z = frontZ + 0.15
			if product == "battery" then
				battery(model, idx, x, y, z, pitch, rs)
			elseif product == "tires" then
				tire(model, idx, x, y, z, pitch, rs)
			elseif product == "oil" then
				oil(model, idx, x, y, z, pitch, rs)
			else
				rim(model, idx, x, y + rs - 0.35, frontZ + 0.2, pitch, rs)
			end
		end
	end

	return model
end
