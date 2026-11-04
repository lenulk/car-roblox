--!strict
-- The opening-scene circuit: a closed loop of evenly spaced points plus "track space" helpers.
-- Track space: s = distance along the centre line (wraps by Track.length), d = sideways offset
-- (positive = to the RIGHT of the driving direction). The loop turns right almost everywhere.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config: any = require(Shared:WaitForChild("Config"):WaitForChild("Prologue") :: ModuleScript)

local Track = {}

local UP = Vector3.new(0, 1, 0)

-- Control points (x, z) at scale 1. The first point sits on the main straight; s = 0 is the start line.
local CONTROL: { { number } } = {
	{ -140, 0 },
	{ 140, 0 },
	{ 420, 0 },
	{ 560, 10 },
	{ 650, 70 },
	{ 690, 170 },
	{ 690, 300 },
	{ 660, 410 },
	{ 560, 470 },
	{ 470, 540 },
	{ 480, 640 },
	{ 570, 710 },
	{ 600, 800 },
	{ 520, 880 },
	{ 380, 900 },
	{ 230, 880 },
	{ 120, 800 },
	{ -20, 760 },
	{ -170, 790 },
	{ -280, 760 },
	{ -360, 680 },
	{ -340, 580 },
	{ -420, 500 },
	{ -560, 470 },
	{ -660, 390 },
	{ -670, 270 },
	{ -640, 150 },
	{ -570, 60 },
	{ -500, 15 },
	{ -420, 0 },
}

local SAMPLES_PER_SEGMENT = 40

-- Centripetal Catmull-Rom through the control points, closed loop.
local function smoothLoop(points: { Vector3 }): { Vector3 }
	local out: { Vector3 } = {}
	local n = #points
	for i = 1, n do
		local p0 = points[(i - 2) % n + 1]
		local p1 = points[i]
		local p2 = points[i % n + 1]
		local p3 = points[(i + 1) % n + 1]
		local t0 = 0
		local t1 = t0 + (p1 - p0).Magnitude ^ 0.5
		local t2 = t1 + (p2 - p1).Magnitude ^ 0.5
		local t3 = t2 + (p3 - p2).Magnitude ^ 0.5
		for k = 0, SAMPLES_PER_SEGMENT - 1 do
			local t = t1 + (t2 - t1) * (k / SAMPLES_PER_SEGMENT)
			local a1 = p0 * ((t1 - t) / (t1 - t0)) + p1 * ((t - t0) / (t1 - t0))
			local a2 = p1 * ((t2 - t) / (t2 - t1)) + p2 * ((t - t1) / (t2 - t1))
			local a3 = p2 * ((t3 - t) / (t3 - t2)) + p3 * ((t - t2) / (t3 - t2))
			local b1 = a1 * ((t2 - t) / (t2 - t0)) + a2 * ((t - t0) / (t2 - t0))
			local b2 = a2 * ((t3 - t) / (t3 - t1)) + a3 * ((t - t1) / (t3 - t1))
			table.insert(out, b1 * ((t2 - t) / (t2 - t1)) + b2 * ((t - t1) / (t2 - t1)))
		end
	end
	return out
end

-- Re-samples a closed polyline to `count` evenly spaced points.
local function resample(dense: { Vector3 }, count: number, total: number): { Vector3 }
	local n = #dense
	local cumulative: { number } = { 0 }
	for i = 1, n do
		local nextPoint = dense[i % n + 1]
		cumulative[i + 1] = cumulative[i] + (nextPoint - dense[i]).Magnitude
	end
	local out: { Vector3 } = {}
	local step = total / count
	local seg = 1
	for k = 0, count - 1 do
		local target = k * step
		while seg < n and cumulative[seg + 1] < target do
			seg += 1
		end
		local a = dense[seg]
		local b = dense[seg % n + 1]
		local segLength = cumulative[seg + 1] - cumulative[seg]
		local f = if segLength > 1e-6 then (target - cumulative[seg]) / segLength else 0
		table.insert(out, a:Lerp(b, math.clamp(f, 0, 1)))
	end
	return out
end

local origin: Vector3 = Config.ARENA_ORIGIN
local scale: number = Config.TRACK_SCALE

local controlPoints: { Vector3 } = {}
for _, c in CONTROL do
	table.insert(controlPoints, Vector3.new(c[1] * scale, 0, c[2] * scale))
end

local dense = smoothLoop(controlPoints)
local denseLength = 0
for i = 1, #dense do
	denseLength += (dense[i % #dense + 1] - dense[i]).Magnitude
end

local count = math.max(8, math.floor(denseLength / Config.TRACK_STEP + 0.5))
local positions = resample(dense, count, denseLength)
for i = 1, count do
	positions[i] = positions[i] + origin
end

local stepLength = denseLength / count
local tangents: { Vector3 } = {}
local curvature: { number } = {} -- signed, positive = turning right
local curvatureAbs: { number } = {}

local function wrap(i: number): number
	return (i - 1) % count + 1
end

for i = 1, count do
	local d = positions[wrap(i + 1)] - positions[wrap(i - 1)]
	tangents[i] = Vector3.new(d.X, 0, d.Z).Unit
end
for i = 1, count do
	local a = tangents[wrap(i - 2)]
	local b = tangents[wrap(i + 2)]
	local turnLeft = math.asin(math.clamp(a:Cross(b).Y, -1, 1)) -- >0 = left turn
	curvature[i] = -turnLeft / (4 * stepLength)
	curvatureAbs[i] = math.abs(curvature[i])
end

Track.positions = positions
Track.count = count
Track.stepLength = stepLength
Track.length = denseLength
Track.halfWidth = Config.TRACK_WIDTH / 2
Track.origin = origin

function Track.wrapIndex(i: number): number
	return wrap(i)
end

local function indexAt(s: number): number
	return math.floor((s % denseLength) / stepLength + 0.5) % count + 1
end

-- Frame at (s, d): LookVector = driving direction, RightVector = +d, on the ground plane of the arena.
function Track.cframeAt(s: number, d: number): CFrame
	local f = (s % denseLength) / stepLength
	local i0 = math.floor(f)
	local t = f - i0
	local a = i0 % count + 1
	local b = (i0 + 1) % count + 1
	local pos = positions[a]:Lerp(positions[b], t)
	local look = tangents[a]:Lerp(tangents[b], t)
	if look.Magnitude < 1e-4 then
		look = tangents[a]
	end
	look = look.Unit
	local right = look:Cross(UP)
	return CFrame.fromMatrix(pos + right * d, right, UP, -look)
end

function Track.pointAt(s: number, d: number, height: number?): Vector3
	return Track.cframeAt(s, d).Position + Vector3.new(0, height or 0, 0)
end

-- Frame of the straight chord between point i and i + 1 (centred on the chord, offset d sideways).
function Track.segmentFrame(i: number, d: number): CFrame
	local a = positions[wrap(i)]
	local b = positions[wrap(i + 1)]
	local dir = Vector3.new(b.X - a.X, 0, b.Z - a.Z).Unit
	local right = dir:Cross(UP)
	return CFrame.fromMatrix((a + b) / 2 + right * d, right, UP, -dir)
end

function Track.chordLength(i: number): number
	return (positions[wrap(i + 1)] - positions[wrap(i)]).Magnitude
end

-- World point at track point i, offset d sideways.
function Track.pointAtIndex(i: number, d: number): Vector3
	local right = tangents[wrap(i)]:Cross(UP)
	return positions[wrap(i)] + right * d
end

-- Signed curvature (1 / radius) at point i; positive = turning right.
function Track.curvatureAtIndex(i: number): number
	return curvature[wrap(i)]
end

function Track.curvatureAt(s: number): number
	return curvature[indexAt(s)]
end

-- Largest |curvature| from s up to s + distance.
function Track.maxCurvatureAhead(s: number, distance: number): number
	local best = 0
	-- every point (not every other one): skipping points made the result jump as s crossed a point
	local steps = math.max(1, math.ceil(distance / stepLength))
	local base = indexAt(s)
	for k = 0, steps do
		local c = curvatureAbs[wrap(base + k)]
		if c > best then
			best = c
		end
	end
	return best
end

-- Which side (-1 / +1 in d) is the OUTSIDE of the bend at s. Straights count as -1 (left).
function Track.outerSign(s: number): number
	local c = Track.curvatureAt(s)
	if c > 1e-4 then
		return -1
	elseif c < -1e-4 then
		return 1
	end
	return -1
end

-- Average signed curvature over [s0, s1] (used to choose the outside of a stand section).
function Track.averageCurvature(s0: number, s1: number): number
	local total, n = 0, 0
	local s = s0
	while s <= s1 do
		total += Track.curvatureAt(s)
		n += 1
		s += stepLength * 2
	end
	return if n > 0 then total / n else 0
end

-- Distance from a world point to the nearest track point, ignoring points within `excludeDistance`
-- (along the track) of `ignoreS`. Used to keep stands and props clear of other parts of the circuit.
function Track.clearance(point: Vector3, ignoreS: number, excludeDistance: number): number
	local best = math.huge
	local flat = Vector3.new(point.X, 0, point.Z)
	for i = 1, count do
		local sPoint = (i - 1) * stepLength
		local along = math.abs(((sPoint - ignoreS + denseLength / 2) % denseLength) - denseLength / 2)
		if along > excludeDistance then
			local p = positions[i]
			local dist = (Vector3.new(p.X, 0, p.Z) - flat).Magnitude
			if dist < best then
				best = dist
			end
		end
	end
	return best
end

-- Starting grid: slot 1 is the front row, GRID_SLOTS is the back (the player).
function Track.gridSlot(slot: number): (number, number)
	local s = -(Config.GRID_FIRST + (slot - 1) * Config.GRID_SPACING)
	local d = if slot % 2 == 1 then -Config.GRID_LATERAL else Config.GRID_LATERAL
	return s, d
end

-- World-space box around the circuit (for the ground plate).
function Track.bounds(): (Vector3, Vector3)
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, p in positions do
		minX = math.min(minX, p.X)
		maxX = math.max(maxX, p.X)
		minZ = math.min(minZ, p.Z)
		maxZ = math.max(maxZ, p.Z)
	end
	return Vector3.new(minX, 0, minZ), Vector3.new(maxX, 0, maxZ)
end

-- Wraps a track distance difference into [-length/2, length/2).
function Track.wrapDelta(delta: number): number
	return (delta + denseLength / 2) % denseLength - denseLength / 2
end

return Track
