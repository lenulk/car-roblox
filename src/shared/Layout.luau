--!strict
-- Single source of truth for world geometry. Every builder and service must use these numbers.
-- Plot-local space: origin = plot center on the ground, -Z points toward the ring road (front),
-- +Z points to the back wall, +X is the plot's right side when facing the ring from inside.

local Layout = {}

Layout.GROUND_Y = 0
Layout.PLOT_COUNT = 4

Layout.RING_CENTER = Vector3.new(0, 0, 0)
Layout.RING_INNER_RADIUS = 80
Layout.RING_OUTER_RADIUS = 110
Layout.RING_LANE_RADIUS = 95

Layout.PLOT_DISTANCE = 230
Layout.PLOT_WIDTH = 140 -- local X: -70 .. 70
Layout.PLOT_DEPTH = 120 -- local Z: -60 .. 60

Layout.BUILDING = {
	minX = -70,
	maxX = 70,
	frontZ = -22,
	backZ = 60,
	height = 24,
}

Layout.ENTRY_LANE_X = -6
Layout.EXIT_LANE_X = 6
Layout.CONNECTOR_RING_Z = -120 -- where the connector road meets the ring's outer edge
Layout.LOT_LANE_Z = -55 -- lane in the parking lot that runs in front of the queue row
Layout.BAY_LANE_Z = -28 -- lane between the queue row and the building front

Layout.CAR_LENGTH = 14
Layout.CAR_WIDTH = 7

-- A car CFrame whose LookVector points to local +Z (nose into the building).
local function faceIn(x: number, z: number): CFrame
	return CFrame.new(x, 0, z) * CFrame.Angles(0, math.pi, 0)
end
-- An object CFrame whose LookVector points to local -Z (front faces the ring / the customers).
local function faceOut(x: number, z: number): CFrame
	return CFrame.new(x, 0, z)
end
Layout.faceIn = faceIn
Layout.faceOut = faceOut

-- Queue spots 1-3 exist from the start; 4-6 come with the "Parking" unlock.
Layout.QUEUE = {
	faceIn(-36, -42),
	faceIn(-48, -42),
	faceIn(-60, -42),
	faceIn(36, -42),
	faceIn(48, -42),
	faceIn(60, -42),
}

-- car: where the customer car parks. machine: station equipment. employee: where the mechanic stands.
-- button: unlock pad for that bay.
Layout.BAYS = {
	{ car = faceIn(-48, -2), machine = faceOut(-38, -2), employee = faceOut(-58, 4), button = Vector3.new(-48, 0, -15) },
	{ car = faceIn(-16, -2), machine = faceOut(-6, -2), employee = faceOut(-26, 4), button = Vector3.new(-16, 0, -15) },
	{ car = faceIn(16, -2), machine = faceOut(26, -2), employee = faceOut(6, 4), button = Vector3.new(16, 0, -15) },
	{ car = faceIn(48, -2), machine = faceOut(58, -2), employee = faceOut(38, 4), button = Vector3.new(48, 0, -15) },
}

-- Parts shelves along the back-left of the building, facing the customers (-Z).
Layout.SHELVES = {
	{ shelf = faceOut(-62, 46), button = Vector3.new(-62, 0, 38) },
	{ shelf = faceOut(-50, 46), button = Vector3.new(-50, 0, 38) },
	{ shelf = faceOut(-38, 46), button = Vector3.new(-38, 0, 38) },
	{ shelf = faceOut(-26, 46), button = Vector3.new(-26, 0, 38) },
}

Layout.CASHIER = { counter = faceOut(0, 40), employee = faceOut(0, 45), button = Vector3.new(0, 0, 30) }
Layout.SAFE = faceOut(20, 40)
Layout.HIRE_BOARD = faceOut(55, 58)
Layout.PARKING_BUTTON = Vector3.new(48, 0, -52)
Layout.PLAYER_SPAWN = faceOut(0, 20)
Layout.GATE = faceOut(0, -60)

-- Plot i sits at angle (i-1)*90deg around the ring. Its -Z (LookVector) faces the ring center.
function Layout.plotAngle(plotIndex: number): number
	return (plotIndex - 1) * math.pi / 2
end

function Layout.ringPoint(angle: number, radius: number?): Vector3
	local r = radius or Layout.RING_LANE_RADIUS
	return Vector3.new(math.sin(angle) * r, Layout.GROUND_Y, math.cos(angle) * r)
end

function Layout.plotCFrame(plotIndex: number): CFrame
	local angle = Layout.plotAngle(plotIndex)
	local pos = Vector3.new(math.sin(angle), 0, math.cos(angle)) * Layout.PLOT_DISTANCE
	return CFrame.lookAt(pos, Vector3.new(0, 0, 0))
end

function Layout.toWorld(plotIndex: number, localCFrame: CFrame): CFrame
	return Layout.plotCFrame(plotIndex) * localCFrame
end

function Layout.pointToWorld(plotIndex: number, localPoint: Vector3): Vector3
	return Layout.plotCFrame(plotIndex) * localPoint
end

-- Points along the ring lane from angle a0 to a1 (cars always drive toward increasing angle).
function Layout.ringArc(a0: number, a1: number, stepRadians: number?): { Vector3 }
	local step = stepRadians or math.rad(8)
	while a1 < a0 do
		a1 += 2 * math.pi
	end
	local points = {}
	local a = a0
	while a < a1 do
		table.insert(points, Layout.ringPoint(a))
		a += step
	end
	table.insert(points, Layout.ringPoint(a1))
	return points
end

-- World waypoints: ring (upstream of the plot) -> connector -> lot lane -> in front of the queue spot.
-- The caller finishes by moving the car onto Layout.QUEUE[queueIndex].
function Layout.arrivalPath(plotIndex: number, queueIndex: number): { Vector3 }
	local a = Layout.plotAngle(plotIndex)
	local points = Layout.ringArc(a - math.rad(70), a - math.rad(4))
	local q = Layout.QUEUE[queueIndex].Position
	for _, p in
		{
			Vector3.new(Layout.ENTRY_LANE_X, 0, Layout.CONNECTOR_RING_Z),
			Vector3.new(Layout.ENTRY_LANE_X, 0, Layout.LOT_LANE_Z),
			Vector3.new(q.X, 0, Layout.LOT_LANE_Z),
		}
	do
		table.insert(points, Layout.pointToWorld(plotIndex, p))
	end
	return points
end

-- World waypoints: queue spot -> bay lane -> in front of the bay. Caller finishes on BAYS[bayIndex].car.
function Layout.queueToBayPath(plotIndex: number, queueIndex: number, bayIndex: number): { Vector3 }
	local q = Layout.QUEUE[queueIndex].Position
	local b = Layout.BAYS[bayIndex].car.Position
	return {
		Layout.pointToWorld(plotIndex, Vector3.new(q.X, 0, Layout.BAY_LANE_Z)),
		Layout.pointToWorld(plotIndex, Vector3.new(b.X, 0, Layout.BAY_LANE_Z)),
	}
end

-- World waypoints: bay -> exit lane -> connector -> ring (downstream). Caller despawns at the end.
function Layout.departurePath(plotIndex: number, bayIndex: number): { Vector3 }
	local b = Layout.BAYS[bayIndex].car.Position
	local points = {}
	for _, p in
		{
			Vector3.new(b.X, 0, Layout.BAY_LANE_Z),
			Vector3.new(Layout.EXIT_LANE_X, 0, Layout.BAY_LANE_Z),
			Vector3.new(Layout.EXIT_LANE_X, 0, Layout.CONNECTOR_RING_Z),
		}
	do
		table.insert(points, Layout.pointToWorld(plotIndex, p))
	end
	local a = Layout.plotAngle(plotIndex)
	for _, p in Layout.ringArc(a + math.rad(4), a + math.rad(70)) do
		table.insert(points, p)
	end
	return points
end

return Layout
