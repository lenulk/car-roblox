--!strict
-- Top-center pill: money (animated count-up) + star rating with progress bar, a multiplier badge under the
-- money pill (hidden at x1), and on the right: the gear button (Settings) with a stack of round icon buttons
-- under it: Daily (red dot when claimable), Themes, Shop (always visible).
-- The multiplier badge shows a countdown while a Robux boost is active; tapping it opens the Shop's Boost tab.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format: any = require(Shared:WaitForChild("Format") :: ModuleScript)
local GameConfig: any = require(Shared:WaitForChild("Config"):WaitForChild("Game") :: ModuleScript)
local Client = (script.Parent :: Instance).Parent :: Instance
local ClientState: any = require(Client:WaitForChild("ClientState") :: ModuleScript)
local Theme: any = require(Client:WaitForChild("Theme") :: ModuleScript)
local Controllers = script.Parent :: Instance
local Localizer: any = require(Controllers:WaitForChild("Localizer") :: ModuleScript)
local Settings: any = require(Controllers:WaitForChild("Settings") :: ModuleScript)
local Daily: any = require(Controllers:WaitForChild("Daily") :: ModuleScript)
local Themes: any = require(Controllers:WaitForChild("Themes") :: ModuleScript)
local Shop: any = require(Controllers:WaitForChild("Shop") :: ModuleScript)

local HUD = {}

local STAR_COUNT = 5

-- 1.5 -> "x1.5", 2 -> "x2"
local function formatMultiplier(value: number): string
	return "x" .. tostring(math.floor(value * 100 + 0.5) / 100)
end

-- 754 -> "12:34"
local function formatClock(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

function HUD.start()
	local C = Theme.colors
	local _gui, root = Theme.newGui("HUD", 5, false)

	-- Row that holds the money pill and the star pill (width follows the viewport so phones fit the gear button).
	local row = Theme.new("Frame", {
		Name = "Row",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(440, 60),
	}, root)
	Theme.onViewport(function(viewport: Vector2)
		local s: number = Theme.scaleFor(viewport)
		row.Size = UDim2.fromOffset(math.clamp(viewport.X / s - 170, 280, 440), 60)
	end)

	----------------------------------------------------------------- money pill
	local moneyContainer, moneyBody = Theme.panel({
		Name = "Money",
		Size = UDim2.new(0.4, -5, 1, 0),
		Radius = 30,
	}, row)
	local moneyStroke = Theme.stroke(moneyBody, C.money, 1.5, 0.7)
	local moneyLabel = Theme.label({
		Name = "Amount",
		Size = UDim2.new(1, -20, 1, 0),
		Position = UDim2.fromOffset(10, 0),
		TextColor3 = C.money,
		TextScaled = true,
		Text = Format.money(0),
	}, moneyBody)
	Theme.fitText(moneyLabel, 14, 30)

	local displayed = Instance.new("NumberValue")
	displayed.Value = 0
	displayed.Changed:Connect(function(value: number)
		moneyLabel.Text = Format.money(math.floor(value + 0.5))
	end)

	local moneyTarget: number? = nil
	local moneyTween: Tween? = nil

	local function flashIncrease()
		-- little bounce
		moneyContainer.Position = UDim2.fromOffset(0, -6)
		Theme.tween(moneyContainer, { Position = UDim2.fromOffset(0, 0) }, 0.45, Enum.EasingStyle.Bounce)
		-- green flash
		moneyBody.BackgroundColor3 = Color3.fromRGB(40, 110, 62)
		Theme.tween(moneyBody, { BackgroundColor3 = C.panel }, 0.8)
		moneyStroke.Transparency = 0
		moneyStroke.Thickness = 3
		Theme.tween(moneyStroke, { Transparency = 0.7, Thickness = 1.5 }, 0.8)
		moneyLabel.TextColor3 = Color3.fromRGB(210, 255, 220)
		Theme.tween(moneyLabel, { TextColor3 = C.money }, 0.8)
	end

	local function setMoney(value: number)
		local previous = moneyTarget
		moneyTarget = value
		if previous == nil then
			displayed.Value = value
			return
		end
		if value == previous then
			return
		end
		if moneyTween then
			moneyTween:Cancel()
		end
		local increased = value > previous
		moneyTween = Theme.tween(displayed, { Value = value }, if increased then 0.6 else 0.35, Enum.EasingStyle.Quad)
		if increased then
			flashIncrease()
		end
	end

	----------------------------------------------------------------- star pill
	local _starContainer, starBody = Theme.panel({
		Name = "Stars",
		Position = UDim2.new(0.4, 5, 0, 0),
		Size = UDim2.new(0.6, -5, 1, 0),
		Radius = 30,
	}, row)

	local starRow = Theme.new("Frame", {
		Name = "StarRow",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(18, 5),
		Size = UDim2.new(1, -36, 0, 32),
	}, starBody)
	Theme.list(starRow, Enum.FillDirection.Horizontal, 0, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)

	local starLabels: { any } = {}
	for i = 1, STAR_COUNT do
		local star = Theme.label({
			Name = "Star" .. i,
			Size = UDim2.new(1 / STAR_COUNT, 0, 1, 0),
			Text = "★",
			TextScaled = true,
			TextColor3 = C.starDim,
			LayoutOrder = i,
		}, starRow)
		Theme.fitText(star, 10, 30)
		starLabels[i] = star
	end

	local barTrack = Theme.new("Frame", {
		Name = "BarTrack",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -9),
		Size = UDim2.new(1, -44, 0, 8),
		BackgroundColor3 = C.starDim,
	}, starBody)
	Theme.corner(barTrack, 4)
	local barFill = Theme.new("Frame", {
		Name = "Fill",
		BackgroundColor3 = C.star,
		Size = UDim2.fromScale(0, 1),
	}, barTrack)
	Theme.corner(barFill, 4)

	local lastLevel = -1
	local function setStars(level: number, points: number, nextAt: number?)
		for i, star in starLabels do
			local earned = i <= level
			if earned then
				if lastLevel >= 0 and i > lastLevel then
					-- newly earned star: pop
					star.TextColor3 = C.text
					star.Rotation = -25
					Theme.tween(star, { Rotation = 0 }, 0.5, Enum.EasingStyle.Back)
				end
				Theme.tween(star, { TextColor3 = C.star }, 0.4)
			else
				star.TextColor3 = C.starDim
			end
		end
		lastLevel = level

		local fraction = 1
		if nextAt ~= nil then
			local thresholds: { number } = GameConfig.STAR_THRESHOLDS
			local previousAt = if level > 0 then (thresholds[level] or 0) else 0
			local span = nextAt - previousAt
			fraction = if span > 0 then math.clamp((points - previousAt) / span, 0, 1) else 0
		end
		Theme.tween(barFill, { Size = UDim2.fromScale(fraction, 1) }, 0.4)
	end

	----------------------------------------------------------------- gear button
	local gear = Theme.button({
		Name = "Gear",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 6),
		Size = UDim2.fromOffset(64, 64),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = Theme.panelTransparency,
		Text = "⚙",
		TextSize = 34,
		TextColor3 = C.text,
	}, root)
	Theme.corner(gear, 32)
	Theme.stroke(gear, C.stroke, 1.5, 0.6)
	gear.Activated:Connect(function()
		Settings.toggle()
	end)

	----------------------------------------------------------------- multiplier badge
	local badgeContainer, badgeBody = Theme.panel({
		Name = "Multiplier",
		Position = UDim2.new(0, 14, 1, -4),
		Size = UDim2.fromOffset(78, 28),
		Radius = 14,
		ZIndex = 3,
		Visible = false,
	}, row)
	local badgeStroke = badgeBody:FindFirstChildOfClass("UIStroke")
	if badgeStroke then
		badgeStroke.Color = C.star
		badgeStroke.Transparency = 0.2
	end
	local badgeLabel = Theme.label({
		Name = "Value",
		Size = UDim2.new(1, 0, 0, 28),
		TextScaled = true,
		TextColor3 = C.star,
	}, badgeBody)
	Theme.fitText(badgeLabel, 12, 18)
	-- boost countdown, under "x2"
	local badgeTimer = Theme.label({
		Name = "Timer",
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 0, 16),
		Font = Theme.fontMedium,
		TextScaled = true,
		TextColor3 = C.text,
		Visible = false,
	}, badgeBody)
	Theme.fitText(badgeTimer, 9, 13)
	-- tap the badge -> Shop, Boost tab
	local badgeButton = Theme.new("TextButton", {
		Name = "Tap",
		BackgroundTransparency = 1,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 6,
	}, badgeBody)
	badgeButton.Activated:Connect(function()
		Shop.open("boost")
	end)

	local lastMultiplier = 1
	local badgeHeight = 28

	local function setBadgeHeight(height: number)
		badgeHeight = height
		badgeContainer.Size = UDim2.fromOffset(78, height)
	end

	-- Updates the countdown from the snapshot's server clock; also sizes the badge. Cheap, runs twice a second.
	local function updateBoostTimer()
		local left: number = ClientState.boostRemaining()
		if left > 0 then
			badgeTimer.Text = formatClock(left)
			badgeTimer.Visible = true
			if badgeHeight ~= 44 then
				setBadgeHeight(44)
			end
		else
			badgeTimer.Visible = false
			if badgeHeight ~= 28 then
				setBadgeHeight(28)
			end
		end
	end

	local function setMultiplier(value: number)
		local shown = math.abs(value - 1) > 0.001
		badgeContainer.Visible = shown
		if not shown then
			lastMultiplier = value
			return
		end
		badgeLabel.Text = formatMultiplier(value)
		updateBoostTimer()
		if math.abs(value - lastMultiplier) > 0.001 then
			badgeContainer.Size = UDim2.fromOffset(94, badgeHeight + 6)
			Theme.tween(badgeContainer, { Size = UDim2.fromOffset(78, badgeHeight) }, 0.5, Enum.EasingStyle.Back)
		end
		lastMultiplier = value
	end

	task.spawn(function()
		while true do
			task.wait(0.5)
			if badgeContainer.Visible then
				updateBoostTimer()
			end
		end
	end)

	----------------------------------------------------------------- side buttons
	local stack = Theme.new("Frame", {
		Name = "SideButtons",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 78),
		Size = UDim2.fromOffset(68, 10),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, root)
	Theme.list(stack, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)

	-- item: { button, circle, icon, caption, stroke }
	local sideItems: { any } = {}

	local function makeSideButton(name: string, glyph: string, captionKey: string, order: number, onPress: () -> ()): any
		local button = Theme.new("TextButton", {
			Name = name,
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			Size = UDim2.fromOffset(68, 76),
			LayoutOrder = order,
		}, stack)

		local circle = Theme.new("Frame", {
			Name = "Circle",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromOffset(56, 56),
			BackgroundColor3 = C.panel,
			BackgroundTransparency = Theme.panelTransparency,
		}, button)
		Theme.corner(circle, 28)
		local stroke = Theme.stroke(circle, C.stroke, 1.5, 0.6)

		local icon = Theme.label({
			Name = "Icon",
			Size = UDim2.fromScale(1, 1),
			Text = glyph,
			TextSize = 28,
		}, circle)

		local caption = Theme.label({
			Name = "Caption",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 58),
			Size = UDim2.new(1, 0, 0, 16),
			Font = Theme.fontMedium,
			TextSize = 13,
			TextStrokeColor3 = C.black,
			TextStrokeTransparency = 0.45,
		}, button)
		Localizer.bind(caption, captionKey)

		-- tap feedback: the circle dips and springs back
		local pressScale = Instance.new("UIScale")
		pressScale.Parent = circle
		button.Activated:Connect(function()
			Theme.tween(pressScale, { Scale = 0.88 }, 0.07)
			task.delay(0.07, function()
				Theme.tween(pressScale, { Scale = 1 }, 0.25, Enum.EasingStyle.Back)
			end)
			onPress()
		end)

		local item = { button = button, circle = circle, icon = icon, caption = caption, stroke = stroke }
		table.insert(sideItems, item)
		return item
	end

	local dailyItem = makeSideButton("Daily", "📅", "hud_daily", 1, function()
		Daily.open()
	end)
	local themesItem = makeSideButton("Themes", "🎨", "hud_themes", 2, function()
		Themes.open()
	end)
	local shopItem = makeSideButton("Shop", "🛒", "hud_shop", 3, function()
		Shop.open()
	end)

	-- red "claimable" dot on the Daily button, gently pulsing
	local dailyDot = Theme.new("Frame", {
		Name = "Dot",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.84, 0.16),
		Size = UDim2.fromOffset(18, 18),
		BackgroundColor3 = C.danger,
		Visible = false,
		ZIndex = 5,
	}, dailyItem.circle)
	Theme.corner(dailyDot, 9)
	Theme.stroke(dailyDot, C.text, 2, 0)
	local dotScale = Instance.new("UIScale")
	dotScale.Parent = dailyDot
	TweenService:Create(dotScale, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.25 }):Play()

	-- phones: a smaller stack
	Theme.onViewport(function()
		local compact = Theme.isCompact()
		local circleSize = if compact then 46 else 56
		local itemWidth = if compact then 60 else 68
		local itemHeight = circleSize + (if compact then 18 else 20)
		stack.Size = UDim2.fromOffset(itemWidth, 10)
		stack.Position = UDim2.new(1, -12, 0, if compact then 74 else 78)
		for _, item in sideItems do
			item.button.Size = UDim2.fromOffset(itemWidth, itemHeight)
			item.circle.Size = UDim2.fromOffset(circleSize, circleSize)
			item.circle.Position = UDim2.fromScale(0.5, 0)
			item.icon.TextSize = if compact then 23 else 28
			item.caption.Position = UDim2.new(0.5, 0, 0, circleSize + 2)
			item.caption.TextSize = if compact then 11 else 13
		end
	end)

	ClientState.onChanged(function(snapshot: any)
		setMoney(snapshot.money or 0)
		setStars(snapshot.starLevel or 0, snapshot.starPoints or 0, snapshot.nextStarAt)
		setMultiplier(if type(snapshot.multiplier) == "number" then snapshot.multiplier else 1)
		local daily: any = snapshot.daily
		dailyDot.Visible = type(daily) == "table" and daily.available == true
	end)
end

return HUD
