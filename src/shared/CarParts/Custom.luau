--!strict
-- Customization visuals bolted onto a finished body: spoilers, body kits, hood options, decals, underglow.
-- `P` is the profile table returned by Designs.build (see shell()).

local Kit = require(script.Parent.Kit)

local Custom = {}

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local RGB = Color3.fromRGB
local PI = math.pi

local DARK = Kit.DARK
local CHROME = Kit.CHROME
local METAL = Kit.METAL
local NEON = Kit.NEON
local CARBON = Kit.CARBON
local CARBON_PROPS = Kit.CARBON_PROPS

------------------------------------------------------------------------------------------------
-- Spoilers
------------------------------------------------------------------------------------------------

local function spoiler(ctx: any, T: any, P: any)
	local kind: string = ctx.custom.spoiler
	if kind == "None" then
		return
	end
	local wall: boolean = P.wall
	local y0: number = P.deckY
	local zEnd: number = P.deckZ1
	local w: number = P.deckW
	local k = if wall then 0.7 else 1

	if kind == "Lip" then
		local lw = w - 1.0
		T.pbox("BodyPanel", V3(lw, 0.22, 0.55), CF(0, y0 + 0.11, zEnd - 0.5))
		T.pwedge("BodyPanel", V3(lw, 0.22, 0.5), CF(0, y0 + 0.11, zEnd - 1.025))
		for _, sx in { -1, 1 } do
			T.pbox("BodyPanel", V3(0.1, 0.34, 0.55), CF(sx * lw / 2, y0 + 0.17, zEnd - 0.5))
		end
	elseif kind == "Ducktail" then
		local dw = w - 0.8
		T.pwedge("BodyPanel", V3(dw, 0.6, 2.2), CF(0, y0 + 0.3, zEnd - 1.1))
		T.pbox("BodyPanel", V3(dw, 0.1, 0.4), CF(0, y0 + 0.64, zEnd - 0.2))
		for _, sx in { -1, 1 } do
			T.pbox("BodyPanel", V3(0.1, 0.45, 0.5), CF(sx * dw / 2, y0 + 0.72, zEnd - 0.25))
		end
	elseif kind == "Wing" then
		local ww = w - 0.4
		local post = 1.15 * k + (if wall then 0.5 else 0)
		local zc = zEnd - 1.3
		for _, sx in { -1, 1 } do
			T.box("WingPost", V3(0.3, post, 0.75), CF(sx * (ww / 2 - 0.9), y0 + post / 2, zc), DARK)
			T.box("WingBase", V3(0.8, 0.1, 1.1), CF(sx * (ww / 2 - 0.9), y0 + 0.05, zc), DARK)
			T.pbox("BodyPanel", V3(0.12, 0.6, 1.75), CF(sx * ww / 2, y0 + post + 0.12, zc))
		end
		T.pbox("BodyPanel", V3(ww, 0.16, 1.6), CF(0, y0 + post + 0.08, zc) * ANG(-0.1, 0, 0))
	elseif kind == "GTWing" then
		local ww = w - 0.2
		local hh = 2.2 * k
		local zc = zEnd - 1.0
		for _, sx in { -1, 1 } do
			local x = sx * (ww / 2 - 1.6)
			-- swan-neck: slanted pylon up from the deck, then a short neck into the top of the wing
			T.beam("WingPylon", V3(x, y0, zEnd - 2.2), V3(x, y0 + hh - 0.1, zEnd - 1.15), 0.3, 0.5, DARK)
			T.beam("WingNeck", V3(x, y0 + hh - 0.1, zEnd - 1.15), V3(x, y0 + hh + 0.12, zEnd - 0.6), 0.3, 0.22, DARK)
			T.box("WingBase", V3(0.9, 0.1, 1.4), CF(x, y0 + 0.05, zEnd - 2.2), DARK)
			-- end plates
			T.pbox("BodyPanel", V3(0.14, 1.2 * k + 0.2, 2.5), CF(sx * ww / 2, y0 + hh + 0.15, zc))
		end
		T.pbox("BodyPanel", V3(ww, 0.18, 2.0), CF(0, y0 + hh, zc) * ANG(-0.14, 0, 0)) -- main element
		T.pbox("BodyPanel", V3(ww, 0.12, 0.95), CF(0, y0 + hh + 0.38, zc + 0.75) * ANG(-0.42, 0, 0)) -- upper flap
		T.box("WingLip", V3(ww, 0.06, 0.16), CF(0, y0 + hh + 0.2, zc - 0.98), CARBON)
	end
end

------------------------------------------------------------------------------------------------
-- Body kits
------------------------------------------------------------------------------------------------

local function kit(ctx: any, T: any, P: any)
	local kind: string = ctx.custom.kit
	if kind ~= "Street" and kind ~= "Race" then
		return
	end
	local race = kind == "Race"
	local Wb: number = P.Wb
	local R: number = ctx.D / 2
	local zf, zr = P.zf, P.zr
	local darkProps = CARBON_PROPS

	-- front splitter (+ end plates and canards for Race)
	local ext = if race then 0.95 else 0.45
	local z0 = zf - 0.1
	local z1 = zf - 0.55 - ext
	T.box("Splitter", V3(Wb + 0.2, 0.12, z0 - z1), CF(0, 0.28, (z0 + z1) / 2), CARBON, darkProps)
	if race then
		for _, sx in { -1, 1 } do
			T.box("SplitterPlate", V3(0.1, 0.5, z0 - z1), CF(sx * (Wb / 2 + 0.1), 0.45, (z0 + z1) / 2), CARBON, darkProps)
			T.pbox("BodyPanel", V3(0.9, 0.1, 0.7), CF(sx * (Wb / 2 - 0.1), 1.05, zf - 0.45) * ANG(0, 0, sx * 0.42))
		end
	end

	-- side skirts between the wheels
	local sz0 = ctx.axF + R + 0.1
	local sz1 = ctx.axR - R - 0.1
	if sz1 - sz0 > 0.5 then
		local sw = if race then 0.5 else 0.35
		local sh = if race then 0.6 else 0.45
		for _, sx in { -1, 1 } do
			T.pbox("BodyPanel", V3(sw, sh, sz1 - sz0), CF(sx * (Wb / 2 + sw / 2 - 0.05), P.gc + 0.1, (sz0 + sz1) / 2))
			T.box("SkirtLip", V3(sw + 0.04, 0.1, sz1 - sz0), CF(sx * (Wb / 2 + sw / 2 - 0.05), P.gc - 0.22, (sz0 + sz1) / 2), CARBON, darkProps)
		end
	end

	-- rear diffuser with fins
	local dw = Wb - 1.4
	local dd = if race then 1.1 else 0.8
	T.box("Diffuser", V3(dw, 0.35, dd), CF(0, 0.38, zr + 0.2 + dd / 2), CARBON, darkProps)
	local nf = if race then 6 else 4
	for i = 0, nf - 1 do
		local fx = (i - (nf - 1) / 2) * (dw - 0.3) / (nf - 1)
		local fh = if race then 0.55 else 0.4
		T.box("DiffuserFin", V3(0.08, fh, dd + 0.1), CF(fx, 0.38 + fh / 2 - 0.1, zr + 0.2 + dd / 2), DARK)
	end
	if race then
		T.box("DiffuserLip", V3(dw + 0.2, 0.08, 0.2), CF(0, 0.2, zr + 0.25 + dd), CARBON, darkProps)
		for _, sx in { -1, 1 } do
			T.box("DiffuserPlate", V3(0.08, 0.7, dd + 0.15), CF(sx * (dw / 2 + 0.05), 0.5, zr + 0.2 + dd / 2), DARK)
		end
	end

	-- wide fender flares over every wheel (Race)
	if race then
		local Ra = R + 0.33
		local width: number = ctx.TW + 1.0
		local step = PI / 3.2
		local chord = 2 * Ra * math.sin(step / 2) * 1.15
		for _, sx in { -1, 1 } do
			for _, cz in { ctx.axF, ctx.axR } do
				local cx = sx * (ctx.wx + 0.2)
				for i = 0, 2 do
					local phi = (i - 1) * step
					T.pbox(
						"BodyPanel",
						V3(width, 0.26, chord),
						CF(cx, R + Ra * math.cos(phi), cz + Ra * math.sin(phi)) * ANG(phi, 0, 0)
					)
				end
				-- rivet strip along the outer lip
				T.box(
					"FlareStrip",
					V3(0.08, 0.1, Ra * 1.6),
					CF(cx + sx * (width / 2 - 0.02), R + Ra * 0.96, cz),
					DARK
				)
			end
		end
	end
end

------------------------------------------------------------------------------------------------
-- Hood options
------------------------------------------------------------------------------------------------

local function hood(ctx: any, T: any, P: any)
	local kind: string = ctx.custom.hood
	if kind == "Stock" then
		return
	end
	local zA, zh0 = P.zA, P.zh0
	local hoodY = P.hoodY

	-- frame sitting on the hood surface at z, tilted to the hood slope over `len`
	local function frameAt(z: number, len: number): CFrame
		local theta = math.atan2(hoodY(z + len / 2) - hoodY(z - len / 2), len)
		return CF(0, hoodY(z), z) * ANG(-theta, 0, 0)
	end

	if kind == "Scoop" then
		local len = math.clamp((zA - zh0) * 0.6 + 0.3, 1.2, 2.4)
		local zc = zA - len / 2 - 0.15
		local F = frameAt(zc, len)
		local h = 0.65
		T.pwedge("BodyPanel", V3(1.8, h, len), F * CF(0, h / 2 - 0.05, 0) * ANG(0, PI, 0))
		T.box("ScoopIntake", V3(1.45, h * 0.7, 0.1), F * CF(0, h * 0.4, -len / 2 - 0.02), DARK)
		T.box("ScoopFrame", V3(1.9, 0.08, 0.14), F * CF(0, h - 0.03, -len / 2 + 0.02), CHROME, METAL)
		for _, sx in { -1, 1 } do
			T.box("ScoopFrame", V3(0.08, h * 0.8, 0.14), F * CF(sx * 0.85, h * 0.4, -len / 2 + 0.02), CHROME, METAL)
		end
	elseif kind == "Carbon" then
		-- subtle vent: dark plate with louvre slats
		local zc: number
		if ctx.id == "Muscle" then
			zc = zh0 + 0.9
		else
			-- short hoods (Super): zh0 + 0.6 can exceed zA - 0.4, so centre the vent instead of clamping
			local lo, hi = zh0 + 0.6, zA - 0.4
			zc = if lo <= hi then math.clamp(zA - 1.3, lo, hi) else (zh0 + zA) / 2
		end
		local F = frameAt(zc, 1.0)
		T.box("HoodVent", V3(1.6, 0.06, 1.0), F * CF(0, 0.04, 0), DARK)
		for i = -1, 1 do
			T.box("HoodSlat", V3(1.55, 0.08, 0.08), F * CF(0, 0.08, i * 0.3), RGB(78, 80, 90), METAL)
		end
	end
end

------------------------------------------------------------------------------------------------
-- Decals
------------------------------------------------------------------------------------------------

-- Where side decals go: x of the surface, y range and z range
local function sideSurface(ctx: any, P: any): { [string]: number }
	if ctx.id == "Truck" then
		return {
			x = (P.Wb + 0.1) / 2 + 0.03,
			y0 = 2.7,
			y1 = ctx.H - 1.2,
			z0 = P.zC + 0.7,
			z1 = P.zr - 2.4,
			rz = P.zC + 2.3,
			ry = ctx.H - 2.6,
		}
	end
	return {
		x = P.Wb / 2 + 0.03,
		y0 = P.gc + 0.35,
		y1 = P.slabTop - 0.15,
		z0 = ctx.axF + ctx.D / 2 + 0.3,
		z1 = ctx.axR - ctx.D / 2 - 0.3,
		rz = P.doorZ,
		ry = P.doorY + 0.1,
	}
end

local function decal(ctx: any, T: any, P: any)
	local kind: string = ctx.custom.decal
	if kind == "None" then
		return
	end
	local Wb: number = P.Wb
	local S = sideSurface(ctx, P)

	if kind == "Stripes" then
		local lum = ctx.paintColor.R * 0.3 + ctx.paintColor.G * 0.59 + ctx.paintColor.B * 0.11
		local sc = if lum > 0.55 then RGB(30, 30, 34) else RGB(245, 245, 248)
		for _, seg in P.stripeSegs do
			for _, sx in { -1, 1 } do
				local x = sx * 0.5
				T.beam(
					"Stripe",
					V3(x, seg[2] + 0.04, seg[1]),
					V3(x, seg[4] + 0.04, seg[3]),
					0.55,
					0.05,
					sc,
					{ Material = Enum.Material.SmoothPlastic }
				)
			end
		end
	elseif kind == "Number" then
		for _, sx in { -1, 1 } do
			local x = sx * S.x
			local cf = CF(x + sx * 0.02, S.ry, S.rz)
			T.cyl("RoundelRim", 0.05, 1.6, cf, RGB(20, 20, 24))
			T.cyl("Roundel", 0.07, 1.42, CF(x + sx * 0.03, S.ry, S.rz), Kit.WHITE)
			local np = T.box(
				"NumberPlate",
				V3(0.02, 1.2, 1.2),
				CF(x + sx * 0.105, S.ry, S.rz),
				Kit.WHITE,
				{ Transparency = 1 }
			)
			Kit.addNumberGui(np, if sx > 0 then Enum.NormalId.Right else Enum.NormalId.Left, ctx.numberText)
		end
	elseif kind == "Checker" then
		local sq = 0.45
		local cols = math.floor((S.z1 - S.z0) / sq)
		if cols >= 2 then
			local cy = (S.y0 + S.y1) / 2 - 0.05
			local zStart = (S.z0 + S.z1) / 2 - cols * sq / 2
			for _, sx in { -1, 1 } do
				local x = sx * S.x
				T.box("CheckBand", V3(0.04, 2 * sq, cols * sq), CF(x, cy, zStart + cols * sq / 2), Kit.WHITE)
				for c = 0, cols - 1 do
					for r = 0, 1 do
						if (c + r) % 2 == 0 then
							T.box(
								"CheckSquare",
								V3(0.05, sq, sq),
								CF(x + sx * 0.03, cy + (r - 0.5) * sq, zStart + (c + 0.5) * sq),
								RGB(18, 18, 22)
							)
						end
					end
				end
			end
		end
	elseif kind == "Flames" then
		local avail = math.min(S.z1 - S.z0, 3.8)
		if avail > 1 then
			local hs = S.y1 - S.y0
			local lens = { 1.0, 0.76, 0.52 }
			for _, sx in { -1, 1 } do
				local x = sx * S.x
				for i = 1, 3 do
					local len = avail * lens[i]
					local h = hs * 0.36
					local yc = S.y0 + hs * (0.2 + 0.3 * (i - 1)) + h / 2 * 0.2
					T.wedge(
						"FlameDecal",
						V3(0.04, h, len),
						CF(x, yc, S.z0 + len / 2) * ANG(0, PI, 0),
						RGB(255, 112, 22)
					)
					T.wedge(
						"FlameDecal",
						V3(0.04, h * 0.55, len * 0.68),
						CF(x + sx * 0.025, yc - h * 0.05, S.z0 + len * 0.68 / 2) * ANG(0, PI, 0),
						RGB(255, 214, 48)
					)
				end
			end
		end
	end
end

------------------------------------------------------------------------------------------------
-- Underglow
------------------------------------------------------------------------------------------------

local function underglow(ctx: any, T: any, P: any)
	local neon: Color3? = ctx.neonColor
	if neon == nil then
		return
	end
	local color = neon :: Color3
	local Wb: number = P.Wb
	local len = P.zr - P.zf - 2.0
	local main = T.box("Underglow", V3(Wb - 0.6, 0.1, len), CF(0, math.max(P.gc - 0.28, 0.12), (P.zf + P.zr) / 2), color, NEON)
	local light = Instance.new("PointLight")
	light.Name = "UnderglowLight"
	light.Color = color
	light.Range = 14
	light.Brightness = 2
	light.Parent = main
	local sy = math.max(P.gc - 0.12, 0.2)
	local z0 = ctx.axF + ctx.D / 2 + 0.2
	local z1 = ctx.axR - ctx.D / 2 - 0.2
	for _, sx in { -1, 1 } do
		T.box("UnderglowStrip", V3(0.14, 0.12, z1 - z0), CF(sx * (Wb / 2 - 0.12), sy, (z0 + z1) / 2), color, NEON)
	end
	T.box("UnderglowStrip", V3(Wb - 1.0, 0.12, 0.14), CF(0, sy, P.zf + 0.5), color, NEON)
	T.box("UnderglowStrip", V3(Wb - 1.0, 0.12, 0.14), CF(0, sy, P.zr - 0.5), color, NEON)
end

------------------------------------------------------------------------------------------------

function Custom.apply(ctx: any, P: any)
	local T = Kit.tools(ctx, ctx.model)
	spoiler(ctx, T, P)
	kit(ctx, T, P)
	hood(ctx, T, P)
	decal(ctx, T, P)
	underglow(ctx, T, P)
end

return Custom
