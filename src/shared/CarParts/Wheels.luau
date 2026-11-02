--!strict
-- Wheel models: Wheel_FL / FR / RL / RR. PrimaryPart "Hub" is the tire (Cylinder along car X, size (tireWidth, D, D)).
-- Everything else is decoration welded to the Hub (CarBuilder welds; Hub -> Root via "WheelWeld").

local Kit = require(script.Parent.Kit)

local Wheels = {}

type Props = Kit.Props

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local RGB = Color3.fromRGB
local TAU = math.pi * 2

local GOLD = RGB(255, 196, 56)
local ROTOR = RGB(128, 132, 140)
local SIDEWALL = RGB(46, 46, 52)
local GUNMETAL = RGB(34, 36, 42)
local METAL: Props = { Material = Enum.Material.Metal, Reflectance = 0.4 }
local GOLD_PROPS: Props = { Material = Enum.Material.Metal, Reflectance = 0.5 }

-- sx = -1 for the left side (outer face looks toward -X), +1 for the right side. (cx, cz) = wheel center on the ground plane.
function Wheels.build(ctx: any, name: string, sx: number, cx: number, cz: number): Model
	local wm = Instance.new("Model")
	wm.Name = name
	local T = Kit.tools(ctx, wm)

	local D: number = ctx.D
	local TW: number = ctx.TW
	local R = D / 2
	local cy = R
	local style: string = ctx.wheelStyle
	local rimColor: Color3 = ctx.rimColor
	local detail: boolean = ctx.detail
	local xo = cx + sx * TW / 2 -- x of the outer tire face

	local hub = T.cyl("Hub", TW, D, CF(cx, cy, cz), Kit.TIRE)
	wm.PrimaryPart = hub

	-- flat disc on the outer face, spanning offsets o0..o1 (studs) outward from the tire face
	local function disc(nm: string, dia: number, o0: number, o1: number, color: Color3, props: Props?): BasePart
		return T.cyl(nm, o1 - o0, dia, CF(xo + sx * (o0 + o1) / 2, cy, cz), color, props)
	end
	-- radial arm from radius r0 to r1 at angle a (0 = up, positive toward +Z), width w, spanning offsets o0..o1
	local function arm(
		nm: string,
		a: number,
		r0: number,
		r1: number,
		w: number,
		o0: number,
		o1: number,
		color: Color3,
		props: Props?
	): BasePart
		return T.box(
			nm,
			V3(o1 - o0, r1 - r0, w),
			CF(xo + sx * (o0 + o1) / 2, cy, cz) * ANG(a, 0, 0) * CF(0, (r0 + r1) / 2, 0),
			color,
			props
		)
	end

	-- layer base: DeepDish pushes every layer outward behind its deep chrome lip
	local B = if style == "DeepDish" then 0.32 else 0
	local lipDia = if style == "DeepDish" then 0.78 * D elseif style == "OffRoad" then 0.76 * D else 0.72 * D
	local barrelDia = 0.58 * D
	local rs = 0.29 * D -- spoke reach (barrel radius)

	if detail then
		disc("Sidewall", D * 0.9, -0.01, 0.02, SIDEWALL)
	end

	-- rim lip (the ring you see around the spokes)
	if style == "NeonRim" then
		local lip = disc("RimLip", lipDia, -0.02, 0.08, rimColor, Kit.NEON)
		local glow = Instance.new("PointLight")
		glow.Name = "RimGlow"
		glow.Color = rimColor
		glow.Range = 8
		glow.Brightness = 1.2
		glow.Parent = lip
	elseif style == "DeepDish" then
		disc("RimLip", lipDia, -0.05, B + 0.07, Kit.CHROME, { Material = Enum.Material.Metal, Reflectance = 0.6 })
	else
		disc("RimLip", lipDia, -0.02, 0.07, rimColor, METAL)
	end
	-- dark barrel / dish behind the spokes
	disc("RimBarrel", barrelDia, B, B + 0.09, Kit.DARK)

	-- brake rotor + caliper behind the spokes
	if detail then
		disc("Rotor", D * 0.46, B + 0.02, B + 0.1, ROTOR, METAL)
		T.box(
			"Caliper",
			V3(0.1, D * 0.13, D * 0.17),
			CF(xo + sx * (B + 0.11), cy, cz) * ANG(-0.75, 0, 0) * CF(0, D * 0.2, 0),
			ctx.caliperColor,
			{ Material = Enum.Material.SmoothPlastic, Reflectance = 0.1 }
		)
	end

	local s0, s1 = B + 0.14, B + 0.26 -- spoke layer
	local capColor = rimColor

	if style == "Sport" then
		-- 10 thin spokes = 5 bars through the center
		for i = 0, 4 do
			arm("Spoke", i * math.pi / 5, -rs, rs, 0.11, s0, s1, rimColor, METAL)
		end
	elseif style == "Turbo" then
		-- turbine: 8 pitched fan blades
		for i = 0, 7 do
			local a = i * TAU / 8
			T.box(
				"Blade",
				V3(0.09, D * 0.23, 0.32),
				CF(xo + sx * (B + 0.2), cy, cz) * ANG(a, 0, 0) * CF(0, D * 0.17, 0) * ANG(0, -sx * 0.75, 0),
				rimColor,
				METAL
			)
		end
		disc("TurbineCore", D * 0.16, s0, s1 + 0.04, GUNMETAL, METAL)
		capColor = GUNMETAL
	elseif style == "Mesh" then
		-- cross-hatch: two crossing sets of chords clipped to the barrel circle
		local rin = rs * 0.97
		for k = 0, 1 do
			local beta = math.pi / 4 + k * math.pi / 2
			for _, f in { -0.62, -0.21, 0.21, 0.62 } do
				local d = f * rin
				local chord = 2 * math.sqrt(rin * rin - d * d)
				T.box(
					"Mesh",
					V3(0.1 + k * 0.03, 0.07, chord),
					CF(xo + sx * (B + 0.2 + k * 0.015), cy, cz) * ANG(beta, 0, 0) * CF(0, d, 0),
					rimColor,
					METAL
				)
			end
		end
		disc("MeshRing", D * 0.62, B + 0.1, B + 0.15, rimColor, METAL)
		disc("MeshHole", D * 0.46, B + 0.11, B + 0.16, Kit.DARK)
	elseif style == "OffRoad" then
		-- chunky: 3 fat bars, bolted beadlock ring, tread blocks around the tire
		for i = 0, 2 do
			arm("Spoke", i * math.pi / 3, -rs, rs, 0.28, s0, s1 + 0.04, rimColor, METAL)
		end
		for i = 0, 5 do
			local a = i * TAU / 6 + 0.26
			T.cyl(
				"Bolt",
				0.12,
				0.2,
				CF(xo + sx * 0.12, cy, cz) * ANG(a, 0, 0) * CF(0, 0.33 * D, 0),
				Kit.CHROME,
				METAL
			)
		end
		for i = 0, 9 do
			local a = i * TAU / 10
			T.box(
				"Tread",
				V3(TW * 0.94, 0.13, 0.5),
				CF(cx, cy, cz) * ANG(a, 0, 0) * CF(0, R - 0.02, 0),
				RGB(14, 14, 16)
			)
		end
	elseif style == "DeepDish" then
		-- 5 slim spokes inside the deep dish + small center
		for i = 0, 4 do
			arm("Spoke", i * TAU / 5, 0.03 * D, rs * 1.02, 0.13, s0, s1 + 0.04, rimColor, METAL)
		end
	elseif style == "Spinner" then
		-- stepped five-point star (wide base, narrow tip) with a gold spinner center
		for i = 0, 4 do
			local a = i * TAU / 5
			arm("StarArm", a, 0.02 * D, 0.15 * D, 0.3, s0, s1, rimColor, METAL)
			arm("StarTip", a, 0.15 * D, rs, 0.14, s0, s1, rimColor, METAL)
		end
		capColor = GOLD
	elseif style == "NeonRim" then
		for i = 0, 5 do
			arm("Spoke", i * TAU / 6, 0.02 * D, rs, 0.12, s0, s1, GUNMETAL, METAL)
		end
		capColor = rimColor
	else
		-- Classic: 5 thick spokes
		for i = 0, 4 do
			arm("Spoke", i * TAU / 5, 0.03 * D, rs, 0.26, s0, s1, rimColor, METAL)
		end
	end

	-- center cap
	if style == "Spinner" then
		disc("SpinnerRing", D * 0.3, s0, s1 + 0.05, GOLD, GOLD_PROPS)
		disc("SpinnerCap", D * 0.15, s1 + 0.05, s1 + 0.2, Kit.CHROME, METAL)
	elseif style == "NeonRim" then
		disc("Cap", D * 0.2, s0, s1 + 0.1, capColor, Kit.NEON)
	elseif style == "DeepDish" then
		disc("Cap", D * 0.15, s0, s1 + 0.14, capColor, METAL)
	elseif style ~= "Turbo" then
		disc("Cap", D * 0.2, s0, s1 + 0.1, capColor, METAL)
	end

	return wm
end

return Wheels
