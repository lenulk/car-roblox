--!strict
-- Builds the whole stadium (road, kerbs, fences, stands, start gantry, boards, lamps) inside ONE folder
-- "PrologueArena" under workspace. Destroying that folder removes everything. Yields every few hundred parts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config: any = require(Shared:WaitForChild("Config"):WaitForChild("Prologue") :: ModuleScript)
local Track: any = require((script.Parent :: Instance):WaitForChild("Track") :: ModuleScript)

local ArenaBuilder = {}

export type Seat = { cf: CFrame, fill: number }

export type Arena = {
	folder: Folder,
	seats: { Seat },
	partCount: number,
	setLights: (lit: number, color: Color3?) -> (),
	confetti: () -> (),
	destroy: () -> (),
}

local YIELD_EVERY = 250

local ROAD_COLOR = Color3.fromRGB(52, 54, 60)
local GRASS_COLOR = Color3.fromRGB(70, 140, 62)
local WHITE = Color3.fromRGB(240, 240, 244)
local RED = Color3.fromRGB(210, 36, 40)
local DARK = Color3.fromRGB(24, 24, 28)
local LIGHT_OFF = Color3.fromRGB(60, 22, 22)
local LIGHT_RED = Color3.fromRGB(255, 30, 30)
local LIGHT_GREEN = Color3.fromRGB(60, 255, 90)

local SPONSORS = { "TURBO", "NITRO", "GT GARAGE", "OCTANE", "APEX", "VELOCITY", "ROADKING", "PISTON" }
local BOARD_COLORS = {
	Color3.fromRGB(250, 200, 40),
	Color3.fromRGB(60, 140, 240),
	Color3.fromRGB(240, 90, 40),
	Color3.fromRGB(245, 245, 250),
	Color3.fromRGB(80, 200, 120),
	Color3.fromRGB(220, 60, 120),
}

function ArenaBuilder.build(): Arena
	local half: number = Track.halfWidth
	local count: number = Track.count
	local lap: number = Track.length
	local partCount = 0

	local folder = Instance.new("Folder")
	folder.Name = "PrologueArena"

	local function sub(name: string): Folder
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = folder
		return f
	end

	local function newPart(
		parent: Instance,
		name: string,
		size: Vector3,
		cf: CFrame,
		color: Color3,
		material: Enum.Material?
	): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Material = material or Enum.Material.SmoothPlastic
		p.Color = color
		p.Size = size
		p.CFrame = cf
		p.Parent = parent
		partCount += 1
		if partCount % YIELD_EVERY == 0 then
			task.wait()
		end
		return p
	end

	folder.Parent = Workspace

	local ground = sub("Ground")
	local road = sub("Road")
	local fences = sub("Fences")
	local standsFolder = sub("Stands")
	local props = sub("Props")

	----------------------------------------------------------------------------------------------
	-- Ground plate
	----------------------------------------------------------------------------------------------
	local boundsMin, boundsMax = Track.bounds()
	local margin = 400 -- a Part can be at most 2048 studs wide
	local groundSize = Vector3.new(boundsMax.X - boundsMin.X + margin * 2, 1, boundsMax.Z - boundsMin.Z + margin * 2)
	local groundCenter = (boundsMin + boundsMax) / 2 + Vector3.new(0, -0.56, 0)
	newPart(ground, "Grass", groundSize, CFrame.new(groundCenter), GRASS_COLOR, Enum.Material.Grass)

	----------------------------------------------------------------------------------------------
	-- Road, kerbs, edge lines, tyre walls, fences
	----------------------------------------------------------------------------------------------
	local kerbRadiusLimit = 1 / 300
	local isBend: { boolean } = {}
	for i = 1, count do
		isBend[i] = math.abs(Track.curvatureAtIndex(i)) > kerbRadiusLimit
	end

	for i = 1, count do
		local chord: number = Track.chordLength(i)
		local cf = Track.segmentFrame(i, 0) * CFrame.new(0, -0.5 + (i % 3) * 0.004, 0)
		newPart(road, "Road", Vector3.new(half * 2, 1, chord + 8), cf, ROAD_COLOR, Enum.Material.Asphalt)

		if isBend[i] then
			local kerbColor = if i % 2 == 0 then RED else WHITE
			for _, side in { -1, 1 } do
				local kerbCf = Track.segmentFrame(i, side * (half - 1.25)) * CFrame.new(0, 0.07, 0)
				newPart(road, "Kerb", Vector3.new(2.5, 0.14, chord + 0.6), kerbCf, kerbColor)
			end
		elseif i % 2 == 0 then
			for _, side in { -1, 1 } do
				local lineCf = Track.segmentFrame(i, side * (half - 2.6)) * CFrame.new(0, 0.04, 0)
				newPart(road, "EdgeLine", Vector3.new(0.7, 0.08, chord * 0.6), lineCf, WHITE)
			end
		end

		-- tyre wall on the outside of every other bend segment
		if isBend[i] and i % 2 == 1 then
			local outer = if Track.curvatureAtIndex(i) > 0 then -1 else 1
			local wallCf = Track.segmentFrame(i, outer * (half + 6)) * CFrame.new(0, 1.2, 0)
			local wallColor = if (i // 2) % 2 == 0 then RED else WHITE
			newPart(fences, "TyreWall", Vector3.new(2.4, 2.4, chord + 0.8), wallCf, wallColor, Enum.Material.Slate)
		end
	end

	-- fences (one long part per two segments, both sides)
	for i = 1, count, 2 do
		for _, side in { -1, 1 } do
			local offset = side * (half + 12)
			local pa: Vector3 = Track.pointAtIndex(i, offset)
			local pb: Vector3 = Track.pointAtIndex(i + 2, offset)
			local length = (pb - pa).Magnitude
			if length > 0.5 then
				local mid = (pa + pb) / 2 + Vector3.new(0, 1.7, 0)
				local color = if (i // 2) % 2 == 0 then Color3.fromRGB(40, 70, 150) else WHITE
				newPart(fences, "Fence", Vector3.new(0.8, 3.4, length + 0.6), CFrame.lookAt(mid, mid + (pb - pa)), color)
			end
		end
	end

	----------------------------------------------------------------------------------------------
	-- Start line, grid boxes
	----------------------------------------------------------------------------------------------
	local startFrame: CFrame = Track.cframeAt(0, 0)
	newPart(road, "StartLine", Vector3.new(half * 2, 0.1, 4), startFrame * CFrame.new(0, 0.05, 0), WHITE)
	local cells = math.floor(half * 2 / 2)
	for col = 0, cells - 1 do
		for row = 0, 1 do
			if (col + row) % 2 == 0 then
				local x = -half + 1 + col * 2
				newPart(
					road,
					"Checker",
					Vector3.new(2, 0.12, 2),
					startFrame * CFrame.new(x, 0.06, -1 + row * 2),
					DARK
				)
			end
		end
	end
	for slot = 1, Config.GRID_SLOTS do
		local s, d = Track.gridSlot(slot)
		local boxCf: CFrame = Track.cframeAt(s - 8.5, d)
		newPart(road, "GridBar", Vector3.new(9, 0.1, 0.8), boxCf * CFrame.new(0, 0.05, 0), WHITE)
	end

	----------------------------------------------------------------------------------------------
	-- Start gantry with three lights
	----------------------------------------------------------------------------------------------
	local gantryHalf = half + 3
	local lights: { Part } = {}
	local lightSources: { PointLight } = {}
	local confettiEmitters: { ParticleEmitter } = {}

	for _, side in { -1, 1 } do
		local pillar = newPart(
			props,
			"GantryPillar",
			Vector3.new(2, 19, 2),
			startFrame * CFrame.new(side * gantryHalf, 9.5, 0),
			DARK,
			Enum.Material.Metal
		)
		local attachment = Instance.new("Attachment")
		attachment.Position = Vector3.new(0, 10, 0)
		attachment.Parent = pillar
		local emitter = Instance.new("ParticleEmitter")
		emitter.Enabled = false
		emitter.Rate = 0
		emitter.Lifetime = NumberRange.new(2.2, 3.4)
		emitter.Speed = NumberRange.new(25, 45)
		emitter.SpreadAngle = Vector2.new(55, 55)
		emitter.Acceleration = Vector3.new(0, -22, 0)
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-240, 240)
		emitter.Size = NumberSequence.new(0.9, 0.6)
		emitter.LightEmission = 0.4
		emitter.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
			ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 220, 60)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 220, 120)),
			ColorSequenceKeypoint.new(0.75, Color3.fromRGB(80, 160, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(230, 90, 220)),
		})
		emitter.Parent = attachment
		table.insert(confettiEmitters, emitter)
	end
	newPart(
		props,
		"GantryBeam",
		Vector3.new(gantryHalf * 2 + 2, 3, 3),
		startFrame * CFrame.new(0, 19.5, 0),
		DARK,
		Enum.Material.Metal
	)
	newPart(props, "LightBoard", Vector3.new(18, 5.4, 1), startFrame * CFrame.new(0, 15.3, 0), DARK)
	for i = 1, 3 do
		local x = (i - 2) * 5
		local ball = newPart(props, "StartLight", Vector3.new(3.6, 3.6, 3.6), startFrame * CFrame.new(x, 15.3, 1.1), LIGHT_OFF)
		ball.Shape = Enum.PartType.Ball
		local glow = Instance.new("PointLight")
		glow.Range = 40
		glow.Brightness = 3
		glow.Enabled = false
		glow.Parent = ball
		table.insert(lights, ball)
		table.insert(lightSources, glow)
	end

	----------------------------------------------------------------------------------------------
	-- Stands (also produce the seats for the crowd)
	----------------------------------------------------------------------------------------------
	local seats: { Seat } = {}
	local rows: number = Config.STAND_ROWS
	local riser: number = Config.STAND_RISER
	local depth: number = Config.STAND_DEPTH
	local gap: number = Config.STAND_GAP
	local standDepth = rows * depth

	for _, spec in Config.STANDS do
		local fromS: number = spec.from * lap
		local toS: number = spec.to * lap
		local chunk: number = spec.chunk
		local side: number = spec.side
		if side == 0 then
			side = if Track.averageCurvature(fromS, toS) > 0 then -1 else 1
		end
		local standColors = { Color3.fromRGB(150, 154, 164), Color3.fromRGB(128, 132, 144) }

		local s = fromS + chunk / 2
		local chunkIndex = 0
		while s < toS do
			chunkIndex += 1
			local base: CFrame = Track.cframeAt(s, 0)
			local centre: Vector3 = (base * CFrame.new(side * (half + gap + standDepth / 2), 0, 0)).Position
			-- skip chunks that would run into another part of the circuit
			if Track.clearance(centre, s, 160) > standDepth / 2 + chunk / 2 + 20 then
				for k = 0, rows - 1 do
					local xFront = half + gap + k * depth
					local height = (k + 1) * riser
					local rowCf = base * CFrame.new(side * (xFront + depth / 2), height / 2, 0)
					newPart(
						standsFolder,
						"Row",
						Vector3.new(depth, height, chunk + 8),
						rowCf,
						standColors[(k % 2) + 1],
						Enum.Material.Concrete
					)
					-- seats on top of the row
					local z = -chunk / 2 + Config.SEAT_SPACING / 2
					while z < chunk / 2 do
						local seatPos = (base * CFrame.new(side * (xFront + depth / 2), height, z)).Position
						local facing = -side * base.RightVector
						table.insert(seats, { cf = CFrame.lookAt(seatPos, seatPos + facing), fill = spec.fill })
						z += Config.SEAT_SPACING
					end
				end
				local wallHeight = rows * riser + 5
				newPart(
					standsFolder,
					"BackWall",
					Vector3.new(1, wallHeight, chunk + 8),
					base * CFrame.new(side * (half + gap + standDepth + 0.5), wallHeight / 2, 0),
					Color3.fromRGB(70, 74, 88)
				)
				if spec.roof then
					local roofHeight = rows * riser + 9.5
					newPart(
						standsFolder,
						"Roof",
						Vector3.new(standDepth + 5, 0.8, chunk + 8),
						base * CFrame.new(side * (half + gap + standDepth / 2 + 1.5), roofHeight, 0),
						Color3.fromRGB(200, 60, 56)
					)
					newPart(
						standsFolder,
						"RoofPost",
						Vector3.new(0.8, roofHeight, 0.8),
						base * CFrame.new(side * (half + gap - 0.6), roofHeight / 2, 0),
						Color3.fromRGB(70, 74, 88)
					)
				end
			end
			s += chunk
		end
	end

	----------------------------------------------------------------------------------------------
	-- Sponsor boards along the main straight, lamp poles in the infield
	----------------------------------------------------------------------------------------------
	local boardIndex = 0
	local boardS = -lap * 0.035
	while boardS < lap * 0.09 do
		boardIndex += 1
		local side = if boardIndex % 2 == 0 then 1 else -1
		local boardCf: CFrame = Track.cframeAt(boardS, side * (half + 11.3)) * CFrame.new(0, 2.3, 0)
		local board = newPart(
			props,
			"Board",
			Vector3.new(0.3, 2.6, 16),
			boardCf,
			BOARD_COLORS[(boardIndex % #BOARD_COLORS) + 1]
		)
		local gui = Instance.new("SurfaceGui")
		gui.Face = if side == 1 then Enum.NormalId.Left else Enum.NormalId.Right
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 24
		gui.LightInfluence = 0
		gui.Parent = board
		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.Size = UDim2.fromScale(1, 1)
		text.Font = Enum.Font.GothamBlack
		text.TextScaled = true
		text.TextColor3 = DARK
		text.Text = SPONSORS[(boardIndex % #SPONSORS) + 1]
		text.Parent = gui
		boardS += 36
	end

	for i = 0, 7 do
		local sLamp = -lap * 0.03 + i * 95
		local lampCf: CFrame = Track.cframeAt(sLamp, half + 80)
		newPart(props, "LampPole", Vector3.new(0.8, 24, 0.8), lampCf * CFrame.new(0, 12, 0), DARK, Enum.Material.Metal)
		local head = newPart(props, "LampHead", Vector3.new(5, 0.8, 2.6), lampCf * CFrame.new(0, 24.4, 0), WHITE)
		local lamp = Instance.new("PointLight")
		lamp.Range = 60
		lamp.Brightness = 0.8
		lamp.Parent = head
	end

	----------------------------------------------------------------------------------------------
	-- API
	----------------------------------------------------------------------------------------------
	local arena: Arena = {
		folder = folder,
		seats = seats,
		partCount = partCount,
		setLights = function(lit: number, color: Color3?)
			for i, ball in lights do
				local on = i <= lit
				ball.Color = if on then (color or LIGHT_RED) else LIGHT_OFF
				ball.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
				lightSources[i].Enabled = on
				lightSources[i].Color = color or LIGHT_RED
			end
		end,
		confetti = function()
			for _, emitter in confettiEmitters do
				emitter:Emit(90)
			end
		end,
		destroy = function()
			folder:Destroy()
		end,
	}
	return arena
end

ArenaBuilder.LIGHT_RED = LIGHT_RED
ArenaBuilder.LIGHT_GREEN = LIGHT_GREEN

return ArenaBuilder
