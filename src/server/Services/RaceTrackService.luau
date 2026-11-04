--!strict
-- Private race track: opens the annex back door when the RaceTrack unlock is owned and times laps.
-- The server decides everything: one Heartbeat checks every car with OnTrack = true against gate lines
-- (start/finish + 8 checkpoints). Gates are segment crossings, never Touched, so fast cars are not missed.
-- Results reach the client as attributes on the car model: LapStart, NextCheckpoint, CheckpointCount,
-- LastLap, BestLap, LapCount.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Layout = require(Shared.Layout)
local Remotes = require(Shared.Remotes)

local PlayerData = require(script.Parent.PlayerData)
local PlotService = require(script.Parent.PlotService)
local UnlockService = require(script.Parent.UnlockService)
local MapBuilder = require(script.Parent.MapBuilder)

local RaceTrackService = {}

local UNLOCK = "RaceTrack"
local ROOM = "TuningRoom"
local CHECK_INTERVAL = 0.06
local MAX_SPEED_FOR_CHEAT_CHECK = 220 -- studs/s: a lap faster than length / this is rejected
local MAX_JUMP = 90 -- studs between two checks; more means the car was moved, so skip that step

type CarState = {
	lastPos: Vector3?,
	started: boolean,
	lapStart: number,
	nextCheckpoint: number, -- 1 .. #checkpoints, #checkpoints + 1 = all passed
	laps: number,
}

local states: { [Model]: CarState } = {}
local doors: { [number]: Model } = {}
local rooms: { [number]: Model } = {}
local doorStash: Folder

local track = Layout.TRACK
local path: { Vector3 } = track.path
local pathCount = #path
local checkpointCount = #track.checkpoints
local minLapTime = track.length / MAX_SPEED_FOR_CHEAT_CHECK
local gateHalf = track.width / 2 + 3 -- gate line length = width + 6

-- Gate lines in plot-local XZ: a center, a unit direction of travel, and a unit sideways vector.
local gateCenters: { Vector3 } = {}
local gateForward: { Vector3 } = {}
local gateSide: { Vector3 } = {}

local function addGate(index: number)
	local before = path[(index - 2) % pathCount + 1]
	local after = path[index % pathCount + 1]
	local forward = (after - before).Unit
	table.insert(gateCenters, path[index])
	table.insert(gateForward, forward)
	table.insert(gateSide, Vector3.new(-forward.Z, 0, forward.X))
end

-- gate 1 = start/finish, gates 2.. = checkpoints in order
addGate(1)
for _, index in track.checkpoints do
	addGate(index)
end

local function cross2(a: Vector3, b: Vector3): number
	return a.X * b.Z - a.Z * b.X
end

-- True if the move prev -> cur crosses gate `gate` in the direction of travel.
local function crossedForward(gate: number, prev: Vector3, cur: Vector3): boolean
	local move = cur - prev
	move = Vector3.new(move.X, 0, move.Z)
	if move:Dot(gateForward[gate]) <= 0 then
		return false
	end
	local side = gateSide[gate]
	local denominator = cross2(move, side)
	if math.abs(denominator) < 1e-6 then
		return false
	end
	local toGate = gateCenters[gate] - prev
	toGate = Vector3.new(toGate.X, 0, toGate.Z)
	local along = cross2(toGate, side) / denominator -- 0..1 inside this step
	local across = cross2(toGate, move) / denominator -- distance from the gate center
	return along >= 0 and along <= 1 and math.abs(across) <= gateHalf
end

local function formatLap(seconds: number): string
	local minutes = math.floor(seconds / 60)
	return string.format("%d:%06.3f", minutes, seconds - minutes * 60)
end

local function publish(car: Model, state: CarState)
	car:SetAttribute("LapStart", if state.started then state.lapStart else nil)
	car:SetAttribute("NextCheckpoint", state.nextCheckpoint)
	car:SetAttribute("LapCount", state.laps)
end

local function finishLap(car: Model, player: Player, state: CarState, now: number)
	local lapTime = now - state.lapStart
	if lapTime < minLapTime then
		return -- too fast to be real: ignore and keep timing the current lap
	end
	state.laps += 1
	state.lapStart = now
	state.nextCheckpoint = 1

	local carId = car:GetAttribute("CarId")
	local previous = car:GetAttribute("BestLap")
	local isBest = type(previous) ~= "number" or lapTime < previous
	if isBest then
		car:SetAttribute("BestLap", lapTime)
		if type(carId) == "string" then
			PlayerData.update(player, function(d)
				local saved = d.bestLaps[carId]
				if saved == nil or lapTime < saved then
					d.bestLaps[carId] = lapTime
				end
			end)
		end
		Remotes.get("Notify"):FireClient(player, "notify_track_best", { formatLap(lapTime) })
		Remotes.get("Effect"):FireClient(player, "Level", car:GetPivot().Position + Vector3.new(0, 6, 0))
	end
	car:SetAttribute("LastLap", lapTime)
	publish(car, state) -- LapCount last: the HUD reacts to it and reads the other attributes
end

local function step(car: Model, now: number)
	local ownerId = car:GetAttribute("OwnerUserId")
	local player = if type(ownerId) == "number" then Players:GetPlayerByUserId(ownerId) else nil
	local plotIndex = if player then PlotService.getPlotIndex(player) else nil
	if not player or not plotIndex then
		return
	end

	local state = states[car]
	if not state then
		state = { lastPos = nil, started = false, lapStart = 0, nextCheckpoint = 1, laps = 0 }
		states[car] = state
		local data = PlayerData.get(player)
		local carId = car:GetAttribute("CarId")
		local best = if data and type(carId) == "string" then data.bestLaps[carId] else nil
		car:SetAttribute("CheckpointCount", checkpointCount)
		car:SetAttribute("BestLap", best)
		car:SetAttribute("LastLap", nil)
		publish(car, state)
	end
	local current = state :: CarState

	local here = Layout.plotCFrame(plotIndex):PointToObjectSpace(car:GetPivot().Position)
	local prev = current.lastPos
	current.lastPos = here
	if not prev or (here - prev).Magnitude > MAX_JUMP then
		return
	end

	if not current.started then
		if crossedForward(1, prev, here) then
			current.started = true
			current.lapStart = now
			current.nextCheckpoint = 1
			publish(car, current)
		end
		return
	end

	if current.nextCheckpoint <= checkpointCount then
		if crossedForward(current.nextCheckpoint + 1, prev, here) then
			current.nextCheckpoint += 1
			publish(car, current)
		end
	elseif crossedForward(1, prev, here) then
		finishLap(car, player, current, now)
	end
end

local function openDoor(plotIndex: number, open: boolean)
	local door = doors[plotIndex]
	local room = rooms[plotIndex]
	if door and room then
		door.Parent = if open then doorStash else room
	end
end

local function refreshDoor(player: Player, plotIndex: number)
	openDoor(plotIndex, UnlockService.isOwned(player, UNLOCK))
end

-- The Tuning room lives under plot.Unlockables, or in ServerStorage while it is locked.
local function findRoom(plotIndex: number): Model?
	local plot = MapBuilder.getPlot(plotIndex)
	local unlockables = plot:FindFirstChild("Unlockables")
	local room = unlockables and unlockables:FindFirstChild(ROOM)
	if not room then
		local storage = ServerStorage:FindFirstChild("LockedUnlockables")
		local plotStorage = storage and storage:FindFirstChild("Plot" .. plotIndex)
		room = plotStorage and plotStorage:FindFirstChild("Unlockables_" .. ROOM)
	end
	return if room and room:IsA("Model") then room else nil
end

function RaceTrackService.init()
	local stash = Instance.new("Folder")
	stash.Name = "TrackDoors"
	stash.Parent = ServerStorage
	doorStash = stash
end

function RaceTrackService.start()
	for plotIndex = 1, Layout.PLOT_COUNT do
		local room = findRoom(plotIndex)
		local door = if room then room:FindFirstChild("TrackDoor") else nil
		if room and door and door:IsA("Model") then
			rooms[plotIndex] = room
			doors[plotIndex] = door
		else
			warn("[RaceTrackService] TrackDoor missing on plot " .. plotIndex)
		end
	end

	PlotService.onAssigned(refreshDoor)
	PlotService.onReleased(function(_player, plotIndex)
		openDoor(plotIndex, false)
	end)
	UnlockService.onUnlocked(function(player, id)
		local plotIndex = PlotService.getPlotIndex(player)
		if id == UNLOCK and plotIndex then
			refreshDoor(player, plotIndex)
		end
	end)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < CHECK_INTERVAL then
			return
		end
		elapsed = 0
		local now = workspace:GetServerTimeNow()
		local folder = workspace:FindFirstChild("PlayerCars")
		if folder then
			for _, car in folder:GetChildren() do
				if car:IsA("Model") and car:GetAttribute("OnTrack") == true then
					local ok, err = pcall(step, car, now)
					if not ok then
						warn("[RaceTrackService] " .. tostring(err))
					end
				end
			end
		end
		for car in states do
			if car.Parent == nil then
				states[car] = nil
			end
		end
	end)
end

return RaceTrackService
