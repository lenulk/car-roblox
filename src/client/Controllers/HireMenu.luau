--!strict
-- Hire window, opened by the server with OpenUI("Hire"). Cards come from snapshot.hireOptions.
-- The server answers a hire with a Notify toast, so no extra toast is shown here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes: any = require(Shared:WaitForChild("Remotes") :: ModuleScript)
local Format: any = require(Shared:WaitForChild("Format") :: ModuleScript)
local Employees: any = require(Shared:WaitForChild("Config"):WaitForChild("Employees") :: ModuleScript)
local Client = (script.Parent :: Instance).Parent :: Instance
local ClientState: any = require(Client:WaitForChild("ClientState") :: ModuleScript)
local Theme: any = require(Client:WaitForChild("Theme") :: ModuleScript)
local Localizer: any = require((script.Parent :: Instance):WaitForChild("Localizer") :: ModuleScript)

local HireMenu = {}

local CARD_WIDTH = 240
local CARD_HEIGHT = 320
local CARD_GAP = 16
local SKIN = Color3.fromRGB(255, 214, 170)

function HireMenu.start()
	local C = Theme.colors
	local m = Theme.modal("HireMenu", 20, 580, 500)
	local body = m.body

	local title = Theme.label({
		Name = "Title",
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(1, 0, 0, 40),
		TextSize = 30,
	}, body)
	Localizer.bind(title, "hire_title")

	local scroll = Theme.new("ScrollingFrame", {
		Name = "Cards",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 64),
		Size = UDim2.new(1, -32, 1, -152),
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = C.gray,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.XY,
		ScrollingDirection = Enum.ScrollingDirection.XY,
	}, body)
	Theme.list(scroll, Enum.FillDirection.Horizontal, CARD_GAP, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)
	local scrollPadding = Theme.padding(scroll, 4, 0)

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
	local lastSignature: string? = nil
	local entries: { { button: any, available: boolean } } = {}
	local cardCount = 0

	local function styleButton(entry: { button: any, available: boolean })
		local enabled = entry.available and not busy
		entry.button.AutoButtonColor = enabled
		Theme.tween(entry.button, {
			BackgroundColor3 = if enabled then C.accent else C.gray,
			TextColor3 = if enabled then C.text else C.textDim,
		}, 0.15)
	end

	local function refreshButtons()
		for _, entry in entries do
			styleButton(entry)
		end
	end

	-- Cards are centered by hand (a ScrollingFrame left-aligns its canvas).
	local function recenter()
		local size: Vector2 = m.targetSize()
		local available = size.X - 32
		local contentWidth = cardCount * CARD_WIDTH + math.max(0, cardCount - 1) * CARD_GAP
		scrollPadding.PaddingLeft = UDim.new(0, math.max(0, math.floor((available - contentWidth) / 2)))
	end
	Theme.onViewport(function()
		recenter()
	end)

	local function hire(role: string)
		if busy then
			return
		end
		busy = true
		refreshButtons()
		local ok, err = pcall(function()
			Remotes.get("HireEmployee"):InvokeServer(role)
		end)
		if not ok then
			warn("[HireMenu] HireEmployee failed: " .. tostring(err))
		end
		task.wait(0.25)
		busy = false
		refreshButtons()
	end

	----------------------------------------------------------------- cards
	local function buildCard(option: any, index: number)
		local role: string = tostring(option.role)
		local definition = Employees.byId[role]
		local shirt: Color3 = if definition then definition.shirtColor else C.gray
		local price: number = if type(option.price) == "number" then option.price else 0
		local available: boolean = option.available ~= false

		local card = Theme.new("Frame", {
			Name = "Card_" .. role,
			BackgroundColor3 = C.panelLight,
			Size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT),
			LayoutOrder = index,
		}, scroll)
		Theme.corner(card, 16)
		Theme.stroke(card, C.stroke, 1.5, 0.75)

		-- simple character icon: colored badge, head, shoulders
		local badge = Theme.new("Frame", {
			Name = "Icon",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 14),
			Size = UDim2.fromOffset(76, 76),
			BackgroundColor3 = shirt,
		}, card)
		Theme.corner(badge, 38)
		Theme.stroke(badge, C.text, 2, 0.6)
		local head = Theme.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 15),
			Size = UDim2.fromOffset(24, 24),
			BackgroundColor3 = SKIN,
		}, badge)
		Theme.corner(head, 12)
		local torso = Theme.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 41),
			Size = UDim2.fromOffset(40, 22),
			BackgroundColor3 = C.text,
			BackgroundTransparency = 0.15,
		}, badge)
		Theme.corner(torso, 10)

		local name = Theme.label({
			Name = "RoleName",
			Position = UDim2.fromOffset(0, 98),
			Size = UDim2.new(1, 0, 0, 30),
			TextSize = 24,
		}, card)
		Localizer.bind(name, "role_" .. role)

		local description = Theme.label({
			Name = "Description",
			Position = UDim2.fromOffset(12, 130),
			Size = UDim2.new(1, -24, 0, 54),
			Font = Theme.fontRegular,
			TextColor3 = C.textDim,
			TextScaled = true,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
		}, card)
		Theme.fitText(description, 11, 16)
		Localizer.bind(description, "role_" .. role .. "_desc")

		-- price / free badge / reason
		if not available and type(option.reasonKey) == "string" then
			local reason = Theme.label({
				Name = "Reason",
				Position = UDim2.fromOffset(12, 190),
				Size = UDim2.new(1, -24, 0, 46),
				TextColor3 = C.danger,
				TextScaled = true,
				TextWrapped = true,
			}, card)
			Theme.fitText(reason, 11, 17)
			Localizer.bind(reason, option.reasonKey)
		elseif price == 0 then
			local freeBadge = Theme.new("Frame", {
				Name = "FreeBadge",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 192),
				Size = UDim2.fromOffset(150, 42),
				BackgroundColor3 = C.star,
			}, card)
			Theme.corner(freeBadge, 21)
			local freeText = Theme.label({
				Size = UDim2.fromScale(1, 1),
				TextSize = 26,
				TextColor3 = C.panel,
			}, freeBadge)
			Localizer.bind(freeText, "hire_free_badge")
		else
			local priceLabel = Theme.label({
				Name = "Price",
				Position = UDim2.fromOffset(0, 194),
				Size = UDim2.new(1, 0, 0, 36),
				TextSize = 24,
				TextColor3 = C.money,
			}, card)
			Localizer.bind(priceLabel, "hire_price", Format.money(price))
		end

		local hireButton = Theme.button({
			Name = "HireButton",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -14),
			Size = UDim2.new(1, -28, 0, Theme.buttonHeight),
			TextSize = 26,
		}, card)
		Localizer.bind(hireButton, "hire_button")

		local entry = { button = hireButton, available = available }
		table.insert(entries, entry)
		hireButton.Activated:Connect(function()
			if available and not busy then
				hire(role)
			end
		end)
	end

	local function signature(options: any): string
		local parts: { string } = {}
		for _, option in options do
			table.insert(
				parts,
				`{tostring(option.role)}|{tostring(option.price)}|{tostring(option.available)}|{tostring(option.reasonKey)}`
			)
		end
		return table.concat(parts, ";")
	end

	local function render()
		local snapshot: any = ClientState.snapshot
		local options: any = if snapshot and snapshot.hireOptions then snapshot.hireOptions else {}
		local sig = signature(options)
		if sig == lastSignature then
			return
		end
		lastSignature = sig
		for _, child in scroll:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		entries = {}
		cardCount = 0
		for index, option in options do
			buildCard(option, index)
			cardCount += 1
		end
		recenter()
		refreshButtons()
	end

	m.onOpen = function()
		render()
		recenter()
	end

	ClientState.onChanged(function()
		if m.isOpen then
			render()
		end
	end)

	Remotes.get("OpenUI").OnClientEvent:Connect(function(uiName: any)
		if uiName == "Hire" then
			m.open()
		end
	end)
end

return HireMenu
