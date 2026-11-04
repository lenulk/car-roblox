--!strict
-- Low level part helpers for CarBuilder (not meant to be required from anywhere else).
-- Car space: Root at the origin on the ground, nose = -Z, +X right, +Y up.
-- WedgePart default orientation: sloped face looks up/-Z, the tall vertical edge is at +Z (thin edge at -Z).
-- Cylinder Parts: the axis is the part's local X, Size = (length, diameter, diameter).

local CollectionService = game:GetService("CollectionService")

local Kit = {}

-- CollectionService tags read by the client controller CarFx (Robux rainbow paint / rainbow underglow)
Kit.TAG_RAINBOW_PAINT = "RainbowPaint"
Kit.TAG_RAINBOW_NEON = "RainbowNeon"

export type Props = { [string]: any }

local V3 = Vector3.new
local CF = CFrame.new
local RGB = Color3.fromRGB

Kit.TIRE = RGB(24, 24, 27)
Kit.DARK = RGB(22, 23, 27)
Kit.SEAT = RGB(44, 46, 54)
Kit.CHROME = RGB(222, 225, 232)
Kit.BUMPER = RGB(58, 60, 66)
Kit.CARBON = RGB(28, 28, 32)
Kit.TAILLIGHT = RGB(255, 40, 50)
Kit.WHITE = RGB(245, 245, 245)

Kit.METAL = { Material = Enum.Material.Metal, Reflectance = 0.45 } :: Props
Kit.NEON = { Material = Enum.Material.Neon } :: Props
Kit.CARBON_PROPS = { Material = Enum.Material.DiamondPlate, Reflectance = 0.15 } :: Props

function Kit.configure(
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
	p.Material = Enum.Material.SmoothPlastic
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

-- Returns a table of builder closures that create parts under `parent`.
-- ctx fields used: paintColor, paintProps, glassColor, glassProps.
function Kit.tools(ctx: any, parent: Instance): any
	local T: any = {}

	local function make(class: string, name: string, size: Vector3, cf: CFrame, color: Color3, props: Props?): BasePart
		local p = Instance.new(class) :: any
		Kit.configure(p, parent, name, size, cf, color, props)
		return p :: BasePart
	end

	T.box = function(name: string, size: Vector3, cf: CFrame, color: Color3, props: Props?): BasePart
		return make("Part", name, size, cf, color, props)
	end
	T.wedge = function(name: string, size: Vector3, cf: CFrame, color: Color3, props: Props?): BasePart
		return make("WedgePart", name, size, cf, color, props)
	end
	-- cylinder with its axis along the part's local X
	T.cyl = function(name: string, length: number, dia: number, cf: CFrame, color: Color3, props: Props?): BasePart
		local p = make("Part", name, V3(length, dia, dia), cf, color, props) :: any
		p.Shape = Enum.PartType.Cylinder
		return p :: BasePart
	end
	T.ball = function(name: string, dia: number, cf: CFrame, color: Color3, props: Props?): BasePart
		local p = make("Part", name, V3(dia, dia, dia), cf, color, props) :: any
		p.Shape = Enum.PartType.Ball
		return p :: BasePart
	end
	-- slab between two points: Size = (w, t, |b - a|); the part's -Z axis (its Front face) looks from a toward b
	T.beam = function(name: string, a: Vector3, b: Vector3, w: number, t: number, color: Color3, props: Props?): BasePart
		local d = b - a
		local len = d.Magnitude
		local up = V3(0, 1, 0)
		if len > 0.001 and math.abs(d.Y / len) > 0.97 then
			up = V3(1, 0, 0)
		end
		local cf = CFrame.lookAt((a + b) / 2, b, up)
		return make("Part", name, V3(w, t, math.max(len, 0.05)), cf, color, props)
	end

	-- painted pieces (follow the body paint + material). With the Rainbow paint (ctx.rainbowPaint) every painted
	-- piece gets the "RainbowPaint" tag: the client controller CarFx cycles the hue of tagged parts.
	local function paintTag(p: BasePart): BasePart
		if ctx.rainbowPaint then
			CollectionService:AddTag(p, Kit.TAG_RAINBOW_PAINT)
		end
		return p
	end
	T.pbox = function(name: string, size: Vector3, cf: CFrame): BasePart
		return paintTag(T.box(name, size, cf, ctx.paintColor, ctx.paintProps))
	end
	T.pwedge = function(name: string, size: Vector3, cf: CFrame): BasePart
		return paintTag(T.wedge(name, size, cf, ctx.paintColor, ctx.paintProps))
	end
	T.pcyl = function(name: string, length: number, dia: number, cf: CFrame): BasePart
		return paintTag(T.cyl(name, length, dia, cf, ctx.paintColor, ctx.paintProps))
	end
	T.pbeam = function(name: string, a: Vector3, b: Vector3, w: number, t: number): BasePart
		return paintTag(T.beam(name, a, b, w, t, ctx.paintColor, ctx.paintProps))
	end

	-- glass pieces (follow the tint)
	T.glass = function(name: string, size: Vector3, cf: CFrame): BasePart
		return T.box(name, size, cf, ctx.glassColor, ctx.glassProps)
	end
	T.gwedge = function(name: string, size: Vector3, cf: CFrame): BasePart
		return T.wedge(name, size, cf, ctx.glassColor, ctx.glassProps)
	end
	T.gbeam = function(name: string, a: Vector3, b: Vector3, w: number, t: number): BasePart
		return T.beam(name, a, b, w, t, ctx.glassColor, ctx.glassProps)
	end

	return T
end

function Kit.addPlateGui(plate: BasePart, face: Enum.NormalId, text: string)
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

function Kit.addNumberGui(part: BasePart, face: Enum.NormalId, text: string)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "NumberGui"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 1
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Name = "NumberText"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = RGB(20, 20, 24)
	label.Parent = gui
end

-- Weld every BasePart descendant of `model` (except Root) to Root, wheel parts to their Hub, and Hub to Root ("WheelWeld").
function Kit.weldAll(model: Model, root: BasePart)
	local function weld(a: BasePart, b: BasePart, name: string, parent: Instance)
		local w = Instance.new("WeldConstraint")
		w.Name = name
		w.Part0 = a
		w.Part1 = b
		w.Parent = parent
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= root then
			local parent = d.Parent
			if parent and parent:IsA("Model") and parent ~= model and parent.PrimaryPart ~= nil then
				local hub = parent.PrimaryPart :: BasePart
				if d == hub then
					weld(root, d, "WheelWeld", d)
				else
					weld(hub, d, "Weld", d)
				end
			else
				weld(root, d, "Weld", d)
			end
		end
	end
end

Kit.V3 = V3
Kit.CF = CF

return Kit
