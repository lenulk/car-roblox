--!strict
-- Staff window, opened by the server with OpenUI("Hire"). Two tabs:
--   Hire     - one card per snapshot.hireOptions entry (scrolling grid, fits 6+ roles)
--   My staff - one row per snapshot.employees entry with level pips and an Upgrade button
-- The server answers every action with a Notify toast, so no extra toast is shown here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes: any = require(Shared:WaitForChild("Remotes") :: ModuleScript)
local Format: any = require(Shared:WaitForChild("Format") :: ModuleScript)
local Employees: any = require(Shared:WaitForChild("Config"):WaitForChild("Employees") :: ModuleScript)
local Game: any = require(Shared:WaitForChild("Config"):WaitForChild("Game") :: ModuleScript)
local Client = (script.Parent :: Instance).Parent :: Instance
local ClientState: any = require(Client:WaitForChild("ClientState") :: ModuleScript)
local Theme: any = require(Client:WaitForChild("Theme") :: ModuleScript)
local Localizer: any = require((script.Parent :: Instance):WaitForChild("Localizer") :: ModuleScript)

local HireMenu = {}

local CARD_MIN_WIDTH = 210
local CARD_MAX_WIDTH = 300
local CARD_HEIGHT = 310
local CARD_GAP = 14
local ROW_HEIGHT = 92
local MAX_LEVEL = 5
local SKIN = Color3.fromRGB(255, 214, 170)
local DARK_TEXT = Color3.fromRGB(60, 40, 0)
local EFFECT_LINE = 20

local function num(x: number): string
	return string.format("%g", math.floor(x * 1000 + 0.5) / 1000)
end

local function percent(x: number): string
	return num(x * 100) .. "%"
end

local function plusPercent(x: number): string
	return "+" .. percent(x)
end

local function times(x: number): string
	return "x" .. num(x)
end

type Effect = { key: string, values: { number }, format: (number) -> string }

-- What each level does per role (numbers straight from Config/Game, indexed by employee level).
local EFFECTS: { [string]: { Effect } } = {
	mechanic = { { key = "staff_effect_repair", values = Game.MECHANIC_SPEED, format = percent } },
	painter = { { key = "staff_effect_repair", values = Game.MECHANIC_SPEED, format = percent } },
	cashier = { { key = "staff_effect_income", values = Game.CASHIER_BONUS, format = plusPercent } },
	stocker = { { key = "staff_effect_restock", values = Game.STOCKER_SPEED, format = times } },
	receptionist = {
		{ key = "staff_effect_spawn", values = Game.RECEPTION_SPAWN_MULT, format = times },
		{ key = "staff_effect_tip", values = Game.RECEPTION_TIP_BONUS, format = plusPercent },
	},
	manager = { { key = "staff_effect_manager", values = Game.MANAGER_SPEED, format = plusPercent } },
}

-- "now → next" (just "now" at max level).
local function effectChange(effect: Effect, level: number): string
	local values = effect.values
	local now = values[math.clamp(level, 1, #values)]
	local nxt = if level < MAX_LEVEL then values[level + 1] else nil
	if nxt == nil then
		return effect.format(now)
	end
	return effect.format(now) .. " → " .. effect.format(nxt)
end

-- Round character badge: colored circle, head, shoulders. `size` is the diameter in pixels.
local function makeIcon(parent: Instance, size: number, shirt: Color3, props: { [string]: any }?): any
	local C = Theme.colors
	local badge = Theme.new("Frame", {
		Name = "Icon",
		BackgroundColor3 = shirt,
		Size = UDim2.fromOffset(size, size),
	}, parent)
	if props then
		for k, v in props do
			badge[k] = v
		end
	end
	Theme.corner(badge, math.floor(size / 2))
	Theme.stroke(badge, C.text, 2, 0.6)
	local head = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, math.floor(size * 0.2)),
		Size = UDim2.fromOffset(math.floor(size * 0.32), math.floor(size * 0.32)),
		BackgroundColor3 = SKIN,
	}, badge)
	Theme.corner(head, math.floor(size * 0.16))
	local torso = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, math.floor(size * 0.54)),
		Size = UDim2.fromOffset(math.floor(size * 0.52), math.floor(size * 0.29)),
		BackgroundColor3 = C.text,
		BackgroundTransparency = 0.15,
	}, badge)
	Theme.corner(torso, math.floor(size * 0.13))
	return badge
end

function HireMenu.start()
	local C = Theme.colors
	local m = Theme.modal("HireMenu", 20, 620, 590)
	local body = m.body

	local title = Theme.label({
		Name = "Title",
		Position = UDim2.fromOffset(0, 12),
		Size = UDim2.new(1, 0, 0, 40),
		TextSize = 30,
	}, body)
	Localizer.bind(title, "hire_title")

	----------------------------------------------------------------- tabs
	local tabBar = Theme.new("Frame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 58),
		Size = UDim2.new(1, -32, 0, 56),
	}, body)
	local hireTab = Theme.button({
		Name = "HireTab",
		Size = UDim2.new(0.5, -6, 1, 0),
		TextSize = 22,
	}, tabBar)
	Localizer.bind(hireTab, "hire_tab_hire")
	local staffTab = Theme.button({
		Name = "StaffTab",
		Position = UDim2.new(0.5, 6, 0, 0),
		Size = UDim2.new(0.5, -6, 1, 0),
		TextSize = 22,
	}, tabBar)
	Localizer.bind(staffTab, "hire_tab_staff")

	----------------------------------------------------------------- scrolling areas
	local function makeScroll(name: string): any
		local scroll = Theme.new("ScrollingFrame", {
			Name = name,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(16, 124),
			Size = UDim2.new(1, -32, 1, -124 - 88),
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
		return scroll
	end

	local hireScroll = makeScroll("HireCards")
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(CARD_MAX_WIDTH, CARD_HEIGHT)
	grid.CellPadding = UDim2.fromOffset(CARD_GAP, CARD_GAP)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.FillDirection = Enum.FillDirection.Horizontal
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.Parent = hireScroll

	local staffScroll = makeScroll("StaffRows")
	staffScroll.Visible = false
	Theme.list(staffScroll, Enum.FillDirection.Vertical, 10)

	local emptyLabel = Theme.label({
		Name = "Empty",
		Position = UDim2.fromOffset(32, 150),
		Size = UDim2.new(1, -64, 0, 90),
		Font = Theme.fontMedium,
		TextColor3 = C.textDim,
		TextScaled = true,
		TextWrapped = true,
		Visible = false,
	}, body)
	Theme.fitText(emptyLabel, 13, 20)
	Localizer.bind(emptyLabel, "staff_empty")

	local closeButton = Theme.button({
		Name = "Close",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
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
	local currentTab = "hire"
	local lastHireSignature: string? = nil
	local lastStaffSignature: string? = nil
	local hireEntries: { { button: any, available: boolean } } = {}
	local staffEntries: { { button: any, cost: number } } = {}
	local staffCount = 0

	local function updateEmpty()
		emptyLabel.Visible = currentTab == "staff" and staffCount == 0
	end

	local function setTab(name: string)
		currentTab = name
		hireScroll.Visible = name == "hire"
		staffScroll.Visible = name == "staff"
		for tab, button in { hire = hireTab, staff = staffTab } do
			local selected = tab == name
			Theme.tween(button, {
				BackgroundColor3 = if selected then C.accent else C.panelLighter,
				TextColor3 = if selected then C.text else C.textDim,
			}, 0.15)
		end
		updateEmpty()
	end
	hireTab.Activated:Connect(function()
		setTab("hire")
	end)
	staffTab.Activated:Connect(function()
		setTab("staff")
	end)

	local function money(): number
		local snapshot: any = ClientState.snapshot
		return if snapshot and type(snapshot.money) == "number" then snapshot.money else 0
	end

	local function styleButton(button: any, enabled: boolean)
		button.AutoButtonColor = enabled
		Theme.tween(button, {
			BackgroundColor3 = if enabled then C.accent else C.gray,
			TextColor3 = if enabled then C.text else C.textDim,
		}, 0.15)
	end

	local function refreshButtons()
		for _, entry in hireEntries do
			styleButton(entry.button, entry.available and not busy)
		end
		local wallet = money()
		for _, entry in staffEntries do
			styleButton(entry.button, wallet >= entry.cost and not busy)
		end
	end

	-- Cards per row follow the modal width (1 column on narrow phones, 2 on wide screens).
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

	local function invoke(remoteName: string, argument: string)
		if busy then
			return
		end
		busy = true
		refreshButtons()
		local ok, err = pcall(function()
			Remotes.get(remoteName):InvokeServer(argument)
		end)
		if not ok then
			warn(`[HireMenu] {remoteName} failed: {tostring(err)}`)
		end
		task.wait(0.25)
		busy = false
		refreshButtons()
	end

	----------------------------------------------------------------- hire cards
	local function buildCard(option: any, index: number)
		local role: string = tostring(option.role)
		local definition = Employees.byId[role]
		local shirt: Color3 = if definition then definition.shirtColor else C.gray
		local price: number = if type(option.price) == "number" then option.price else 0
		local available: boolean = option.available ~= false

		local card = Theme.new("Frame", {
			Name = "Card_" .. role,
			BackgroundColor3 = C.panelLight,
			LayoutOrder = index,
		}, hireScroll)
		Theme.corner(card, 16)
		Theme.stroke(card, C.stroke, 1.5, 0.75)

		local icon = makeIcon(card, 76, shirt, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 12),
		})
		icon.Name = "Icon"

		local name = Theme.label({
			Name = "RoleName",
			Position = UDim2.fromOffset(0, 94),
			Size = UDim2.new(1, 0, 0, 30),
			TextSize = 24,
		}, card)
		Localizer.bind(name, "role_" .. role)

		local description = Theme.label({
			Name = "Description",
			Position = UDim2.fromOffset(12, 126),
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
				Position = UDim2.fromOffset(12, 184),
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
				Position = UDim2.new(0.5, 0, 0, 186),
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
				Position = UDim2.fromOffset(0, 188),
				Size = UDim2.new(1, 0, 0, 36),
				TextSize = 24,
				TextColor3 = C.money,
			}, card)
			Localizer.bind(priceLabel, "hire_price", Format.money(price))
		end

		local hireButton = Theme.button({
			Name = "HireButton",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -12),
			Size = UDim2.new(1, -28, 0, Theme.buttonHeight),
			TextSize = 26,
		}, card)
		Localizer.bind(hireButton, "hire_button")

		table.insert(hireEntries, { button = hireButton, available = available })
		hireButton.Activated:Connect(function()
			if available and not busy then
				invoke("HireEmployee", role)
			end
		end)
	end

	local function renderHire(snapshot: any)
		local options: any = if snapshot and type(snapshot.hireOptions) == "table" then snapshot.hireOptions else {}
		local parts: { string } = {}
		for _, option in options do
			table.insert(
				parts,
				`{tostring(option.role)}|{tostring(option.price)}|{tostring(option.available)}|{tostring(option.reasonKey)}`
			)
		end
		local signature = table.concat(parts, ";")
		if signature == lastHireSignature then
			return
		end
		lastHireSignature = signature
		for _, child in hireScroll:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		hireEntries = {}
		for index, option in options do
			buildCard(option, index)
		end
		layoutGrid()
	end

	----------------------------------------------------------------- staff rows
	local function buildPips(parent: Instance, level: number)
		local row = Theme.new("Frame", {
			Name = "Pips",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(82, 66),
			Size = UDim2.new(1, -240, 0, 14),
		}, parent)
		Theme.list(row, Enum.FillDirection.Horizontal, 5, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
		for i = 1, MAX_LEVEL do
			local pip = Theme.new("Frame", {
				Size = UDim2.fromOffset(14, 14),
				BackgroundColor3 = if i <= level then C.star else C.starDim,
				LayoutOrder = i,
			}, row)
			Theme.corner(pip, 7)
		end
	end

	local function buildStaffRow(employee: any, index: number)
		local role: string = tostring(employee.role)
		local slot: string = tostring(employee.slot)
		local level: number = if type(employee.level) == "number" then employee.level else 1
		local cost: number? = if type(employee.upgradeCost) == "number" then employee.upgradeCost else nil
		local definition = Employees.byId[role]
		local shirt: Color3 = if definition then definition.shirtColor else C.gray
		local effects: { Effect } = EFFECTS[role] or {}
		local rowHeight = if #effects > 0 then 84 + EFFECT_LINE * #effects + 8 else ROW_HEIGHT

		local row = Theme.new("Frame", {
			Name = "Staff_" .. slot,
			BackgroundColor3 = C.panelLight,
			Size = UDim2.new(1, 0, 0, rowHeight),
			LayoutOrder = index,
		}, staffScroll)
		Theme.corner(row, 16)
		Theme.stroke(row, C.stroke, 1.5, 0.75)

		makeIcon(row, 58, shirt, { Position = UDim2.fromOffset(14, math.floor((rowHeight - 58) / 2)) })

		local name = Theme.label({
			Name = "RoleName",
			Position = UDim2.fromOffset(82, 10),
			Size = UDim2.new(1, -240, 0, 28),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextScaled = true,
		}, row)
		Theme.fitText(name, 13, 23)
		Localizer.bind(name, "role_" .. role)

		local slotLabel = Theme.label({
			Name = "Slot",
			Position = UDim2.fromOffset(82, 40),
			Size = UDim2.new(1, -240, 0, 20),
			Font = Theme.fontMedium,
			TextColor3 = C.textDim,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, row)
		Theme.fitText(slotLabel, 11, 16)
		local bayNumber = string.match(slot, "^Bay(%d+)$")
		if bayNumber then
			Localizer.bind(slotLabel, "staff_slot_bay", bayNumber)
		elseif Localizer.t("staff_slot_" .. slot) ~= "staff_slot_" .. slot then
			Localizer.bind(slotLabel, "staff_slot_" .. slot)
		else
			slotLabel.Text = slot
		end

		buildPips(row, level)

		for i, effect in effects do
			local effectLabel = Theme.label({
				Name = "Effect",
				Position = UDim2.fromOffset(82, 84 + (i - 1) * EFFECT_LINE),
				Size = UDim2.new(1, -240, 0, EFFECT_LINE),
				Font = Theme.fontMedium,
				TextColor3 = C.money,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
			}, row)
			Theme.fitText(effectLabel, 11, 16)
			Localizer.bind(effectLabel, effect.key, effectChange(effect, level))
		end

		if cost ~= nil and level < MAX_LEVEL then
			local button = Theme.button({
				Name = "UpgradeButton",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -14, 0.5, 0),
				Size = UDim2.fromOffset(136, 60),
				TextScaled = true,
				TextWrapped = true,
			}, row)
			Theme.fitText(button, 11, 20)
			Localizer.bind(button, "upgrade_button", Format.money(cost))
			table.insert(staffEntries, { button = button, cost = cost })
			button.Activated:Connect(function()
				if not busy and money() >= cost then
					invoke("UpgradeEmployee", slot)
				end
			end)
		else
			local badge = Theme.new("Frame", {
				Name = "MaxBadge",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -14, 0.5, 0),
				Size = UDim2.fromOffset(110, 48),
				BackgroundColor3 = C.star,
			}, row)
			Theme.corner(badge, 24)
			local badgeText = Theme.label({
				Size = UDim2.fromScale(1, 1),
				TextSize = 24,
				TextColor3 = DARK_TEXT,
			}, badge)
			Localizer.bind(badgeText, "ui_max")
		end
	end

	local function renderStaff(snapshot: any)
		local employees: any = if snapshot and type(snapshot.employees) == "table" then snapshot.employees else {}
		local parts: { string } = {}
		for _, employee in employees do
			table.insert(
				parts,
				`{tostring(employee.role)}|{tostring(employee.slot)}|{tostring(employee.level)}|{tostring(employee.upgradeCost)}`
			)
		end
		local signature = table.concat(parts, ";")
		if signature == lastStaffSignature then
			return
		end
		lastStaffSignature = signature
		for _, child in staffScroll:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		staffEntries = {}
		staffCount = 0
		for index, employee in employees do
			buildStaffRow(employee, index)
			staffCount += 1
		end
		updateEmpty()
	end

	local function render()
		local snapshot: any = ClientState.snapshot
		renderHire(snapshot)
		renderStaff(snapshot)
		refreshButtons()
	end

	m.onOpen = function()
		render()
		layoutGrid()
	end

	ClientState.onChanged(function()
		if m.isOpen then
			render()
		end
	end)

	Remotes.get("OpenUI").OnClientEvent:Connect(function(uiName: any)
		if uiName == "Hire" then
			setTab("hire")
			m.open()
		end
	end)

	setTab("hire")
end

return HireMenu
