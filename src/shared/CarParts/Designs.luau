--!strict
-- The six car bodies. Every design is built from the same "shell" (body slab, hood/nose wedges, greenhouse made of
-- tilted glass slabs + thin wedge side windows, pillars) plus per-car front/rear ends and extras.
-- Z layout: nose = -Z. Sedan/Muscle/Sports/Super have a sloped rear window ("notch"/"fast"), Pickup/Truck a cab with a flat back ("wall").

local Kit = require(script.Parent.Kit)

local Designs = {}

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local RGB = Color3.fromRGB
local PI = math.pi

local DARK = Kit.DARK
local CHROME = Kit.CHROME
local METAL = Kit.METAL
local NEON = Kit.NEON
local TAIL = Kit.TAILLIGHT
local SEAT = Kit.SEAT
local BUMPER = Kit.BUMPER

-- kD: wheel diameter = kD * L, tw: tire width, axF/axR: axle z as a fraction of L
Designs.PARAMS = {
	Sedan = { kD = 0.21, tw = 1.0, axF = -0.31, axR = 0.31 },
	Pickup = { kD = 0.22, tw = 1.1, axF = -0.29, axR = 0.30 },
	Muscle = { kD = 0.205, tw = 1.1, axF = -0.30, axR = 0.28 },
	Truck = { kD = 0.22, tw = 1.3, axF = -0.28, axR = 0.285 },
	Sports = { kD = 0.195, tw = 1.1, axF = -0.31, axR = 0.31 },
	Super = { kD = 0.175, tw = 1.2, axF = -0.32, axR = 0.28 },
} :: { [string]: any }

------------------------------------------------------------------------------------------------
-- Per-car numbers
------------------------------------------------------------------------------------------------

local function specFor(id: string, ctx: any): any
	local L, H = ctx.L, ctx.H
	local hl = L / 2 - 0.55
	local sp: any = { zf = -hl, zr = hl, noseL = 0, bPillar = false, style = id }
	if id == "Pickup" then
		sp.rear = "wall"
		sp.gc, sp.slabTop, sp.beltTop, sp.roofY = 0.145 * H, 0.545 * H, 0.627 * H, H
		sp.zA, sp.zB, sp.zC = -0.203 * L, -0.123 * L, 0.033 * L
		sp.rearGlass = true
		sp.seatDz, sp.backDz, sp.wheelDz = 0.95, 0.7, 1.5
		sp.seams = { ctx.axF + ctx.D / 2 + 0.1, sp.zC - 0.25 }
	elseif id == "Truck" then
		sp.rear = "wall"
		sp.gc, sp.slabTop, sp.beltTop, sp.roofY = 0.154 * H, 0.554 * H, 0.615 * H, 0.908 * H
		sp.zA, sp.zB, sp.zC = -0.347 * L, -0.306 * L, -0.188 * L
		sp.rearGlass = false
		sp.seatDz, sp.backDz, sp.wheelDz = 0.9, 0.65, 0.6
	elseif id == "Muscle" then
		sp.rear = "fast"
		sp.gc, sp.slabTop, sp.beltTop, sp.roofY = 0.12 * H, 0.554 * H, 0.652 * H, H
		sp.zA, sp.zB, sp.zC, sp.zD = -0.12 * L, -0.03 * L, 0.10 * L, 0.36 * L
		sp.seams = { ctx.axF + ctx.D / 2 + 0.1, sp.zC + 0.5 }
	elseif id == "Sports" then
		sp.rear = "fast"
		sp.noseL = 0.19 * L
		sp.gc, sp.slabTop, sp.beltTop, sp.roofY = 0.113 * H, 0.575 * H, 0.65 * H, H
		sp.zA, sp.zB, sp.zC, sp.zD = -0.17 * L, -0.06 * L, 0.115 * L, 0.30 * L
		sp.seams = { ctx.axF + ctx.D / 2 + 0.1, sp.zC + 0.25 }
	elseif id == "Super" then
		sp.rear = "fast"
		sp.noseL = 0.18 * L
		sp.gc, sp.slabTop, sp.beltTop, sp.roofY = 0.108 * H, 0.581 * H, 0.649 * H, H
		sp.zA, sp.zB, sp.zC, sp.zD = -0.24 * L, -0.12 * L, 0.0, 0.14 * L
		sp.seams = { ctx.axF + ctx.D / 2 + 0.1, sp.zC + 1.0 }
	else -- Sedan
		sp.rear = "notch"
		sp.bPillar = true
		sp.gc, sp.slabTop, sp.beltTop, sp.roofY = 0.122 * H, 0.544 * H, 0.633 * H, H
		sp.zA, sp.zB, sp.zC, sp.zD = -0.207 * L, -0.093 * L, 0.157 * L, 0.286 * L
		sp.rearSeat = true
		sp.seams = { ctx.axF + ctx.D / 2 + 0.1, (sp.zB + sp.zC) / 2, ctx.axR - ctx.D / 2 - 0.1 }
	end
	if sp.zD == nil then
		sp.zD = sp.zC
	end
	-- interior layout: steering wheel must sit under the windshield, seats under the roof / rear glass
	local glassTopY = sp.roofY - 0.22
	local slope = (glassTopY - sp.beltTop) / (sp.zB - sp.zA)
	local wdz = sp.wheelDz or math.max(1.5, 0.95 / slope + 0.7)
	sp.wheelZ = sp.zA + wdz
	sp.seatZ = sp.wheelZ + (sp.seatDz or 1.25)
	sp.backZ = sp.seatZ + (sp.backDz or 0.85)
	return sp
end

------------------------------------------------------------------------------------------------
-- Small shared pieces
------------------------------------------------------------------------------------------------

local function addBeam(ctx: any, part: BasePart)
	if not ctx.beams then
		return
	end
	local s = Instance.new("SpotLight")
	s.Name = "HeadlightBeam"
	s.Face = Enum.NormalId.Front
	s.Range = 40
	s.Angle = 50
	s.Brightness = 2
	s.Color = ctx.headColor
	s.Shadows = false
	s.Parent = part
end

-- round headlight: chrome bezel (axis Z) + neon ball
local function headBall(ctx: any, T: any, x: number, y: number, z: number, dia: number)
	if ctx.detail then
		T.cyl("HeadBezel", 0.2, dia + 0.25, CF(x, y, z + 0.02) * ANG(0, PI / 2, 0), CHROME, METAL)
	end
	local b = T.ball("Headlight", dia, CF(x, y, z - 0.06), ctx.headColor, NEON)
	addBeam(ctx, b)
end

local function headRect(ctx: any, T: any, x: number, y: number, z: number, w: number, h: number)
	if ctx.detail then
		T.box("HeadFrame", V3(w + 0.2, h + 0.2, 0.2), CF(x, y, z + 0.02), DARK)
	end
	local p = T.box("Headlight", V3(w, h, 0.22), CF(x, y, z - 0.05), ctx.headColor, NEON)
	addBeam(ctx, p)
end

local function tail(T: any, x: number, y: number, z: number, w: number, h: number)
	T.box("Taillight", V3(w, h, 0.22), CF(x, y, z), TAIL, NEON)
end

local function plate(ctx: any, T: any, x: number, y: number, z: number, face: Enum.NormalId)
	local p = T.box("LicensePlate", V3(1.7, 0.75, 0.1), CF(x, y, z), Kit.WHITE)
	Kit.addPlateGui(p, face, ctx.plateText)
end

-- Bumper across the front (side = -1) or the rear (side = 1). kind: "paint" | "chrome" | "dark".
local function bumper(ctx: any, T: any, P: any, side: number, kind: string, y: number, h: number)
	local Wb: number = P.Wb
	local zb = if side < 0 then P.zf else P.zr
	local zc = zb + side * 0.25
	if kind == "paint" then
		T.pbox("Bumper", V3(Wb - 0.7, h, 0.65), CF(0, y, zc))
		for _, sx in { -1, 1 } do
			T.pcyl("BumperEnd", h, 0.65, CF(sx * (Wb / 2 - 0.35), y, zc) * ANG(0, 0, PI / 2))
		end
		if ctx.detail then
			T.box("Valance", V3(Wb - 1.4, 0.32, 0.55), CF(0, y - h / 2 - 0.02, zc), DARK)
			T.box("BumperTrim", V3(Wb - 0.9, 0.08, 0.67), CF(0, y + h * 0.18, zc), CHROME, METAL)
		end
	elseif kind == "chrome" then
		T.box("Bumper", V3(Wb + 0.1, h, 0.32), CF(0, y, zc + side * 0.04), CHROME, METAL)
		if ctx.detail then
			for _, sx in { -1, 1 } do
				T.cyl("BumperGuard", h + 0.3, 0.38, CF(sx * Wb * 0.3, y, zc + side * 0.2) * ANG(0, 0, PI / 2), CHROME, METAL)
			end
			T.box("Valance", V3(Wb - 1.0, 0.45, 0.5), CF(0, y - h / 2 - 0.2, zc), DARK)
		end
	else
		T.box("Bumper", V3(Wb + 0.2, h, 0.8), CF(0, y, zb + side * 0.3), BUMPER)
		T.box("BumperStep", V3(Wb - 0.2, 0.12, 0.84), CF(0, y + h / 2 + 0.04, zb + side * 0.3), CHROME, METAL)
		if ctx.detail then
			for _, sx in { -1, 1 } do
				T.box("BumperBolt", V3(0.3, 0.3, 0.1), CF(sx * (Wb / 2 - 0.5), y, zb + side * 0.72), CHROME, METAL)
			end
		end
	end
end

-- twin exhaust tips poking out of the rear; records the attachment positions in ctx.exhaust
local function exhaust(ctx: any, T: any, P: any, xs: number, y: number, dia: number)
	local zc = P.zr + 0.3
	ctx.exhaust = {}
	for _, sx in { -1, 1 } do
		T.cyl("ExhaustTip", 0.95, dia, CF(sx * xs, y, zc) * ANG(0, PI / 2, 0), CHROME, METAL)
		if ctx.detail then
			T.cyl("ExhaustInner", 0.97, dia * 0.62, CF(sx * xs, y, zc + 0.03) * ANG(0, PI / 2, 0), DARK)
		end
		table.insert(ctx.exhaust, V3(sx * xs, y, zc + 0.55))
	end
end

------------------------------------------------------------------------------------------------
-- The shell
------------------------------------------------------------------------------------------------

local function shell(ctx: any, T: any, sp: any): any
	local Wb: number = ctx.Wb
	local Wg = Wb - 1.0
	local Wr = Wb - 1.1
	local detail: boolean = ctx.detail
	local gc, slabTop, beltTop, roofY = sp.gc, sp.slabTop, sp.beltTop, sp.roofY
	local zf, zr = sp.zf, sp.zr
	local noseL: number = sp.noseL
	local zh0 = zf + noseL
	local zA, zB, zC, zD = sp.zA, sp.zB, sp.zC, sp.zD
	local wall = sp.rear == "wall"
	local fast = sp.rear == "fast"
	local zEnd = if wall then zC else zD
	local slabH = slabTop - gc
	local deckH = beltTop - slabTop
	local underRoof = roofY - 0.2
	local glassH = underRoof - beltTop
	local wsTop = underRoof - 0.02

	local function hoodY(z: number): number
		if noseL > 0 and z < zh0 then
			return gc + slabH * math.clamp((z - zf) / noseL, 0, 1)
		end
		if z < zA then
			return slabTop + deckH * math.clamp((z - zh0) / (zA - zh0), 0, 1)
		end
		return beltTop
	end

	-- body ---------------------------------------------------------------------------------------
	T.pbox("Body", V3(Wb, slabH, zr - zh0), CF(0, gc + slabH / 2, (zh0 + zr) / 2))
	T.box("Underbody", V3(Wb - 0.8, 0.3, zr - zf - 1.4), CF(0, gc - 0.05, (zf + zr) / 2), DARK)

	local carbon = ctx.hoodStyle == "Carbon"
	local function hoodPiece(size: Vector3, cf: CFrame)
		if carbon then
			T.wedge("HoodCarbon", size, cf, Kit.CARBON, Kit.CARBON_PROPS)
		else
			T.pwedge("BodyPanel", size, cf)
		end
	end
	if noseL > 0 then
		hoodPiece(V3(Wb, slabH, noseL), CF(0, gc + slabH / 2, zf + noseL / 2))
	end
	hoodPiece(V3(Wb - 0.2, deckH, zA - zh0), CF(0, slabTop + deckH / 2, (zh0 + zA) / 2))

	if not wall then
		T.pbox("BodyPanel", V3(Wb - 0.2, deckH, zr - zD), CF(0, slabTop + deckH / 2, (zD + zr) / 2))
	end

	-- cabin floor / rails / dash ---------------------------------------------------------------------
	if detail then
		for _, sx in { -1, 1 } do
			T.pbox("BodyPanel", V3(0.55, deckH, zEnd - zA), CF(sx * (Wb / 2 - 0.275), slabTop + deckH / 2, (zA + zEnd) / 2))
		end
		T.box("Dashboard", V3(Wg, deckH + 0.15, 1.1), CF(0, slabTop + (deckH + 0.15) / 2, zA + 0.55), DARK)
		if not wall then
			T.box("RearShelf", V3(Wg, deckH, 1.0), CF(0, slabTop + deckH / 2, zD - 0.5), DARK)
		end
	else
		T.pbox("BodyPanel", V3(Wb - 0.1, deckH, zEnd - zA), CF(0, slabTop + deckH / 2, (zA + zEnd) / 2))
		T.box("Seats", V3(Wg - 0.6, 0.85, 1.4), CF(0, beltTop + 0.4, sp.seatZ + 0.2), SEAT)
	end

	-- cab back wall (pickup / truck) --------------------------------------------------------------------
	if wall then
		if sp.rearGlass then
			local wallTop = beltTop + 0.5
			T.pbox("BodyPanel", V3(Wg + 0.6, wallTop - slabTop, 0.3), CF(0, (slabTop + wallTop) / 2, zC + 0.1))
			T.glass("RearWindow", V3(Wg - 0.5, underRoof - wallTop - 0.05, 0.1), CF(0, (wallTop + underRoof) / 2, zC + 0.08))
		else
			T.pbox("BodyPanel", V3(Wg + 0.6, roofY - slabTop, 0.3), CF(0, (slabTop + roofY) / 2, zC + 0.1))
		end
	end

	-- greenhouse ----------------------------------------------------------------------------------------
	T.gbeam("Windshield", V3(0, beltTop, zA), V3(0, wsTop, zB), Wg, 0.14)
	if not wall then
		T.gbeam("RearWindow", V3(0, wsTop, zC), V3(0, beltTop, zD), Wg, 0.14)
	end
	T.pbox("BodyPanel", V3(Wr, 0.2, zC - zB + 0.5), CF(0, roofY - 0.1, (zB + zC) / 2))

	for _, sx in { -1, 1 } do
		local xg = sx * (Wg / 2 - 0.03)
		local ymid = beltTop + glassH / 2
		T.glass("SideGlass", V3(0.1, glassH, zC - zB), CF(xg, ymid, (zB + zC) / 2))
		T.gwedge("SideGlass", V3(0.1, glassH, zB - zA), CF(xg, ymid, (zA + zB) / 2))
		if not wall then
			if fast then
				-- solid sail panel instead of a rear quarter window
				T.pwedge("BodyPanel", V3(0.7, glassH, zD - zC), CF(sx * (Wb / 2 - 0.35), ymid, (zC + zD) / 2) * ANG(0, PI, 0))
			else
				T.gwedge("SideGlass", V3(0.1, glassH, zD - zC), CF(xg, ymid, (zC + zD) / 2) * ANG(0, PI, 0))
			end
		end
		-- pillars
		T.pbeam(
			"BodyPanel",
			V3(sx * (Wg / 2 + 0.04), beltTop, zA),
			V3(sx * (Wg / 2 + 0.02), underRoof, zB),
			0.3,
			0.22
		)
		if wall then
			T.pbox("BodyPanel", V3(0.3, glassH, 0.3), CF(sx * (Wg / 2 + 0.02), beltTop + glassH / 2, zC))
		elseif not fast then
			T.pbeam(
				"BodyPanel",
				V3(sx * (Wg / 2 + 0.02), underRoof, zC),
				V3(sx * (Wg / 2 + 0.04), beltTop, zD),
				0.3,
				0.22
			)
		end
		if sp.bPillar then
			T.pbox("BodyPanel", V3(0.28, glassH, 0.3), CF(sx * (Wg / 2 + 0.02), beltTop + glassH / 2, (zB + zC) / 2))
		end
	end

	-- profile handed to the customization code -----------------------------------------------------------
	local P: any = {
		zf = zf,
		zr = zr,
		Wb = Wb,
		Wg = Wg,
		Wr = Wr,
		gc = gc,
		slabTop = slabTop,
		beltTop = beltTop,
		roofY = roofY,
		zA = zA,
		zB = zB,
		zC = zC,
		zD = zD,
		zh0 = zh0,
		noseL = noseL,
		wall = wall,
		fast = fast,
		hoodY = hoodY,
		underRoof = underRoof,
		glassH = glassH,
		doorY = (gc + 0.5 + slabTop) / 2,
	}
	function P.glassYAt(z: number): number
		if wall or z <= zC then
			return underRoof
		end
		return underRoof - (z - zC) / (zD - zC) * (underRoof - beltTop)
	end
	if wall then
		P.deckY, P.deckZ0, P.deckZ1, P.deckW = roofY, zB, zC + 0.2, Wr
	else
		P.deckY, P.deckZ0, P.deckZ1, P.deckW = beltTop, zD, zr, Wb
	end
	-- doors: seams and the z range between the first and last seam
	P.seams = sp.seams or {}
	if #P.seams >= 2 then
		P.doorZ0 = P.seams[1]
		P.doorZ1 = P.seams[#P.seams]
		P.doorZ = (P.seams[1] + P.seams[2]) / 2
	else
		P.doorZ0, P.doorZ1, P.doorZ = zA, zC, (zA + zC) / 2
	end
	-- top-surface center lines for racing stripes: {z0, y0, z1, y1}
	local segs: { { number } } = {}
	local zs = zf + 0.3
	if noseL > 0 then
		table.insert(segs, { zs, hoodY(zs), zh0, slabTop })
		table.insert(segs, { zh0, slabTop, zA, beltTop })
	else
		table.insert(segs, { zs, hoodY(zs), zA, beltTop })
	end
	table.insert(segs, { zB - 0.2, roofY, zC + 0.2, roofY })
	if not wall then
		table.insert(segs, { zD, beltTop, zr - 0.1, beltTop })
	end
	P.stripeSegs = segs
	return P
end

------------------------------------------------------------------------------------------------
-- Wheel arches (fender flares), mirrors, door details
------------------------------------------------------------------------------------------------

local function arches(ctx: any, T: any, P: any)
	local R: number = ctx.D / 2
	local Wb: number = P.Wb
	local n = if ctx.detail then 5 else 3
	local Ra = R + 0.2
	local width: number = ctx.TW + 0.3
	local step = if n == 5 then PI / 5 else PI / 3
	local chord = 2 * Ra * math.sin(step / 2) * 1.15
	for _, sx in { -1, 1 } do
		for _, cz in { ctx.axF, ctx.axR } do
			local cx = sx * ctx.wx
			for i = 0, n - 1 do
				local phi = (i - (n - 1) / 2) * step
				T.pbox(
					"BodyPanel",
					V3(width, 0.24, chord),
					CF(cx, R + Ra * math.cos(phi), cz + Ra * math.sin(phi)) * ANG(phi, 0, 0)
				)
			end
			if ctx.detail then
				T.cyl("WheelWell", 0.04, 2 * (R + 0.1), CF(sx * (Wb / 2 + 0.03), R + 0.1, cz), DARK)
			end
		end
	end
end

local function sideDetails(ctx: any, T: any, P: any, sp: any)
	local Wb: number = P.Wb
	local detail: boolean = ctx.detail
	local style: string = sp.style

	-- door seams + handles
	local seams: { number } = P.seams
	local seamH = P.beltTop - (P.gc + 0.45)
	local seamY = (P.gc + 0.45 + P.beltTop) / 2
	for _, sx in { -1, 1 } do
		for i, z in seams do
			T.box("DoorSeam", V3(0.05, seamH, 0.07), CF(sx * (Wb / 2 + 0.02), seamY, z), DARK)
			if detail and i >= 2 then
				T.box(
					"DoorHandle",
					V3(0.1, 0.14, 0.6),
					CF(sx * (Wb / 2 + 0.05), P.slabTop - 0.05, z - 0.65),
					CHROME,
					METAL
				)
			end
		end
		if detail and style ~= "Truck" then
			-- rocker trim between the wheels
			local z0 = ctx.axF + ctx.D / 2 + 0.2
			local z1 = ctx.axR - ctx.D / 2 - 0.2
			if z1 > z0 then
				T.box("SideTrim", V3(0.06, 0.09, z1 - z0), CF(sx * (Wb / 2 + 0.03), P.gc + 0.42, (z0 + z1) / 2), CHROME, METAL)
			end
		end
	end

	-- mirrors
	for _, sx in { -1, 1 } do
		if style == "Truck" then
			local zc = P.zA + 0.4
			for _, my in { 4.45, 5.55 } do
				T.beam(
					"MirrorArm",
					V3(sx * (P.Wg / 2 + 0.05), my, zc),
					V3(sx * (Wb / 2 + 0.85), my + 0.1, zc - 0.1),
					0.16,
					0.16,
					DARK
				)
			end
			T.box("MirrorBody", V3(0.3, 1.7, 0.9), CF(sx * (Wb / 2 + 1.0), 5.0, zc - 0.1), DARK)
			if detail then
				T.box("MirrorGlass", V3(0.05, 1.5, 0.7), CF(sx * (Wb / 2 + 1.0), 5.0, zc + 0.37), RGB(120, 130, 145), METAL)
			end
		elseif style == "Pickup" then
			local zc = P.zA + 0.55
			if detail then
				T.beam(
					"MirrorArm",
					V3(sx * (P.Wg / 2 + 0.05), P.beltTop + 0.35, zc),
					V3(sx * (Wb / 2 + 0.6), P.beltTop + 0.55, zc - 0.1),
					0.16,
					0.16,
					DARK
				)
			end
			T.box("MirrorBody", V3(0.3, 0.85, 0.65), CF(sx * (Wb / 2 + 0.75), P.beltTop + 0.6, zc - 0.1), DARK)
		else
			local zc = P.zA + 0.45
			if detail then
				T.beam(
					"MirrorArm",
					V3(sx * (P.Wg / 2 + 0.3), P.beltTop + 0.2, zc),
					V3(sx * (Wb / 2 + 0.3), P.beltTop + 0.3, zc),
					0.14,
					0.12,
					DARK
				)
			end
			T.pbox("BodyPanel", V3(0.36, 0.5, 0.7), CF(sx * (Wb / 2 + 0.5), P.beltTop + 0.45, zc))
			if detail then
				T.box("MirrorGlass", V3(0.38, 0.4, 0.05), CF(sx * (Wb / 2 + 0.5), P.beltTop + 0.45, zc + 0.37), RGB(120, 130, 145), METAL)
			end
		end
	end
end

------------------------------------------------------------------------------------------------
-- Interior (full detail only)
------------------------------------------------------------------------------------------------

local function interior(ctx: any, T: any, P: any, sp: any)
	local W: number = ctx.W
	local seatX = W * 0.22
	local slab: number = P.slabTop
	local belt: number = P.beltTop
	local wz: number = sp.wheelZ
	local tilt = 0.55

	-- steering wheel (ring = dark disc + lighter inner disc), column, hub
	local swCF = CF(-seatX, belt + 0.45, wz) * ANG(tilt, 0, 0) * ANG(0, PI / 2, 0)
	T.cyl("SteeringWheel", 0.12, 1.05, swCF, DARK)
	T.cyl("SteeringInner", 0.14, 0.7, swCF, RGB(70, 72, 80))
	T.cyl("SteeringHub", 0.18, 0.28, swCF, DARK)
	T.beam("SteeringColumn", V3(-seatX, belt + 0.4, wz - 0.1), V3(-seatX, belt - 0.15, wz - 0.95), 0.18, 0.18, DARK)

	local sz: number = sp.seatZ
	local bz: number = sp.backZ
	local glassAtBack = P.glassYAt(bz + 0.2)
	local backTop = math.min(slab + 1.0, glassAtBack - 0.12)
	local backH = backTop - slab
	for _, sx in { -1, 1 } do
		T.box("SeatBase", V3(1.7, 0.32, 1.4), CF(sx * seatX, slab + 0.16, sz), SEAT)
		T.box("SeatBack", V3(1.7, backH, 0.3), CF(sx * seatX, slab + backH / 2, bz), SEAT)
		if backTop + 0.4 < glassAtBack then
			T.box("Headrest", V3(0.8, 0.38, 0.26), CF(sx * seatX, backTop + 0.2, bz), SEAT)
		end
	end
	T.box("Console", V3(0.6, 0.42, 2.0), CF(0, slab + 0.21, sz), DARK)

	if sp.rearSeat then
		local rz = bz + 0.95
		local rBack = math.min(slab + 0.95, P.glassYAt(rz + 0.9) - 0.12)
		T.box("RearSeatBase", V3(P.Wg - 0.6, 0.32, 1.3), CF(0, slab + 0.16, rz), SEAT)
		T.box("RearSeatBack", V3(P.Wg - 0.6, rBack - slab, 0.3), CF(0, (slab + rBack) / 2, rz + 0.7), SEAT)
	end
end

------------------------------------------------------------------------------------------------
-- Cargo: pickup bed / truck box
------------------------------------------------------------------------------------------------

local function pickupBed(ctx: any, T: any, P: any)
	local Wb: number = P.Wb
	local bedStart = P.zC + 0.4
	local bedEnd = P.zr
	local bedLen = bedEnd - bedStart
	local bedMid = (bedStart + bedEnd) / 2
	local slab: number = P.slabTop
	T.box("BedLiner", V3(Wb - 1.0, 0.1, bedLen - 0.5), CF(0, slab + 0.05, bedMid), RGB(36, 38, 44))
	for _, sx in { -1, 1 } do
		T.pbox("BodyPanel", V3(0.4, 1.15, bedLen), CF(sx * (Wb / 2 - 0.2), slab + 0.575, bedMid))
		T.box("BedRail", V3(0.48, 0.09, bedLen + 0.04), CF(sx * (Wb / 2 - 0.2), slab + 1.2, bedMid), CHROME, METAL)
		if ctx.detail then
			-- running board
			T.box(
				"SideStep",
				V3(0.6, 0.18, P.doorZ1 - P.doorZ0 - 0.2),
				CF(sx * (Wb / 2 + 0.38), 1.15, (P.doorZ0 + P.doorZ1) / 2),
				DARK
			)
		end
	end
	T.pbox("BodyPanel", V3(Wb - 0.8, 1.6, 0.35), CF(0, slab + 0.8, bedStart + 0.17)) -- headboard
	T.pbox("BodyPanel", V3(Wb - 0.8, 1.15, 0.3), CF(0, slab + 0.575, bedEnd - 0.15)) -- tailgate
	T.box("BedRail", V3(Wb - 0.4, 0.09, 0.4), CF(0, slab + 1.2, bedEnd - 0.15), CHROME, METAL)
	if ctx.detail then
		T.box("GateHandle", V3(1.0, 0.14, 0.1), CF(0, slab + 0.95, bedEnd + 0.02), CHROME, METAL)
		T.box("GateEmboss", V3(Wb - 1.8, 0.5, 0.05), CF(0, slab + 0.5, bedEnd + 0.02), DARK)
	end
end

local function cargoBox(ctx: any, T: any, P: any, sp: any): number
	local Wb: number = P.Wb
	local H: number = ctx.H
	local z0 = P.zC + 0.1
	local z1 = P.zr + 0.05
	local y0 = 2.4
	local bw = Wb + 0.1
	T.pbox("BodyPanel", V3(bw, H - y0, z1 - z0), CF(0, (y0 + H) / 2, (z0 + z1) / 2))
	T.box("BoxSkirt", V3(bw + 0.08, 0.35, z1 - z0 + 0.08), CF(0, y0 + 0.17, (z0 + z1) / 2), DARK)
	-- roof cap band
	T.box("BoxRoofCap", V3(bw + 0.06, 0.12, z1 - z0 + 0.06), CF(0, H - 0.06, (z0 + z1) / 2), CHROME, METAL)
	local dy = (y0 + 0.35 + H - 0.2) / 2
	local dh = H - 0.2 - (y0 + 0.35)
	if ctx.detail then
		for _, sx in { -1, 1 } do
			for k = 0, 3 do
				local z = z0 + 1.2 + k * ((z1 - z0 - 2.4) / 3)
				T.box("BoxRib", V3(0.05, dh, 0.12), CF(sx * (bw / 2 + 0.02), dy, z), RGB(60, 62, 70))
			end
		end
		-- side door outline (right side) + handle
		local sdz = (z0 + z1) / 2 - 1.0
		local fx = bw / 2 + 0.03
		local dBot = y0 + 0.6
		local dTop = H - 0.9
		local dMid = (dBot + dTop) / 2
		T.box("SideDoorLine", V3(0.05, dTop - dBot, 0.08), CF(fx, dMid, sdz - 1.5), DARK)
		T.box("SideDoorLine", V3(0.05, dTop - dBot, 0.08), CF(fx, dMid, sdz + 1.5), DARK)
		T.box("SideDoorLine", V3(0.05, 0.08, 3.08), CF(fx, dTop, sdz), DARK)
		T.box("SideDoorLine", V3(0.05, 0.08, 3.08), CF(fx, dBot, sdz), DARK)
		T.box("SideDoorHandle", V3(0.1, 0.9, 0.14), CF(fx + 0.03, dMid, sdz + 1.2), CHROME, METAL)
		-- rear doors: center seam, hinges, lock bars, handles
		local rz = z1 + 0.03
		T.box("RearDoorSeam", V3(0.07, dh, 0.06), CF(0, dy, rz), DARK)
		for _, sx2 in { -1, 1 } do
			T.box("RearDoorEdge", V3(0.07, dh, 0.06), CF(sx2 * (bw / 2 - 0.3), dy, rz), DARK)
			for _, hy in { y0 + 0.7, dy, H - 1.0 } do
				T.box("Hinge", V3(0.28, 0.35, 0.1), CF(sx2 * (bw / 2 - 0.15), hy, rz + 0.03), RGB(70, 72, 80), METAL)
			end
			T.cyl("LockBar", dh * 0.8, 0.12, CF(sx2 * 0.55, dy, rz + 0.07) * ANG(0, 0, PI / 2), CHROME, METAL)
			T.box("RearDoorHandle", V3(0.2, 0.6, 0.12), CF(sx2 * 0.55, dy - 0.2, rz + 0.12), CHROME, METAL)
		end
		-- cab roof marker lights
		for _, mx in { -1.2, 0, 1.2 } do
			T.box("MarkerLight", V3(0.5, 0.2, 0.3), CF(mx, P.roofY + 0.1, P.zB - 0.1), RGB(255, 170, 40), NEON)
		end
	else
		T.box("RearDoorSeam", V3(0.07, dh, 0.06), CF(0, dy, z1 + 0.03), DARK)
	end
	return z1
end

------------------------------------------------------------------------------------------------
-- Front / rear ends and extras per car
------------------------------------------------------------------------------------------------

local function sedanEnds(ctx: any, T: any, P: any)
	local Wb: number = P.Wb
	local zf, zr = P.zf, P.zr
	bumper(ctx, T, P, -1, "paint", 0.9, 1.1)
	bumper(ctx, T, P, 1, "paint", 0.9, 1.1)
	local gy = P.slabTop - 0.75
	T.box("Grille", V3(Wb * 0.46, 0.62, 0.14), CF(0, gy, zf - 0.05), DARK)
	if ctx.detail then
		for _, o in { -0.3, 0, 0.3 } do
			T.box("GrilleBar", V3(Wb * 0.46 + 0.12, 0.06, 0.18), CF(0, gy + o, zf - 0.07), CHROME, METAL)
		end
		T.box("Emblem", V3(0.4, 0.4, 0.1), CF(0, gy, zf - 0.14), CHROME, METAL)
	end
	for _, sx in { -1, 1 } do
		headBall(ctx, T, sx * (Wb / 2 - 0.85), P.slabTop - 0.5, zf, 0.95)
		tail(T, sx * (Wb / 2 - 1.0), P.slabTop - 0.5, zr + 0.03, 1.4, 0.55)
	end
	T.box("TaillightBar", V3(Wb - 4.2, 0.14, 0.2), CF(0, P.slabTop - 0.5, zr + 0.02), RGB(170, 25, 35), NEON)
	plate(ctx, T, 0, 0.9, zf - 0.62, Enum.NormalId.Front)
	plate(ctx, T, 0, 0.9, zr + 0.62, Enum.NormalId.Back)
	exhaust(ctx, T, P, Wb * 0.3, 0.5, 0.5)
	if ctx.detail then
		T.box("Antenna", V3(0.06, 1.3, 0.06), CF(Wb / 2 - 0.9, P.roofY + 0.5, P.zC - 0.2), DARK)
		T.box("TrunkBadge", V3(0.9, 0.2, 0.08), CF(0, P.beltTop - 0.1, zr + 0.04), CHROME, METAL)
	end
end

local function muscleEnds(ctx: any, T: any, P: any)
	local Wb: number = P.Wb
	local zf, zr = P.zf, P.zr
	bumper(ctx, T, P, -1, "chrome", 0.95, 0.55)
	bumper(ctx, T, P, 1, "chrome", 0.95, 0.55)
	local gy = P.slabTop - 0.7
	T.box("Grille", V3(Wb * 0.36, 0.9, 0.14), CF(0, gy, zf - 0.05), DARK)
	if ctx.detail then
		for _, o in { -0.25, 0, 0.25 } do
			T.box("GrilleBar", V3(Wb * 0.36, 0.05, 0.17), CF(0, gy + o, zf - 0.07), CHROME, METAL)
		end
		T.box("Emblem", V3(0.5, 0.35, 0.1), CF(0, gy, zf - 0.14), RGB(210, 40, 40), METAL)
	end
	for _, sx in { -1, 1 } do
		headBall(ctx, T, sx * (Wb / 2 - 0.6), gy, zf, 0.82)
		headBall(ctx, T, sx * (Wb / 2 - 1.55), gy, zf, 0.82)
		for i = 0, 2 do
			tail(T, sx * (Wb / 2 - 0.55 - i * 0.62), P.slabTop - 0.35, zr + 0.03, 0.5, 0.75)
		end
	end
	T.box("TaillightPanel", V3(Wb - 0.6, 0.95, 0.12), CF(0, P.slabTop - 0.35, zr + 0.0), DARK)
	plate(ctx, T, 0, 0.95, zr + 0.5, Enum.NormalId.Back)
	plate(ctx, T, 0, 0.95, zf - 0.5, Enum.NormalId.Front)
	exhaust(ctx, T, P, Wb * 0.3, 0.6, 0.65)

	-- hood bulge + nostrils
	local hz0, hz1 = P.zh0 + 1.6, P.zA - 0.5
	local hy = P.hoodY((hz0 + hz1) / 2)
	local bulgeName = if ctx.hoodStyle == "Carbon" then "HoodCarbon" else "BodyPanel"
	if ctx.hoodStyle == "Carbon" then
		T.wedge(bulgeName, V3(1.9, 0.4, hz1 - hz0), CF(0, hy + 0.1, (hz0 + hz1) / 2), Kit.CARBON, Kit.CARBON_PROPS)
	else
		T.pwedge(bulgeName, V3(1.9, 0.4, hz1 - hz0), CF(0, hy + 0.1, (hz0 + hz1) / 2))
	end
	if ctx.detail then
		for _, sx in { -1, 1 } do
			T.box("Nostril", V3(0.6, 0.12, 0.35), CF(sx * 0.5, P.hoodY(hz0) + 0.17, hz0 + 0.1), DARK)
		end
		-- classic quarter-panel stripe accent + hood pins
		for _, sx in { -1, 1 } do
			T.cyl("HoodPin", 0.1, 0.22, CF(sx * 1.4, P.hoodY(P.zA - 0.6) + 0.07, P.zA - 0.6) * ANG(0, 0, PI / 2), CHROME, METAL)
		end
	end
end

local function sportsEnds(ctx: any, T: any, P: any)
	local Wb: number = P.Wb
	local zf, zr = P.zf, P.zr
	-- nose lip + intake
	T.pbox("BodyPanel", V3(Wb - 0.3, 0.5, 0.7), CF(0, 0.62, zf - 0.1))
	T.box("Intake", V3(Wb * 0.55, 0.28, 0.1), CF(0, 0.58, zf - 0.46), DARK)
	if ctx.detail then
		for sx = -1, 1, 2 do
			T.box("AirCurtain", V3(0.7, 0.3, 0.1), CF(sx * (Wb / 2 - 0.9), 0.58, zf - 0.46), DARK)
		end
		T.box("Splitter", V3(Wb, 0.1, 0.5), CF(0, 0.3, zf - 0.35), Kit.CARBON, Kit.CARBON_PROPS)
	end
	plate(ctx, T, 0, 0.62, zf - 0.52, Enum.NormalId.Front)
	-- LED headlights lying on the sloped nose
	for _, sx in { -1, 1 } do
		local x = sx * (Wb / 2 - 1.25)
		local za, zb = zf + 1.35, zf + 2.05
		local hb = T.beam(
			"Headlight",
			V3(x, P.hoodY(zb) + 0.05, zb),
			V3(x, P.hoodY(za) + 0.05, za),
			1.5,
			0.12,
			ctx.headColor,
			NEON
		)
		addBeam(ctx, hb)
		if ctx.detail then
			T.beam("HeadHousing", V3(x, P.hoodY(zb + 0.12) + 0.02, zb + 0.12), V3(x, P.hoodY(za - 0.12) + 0.02, za - 0.12), 1.75, 0.1, DARK)
			T.beam(
				"DRL",
				V3(x - sx * 0.4, P.hoodY(zb) + 0.06, zb),
				V3(x - sx * 0.4, P.hoodY(za - 0.25) + 0.06, za - 0.25),
				0.16,
				0.12,
				RGB(255, 255, 255),
				NEON
			)
		end
	end
	-- rear
	bumper(ctx, T, P, 1, "paint", 0.75, 0.7)
	T.box("TaillightBar", V3(Wb - 1.0, 0.16, 0.2), CF(0, P.slabTop + 0.05, zr + 0.02), TAIL, NEON)
	for _, sx in { -1, 1 } do
		tail(T, sx * (Wb / 2 - 0.95), P.slabTop - 0.3, zr + 0.03, 1.2, 0.5)
	end
	if ctx.detail then
		T.box("Diffuser", V3(Wb - 1.8, 0.45, 0.5), CF(0, 0.45, zr + 0.5), DARK)
		for i = -2, 2 do
			T.box("DiffuserFin", V3(0.08, 0.45, 0.55), CF(i * 0.8, 0.45, zr + 0.55), Kit.CARBON)
		end
	end
	plate(ctx, T, 0, 1.45, zr + 0.04, Enum.NormalId.Back)
	exhaust(ctx, T, P, Wb * 0.24, 0.8, 0.55)
	-- side intakes behind the doors
	local zi0 = P.seams[#P.seams] + 0.12
	local zi1 = ctx.axR - ctx.D / 2 - 0.15
	if zi1 - zi0 > 0.4 then
		for _, sx in { -1, 1 } do
			T.wedge("SideIntake", V3(0.12, 0.95, zi1 - zi0), CF(sx * (Wb / 2 + 0.04), P.doorY + 0.15, (zi0 + zi1) / 2), DARK)
			if ctx.detail then
				for k = 0, 2 do
					T.pbox("BodyPanel", V3(0.16, 0.05, zi1 - zi0 - 0.1 - k * 0.1), CF(sx * (Wb / 2 + 0.07), P.doorY - 0.1 + k * 0.25, (zi0 + zi1) / 2 + 0.05 + k * 0.05))
				end
			end
		end
	end
end

local function superEnds(ctx: any, T: any, P: any)
	local Wb: number = P.Wb
	local zf, zr = P.zf, P.zr
	T.pbox("BodyPanel", V3(Wb - 0.3, 0.5, 0.7), CF(0, 0.55, zf - 0.1))
	T.box("Intake", V3(Wb * 0.62, 0.26, 0.1), CF(0, 0.5, zf - 0.46), DARK)
	T.box("Splitter", V3(Wb + 0.1, 0.1, 0.8), CF(0, 0.26, zf - 0.55), Kit.CARBON, Kit.CARBON_PROPS)
	plate(ctx, T, 0, 0.58, zf - 0.52, Enum.NormalId.Front)
	-- sharp LED eyes: angled bar + under-strip, plus a front LED strip on the splitter
	for _, sx in { -1, 1 } do
		local za, zb = zf + 1.6, zf + 2.5
		local hb = T.beam(
			"Headlight",
			V3(sx * (Wb / 2 - 0.5), P.hoodY(zb) + 0.05, zb),
			V3(sx * (Wb / 2 - 2.2), P.hoodY(za) + 0.05, za),
			0.5,
			0.12,
			ctx.headColor,
			NEON
		)
		addBeam(ctx, hb)
		if ctx.detail then
			T.beam(
				"HeadHousing",
				V3(sx * (Wb / 2 - 0.4), P.hoodY(zb + 0.1) + 0.02, zb + 0.1),
				V3(sx * (Wb / 2 - 2.35), P.hoodY(za - 0.1) + 0.02, za - 0.1),
				0.9,
				0.1,
				DARK
			)
			T.beam(
				"DRL",
				V3(sx * (Wb / 2 - 0.9), P.hoodY(zb + 0.4) + 0.05, zb + 0.4),
				V3(sx * (Wb / 2 - 2.0), P.hoodY(za + 0.35) + 0.05, za + 0.35),
				0.14,
				0.12,
				RGB(255, 255, 255),
				NEON
			)
			T.box("LEDStrip", V3(Wb - 1.0, 0.06, 0.1), CF(0, 0.5, zf - 0.53), ctx.headColor, NEON)
		end
	end
	-- rear: full-width LED bar, quad light blocks, diffuser
	bumper(ctx, T, P, 1, "paint", 0.7, 0.6)
	T.box("TaillightBar", V3(Wb - 0.8, 0.14, 0.2), CF(0, P.slabTop + 0.1, zr + 0.02), TAIL, NEON)
	for _, sx in { -1, 1 } do
		tail(T, sx * (Wb / 2 - 0.9), P.slabTop - 0.35, zr + 0.03, 1.0, 0.45)
		if ctx.detail then
			tail(T, sx * (Wb / 2 - 2.0), P.slabTop - 0.35, zr + 0.03, 0.5, 0.45)
		end
	end
	if ctx.detail then
		T.box("Diffuser", V3(Wb - 1.8, 0.5, 0.5), CF(0, 0.5, zr + 0.5), DARK)
		for i = -2, 2 do
			T.box("DiffuserFin", V3(0.08, 0.5, 0.55), CF(i * 0.85, 0.5, zr + 0.55), Kit.CARBON)
		end
	end
	plate(ctx, T, 0, 1.4, zr + 0.04, Enum.NormalId.Back)
	exhaust(ctx, T, P, Wb * 0.17, 0.85, 0.6)

	-- big side intakes behind the doors
	local zi0 = P.seams[#P.seams] + 0.15
	local zi1 = ctx.axR - ctx.D / 2 - 0.2
	if zi1 - zi0 > 0.4 then
		for _, sx in { -1, 1 } do
			T.wedge("SideIntake", V3(0.14, 1.2, zi1 - zi0), CF(sx * (Wb / 2 + 0.05), P.doorY + 0.3, (zi0 + zi1) / 2), DARK)
			if ctx.detail then
				for k = 0, 2 do
					T.pbox("BodyPanel", V3(0.18, 0.05, zi1 - zi0 - 0.15 - k * 0.15), CF(sx * (Wb / 2 + 0.08), P.doorY + k * 0.3, (zi0 + zi1) / 2 + 0.1 + k * 0.07))
				end
			end
		end
	end
	-- rear engine deck: vents
	local vz0 = P.zD + 0.9
	local vz1 = zr - 0.7
	T.box("EngineVentFrame", V3(Wb * 0.6, 0.06, vz1 - vz0), CF(0, P.beltTop + 0.03, (vz0 + vz1) / 2), DARK)
	local nv = if ctx.detail then 6 else 3
	for i = 0, nv - 1 do
		local z = vz0 + 0.3 + i * ((vz1 - vz0 - 0.6) / math.max(nv - 1, 1))
		T.pbox("BodyPanel", V3(Wb * 0.6, 0.1, 0.16), CF(0, P.beltTop + 0.1, z))
	end
	if ctx.detail then
		-- buttresses
		for _, sx in { -1, 1 } do
			T.pbox("BodyPanel", V3(0.3, 0.7, vz1 - vz0), CF(sx * Wb * 0.34, P.beltTop + 0.32, (vz0 + vz1) / 2))
		end
	end
end

local function pickupEnds(ctx: any, T: any, P: any)
	local Wb: number = P.Wb
	local zf, zr = P.zf, P.zr
	bumper(ctx, T, P, -1, "dark", 1.15, 1.0)
	bumper(ctx, T, P, 1, "dark", 1.15, 0.9)
	local gy = 2.35
	T.box("GrilleFrame", V3(Wb * 0.6, 1.2, 0.12), CF(0, gy, zf - 0.03), CHROME, METAL)
	T.box("Grille", V3(Wb * 0.6 - 0.3, 0.95, 0.14), CF(0, gy, zf - 0.07), DARK)
	if ctx.detail then
		for k = -2, 2 do
			T.box("GrilleBar", V3(0.09, 0.95, 0.17), CF(k * 0.6, gy, zf - 0.09), CHROME, METAL)
		end
	end
	for _, sx in { -1, 1 } do
		headRect(ctx, T, sx * (Wb / 2 - 0.95), 2.45, zf, 1.3, 0.75)
		if ctx.detail then
			T.box("Indicator", V3(0.8, 0.2, 0.2), CF(sx * (Wb / 2 - 0.95), 1.95, zf - 0.04), RGB(255, 170, 40), NEON)
		end
		tail(T, sx * (Wb / 2 - 0.35), P.slabTop + 0.55, zr + 0.02, 0.5, 1.0)
	end
	plate(ctx, T, 0, 1.15, zf - 0.78, Enum.NormalId.Front)
	plate(ctx, T, 0, 1.1, zr + 0.78, Enum.NormalId.Back)
	exhaust(ctx, T, P, Wb * 0.3, 0.65, 0.5)
	pickupBed(ctx, T, P)
end

local function truckEnds(ctx: any, T: any, P: any, sp: any)
	local Wb: number = P.Wb
	local zf = P.zf
	bumper(ctx, T, P, -1, "dark", 1.3, 1.2)
	local gy = 2.85
	T.box("GrilleFrame", V3(Wb * 0.58, 1.55, 0.12), CF(0, gy, zf - 0.03), CHROME, METAL)
	T.box("Grille", V3(Wb * 0.58 - 0.3, 1.3, 0.14), CF(0, gy, zf - 0.07), DARK)
	if ctx.detail then
		for k = -3, 3 do
			T.box("GrilleBar", V3(0.09, 1.3, 0.17), CF(k * 0.5, gy, zf - 0.09), CHROME, METAL)
		end
		T.box("Emblem", V3(0.7, 0.45, 0.1), CF(0, gy, zf - 0.16), CHROME, METAL)
	end
	for _, sx in { -1, 1 } do
		headRect(ctx, T, sx * (Wb / 2 - 0.85), gy, zf, 1.1, 0.9)
		if ctx.detail then
			T.box("Indicator", V3(0.7, 0.22, 0.2), CF(sx * (Wb / 2 - 0.85), gy - 0.75, zf - 0.04), RGB(255, 170, 40), NEON)
		end
	end
	plate(ctx, T, 0, 1.3, zf - 0.82, Enum.NormalId.Front)

	local zEndBox = cargoBox(ctx, T, P, sp)
	-- rear ICC bumper, lights, plate
	T.box("Bumper", V3(Wb - 0.2, 0.7, 0.6), CF(0, 1.1, zEndBox + 0.3), BUMPER)
	T.box("BumperStep", V3(Wb - 0.4, 0.12, 0.64), CF(0, 1.5, zEndBox + 0.3), CHROME, METAL)
	for _, sx in { -1, 1 } do
		tail(T, sx * (Wb / 2 - 0.65), 3.6, zEndBox + 0.04, 0.45, 1.5)
		T.box("MudFlap", V3(0.1, 0.9, 1.1), CF(sx * ctx.wx, 0.75, ctx.axR + ctx.D / 2 + 0.3), DARK)
	end
	plate(ctx, T, 0, 1.1, zEndBox + 0.66, Enum.NormalId.Back)
	P.zr = zEndBox
	-- exhaust: under the rear of the box
	ctx.exhaust = {}
	for _, sx in { -1, 1 } do
		T.cyl("ExhaustTip", 0.95, 0.55, CF(sx * Wb * 0.3, 0.5, zEndBox + 0.2) * ANG(0, PI / 2, 0), CHROME, METAL)
		table.insert(ctx.exhaust, V3(sx * Wb * 0.3, 0.5, zEndBox + 0.7))
	end
	-- vertical exhaust stacks behind the cab
	if ctx.detail then
		for _, sx in { -1, 1 } do
			T.cyl("Stack", 3.6, 0.5, CF(sx * (Wb / 2 + 0.4), 2.6, P.zC + 0.9) * ANG(0, 0, PI / 2), CHROME, METAL)
		end
	end
end

------------------------------------------------------------------------------------------------
-- Entry point
------------------------------------------------------------------------------------------------

-- Builds the whole body (everything except the wheels and customization). Returns the profile table.
function Designs.build(ctx: any): any
	local T = Kit.tools(ctx, ctx.model)
	local id: string = ctx.id
	local sp = specFor(id, ctx)
	local P = shell(ctx, T, sp)
	P.sp = sp
	arches(ctx, T, P)
	sideDetails(ctx, T, P, sp)
	if ctx.detail then
		interior(ctx, T, P, sp)
	end
	if id == "Pickup" then
		pickupEnds(ctx, T, P)
	elseif id == "Truck" then
		truckEnds(ctx, T, P, sp)
	elseif id == "Muscle" then
		muscleEnds(ctx, T, P)
	elseif id == "Sports" then
		sportsEnds(ctx, T, P)
	elseif id == "Super" then
		superEnds(ctx, T, P)
	else
		sedanEnds(ctx, T, P)
	end
	P.driverPos = V3(-ctx.W * 0.22, P.slabTop + 0.75, sp.seatZ)
	return P
end

return Designs
