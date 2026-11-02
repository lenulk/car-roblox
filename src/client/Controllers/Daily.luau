--!strict
-- Daily reward window (OpenUI("Daily") or the HUD button): a 7-day calendar strip and a Claim button.
-- snapshot.daily = { available, streak, reward }. The server answers ClaimDaily with a Notify toast.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes: any = require(Shared:WaitForChild("Remotes") :: ModuleScript)
local Format: any = require(Shared:WaitForChild("Format") :: ModuleScript)
local GameConfig: any = require(Shared:WaitForChild("Config"):WaitForChild("Game") :: ModuleScript)
local Controllers = script.Parent :: Instance
local Client = Controllers.Parent :: Instance
local ClientState: any = require(Client:WaitForChild("ClientState") :: ModuleScript)
local Theme: any = require(Client:WaitForChild("Theme") :: ModuleScript)
local Localizer: any = require(Controllers:WaitForChild("Localizer") :: ModuleScript)
local Effects: any = require(Controllers:WaitForChild("Effects") :: ModuleScript)

local Daily = {}

local modal: any = nil

function Daily.open()
	if modal then
		modal.open()
	end
end

function Daily.close()
	if modal then
		modal.close()
	end
end

function Daily.toggle()
	if modal then
		modal.toggle()
	end
end

function Daily.start()
	local C = Theme.colors
	local m = Theme.modal("Daily", 21, 620, 500)
	modal = m
	local body = m.body

	local dayCount: number = if type(GameConfig.DAILY_MAX_STREAK) == "number" then GameConfig.DAILY_MAX_STREAK else 7
	local baseReward: number = if type(GameConfig.DAILY_BASE) == "number" then GameConfig.DAILY_BASE else 500

	local title = Theme.label({
		Name = "Title",
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(1, 0, 0, 40),
		TextSize = 30,
	}, body)
	Localizer.bind(title, "daily_title")

	local subtitle = Theme.label({
		Name = "Subtitle",
		Position = UDim2.fromOffset(24, 56),
		Size = UDim2.new(1, -48, 0, 26),
		Font = Theme.fontMedium,
		TextColor3 = C.textDim,
		TextScaled = true,
	}, body)
	Theme.fitText(subtitle, 11, 17)
	Localizer.bind(subtitle, "daily_sub")

	----------------------------------------------------------------- calendar strip
	local strip = Theme.new("Frame", {
		Name = "Strip",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 96),
		Size = UDim2.new(1, -32, 0, 156),
	}, body)

	local cells: { { frame: any, stroke: UIStroke, dayLabel: any, icon: any, reward: any } } = {}
	for day = 1, dayCount do
		local frame = Theme.new("Frame", {
			Name = "Day" .. day,
			Position = UDim2.new((day - 1) / dayCount, 3, 0, 8),
			Size = UDim2.new(1 / dayCount, -6, 1, -16),
			BackgroundColor3 = C.panelLight,
		}, strip)
		Theme.corner(frame, 12)
		local stroke = Theme.stroke(frame, C.stroke, 1.5, 0.75)

		local dayLabel = Theme.label({
			Name = "Day",
			Position = UDim2.fromOffset(0, 6),
			Size = UDim2.new(1, 0, 0, 22),
			TextScaled = true,
			TextColor3 = C.textDim,
		}, frame)
		Theme.fitText(dayLabel, 9, 16)
		Localizer.bind(dayLabel, "daily_day", day)

		local icon = Theme.label({
			Name = "Icon",
			Position = UDim2.new(0, 0, 0.5, -20),
			Size = UDim2.new(1, 0, 0, 40),
			Text = if day == dayCount then "★" else "$",
			TextScaled = true,
			TextColor3 = C.star,
		}, frame)
		Theme.fitText(icon, 14, 34)

		local reward = Theme.label({
			Name = "Reward",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, -6),
			Size = UDim2.new(1, 0, 0, 22),
			Text = Format.money(baseReward * day),
			TextScaled = true,
			TextColor3 = C.money,
		}, frame)
		Theme.fitText(reward, 9, 17)

		cells[day] = { frame = frame, stroke = stroke, dayLabel = dayLabel, icon = icon, reward = reward }
	end

	local streakLabel = Theme.label({
		Name = "Streak",
		Position = UDim2.fromOffset(0, 262),
		Size = UDim2.new(1, 0, 0, 28),
		Font = Theme.fontMedium,
		TextSize = 20,
		TextColor3 = C.star,
	}, body)

	----------------------------------------------------------------- buttons
	local claimButton = Theme.button({
		Name = "Claim",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -94),
		Size = UDim2.new(1, -48, 0, 76),
		TextScaled = true,
	}, body)
	Theme.fitText(claimButton, 16, 30)

	local closeButton = Theme.button({
		Name = "Close",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(220, Theme.buttonHeight),
		BackgroundColor3 = C.gray,
		TextSize = 24,
	}, body)
	Localizer.bind(closeButton, "close")
	closeButton.Activated:Connect(function()
		m.close()
	end)

	----------------------------------------------------------------- state
	local busy = false
	local available = false

	local function styleClaim()
		local enabled = available and not busy
		claimButton.AutoButtonColor = enabled
		Theme.tween(claimButton, {
			BackgroundColor3 = if enabled then C.accent else C.gray,
			TextColor3 = if enabled then C.text else C.textDim,
		}, 0.15)
	end

	local function render()
		local snapshot: any = ClientState.snapshot
		local daily: any = if snapshot then snapshot.daily else nil
		if type(daily) ~= "table" then
			return
		end
		available = daily.available == true
		local streak = math.clamp(if type(daily.streak) == "number" then math.floor(daily.streak) else 1, 1, dayCount)
		local reward: number = if type(daily.reward) == "number" then daily.reward else baseReward * streak

		for day, cell in cells do
			-- claimed: every earlier day, and today's too once it was collected
			local claimed = day < streak or (day == streak and not available)
			local isCurrent = day == streak
			cell.frame.BackgroundColor3 = if claimed then Color3.fromRGB(30, 70, 48) elseif isCurrent then C.panelLighter else C.panelLight
			cell.stroke.Color = if isCurrent then C.accent else if claimed then C.money else C.stroke
			cell.stroke.Thickness = if isCurrent then 3.5 else 1.5
			cell.stroke.Transparency = if isCurrent then 0 elseif claimed then 0.45 else 0.75
			cell.icon.Text = if claimed then "✓" elseif day == dayCount then "★" else "$"
			cell.icon.TextColor3 = if claimed then C.money else C.star
			cell.dayLabel.TextColor3 = if isCurrent then C.text else C.textDim
			cell.frame.Position = UDim2.new((day - 1) / dayCount, 3, 0, if isCurrent then 0 else 8)
			cell.frame.Size = UDim2.new(1 / dayCount, -6, 1, if isCurrent then 0 else -16)
		end

		Localizer.bind(streakLabel, "daily_streak", streak)
		if available then
			Localizer.bind(claimButton, "daily_claim", Format.money(reward))
		else
			Localizer.bind(claimButton, "daily_claimed")
		end
		styleClaim()
	end

	claimButton.Activated:Connect(function()
		if busy or not available then
			return
		end
		busy = true
		styleClaim()
		local ok, result = pcall(function()
			local success = Remotes.get("ClaimDaily"):InvokeServer()
			return success
		end)
		if not ok then
			warn("[Daily] ClaimDaily failed: " .. tostring(result))
		elseif result == true then
			Effects.confetti(m.root, 44)
		end
		task.wait(0.3)
		busy = false
		render()
	end)

	m.onOpen = function()
		render()
	end

	ClientState.onChanged(function()
		if m.isOpen then
			render()
		end
	end)

	Remotes.get("OpenUI").OnClientEvent:Connect(function(uiName: any)
		if uiName == "Daily" then
			m.open()
		end
	end)
end

return Daily
