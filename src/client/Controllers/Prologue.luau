--!strict
-- Opening scene for new players: a stadium race the player drives (as last on the grid), the engine blows in the
-- final corner, story cards, then back to the garage. Built, simulated and cleaned up on this client only.
-- Modules live in src/client/Prologue/ (Track, ArenaBuilder, Crowd, RaceCars, PrologueUI); tunables in Config/Prologue.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config: any = require(Shared:WaitForChild("Config"):WaitForChild("Prologue") :: ModuleScript)
local Remotes: any = require(Shared:WaitForChild("Remotes") :: ModuleScript)
local SoundFx: any = require(Shared:WaitForChild("SoundFx") :: ModuleScript)

local Controllers = script.Parent :: Instance
local Client = Controllers.Parent :: Instance
local ClientState: any = require(Client:WaitForChild("ClientState") :: ModuleScript)
local Music: any = require(Controllers:WaitForChild("Music") :: ModuleScript)

local PrologueFolder = Client:WaitForChild("Prologue")
local Track: any = require(PrologueFolder:WaitForChild("Track") :: ModuleScript)
local ArenaBuilder: any = require(PrologueFolder:WaitForChild("ArenaBuilder") :: ModuleScript)
local Crowd: any = require(PrologueFolder:WaitForChild("Crowd") :: ModuleScript)
local RaceCars: any = require(PrologueFolder:WaitForChild("RaceCars") :: ModuleScript)
local PrologueUI: any = require(PrologueFolder:WaitForChild("PrologueUI") :: ModuleScript)

local LocalPlayer = Players.LocalPlayer

local Prologue = {}

local STORY_KEYS = { "prologue_story1", "prologue_story2", "prologue_story3" }

-- Waits for the first snapshot (nil on timeout).
local function waitForSnapshot(timeout: number): any?
	if ClientState.snapshot ~= nil then
		return ClientState.snapshot
	end
	local result: any = nil
	local connection = ClientState.onChanged(function(snapshot: any)
		result = snapshot
	end)
	local t0 = os.clock()
	while result == nil and os.clock() - t0 < timeout do
		task.wait(0.1)
	end
	connection:Disconnect()
	return result
end

local function smooth(t: number): number
	local x = math.clamp(t, 0, 1)
	return x * x * (3 - 2 * x)
end

-- Plays the whole scene. `ui` already exists and covers the screen in black.
local function runScene(ui: any)
	while Workspace.CurrentCamera == nil do
		task.wait()
	end
	local camera = Workspace.CurrentCamera :: Camera
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")

	local skipped = false -- skip pressed before the story
	local skipStory = false -- skip pressed during the story
	local finished = false -- scene torn down, frame loop must stop
	local restored = false
	local phase = "loading" -- loading | intro | countdown | race | blown | story

	local arena: any = nil
	local crowd: any = nil
	local race: any = nil
	local frameConnection: RBXScriptConnection? = nil
	local crowdLoop: Sound? = nil

	local camMode = "intro"
	local camCF = camera.CFrame
	local introStart = 0
	local introCams: { Vector3 } = {}
	local introLooks: { Vector3 } = {}
	local orbitAngle: number? = nil

	local raceStart = 0
	local smoking = false
	local smokeForced = false
	local smokeStart = 0
	local lastRank = 7
	local hasLed = false
	local lastComment = 0

	----------------------------------------------------------------------------------------------
	-- Player / GUI / camera / music preparation (all reverted by restorePlayer)
	----------------------------------------------------------------------------------------------
	local guiState: { [ScreenGui]: { wanted: boolean, conn: RBXScriptConnection? } } = {}
	local guiAddedConnection: RBXScriptConnection? = nil
	local characterConnection: RBXScriptConnection? = nil
	local musicConnection: RBXScriptConnection? = nil

	local function hideGui(g: ScreenGui)
		if restored or g == ui.gui or g.Name == "TouchGui" or guiState[g] ~= nil then
			return
		end
		local entry: { wanted: boolean, conn: RBXScriptConnection? } = { wanted = g.Enabled, conn = nil }
		guiState[g] = entry
		-- somebody wants it visible: remember that and keep it hidden until the scene ends
		entry.conn = g:GetPropertyChangedSignal("Enabled"):Connect(function()
			if g.Enabled and not restored then
				entry.wanted = true
				g.Enabled = false
			end
		end)
		g.Enabled = false
	end

	local function anchorCharacter(character: Model)
		task.spawn(function()
			local root = character:WaitForChild("HumanoidRootPart", 10)
			if root and root:IsA("BasePart") and not restored then
				root.Anchored = true
			end
		end)
	end

	local function restorePlayer()
		if restored then
			return
		end
		restored = true
		if guiAddedConnection then
			guiAddedConnection:Disconnect()
		end
		for g, entry in guiState do
			if entry.conn then
				entry.conn:Disconnect()
			end
			if g.Parent then
				g.Enabled = entry.wanted
			end
		end
		table.clear(guiState)
		if characterConnection then
			characterConnection:Disconnect()
		end
		if musicConnection then
			musicConnection:Disconnect()
		end

		local character = LocalPlayer.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if root and root:IsA("BasePart") then
			root.Anchored = false
		end
		local cam = Workspace.CurrentCamera
		if cam then
			local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
			if humanoid then
				cam.CameraSubject = humanoid
			end
			cam.CameraType = Enum.CameraType.Custom
			cam.FieldOfView = 70
		end

		local snapshot: any = ClientState.snapshot
		local musicOn = true
		if snapshot and snapshot.settings and snapshot.settings.music == false then
			musicOn = false
		end
		Music.setWanted(musicOn)
		LocalPlayer:SetAttribute("InPrologue", false)
	end

	-- Removes the stadium, cars, crowd, sounds and the frame loop.
	local function stopWorld()
		finished = true
		if frameConnection then
			frameConnection:Disconnect()
			frameConnection = nil
		end
		if race then
			race.stopEngine()
		end
		SoundFx.release(crowdLoop)
		crowdLoop = nil
		if arena then
			arena.destroy()
		end
		-- a build that failed half way never returned `arena`: remove its folder too
		local leftover = Workspace:FindFirstChild("PrologueArena")
		if leftover then
			leftover:Destroy()
		end
		arena, crowd, race = nil, nil, nil
	end

	----------------------------------------------------------------------------------------------
	-- Input (keyboard, touch thumbstick and gamepad all come through the PlayerModule controls)
	----------------------------------------------------------------------------------------------
	local controls: any = nil
	task.spawn(function()
		local ok, controlsOrError = pcall(function()
			local scripts = LocalPlayer:WaitForChild("PlayerScripts")
			local playerModule = scripts:WaitForChild("PlayerModule", 15)
			if playerModule == nil then
				return nil
			end
			return (require(playerModule :: ModuleScript) :: any):GetControls()
		end)
		if ok then
			controls = controlsOrError
		end
	end)

	-- Returns steer (-1 left .. 1 right) and throttle (-1 back .. 1 forward).
	local function readInput(): (number, number)
		local x, z = 0, 0
		if controls ~= nil then
			local ok, vector = pcall(function()
				return controls:GetMoveVector()
			end)
			if ok and typeof(vector) == "Vector3" then
				x, z = vector.X, vector.Z
			end
		end
		if x == 0 and z == 0 and UserInputService:GetFocusedTextBox() == nil then
			if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
				x -= 1
			end
			if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
				x += 1
			end
			if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then
				z -= 1
			end
			if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then
				z += 1
			end
		end
		return math.clamp(x, -1, 1), math.clamp(-z, -1, 1) -- Roblox move vectors use -Z for forward
	end

	----------------------------------------------------------------------------------------------
	-- Scene events
	----------------------------------------------------------------------------------------------
	local function say(key: string)
		ui.say(key, Config.COMMENT_SECONDS)
		lastComment = os.clock()
	end

	local function startSmoke(now: number, forced: boolean)
		smoking = true
		smokeForced = forced
		smokeStart = now
		race.setSmoking(true)
		ui.setEngineWarning(true)
		say("prologue_c_smoke")
		SoundFx.play(race.player.root, "engineSputter")
	end

	local function blow()
		phase = "blown"
		race.blow()
		race.stopEngine()
		ui.setEngineWarning(false)
		ui.flashWhite()
		say("prologue_c_blow")
		SoundFx.play(race.player.root, "engineBlow")
		crowd.gasp(race.playerPosition())
		SoundFx.play(SoundService, "crowdGasp")
		camMode = "orbit"
		orbitAngle = nil
	end

	local function raceEvents(now: number)
		local progress: number = race.progress()
		local rank: number = race.rank()
		ui.setRank(rank, race.total)
		ui.setSpeed(race.player.speed)
		ui.setProgress(progress)

		if rank < lastRank then
			if rank == 1 and not hasLed then
				hasLed = true
				say("prologue_c_lead")
				crowd.cheer(2.6)
			elseif now - lastComment > Config.COMMENT_COOLDOWN then
				say("prologue_c_pass")
				crowd.cheer(1.3)
			end
			SoundFx.play(SoundService, "crowdCheer")
		end
		lastRank = rank

		if not smoking then
			if progress >= Config.SMOKE_AT then
				startSmoke(now, false)
			elseif now - raceStart >= Config.IDLE_TIMEOUT then
				startSmoke(now, true)
			end
		else
			local limit = if smokeForced then Config.FORCED_BLOW_DELAY else Config.SMOKE_TO_BLOW_MAX
			if progress >= Config.BLOW_AT or now - smokeStart >= limit then
				blow()
			end
		end
	end

	----------------------------------------------------------------------------------------------
	-- Camera
	----------------------------------------------------------------------------------------------
	local function updateCamera(dt: number)
		if camera.CameraType ~= Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Scriptable
		end
		local fov = 62
		if camMode == "intro" then
			local count = #introCams
			local u = smooth((os.clock() - introStart) / Config.INTRO_SECONDS) * (count - 1)
			local index = math.clamp(math.floor(u) + 1, 1, count - 1)
			local f = u - (index - 1)
			local pos = introCams[index]:Lerp(introCams[index + 1], f)
			local look = introLooks[index]:Lerp(introLooks[index + 1], f)
			camCF = CFrame.lookAt(pos, look)
		elseif camMode == "chase" and race then
			local p = race.player
			local base: CFrame = Track.cframeAt(p.s, p.d)
			local pos = base:PointToWorldSpace(Vector3.new(0, Config.CHASE_UP, Config.CHASE_BACK))
			local look = base:PointToWorldSpace(Vector3.new(0, 3, -Config.CHASE_LOOK_AHEAD))
			camCF = camCF:Lerp(CFrame.lookAt(pos, look), 1 - math.exp(-dt * 9))
			fov = Config.CHASE_FOV + Config.CHASE_FOV_BOOST * math.clamp(p.speed / Config.MAX_SPEED, 0, 1)
		elseif camMode == "orbit" and race then
			local carPos: Vector3 = race.playerPosition()
			local angle = orbitAngle
			if angle == nil then
				local rel = camCF.Position - carPos
				angle = math.atan2(rel.X, rel.Z)
			end
			angle += Config.ORBIT_SPEED * dt
			orbitAngle = angle
			local pos = carPos + Vector3.new(math.sin(angle) * Config.ORBIT_RADIUS, Config.ORBIT_HEIGHT, math.cos(angle) * Config.ORBIT_RADIUS)
			camCF = camCF:Lerp(CFrame.lookAt(pos, carPos + Vector3.new(0, 2, 0)), 1 - math.exp(-dt * 3))
			fov = 55
		end
		camera.CFrame = camCF
		camera.FieldOfView = camera.FieldOfView + (fov - camera.FieldOfView) * math.min(1, dt * 4)
	end

	local function onFrame(dt: number)
		if finished or race == nil or crowd == nil then
			return
		end
		local now = os.clock()
		local cameraPosition = camCF.Position
		if phase == "race" then
			local steer, throttle = readInput()
			race.step(dt, steer, throttle, cameraPosition)
			raceEvents(now)
		else
			race.step(dt, 0, 0, cameraPosition)
			if phase == "blown" then
				ui.setSpeed(race.player.speed)
				ui.setRank(race.rank(), race.total)
			end
		end
		race.updateEngine()
		updateCamera(dt)
		crowd.update(dt, camCF.Position)
		ui.update(now)
	end

	local function waitSeconds(seconds: number)
		local t0 = os.clock()
		while os.clock() - t0 < seconds and not skipped and not finished do
			task.wait()
		end
	end

	ui.onSkip(function()
		if phase == "story" then
			skipStory = true
		else
			skipped = true
		end
	end)

	----------------------------------------------------------------------------------------------
	-- Start: hide the rest of the game
	----------------------------------------------------------------------------------------------
	LocalPlayer:SetAttribute("InPrologue", true)
	Music.setWanted(false)
	musicConnection = ClientState.onChanged(function()
		-- Music.lua re-applies the saved setting on every snapshot; push it back down while the scene runs
		task.defer(function()
			if not restored then
				Music.setWanted(false)
			end
		end)
	end)
	for _, child in playerGui:GetChildren() do
		if child:IsA("ScreenGui") then
			hideGui(child)
		end
	end
	guiAddedConnection = playerGui.ChildAdded:Connect(function(child)
		if child:IsA("ScreenGui") then
			-- wait until its creator finished configuring it (many controllers set Enabled right after creating)
			task.defer(hideGui, child)
		end
	end)
	characterConnection = LocalPlayer.CharacterAdded:Connect(anchorCharacter)
	if LocalPlayer.Character then
		anchorCharacter(LocalPlayer.Character)
	end

	----------------------------------------------------------------------------------------------
	-- The scene
	----------------------------------------------------------------------------------------------
	local function playScene()
		-- 0: build everything behind the black cover
		arena = ArenaBuilder.build()
		crowd = Crowd.new(arena.seats, arena.folder, Config.CROWD_COUNT)
		race = RaceCars.new(arena.folder)
		arena.setLights(0)
		lastRank = race.total

		for _, shot in Config.INTRO_SHOTS do
			table.insert(introCams, Track.pointAt(shot.cam[1], shot.cam[2], shot.cam[3]))
			table.insert(introLooks, Track.pointAt(shot.look[1], shot.look[2], shot.look[3]))
		end
		camCF = CFrame.lookAt(introCams[1], introLooks[1])
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = camCF
		introStart = os.clock()
		phase = "intro"
		camMode = "intro"
		frameConnection = RunService.RenderStepped:Connect(onFrame)

		-- 1: intro fly-by
		crowdLoop = SoundFx.attach(SoundService, "crowdLoop")
		ui.setSkipVisible(true)
		ui.fade(1, 0.9)
		ui.showTitle()
		waitSeconds(Config.INTRO_SECONDS - 0.9)

		-- 2: countdown
		if not skipped then
			phase = "countdown"
			camMode = "chase"
			ui.hideTitle()
			ui.setHudVisible(true)
			ui.setRank(race.total, race.total)
			for i = 1, 3 do
				if skipped then
					break
				end
				arena.setLights(i, ArenaBuilder.LIGHT_RED)
				ui.showCountdown(tostring(4 - i), Color3.fromRGB(255, 255, 255))
				SoundFx.play(SoundService, "countdownBeep")
				waitSeconds(Config.COUNTDOWN_STEP)
			end
		end

		-- 3: the race
		if not skipped then
			arena.setLights(3, ArenaBuilder.LIGHT_GREEN)
			ui.showCountdownKey("prologue_go", Color3.fromRGB(110, 255, 130))
			SoundFx.play(SoundService, "countdownGo")
			arena.confetti()
			crowd.cheer(2.4)
			SoundFx.play(SoundService, "crowdCheer")
			race.start()
			raceStart = os.clock()
			phase = "race"
			say("prologue_c_start")
			waitSeconds(Config.GO_HOLD)
			ui.hideCountdown()
			-- onFrame runs the race and flips the phase to "blown" when the engine goes
			while phase == "race" and not skipped and not finished do
				task.wait()
			end
		end

		-- 5: watch the others drive past
		if phase == "blown" and not skipped then
			local t0 = os.clock()
			while not skipped and not finished do
				local elapsed = os.clock() - t0
				if elapsed >= Config.BLOW_WATCH_SECONDS and (race.rank() >= 4 or elapsed >= Config.BLOW_WATCH_SECONDS + 4) then
					break
				end
				task.wait()
			end
		end
	end

	local ok, err = pcall(playScene)
	if not ok then
		warn("[Prologue] Scene failed: " .. tostring(err))
		skipped = true
	end

	----------------------------------------------------------------------------------------------
	-- 6: story cards over black
	----------------------------------------------------------------------------------------------
	phase = "story"
	ui.hideAllHud()
	ui.setSkipVisible(ok)
	ui.fade(0, if skipped then 0.35 else Config.STORY_FADE)
	stopWorld()
	if ok then
		local first = if skipped then #STORY_KEYS else 1
		for i = first, #STORY_KEYS do
			if skipStory then
				break
			end
			ui.showStoryCard(STORY_KEYS[i], Config.STORY_CARD_SECONDS, function()
				return skipStory
			end)
		end
	end

	----------------------------------------------------------------------------------------------
	-- 7: back to the garage
	----------------------------------------------------------------------------------------------
	ui.setSkipVisible(false)
	restorePlayer()
	Remotes.get("SetSetting"):FireServer("prologueDone", true)
	task.wait(0.15)
	ui.fade(1, 1.1)
	if ok then
		ui.showWelcome(Config.WELCOME_SECONDS)
		task.wait(Config.WELCOME_SECONDS + 0.8)
	end
	ui.destroy()
end

function Prologue.start()
	-- Cover the screen at once so the garage never flashes before the scene.
	local ui = PrologueUI.new()

	local snapshot = waitForSnapshot(Config.SNAPSHOT_TIMEOUT)
	local force = Config.FORCE_IN_STUDIO and RunService:IsStudio()
	if snapshot == nil or (snapshot.prologueDone == true and not force) then
		ui.fade(1, 0.25)
		ui.destroy()
		return
	end

	local ok, err = pcall(runScene, ui)
	if not ok then
		warn("[Prologue] Failed: " .. tostring(err))
		ui.destroy()
		LocalPlayer:SetAttribute("InPrologue", false)
	end
end

return Prologue
