--!strict
-- The player's car and six scripted rivals, all simulated in "track space" (s along the track, d sideways).
-- No physics: every car is Anchored and placed with PivotTo each frame.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config: any = require(Shared:WaitForChild("Config"):WaitForChild("Prologue") :: ModuleScript)
local CarBuilder: any = require(Shared:WaitForChild("CarBuilder") :: ModuleScript)
local CarTypes: any = require(Shared:WaitForChild("Config"):WaitForChild("CarTypes") :: ModuleScript)
local SoundFx: any = require(Shared:WaitForChild("SoundFx") :: ModuleScript)
local Track: any = require((script.Parent :: Instance):WaitForChild("Track") :: ModuleScript)

local RaceCars = {}

local WHEEL_NAMES = { "Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR" }
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE_TEXTURE = "rbxasset://textures/particles/fire_main.dds"
local SPIN_RANGE_SQ = 130 * 130

local rng = Random.new()

type Car = {
	model: Model,
	root: BasePart,
	isPlayer: boolean,
	s: number,
	d: number,
	speed: number,
	lat: number, -- sideways speed
	width: number,
	length: number,
	base: number, -- rival cruise speed
	lane: number, -- rival preferred d
	bumpCooldown: number,
	wheels: { Model },
	wheelRadius: number,
	wheelAngle: number,
	cf: CFrame,
}

local function approach(value: number, target: number, maxStep: number): number
	if value < target then
		return math.min(value + maxStep, target)
	end
	return math.max(value - maxStep, target)
end

local function prepare(model: Model)
	for _, d in model:GetDescendants() do
		-- Every part is anchored and moved with PivotTo, so welds are not needed. They must go: with a weld to
		-- Root, pivoting a wheel would drag the whole car around the wheel axis.
		if d:IsA("WeldConstraint") or d:IsA("JointInstance") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
		end
	end
end

local function makeCar(parent: Instance, carType: string, color: Color3, isPlayer: boolean): Car
	local model: Model = CarBuilder.build(carType, { color = color })
	model.Name = if isPlayer then "PlayerCar" else "Rival_" .. carType
	prepare(model)
	model.Parent = parent
	local def: any = CarTypes.byId[carType]
	local size: Vector3 = if def then def.size else Vector3.new(7.4, 4.2, 15)
	local wheels: { Model } = {}
	for _, name in WHEEL_NAMES do
		local wheel = model:FindFirstChild(name)
		if wheel and wheel:IsA("Model") and wheel.PrimaryPart then
			table.insert(wheels, wheel)
		end
	end
	local diameter = model:GetAttribute("WheelDiameter")
	local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	return {
		model = model,
		root = root :: BasePart,
		isPlayer = isPlayer,
		s = 0,
		d = 0,
		speed = 0,
		lat = 0,
		width = size.X,
		length = size.Z,
		base = 70,
		lane = 0,
		bumpCooldown = 0,
		wheels = wheels,
		wheelRadius = if type(diameter) == "number" and diameter > 0.5 then diameter / 2 else 1.6,
		wheelAngle = 0,
		cf = CFrame.new(),
	}
end

local function newEmitter(parent: Instance, name: string): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Enabled = false
	e.Rate = 0
	e.Parent = parent
	return e
end

function RaceCars.new(arenaFolder: Instance): any
	local folder = Instance.new("Folder")
	folder.Name = "RaceCars"
	folder.Parent = arenaFolder

	local race: any = {}

	local rivals: { Car } = {}
	local all: { Car } = {}
	local started = false
	local smoking = false
	local blown = false
	local rubber = true
	local onBump: ((position: Vector3) -> ())? = nil

	----------------------------------------------------------------------------------------------
	-- Build the cars on the grid
	----------------------------------------------------------------------------------------------
	local playerSlot: number = Config.GRID_SLOTS
	local player = makeCar(folder, Config.PLAYER_CAR, Config.PLAYER_COLOR, true)
	player.s, player.d = Track.gridSlot(playerSlot)
	table.insert(all, player)

	for index, rivalCfg in Config.RIVALS do
		local rival = makeCar(folder, rivalCfg.car, rivalCfg.color, false)
		rival.s, rival.d = Track.gridSlot(index)
		rival.base = rivalCfg.speed
		rival.lane = rivalCfg.lane
		table.insert(rivals, rival)
		table.insert(all, rival)
		task.wait() -- spread the build over frames
	end

	race.player = player
	race.rivals = rivals
	race.total = #all

	----------------------------------------------------------------------------------------------
	-- Engine trouble effects (on the player's car)
	----------------------------------------------------------------------------------------------
	local hood = Instance.new("Attachment")
	hood.Name = "HoodFx"
	hood.Position = Vector3.new(0, 2.6, -player.length * 0.26)
	hood.Parent = player.root

	local smokeGray = newEmitter(hood, "SmokeGray")
	smokeGray.Texture = SMOKE_TEXTURE
	smokeGray.Rate = 28
	smokeGray.Lifetime = NumberRange.new(1.2, 2.2)
	smokeGray.Speed = NumberRange.new(5, 9)
	smokeGray.SpreadAngle = Vector2.new(18, 18)
	smokeGray.Acceleration = Vector3.new(0, 5, 0)
	smokeGray.Rotation = NumberRange.new(0, 360)
	smokeGray.RotSpeed = NumberRange.new(-60, 60)
	smokeGray.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.2),
		NumberSequenceKeypoint.new(1, 5),
	})
	smokeGray.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	smokeGray.Color = ColorSequence.new(Color3.fromRGB(190, 190, 195))

	local smokeBlack = newEmitter(hood, "SmokeBlack")
	smokeBlack.Texture = SMOKE_TEXTURE
	smokeBlack.Rate = 60
	smokeBlack.Lifetime = NumberRange.new(2, 3.4)
	smokeBlack.Speed = NumberRange.new(8, 14)
	smokeBlack.SpreadAngle = Vector2.new(24, 24)
	smokeBlack.Acceleration = Vector3.new(0, 7, 0)
	smokeBlack.Rotation = NumberRange.new(0, 360)
	smokeBlack.RotSpeed = NumberRange.new(-50, 50)
	smokeBlack.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 3),
		NumberSequenceKeypoint.new(1, 11),
	})
	smokeBlack.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	smokeBlack.Color = ColorSequence.new(Color3.fromRGB(28, 28, 30))

	local fire = newEmitter(hood, "Fire")
	fire.Texture = FIRE_TEXTURE
	fire.Rate = 70
	fire.Lifetime = NumberRange.new(0.5, 0.9)
	fire.Speed = NumberRange.new(4, 9)
	fire.SpreadAngle = Vector2.new(22, 22)
	fire.Acceleration = Vector3.new(0, 10, 0)
	fire.Rotation = NumberRange.new(0, 360)
	fire.LightEmission = 1
	fire.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 3.4),
		NumberSequenceKeypoint.new(1, 0.6),
	})
	fire.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	fire.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 220, 90)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(235, 60, 20)),
	})

	local sparks = newEmitter(hood, "Sparks")
	sparks.Lifetime = NumberRange.new(0.4, 1)
	sparks.Speed = NumberRange.new(35, 75)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Acceleration = Vector3.new(0, -60, 0)
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 190, 70))

	local wallSparks = newEmitter(player.root, "WallSparks")
	wallSparks.Lifetime = NumberRange.new(0.25, 0.6)
	wallSparks.Speed = NumberRange.new(18, 40)
	wallSparks.SpreadAngle = Vector2.new(60, 60)
	wallSparks.Acceleration = Vector3.new(0, -50, 0)
	wallSparks.LightEmission = 1
	wallSparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	wallSparks.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120))

	----------------------------------------------------------------------------------------------
	-- Placement
	----------------------------------------------------------------------------------------------
	local function place(car: Car, dt: number, cameraPosition: Vector3?)
		local lateralFraction = math.clamp(car.lat / Config.STEER_SPEED, -1, 1)
		local yaw = -lateralFraction * 0.14
		local roll = lateralFraction * 0.03
		local cf: CFrame = Track.cframeAt(car.s, car.d) * CFrame.new(0, 0.15, 0) * CFrame.Angles(0, yaw, roll)
		car.cf = cf
		car.model:PivotTo(cf)
		if dt > 0 and #car.wheels > 0 then
			-- The body PivotTo above carries each wheel's previous rotation along, so only this frame's
			-- angle step is applied here (a running total would make the spin speed up every frame).
			local step = car.speed * dt / car.wheelRadius
			car.wheelAngle += step
			local spin = car.isPlayer
			if not spin and cameraPosition then
				local delta = cf.Position - cameraPosition
				spin = delta:Dot(delta) < SPIN_RANGE_SQ
			end
			if spin then
				local rotation = CFrame.Angles(-step, 0, 0)
				for _, wheel in car.wheels do
					wheel:PivotTo(wheel:GetPivot() * rotation)
				end
			end
		end
	end

	for _, car in all do
		place(car, 0, nil)
	end

	----------------------------------------------------------------------------------------------
	-- API
	----------------------------------------------------------------------------------------------
	function race.setBumpHandler(fn: (position: Vector3) -> ())
		onBump = fn
	end

	function race.start()
		started = true
	end

	function race.setRubberBand(enabled: boolean)
		rubber = enabled
	end

	function race.isBlown(): boolean
		return blown
	end

	-- Player lap fraction (can be slightly negative while still behind the start line).
	function race.progress(): number
		return player.s / Track.length
	end

	-- 1 = leading.
	function race.rank(): number
		local ahead = 0
		for _, r in rivals do
			if r.s > player.s then
				ahead += 1
			end
		end
		return ahead + 1
	end

	function race.setSmoking(on: boolean)
		smoking = on
		smokeGray.Enabled = on and not blown
	end

	-- Engine explodes: control is cut, fire and smoke start, a flash and sparks go off.
	function race.blow()
		if blown then
			return
		end
		blown = true
		smoking = false
		rubber = false
		player.lat = 0
		smokeGray.Enabled = false
		smokeBlack.Enabled = true
		fire.Enabled = true
		sparks:Emit(80)

		local flashCf: CFrame = player.cf * CFrame.new(0, 3, -player.length * 0.26)
		local flash = Instance.new("Part")
		flash.Name = "BlastFlash"
		flash.Shape = Enum.PartType.Ball
		flash.Anchored = true
		flash.CanCollide = false
		flash.CanQuery = false
		flash.CanTouch = false
		flash.CastShadow = false
		flash.Material = Enum.Material.Neon
		flash.Color = Color3.fromRGB(255, 214, 120)
		flash.Size = Vector3.new(6, 6, 6)
		flash.CFrame = flashCf
		flash.Parent = folder
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 190, 100)
		light.Range = 70
		light.Brightness = 10
		light.Parent = flash
		TweenService:Create(
			flash,
			TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = Vector3.new(34, 34, 34), Transparency = 1 }
		):Play()
		TweenService:Create(light, TweenInfo.new(0.7), { Brightness = 0 }):Play()
		task.delay(0.9, function()
			flash:Destroy()
		end)

		-- the engine keeps burning: a steady glow on the hood
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(255, 140, 50)
		glow.Range = 28
		glow.Brightness = 2.5
		glow.Parent = hood
	end

	-- One frame of simulation. steer: -1..1 (+ = right), throttle: -1..1 (+ = forward).
	function race.step(dt: number, steer: number, throttle: number, cameraPosition: Vector3?)
		local half: number = Track.halfWidth
		local lap: number = Track.length

		if started then
			----------------------------------------------------------------------------------------
			-- player
			----------------------------------------------------------------------------------------
			if blown then
				player.speed *= math.exp(-Config.COAST_DECAY * dt)
				if player.speed < 1.5 then
					player.speed = 0
				end
				local outer: number = Track.outerSign(player.s)
				local target = outer * (half - player.width / 2 - 2.5)
				player.d += (target - player.d) * math.min(1, dt * 1.2)
				player.lat = (target - player.d) * 0.4 * math.min(1, player.speed / 20)
			else
				local topSpeed: number = Config.MAX_SPEED * (if smoking then Config.SMOKE_SPEED_FACTOR else 1)
				local cruise = math.min(Config.CRUISE_SPEED, topSpeed)
				local target = cruise
				if throttle > 0.3 then
					target = topSpeed
				elseif throttle < -0.3 then
					target = Config.BRAKE_SPEED
				end
				local rate = if target > player.speed then Config.ACCEL else Config.DECEL
				player.speed = approach(player.speed, target, rate * dt)

				local speedFactor = 1 - 0.35 * math.clamp(player.speed / Config.MAX_SPEED, 0, 1)
				player.lat = approach(
					player.lat,
					math.clamp(steer, -1, 1) * Config.STEER_SPEED * speedFactor,
					Config.STEER_RESPONSE * dt
				)
				player.d += player.lat * dt

				local limit = half - player.width / 2
				player.bumpCooldown = math.max(0, player.bumpCooldown - dt)
				if math.abs(player.d) > limit then
					player.d = math.sign(player.d) * limit
					player.lat = 0
					if player.bumpCooldown <= 0 then
						player.bumpCooldown = 0.6
						player.speed *= 1 - Config.WALL_SPEED_LOSS
						wallSparks:Emit(24)
						if onBump then
							onBump(player.cf.Position)
						end
					end
				end
			end
			player.s += player.speed * dt

			----------------------------------------------------------------------------------------
			-- rivals
			----------------------------------------------------------------------------------------
			for _, r in rivals do
				local gap = r.s - player.s -- > 0: rival is ahead of the player
				-- Pace follows the player so the pack stays together: rivals ahead run a little slower than the
				-- player (the player reels them in over the lap, not in the first seconds), rivals behind stay
				-- close and catch up when they fall far back. After the blow-up they charge past.
				local pace = r.base
				if rubber then
					if gap > 0 then
						pace = math.max(r.base * (1 - Config.RUBBER_SLOW), player.speed * Config.RUBBER_AHEAD_PACE)
					else
						local far = math.clamp((-gap - 30) / Config.RUBBER_BEHIND_RANGE, 0, 1)
						local behindPace = Config.RUBBER_BEHIND_PACE + (Config.RUBBER_CATCHUP_PACE - Config.RUBBER_BEHIND_PACE) * far
						pace = math.max(r.base, player.speed * behindPace)
					end
				elseif blown then
					pace = r.base * Config.BLOWN_RIVAL_BOOST
				end
				local curveAhead: number = Track.maxCurvatureAhead(r.s, 70)
				local cornerSpeed = math.huge
				if curveAhead > 1e-4 then
					cornerSpeed = math.sqrt(Config.CORNER_GRIP / curveAhead)
				end
				local targetSpeed = math.min(pace, cornerSpeed)
				local desiredD = r.lane

				for _, other in all do
					-- no dodging while standing on the grid
					if other ~= r and r.speed > 15 then
						local ds = Track.wrapDelta(other.s - r.s)
						local dd = other.d - r.d
						local needed = (r.width + other.width) / 2
						if ds > 0 and ds < r.length + 30 and math.abs(dd) < needed + 1.5 then
							local dir = if r.d >= other.d then 1 else -1
							local candidate = other.d + dir * (needed + 2)
							local limit = half - r.width / 2 - 1
							if math.abs(candidate) > limit then
								candidate = other.d - dir * (needed + 2)
							end
							desiredD = candidate
							if ds < r.length + 6 and math.abs(dd) < needed * 0.9 then
								targetSpeed = math.min(targetSpeed, other.speed * 0.98)
							end
						end
					end
				end

				local rate = if targetSpeed > r.speed then Config.RIVAL_ACCEL else Config.RIVAL_DECEL
				r.speed = approach(r.speed, targetSpeed, rate * dt)
				local previousD = r.d
				local limitD = half - r.width / 2 - 0.5
				local nextD = r.d + math.clamp(desiredD - r.d, -Config.AVOID_RATE * dt, Config.AVOID_RATE * dt)
				r.d = math.clamp(nextD, -limitD, limitD)
				r.lat = if dt > 0 then (r.d - previousD) / dt else 0
				r.s += r.speed * dt
				r.bumpCooldown = math.max(0, r.bumpCooldown - dt)
			end

			----------------------------------------------------------------------------------------
			-- player <-> rival contact
			----------------------------------------------------------------------------------------
			if not blown then
				for _, r in rivals do
					local ds = Track.wrapDelta(r.s - player.s)
					local dd = r.d - player.d
					local lengthSum = (player.length + r.length) / 2 * 0.92
					local widthSum = (player.width + r.width) / 2 * 0.92
					if math.abs(ds) < lengthSum and math.abs(dd) < widthSum then
						local push = widthSum - math.abs(dd)
						local dir = if dd > 0.05 then 1 elseif dd < -0.05 then -1 else (if rng:NextNumber() < 0.5 then 1 else -1)
						local playerLimit = half - player.width / 2
						local rivalLimit = half - r.width / 2
						player.d = math.clamp(player.d - dir * push * 0.6, -playerLimit, playerLimit)
						r.d = math.clamp(r.d + dir * push * 0.4, -rivalLimit, rivalLimit)
						if r.bumpCooldown <= 0 then
							r.bumpCooldown = 0.35
							if ds > 0 then
								player.speed *= 0.93 -- the car behind loses a little speed
							else
								r.speed *= 0.93
							end
							if onBump then
								onBump((player.cf.Position + r.cf.Position) / 2)
							end
						end
					end
				end
			end
		end

		for _, car in all do
			place(car, dt, cameraPosition)
		end
		-- lap wrap safety: keep s finite and sane (the scene ends long before one lap + grid)
		if player.s > lap * 3 then
			player.s -= lap
		end
	end

	-- Position of the player's car body (for camera / sounds).
	function race.playerPosition(): Vector3
		return player.cf.Position
	end

	function race.destroy()
		folder:Destroy()
	end

	-- Looping engine sound that follows the car's speed (nil when the sound is off).
	local engineSound: Sound? = SoundFx.attach(player.root, "raceEngine")
	function race.updateEngine()
		local s = engineSound
		if s then
			s.PlaybackSpeed = 0.7 + math.clamp(player.speed / Config.MAX_SPEED, 0, 1.3) * 0.9
		end
	end
	function race.stopEngine()
		SoundFx.release(engineSound)
		engineSound = nil
	end

	return race
end

return RaceCars
