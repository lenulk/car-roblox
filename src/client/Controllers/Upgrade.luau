--!strict
-- Station upgrade window, opened by the server with OpenUI("Upgrade", unlockId).
-- Everything shown comes from snapshot.upgradeInfo[unlockId]; the server answers with a Notify toast.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes: any = require(Shared:WaitForChild("Remotes") :: ModuleScript)
local Format: any = require(Shared:WaitForChild("Format") :: ModuleScript)
local Controllers = script.Parent :: Instance
local Client = Controllers.Parent :: Instance
local ClientState: any = require(Client:WaitForChild("ClientState") :: ModuleScript)
local Theme: any = require(Client:WaitForChild("Theme") :: ModuleScript)
local Localizer: any = require(Controllers:WaitForChild("Localizer") :: ModuleScript)
local Effects: any = require(Controllers:WaitForChild("Effects") :: ModuleScript)

local Upgrade = {}

local PIP_COUNT = 5
local DARK_TEXT = Color3.fromRGB(60, 40, 0)

local openFor: ((string) -> ())? = nil

-- Opens the window for an unlock id (same as the server's OpenUI("Upgrade", id)).
function Upgrade.open(unlockId: string)
	if openFor then
		openFor(unlockId)
	end
end

function Upgrade.start()
	local C = Theme.colors
	local m = Theme.modal("Upgrade", 22, 460, 590)
	local body = m.body

	----------------------------------------------------------------- header
	local header = Theme.label({
		Name = "Header",
		Position = UDim2.fromOffset(70, 16),
		Size = UDim2.new(1, -140, 0, 22),
		TextSize = 16,
		TextColor3 = C.accent,
	}, body)
	Localizer.bind(header, "upgrade_title")

	local nameLabel = Theme.label({
		Name = "StationName",
		Position = UDim2.fromOffset(70, 38),
		Size = UDim2.new(1, -140, 0, 44),
		TextScaled = true,
	}, body)
	Theme.fitText(nameLabel, 16, 30)

	local closeX = Theme.button({
		Name = "CloseX",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 10),
		Size = UDim2.fromOffset(56, 56),
		BackgroundColor3 = C.panelLighter,
		Text = "✕",
		TextSize = 24,
		TextColor3 = C.textDim,
	}, body)
	closeX.Activated:Connect(function()
		m.close()
	end)

	-- everything that needs snapshot data lives in `content` (hidden until the info exists)
	local content = Theme.new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
	}, body)

	----------------------------------------------------------------- level pips
	local pipsRow = Theme.new("Frame", {
		Name = "Pips",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 92),
		Size = UDim2.new(1, 0, 0, 56),
	}, content)
	Theme.list(pipsRow, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)

	local pips: { { slot: Frame, pip: any, stroke: UIStroke, num: any } } = {}
	for i = 1, PIP_COUNT do
		local slot = Theme.new("Frame", {
			Name = "Slot" .. i,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(52, 52),
			LayoutOrder = i,
		}, pipsRow)
		local pip = Theme.new("Frame", {
			Name = "Pip",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(30, 30),
			BackgroundColor3 = C.starDim,
		}, slot)
		Theme.corner(pip, 26)
		local pipStroke = Theme.stroke(pip, C.text, 3, 1)
		local num = Theme.label({
			Size = UDim2.fromScale(1, 1),
			Text = tostring(i),
			TextSize = 18,
			TextColor3 = C.textDim,
		}, pip)
		pips[i] = { slot = slot, pip = pip, stroke = pipStroke, num = num }
	end

	local levelLabel = Theme.label({
		Name = "LevelText",
		Position = UDim2.fromOffset(0, 150),
		Size = UDim2.new(1, 0, 0, 24),
		TextSize = 17,
		Font = Theme.fontMedium,
		TextColor3 = C.textDim,
	}, content)

	----------------------------------------------------------------- stat rows
	local rowsScroll = Theme.new("ScrollingFrame", {
		Name = "Rows",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(24, 186),
		Size = UDim2.new(1, -48, 1, -186 - 138),
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = C.gray,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, content)
	Theme.list(rowsScroll, Enum.FillDirection.Vertical, 8)

	----------------------------------------------------------------- buy area
	local needLabel = Theme.label({
		Name = "NeedMore",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -104),
		Size = UDim2.new(1, -48, 0, 24),
		TextSize = 17,
		Font = Theme.fontMedium,
		TextColor3 = C.danger,
		Visible = false,
	}, content)

	local upgradeButton = Theme.button({
		Name = "UpgradeButton",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -22),
		Size = UDim2.new(1, -48, 0, 76),
		TextScaled = true,
	}, content)
	Theme.fitText(upgradeButton, 16, 30)

	----------------------------------------------------------------- state
	local busy = false
	local currentId: string? = nil
	local lastLevel: number? = nil
	local lastRowsSignature: string? = nil
	local canBuy = false

	local function styleButton()
		local enabled = canBuy and not busy
		upgradeButton.AutoButtonColor = enabled
		Theme.tween(upgradeButton, {
			BackgroundColor3 = if enabled then C.accent else C.gray,
			TextColor3 = if enabled then C.text else C.textDim,
		}, 0.15)
	end

	local function setPips(level: number, maxLevel: number, popIndex: number?)
		for i, entry in pips do
			entry.slot.Visible = i <= maxLevel
			local state = if i < level then "done" elseif i == level then "current" else "todo"
			local size = if state == "current" then 46 elseif state == "done" then 34 else 30
			local fill = if state == "current" then C.accent elseif state == "done" then C.star else C.starDim
			entry.num.TextColor3 = if state == "todo" then C.textDim else if state == "done" then DARK_TEXT else C.text
			entry.num.TextSize = if state == "current" then 24 else 18
			if popIndex == i then
				entry.pip.Size = UDim2.fromOffset(12, 12)
				Theme.tween(entry.pip, { Size = UDim2.fromOffset(size, size), BackgroundColor3 = fill }, 0.55, Enum.EasingStyle.Back)
			else
				Theme.tween(entry.pip, { Size = UDim2.fromOffset(size, size), BackgroundColor3 = fill }, 0.2)
			end
			Theme.tween(entry.stroke, { Transparency = if state == "current" then 0.15 else 1 }, 0.2)
		end
		Localizer.bind(levelLabel, "ui_level_of", level, maxLevel)
	end

	local function buildRow(row: any, index: number, atMax: boolean)
		local frame = Theme.new("Frame", {
			Name = "Row" .. index,
			Size = UDim2.new(1, -8, 0, 56),
			BackgroundColor3 = C.panelLight,
			LayoutOrder = index,
		}, rowsScroll)
		Theme.corner(frame, 12)

		local label = Theme.label({
			Name = "Label",
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.new(0.5, -14, 1, 0),
			Font = Theme.fontMedium,
			TextScaled = true,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, frame)
		Theme.fitText(label, 11, 19)
		if type(row.labelKey) == "string" then
			Localizer.bind(label, row.labelKey)
		end

		local right = Theme.new("Frame", {
			Name = "Values",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.new(0.5, -14, 1, 0),
			BackgroundTransparency = 1,
		}, frame)
		Theme.list(right, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)

		Theme.label({
			Name = "Now",
			Size = UDim2.fromOffset(0, 32),
			AutomaticSize = Enum.AutomaticSize.X,
			Text = tostring(row.now),
			TextSize = 20,
			TextColor3 = if atMax then C.text else C.textDim,
			LayoutOrder = 1,
		}, right)

		if atMax or row.next == nil then
			local badge = Theme.new("Frame", {
				Name = "Max",
				Size = UDim2.fromOffset(58, 28),
				BackgroundColor3 = C.star,
				LayoutOrder = 2,
			}, right)
			Theme.corner(badge, 14)
			local badgeText = Theme.label({
				Size = UDim2.fromScale(1, 1),
				TextSize = 16,
				TextColor3 = DARK_TEXT,
			}, badge)
			Localizer.bind(badgeText, "ui_max")
		else
			Theme.label({
				Name = "Arrow",
				Size = UDim2.fromOffset(0, 32),
				AutomaticSize = Enum.AutomaticSize.X,
				Text = "➜",
				TextSize = 22,
				TextColor3 = C.money,
				LayoutOrder = 2,
			}, right)
			Theme.label({
				Name = "Next",
				Size = UDim2.fromOffset(0, 32),
				AutomaticSize = Enum.AutomaticSize.X,
				Text = tostring(row.next),
				TextSize = 20,
				TextColor3 = C.money,
				LayoutOrder = 3,
			}, right)
		end
	end

	local function renderRows(rows: any, atMax: boolean)
		local parts: { string } = { if atMax then "max" else "up" }
		for _, row in rows do
			table.insert(parts, `{tostring(row.labelKey)}|{tostring(row.now)}|{tostring(row.next)}`)
		end
		local signature = table.concat(parts, ";")
		if signature == lastRowsSignature then
			return
		end
		lastRowsSignature = signature
		for _, child in rowsScroll:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for index, row in rows do
			buildRow(row, index, atMax)
		end
	end

	-- "Level up!" flourish: the new pip pops, a banner rises, the panel border flashes, confetti.
	local function flourish()
		local banner = Theme.label({
			Name = "LevelUpBanner",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, 120),
			Size = UDim2.new(1, -40, 0, 50),
			TextSize = 38,
			TextColor3 = C.star,
			TextStrokeColor3 = Color3.fromRGB(150, 80, 0),
			TextStrokeTransparency = 0.3,
			TextTransparency = 1,
			ZIndex = 10,
		}, body)
		Localizer.bind(banner, "upgrade_level_up")
		Theme.tween(banner, { TextTransparency = 0, Position = UDim2.new(0.5, 0, 0, 100) }, 0.3, Enum.EasingStyle.Back)
		task.delay(0.9, function()
			if banner.Parent then
				Theme.tween(banner, { TextTransparency = 1, TextStrokeTransparency = 1, Position = UDim2.new(0.5, 0, 0, 60) }, 0.6)
			end
		end)
		task.delay(1.6, function()
			banner:Destroy()
		end)

		local stroke = body:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = C.star
			stroke.Transparency = 0
			stroke.Thickness = 4
			Theme.tween(stroke, { Transparency = 0.75, Thickness = 1.5 }, 0.9)
			task.delay(0.9, function()
				stroke.Color = C.stroke
			end)
		end
		Effects.confetti(m.root, 28)
	end

	local function render()
		local snapshot: any = ClientState.snapshot
		local id = currentId
		if snapshot == nil or id == nil then
			return
		end
		local infos: any = snapshot.upgradeInfo
		local info: any = if type(infos) == "table" then infos[id] else nil
		content.Visible = info ~= nil
		if info == nil then
			return
		end

		local level: number = if type(info.level) == "number" then info.level else 1
		local maxLevel: number = if type(info.maxLevel) == "number" then info.maxLevel else PIP_COUNT
		local cost: number? = if type(info.cost) == "number" then info.cost else nil
		local atMax = cost == nil or level >= maxLevel
		local money: number = if type(snapshot.money) == "number" then snapshot.money else 0

		local leveledUp = lastLevel ~= nil and level > lastLevel and m.isOpen
		lastLevel = level
		setPips(level, maxLevel, if leveledUp then level else nil)
		renderRows(if type(info.rows) == "table" then info.rows else {}, atMax)
		if leveledUp then
			flourish()
		end

		if atMax or cost == nil then
			canBuy = false
			needLabel.Visible = false
			Localizer.bind(upgradeButton, "ui_max_level")
		else
			canBuy = money >= cost
			Localizer.bind(upgradeButton, "upgrade_button", Format.money(cost))
			needLabel.Visible = not canBuy
			if not canBuy then
				Localizer.bind(needLabel, "upgrade_need_more", Format.money(cost - money))
			end
		end
		styleButton()
	end

	upgradeButton.Activated:Connect(function()
		local id = currentId
		if busy or not canBuy or id == nil then
			return
		end
		busy = true
		styleButton()
		local ok, err = pcall(function()
			Remotes.get("Upgrade"):InvokeServer(id)
		end)
		if not ok then
			warn("[Upgrade] Upgrade failed: " .. tostring(err))
		end
		task.wait(0.25)
		busy = false
		render()
	end)

	openFor = function(id: string)
		currentId = id
		lastLevel = nil
		lastRowsSignature = nil
		Localizer.bind(nameLabel, "unlock_" .. id)
		render()
		m.open()
	end

	ClientState.onChanged(function()
		if m.isOpen then
			render()
		end
	end)

	Remotes.get("OpenUI").OnClientEvent:Connect(function(uiName: any, arg: any)
		if uiName == "Upgrade" and type(arg) == "string" then
			openFor(arg)
		end
	end)
end

return Upgrade
