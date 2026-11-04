--!strict
-- Animates the storefront decorations (server models from DecorModels, tag "DecorModel").
-- The server only builds anchored parts and marks the moving ones with attributes:
--   Anim (role) / AnimIdx / AnimPivot (world position to rotate around) / OnColor (lit colour of blinking parts).
-- Everything here runs on the client, at 30 Hz, and only for models within ~200 studs of the camera.
-- Burst effects: bear confetti + jump when a repair finishes (Effect "Repair"), fireworks on every customer arrival
-- (the server bumps the model attribute "Arrivals"), dragon smoke puffs on a timer.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes: any = require(Shared:WaitForChild("Remotes") :: ModuleScript)
local Client = (script.Parent :: Instance).Parent :: Instance
local ClientState: any = require(Client:WaitForChild("ClientState") :: ModuleScript)

local DecorAnimator = {}

local TAG = "DecorModel"
local RANGE = 200 -- studs from the camera
local RATE = 30 -- Hz
local JUMP_SECONDS = 0.7
local JUMP_HEIGHT = 3.2
local PUFF_INTERVAL = 3.6

type Info = {
	part: BasePart,
	role: string,
	idx: number,
	rest: CFrame,
	pivot: Vector3?,
	onColor: Color3?,
	light: PointLight?,
	label: TextLabel?,
}

type Entry = {
	model: Model,
	id: string,
	plotIndex: number,
	infos: { Info },
	center: Vector3,
	right: Vector3,
	look: Vector3,
	-- per-model state
	jumpStart: number?,
	headYaw: number,
	lastPuff: number,
	lastArrivals: number,
	lastLaunch: number,
	confetti: ParticleEmitter?,
	puff: ParticleEmitter?,
	connection: RBXScriptConnection?,
}

local entries: { [Model]: Entry } = {}

----------------------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------------------

-- rotates a world CFrame around a world pivot point and axis
local function rotateAbout(rest: CFrame, pivot: Vector3, axis: Vector3, angle: number): CFrame
	return CFrame.new(pivot) * CFrame.fromAxisAngle(axis, angle) * CFrame.new(-pivot) * rest
end

local function planarAngle(v: Vector3): number
	return math.atan2(v.X, v.Z)
end

local function wrapAngle(a: number): number
	a = (a + math.pi) % (2 * math.pi) - math.pi
	return a
end

local function myPlot(): number?
	local snapshot: any = ClientState.snapshot
	if snapshot and type(snapshot.plotIndex) == "number" then
		return snapshot.plotIndex
	end
	return nil
end

----------------------------------------------------------------------------------------------------
-- Bursts
----------------------------------------------------------------------------------------------------

local ROCKET_COLORS = {
	Color3.fromRGB(255, 80, 80),
	Color3.fromRGB(255, 210, 70),
	Color3.fromRGB(90, 220, 140),
	Color3.fromRGB(90, 170, 255),
	Color3.fromRGB(230, 110, 255),
	Color3.fromRGB(255, 150, 60),
}

local function anchoredBall(position: Vector3, size: number, color: Color3, transparency: number): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = transparency
	p.Size = Vector3.new(size, size, size)
	p.Position = position
	p.Parent = Workspace
	return p
end

-- A small rocket from the launcher that bursts into sparks.
local function launchFirework(from: Vector3)
	local color = ROCKET_COLORS[math.random(1, #ROCKET_COLORS)]
	local rocket = anchoredBall(from, 0.7, Color3.fromRGB(255, 240, 200), 0)
	local trail = Instance.new("ParticleEmitter")
	trail.Rate = 70
	trail.Lifetime = NumberRange.new(0.3, 0.5)
	trail.Speed = NumberRange.new(1, 3)
	trail.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 120, 40))
	trail.LightEmission = 1
	trail.Parent = rocket

	local height = 26 + math.random() * 8
	local drift = Vector3.new((math.random() - 0.5) * 8, 0, (math.random() - 0.5) * 8)
	local target = from + Vector3.new(0, height, 0) + drift
	local tween = TweenService:Create(rocket, TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = target })
	tween.Completed:Connect(function()
		rocket:Destroy()
		local burst = anchoredBall(target, 0.2, color, 1)
		local emitter = Instance.new("ParticleEmitter")
		emitter.Rate = 0
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		emitter.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.5), color)
		emitter.LightEmission = 1
		emitter.LightInfluence = 0
		emitter.Lifetime = NumberRange.new(1.1, 1.7)
		emitter.Speed = NumberRange.new(18, 30)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Acceleration = Vector3.new(0, -10, 0)
		emitter.Drag = 2
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1), NumberSequenceKeypoint.new(1, 0) })
		emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
		emitter.Parent = burst
		emitter:Emit(70)
		Debris:AddItem(burst, 2.5)
	end)
	tween:Play()
	Debris:AddItem(rocket, 2)
end

----------------------------------------------------------------------------------------------------
-- Per-decoration animation (called at RATE Hz for models near the camera)
----------------------------------------------------------------------------------------------------

type Animator = (e: Entry, t: number, dt: number) -> ()

local ANIMATORS: { [string]: Animator } = {}

ANIMATORS.Bunting = function(e, t, _dt)
	for _, info in e.infos do
		if info.role == "Sway" and info.pivot then
			info.part.CFrame = rotateAbout(info.rest, info.pivot, e.right, 0.2 * math.sin(t * 2 + info.idx * 0.9))
		end
	end
end

ANIMATORS.OpenSign = function(e, t, _dt)
	-- steady glow with a short double flicker every few seconds
	local phase = (t * 1.2) % 6
	local lit = not ((phase >= 4.6 and phase < 5.0) or (phase >= 5.2 and phase < 5.5))
	for _, info in e.infos do
		local on = info.onColor
		if on then
			local color = if lit then on else on:Lerp(Color3.new(0, 0, 0), 0.9)
			if info.role == "OpenNeon" then
				info.part.Color = color
				if info.light then
					info.light.Brightness = if lit then 1 else 0
				end
			elseif info.label then
				info.label.TextColor3 = color
			end
		end
	end
end

ANIMATORS.TubeMan = function(e, t, _dt)
	local function offset(i: number): Vector3
		local k = (i / 7) ^ 1.4
		local angle = t * 3.4 + i * 0.75
		return e.right * (math.sin(angle) * 1.5 * k) + e.look * (math.cos(angle * 0.8) * 1.0 * k)
	end
	for _, info in e.infos do
		if info.role == "TubeSeg" then
			info.part.CFrame = info.rest + offset(info.idx)
		elseif info.role == "TubeHead" then
			info.part.CFrame = info.rest + offset(7.6)
		elseif info.role == "TubeArm" and info.pivot then
			-- idx is the side (-1 / +1): the arms flail up and down, one a bit behind the other
			local angle = 0.7 * math.sin(t * 6.5 + (if info.idx > 0 then 0 else 1.9))
			info.part.CFrame = rotateAbout(info.rest, info.pivot, e.look, angle * -info.idx) + offset(6.6)
		end
	end
end

ANIMATORS.Searchlight = function(e, t, _dt)
	local angle = t * 0.7
	for _, info in e.infos do
		if info.role == "SearchHead" and info.pivot then
			info.part.CFrame = rotateAbout(info.rest, info.pivot, Vector3.yAxis, angle)
		end
	end
end

ANIMATORS.MascotBear = function(e, t, _dt)
	local jump = 0
	if e.jumpStart then
		local u = (t - e.jumpStart) / JUMP_SECONDS
		if u >= 1 then
			e.jumpStart = nil
		else
			jump = JUMP_HEIGHT * 4 * u * (1 - u)
		end
	end
	local offset = Vector3.new(0, jump + 0.12 * math.abs(math.sin(t * 2.2)), 0)
	local waving = if e.jumpStart then 1.1 else 0.45 -- wave harder while celebrating
	for _, info in e.infos do
		if info.role == "BearBody" then
			info.part.CFrame = info.rest + offset
		elseif info.role == "BearArm" and info.pivot then
			info.part.CFrame = rotateAbout(info.rest, info.pivot, e.look, waving * math.sin(t * 5)) + offset
		end
	end
end

-- nearest customer car of this plot that is arriving (else waiting in the queue)
local function nearestCustomer(plotIndex: number, from: Vector3): Vector3?
	local folder = Workspace:FindFirstChild("CustomerCars")
	if not folder then
		return nil
	end
	local best: Vector3? = nil
	local bestScore = math.huge
	for _, car in folder:GetChildren() do
		if car:IsA("Model") and car:GetAttribute("PlotIndex") == plotIndex then
			local state = car:GetAttribute("State")
			if state == "Arriving" or state == "Queued" then
				local position = car:GetPivot().Position
				local score = (position - from).Magnitude + (if state == "Queued" then 60 else 0)
				if score < bestScore then
					bestScore = score
					best = position
				end
			end
		end
	end
	return best
end

ANIMATORS.MechRobot = function(e, t, dt)
	local headPosition = e.center + Vector3.new(0, 13, 0)
	local target = 0.5 * math.sin(t * 0.6) -- idle scan
	local car = nearestCustomer(e.plotIndex, headPosition)
	if car then
		local planar = Vector3.new(car.X - headPosition.X, 0, car.Z - headPosition.Z)
		if planar.Magnitude > 0.5 then
			target = math.clamp(wrapAngle(planarAngle(planar) - planarAngle(e.look)), -1.3, 1.3)
		end
	end
	e.headYaw += (target - e.headYaw) * math.min(1, dt * 6)
	for _, info in e.infos do
		if info.role == "RobotHead" and info.pivot then
			info.part.CFrame = rotateAbout(info.rest, info.pivot, Vector3.yAxis, e.headYaw)
		elseif info.role == "Wrench" and info.pivot then
			info.part.CFrame = rotateAbout(info.rest, info.pivot, e.look, 0.1 * math.sin(t * 1.5))
		end
	end
end

ANIMATORS.NeonDragon = function(e, t, _dt)
	local color = Color3.fromHSV((t * 0.06) % 1, 0.9, 1)
	local breathe = math.sin(t * 1.8)
	local flap = math.sin(t * 1.6)
	for _, info in e.infos do
		local role = info.role
		if role == "DragonWing" or role == "DragonWingGlow" then
			-- wings ride the shoulders (weight 8) and flap around the body's forward axis, mirrored per side
			local lift = Vector3.new(0, 0.3 * breathe * 0.8, 0)
			local cf = info.rest + lift
			if info.pivot then
				local side = if info.idx < 0 then -1 else 1
				cf = rotateAbout(cf, info.pivot + lift, e.look, side * 0.22 * flap)
			end
			info.part.CFrame = cf
			if role == "DragonWingGlow" then
				info.part.Color = color
			end
		else
			-- gentle breathing that grows from the coiled tail (0) to the head (10)
			info.part.CFrame = info.rest + Vector3.new(0, 0.3 * breathe * math.clamp(info.idx / 10, 0, 1), 0)
			if role == "DragonNeon" then
				info.part.Color = color
				if info.light then
					info.light.Color = color
				end
			end
		end
	end
	if e.puff and t - e.lastPuff >= PUFF_INTERVAL then
		e.lastPuff = t
		e.puff:Emit(8)
	end
end

ANIMATORS.GoldStatue = function(e, t, _dt)
	local angle = t * 0.9
	for _, info in e.infos do
		if info.role == "Spin" and info.pivot then
			info.part.CFrame = rotateAbout(info.rest, info.pivot, Vector3.yAxis, angle)
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Registration
----------------------------------------------------------------------------------------------------

local function register(model: Model)
	if entries[model] then
		return
	end
	local id = model:GetAttribute("Decor")
	local pivotPart = model.PrimaryPart
	if type(id) ~= "string" or not pivotPart then
		return
	end
	local frame = model:GetPivot()
	local entry: Entry = {
		model = model,
		id = id,
		plotIndex = (model:GetAttribute("PlotIndex") :: any) or 0,
		infos = {},
		center = frame.Position,
		right = frame.RightVector,
		look = frame.LookVector,
		jumpStart = nil,
		headYaw = 0,
		lastPuff = os.clock() + math.random() * PUFF_INTERVAL,
		lastArrivals = (model:GetAttribute("Arrivals") :: any) or 0,
		lastLaunch = 0,
		confetti = nil,
		puff = nil,
		connection = nil,
	}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local role = d:GetAttribute("Anim")
			if type(role) == "string" then
				local pivot = d:GetAttribute("AnimPivot")
				local onColor = d:GetAttribute("OnColor")
				local idx = d:GetAttribute("AnimIdx")
				local gui = d:FindFirstChild("SignGui")
				local label = if gui then gui:FindFirstChild("Text") else nil
				table.insert(entry.infos, {
					part = d,
					role = role,
					idx = if type(idx) == "number" then idx else 0,
					rest = d.CFrame,
					pivot = if typeof(pivot) == "Vector3" then pivot else nil,
					onColor = if typeof(onColor) == "Color3" then onColor else nil,
					light = d:FindFirstChildWhichIsA("PointLight"),
					label = if label and label:IsA("TextLabel") then label else nil,
				})
			end
			if d.Name == "Cap" then
				local confetti = d:FindFirstChild("Confetti")
				if confetti and confetti:IsA("ParticleEmitter") then
					entry.confetti = confetti
				end
			elseif d.Name == "Nose" then
				local puff = d:FindFirstChild("Puff")
				if puff and puff:IsA("ParticleEmitter") then
					entry.puff = puff
				end
			end
		end
	end
	if id == "Fireworks" then
		entry.connection = model:GetAttributeChangedSignal("Arrivals"):Connect(function()
			local arrivals = model:GetAttribute("Arrivals")
			if type(arrivals) ~= "number" or arrivals <= entry.lastArrivals then
				return
			end
			entry.lastArrivals = arrivals
			local camera = Workspace.CurrentCamera
			if not camera or (camera.CFrame.Position - entry.center).Magnitude > RANGE then
				return
			end
			local now = os.clock()
			if now - entry.lastLaunch < 0.4 then
				return
			end
			entry.lastLaunch = now
			for _, info in entry.infos do
				if info.role == "Launch" then
					launchFirework(info.part.Position)
					break
				end
			end
		end)
	end
	entries[model] = entry
end

local function unregister(model: Model)
	local entry = entries[model]
	if entry then
		if entry.connection then
			entry.connection:Disconnect()
		end
		entries[model] = nil
	end
end

function DecorAnimator.start()
	local function onTagged(inst: Instance)
		if not inst:IsA("Model") then
			return
		end
		local model = inst
		task.spawn(function()
			-- the server builds the model completely before parenting it; the wait only guards against odd replication
			for _ = 1, 20 do
				if model.Parent == nil then
					return
				end
				if model.PrimaryPart then
					break
				end
				task.wait(0.1)
			end
			register(model)
		end)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(onTagged)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(inst)
		if inst:IsA("Model") then
			unregister(inst)
		end
	end)
	for _, inst in CollectionService:GetTagged(TAG) do
		onTagged(inst)
	end

	-- a finished repair makes the bear on my plot jump for joy and throw confetti
	Remotes.get("Effect").OnClientEvent:Connect(function(effect: any)
		if effect ~= "Repair" then
			return
		end
		local plot = myPlot()
		for _, entry in entries do
			if entry.id == "MascotBear" and entry.plotIndex == plot then
				entry.jumpStart = os.clock()
				if entry.confetti then
					entry.confetti:Emit(45)
				end
			end
		end
	end)

	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated < 1 / RATE then
			return
		end
		local step = accumulated
		accumulated = 0
		if next(entries) == nil then
			return
		end
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local origin = camera.CFrame.Position
		local t = os.clock()
		for model, entry in entries do
			if model.Parent == nil then
				unregister(model)
			elseif (entry.center - origin).Magnitude <= RANGE then
				local animator = ANIMATORS[entry.id]
				if animator then
					animator(entry, t, step)
				end
			end
		end
	end)
end

return DecorAnimator
