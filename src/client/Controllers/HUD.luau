--!strict
-- Top-center pill: money (animated count-up) + star rating with progress bar. Gear button opens Settings.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format: any = require(Shared:WaitForChild("Format") :: ModuleScript)
local GameConfig: any = require(Shared:WaitForChild("Config"):WaitForChild("Game") :: ModuleScript)
local Client = (script.Parent :: Instance).Parent :: Instance
local ClientState: any = require(Client:WaitForChild("ClientState") :: ModuleScript)
local Theme: any = require(Client:WaitForChild("Theme") :: ModuleScript)
local Settings: any = require((script.Parent :: Instance):WaitForChild("Settings") :: ModuleScript)

local HUD = {}

local STAR_COUNT = 5

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

	ClientState.onChanged(function(snapshot: any)
		setMoney(snapshot.money or 0)
		setStars(snapshot.starLevel or 0, snapshot.starPoints or 0, snapshot.nextStarAt)
	end)
end

return HUD
