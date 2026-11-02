--!strict
-- Turns a CarBuilder.buildCustom() car into a drivable physics car (docs/CONTRACT.md §18).
--
-- Constraint layout (all positions/axes are defined in WORLD space from Root's CFrame, so Hub orientation is irrelevant):
--
--   Chassis (invisible, low, heavy, collides)  <- Root + every body part are Massless and welded to it
--     |-- PrismaticConstraint "Suspension" (axis = car up, travel +-TRAVEL) + SpringConstraint "Spring"
--   Strut (hidden)                              one per wheel, sits at the wheel center
--     |-- rear:  HingeConstraint "WheelHinge" (axis = car X, Motor) ------------------------> Hub
--     |-- front: HingeConstraint "SteerServo" (axis = car up, Servo) --> Knuckle (hidden)
--                                  Knuckle -- HingeConstraint "WheelHinge" (axis = car X, Motor) --> Hub
--
-- All four wheels are motors (AWD): the controller drives and brakes through them.
-- Only Hub (cylinder) and Chassis collide; NoCollisionConstraints keep them from fighting each other.

local Workspace = game:GetService("Workspace")

local VehicleBuilder = {}

local WHEEL_TAGS = { "FL", "FR", "RL", "RR" }

local TRAVEL = 0.8 -- suspension travel up/down from the rest position (studs)
local SPRING_REST = 1.6 -- distance between the two spring attachments at rest
local BASE_SAG = 0.55 -- static sag (studs) of a corner at handling = 1
local DAMPING_RATIO = 0.7 -- fraction of critical damping: no bounce, still lively
local STEER_LIMIT = 50 -- degrees, hard stop of the steering hinge
local UP_AXIS = CFrame.Angles(0, 0, math.pi / 2) -- turns an attachment's X axis (hinge/prismatic axis) into +Y

local function num(inst: Instance, name: string, default: number): number
	local value = inst:GetAttribute(name)
	if type(value) == "number" then
		return value
	end
	return default
end

-- Invisible, non-colliding, unanchored helper part.
local function newPart(name: string, size: Vector3, cf: CFrame, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Transparency = 1
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Attachment whose WORLD CFrame is worldCF (part.CFrame must already be final).
local function attach(part: BasePart, worldCF: CFrame, name: string): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.CFrame = part.CFrame:ToObjectSpace(worldCF)
	attachment.Parent = part
	return attachment
end

local function weld(part0: BasePart, part1: BasePart, name: string, parent: Instance): WeldConstraint
	local w = Instance.new("WeldConstraint")
	w.Name = name
	w.Part0 = part0
	w.Part1 = part1
	w.Parent = parent
	return w
end

function VehicleBuilder.make(model: Model, stats: { [string]: number }): Model
	local rootInst: Instance? = model.PrimaryPart or model:FindFirstChild("Root")
	assert(rootInst ~= nil and rootInst:IsA("BasePart"), "VehicleBuilder.make: the car needs a Root part")
	local root = rootInst :: BasePart

	local grip: number = stats.grip or 1
	local handling: number = math.clamp(stats.handling or 1, 0.5, 2)
	local maxSpeed: number = stats.maxSpeed or 70

	local base = root.CFrame -- ground center of the car, nose = -Z
	local rot = base.Rotation
	local up = base.UpVector
	local width = root.Size.X
	local length = root.Size.Z
	local rideHeight = num(model, "RideHeight", 1)

	-- 1. visual parts: massless, no collision, unanchored (Root is un-anchored here too) ---------------------------
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Massless = true
			descendant.CanCollide = false
			descendant.Anchored = false
		end
	end

	-- 2. chassis: wide + low so the car is hard to flip, plus a heavy ballast under it -----------------------------
	local chassisCF = base * CFrame.new(0, rideHeight + 0.5, 0)
	local chassis = newPart("Chassis", Vector3.new(width * 0.9, 1, length * 0.85), chassisCF, model)
	chassis.CanCollide = true
	chassis.Massless = false
	chassis.CustomPhysicalProperties = PhysicalProperties.new(2, 0.3, 0, 1, 1)
	chassis.RootPriority = 10
	chassis.PivotOffset = CFrame.new(0, -(rideHeight + 0.5), 0) -- model:PivotTo(cf) puts the GROUND center at cf

	local ballast = newPart(
		"Ballast",
		Vector3.new(width * 0.5, 0.4, length * 0.4),
		base * CFrame.new(0, math.max(0.3, rideHeight - 0.2), 0),
		model
	)
	ballast.Massless = false
	ballast.CustomPhysicalProperties = PhysicalProperties.new(20, 0.3, 0, 1, 1)
	weld(chassis, ballast, "BallastWeld", chassis)

	weld(root, chassis, "RootWeld", chassis)
	root.Massless = true
	root.CanCollide = false

	-- spring numbers from the sprung mass (chassis + ballast; body parts are massless)
	local sprungMass = chassis.Mass + ballast.Mass
	local cornerMass = sprungMass / 4
	local sag = BASE_SAG / handling
	local stiffness = cornerMass * Workspace.Gravity / sag
	local damping = 2 * DAMPING_RATIO * math.sqrt(stiffness * cornerMass)
	local unsprungMass = 0

	-- 3. wheels ----------------------------------------------------------------------------------------------------
	for _, tag in WHEEL_TAGS do
		local wheel = model:FindFirstChild("Wheel_" .. tag)
		if not wheel or not wheel:IsA("Model") then
			warn("[VehicleBuilder] missing wheel model Wheel_" .. tag)
			continue
		end
		local hubInst: Instance? = wheel.PrimaryPart or wheel:FindFirstChild("Hub")
		if not hubInst or not hubInst:IsA("BasePart") then
			warn("[VehicleBuilder] Wheel_" .. tag .. " has no Hub")
			continue
		end
		local hub = hubInst :: BasePart
		local isFront = string.sub(tag, 1, 1) == "F"

		for _, descendant in wheel:GetDescendants() do
			if descendant.Name == "WheelWeld" then
				descendant:Destroy()
			end
		end

		hub.Anchored = false
		hub.Massless = false
		hub.CanCollide = true
		hub.CustomPhysicalProperties = PhysicalProperties.new(1, math.min(2, 1.6 * grip), 0, 100, 1)

		local hubPos = hub.Position
		local posFrame = CFrame.new(hubPos) * rot

		-- suspension carrier
		local strut = newPart("Strut", Vector3.new(1, 1, 1), posFrame, wheel)
		strut.CustomPhysicalProperties = PhysicalProperties.new(8, 0, 0, 1, 1)

		local suspensionFrame = posFrame * UP_AXIS -- X axis of the attachments = car up
		local suspA0 = attach(chassis, suspensionFrame, "Susp_" .. tag)
		local suspA1 = attach(strut, suspensionFrame, "Susp_" .. tag)
		local prismatic = Instance.new("PrismaticConstraint")
		prismatic.Name = "Suspension"
		prismatic.Attachment0 = suspA0
		prismatic.Attachment1 = suspA1
		prismatic.LimitsEnabled = true
		prismatic.LowerLimit = -TRAVEL
		prismatic.UpperLimit = TRAVEL
		prismatic.Restitution = 0
		prismatic.Visible = false
		prismatic.Parent = strut

		-- spring: upper end on the chassis, lower end on the strut; free length chosen so the rest position is mid-travel
		local springA0 = attach(chassis, CFrame.new(hubPos + up * SPRING_REST) * rot, "Spring_" .. tag)
		local spring = Instance.new("SpringConstraint")
		spring.Name = "Spring"
		spring.Attachment0 = springA0
		spring.Attachment1 = suspA1
		spring.FreeLength = SPRING_REST + sag
		spring.Stiffness = stiffness
		spring.Damping = damping
		spring.LimitsEnabled = false
		spring.Visible = false
		spring.Parent = strut

		-- who carries the hub: the steering knuckle (front) or the strut itself (rear)
		local carrier: BasePart = strut
		if isFront then
			local knuckle = newPart("Knuckle", Vector3.new(1, 1, 1), posFrame, wheel)
			knuckle.CustomPhysicalProperties = PhysicalProperties.new(6, 0, 0, 1, 1)
			local steerFrame = posFrame * UP_AXIS -- steering axis = car up, through the wheel center
			local servo = Instance.new("HingeConstraint")
			servo.Name = "SteerServo"
			servo.Attachment0 = attach(strut, steerFrame, "Steer_" .. tag)
			servo.Attachment1 = attach(knuckle, steerFrame, "Steer_" .. tag)
			servo.ActuatorType = Enum.ActuatorType.Servo
			servo.ServoMaxTorque = 2e5
			servo.AngularSpeed = 5
			servo.TargetAngle = 0
			servo.LimitsEnabled = true
			servo.LowerAngle = -STEER_LIMIT
			servo.UpperAngle = STEER_LIMIT
			servo.Restitution = 0
			servo.Visible = false
			servo.Parent = knuckle
			carrier = knuckle
			unsprungMass += knuckle.Mass
		end

		-- wheel axle: axis = car X (right). Motor; the controller sets velocity / torque.
		local axleFrame = posFrame
		local axle = Instance.new("HingeConstraint")
		axle.Name = "WheelHinge"
		axle.Attachment0 = attach(carrier, axleFrame, "Axle_" .. tag)
		axle.Attachment1 = attach(hub, axleFrame, "Axle_" .. tag)
		axle.ActuatorType = Enum.ActuatorType.Motor
		axle.AngularVelocity = 0
		axle.MotorMaxTorque = 2000
		axle.MotorMaxAcceleration = 1e6
		axle.LimitsEnabled = false
		axle.Restitution = 0
		axle.Visible = false
		axle.Parent = hub

		-- the wide chassis must not fight the wheels it is connected to
		local noCollide = Instance.new("NoCollisionConstraint")
		noCollide.Name = "NoCollide_" .. tag
		noCollide.Part0 = chassis
		noCollide.Part1 = hub
		noCollide.Parent = chassis

		unsprungMass += hub.Mass + strut.Mass
	end

	-- 4. driver seat -----------------------------------------------------------------------------------------------
	local seatAttachment = root:FindFirstChild("DriverSeat")
	local seatPos: Vector3
	if seatAttachment and seatAttachment:IsA("Attachment") then
		seatPos = root.CFrame:PointToWorldSpace(seatAttachment.Position)
	else
		seatPos = chassisCF:PointToWorldSpace(Vector3.new(0, 1, 0))
	end
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriveSeat"
	seat.Size = Vector3.new(2, 0.5, 2)
	seat.CFrame = CFrame.new(seatPos) * rot
	seat.Anchored = false
	seat.CanCollide = false
	seat.CanQuery = false
	seat.Massless = true
	seat.Transparency = 1
	seat.HeadsUpDisplay = false
	seat.MaxSpeed = 0 -- unused: VehicleController drives the wheel motors
	seat.Torque = 0
	seat.TurnSpeed = 0
	seat.Disabled = false
	seat.Parent = model
	weld(seat, chassis, "SeatWeld_Body", seat)

	-- 5. finish ----------------------------------------------------------------------------------------------------
	model.PrimaryPart = chassis
	model:SetAttribute("MaxSpeed", maxSpeed)
	model:SetAttribute("CarMass", sprungMass + unsprungMass)

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
		end
	end
	return model
end

return VehicleBuilder
