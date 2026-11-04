--!strict
-- All screen UI of the opening scene: black cover, title, countdown, race HUD, commentary, story cards, skip button.

local Client = (script.Parent :: Instance).Parent :: Instance
local Theme: any = require(Client:WaitForChild("Theme") :: ModuleScript)
local Localizer: any = require((Client:WaitForChild("Controllers") :: Instance):WaitForChild("Localizer") :: ModuleScript)

local PrologueUI = {}

local COVER_Z = 50
local TOP_Z = 60

local function setPlain(label: any, text: string)
	label:SetAttribute("TextKey", nil)
	label:SetAttribute("TextArgs", nil)
	label.Text = text
end

function PrologueUI.new(): any
	local C = Theme.colors
	-- Very high DisplayOrder, no GUI inset: the cover must hide everything else.
	local gui, root = Theme.newGui("Prologue", 1000, true)
	local ui: any = { gui = gui }

	-- full-screen cover, starts opaque so nothing flashes before the scene is ready
	local cover = Theme.new("Frame", {
		Name = "Cover",
		BackgroundColor3 = C.black,
		BackgroundTransparency = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = COVER_Z,
	}, root)

	local flash = Theme.new("Frame", {
		Name = "Flash",
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = COVER_Z - 2,
	}, root)

	----------------------------------------------------------------------------------------------
	-- Race HUD
	----------------------------------------------------------------------------------------------
	local hud = Theme.new("Frame", {
		Name = "Hud",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 5,
	}, root)

	local posPanel, posBody = Theme.panel({
		Name = "Position",
		Position = UDim2.fromOffset(16, 16),
		Size = UDim2.fromOffset(170, 96),
		ZIndex = 5,
	}, hud)
	local posCaption = Theme.label({
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -24, 0, 22),
		TextSize = 18,
		TextColor3 = C.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 6,
	}, posBody)
	Localizer.bind(posCaption, "prologue_position")
	local posLabel = Theme.label({
		Name = "Rank",
		Position = UDim2.fromOffset(12, 28),
		Size = UDim2.new(1, -24, 1, -34),
		TextScaled = true,
		TextColor3 = C.star,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "P7/7",
		ZIndex = 6,
	}, posBody)
	Theme.fitText(posLabel, 20, 56)
	local posPulse = Instance.new("UIScale")
	posPulse.Parent = posPanel

	local _speedPanel, speedBody = Theme.panel({
		Name = "Speed",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16),
		Size = UDim2.fromOffset(190, 76),
		ZIndex = 5,
	}, hud)
	local speedLabel = Theme.label({
		Position = UDim2.fromOffset(10, 4),
		Size = UDim2.new(1, -20, 1, -8),
		TextScaled = true,
		Text = "0 km/h",
		ZIndex = 6,
	}, speedBody)
	Theme.fitText(speedLabel, 16, 38)

	local barTrack = Theme.new("Frame", {
		Name = "ProgressTrack",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 22),
		Size = UDim2.new(0.34, 0, 0, 12),
		BackgroundColor3 = C.starDim,
		ZIndex = 5,
	}, hud)
	Theme.corner(barTrack, 6)
	local barFill = Theme.new("Frame", {
		Name = "Fill",
		BackgroundColor3 = C.accent,
		Size = UDim2.fromScale(0, 1),
		ZIndex = 6,
	}, barTrack)
	Theme.corner(barFill, 6)

	local engineLabel = Theme.label({
		Name = "Engine",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 50),
		Size = UDim2.fromOffset(300, 54),
		TextScaled = true,
		TextColor3 = C.danger,
		TextStrokeColor3 = C.black,
		TextStrokeTransparency = 0.3,
		Visible = false,
		ZIndex = 7,
	}, hud)
	Theme.fitText(engineLabel, 18, 44)
	Localizer.bind(engineLabel, "prologue_engine")

	----------------------------------------------------------------------------------------------
	-- Centre texts
	----------------------------------------------------------------------------------------------
	local countdown = Theme.label({
		Name = "Countdown",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(420, 200),
		TextScaled = true,
		TextStrokeColor3 = C.black,
		TextStrokeTransparency = 0.2,
		Visible = false,
		ZIndex = 8,
	}, root)
	Theme.fitText(countdown, 40, 150)
	local countdownScale = Instance.new("UIScale")
	countdownScale.Parent = countdown

	local title = Theme.label({
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.12, 0),
		Size = UDim2.new(0.8, 0, 0, 74),
		TextScaled = true,
		TextColor3 = C.star,
		TextStrokeColor3 = C.black,
		TextStrokeTransparency = 0.2,
		TextTransparency = 1,
		ZIndex = 8,
	}, root)
	Theme.fitText(title, 18, 56)
	Localizer.bind(title, "prologue_event")

	-- commentary subtitle (bottom centre)
	local subtitlePanel, subtitleBody = Theme.panel({
		Name = "Subtitle",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -22),
		Size = UDim2.new(0.52, 0, 0, 58),
		ZIndex = 9,
		Visible = false,
	}, root)
	local subtitleLabel = Theme.label({
		Position = UDim2.fromOffset(10, 4),
		Size = UDim2.new(1, -20, 1, -8),
		TextScaled = true,
		Font = Theme.fontMedium,
		ZIndex = 10,
	}, subtitleBody)
	Theme.fitText(subtitleLabel, 12, 26)

	-- story card + tap catcher (above the cover)
	local tapCatcher = Theme.new("TextButton", {
		Name = "Tap",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		ZIndex = COVER_Z + 3,
	}, root)
	local storyLabel = Theme.label({
		Name = "Story",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.8, 0, 0.4, 0),
		TextScaled = true,
		TextWrapped = true,
		TextTransparency = 1,
		ZIndex = COVER_Z + 4,
	}, root)
	Theme.fitText(storyLabel, 20, 60)

	local welcome = Theme.label({
		Name = "Welcome",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -40),
		Size = UDim2.new(0.8, 0, 0, 56),
		TextScaled = true,
		TextColor3 = C.accent,
		TextStrokeColor3 = C.black,
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		ZIndex = 8,
	}, root)
	Theme.fitText(welcome, 18, 40)

	-- skip button (top right, above the cover so it works during story cards too)
	local skipButton = Theme.button({
		Name = "Skip",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.fromOffset(150, Theme.buttonHeight),
		BackgroundColor3 = C.panelLighter,
		TextSize = 24,
		Visible = false,
		ZIndex = TOP_Z,
	}, root)
	Theme.stroke(skipButton, C.stroke, 2, 0.4)
	Localizer.bind(skipButton, "prologue_skip")

	----------------------------------------------------------------------------------------------
	-- API
	----------------------------------------------------------------------------------------------
	local subtitleToken = 0
	local storyToken = 0
	local tapped = false
	local engineWarning = false

	-- Fades the black cover to `transparency` (1 = scene visible, 0 = black). Yields for the duration.
	function ui.fade(transparency: number, seconds: number)
		Theme.tween(cover, { BackgroundTransparency = transparency }, seconds, Enum.EasingStyle.Sine)
		if seconds > 0 then
			task.wait(seconds)
		end
	end

	function ui.setCoverTransparency(value: number)
		cover.BackgroundTransparency = value
	end

	function ui.onSkip(fn: () -> ())
		skipButton.Activated:Connect(fn)
	end

	function ui.setSkipVisible(visible: boolean)
		skipButton.Visible = visible
	end

	function ui.showTitle()
		title.TextTransparency = 1
		Theme.tween(title, { TextTransparency = 0 }, 0.8)
		task.delay(4.6, function()
			if title.Parent then
				Theme.tween(title, { TextTransparency = 1 }, 0.8)
			end
		end)
	end

	function ui.hideTitle()
		title.TextTransparency = 1
	end

	function ui.setHudVisible(visible: boolean)
		hud.Visible = visible
	end

	function ui.setRank(rank: number, total: number)
		local text = `P{rank}/{total}`
		if posLabel.Text ~= text then
			posLabel.Text = text
			posPulse.Scale = 1.18
			Theme.tween(posPulse, { Scale = 1 }, 0.3, Enum.EasingStyle.Back)
		end
	end

	function ui.setSpeed(studsPerSecond: number)
		speedLabel.Text = `{math.floor(studsPerSecond * 1.6 + 0.5)} km/h`
	end

	function ui.setProgress(fraction: number)
		barFill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
	end

	function ui.setEngineWarning(on: boolean)
		engineWarning = on
		engineLabel.Visible = on
	end

	-- Call every frame with os.clock(): blinks the ENGINE warning.
	function ui.update(now: number)
		if engineWarning then
			engineLabel.TextTransparency = if math.floor(now * 4) % 2 == 0 then 0 else 0.6
		end
	end

	function ui.showCountdown(text: string, color: Color3?)
		setPlain(countdown, text)
		countdown.TextColor3 = color or C.text
		countdown.Visible = true
		countdownScale.Scale = 1.6
		Theme.tween(countdownScale, { Scale = 1 }, 0.35, Enum.EasingStyle.Back)
	end

	function ui.showCountdownKey(key: string, color: Color3?)
		Localizer.bind(countdown, key)
		countdown.TextColor3 = color or C.text
		countdown.Visible = true
		countdownScale.Scale = 1.6
		Theme.tween(countdownScale, { Scale = 1 }, 0.35, Enum.EasingStyle.Back)
	end

	function ui.hideCountdown()
		countdown.Visible = false
	end

	-- Commentary line at the bottom (replaces the previous one; hides itself).
	function ui.say(key: string, seconds: number)
		subtitleToken += 1
		local mine = subtitleToken
		Localizer.bind(subtitleLabel, key)
		subtitlePanel.Visible = true
		task.delay(seconds, function()
			if subtitleToken == mine and subtitlePanel.Parent then
				subtitlePanel.Visible = false
			end
		end)
	end

	function ui.hideSay()
		subtitleToken += 1
		subtitlePanel.Visible = false
	end

	-- Quick white flash (explosion).
	function ui.flashWhite()
		flash.BackgroundTransparency = 0.1
		Theme.tween(flash, { BackgroundTransparency = 1 }, 0.7, Enum.EasingStyle.Quad)
	end

	-- Shows one story card over black and waits until its time is up, a tap, or `abort()` returns true.
	function ui.showStoryCard(key: string, seconds: number, abort: () -> boolean)
		storyToken += 1
		local mine = storyToken
		tapped = false
		Localizer.bind(storyLabel, key)
		storyLabel.TextTransparency = 1
		tapCatcher.Visible = true
		local connection = tapCatcher.Activated:Connect(function()
			tapped = true
		end)
		Theme.tween(storyLabel, { TextTransparency = 0 }, 0.6)
		local t0 = os.clock()
		while os.clock() - t0 < seconds and not tapped and not abort() and storyToken == mine do
			task.wait()
		end
		connection:Disconnect()
		Theme.tween(storyLabel, { TextTransparency = 1 }, 0.45)
		tapCatcher.Visible = false
		task.wait(0.5)
	end

	function ui.showWelcome(seconds: number)
		Localizer.bind(welcome, "prologue_welcome")
		welcome.TextTransparency = 1
		welcome.TextStrokeTransparency = 1
		Theme.tween(welcome, { TextTransparency = 0, TextStrokeTransparency = 0.25 }, 0.5)
		task.delay(seconds, function()
			if welcome.Parent then
				Theme.tween(welcome, { TextTransparency = 1, TextStrokeTransparency = 1 }, 0.6)
			end
		end)
	end

	function ui.hideAllHud()
		hud.Visible = false
		countdown.Visible = false
		subtitlePanel.Visible = false
		engineLabel.Visible = false
		engineWarning = false
		skipButton.Visible = false
		title.TextTransparency = 1
	end

	function ui.destroy()
		gui:Destroy()
	end

	return ui
end

return PrologueUI
