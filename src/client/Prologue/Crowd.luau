--!strict
-- The audience: simple people (body + head + one arm, a few with a sign) standing on the stand seats.
-- Everything is Anchored and moved with one Workspace:BulkMoveTo per update; only people near the camera animate.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config: any = require(Shared:WaitForChild("Config"):WaitForChild("Prologue") :: ModuleScript)

local Crowd = {}

type Seat = { cf: CFrame, fill: number }

type Person = {
	base: CFrame,
	gaspBase: CFrame?,
	body: Part,
	head: Part,
	arm: Part,
	sign: Part?,
	phase: number,
	waves: boolean, -- holds a sign / waves even when idle
}

local SHIRTS = {
	Color3.fromRGB(220, 50, 50),
	Color3.fromRGB(240, 190, 40),
	Color3.fromRGB(60, 120, 220),
	Color3.fromRGB(70, 180, 100),
	Color3.fromRGB(235, 235, 240),
	Color3.fromRGB(240, 120, 40),
	Color3.fromRGB(150, 80, 200),
	Color3.fromRGB(40, 40, 50),
	Color3.fromRGB(230, 110, 170),
	Color3.fromRGB(60, 190, 200),
}
local SKINS = {
	Color3.fromRGB(255, 219, 172),
	Color3.fromRGB(241, 194, 125),
	Color3.fromRGB(224, 172, 105),
	Color3.fromRGB(198, 134, 66),
	Color3.fromRGB(141, 85, 36),
	Color3.fromRGB(94, 60, 30),
}
local SIGNS = {
	Color3.fromRGB(255, 220, 40),
	Color3.fromRGB(255, 80, 120),
	Color3.fromRGB(80, 220, 255),
	Color3.fromRGB(120, 255, 120),
}

local YIELD_EVERY = 300
local ARM_LENGTH = 1.7

local rng = Random.new()

local function makePart(parent: Instance, name: string, size: Vector3, color: Color3, cf: CFrame, ball: boolean): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	if ball then
		p.Shape = Enum.PartType.Ball
	end
	p.Color = color
	p.Size = size
	p.CFrame = cf
	p.Parent = parent
	return p
end

-- Creates the crowd on the best `count` seats (weighted by each seat's fill). Yields while building.
function Crowd.new(seats: { Seat }, parent: Instance, count: number): any
	local folder = Instance.new("Folder")
	folder.Name = "Crowd"
	folder.Parent = parent

	-- weighted pick without replacement: sort by random / fill
	local keyed: { { key: number, seat: Seat } } = {}
	for _, seat in seats do
		table.insert(keyed, { key = rng:NextNumber() / math.max(seat.fill, 0.05), seat = seat })
	end
	table.sort(keyed, function(a, b)
		return a.key < b.key
	end)

	local people: { Person } = {}
	local made = 0
	for _, entry in keyed do
		if #people >= count then
			break
		end
		local base = entry.seat.cf
		local shirt = SHIRTS[rng:NextInteger(1, #SHIRTS)]
		local skin = SKINS[rng:NextInteger(1, #SKINS)]
		local body = makePart(folder, "Body", Vector3.new(1.6, 2.2, 1), shirt, base * CFrame.new(0, 1.1, 0), false)
		local head = makePart(folder, "Head", Vector3.new(1.2, 1.2, 1.2), skin, base * CFrame.new(0, 2.8, 0), true)
		local arm = makePart(
			folder,
			"Arm",
			Vector3.new(0.5, ARM_LENGTH, 0.5),
			skin,
			base * CFrame.new(1.05, 1.15, 0),
			false
		)
		local waves = rng:NextNumber() < Config.CROWD_FLAG_RATIO
		local sign: Part? = nil
		if waves then
			sign = makePart(
				folder,
				"Sign",
				Vector3.new(0.15, 1.3, 1.8),
				SIGNS[rng:NextInteger(1, #SIGNS)],
				base * CFrame.new(1.05, 3.3, 0),
				false
			)
		end
		table.insert(people, {
			base = base,
			gaspBase = nil,
			body = body,
			head = head,
			arm = arm,
			sign = sign,
			phase = rng:NextNumber() * math.pi * 2,
			waves = waves,
		})
		made += 1
		if made % (YIELD_EVERY // 3) == 0 then
			task.wait()
		end
	end

	local crowd: any = {}
	local cheerUntil = 0
	local gasping = false
	local accumulator = 0
	local cullSq: number = Config.CROWD_CULL * Config.CROWD_CULL
	local interval = 1 / Config.CROWD_UPDATE_HZ

	crowd.count = #people

	-- Cheer (jump and wave) for `seconds`.
	function crowd.cheer(seconds: number)
		if gasping then
			return
		end
		cheerUntil = math.max(cheerUntil, os.clock() + seconds)
	end

	-- Everyone stops bouncing and turns to `focus`, leaning forward.
	function crowd.gasp(focus: Vector3)
		gasping = true
		for _, person in people do
			local pos = person.base.Position
			local target = Vector3.new(focus.X, pos.Y, focus.Z)
			if (target - pos).Magnitude > 0.5 then
				person.gaspBase = CFrame.lookAt(pos, target)
			else
				person.gaspBase = person.base
			end
		end
	end

	function crowd.update(dt: number, cameraPosition: Vector3)
		accumulator += dt
		if accumulator < interval then
			return
		end
		accumulator = 0
		local t = os.clock()
		local mode = if gasping then "gasp" elseif t < cheerUntil then "cheer" else "idle"

		local parts: { Instance } = {}
		local frames: { CFrame } = {}
		local n = 0
		for _, person in people do
			local basePos = person.base.Position
			local dx = basePos.X - cameraPosition.X
			local dy = basePos.Y - cameraPosition.Y
			local dz = basePos.Z - cameraPosition.Z
			if dx * dx + dy * dy + dz * dz < cullSq then
				local phase = person.phase
				local lift = 0
				local lean = 0
				local armAngle = 0.15
				local frame = person.base
				if mode == "idle" then
					lift = (math.sin(t * 2.2 + phase) * 0.5 + 0.5) * 0.18
					if person.waves then
						armAngle = 2.8 + math.sin(t * 4 + phase) * 0.4
					else
						armAngle = 0.15 + math.sin(t * 1.5 + phase) * 0.08
					end
				elseif mode == "cheer" then
					lift = math.abs(math.sin(t * 7 + phase)) * 1.5
					armAngle = math.pi + math.sin(t * 9 + phase) * 0.45
				else
					frame = person.gaspBase or person.base
					lean = 0.28
					armAngle = 2.4
				end
				local posed = frame * CFrame.new(0, lift, 0) * CFrame.Angles(-lean, 0, 0)
				local shoulder = posed * CFrame.new(1.05, 2.0, 0) * CFrame.Angles(0, 0, armAngle)

				parts[n + 1] = person.body
				frames[n + 1] = posed * CFrame.new(0, 1.1, 0)
				parts[n + 2] = person.head
				frames[n + 2] = posed * CFrame.new(0, 2.8, 0)
				parts[n + 3] = person.arm
				frames[n + 3] = shoulder * CFrame.new(0, -ARM_LENGTH / 2, 0)
				n += 3
				local sign = person.sign
				if sign then
					parts[n + 1] = sign
					frames[n + 1] = shoulder * CFrame.new(0, -ARM_LENGTH - 0.6, 0)
					n += 1
				end
			end
		end
		if n > 0 then
			Workspace:BulkMoveTo(parts :: any, frames :: any, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end

	function crowd.destroy()
		folder:Destroy()
		table.clear(people)
	end

	return crowd
end

return Crowd
