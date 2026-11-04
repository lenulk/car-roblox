--!strict
-- Rebirth window (HUD button or OpenUI("Rebirth")): current multiplier -> next multiplier, the requirement
-- (every unlock bought) with a progress bar, and a Rebirth button with a confirm step.
-- snapshot.rebirth = { count, multiplier, canRebirth, nextMultiplier }; the server sends the result toast.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes: any = require(Shared:WaitForChild("Remotes") :: ModuleScript)
local Unlocks: any = require(Shared:WaitForChild("Config"):WaitForChild("Unlocks") :: ModuleScript)
local Controllers = script.Parent :: Instance
local Client = Controllers.Parent :: Instance
local ClientState: any = require(Client:WaitForChild("ClientState") :: ModuleScript)
local Theme: any = require(Client:WaitForChild("Theme") :: ModuleScript)
local Localizer: any = require(Controllers:WaitForChild("Localizer") :: ModuleScript)
local Effects: any = require(Controllers:WaitForChild("Effects") :: ModuleScript)

local Rebirth = {}

local modal: any = nil

function Rebirth.open()
	if modal then
		modal.open()
	end
end

function Rebirth.close()
	if modal then
		modal.close()
	end
end

function Rebirth.toggle()
	if modal then
		modal.toggle()
	end
end

-- 1.5 -> "x1.5", 2 -> "x2"
local function formatMultiplier(value: number): string
	return "x" .. tostring(math.floor(value * 100 + 0.5) / 100)
end

function Rebirth.start()
	local C = Theme.colors
	local m = Theme.modal("Rebirth", 21, 520, 590)
	modal = m
	local body = m.body

	local title = Theme.label({
		Name = "Title",
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(1, 0, 0, 40),
		TextSize = 30,
	}, body)
	Localizer.bind(title, "rebirth_title")

	local description = Theme.label({
		Name = "Description",
		Position = UDim2.fromOffset(28, 58),
		Size = UDim2.new(1, -56, 0, 50),
		Font = Theme.fontMedium,
		TextColor3 = C.textDim,
		TextScaled = true,
		TextWrapped = true,
	}, body)
	Theme.fitText(description, 12, 18)
	Localizer.bind(description, "rebirth_desc")

	----------------------------------------------------------------- multiplier comparison
	local compare = Theme.new("Frame", {
		Name = "Compare",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(24, 118),
		Size = UDim2.new(1, -48, 0, 104),
	}, body)

	local function multiplierBox(xScale: number, captionKey: string, valueColor: Color3, fill: Color3): any
		local box = Theme.new("Frame", {
			Position = UDim2.new(xScale, if xScale == 0 then 0 else 20, 0, 0),
			Size = UDim2.new(0.5, -20, 1, 0),
			BackgroundColor3 = fill,
		}, compare)
		Theme.corner(box, 16)
		Theme.stroke(box, valueColor, 2, 0.5)
		local caption = Theme.label({
			Position = UDim2.fromOffset(0, 8),
			Size = UDim2.new(1, 0, 0, 22),
			Font = Theme.fontMedium,
			TextSize = 16,
			TextColor3 = C.textDim,
		}, box)
		Localizer.bind(caption, captionKey)
		local value = Theme.label({
			Position = UDim2.fromOffset(0, 34),
			Size = UDim2.new(1, 0, 1, -42),
			TextScaled = true,
			TextColor3 = valueColor,
		}, box)
		Theme.fitText(value, 20, 46)
		return value
	end
	local currentValue = multiplierBox(0, "rebirth_current", C.text, C.panelLight)
	local nextValue = multiplierBox(0.5, "rebirth_next", C.star, Color3.fromRGB(58, 48, 20))

	Theme.label({
		Name = "Arrow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(40, 40),
		Text = "➜",
		TextSize = 30,
		TextColor3 = C.money,
	}, compare)

	----------------------------------------------------------------- requirement + progress
	local reqLabel = Theme.label({
		Name = "Requirement",
		Position = UDim2.fromOffset(28, 238),
		Size = UDim2.new(1, -56, 0, 26),
		Font = Theme.fontMedium,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, body)
	Theme.fitText(reqLabel, 12, 18)
	Localizer.bind(reqLabel, "rebirth_req")

	local barTrack = Theme.new("Frame", {
		Name = "BarTrack",
		Position = UDim2.fromOffset(28, 272),
		Size = UDim2.new(1, -56, 0, 26),
		BackgroundColor3 = C.starDim,
	}, body)
	Theme.corner(barTrack, 13)
	local barFill = Theme.new("Frame", {
		Name = "Fill",
		BackgroundColor3 = C.money,
		Size = UDim2.fromScale(0, 1),
	}, barTrack)
	Theme.corner(barFill, 13)
	local barText = Theme.label({
		Size = UDim2.fromScale(1, 1),
		TextSize = 16,
		ZIndex = 3,
	}, barTrack)

	local countLabel = Theme.label({
		Name = "Count",
		Position = UDim2.fromOffset(0, 308),
		Size = UDim2.new(1, 0, 0, 24),
		Font = Theme.fontMedium,
		TextSize = 17,
		TextColor3 = C.textDim,
	}, body)

	local hintLabel = Theme.label({
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -184),
		Size = UDim2.new(1, -56, 0, 24),
		Font = Theme.fontMedium,
		TextScaled = true,
		TextColor3 = C.danger,
	}, body)
	Theme.fitText(hintLabel, 11, 17)
	Localizer.bind(hintLabel, "rebirth_locked_hint")

	----------------------------------------------------------------- buttons
	local rebirthButton = Theme.button({
		Name = "RebirthButton",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -96),
		Size = UDim2.new(1, -56, 0, 76),
		TextScaled = true,
	}, body)
	Theme.fitText(rebirthButton, 16, 30)
	Localizer.bind(rebirthButton, "rebirth_button")

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

	----------------------------------------------------------------- confirm overlay
	local overlay = Theme.new("Frame", {
		Name = "Confirm",
		BackgroundColor3 = C.black,
		BackgroundTransparency = 0.3,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Active = true,
		ZIndex = 20,
	}, body)
	Theme.corner(overlay, 18)

	local card = Theme.new("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -48, 0, 300),
		BackgroundColor3 = C.panelLight,
		ZIndex = 21,
	}, overlay)
	Theme.corner(card, 18)
	Theme.stroke(card, C.accent, 2, 0.2)

	local confirmTitle = Theme.label({
		Position = UDim2.fromOffset(0, 16),
		Size = UDim2.new(1, 0, 0, 36),
		TextSize = 28,
		ZIndex = 22,
	}, card)
	Localizer.bind(confirmTitle, "rebirth_confirm_title")

	local confirmText = Theme.label({
		Position = UDim2.fromOffset(20, 60),
		Size = UDim2.new(1, -40, 0, 90),
		Font = Theme.fontMedium,
		TextColor3 = C.textDim,
		TextScaled = true,
		TextWrapped = true,
		ZIndex = 22,
	}, card)
	Theme.fitText(confirmText, 12, 20)
	Localizer.bind(confirmText, "rebirth_confirm_text")

	local yesButton = Theme.button({
		Name = "Yes",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -88),
		Size = UDim2.new(1, -40, 0, 64),
		TextScaled = true,
		ZIndex = 22,
	}, card)
	Theme.fitText(yesButton, 14, 26)
	Localizer.bind(yesButton, "rebirth_yes")

	local noButton = Theme.button({
		Name = "No",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.new(1, -40, 0, 56),
		BackgroundColor3 = C.gray,
		TextSize = 22,
		ZIndex = 22,
	}, card)
	Localizer.bind(noButton, "ui_cancel")

	----------------------------------------------------------------- state
	local busy = false
	local canRebirth = false

	local function styleButton()
		local enabled = canRebirth and not busy
		rebirthButton.AutoButtonColor = enabled
		Theme.tween(rebirthButton, {
			BackgroundColor3 = if enabled then C.accent else C.gray,
			TextColor3 = if enabled then C.text else C.textDim,
		}, 0.15)
		yesButton.AutoButtonColor = not busy
	end

	local function showConfirm(visible: boolean)
		overlay.Visible = visible
	end

	local function render()
		local snapshot: any = ClientState.snapshot
		if snapshot == nil then
			return
		end
		local info: any = snapshot.rebirth
		local current = 1
		local nextMultiplier = 1.5
		local count = 0
		canRebirth = false
		if type(info) == "table" then
			if type(info.multiplier) == "number" then
				current = info.multiplier
			end
			if type(info.nextMultiplier) == "number" then
				nextMultiplier = info.nextMultiplier
			end
			if type(info.count) == "number" then
				count = info.count
			end
			canRebirth = info.canRebirth == true
		end
		currentValue.Text = formatMultiplier(current)
		nextValue.Text = formatMultiplier(nextMultiplier)

		local owned = 0
		local total = 0
		local unlocked: any = snapshot.unlocks
		for _, entry in Unlocks.list do
			-- personal unlocks (race track) are not part of the rebirth requirement
			if not (entry :: any).keepOnRebirth then
				total += 1
				if type(unlocked) == "table" and unlocked[entry.id] then
					owned += 1
				end
			end
		end
		Theme.tween(barFill, { Size = UDim2.fromScale(if total > 0 then owned / total else 0, 1) }, 0.3)
		Localizer.bind(barText, "rebirth_progress", owned, total)
		Localizer.bind(countLabel, "rebirth_count", count)
		hintLabel.Visible = not canRebirth
		if not canRebirth then
			showConfirm(false)
		end
		styleButton()
	end

	rebirthButton.Activated:Connect(function()
		if canRebirth and not busy then
			showConfirm(true)
		end
	end)
	noButton.Activated:Connect(function()
		showConfirm(false)
	end)

	yesButton.Activated:Connect(function()
		if busy or not canRebirth then
			return
		end
		busy = true
		styleButton()
		local ok, result = pcall(function()
			local success = Remotes.get("Rebirth"):InvokeServer()
			return success
		end)
		showConfirm(false)
		if not ok then
			warn("[Rebirth] Rebirth failed: " .. tostring(result))
		elseif result == true then
			Effects.confetti(m.root, 50)
			task.delay(1.2, function()
				m.close()
			end)
		end
		task.wait(0.3)
		busy = false
		render()
	end)

	m.onOpen = function()
		showConfirm(false)
		render()
	end

	ClientState.onChanged(function()
		if m.isOpen then
			render()
		end
	end)

	Remotes.get("OpenUI").OnClientEvent:Connect(function(uiName: any)
		if uiName == "Rebirth" then
			m.open()
		end
	end)
end

return Rebirth
