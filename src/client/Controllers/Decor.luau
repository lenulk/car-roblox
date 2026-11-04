--!strict
-- Storefront decoration window. The server opens it with OpenUI("Decor", slot) when the owner uses the
-- "Decorate" prompt at one of the six decor spots in front of the garage.
-- One card per Config/Decor item: buy (money -> BuyDecor, Robux -> product prompt), place / move here / remove (PlaceDecor).
-- snapshot.decor = { owned = { [id] = true }, placed = { ["1".."6"] = id }, bonus = 0..MAX, queueFull = bool }.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes: any = require(Shared:WaitForChild("Remotes") :: ModuleScript)
local Format: any = require(Shared:WaitForChild("Format") :: ModuleScript)
local DecorConfig: any = require(Shared:WaitForChild("Config"):WaitForChild("Decor") :: ModuleScript)
local Controllers = script.Parent :: Instance
local Client = Controllers.Parent :: Instance
local ClientState: any = require(Client:WaitForChild("ClientState") :: ModuleScript)
local Theme: any = require(Client:WaitForChild("Theme") :: ModuleScript)
local RobuxBuy: any = require(Client:WaitForChild("RobuxBuy") :: ModuleScript)
local Localizer: any = require(Controllers:WaitForChild("Localizer") :: ModuleScript)

local Decor = {}

local GREEN = Color3.fromRGB(52, 176, 96)
local CARD_HEIGHT = 168

local ICONS: { [string]: string } = {
	Bunting = "🎏",
	OpenSign = "🪧",
	TubeMan = "🕺",
	BalloonArch = "🎈",
	ClassicStatue = "🚗",
	Searchlight = "🔦",
	MascotBear = "🐻",
	MechRobot = "🤖",
	NeonDragon = "🐉",
	GoldStatue = "🏆",
	Fireworks = "🎆",
}

local modal: any = nil
local currentSlot = 1
local rebuild: (() -> ())? = nil -- set by start(): re-renders the window (used when another slot's prompt is used while open)

function Decor.open(slot: number?)
	if not modal then
		return
	end
	if type(slot) == "number" and slot >= 1 and slot <= DecorConfig.SLOTS then
		currentSlot = math.floor(slot)
	end
	if modal.isOpen and rebuild then
		rebuild()
	end
	modal.open()
end

function Decor.close()
	if modal then
		modal.close()
	end
end

function Decor.start()
	local C = Theme.colors

	local m = Theme.modal("Decor", 21, 640, 600)
	modal = m
	local body = m.body

	local title = Theme.label({
		Name = "Title",
		Position = UDim2.fromOffset(0, 10),
		Size = UDim2.new(1, 0, 0, 36),
		TextSize = 30,
	}, body)
	Localizer.bind(title, "decor_title")

	local slotLabel = Theme.label({
		Name = "Slot",
		Position = UDim2.fromOffset(0, 44),
		Size = UDim2.new(1, 0, 0, 20),
		Font = Theme.fontMedium,
		TextSize = 16,
		TextColor3 = C.textDim,
	}, body)

	local bonusLabel = Theme.label({
		Name = "Bonus",
		Position = UDim2.fromOffset(16, 68),
		Size = UDim2.new(1, -32, 0, 26),
		TextScaled = true,
		TextColor3 = C.money,
	}, body)
	Theme.fitText(bonusLabel, 12, 20)

	local hintLabel = Theme.label({
		Name = "ParkingHint",
		Position = UDim2.fromOffset(16, 96),
		Size = UDim2.new(1, -32, 0, 22),
		Font = Theme.fontMedium,
		TextScaled = true,
		TextColor3 = C.star,
		Visible = false,
	}, body)
	Theme.fitText(hintLabel, 11, 16)
	Localizer.bind(hintLabel, "decor_hint_parking")

	local scroll = Theme.new("ScrollingFrame", {
		Name = "Items",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 124),
		Size = UDim2.new(1, -32, 1, -124 - 80),
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = C.gray,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, body)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = scroll
	local grid = Instance.new("UIGridLayout")
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.CellSize = UDim2.new(0.5, -5, 0, CARD_HEIGHT)
	grid.Parent = scroll

	local closeButton = Theme.button({
		Name = "Close",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(220, 56),
		BackgroundColor3 = C.gray,
		TextSize = 24,
	}, body)
	Localizer.bind(closeButton, "close")
	closeButton.Activated:Connect(function()
		m.close()
	end)

	Theme.onViewport(function()
		local compact: boolean = Theme.isCompact()
		grid.CellSize = if compact then UDim2.new(1, -2, 0, CARD_HEIGHT) else UDim2.new(0.5, -5, 0, CARD_HEIGHT)
	end)

	----------------------------------------------------------------- server calls
	local busy = false
	local function call(remoteName: string, ...: any)
		if busy then
			return
		end
		busy = true
		local args = table.pack(...)
		local ok, err = pcall(function()
			local remote: any = Remotes.get(remoteName)
			remote:InvokeServer(table.unpack(args, 1, args.n))
		end)
		if not ok then
			warn("[Decor] " .. remoteName .. " failed: " .. tostring(err))
		end
		task.wait(0.2)
		busy = false
	end

	----------------------------------------------------------------- cards
	local function snapshotDecor(): (any, any)
		local snapshot: any = ClientState.snapshot or {}
		local decor: any = snapshot.decor
		local owned: any = if type(decor) == "table" and type(decor.owned) == "table" then decor.owned else {}
		local placed: any = if type(decor) == "table" and type(decor.placed) == "table" then decor.placed else {}
		return owned, placed
	end

	local function visibleItem(item: any, owned: any): boolean
		return item.robuxProduct == nil or owned[item.id] == true or RobuxBuy.available(item.robuxProduct)
	end

	local refresh: () -> ()

	local function buildCard(item: any, order: number, owned: any, placed: any, money: number)
		local id: string = item.id
		local isOwned = owned[id] == true
		local placedSlot: number? = nil
		for key, placedId in placed do
			if placedId == id then
				placedSlot = tonumber(key)
			end
		end
		local hereId: any = placed[tostring(currentSlot)]
		local isHere = hereId == id
		local robuxProduct: string? = item.robuxProduct

		local card = Theme.new("Frame", {
			Name = "Card_" .. id,
			BackgroundColor3 = if isHere then C.panelLighter else C.panelLight,
			LayoutOrder = order,
		}, scroll)
		Theme.corner(card, 16)
		if robuxProduct and not isOwned then
			Theme.stroke(card, RobuxBuy.GOLD, 3, 0) -- Robux decoration: gold border
		elseif isHere then
			Theme.stroke(card, C.accent, 3, 0)
		else
			Theme.stroke(card, C.stroke, 1.5, 0.75)
		end

		local iconBadge = Theme.new("Frame", {
			Name = "Icon",
			Position = UDim2.fromOffset(10, 10),
			Size = UDim2.fromOffset(52, 52),
			BackgroundColor3 = C.panelLighter,
		}, card)
		Theme.corner(iconBadge, 26)
		Theme.stroke(iconBadge, if robuxProduct then RobuxBuy.GOLD else C.stroke, 2, 0.4)
		Theme.label({
			Size = UDim2.fromScale(1, 1),
			Text = ICONS[id] or "★",
			TextSize = 28,
		}, iconBadge)

		local nameLabel = Theme.label({
			Name = "ItemName",
			Position = UDim2.fromOffset(70, 8),
			Size = UDim2.new(1, -80, 0, 26),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextScaled = true,
		}, card)
		Theme.fitText(nameLabel, 12, 22)
		Localizer.bind(nameLabel, "decor_" .. id)

		local bonusText = Theme.label({
			Name = "ItemBonus",
			Position = UDim2.fromOffset(70, 36),
			Size = UDim2.new(1, -80, 0, 22),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextScaled = true,
			TextColor3 = C.money,
		}, card)
		Theme.fitText(bonusText, 11, 18)
		Localizer.bind(bonusText, "decor_customers", math.floor(item.bonus * 100 + 0.5))

		local status = Theme.label({
			Name = "ItemStatus",
			Position = UDim2.fromOffset(10, 70),
			Size = UDim2.new(1, -20, 0, 22),
			Font = Theme.fontMedium,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextScaled = true,
		}, card)
		Theme.fitText(status, 11, 17)

		local button = Theme.button({
			Name = "ActionButton",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -10),
			Size = UDim2.new(1, -20, 0, 52),
			TextScaled = true,
		}, card)
		Theme.fitText(button, 12, 22)

		if not isOwned then
			if robuxProduct then
				status.TextColor3 = RobuxBuy.GOLD
				Localizer.bind(status, "ui_robux_only")
				button.BackgroundColor3 = RobuxBuy.BUTTON
				Localizer.bind(button, "tuning_buy", RobuxBuy.priceText(robuxProduct, function()
					if m.isOpen then
						refresh()
					end
				end))
				button.Activated:Connect(function()
					RobuxBuy.buy(robuxProduct)
				end)
			else
				local price: number = item.price or 0
				local affordable = money >= price
				status.TextColor3 = if affordable then C.money else C.danger
				status.Text = Format.money(price)
				button.BackgroundColor3 = if affordable then C.accent else C.gray
				Localizer.bind(button, "tuning_buy", Format.money(price))
				button.Activated:Connect(function()
					task.spawn(call, "BuyDecor", id)
				end)
			end
		else
			if isHere then
				status.TextColor3 = C.star
				Localizer.bind(status, "decor_here")
				button.BackgroundColor3 = C.gray
				Localizer.bind(button, "decor_remove")
				button.Activated:Connect(function()
					task.spawn(call, "PlaceDecor", currentSlot, nil)
				end)
			else
				if placedSlot then
					status.TextColor3 = C.textDim
					Localizer.bind(status, "decor_in_slot", placedSlot)
				else
					status.TextColor3 = C.money
					Localizer.bind(status, "ui_owned")
				end
				button.BackgroundColor3 = GREEN
				Localizer.bind(button, if placedSlot then "decor_move" else "decor_place")
				button.Activated:Connect(function()
					task.spawn(call, "PlaceDecor", currentSlot, id)
				end)
			end
		end
	end

	local lastSignature = ""

	local function signature(): string
		local owned, placed = snapshotDecor()
		local snapshot: any = ClientState.snapshot or {}
		local money: number = if type(snapshot.money) == "number" then snapshot.money else 0
		local affordable: { boolean } = {}
		for _, item in DecorConfig.items do
			table.insert(affordable, type(item.price) == "number" and money >= item.price)
		end
		local decor: any = snapshot.decor
		local ok, encoded = pcall(function()
			return HttpService:JSONEncode({ owned, placed, affordable, currentSlot, type(decor) == "table" and decor.queueFull == true })
		end)
		return if ok then encoded else tostring(os.clock())
	end

	refresh = function()
		local snapshot: any = ClientState.snapshot or {}
		local owned, placed = snapshotDecor()
		local money: number = if type(snapshot.money) == "number" then snapshot.money else 0
		local decor: any = snapshot.decor

		Localizer.bind(slotLabel, "decor_slot", currentSlot)
		local bonus: number = if type(decor) == "table" and type(decor.bonus) == "number" then decor.bonus else 0
		Localizer.bind(bonusLabel, "decor_bonus", math.floor(bonus * 100 + 0.5), math.floor(DecorConfig.MAX_BONUS * 100 + 0.5))
		hintLabel.Visible = type(decor) == "table" and decor.queueFull == true

		lastSignature = signature()
		local saved = scroll.CanvasPosition
		for _, child in scroll:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local order = 0
		for _, item in DecorConfig.items do
			if visibleItem(item, owned) then
				order += 1
				buildCard(item, order, owned, placed, money)
			end
		end
		scroll.CanvasPosition = saved
	end

	rebuild = refresh
	m.onOpen = function()
		scroll.CanvasPosition = Vector2.zero
		refresh()
	end

	ClientState.onChanged(function()
		-- money ticks every few seconds: only rebuild the cards when something they show actually changed
		if m.isOpen and signature() ~= lastSignature then
			refresh()
		end
	end)

	Remotes.get("OpenUI").OnClientEvent:Connect(function(uiName: any, arg: any)
		if uiName == "Decor" then
			Decor.open(if type(arg) == "number" then arg else nil)
		end
	end)
end

return Decor
