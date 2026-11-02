--!strict
-- TrafficService: moves cars along polylines (customer cars) and keeps decorative ambient traffic on the ring.
--
-- One shared Heartbeat connection updates every active drive. Position follows the polyline exactly;
-- only the heading is smoothed. Cars are pivoted at ground level (Layout.GROUND_Y) and are moved with
-- Model:PivotTo (CarBuilder welds every part to the anchored Root).

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Layout: any = require(Shared:WaitForChild("Layout") :: ModuleScript)
local CarBuilder: any = require(Shared:WaitForChild("CarBuilder") :: ModuleScript)
local ConfigFolder = Shared:WaitForChild("Config")
local Game: any = require(ConfigFolder:WaitForChild("Game") :: ModuleScript)
local CarTypes: any = require(ConfigFolder:WaitForChild("CarTypes") :: ModuleScript)

local TURN_RATE = 4 -- radians per second while driving
local FINAL_TURN_TIME = 0.35 -- seconds for the in-place rotation onto finalCFrame
local EPSILON = 1e-3
local MAX_DT = 0.1 -- clamp hitches so cars never teleport
local AMBIENT_COUNT = 6
local AMBIENT_SPEED_FACTOR = 0.8

type DriveRecord = {
	model: Model,
	points: { Vector3 },
	index: number,
	speed: number,
	pos: Vector3,
	yaw: number,
	finalYaw: number?,
	stage: string, -- "path" | "turn"
	turnT: number,
	turnFrom: number,
	turnDelta: number,
	thread: thread,
	done: boolean,
}

local TrafficService = {}

local active: { DriveRecord } = {}
local byModel: { [Model]: DriveRecord } = {}
local connection: RBXScriptConnection? = nil

-- Heading helpers. CFrame.Angles(0, yaw, 0).LookVector == (-sin yaw, 0, -cos yaw).
local function yawOfDirection(dir: Vector3): number
	return math.atan2(-dir.X, -dir.Z)
end

local function angleDiff(from: number, to: number): number
	return ((to - from + math.pi) % (2 * math.pi)) - math.pi
end

local function approachAngle(current: number, target: number, maxStep: number): number
	local diff = angleDiff(current, target)
	if math.abs(diff) <= maxStep then
		return target
	end
	return current + math.sign(diff) * maxStep
end

local function flat(p: Vector3): Vector3
	return Vector3.new(p.X, Layout.GROUND_Y, p.Z)
end

local function finish(rec: DriveRecord, ok: boolean)
	if rec.done then
		return
	end
	rec.done = true
	local idx = table.find(active, rec)
	if idx then
		table.remove(active, idx)
	end
	if byModel[rec.model] == rec then
		byModel[rec.model] = nil
	end
	-- Deferred so the waiting thread resumes outside the Heartbeat update loop.
	task.defer(rec.thread, ok)
	if #active == 0 and connection then
		connection:Disconnect()
		connection = nil
	end
end

-- Advances one drive. Returns true when the drive is complete.
local function step(rec: DriveRecord, dt: number): boolean
	if rec.stage == "path" then
		local remaining = rec.speed * dt
		local desiredYaw = rec.yaw
		local points = rec.points
		while rec.index <= #points do
			local target = points[rec.index]
			local delta = target - rec.pos
			local dist = delta.Magnitude
			if dist < EPSILON then
				rec.pos = target
				rec.index += 1
			else
				desiredYaw = yawOfDirection(delta)
				if remaining <= 0 then
					break
				end
				if dist <= remaining then
					rec.pos = target
					remaining -= dist
					rec.index += 1
				else
					rec.pos += delta.Unit * remaining
					remaining = 0
					break
				end
			end
		end
		rec.yaw = approachAngle(rec.yaw, desiredYaw, TURN_RATE * dt)
		rec.model:PivotTo(CFrame.new(rec.pos) * CFrame.Angles(0, rec.yaw, 0))

		if rec.index > #points then
			local finalYaw = rec.finalYaw
			if finalYaw == nil then
				return true
			end
			rec.stage = "turn"
			rec.turnT = 0
			rec.turnFrom = rec.yaw
			rec.turnDelta = angleDiff(rec.yaw, finalYaw)
		end
		return false
	end

	-- "turn": rotate in place onto the final orientation.
	rec.turnT += dt
	local a = math.min(rec.turnT / FINAL_TURN_TIME, 1)
	local s = a * a * (3 - 2 * a)
	rec.yaw = rec.turnFrom + rec.turnDelta * s
	rec.model:PivotTo(CFrame.new(rec.pos) * CFrame.Angles(0, rec.yaw, 0))
	return a >= 1
end

local function onHeartbeat(dt: number)
	if dt > MAX_DT then
		dt = MAX_DT
	end
	for i = #active, 1, -1 do
		local rec = active[i]
		if rec == nil or rec.done then
			continue
		end
		if not rec.model:IsDescendantOf(game) then
			finish(rec, false)
			continue
		end
		local ok, result = pcall(step, rec, dt)
		if not ok then
			warn("[TrafficService] drive step failed: " .. tostring(result))
			finish(rec, false)
		elseif result then
			finish(rec, true)
		end
	end
end

--[[
	Drives `model` through `waypoints` at `speed` studs/s, then (optionally) to finalCFrame.Position and
	rotates onto finalCFrame's heading. The path starts at the model's current position.
	YIELDS until finished: it must be called from a yieldable thread (task.spawn / task.defer / event handler).
	Returns true when the drive completed, false if the model left the DataModel, the drive was stopped
	(TrafficService.stop), or the same model was given a new drive.
]]
function TrafficService.drive(model: Model, waypoints: { Vector3 }, speed: number, finalCFrame: CFrame?): boolean
	if not model:IsDescendantOf(game) then
		return false
	end
	if not coroutine.isyieldable() then
		warn("[TrafficService] drive must be called from a yieldable thread")
		return false
	end

	-- A model has at most one active drive.
	local previous = byModel[model]
	if previous then
		finish(previous, false)
	end

	local points: { Vector3 } = {}
	for _, p in waypoints do
		table.insert(points, flat(p))
	end
	local finalYaw: number? = nil
	if finalCFrame then
		table.insert(points, flat(finalCFrame.Position))
		finalYaw = yawOfDirection(finalCFrame.LookVector)
	end
	if #points == 0 then
		return true
	end

	local pivot = model:GetPivot()
	local rec: DriveRecord = {
		model = model,
		points = points,
		index = 1,
		speed = math.max(speed, 0.01),
		pos = flat(pivot.Position),
		yaw = yawOfDirection(pivot.LookVector),
		finalYaw = finalYaw,
		stage = "path",
		turnT = 0,
		turnFrom = 0,
		turnDelta = 0,
		thread = coroutine.running(),
		done = false,
	}
	table.insert(active, rec)
	byModel[model] = rec
	if connection == nil then
		connection = RunService.Heartbeat:Connect(onHeartbeat)
	end

	-- Resumed by finish() via task.defer(thread, ok).
	local result: any = coroutine.yield()
	return result == true
end

-- Cancels the active drive of `model`; the waiting drive() call returns false.
function TrafficService.stop(model: Model)
	local rec = byModel[model]
	if rec then
		finish(rec, false)
	end
end

----------------------------------------------------------------------------------------------------
-- Ambient traffic
----------------------------------------------------------------------------------------------------

local rng = Random.new()

local function pickCarType(): any
	local list = CarTypes.list
	local total = 0
	for _, entry in list do
		total += entry.weight
	end
	local roll = rng:NextNumber() * total
	for _, entry in list do
		roll -= entry.weight
		if roll <= 0 then
			return entry
		end
	end
	return list[#list]
end

local function runAmbientCar(folder: Folder, index: number)
	local carType = pickCarType()
	local colors = carType.colors
	local color: Color3 = colors[rng:NextInteger(1, #colors)]

	local built, model = pcall(function()
		return CarBuilder.build(carType.id, { color = color })
	end)
	if not built or model == nil then
		warn("[TrafficService] ambient CarBuilder.build failed: " .. tostring(model))
		return
	end
	local car = model :: Model

	local startAngle = (index - 1) * (2 * math.pi / AMBIENT_COUNT)
	local loop: { Vector3 } = Layout.ringArc(startAngle, startAngle + 2 * math.pi)
	local startPos: Vector3 = loop[1]
	local tangent = Vector3.new(math.cos(startAngle), 0, -math.sin(startAngle)) -- direction of increasing angle
	car:PivotTo(CFrame.lookAt(startPos, startPos + tangent))
	car.Name = "AmbientCar" .. index
	car.Parent = folder

	local speed = Game.ROAD_SPEED * AMBIENT_SPEED_FACTOR
	while car.Parent ~= nil do
		if not TrafficService.drive(car, loop, speed) then
			break
		end
	end
end

function TrafficService.start()
	local existing = Workspace:FindFirstChild("AmbientTraffic")
	local folder: Folder
	if existing ~= nil and existing:IsA("Folder") then
		folder = existing
	else
		folder = Instance.new("Folder")
		folder.Name = "AmbientTraffic"
		folder.Parent = Workspace
	end
	for i = 1, AMBIENT_COUNT do
		task.spawn(runAmbientCar, folder, i)
	end
end

return TrafficService
