--!strict
-- Driving HUD: speedometer (km/h, segmented arc, D/N/R gear badge) at bottom-center and a big Return button.
-- Visible only while the local Humanoid sits in a VehicleSeat named "DriveSeat". Also widens the FOV a little with speed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes: any = require(Shared:WaitForChild("Remotes") :: ModuleScript)
local Client = (script.Parent :: Instance).Parent :: Instance
local Theme: any = require(Client:WaitForChild("Theme") :: ModuleScript)
local Localizer: any = require((script.Parent :: Instance):WaitForChild("Localizer") :: ModuleScript)

local LocalPlayer = Players.LocalPlayer

local DriveHUD = {}

local SEGMENTS = 26
local KMH_PER_STUD = 1.2
local DEFAULT_MAX_SPEED = 100
local FOV_BOOST = 14 -- degrees at top speed
local RETURN_KEY = "drive_return"

function DriveHUD.start()
	local C = Theme.colors
	local _gui, root = Theme.newGui("DriveHUD", 6, false)

	local SPEEDO_SHOWN = UDim2.new(0.5, 0, 1, -14)
	local SPEEDO_HIDDEN = UDim2.new(0.5, 0, 1, 240)
	local RETURN_SHOWN = UDim2.new(1, -12, 0, 82)
	local RETURN_HIDDEN = UDim2.new(1, 240, 0, 82)

	----------------------------------------------------------------- speedometer
	local speedoContainer, speedoBody = Theme.panel({
		Name = "Speedo",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = SPEEDO_HIDDEN,
		Size = UDim2.fromOffset(300, 176),
		Radius = 30,
		Visible = false,
	}, root)

	local segments: { any } = {}
	local segmentColors: { Color3 } = {}
	local cx, cy, arcRadius = 150, 124, 110
	for i = 1, SEGMENTS do
		local t = (i - 1) / (SEGMENTS - 1)
		local theta = math.pi * (1 - t) -- pi = left end, 0 = right end
		local color = if t < 0.5 then C.money:Lerp(C.star, t / 0.5) else C.star:Lerp(C.danger, (t - 0.5) / 0.5)
		local segment = Theme.new("Frame", {
			Name = "Seg" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(cx + arcRadius * math.cos(theta), cy - arcRadius * math.sin(theta)),
			Size = UDim2.fromOffset(20, 7), -- width runs along the radius
			Rotation = -math.deg(theta),
			BackgroundColor3 = C.starDim,
		}, speedoBody)
		Theme.corner(segment, 3)
		segments[i] = segment
		segmentColors[i] = color
	end

	local speedLabel = Theme.label({
		Name = "Speed",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, 88),
		Size = UDim2.fromOffset(150, 60),
		TextScaled = true,
		Text = "0",
	}, speedoBody)
	Theme.fitText(speedLabel, 24, 56)

	Theme.label({
		Name = "Unit",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, 126),
		Size = UDim2.fromOffset(100, 20),
		TextSize = 16,
		TextColor3 = C.textDim,
		Text = "km/h",
	}, speedoBody)

	local gearBadge = Theme.new("Frame", {
		Name = "Gear",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, 153),
		Size = UDim2.fromOffset(34, 34),
		BackgroundColor3 = C.panelLighter,
	}, speedoBody)
	Theme.corner(gearBadge, 17)
	local gearStroke = Theme.stroke(gearBadge, C.textDim, 2, 0.3)
	local gearLabel = Theme.label({
		Name = "Letter",
		Size = UDim2.fromScale(1, 1),
		TextScaled = true,
		TextColor3 = C.textDim,
		Text = "N",
	}, gearBadge)
	Theme.fitText(gearLabel, 12, 22)

	----------------------------------------------------------------- return button
	local returnButton = Theme.button({
		Name = "Return",
		AnchorPoint = Vector2.new(1, 0),
		Position = RETURN_HIDDEN,
		Size = UDim2.fromOffset(170, Theme.buttonHeight),
		BackgroundColor3 = C.accent,
		TextScaled = true,
		Visible = false,
	}, root)
	Theme.stroke(returnButton, C.text, 2, 0.6)
	Theme.fitText(returnButton, 16, 26)

	local function refreshReturnText()
		local text: string = Localizer.t(RETURN_KEY)
		if text == RETURN_KEY or text == "" then
			text = "↩"
		end
		returnButton.Text = text
	end
	refreshReturnText()
	Localizer.onLangChanged(function()
		refreshReturnText()
	end)

	local lastReturn = 0.0
	returnButton.Activated:Connect(function()
		local now = os.clock()
		if now - lastReturn < 1 then
			return
		end
		lastReturn = now
		Remotes.get("ReturnCar"):FireServer()
	end)

	----------------------------------------------------------------- lap timer (private race track)
	-- Visible only while driving a car with OnTrack = true. The server publishes LapStart / NextCheckpoint /
	-- CheckpointCount / LastLap / BestLap / LapCount as attributes on the car; the running time is computed here.
	local timerContainer, timerBody = Theme.panel({
		Name = "LapTimer",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 78),
		Size = UDim2.fromOffset(290, 100),
		Radius = 20,
		Visible = false,
	}, root)

	local lapLabel = Theme.label({
		Name = "Lap",
		Position = UDim2.fromOffset(10, 4),
		Size = UDim2.new(1, -20, 0, 40),
		TextScaled = true,
		Text = "0:00.000",
	}, timerBody)
	Theme.fitText(lapLabel, 18, 36)

	local bestLabel = Theme.label({
		Name = "Best",
		Position = UDim2.fromOffset(12, 46),
		Size = UDim2.new(0.5, -12, 0, 22),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.textDim,
		Text = "",
	}, timerBody)
	Theme.fitText(bestLabel, 10, 16)

	local checkpointLabel = Theme.label({
		Name = "Checkpoint",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 46),
		Size = UDim2.new(0.5, -12, 0, 22),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.textDim,
		Text = "",
	}, timerBody)
	Theme.fitText(checkpointLabel, 10, 16)

	local messageLabel = Theme.label({
		Name = "Message",
		Position = UDim2.fromOffset(10, 70),
		Size = UDim2.new(1, -20, 0, 24),
		TextScaled = true,
		TextColor3 = C.textDim,
		Text = "",
	}, timerBody)
	Theme.fitText(messageLabel, 10, 18)

	local function formatLap(seconds: number): string
		local minutes = math.floor(seconds / 60)
		return string.format("%d:%06.3f", minutes, seconds - minutes * 60)
	end

	local trackCar: Model? = nil
	local trackConns: { RBXScriptConnection } = {}
	local previousBest: number? = nil
	local flashUntil = 0.0
	local flashText = ""
	local flashColor = C.text

	local function numberAttr(model: Model, name: string): number?
		local value = model:GetAttribute(name)
		return if type(value) == "number" then value else nil
	end

	local function refreshTimerTexts()
		local car = trackCar
		if not car then
			return
		end
		local best = numberAttr(car, "BestLap")
		bestLabel.Text = Localizer.t("track_best") .. " " .. (if best then formatLap(best) else "-:--.---")
		local passed = math.max((numberAttr(car, "NextCheckpoint") or 1) - 1, 0)
		checkpointLabel.Text =
			string.format("%s %d/%d", Localizer.t("track_checkpoint"), passed, numberAttr(car, "CheckpointCount") or 0)
	end

	local function onLapFinished(car: Model)
		local lap = numberAttr(car, "LastLap")
		if not lap then
			return
		end
		local best = numberAttr(car, "BestLap")
		local before = previousBest
		local isBest = best ~= nil and math.abs(best - lap) < 1e-6 and (before == nil or lap < before)
		previousBest = best
		flashText = formatLap(lap)
		flashColor = if isBest then C.money else C.text
		flashUntil = os.clock() + 4
		if before then
			local diff = lap - before
			messageLabel.Text = string.format("%+.3f", diff)
			messageLabel.TextColor3 = if diff > 0 then C.danger else C.money
		else
			messageLabel.Text = ""
		end
		refreshTimerTexts()
	end

	local function setTimerCar(car: Model?)
		for _, conn in trackConns do
			conn:Disconnect()
		end
		trackConns = {}
		trackCar = car
		flashUntil = 0
		timerContainer.Visible = car ~= nil
		if not car then
			return
		end
		previousBest = numberAttr(car, "BestLap")
		lapLabel.TextColor3 = C.text
		messageLabel.TextColor3 = C.textDim
		messageLabel.Text = Localizer.t("track_start_hint")
		refreshTimerTexts()
		local function watch(name: string, fn: () -> ())
			table.insert(trackConns, car:GetAttributeChangedSignal(name):Connect(fn))
		end
		watch("NextCheckpoint", refreshTimerTexts)
		watch("BestLap", refreshTimerTexts)
		watch("CheckpointCount", refreshTimerTexts)
		-- the server sets LapCount last, so LastLap / BestLap are already current here
		watch("LapCount", function()
			onLapFinished(car)
		end)
		watch("LapStart", function()
			if car:GetAttribute("LapStart") ~= nil and flashUntil == 0 and (numberAttr(car, "LapCount") or 0) == 0 then
				messageLabel.Text = ""
			end
		end)
	end

	local function updateTimer()
		local car = trackCar
		if not car then
			return
		end
		local now = os.clock()
		if now < flashUntil then
			lapLabel.Text = flashText
			lapLabel.TextColor3 = flashColor
			lapLabel.TextTransparency = if math.floor(now * 4) % 2 == 0 then 0 else 0.55
			return
		end
		lapLabel.TextTransparency = 0
		lapLabel.TextColor3 = C.text
		local lapStart = numberAttr(car, "LapStart")
		if lapStart then
			lapLabel.Text = formatLap(math.max(Workspace:GetServerTimeNow() - lapStart, 0))
		else
			lapLabel.Text = "0:00.000"
		end
	end

	Localizer.onLangChanged(function()
		refreshTimerTexts()
		if trackCar and numberAttr(trackCar, "LapStart") == nil then
			messageLabel.Text = Localizer.t("track_start_hint")
		end
	end)

	local function findTrackCar(part: BasePart): Model?
		local node: Instance? = part.Parent
		while node and node ~= Workspace do
			if node:IsA("Model") and node:GetAttribute("OnTrack") == true then
				return node
			end
			node = node.Parent
		end
		return nil
	end

	----------------------------------------------------------------- state
	local seat: VehicleSeat? = nil
	local seatMaxSpeed = DEFAULT_MAX_SPEED
	local renderConn: RBXScriptConnection? = nil
	local humanoidConn: RBXScriptConnection? = nil
	local shown = false
	local showToken = 0
	local shownSpeed = 0.0
	local litCount = 0
	local currentGear = ""
	local baseFov: number? = nil

	local function setGear(letter: string)
		if letter == currentGear then
			return
		end
		currentGear = letter
		local color = if letter == "D" then C.money elseif letter == "R" then C.danger else C.textDim
		gearLabel.Text = letter
		gearLabel.TextColor3 = color
		gearStroke.Color = color
	end

	local function setLit(count: number)
		if count == litCount then
			return
		end
		litCount = count
		for i, segment in segments do
			segment.BackgroundColor3 = if i <= count then segmentColors[i] else C.starDim
		end
	end

	local function setShown(on: boolean)
		if shown == on then
			return
		end
		shown = on
		showToken += 1
		local mine = showToken
		if on then
			speedoContainer.Visible = true
			returnButton.Visible = true
			Theme.tween(speedoContainer, { Position = SPEEDO_SHOWN }, 0.4, Enum.EasingStyle.Back)
			Theme.tween(returnButton, { Position = RETURN_SHOWN }, 0.4, Enum.EasingStyle.Back)
		else
			Theme.tween(speedoContainer, { Position = SPEEDO_HIDDEN }, 0.3)
			Theme.tween(returnButton, { Position = RETURN_HIDDEN }, 0.3)
			task.delay(0.35, function()
				if showToken == mine and not shown then
					speedoContainer.Visible = false
					returnButton.Visible = false
				end
			end)
		end
	end

	local exitDrive: () -> ()

	local function update(dt: number)
		local current = seat
		if not current or not current.Parent then
			exitDrive()
			return
		end
		updateTimer()
		local velocity = current.AssemblyLinearVelocity
		local planar = Vector3.new(velocity.X, 0, velocity.Z)
		local speed = planar.Magnitude
		local along = planar:Dot(current.CFrame.LookVector)

		shownSpeed += (speed - shownSpeed) * math.min(1, dt * 10)
		local kmh = math.floor(shownSpeed * KMH_PER_STUD + 0.5)
		local text = tostring(kmh)
		if speedLabel.Text ~= text then
			speedLabel.Text = text
		end
		local fraction = math.clamp(shownSpeed / seatMaxSpeed, 0, 1)
		setLit(math.floor(fraction * SEGMENTS + 0.5))

		if speed < 1.5 then
			setGear("N")
		elseif along < 0 then
			setGear("R")
		else
			setGear("D")
		end

		local camera = Workspace.CurrentCamera
		local base = baseFov
		if camera and base then
			local target = math.min(base + FOV_BOOST * fraction * fraction, 110)
			camera.FieldOfView += (target - camera.FieldOfView) * math.min(1, dt * 4)
		end
	end

	local function enterDrive(part: VehicleSeat)
		local model = part:FindFirstAncestorOfClass("Model")
		local attr = if model then model:GetAttribute("MaxSpeed") else nil
		seatMaxSpeed = if type(attr) == "number" and attr > 0 then attr else DEFAULT_MAX_SPEED
		if seat == part then
			return
		end
		seat = part
		setTimerCar(findTrackCar(part))
		shownSpeed = 0
		litCount = -1
		setLit(0)
		currentGear = ""
		setGear("N")
		refreshReturnText()
		local camera = Workspace.CurrentCamera
		if camera and baseFov == nil then
			baseFov = camera.FieldOfView
		end
		if not renderConn then
			renderConn = RunService.RenderStepped:Connect(update)
		end
		setShown(true)
	end

	exitDrive = function()
		seat = nil
		setTimerCar(nil)
		if renderConn then
			renderConn:Disconnect()
			renderConn = nil
		end
		local camera = Workspace.CurrentCamera
		local base = baseFov
		baseFov = nil
		if camera and base then
			Theme.tween(camera, { FieldOfView = base }, 0.4)
		end
		setShown(false)
	end

	local function onSeatChanged(part: BasePart?)
		if part and part:IsA("VehicleSeat") and part.Name == "DriveSeat" then
			enterDrive(part)
		else
			exitDrive()
		end
	end

	local function watchHumanoid(humanoid: Humanoid)
		if humanoidConn then
			humanoidConn:Disconnect()
		end
		humanoidConn = humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
			onSeatChanged(humanoid.SeatPart)
		end)
		onSeatChanged(humanoid.SeatPart)
	end

	local function watchCharacter(character: Model)
		local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 15)
		if humanoid and humanoid:IsA("Humanoid") then
			watchHumanoid(humanoid)
		end
	end

	LocalPlayer.CharacterAdded:Connect(watchCharacter)
	LocalPlayer.CharacterRemoving:Connect(function()
		if humanoidConn then
			humanoidConn:Disconnect()
			humanoidConn = nil
		end
		exitDrive()
	end)
	local existing = LocalPlayer.Character
	if existing then
		watchCharacter(existing)
	end
end

return DriveHUD
