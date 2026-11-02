--!strict
-- Garage themes window (HUD button or OpenUI("Themes")): one card per Config.Themes entry with a color
-- preview strip, price / Owned / Applied and a Buy / Apply button -> BuyTheme(id).
-- snapshot.themes = { current, owned = { [id] = true } }; the server sends the result toast.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes: any = require(Shared:WaitForChild("Remotes") :: ModuleScript)
local Format: any = require(Shared:WaitForChild("Format") :: ModuleScript)
local ThemeConfig: any = require(Shared:WaitForChild("Config"):WaitForChild("Themes") :: ModuleScript)
local Controllers = script.Parent :: Instance
local Client = Controllers.Parent :: Instance
local ClientState: any = require(Client:WaitForChild("ClientState") :: ModuleScript)
local Theme: any = require(Client:WaitForChild("Theme") :: ModuleScript)
local Localizer: any = require(Controllers:WaitForChild("Localizer") :: ModuleScript)

local Themes = {}

local CARD_MIN_WIDTH = 230
local CARD_MAX_WIDTH = 290
local CARD_HEIGHT = 250
local CARD_GAP = 14

local modal: any = nil

function Themes.open()
	if modal then
		modal.open()
	end
end

function Themes.close()
	if modal then
		modal.close()
	end
end

function Themes.toggle()
	if modal then
		modal.toggle()
	end
end

function Themes.start()
	local C = Theme.colors
	local m = Theme.modal("Themes", 21, 620, 580)
	modal = m
	local body = m.body

	local title = Theme.label({
		Name = "Title",
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(1, 0, 0, 40),
		TextSize = 30,
	}, body)
	Localizer.bind(title, "themes_title")

	local scroll = Theme.new("ScrollingFrame", {
		Name = "Cards",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 66),
		Size = UDim2.new(1, -32, 1, -66 - 88),
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = C.gray,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, body)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = scroll
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(CARD_MAX_WIDTH, CARD_HEIGHT)
	grid.CellPadding = UDim2.fromOffset(CARD_GAP, CARD_GAP)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.FillDirection = Enum.FillDirection.Horizontal
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.Parent = scroll

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

	local function layoutGrid()
		local size: Vector2 = m.targetSize()
		local available = size.X - 32 - 8 - 12
		local columns = math.max(1, math.floor((available + CARD_GAP) / (CARD_MIN_WIDTH + CARD_GAP)))
		local width = math.floor((available - CARD_GAP * (columns - 1)) / columns)
		grid.CellSize = UDim2.fromOffset(math.clamp(width, CARD_MIN_WIDTH, CARD_MAX_WIDTH), CARD_HEIGHT)
	end
	Theme.onViewport(function()
		layoutGrid()
	end)

	----------------------------------------------------------------- cards (built once, restyled on snapshots)
	local busy = false
	-- entry: { id, price, button, statusLabel }
	local entries: { { id: string, price: number, button: any, status: any, card: any, stroke: UIStroke } } = {}

	local function swatch(parent: Instance, index: number, color: Color3?): any
		local s = Theme.new("Frame", {
			Name = "Swatch" .. index,
			Position = UDim2.new((index - 1) / 4, 0, 0, 0),
			Size = UDim2.new(0.25, 0, 1, 0),
			BackgroundColor3 = color or C.text,
		}, parent)
		if color == nil then
			-- "your color": rainbow
			local gradient = Instance.new("UIGradient")
			gradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
				ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 205, 60)),
				ColorSequenceKeypoint.new(0.7, Color3.fromRGB(70, 200, 120)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 150, 255)),
			})
			gradient.Rotation = 45
			gradient.Parent = s
		end
		return s
	end

	for index, definition in ThemeConfig.list do
		local id: string = definition.id
		local price: number = if type(definition.price) == "number" then definition.price else 0

		local card = Theme.new("Frame", {
			Name = "Card_" .. id,
			BackgroundColor3 = C.panelLight,
			LayoutOrder = index,
		}, scroll)
		Theme.corner(card, 16)
		local cardStroke = Theme.stroke(card, C.stroke, 1.5, 0.75)

		local name = Theme.label({
			Name = "ThemeName",
			Position = UDim2.fromOffset(10, 10),
			Size = UDim2.new(1, -20, 0, 30),
			TextScaled = true,
		}, card)
		Theme.fitText(name, 13, 24)
		Localizer.bind(name, "theme_" .. id)

		-- preview strip: accent / wall / floor / roof
		local strip = Theme.new("Frame", {
			Name = "Preview",
			Position = UDim2.fromOffset(14, 48),
			Size = UDim2.new(1, -28, 0, 56),
			BackgroundColor3 = C.black,
			ClipsDescendants = true,
		}, card)
		Theme.corner(strip, 12)
		Theme.stroke(strip, C.text, 2, 0.7)
		swatch(strip, 1, definition.accent)
		swatch(strip, 2, definition.wall)
		swatch(strip, 3, definition.floor)
		swatch(strip, 4, definition.roof)

		local caption = Theme.label({
			Name = "Caption",
			Position = UDim2.fromOffset(14, 106),
			Size = UDim2.new(1, -28, 0, 20),
			Font = Theme.fontMedium,
			TextSize = 14,
			TextColor3 = C.textDim,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, card)
		if definition.accent == nil then
			Localizer.bind(caption, "themes_your_color")
		end

		local status = Theme.label({
			Name = "Status",
			Position = UDim2.fromOffset(10, 128),
			Size = UDim2.new(1, -20, 0, 30),
			TextSize = 22,
			TextColor3 = C.money,
		}, card)

		local button = Theme.button({
			Name = "ActionButton",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -12),
			Size = UDim2.new(1, -28, 0, Theme.buttonHeight),
			TextScaled = true,
			TextWrapped = true,
		}, card)
		Theme.fitText(button, 12, 24)

		local entry = { id = id, price = price, button = button, status = status, card = card, stroke = cardStroke }
		table.insert(entries, entry)
		button.Activated:Connect(function()
			if busy then
				return
			end
			local snapshot: any = ClientState.snapshot
			local themes: any = if snapshot then snapshot.themes else nil
			local owned = id == "Classic" or price == 0 or (type(themes) == "table" and type(themes.owned) == "table" and themes.owned[id] == true)
			local current = type(themes) == "table" and themes.current == id
			local money: number = if snapshot and type(snapshot.money) == "number" then snapshot.money else 0
			if current or (not owned and money < price) then
				return
			end
			busy = true
			local ok, err = pcall(function()
				Remotes.get("BuyTheme"):InvokeServer(id)
			end)
			if not ok then
				warn("[Themes] BuyTheme failed: " .. tostring(err))
			end
			task.wait(0.25)
			busy = false
		end)
	end

	local function render()
		local snapshot: any = ClientState.snapshot
		if snapshot == nil then
			return
		end
		local themes: any = snapshot.themes
		local ownedMap: any = if type(themes) == "table" and type(themes.owned) == "table" then themes.owned else {}
		local currentId: any = if type(themes) == "table" then themes.current else nil
		local money: number = if type(snapshot.money) == "number" then snapshot.money else 0

		for _, entry in entries do
			local owned = ownedMap[entry.id] == true or entry.price == 0
			local applied = currentId == entry.id
			local affordable = money >= entry.price

			if applied then
				Localizer.bind(entry.status, "ui_applied")
				entry.status.TextColor3 = C.star
				Localizer.bind(entry.button, "ui_applied")
			elseif owned then
				Localizer.bind(entry.status, "ui_owned")
				entry.status.TextColor3 = C.money
				Localizer.bind(entry.button, "themes_apply")
			else
				Localizer.bind(entry.status, "themes_price", Format.money(entry.price))
				entry.status.TextColor3 = if affordable then C.money else C.danger
				Localizer.bind(entry.button, "themes_buy", Format.money(entry.price))
			end

			local enabled = (owned and not applied) or (not owned and affordable)
			entry.button.AutoButtonColor = enabled
			Theme.tween(entry.button, {
				BackgroundColor3 = if enabled then C.accent elseif applied then Color3.fromRGB(46, 96, 64) else C.gray,
				TextColor3 = if enabled then C.text else C.textDim,
			}, 0.15)
			entry.stroke.Color = if applied then C.star else C.stroke
			entry.stroke.Thickness = if applied then 3 else 1.5
			entry.stroke.Transparency = if applied then 0 else 0.75
		end
	end

	m.onOpen = function()
		layoutGrid()
		render()
	end

	ClientState.onChanged(function()
		if m.isOpen then
			render()
		end
	end)

	Remotes.get("OpenUI").OnClientEvent:Connect(function(uiName: any)
		if uiName == "Themes" then
			m.open()
		end
	end)
end

return Themes
