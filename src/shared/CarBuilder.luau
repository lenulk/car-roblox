--!strict
-- Builds customer cars out of Parts (CONTRACT.md section 8).
-- Car space: Root is at the origin on the ground, nose = -Z (LookVector), +X = right side, +Y = up.
-- The caller moves the finished car with model:PivotTo(cf).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CarTypes: any = require(script.Parent.Config.CarTypes)

local CarBuilder = {}

type Props = { [string]: any }

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local RGB = Color3.fromRGB

local SMOOTH = Enum.Material.SmoothPlastic
local PAINT: Props = { Material = SMOOTH, Reflectance = 0.15 }

local TIRE_COLOR = RGB(24, 24, 27)
local RIM_COLOR = RGB(218, 221, 228)
local SPOKE_COLOR = RGB(150, 155, 166)
local HUB_COLOR = RGB(58, 60, 66)
local BUMPER_COLOR = RGB(62, 64, 70)
local DARK = RGB(22, 23, 27)
local GLASS_COLOR = RGB(26, 38, 52)
local SEAT_COLOR = RGB(44, 46, 54)
local CHROME = RGB(222, 225, 232)
local HEADLIGHT = RGB(255, 244, 205)
local TAILLIGHT = RGB(255, 40, 50)

------------------------------------------------------------------------------------------------
-- Generic helpers
------------------------------------------------------------------------------------------------

local function configure(
	p: BasePart,
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	props: Props?
)
	p.Name = name
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = SMOOTH
	p.Size = size
	p.CFrame = cf
	p.Color = color
	if props then
		local any = p :: any
		for k, v in props do
			any[k] = v
		end
	end
	p.Parent = parent
end

local function newBox(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, props: Props?): BasePart
	local p = Instance.new("Part")
	configure(p, parent, name, size, cf, color, props)
	return p
end

-- WedgePart default orientation: tall edge on +Z, slope rising toward +Z (low at -Z).
local function newWedge(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, props: Props?): BasePart
	local p = Instance.new("WedgePart")
	configure(p, parent, name, size, cf, color, props)
	return p
end

-- Cylinder whose axis is the part's local X. Size = (length, diameter, diameter).
local function newCylinder(
	parent: Instance,
	name: string,
	length: number,
	diameter: number,
	cf: CFrame,
	color: Color3,
	props: Props?
): BasePart
	local p = Instance.new("Part")
	configure(p, parent, name, V3(length, diameter, diameter), cf, color, props)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function addPlateGui(plate: BasePart, face: Enum.NormalId, text: string)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "PlateGui"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 1
	gui.Parent = plate

	local label = Instance.new("TextLabel")
	label.Name = "PlateText"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = RGB(20, 28, 60)
	label.Parent = gui
end

------------------------------------------------------------------------------------------------
-- Procedural cars (Sedan / Pickup)
------------------------------------------------------------------------------------------------

local function buildProcedural(carTypeId: string, def: any, color: Color3): Model
	local size: Vector3 = def.size
	local W, H, L = size.X, size.Y, size.Z
	local isPickup = carTypeId == "Pickup"

	local model = Instance.new("Model")
	model.Name = carTypeId

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Anchored = true
	root.Transparency = 1
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.CastShadow = false
	root.TopSurface = Enum.SurfaceType.Smooth
	root.BottomSurface = Enum.SurfaceType.Smooth
	root.Size = V3(W, 0.2, L)
	root.CFrame = CF()
	root.Parent = model
	model.PrimaryPart = root

	local top = Instance.new("Attachment")
	top.Name = "TopAttachment"
	top.Position = V3(0, H + 2, 0)
	top.Parent = root

	local function paint(name: string, s: Vector3, cf: CFrame): BasePart
		return newBox(model, name, s, cf, color, PAINT)
	end
	local function box(name: string, s: Vector3, cf: CFrame, c: Color3, props: Props?): BasePart
		return newBox(model, name, s, cf, c, props)
	end

	-- Key dimensions -------------------------------------------------------------------------
	local D = 0.22 * L -- wheel diameter
	local TW = 0.9 -- tire width
	local Wb = W - 1.6 -- body width (wheels stick out on both sides)
	local gc = 0.55 -- ground clearance of the body
	local lowerH = H * 0.39
	local lowerTop = gc + lowerH
	local zf = -L / 2 + 0.6 -- front face of the body
	local zr = L / 2 - 0.6 -- rear face of the body
	local bodyLen = zr - zf
	local hoodLen = (if isPickup then 0.27 else 0.30) * L
	local hoodTop = lowerTop + 0.3
	local cabinStart = zf + hoodLen
	local cabinEnd = if isPickup then cabinStart + 0.28 * L else zr - 0.2 * L
	local cabinSpan = cabinEnd - cabinStart
	local wedgeFront = 0.36 * cabinSpan
	local wedgeRear = if isPickup then 0 else 0.28 * cabinSpan
	local coreLen = cabinSpan - wedgeFront - wedgeRear
	local coreStart = cabinStart + wedgeFront
	local coreEnd = coreStart + coreLen
	local glassH = H - hoodTop - 0.22
	local glassMidY = hoodTop + glassH / 2
	local Wg = Wb * 0.82 -- glass width
	local deckEnd = if isPickup then cabinEnd else zr

	-- Body ----------------------------------------------------------------------------------
	paint("Body", V3(Wb, lowerH, bodyLen), CF(0, gc + lowerH / 2, (zf + zr) / 2))
	box("Underbody", V3(Wb - 0.4, 0.3, bodyLen - 0.4), CF(0, gc - 0.1, 0), DARK)
	-- hood (+ trunk for the sedan) deck
	paint("BodyPanel", V3(Wb - 0.2, 0.3, deckEnd - zf), CF(0, lowerTop + 0.15, (zf + deckEnd) / 2))

	-- Cabin glass ---------------------------------------------------------------------------
	local glassProps: Props = { Material = Enum.Material.Glass, Transparency = 0.35, Reflectance = 0.1 }
	box("Glass", V3(Wg, glassH, coreLen), CF(0, glassMidY, coreStart + coreLen / 2), GLASS_COLOR, glassProps)
	newWedge(
		model,
		"Windshield",
		V3(Wg, glassH, wedgeFront),
		CF(0, glassMidY, cabinStart + wedgeFront / 2),
		GLASS_COLOR,
		glassProps
	)
	if not isPickup then
		newWedge(
			model,
			"RearWindow",
			V3(Wg, glassH, wedgeRear),
			CF(0, glassMidY, cabinEnd - wedgeRear / 2) * ANG(0, math.pi, 0),
			GLASS_COLOR,
			glassProps
		)
	end

	-- Roof + pillars
	paint("BodyPanel", V3(Wb * 0.9, 0.22, coreLen + 0.5), CF(0, H - 0.11, coreStart + coreLen / 2))
	local pillarZs = { coreStart, coreStart + coreLen / 2, coreEnd }
	for _, sx in { -1, 1 } do
		for _, pz in pillarZs do
			paint("BodyPanel", V3(0.28, glassH, 0.32), CF(sx * Wg / 2, glassMidY, pz))
		end
	end
	if isPickup then
		-- solid back of the cab below the rear window
		paint("BodyPanel", V3(Wg + 0.28, glassH * 0.3, 0.3), CF(0, hoodTop + glassH * 0.15, coreEnd + 0.05))
	end

	-- Interior
	box("Dashboard", V3(Wg - 0.3, 0.5, 0.5), CF(0, hoodTop + 0.25, coreStart + 0.35), SEAT_COLOR)
	for _, sx in { -1, 1 } do
		box(
			"SeatBack",
			V3(Wg * 0.36, glassH * 0.55, 0.3),
			CF(sx * Wg * 0.22, hoodTop + glassH * 0.28, coreStart + coreLen * 0.66),
			SEAT_COLOR
		)
		box("SeatBase", V3(Wg * 0.36, 0.35, 0.9), CF(sx * Wg * 0.22, hoodTop + 0.18, coreStart + coreLen * 0.45), SEAT_COLOR)
	end

	-- Pickup cargo bed ----------------------------------------------------------------------
	if isPickup then
		local bedStart = cabinEnd
		local bedLen = zr - bedStart
		local bedMid = (bedStart + zr) / 2
		box("BedLiner", V3(Wb - 0.9, 0.12, bedLen - 0.3), CF(0, lowerTop + 0.06, bedMid), RGB(38, 40, 46))
		for _, sx in { -1, 1 } do
			paint("BodyPanel", V3(0.35, 1.0, bedLen), CF(sx * (Wb / 2 - 0.175), lowerTop + 0.5, bedMid))
			box(
				"BedRail",
				V3(0.4, 0.08, bedLen),
				CF(sx * (Wb / 2 - 0.175), lowerTop + 1.04, bedMid),
				CHROME,
				{ Material = Enum.Material.Metal, Reflectance = 0.4 }
			)
		end
		paint("BodyPanel", V3(Wb - 0.7, 1.0, 0.3), CF(0, lowerTop + 0.5, bedStart + 0.15))
		paint("BodyPanel", V3(Wb, 1.0, 0.3), CF(0, lowerTop + 0.5, zr - 0.15)) -- tailgate
		box(
			"BedRail",
			V3(Wb, 0.08, 0.36),
			CF(0, lowerTop + 1.04, zr - 0.15),
			CHROME,
			{ Material = Enum.Material.Metal, Reflectance = 0.4 }
		)
	end

	-- Bumpers, grille, lights ----------------------------------------------------------------
	local chromeProps: Props = { Material = Enum.Material.Metal, Reflectance = 0.45 }
	box("Bumper", V3(W - 1.2, 0.8, 0.6), CF(0, gc + 0.4, -L / 2 + 0.3), BUMPER_COLOR)
	box("Bumper", V3(W - 1.2, 0.8, 0.6), CF(0, gc + 0.4, L / 2 - 0.3), BUMPER_COLOR)
	box("BumperTrim", V3(W - 1.6, 0.1, 0.64), CF(0, gc + 0.62, -L / 2 + 0.3), CHROME, chromeProps)
	box("BumperTrim", V3(W - 1.6, 0.1, 0.64), CF(0, gc + 0.62, L / 2 - 0.3), CHROME, chromeProps)

	local lightY = gc + lowerH * 0.72
	local grilleY = gc + lowerH * 0.5
	box("Grille", V3(Wb * 0.42, 0.55, 0.15), CF(0, grilleY, zf - 0.03), DARK)
	box("GrilleBar", V3(Wb * 0.42 + 0.1, 0.07, 0.2), CF(0, grilleY + 0.13, zf - 0.05), CHROME, chromeProps)
	box("GrilleBar", V3(Wb * 0.42 + 0.1, 0.07, 0.2), CF(0, grilleY - 0.13, zf - 0.05), CHROME, chromeProps)

	for _, sx in { -1, 1 } do
		box(
			"Headlight",
			V3(1.0, 0.5, 0.25),
			CF(sx * (Wb / 2 - 0.75), lightY, zf - 0.02),
			HEADLIGHT,
			{ Material = Enum.Material.Neon }
		)
		box(
			"Taillight",
			V3(1.3, 0.45, 0.25),
			CF(sx * (Wb / 2 - 0.8), lightY, zr + 0.02),
			TAILLIGHT,
			{ Material = Enum.Material.Neon }
		)
	end
	box(
		"TaillightBar",
		V3(math.max(Wb - 3.6, 0.5), 0.14, 0.2),
		CF(0, lightY, zr + 0.01),
		RGB(170, 25, 35),
		{ Material = Enum.Material.Neon }
	)

	-- License plates
	local plateText = string.format("GT-%04d", math.random(0, 9999))
	local plateProps: Props = { Material = SMOOTH }
	local plateFront = box("LicensePlate", V3(1.7, 0.75, 0.1), CF(0, gc + 0.4, -L / 2 - 0.05), RGB(245, 245, 245), plateProps)
	addPlateGui(plateFront, Enum.NormalId.Front, plateText)
	local plateRear = box("LicensePlate", V3(1.7, 0.75, 0.1), CF(0, gc + 0.4, L / 2 + 0.05), RGB(245, 245, 245), plateProps)
	addPlateGui(plateRear, Enum.NormalId.Back, plateText)

	-- Exhaust
	newCylinder(
		model,
		"Exhaust",
		0.5,
		0.4,
		CF(Wb / 2 - 0.9, 0.42, L / 2 + 0.1) * ANG(0, math.pi / 2, 0),
		CHROME,
		chromeProps
	)

	-- Side details: mirrors, door seams, handles, trim ---------------------------------------
	for _, sx in { -1, 1 } do
		box("MirrorStalk", V3(0.35, 0.1, 0.15), CF(sx * (Wg / 2 + 0.2), hoodTop + 0.5, coreStart - 0.2), DARK)
		paint("BodyPanel", V3(0.4, 0.3, 0.5), CF(sx * (Wg / 2 + 0.55), hoodTop + 0.55, coreStart - 0.2))

		local seamX = sx * (Wb / 2 + 0.02)
		for _, sz in { coreStart - 0.5, coreStart + coreLen * 0.5, coreEnd + 0.4 } do
			box("DoorSeam", V3(0.05, lowerH * 0.9, 0.06), CF(seamX, gc + lowerH * 0.5, sz), DARK)
		end
		for _, hz in { coreStart + coreLen * 0.5 - 0.6, coreStart + coreLen * 0.5 + 0.6 } do
			box("DoorHandle", V3(0.1, 0.14, 0.55), CF(sx * (Wb / 2 + 0.05), gc + lowerH * 0.82, hz), CHROME, chromeProps)
		end
		box("SideTrim", V3(0.06, 0.1, bodyLen * 0.9), CF(sx * (Wb / 2 + 0.03), gc + lowerH * 0.5, 0), CHROME, chromeProps)
	end

	-- Wheels + fenders ------------------------------------------------------------------------
	local wx = W / 2 - TW / 2
	local wz = 0.31 * L
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local cx, cz = sx * wx, sz * wz
			-- Tire (cylinder axis = X axis of the car, no rotation needed)
			newCylinder(model, "Tire", TW, D, CF(cx, D / 2, cz), TIRE_COLOR)
			-- Rim disc + hub + spokes on the outer face
			local outerX = sx * (wx + TW / 2)
			newCylinder(model, "Rim", 0.12, D * 0.62, CF(outerX, D / 2, cz), RIM_COLOR, chromeProps)
			newCylinder(model, "Hub", 0.18, D * 0.24, CF(outerX + sx * 0.04, D / 2, cz), HUB_COLOR)
			for _, a in { 0, math.rad(60), math.rad(120) } do
				box(
					"Spoke",
					V3(0.1, D * 0.56, 0.2),
					CF(outerX + sx * 0.06, D / 2, cz) * ANG(a, 0, 0),
					SPOKE_COLOR,
					{ Material = Enum.Material.Metal }
				)
			end
			-- Wheel arch: fender slab behind the tire + cap above it
			paint("BodyPanel", V3(0.3, D - 0.1, D + 0.2), CF(sx * (Wb / 2), (0.4 + D + 0.3) / 2, cz))
			paint("BodyPanel", V3(TW + 0.3, 0.28, D + 0.5), CF(cx, D + 0.29, cz))
		end
	end

	-- Welds (after everything is positioned) ---------------------------------------------------
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and child ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = child
			weld.Parent = child
		end
	end

	return model
end

------------------------------------------------------------------------------------------------
-- Art override
------------------------------------------------------------------------------------------------

local function recolorParts(model: Model, color: Color3)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and (d.Name == "Body" or d.Name == "BodyPanel") then
			d.Color = color
		end
	end
end

local function finalizeArt(model: Model, carTypeId: string, color: Color3?): Model
	model.Name = carTypeId

	local root: BasePart? = model.PrimaryPart
	if root == nil then
		local cf, size = model:GetBoundingBox()
		local r = Instance.new("Part")
		r.Name = "Root"
		r.TopSurface = Enum.SurfaceType.Smooth
		r.BottomSurface = Enum.SurfaceType.Smooth
		r.Size = V3(size.X, 0.2, size.Z)
		r.CFrame = CF(cf.Position - cf.UpVector * (size.Y / 2)) * cf.Rotation
		r.Transparency = 1
		r.Parent = model
		model.PrimaryPart = r
		root = r
	end
	local rootPart = root :: BasePart
	if rootPart.Name == "Root" then
		rootPart.Transparency = 1
	end

	-- Drop old welds and collect parts.
	local parts: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("WeldConstraint") then
			d:Destroy()
		elseif d:IsA("BasePart") and d ~= rootPart then
			table.insert(parts, d)
		end
	end

	rootPart.Anchored = true
	rootPart.CanCollide = false
	rootPart.CanTouch = false
	rootPart.CanQuery = false
	rootPart.Massless = true

	if rootPart:FindFirstChild("TopAttachment") == nil then
		local cf, size = model:GetBoundingBox()
		local att = Instance.new("Attachment")
		att.Name = "TopAttachment"
		att.Position = rootPart.CFrame:PointToObjectSpace(cf.Position + cf.UpVector * (size.Y / 2 + 2))
		att.Parent = rootPart
	end

	for _, p in parts do
		p.Anchored = false
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = rootPart
		weld.Part1 = p
		weld.Parent = p
	end

	if color then
		recolorParts(model, color)
	end
	return model
end

------------------------------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------------------------------

function CarBuilder.recolor(model: Model, color: Color3)
	recolorParts(model, color)
end

function CarBuilder.build(carTypeId: string, opts: { color: Color3? }?): Model
	local id = carTypeId
	local def = CarTypes.byId[id]
	if def == nil then
		id = "Sedan"
		def = CarTypes.byId[id]
	end
	local color: Color3? = if opts then opts.color else nil

	local models = ReplicatedStorage:FindFirstChild("Models")
	if models then
		local art = models:FindFirstChild("Car_" .. id)
		if art and art:IsA("Model") then
			return finalizeArt(art:Clone(), id, color)
		end
	end

	local colors: { Color3 } = def.colors
	local paintColor: Color3 = color or colors[math.random(1, #colors)]
	return buildProcedural(id, def, paintColor)
end

return CarBuilder
