--!strict
-- Storefront decoration models (Config/Decor.luau). DecorModels.build(id, frame) returns a Model made of anchored
-- Parts (CanCollide false except the plinths), at most ~60 parts each, built in the ModelKit style.
--
-- `frame` is the world CFrame of the slot centre on the ground; the model is built in that local space with its FRONT
-- (the side people see from the road) at -Z.
--
-- Animation is NOT done here: parts that move carry attributes the client controller DecorAnimator reads
--   Anim      string  role ("TubeSeg", "RobotHead", "Spin" ...)
--   AnimIdx   number  index inside the role (optional)
--   AnimPivot Vector3 WORLD position the part rotates around (optional)
--   OnColor   Color3  lit colour of blinking parts (optional)
-- Particle emitters for bursts are created disabled here (Rate 0) and Emit()-ed by the client.

local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local ModelKit = require(Shared.ModelKit)

local DecorModels = {}

type Ctx = { model: Model, frame: CFrame }
type Props = { [string]: any }

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local RGB = Color3.fromRGB
local PI = math.pi

local METAL = Enum.Material.Metal
local NEON = Enum.Material.Neon

local DARK = RGB(30, 32, 40)
local STEEL = RGB(140, 150, 166)
local CHROME = RGB(222, 226, 234)
local GOLD = RGB(255, 196, 48)

DecorModels.TAG = "DecorModel"

----------------------------------------------------------------------------------------------------
-- Tiny part toolkit (positions are local to the slot frame)
----------------------------------------------------------------------------------------------------

local function newCtx(id: string, frame: CFrame): Ctx
	local model = ModelKit.model(id)
	local pivot = model.PrimaryPart :: BasePart
	pivot.CFrame = frame
	model:SetAttribute("Decor", id)
	return { model = model, frame = frame }
end

local function style(props: Props?): Props
	local out: Props = { CanCollide = false, CanTouch = false }
	if props then
		for k, v in props do
			out[k] = v
		end
	end
	return out
end

local function box(c: Ctx, name: string, size: Vector3, cf: CFrame, color: Color3, props: Props?): Part
	return ModelKit.part(c.model, name, size, c.frame * cf, color, style(props))
end

local function ball(c: Ctx, name: string, dia: number, cf: CFrame, color: Color3, props: Props?): Part
	return ModelKit.ball(c.model, name, dia, c.frame * cf, color, style(props))
end

-- cylinder whose length runs along `axis` ("X" | "Y" | "Z") of cf
local function cyl(c: Ctx, name: string, axis: string, length: number, dia: number, cf: CFrame, color: Color3, props: Props?): Part
	return ModelKit.cylinder(c.model, name, axis, length, dia, c.frame * cf, color, style(props))
end

local function wedge(c: Ctx, name: string, size: Vector3, cf: CFrame, color: Color3, props: Props?): WedgePart
	return ModelKit.wedge(c.model, name, size, c.frame * cf, color, style(props))
end

local function upFor(dir: Vector3): Vector3
	return if math.abs(dir.Unit.Y) > 0.98 then V3(1, 0, 0) else V3(0, 1, 0)
end

-- square beam from a to b
local function beam(c: Ctx, name: string, a: Vector3, b: Vector3, w: number, color: Color3, props: Props?): Part
	local len = math.max((b - a).Magnitude, 0.05)
	return box(c, name, V3(w, w, len), CFrame.lookAt((a + b) / 2, b, upFor(b - a)), color, props)
end

-- round bar from a to b (length along the part's X axis)
local function bar(c: Ctx, name: string, a: Vector3, b: Vector3, dia: number, color: Color3, props: Props?): Part
	local len = math.max((b - a).Magnitude, 0.05)
	local cf = CFrame.lookAt((a + b) / 2, b, upFor(b - a)) * ANG(0, PI / 2, 0)
	local p = box(c, name, V3(len, dia, dia), cf, color, props)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- marks a part for the client animator
local function anim(c: Ctx, p: BasePart, role: string, idx: number?, pivot: Vector3?): BasePart
	p:SetAttribute("Anim", role)
	if idx then
		p:SetAttribute("AnimIdx", idx)
	end
	if pivot then
		p:SetAttribute("AnimPivot", c.frame:PointToWorldSpace(pivot))
	end
	return p
end

local function light(parent: BasePart, color: Color3, range: number, brightness: number): PointLight
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Parent = parent
	return l
end

local function signText(part: BasePart, text: string, face: Enum.NormalId, color: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 36
	gui.LightInfluence = 0
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color
	label.Parent = gui
end

local function emitter(parent: Instance, name: string): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Enabled = false
	e.Rate = 0
	e.Parent = parent
	return e
end

----------------------------------------------------------------------------------------------------
-- Money decorations
----------------------------------------------------------------------------------------------------

local FLAG_COLORS = { RGB(235, 70, 70), RGB(250, 200, 50), RGB(60, 160, 235), RGB(90, 200, 110), RGB(240, 120, 200) }

local function buildBunting(c: Ctx)
	local poleH = 9
	for _, sx in { -1, 1 } do
		cyl(c, "Pole", "Y", poleH, 0.5, CF(sx * 5.6, poleH / 2, 0), RGB(190, 190, 198), { Material = METAL })
		cyl(c, "PoleBase", "Y", 0.5, 1.8, CF(sx * 5.6, 0.25, 0), RGB(70, 72, 80))
	end
	local n = 10
	local function stringPoint(u: number): Vector3
		return V3(-5.6 + 11.2 * u, poleH - 0.4 - 1.6 * 4 * u * (1 - u), 0)
	end
	local prev = stringPoint(0)
	for i = 1, n do
		local point = stringPoint(i / n)
		beam(c, "String", prev, point, 0.12, RGB(60, 60, 66))
		prev = point
	end
	for i = 0, n - 1 do
		local top = stringPoint((i + 0.5) / n)
		local flag = box(c, "Flag", V3(0.95, 0.95, 0.08), CF(top.X, top.Y - 0.5, 0) * ANG(0, 0, PI / 4), FLAG_COLORS[i % #FLAG_COLORS + 1])
		anim(c, flag, "Sway", i, top)
	end
end

local function buildOpenSign(c: Ctx)
	for _, sx in { -1, 1 } do
		box(c, "Post", V3(0.4, 6.2, 0.4), CF(sx * 3.2, 3.1, 0), DARK)
	end
	local board = box(c, "Board", V3(8.6, 3.6, 0.5), CF(0, 7.1, 0), RGB(18, 20, 28))
	local textColor = RGB(255, 70, 90)
	signText(board, "OPEN", Enum.NormalId.Front, textColor)
	board:SetAttribute("OnColor", textColor)
	anim(c, board, "OpenText")
	local neonColor = RGB(60, 200, 255)
	local strips: { { size: Vector3, cf: CFrame } } = {
		{ size = V3(8.9, 0.25, 0.3), cf = CF(0, 7.1 + 1.85, -0.2) },
		{ size = V3(8.9, 0.25, 0.3), cf = CF(0, 7.1 - 1.85, -0.2) },
		{ size = V3(0.25, 3.7, 0.3), cf = CF(-4.4, 7.1, -0.2) },
		{ size = V3(0.25, 3.7, 0.3), cf = CF(4.4, 7.1, -0.2) },
	}
	for i, strip in strips do
		local part = box(c, "NeonFrame", strip.size, strip.cf, neonColor, { Material = NEON })
		part:SetAttribute("OnColor", neonColor)
		anim(c, part, "OpenNeon", i)
		if i == 1 then
			light(part, neonColor, 18, 1)
		end
	end
end

local function buildTubeMan(c: Ctx)
	local body = RGB(255, 90, 40)
	local stripe = RGB(255, 220, 40)
	box(c, "Blower", V3(2.6, 1.2, 2.6), CF(0, 0.6, 0), DARK)
	cyl(c, "BlowerFan", "Z", 0.15, 1.8, CF(0, 0.65, -1.35), RGB(90, 94, 106))
	local segments = 7
	local segH = 1.15
	for i = 1, segments do
		local y = 1.2 + (i - 0.5) * segH
		local dia = 1.9 - (i - 1) * 0.04
		local seg = cyl(c, "TubeSeg", "Y", segH + 0.05, dia, CF(0, y, 0), if i % 2 == 0 then stripe else body)
		anim(c, seg, "TubeSeg", i)
	end
	local topY = 1.2 + segments * segH
	local head = ball(c, "Head", 2.3, CF(0, topY + 0.9, 0), body)
	anim(c, head, "TubeHead")
	for _, sx in { -1, 1 } do
		anim(c, ball(c, "Eye", 0.55, CF(sx * 0.55, topY + 1.2, -1.0), RGB(255, 255, 255)), "TubeHead")
		anim(c, ball(c, "Pupil", 0.25, CF(sx * 0.55, topY + 1.2, -1.28), RGB(20, 20, 24)), "TubeHead")
	end
	anim(c, box(c, "Mouth", V3(1.0, 0.3, 0.12), CF(0, topY + 0.55, -1.1), RGB(120, 20, 30)), "TubeHead")
	-- flailing arms: three bars each, rigid, rotating around the shoulder
	local shoulderY = topY - 0.8
	for _, sx in { -1, 1 } do
		local shoulder = V3(sx * 0.8, shoulderY, 0)
		local dir = V3(sx * 0.6, 0.8, 0).Unit
		for k = 0, 2 do
			local a = shoulder + dir * (1.5 * k)
			local b = shoulder + dir * (1.5 * (k + 1))
			anim(c, bar(c, "Arm", a, b, 0.9 - k * 0.08, if k % 2 == 0 then stripe else body), "TubeArm", sx, shoulder)
		end
		anim(c, ball(c, "Hand", 1.0, CF(shoulder + dir * 4.6), body), "TubeArm", sx, shoulder)
	end
end

local BALLOON_COLORS = {
	RGB(235, 70, 70),
	RGB(250, 200, 50),
	RGB(60, 160, 235),
	RGB(90, 200, 110),
	RGB(240, 120, 200),
	RGB(255, 140, 40),
}

local function buildBalloonArch(c: Ctx)
	for _, sx in { -1, 1 } do
		box(c, "Weight", V3(2.2, 0.8, 2.2), CF(sx * 5, 0.4, 0), RGB(70, 72, 80))
	end
	local radius = 5
	local steps = 12
	for i = 0, steps do
		local a = i * PI / steps
		local pos = V3(math.cos(a) * radius, math.sin(a) * radius + 0.9, 0)
		ball(c, "Balloon", 1.9, CF(pos), BALLOON_COLORS[i % #BALLOON_COLORS + 1], { Material = Enum.Material.SmoothPlastic, Reflectance = 0.15 })
		if i < steps then
			local a2 = (i + 0.5) * PI / steps
			local z = if i % 2 == 0 then 0.7 else -0.7
			local pos2 = V3(math.cos(a2) * (radius + 0.25), math.sin(a2) * (radius + 0.25) + 0.9, z)
			ball(c, "Balloon", 1.4, CF(pos2), BALLOON_COLORS[(i + 3) % #BALLOON_COLORS + 1], { Reflectance = 0.15 })
		end
	end
end

-- Cars for the statues. They return every part they made so the caller can mark them for animation.
local function classicCar(c: Ctx, y0: number, bodyColor: Color3, trimColor: Color3): { BasePart }
	local parts: { BasePart } = {}
	local function add(p: BasePart): BasePart
		table.insert(parts, p)
		return p
	end
	local paint: Props = { Material = METAL, Reflectance = 0.3 }
	local chrome: Props = { Material = METAL, Reflectance = 0.6 }
	add(box(c, "Body", V3(3.6, 1.2, 6.4), CF(0, y0 + 1.3, 0.2), bodyColor, paint))
	add(box(c, "Hood", V3(3.2, 0.9, 2.6), CF(0, y0 + 1.55, -2.7), bodyColor, paint))
	for _, sx in { -1, 1 } do
		add(box(c, "FenderFront", V3(0.7, 0.5, 2.2), CF(sx * 1.95, y0 + 1.0, -2.5), trimColor, paint))
		add(box(c, "FenderRear", V3(0.7, 0.5, 2.2), CF(sx * 1.95, y0 + 1.0, 2.6), trimColor, paint))
		add(box(c, "RunningBoard", V3(0.5, 0.15, 3.0), CF(sx * 1.95, y0 + 0.7, 0), trimColor))
		add(ball(c, "Headlight", 0.8, CF(sx * 1.2, y0 + 1.75, -3.95), RGB(255, 240, 180), { Material = NEON }))
		add(box(c, "Taillight", V3(0.5, 0.35, 0.15), CF(sx * 1.3, y0 + 1.6, 3.45), RGB(255, 50, 60), { Material = NEON }))
	end
	add(box(c, "Cabin", V3(3.0, 1.3, 2.6), CF(0, y0 + 2.5, 0.8), bodyColor, paint))
	add(box(c, "Windows", V3(3.06, 0.8, 2.1), CF(0, y0 + 2.6, 0.8), RGB(140, 190, 210), { Transparency = 0.25 }))
	add(box(c, "Roof", V3(3.2, 0.18, 2.9), CF(0, y0 + 3.2, 0.8), trimColor, paint))
	add(box(c, "Grille", V3(1.5, 1.0, 0.15), CF(0, y0 + 1.4, -4.05), CHROME, chrome))
	add(box(c, "BumperFront", V3(3.8, 0.3, 0.4), CF(0, y0 + 0.8, -4.15), CHROME, chrome))
	add(box(c, "BumperRear", V3(3.8, 0.3, 0.4), CF(0, y0 + 0.8, 3.65), CHROME, chrome))
	for _, sx in { -1, 1 } do
		for _, z in { -2.5, 2.6 } do
			add(cyl(c, "Wheel", "X", 0.7, 1.7, CF(sx * 1.9, y0 + 0.85, z), RGB(25, 25, 28)))
			add(cyl(c, "Hubcap", "X", 0.76, 0.9, CF(sx * 1.9, y0 + 0.85, z), CHROME, chrome))
		end
	end
	return parts
end

local function plinth(c: Ctx, dia: number, ringColor: Color3): number
	cyl(c, "Plinth", "Y", 1.4, dia, CF(0, 0.7, 0), RGB(196, 198, 208), { CanCollide = true, Material = Enum.Material.Marble })
	cyl(c, "PlinthRing", "Y", 0.25, dia + 0.5, CF(0, 1.3, 0), ringColor, { Material = METAL, Reflectance = 0.4 })
	return 1.4
end

local function buildClassicStatue(c: Ctx)
	local y0 = plinth(c, 10, RGB(210, 170, 70))
	classicCar(c, y0, RGB(70, 190, 190), RGB(240, 230, 200))
	box(c, "Plaque", V3(2.4, 0.9, 0.12), CF(0, 0.7, -5.05), RGB(210, 170, 70), { Material = METAL })
end

local function buildSearchlight(c: Ctx)
	box(c, "Base", V3(3.4, 1.0, 3.4), CF(0, 0.5, 0), DARK)
	cyl(c, "Post", "Y", 4.0, 1.0, CF(0, 3.0, 0), STEEL, { Material = METAL })
	local head = V3(0, 5.0, 0)
	local dir = V3(0, 1, -0.3).Unit
	local pivot = head
	anim(c, bar(c, "Housing", head - dir * 1.3, head + dir * 1.3, 2.7, DARK), "SearchHead", nil, pivot)
	local lens = bar(c, "Lens", head + dir * 1.25, head + dir * 1.55, 2.3, RGB(255, 255, 240), { Material = NEON })
	anim(c, lens, "SearchHead", nil, pivot)
	-- the lens light only shines at night (LightingService turns NightLight lights on at dusk), so the beam stands out then
	light(lens, RGB(220, 240, 255), 26, 2):SetAttribute("NightLight", true)
	local sky = box(
		c,
		"Beam",
		V3(2.2, 2.2, 110),
		CFrame.lookAt(head + dir * 56, head + dir * 112),
		RGB(190, 230, 255),
		{ Material = NEON, Transparency = 0.82, CastShadow = false }
	)
	anim(c, sky, "SearchHead", nil, pivot)
end

----------------------------------------------------------------------------------------------------
-- Robux decorations
----------------------------------------------------------------------------------------------------

local function buildMascotBear(c: Ctx)
	local fur = RGB(150, 100, 60)
	local furLight = RGB(225, 185, 140)
	local denim = RGB(50, 90, 170)
	local red = RGB(205, 45, 45)
	local black = RGB(20, 20, 24)

	-- legs + feet
	for _, sx in { -1, 1 } do
		cyl(c, "Leg", "Y", 2.0, 2.2, CF(sx * 1.3, 1.0, 0), fur)
		box(c, "Foot", V3(1.9, 0.6, 2.6), CF(sx * 1.3, 0.3, -0.3), furLight)
	end
	ball(c, "Body", 5.2, CF(0, 4.0, 0), fur)
	ball(c, "Tail", 1.2, CF(0, 2.6, 2.6), furLight)
	-- overalls: pants, bib, straps, buttons, pocket
	box(c, "Overalls", V3(4.5, 2.2, 3.7), CF(0, 2.9, 0), denim)
	box(c, "Bib", V3(3.0, 2.0, 0.3), CF(0, 4.5, -1.95), denim)
	for _, sx in { -1, 1 } do
		box(c, "Strap", V3(0.55, 2.4, 0.3), CF(sx * 1.15, 5.3, -1.6) * ANG(0.45, 0, 0), denim)
		ball(c, "Button", 0.5, CF(sx * 1.15, 4.6, -2.15), RGB(255, 210, 60))
	end
	box(c, "Pocket", V3(1.6, 1.0, 0.1), CF(0, 4.2, -2.12), RGB(35, 70, 140))

	-- head
	ball(c, "Head", 4.6, CF(0, 7.7, 0), fur)
	ball(c, "Snout", 2.1, CF(0, 7.1, -2.0), furLight)
	ball(c, "Nose", 0.85, CF(0, 7.6, -3.0), black)
	for _, sx in { -1, 1 } do
		ball(c, "Eye", 0.75, CF(sx * 1.1, 8.2, -2.0), black)
		ball(c, "EyeShine", 0.28, CF(sx * 1.0, 8.4, -2.35), CHROME)
		ball(c, "Ear", 1.8, CF(sx * 2.1, 9.5, 0.1), fur)
		ball(c, "EarInner", 1.0, CF(sx * 2.1, 9.5, -0.55), furLight)
	end
	-- mechanic cap
	ball(c, "Cap", 4.3, CF(0, 9.55, 0.1), red)
	box(c, "CapBrim", V3(3.2, 0.2, 1.7), CF(0, 9.1, -2.3) * ANG(0.2, 0, 0), RGB(150, 25, 25))
	ball(c, "CapBadge", 0.8, CF(0, 9.9, -2.0), CHROME, { Material = METAL })

	-- left arm (down, holds a wrench) and right arm (up, waves)
	local shoulderL = V3(-2.7, 5.4, 0)
	bar(c, "ArmLeft", shoulderL, V3(-3.6, 3.4, -0.5), 1.5, fur)
	ball(c, "HandLeft", 1.6, CF(-3.6, 3.2, -0.5), furLight)
	box(c, "WrenchHandle", V3(0.3, 2.6, 0.3), CF(-3.6, 3.2, -1.4) * ANG(0.3, 0, 0), STEEL, { Material = METAL })
	box(c, "WrenchHead", V3(1.1, 0.6, 0.3), CF(-3.6, 4.5, -1.8), STEEL, { Material = METAL })
	local shoulderR = V3(2.7, 5.4, 0)
	anim(c, bar(c, "ArmRight", shoulderR, V3(4.0, 7.8, -0.4), 1.5, fur), "BearArm", nil, shoulderR)
	anim(c, ball(c, "HandRight", 1.6, CF(4.1, 8.1, -0.4), furLight), "BearArm", nil, shoulderR)

	-- confetti, fired by the client when a repair finishes
	local confetti = emitter(c.model:FindFirstChild("Cap") :: Instance, "Confetti")
	confetti.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	confetti.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, RGB(255, 80, 80)),
		ColorSequenceKeypoint.new(0.25, RGB(255, 220, 60)),
		ColorSequenceKeypoint.new(0.5, RGB(80, 220, 120)),
		ColorSequenceKeypoint.new(0.75, RGB(80, 160, 255)),
		ColorSequenceKeypoint.new(1, RGB(240, 100, 220)),
	})
	confetti.Lifetime = NumberRange.new(1.2, 2)
	confetti.Speed = NumberRange.new(12, 22)
	confetti.SpreadAngle = Vector2.new(60, 60)
	confetti.Acceleration = V3(0, -18, 0)
	confetti.Size = NumberSequence.new(0.5)
	confetti.Rotation = NumberRange.new(0, 360)
	confetti.RotSpeed = NumberRange.new(-300, 300)
	confetti.LightEmission = 0.4
	confetti.EmissionDirection = Enum.NormalId.Top

	-- every part without its own role jumps / bobs with the bear
	for _, d in c.model:GetChildren() do
		if d:IsA("BasePart") and d.Name ~= "Pivot" and d:GetAttribute("Anim") == nil then
			d:SetAttribute("Anim", "BearBody")
		end
	end
end

local function buildMechRobot(c: Ctx)
	local orange = RGB(235, 130, 30)
	local cyan = RGB(60, 230, 255)
	local steelProps: Props = { Material = METAL, Reflectance = 0.25 }

	for _, sx in { -1, 1 } do
		box(c, "Foot", V3(2.3, 0.8, 3.4), CF(sx * 1.7, 0.4, -0.2), DARK)
		bar(c, "Shin", V3(sx * 1.7, 0.8, 0), V3(sx * 1.7, 3.6, 0), 1.4, STEEL, steelProps)
		ball(c, "Knee", 1.8, CF(sx * 1.7, 3.8, 0), orange)
		box(c, "Thigh", V3(1.7, 2.6, 1.9), CF(sx * 1.7, 5.3, 0), STEEL, steelProps)
	end
	box(c, "Hip", V3(4.8, 1.0, 2.7), CF(0, 6.9, 0), DARK)
	box(c, "Torso", V3(5.4, 4.2, 3.4), CF(0, 9.5, 0), orange, steelProps)
	box(c, "ChestPanel", V3(3.2, 2.4, 0.2), CF(0, 9.9, -1.75), DARK)
	local core = ball(c, "Core", 1.3, CF(0, 9.9, -1.95), cyan, { Material = NEON })
	light(core, cyan, 14, 1.5)
	for _, sx in { -1, 1 } do
		ball(c, "Shoulder", 2.4, CF(sx * 3.5, 10.9, 0), STEEL, steelProps)
	end
	cyl(c, "Neck", "Y", 0.8, 1.0, CF(0, 11.9, 0), DARK)

	-- head: turns to follow arriving cars (client)
	local neck = V3(0, 11.9, 0)
	local function headPart(p: BasePart): BasePart
		return anim(c, p, "RobotHead", nil, neck)
	end
	headPart(box(c, "Head", V3(2.9, 2.3, 2.7), CF(0, 13.1, 0), STEEL, steelProps))
	headPart(box(c, "Visor", V3(2.5, 0.8, 0.2), CF(0, 13.2, -1.4), DARK))
	for _, sx in { -1, 1 } do
		local eye = headPart(box(c, "Eye", V3(0.75, 0.45, 0.15), CF(sx * 0.62, 13.2, -1.52), cyan, { Material = NEON }))
		light(eye, cyan, 8, 1)
	end
	headPart(cyl(c, "Antenna", "Y", 1.2, 0.2, CF(0.9, 14.9, 0), DARK))
	headPart(ball(c, "AntennaTip", 0.5, CF(0.9, 15.6, 0), RGB(255, 60, 60), { Material = NEON }))

	-- left arm
	bar(c, "UpperArmL", V3(-3.5, 10.9, 0), V3(-4.3, 8.3, 0), 1.2, STEEL, steelProps)
	bar(c, "ForearmL", V3(-4.3, 8.3, 0), V3(-4.4, 6.3, -0.8), 1.1, STEEL, steelProps)
	ball(c, "FistL", 1.7, CF(-4.4, 6.0, -0.8), orange)
	-- right arm with the giant wrench
	bar(c, "UpperArmR", V3(3.5, 10.9, 0), V3(4.3, 8.5, -0.2), 1.2, STEEL, steelProps)
	bar(c, "ForearmR", V3(4.3, 8.5, -0.2), V3(4.6, 6.8, -1.2), 1.1, STEEL, steelProps)
	ball(c, "FistR", 1.7, CF(4.6, 6.5, -1.2), orange)
	local hand = V3(4.6, 6.5, -1.2)
	local wrenchProps: Props = { Material = METAL, Reflectance = 0.5 }
	local function wrenchPart(p: BasePart): BasePart
		return anim(c, p, "Wrench", nil, hand)
	end
	wrenchPart(box(c, "WrenchHandle", V3(0.75, 9.0, 0.55), CF(4.6, 10.2, -1.9), CHROME, wrenchProps))
	wrenchPart(box(c, "WrenchJawBase", V3(2.6, 0.8, 0.55), CF(4.6, 15.0, -1.9), CHROME, wrenchProps))
	for _, sx in { -1, 1 } do
		wrenchPart(box(c, "WrenchJaw", V3(0.7, 1.8, 0.55), CF(4.6 + sx * 0.95, 16.1, -1.9), CHROME, wrenchProps))
	end
end

-- filled triangle a-b-c (slot-local points) from two wedges
local function triangle(c: Ctx, name: string, a: Vector3, b: Vector3, d: Vector3, color: Color3, props: Props?): { BasePart }
	local ab, ac, bc = b - a, d - a, d - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		d, a = a, d
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, d - a, d - b
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	local w1 = wedge(c, name, V3(0.12, height, math.abs(ab:Dot(back))), CFrame.fromMatrix((a + b) / 2, right, up, back), color, props)
	local w2 = wedge(c, name, V3(0.12, height, math.abs(ac:Dot(back))), CFrame.fromMatrix((a + d) / 2, -right, up, -back), color, props)
	return { w1, w2 }
end

-- A neon serpent dragon coiled on a rock: tail wrapped around the base, body rearing up, horned head with an
-- open jaw facing the road (-Z), bat wings that flap. AnimIdx 0..10 = how much a part sways (tail 0, head 10);
-- wings carry their side (-1 / 1) and pivot at the shoulder.
local function buildNeonDragon(c: Ctx)
	local cyan = RGB(0, 230, 255)
	local dark = RGB(22, 24, 34)
	local glow = { Material = NEON }
	cyl(c, "Rock", "Y", 0.8, 10, CF(0, 0.4, 0), RGB(44, 46, 58), { Material = Enum.Material.Slate })

	local P = {
		V3(3.0, 1.1, 2.2), V3(3.7, 1.2, -0.6), V3(2.4, 1.3, -3.0), V3(-0.4, 1.4, -3.8),
		V3(-3.0, 1.6, -2.4), V3(-3.6, 1.9, 0.6), V3(-1.8, 2.5, 2.9), V3(0.8, 3.5, 2.8),
		V3(1.9, 5.1, 1.2), V3(1.2, 6.9, -0.2), V3(-0.2, 8.5, -0.4), V3(-0.4, 10.0, -1.4),
	}
	local D = { 0.45, 0.8, 1.1, 1.4, 1.7, 1.9, 2.1, 2.2, 2.1, 1.9, 1.6, 1.4 }
	local function weight(i: number): number
		return if i <= 7 then 0 else (i - 7) * 2
	end

	-- body: a ball at every joint, a tube between joints
	for i = 1, #P do
		anim(c, ball(c, "Body", D[i], CF(P[i]), cyan, glow), "DragonNeon", weight(i))
		if i < #P then
			anim(c, bar(c, "Body", P[i], P[i + 1], (D[i] + D[i + 1]) / 2 * 0.92, cyan, glow), "DragonNeon", weight(i))
		end
	end
	-- tail fin and back spikes
	anim(c, wedge(c, "TailFin", V3(0.2, 1.1, 1.3), CFrame.lookAt(P[1] + V3(0, 0.3, 0.3), P[1] + V3(0, 0.3, 2)), dark), "DragonSeg", 0)
	for i = 8, 11 do -- only on the rearing part (spikes on the flat coil look like debris)
		local tangent = (P[i + 1] - P[i]).Unit
		local backDir = if i >= 9 then V3(0, 0.35, 1).Unit else V3(0, 1, 0)
		local pos = P[i] + backDir * (D[i] / 2 + 0.3)
		anim(c, wedge(c, "Spike", V3(0.2, 0.9, 0.9), CFrame.lookAt(pos, pos - tangent, backDir), dark), "DragonSeg", weight(i))
	end

	-- head (faces -Z, tipped slightly down)
	local headCF = CFrame.new(P[12] + V3(0, 0.9, -1.5)) * ANG(-0.12, 0, 0)
	local function hp(x: number, y: number, z: number): Vector3
		return headCF:PointToWorldSpace(V3(x, y, z))
	end
	local skull = box(c, "Head", V3(2.4, 2.0, 2.6), headCF, cyan, glow)
	anim(c, skull, "DragonNeon", 10)
	light(skull, cyan, 24, 1.5)
	anim(c, box(c, "Snout", V3(1.9, 1.1, 2.6), headCF * CF(0, -0.35, -2.3), cyan, glow), "DragonNeon", 10)
	anim(c, box(c, "Jaw", V3(1.7, 0.45, 2.5), headCF * CF(0, -1.25, -1.7) * ANG(-0.3, 0, 0), dark), "DragonSeg", 10)
	local nose = box(c, "Nose", V3(0.3, 0.3, 0.3), headCF * CF(0, -0.2, -3.7), dark, { Transparency = 1 })
	anim(c, nose, "DragonSeg", 10)
	local puff = emitter(nose, "Puff")
	puff.Texture = "rbxasset://textures/particles/smoke_main.dds"
	puff.Color = ColorSequence.new(RGB(200, 235, 255), RGB(90, 110, 140))
	puff.Lifetime = NumberRange.new(1.4, 2.2)
	puff.Speed = NumberRange.new(3, 6)
	puff.SpreadAngle = Vector2.new(25, 25)
	puff.Acceleration = V3(0, 2.5, 0)
	puff.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 3.4) })
	puff.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	puff.EmissionDirection = Enum.NormalId.Front
	for _, sx in { -1, 1 } do
		anim(c, ball(c, "Eye", 0.6, CFrame.new(hp(sx * 1.05, 0.35, -0.9)), RGB(255, 245, 120), glow), "DragonSeg", 10)
		anim(c, bar(c, "Horn", hp(sx * 0.7, 0.9, 0.6), hp(sx * 1.3, 2.5, 2.3), 0.45, dark), "DragonSeg", 10)
		anim(c, bar(c, "Whisker", hp(sx * 0.9, -0.5, -3.2), hp(sx * 2.4, -1.5, -2.2), 0.15, cyan, glow), "DragonNeon", 10)
		-- front arm with a claw
		local shoulder = P[10] + V3(sx * 1.0, -0.4, -0.4)
		local hand = P[10] + V3(sx * 1.7, -2.1, -1.8)
		anim(c, bar(c, "Arm", shoulder, hand, 0.5, cyan, glow), "DragonNeon", 8)
		anim(c, ball(c, "Claw", 0.6, CFrame.new(hand), dark), "DragonSeg", 8)

		-- bat wing: bones + translucent glowing membrane, pivoting at the shoulder
		local root = P[10] + V3(sx * 0.9, 0.2, 0.9)
		local elbow = root + V3(sx * 3.2, 2.4, 1.2)
		local tip = root + V3(sx * 6.4, 3.8, 2.2)
		local low1 = root + V3(sx * 5.6, -0.6, 2.0)
		local low2 = root + V3(sx * 2.6, -1.8, 1.4)
		for _, bone in { { root, elbow, 0.4 }, { elbow, tip, 0.3 }, { elbow, low1, 0.2 } } do
			anim(c, bar(c, "WingBone", bone[1], bone[2], bone[3], dark), "DragonWing", sx, root)
		end
		local membrane = { Material = NEON, Transparency = 0.35 }
		for _, tri in { { root, elbow, low2 }, { elbow, low1, low2 }, { elbow, tip, low1 } } do
			for _, w in triangle(c, "Wing", tri[1], tri[2], tri[3], cyan, membrane) do
				anim(c, w, "DragonWingGlow", sx, root)
			end
		end
	end
end

local function buildGoldStatue(c: Ctx)
	local y0 = plinth(c, 10, GOLD)
	local pivot = V3(0, y0, 0)
	local goldProps: Props = { Material = METAL, Reflectance = 0.5 }
	local darkGold = RGB(200, 140, 20)
	local glassColor = RGB(40, 55, 75)
	local parts: { BasePart } = {}
	local function add(p: BasePart): BasePart
		table.insert(parts, p)
		return p
	end

	add(box(c, "Body", V3(3.4, 0.8, 8.0), CF(0, y0 + 1.0, 0), GOLD, goldProps))
	add(wedge(c, "Nose", V3(3.2, 0.7, 2.6), CF(0, y0 + 0.95, -5.3), GOLD, goldProps))
	add(box(c, "Splitter", V3(3.6, 0.12, 0.8), CF(0, y0 + 0.55, -6.9), darkGold, goldProps))
	add(wedge(c, "Windshield", V3(2.8, 0.9, 3.0), CF(0, y0 + 1.85, -0.9), glassColor, { Transparency = 0.2, Reflectance = 0.2 }))
	add(box(c, "Roof", V3(2.8, 0.12, 1.0), CF(0, y0 + 2.26, 1.1), GOLD, goldProps))
	add(wedge(c, "RearDeck", V3(2.8, 0.9, 2.0), CF(0, y0 + 1.85, 2.6) * ANG(0, PI, 0), GOLD, goldProps))
	add(box(c, "Haunch", V3(3.5, 0.5, 2.4), CF(0, y0 + 1.15, 3.0), GOLD, goldProps))
	for _, sx in { -1, 1 } do
		add(box(c, "WingPost", V3(0.2, 0.9, 0.4), CF(sx * 1.1, y0 + 1.95, 3.7), darkGold))
		add(box(c, "WingPlate", V3(0.12, 0.5, 1.1), CF(sx * 1.85, y0 + 2.4, 3.8), darkGold))
		add(box(c, "Headlight", V3(0.9, 0.12, 0.4), CF(sx * 1.0, y0 + 1.3, -6.0), RGB(255, 250, 220), { Material = NEON }))
		for _, z in { -3.6, 3.0 } do
			add(cyl(c, "Wheel", "X", 0.9, 1.7, CF(sx * 1.85, y0 + 0.85, z), RGB(22, 22, 26)))
			add(cyl(c, "Rim", "X", 0.96, 1.0, CF(sx * 1.85, y0 + 0.85, z), GOLD, goldProps))
		end
	end
	add(box(c, "Wing", V3(3.6, 0.15, 1.1), CF(0, y0 + 2.4, 3.8), darkGold, goldProps))
	for i, p in parts do
		anim(c, p, "Spin", nil, pivot)
		-- sparkles on a few body parts
		if i == 1 or i == 5 or i == 7 then -- body, roof, haunch
			local sparkle = Instance.new("ParticleEmitter")
			sparkle.Name = "Sparkle"
			sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			sparkle.Color = ColorSequence.new(RGB(255, 250, 200), RGB(255, 200, 60))
			sparkle.LightEmission = 1
			sparkle.Lifetime = NumberRange.new(0.8, 1.4)
			sparkle.Rate = 8
			sparkle.Speed = NumberRange.new(0.5, 2)
			sparkle.SpreadAngle = Vector2.new(180, 180)
			sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
			sparkle.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
			sparkle.Parent = p
		end
	end
end

local function buildFireworks(c: Ctx)
	box(c, "Base", V3(5.2, 0.5, 5.2), CF(0, 0.25, 0), DARK)
	local colors = { RGB(220, 50, 50), RGB(50, 110, 220), GOLD }
	for i = 0, 4 do
		local a = i * 2 * PI / 5
		local x, z = math.sin(a) * 1.5, -math.cos(a) * 1.5
		local color = colors[i % #colors + 1]
		cyl(c, "Tube", "Y", 4.5, 1.0, CF(x, 2.75, z), color)
		cyl(c, "TubeBand", "Y", 0.4, 1.1, CF(x, 1.6, z), CHROME, { Material = METAL })
		ball(c, "TubeCap", 0.9, CF(x, 5.0, z), color)
	end
	box(c, "Brace", V3(3.4, 0.35, 0.35), CF(0, 2.2, 0), STEEL, { Material = METAL })
	local launch = box(c, "Launch", V3(0.3, 0.3, 0.3), CF(0, 5.6, 0), DARK, { Transparency = 1 })
	anim(c, launch, "Launch")
end

----------------------------------------------------------------------------------------------------
-- Entry point
----------------------------------------------------------------------------------------------------

local BUILDERS: { [string]: (Ctx) -> () } = {
	Bunting = buildBunting,
	OpenSign = buildOpenSign,
	TubeMan = buildTubeMan,
	BalloonArch = buildBalloonArch,
	ClassicStatue = buildClassicStatue,
	Searchlight = buildSearchlight,
	MascotBear = buildMascotBear,
	MechRobot = buildMechRobot,
	NeonDragon = buildNeonDragon,
	GoldStatue = buildGoldStatue,
	Fireworks = buildFireworks,
}

-- Builds the model completely before returning it (parent it afterwards so clients receive it whole).
function DecorModels.build(id: string, frame: CFrame): Model?
	local builder = BUILDERS[id]
	if not builder then
		return nil
	end
	local c = newCtx(id, frame)
	builder(c)
	CollectionService:AddTag(c.model, DecorModels.TAG)
	return c.model
end

return DecorModels
