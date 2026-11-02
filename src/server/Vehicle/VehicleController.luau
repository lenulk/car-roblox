--!strict
-- Drives cars made by VehicleBuilder from the DriveSeat's ThrottleFloat / SteerFloat (docs/CONTRACT.md §18).
-- One shared Heartbeat loop for every attached car. Wheel motors: HingeConstraint "WheelHinge" (axis = car X),
-- steering: HingeConstraint "SteerServo" (axis = car up).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local VehicleController = {}

-- tuning ------------------------------------------------------------------------------------------------------
local DRIVE_ACCEL = 22 -- studs/s^2 at accel = 1 (limited by motor torque)
local ROLL_DECEL = 5 -- gentle rolling resistance when the throttle is released
local BRAKE_DECEL = 70 -- studs/s^2 at braking = 1
local PARK_DECEL = 150 -- parked / empty cars hold still
local REVERSE_FRACTION = 0.4
local BRAKE_THRESHOLD = 3 -- studs/s: throttle against the direction of travel above this speed = braking
local STEER_AT_REST = 35 -- degrees
local STEER_AT_TOP = 12
local DOWNFORCE_FRACTION = 0.3 -- of the car's weight, reached at top speed
local FLIP_UP_Y = 0.3
local FLIP_SECONDS = 2
local FLAME_LINGER = 0.5

type State = {
	model: Model,
	chassis: BasePart,
	seat: VehicleSeat,
	maxSpeed: number,
	accel: number,
	handling: number,
	braking: number,
	radius: number,
	fallbackMass: number,
	motors: { HingeConstraint },
	servos: { HingeConstraint },
	knuckle: BasePart?,
	flames: { ParticleEmitter },
	smokes: { ParticleEmitter },
	flameOn: boolean,
	smokeOn: boolean,
	flameUntil: number,
	downforce: VectorForce?,
	downAttachment: Attachment?,
	lastDown: number,
	conns: { RBXScriptConnection },
	-- sign calibration (HingeConstraint direction conventions are verified against real motion at run time)
	motorSign: number,
	motorLocked: boolean,
	motorCooldown: number,
	steerSign: number,
	steerLocked: boolean,
	steerCooldown: number,
	flipTimer: number,
	lastW: number,
	lastTorque: number,
	lastTarget: number,
}

local cars: { [Model]: State } = {}
local carCount = 0
local loopConn: RBXScriptConnection? = nil

local function setEmitters(list: { ParticleEmitter }, on: boolean)
	for _, emitter in list do
		emitter.Enabled = on
	end
end

local function setMotors(state: State, w: number, torque: number)
	if math.abs(w - state.lastW) < 0.02 and math.abs(torque - state.lastTorque) < 1 then
		return
	end
	state.lastW = w
	state.lastTorque = torque
	for _, motor in state.motors do
		motor.AngularVelocity = w
		motor.MotorMaxTorque = torque
	end
end

local function setSteer(state: State, degrees: number)
	if math.abs(degrees - state.lastTarget) < 0.2 then
		return
	end
	state.lastTarget = degrees
	for _, servo in state.servos do
		servo.TargetAngle = degrees
	end
end

local function carMass(state: State): number
	local mass = state.chassis.AssemblyMass
	if mass < 1 then
		mass = state.fallbackMass
	end
	return mass
end

local function applyOwner(state: State)
	local humanoid = state.seat.Occupant
	local player: Player? = nil
	if humanoid then
		local character = humanoid.Parent
		if character then
			player = Players:GetPlayerFromCharacter(character)
		end
	end
	pcall(function()
		state.chassis:SetNetworkOwner(player)
	end)
end

-- Puts a capsized car back on its wheels, 3 studs higher, keeping its heading.
local function rightCar(state: State)
	local chassis = state.chassis
	local cf = chassis.CFrame
	local flat = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	if flat.Magnitude < 0.2 then
		flat = Vector3.new(cf.UpVector.X, 0, cf.UpVector.Z)
	end
	if flat.Magnitude < 0.2 then
		flat = Vector3.new(0, 0, -1)
	end
	local pos = cf.Position + Vector3.new(0, 3, 0)
	local upright = CFrame.lookAt(pos, pos + flat.Unit)
	-- hand the physics to the server while teleporting, then give it back to the driver
	pcall(function()
		chassis:SetNetworkOwner(nil)
	end)
	state.model:PivotTo(upright * chassis.PivotOffset)
	for _, part in state.model:GetDescendants() do
		if part:IsA("BasePart") then
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
	task.delay(0.25, function()
		if cars[state.model] == state then
			applyOwner(state)
		end
	end)
end

local function step(state: State, dt: number, now: number)
	local chassis = state.chassis
	local seat = state.seat
	local cf = chassis.CFrame
	local velocity = chassis.AssemblyLinearVelocity
	local planar = Vector3.new(velocity.X, 0, velocity.Z)
	local speed = planar.Magnitude
	local forwardSpeed = planar:Dot(cf.LookVector) -- > 0 = moving nose first
	local maxSpeed = state.maxSpeed
	local occupied = seat.Occupant ~= nil

	local throttle = 0
	local steer = 0
	if occupied then
		throttle = math.clamp(seat.ThrottleFloat, -1, 1)
		steer = math.clamp(seat.SteerFloat, -1, 1)
	end

	-- motors --------------------------------------------------------------------------------------------------------
	local torqueUnit = carMass(state) * 0.25 * state.radius -- torque per wheel for 1 stud/s^2 of car acceleration
	local w = 0
	local torque = 0
	local braking = false
	local brakeAt = if state.motorLocked then BRAKE_THRESHOLD else math.huge
	if not occupied then
		torque = torqueUnit * PARK_DECEL
	elseif math.abs(throttle) < 0.05 then
		torque = torqueUnit * ROLL_DECEL
	elseif throttle * forwardSpeed < -brakeAt then
		braking = true
		torque = torqueUnit * BRAKE_DECEL * state.braking * (0.4 + 0.6 * math.abs(throttle))
	else
		local direction = if throttle > 0 then 1 else -1
		local targetSpeed = throttle * maxSpeed * (if direction < 0 then REVERSE_FRACTION else 1) -- signed, + = forward
		w = state.motorSign * targetSpeed / state.radius
		torque = torqueUnit * DRIVE_ACCEL * state.accel
		-- first drive: check that +w really moves the car nose first, else flip the sign once
		if not state.motorLocked and now >= state.motorCooldown and math.abs(forwardSpeed) > 2.5 then
			if forwardSpeed * direction > 0 then
				state.motorLocked = true
			else
				state.motorSign = -state.motorSign
				state.motorCooldown = now + 0.6
			end
		end
	end
	setMotors(state, w, torque)

	-- steering --------------------------------------------------------------------------------------------------------
	local speedFraction = math.clamp(speed / maxSpeed, 0, 1)
	local maxAngle = STEER_AT_REST + (STEER_AT_TOP - STEER_AT_REST) * speedFraction
	maxAngle = math.clamp(maxAngle * math.clamp(state.handling, 0.6, 1.5), 6, 45)
	local desired = steer * maxAngle -- + = right
	setSteer(state, desired * state.steerSign)
	local knuckle = state.knuckle
	if knuckle and not state.steerLocked and now >= state.steerCooldown and math.abs(desired) > 8 then
		local look = cf:VectorToObjectSpace(knuckle.CFrame.LookVector)
		local yaw = math.deg(math.asin(math.clamp(look.X, -1, 1))) -- + = wheels point right
		if math.abs(yaw) > 4 then
			if yaw * desired > 0 then
				state.steerLocked = true
			else
				state.steerSign = -state.steerSign
				state.steerCooldown = now + 0.6
			end
		end
	end

	-- downforce -------------------------------------------------------------------------------------------------------
	local downforce = state.downforce
	if downforce then
		local force = DOWNFORCE_FRACTION * carMass(state) * Workspace.Gravity * speedFraction * speedFraction
		if math.abs(force - state.lastDown) > 20 then
			state.lastDown = force
			downforce.Force = Vector3.new(0, -force, 0)
		end
	end

	-- anti-flip -------------------------------------------------------------------------------------------------------
	if cf.UpVector.Y < FLIP_UP_Y then
		state.flipTimer += dt
		if state.flipTimer > FLIP_SECONDS then
			state.flipTimer = 0
			rightCar(state)
		end
	else
		state.flipTimer = 0
	end

	-- effects ---------------------------------------------------------------------------------------------------------
	if throttle > 0.9 and speed > 0.6 * maxSpeed then
		state.flameUntil = now + FLAME_LINGER
	end
	local flame = now < state.flameUntil
	if flame ~= state.flameOn then
		state.flameOn = flame
		setEmitters(state.flames, flame)
	end
	local smoke = (math.abs(steer) > 0.6 and speed > 0.4 * maxSpeed)
		or (braking and speed > 0.3 * maxSpeed and math.abs(throttle) > 0.5)
	if smoke ~= state.smokeOn then
		state.smokeOn = smoke
		setEmitters(state.smokes, smoke)
	end
end

local function stopLoopIfIdle()
	if carCount <= 0 and loopConn then
		loopConn:Disconnect()
		loopConn = nil
	end
end

local function ensureLoop()
	if loopConn then
		return
	end
	loopConn = RunService.Heartbeat:Connect(function(dt: number)
		local now = os.clock()
		for model, state in cars do
			if not state.chassis.Parent or not state.seat.Parent then
				VehicleController.detach(model)
			else
				local ok, err = pcall(step, state, dt, now)
				if not ok then
					warn("[VehicleController] " .. tostring(err))
					VehicleController.detach(model)
				end
			end
		end
	end)
end

function VehicleController.attach(model: Model, stats: { [string]: number })
	if cars[model] then
		VehicleController.detach(model)
	end
	local chassis = model:FindFirstChild("Chassis")
	local seat = model:FindFirstChild("DriveSeat")
	if not chassis or not chassis:IsA("BasePart") or not seat or not seat:IsA("VehicleSeat") then
		warn("[VehicleController] car is missing Chassis / DriveSeat (run VehicleBuilder.make first)")
		return
	end

	local motors: { HingeConstraint } = {}
	local servos: { HingeConstraint } = {}
	local flames: { ParticleEmitter } = {}
	local smokes: { ParticleEmitter } = {}
	local knuckle: BasePart? = nil
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("HingeConstraint") then
			if descendant.Name == "WheelHinge" then
				table.insert(motors, descendant)
			elseif descendant.Name == "SteerServo" then
				table.insert(servos, descendant)
				local a1 = descendant.Attachment1
				if knuckle == nil and a1 and a1.Parent and a1.Parent:IsA("BasePart") then
					knuckle = a1.Parent :: BasePart
				end
			end
		elseif descendant:IsA("ParticleEmitter") then
			if descendant.Name == "Flame" then
				table.insert(flames, descendant)
			elseif descendant.Name == "TireSmoke" then
				table.insert(smokes, descendant)
			end
		end
	end

	local maxSpeed = stats.maxSpeed
	if type(maxSpeed) ~= "number" or maxSpeed <= 0 then
		local attr = model:GetAttribute("MaxSpeed")
		maxSpeed = if type(attr) == "number" then attr else 70
	end
	local wheelDiameter = model:GetAttribute("WheelDiameter")
	local radius = if type(wheelDiameter) == "number" and wheelDiameter > 0 then wheelDiameter / 2 else 1.6
	local massAttr = model:GetAttribute("CarMass")

	local state: State = {
		model = model,
		chassis = chassis :: BasePart,
		seat = seat :: VehicleSeat,
		maxSpeed = maxSpeed,
		accel = stats.accel or 1,
		handling = stats.handling or 1,
		braking = stats.braking or 1,
		radius = radius,
		fallbackMass = if type(massAttr) == "number" then massAttr else 400,
		motors = motors,
		servos = servos,
		knuckle = knuckle,
		flames = flames,
		smokes = smokes,
		flameOn = false,
		smokeOn = false,
		flameUntil = 0,
		downforce = nil,
		downAttachment = nil,
		lastDown = 0,
		conns = {},
		motorSign = -1, -- +X axis, right-hand rule: negative spin = nose (-Z) first
		motorLocked = false,
		motorCooldown = 0,
		steerSign = -1, -- + angle about car up turns left; steer + = right
		steerLocked = false,
		steerCooldown = 0,
		flipTimer = 0,
		lastW = 1e9,
		lastTorque = 1e9,
		lastTarget = 1e9,
	}

	-- optional downforce (speed^2) --------------------------------------------------------------------------------
	local downAttachment = Instance.new("Attachment")
	downAttachment.Name = "DownforceAttachment"
	downAttachment.Parent = state.chassis
	local downforce = Instance.new("VectorForce")
	downforce.Name = "Downforce"
	downforce.Attachment0 = downAttachment
	downforce.RelativeTo = Enum.ActuatorRelativeTo.World
	downforce.ApplyAtCenterOfMass = true
	downforce.Force = Vector3.zero
	downforce.Parent = state.chassis
	state.downAttachment = downAttachment
	state.downforce = downforce

	setEmitters(flames, false)
	setEmitters(smokes, false)

	-- network ownership follows the occupant; cleanup on destroy ----------------------------------------------------
	table.insert(
		state.conns,
		state.seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			applyOwner(state)
		end)
	)
	table.insert(
		state.conns,
		model.Destroying:Connect(function()
			VehicleController.detach(model)
		end)
	)
	table.insert(
		state.conns,
		model.AncestryChanged:Connect(function()
			if not model:IsDescendantOf(game) then
				VehicleController.detach(model)
			end
		end)
	)

	cars[model] = state
	carCount += 1
	if state.seat.Occupant ~= nil then
		applyOwner(state)
	end
	ensureLoop()
end

function VehicleController.detach(model: Model)
	local state = cars[model]
	if not state then
		return
	end
	cars[model] = nil
	carCount -= 1
	for _, conn in state.conns do
		conn:Disconnect()
	end
	table.clear(state.conns)
	if state.downforce then
		state.downforce:Destroy()
		state.downforce = nil
	end
	if state.downAttachment then
		state.downAttachment:Destroy()
		state.downAttachment = nil
	end
	-- leave a live car parked and its effects off (harmless if the model is being destroyed)
	pcall(function()
		setEmitters(state.flames, false)
		setEmitters(state.smokes, false)
		for _, motor in state.motors do
			motor.AngularVelocity = 0
			motor.MotorMaxTorque = 20000
		end
		for _, servo in state.servos do
			servo.TargetAngle = 0
		end
	end)
	stopLoopIfIdle()
end

-- planar speed in studs/s
function VehicleController.speed(model: Model): number
	local state = cars[model]
	local part: BasePart? = if state then state.chassis else model.PrimaryPart
	if not part then
		return 0
	end
	local velocity = part.AssemblyLinearVelocity
	return Vector3.new(velocity.X, 0, velocity.Z).Magnitude
end

return VehicleController
