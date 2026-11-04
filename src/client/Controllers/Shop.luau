--!strict
-- Robux shop (HUD button or OpenUI("Shop", tab?)). Tabs are built from the TABS list below (add one entry to add a tab).
-- Cards come from Config/Products (developer products) and Config/GamePasses. Items whose id is 0 are hidden in live
-- games; in Studio (Products.DEBUG_FAKE_IN_STUDIO) they show a TEST tag and buy through the DebugPurchase remote.
-- The server owns prices/grants: the client only prompts the purchase and shows snapshot data.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes: any = require(Shared:WaitForChild("Remotes") :: ModuleScript)
local Format: any = require(Shared:WaitForChild("Format") :: ModuleScript)
local Config = Shared:WaitForChild("Config")
local GamePasses: any = require(Config:WaitForChild("GamePasses") :: ModuleScript)
local Products: any = require(Config:WaitForChild("Products") :: ModuleScript)
local DecorConfig: any = require(Config:WaitForChild("Decor") :: ModuleScript)
local Controllers = script.Parent :: Instance
local Client = Controllers.Parent :: Instance
local ClientState: any = require(Client:WaitForChild("ClientState") :: ModuleScript)
local Theme: any = require(Client:WaitForChild("Theme") :: ModuleScript)
local Localizer: any = require(Controllers:WaitForChild("Localizer") :: ModuleScript)

local LocalPlayer = Players.LocalPlayer

local Shop = {}

local ROBUX = utf8.char(0xE002)
local PRICE_GREEN = Color3.fromRGB(38, 160, 78)
local DARK_TEXT = Color3.fromRGB(60, 40, 0)
local CLICK_DEBOUNCE = 1

local ICONS: { [string]: string } = {
	CashS = "💵",
	CashM = "💰",
	CashL = "🧰",
	CashXL = "🏦",
	Boost2x = "🚀",
	InstantRepair = "🔧",
	DoubleMoney = "💰",
	AutoCollect = "🧲",
	FastStaff = "⚡",
	VIP = "👑",
	-- one-time Robux items (round 2)
	PaintChrome = "🪞",
	PaintGold = "🥇",
	PaintRainbow = "🌈",
	NeonRainbow = "💡",
	SmokeGalaxy = "🌌",
	ThemeGold = "🏛️",
	CarHyper = "🏎️",
	StarterPack = "🎁",
	DecorBear = "🐻",
	DecorRobot = "🤖",
	DecorDragon = "🐉",
	DecorGold = "🏆",
	DecorFireworks = "🎆",
}

local RIBBONS: { [string]: string } = {
	CashM = "shop_popular",
	CashXL = "shop_best_value",
	StarterPack = "shop_best_value",
}

-- A card to show. kind: "cash" | "boost" | "instant" | "pass" | "item" (one-time Robux item, owned badge afterwards).
type Item = {
	kind: string,
	key: string,
	id: number,
	robux: number?,
	nameKey: string,
	descKey: string,
	descArg: any,
	infoType: Enum.InfoType,
}

local function visible(id: number): boolean
	if id ~= 0 then
		return true
	end
	return RunService:IsStudio() and Products.DEBUG_FAKE_IN_STUDIO == true
end

local function productItems(list: { any }, kind: string): { Item }
	local items: { Item } = {}
	for _, p in list do
		if visible(p.id) then
			local nameKey = "shop_cash_" .. p.key
			local descKey = "shop_cash_desc"
			if kind == "boost" then
				nameKey, descKey = "shop_boost_name", "shop_boost_desc"
			elseif kind == "instant" then
				nameKey, descKey = "shop_instant_name", "shop_instant_desc"
			end
			table.insert(items, {
				kind = kind,
				key = p.key,
				id = p.id,
				robux = p.robux,
				nameKey = nameKey,
				descKey = descKey,
				descArg = p.minutes,
				infoType = Enum.InfoType.Product,
			})
		end
	end
	return items
end

local function passItems(): { Item }
	local items: { Item } = {}
	for _, key in GamePasses.order do
		local pass: any = GamePasses[key]
		if type(pass) == "table" and type(pass.id) == "number" and visible(pass.id) then
			table.insert(items, {
				kind = "pass",
				key = key,
				id = pass.id,
				robux = if type(pass.robux) == "number" then pass.robux else nil,
				nameKey = "pass_" .. key,
				descKey = "pass_" .. key .. "_desc",
				descArg = nil,
				infoType = Enum.InfoType.GamePass,
			})
		end
	end
	return items
end

-- One-time Robux items (Products.Items). decor = true lists the storefront decorations, false everything else.
local function oneTimeItems(decor: boolean): { Item }
	local items: { Item } = {}
	for _, p in Products.Items do
		local grant: any = p.grant
		local isDecor = type(grant) == "table" and grant.decor ~= nil
		if isDecor == decor and visible(p.id) then
			local descArg: any = nil
			if isDecor then
				local decorItem: any = DecorConfig.byId[grant.decor]
				descArg = if decorItem then tostring(math.floor(decorItem.bonus * 100 + 0.5)) else "0"
			elseif type(grant) == "table" and type(grant.money) == "number" then
				descArg = Format.money(grant.money)
			end
			table.insert(items, {
				kind = "item",
				key = p.key,
				id = p.id,
				robux = p.robux,
				nameKey = "item_" .. p.key,
				descKey = "item_" .. p.key .. "_desc",
				descArg = descArg,
				infoType = Enum.InfoType.Product,
			})
		end
	end
	return items
end

-- One entry per tab.
local TABS: { { id: string, labelKey: string, items: () -> { Item } } } = {
	{
		id = "cash",
		labelKey = "shop_tab_cash",
		items = function()
			return productItems(Products.CashPacks, "cash")
		end,
	},
	{
		id = "boost",
		labelKey = "shop_tab_boost",
		items = function()
			local items = productItems(Products.Boosts, "boost")
			for _, item in productItems(Products.Instant, "instant") do
				table.insert(items, item)
			end
			return items
		end,
	},
	{
		id = "special",
		labelKey = "shop_tab_special",
		items = function()
			return oneTimeItems(false)
		end,
	},
	{
		id = "storefront",
		labelKey = "shop_tab_storefront",
		items = function()
			return oneTimeItems(true)
		end,
	},
	{
		id = "pass",
		labelKey = "shop_tab_pass",
		items = passItems,
	},
}

local modal: any = nil
local currentTab = "cash" -- remembered for the session
local selectTab: ((string) -> ())? = nil

----------------------------------------------------------------------------------------------------
-- Prices (real Robux price from MarketplaceService, cached)
----------------------------------------------------------------------------------------------------

local priceCache: { [string]: number | boolean } = {}
local pricePending: { [string]: { () -> () } } = {}

local function priceKey(item: Item): string
	return tostring(item.infoType) .. item.id
end

-- Calls onReady() once the real price is known (immediately when cached). id 0 never fetches.
local function fetchPrice(item: Item, onReady: () -> ())
	if item.id == 0 then
		return
	end
	local cacheKey = priceKey(item)
	if priceCache[cacheKey] ~= nil then
		onReady()
		return
	end
	local waiting = pricePending[cacheKey]
	if waiting then
		table.insert(waiting, onReady)
		return
	end
	pricePending[cacheKey] = { onReady }
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(item.id, item.infoType)
		end)
		local price: any = if ok and type(info) == "table" then info.PriceInRobux else nil
		priceCache[cacheKey] = if type(price) == "number" then price else false
		local callbacks = pricePending[cacheKey]
		pricePending[cacheKey] = nil
		if callbacks then
			for _, fn in callbacks do
				fn()
			end
		end
	end)
end

local function priceText(item: Item): string
	local cached = priceCache[priceKey(item)]
	local price: number? = if type(cached) == "number" then cached else item.robux
	if price then
		return ROBUX .. " " .. Format.number(price)
	end
	return Localizer.t("shop_free_price")
end

local function formatClock(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

----------------------------------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------------------------------

-- Kept for HUD / older callers: the shop is always available now.
function Shop.available(): boolean
	return true
end

function Shop.open(tab: string?)
	if not modal then
		return
	end
	if type(tab) == "string" and selectTab then
		selectTab(tab)
	end
	modal.open()
end

function Shop.close()
	if modal then
		modal.close()
	end
end

function Shop.toggle()
	if modal then
		if modal.isOpen then
			modal.close()
		else
			Shop.open()
		end
	end
end

----------------------------------------------------------------------------------------------------
-- UI
----------------------------------------------------------------------------------------------------

function Shop.start()
	local C = Theme.colors

	local m = Theme.modal("Shop", 21, 640, 560)
	modal = m
	local body = m.body

	local title = Theme.label({
		Name = "Title",
		Position = UDim2.fromOffset(0, 10),
		Size = UDim2.new(1, 0, 0, 36),
		TextSize = 30,
	}, body)
	Localizer.bind(title, "shop_title")

	local tabBar = Theme.new("Frame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 54),
		Size = UDim2.new(1, -32, 0, 44),
	}, body)

	local scroll = Theme.new("ScrollingFrame", {
		Name = "Items",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 106),
		Size = UDim2.new(1, -32, 1, -106 - 80),
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
	grid.CellSize = UDim2.new(0.5, -5, 0, 176)
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
		grid.CellSize = if compact then UDim2.new(1, -2, 0, 176) else UDim2.new(0.5, -5, 0, 176)
	end)

	----------------------------------------------------------------- cards
	-- Each card registers an update() that refreshes its dynamic parts from the snapshot.
	local updaters: { () -> () } = {}

	local function snapshotValue(): any
		return ClientState.snapshot or {}
	end

	local function buildCard(item: Item, order: number)
		local card = Theme.new("Frame", {
			Name = "Card_" .. item.key,
			BackgroundColor3 = C.panelLight,
			LayoutOrder = order,
		}, scroll)
		Theme.corner(card, 16)
		Theme.stroke(card, C.stroke, 1.5, 0.75)

		local iconBadge = Theme.new("Frame", {
			Name = "Icon",
			Position = UDim2.fromOffset(10, 10),
			Size = UDim2.fromOffset(52, 52),
			BackgroundColor3 = C.panelLighter,
		}, card)
		Theme.corner(iconBadge, 26)
		Theme.stroke(iconBadge, C.star, 2, 0.4)
		Theme.label({
			Size = UDim2.fromScale(1, 1),
			Text = ICONS[item.key] or "★",
			TextSize = 28,
		}, iconBadge)

		local ribbonKey = RIBBONS[item.key]
		-- width offset = left inset (70) + right margin; with a ribbon the margin also clears the 78 px ribbon
		local nameRight = if ribbonKey then 70 + 94 else 80
		local nameLabel = Theme.label({
			Name = "ItemName",
			Position = UDim2.fromOffset(70, 10),
			Size = UDim2.new(1, -nameRight, 0, 26),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextScaled = true,
		}, card)
		Theme.fitText(nameLabel, 12, 22)
		Localizer.bind(nameLabel, item.nameKey)

		local descLabel = Theme.label({
			Name = "ItemDescription",
			Position = UDim2.fromOffset(70, 38),
			Size = UDim2.new(1, -80, 0, 42),
			Font = Theme.fontRegular,
			TextColor3 = C.textDim,
			TextScaled = true,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
		}, card)
		Theme.fitText(descLabel, 10, 15)
		if item.descArg then
			Localizer.bind(descLabel, item.descKey, item.descArg)
		else
			Localizer.bind(descLabel, item.descKey)
		end

		if ribbonKey then
			local ribbon = Theme.new("Frame", {
				Name = "Ribbon",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -8, 0, 8),
				Size = UDim2.fromOffset(78, 22),
				BackgroundColor3 = C.star,
				ZIndex = 3,
			}, card)
			Theme.corner(ribbon, 11)
			local ribbonText = Theme.label({
				Size = UDim2.fromScale(1, 1),
				TextScaled = true,
				TextColor3 = DARK_TEXT,
				ZIndex = 4,
			}, ribbon)
			Theme.fitText(ribbonText, 9, 14)
			Localizer.bind(ribbonText, ribbonKey)
		end

		local valueLabel = Theme.label({
			Name = "Value",
			Position = UDim2.fromOffset(10, 86),
			Size = UDim2.new(1, -84, 0, 24),
			TextSize = 20,
			TextColor3 = C.money,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextScaled = true,
		}, card)
		Theme.fitText(valueLabel, 11, 22)

		if item.id == 0 then
			local tag = Theme.new("Frame", {
				Name = "TestTag",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -10, 0, 88),
				Size = UDim2.fromOffset(62, 20),
				BackgroundColor3 = C.danger,
			}, card)
			Theme.corner(tag, 10)
			local tagText = Theme.label({
				Size = UDim2.fromScale(1, 1),
				TextScaled = true,
			}, tag)
			Theme.fitText(tagText, 9, 13)
			Localizer.bind(tagText, "shop_test_tag")
		end

		local buyButton = Theme.button({
			Name = "BuyButton",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -10),
			Size = UDim2.new(1, -20, 0, 48),
			BackgroundColor3 = PRICE_GREEN,
			TextSize = 22,
		}, card)

		local ownedBadge = Theme.new("Frame", {
			Name = "OwnedBadge",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -10),
			Size = UDim2.new(1, -20, 0, 48),
			BackgroundColor3 = C.star,
			Visible = false,
		}, card)
		Theme.corner(ownedBadge, 14)
		local ownedText = Theme.label({
			Size = UDim2.fromScale(1, 1),
			TextSize = 20,
			TextColor3 = DARK_TEXT,
		}, ownedBadge)
		Localizer.bind(ownedText, "ui_owned")

		local enabled = true
		local lastClick = 0.0
		buyButton.Activated:Connect(function()
			local now = os.clock()
			if not enabled or now - lastClick < CLICK_DEBOUNCE then
				return
			end
			lastClick = now
			if item.id == 0 then
				Remotes.get("DebugPurchase"):FireServer(item.key)
				return
			end
			local ok, err = pcall(function()
				if item.kind == "pass" then
					MarketplaceService:PromptGamePassPurchase(LocalPlayer, item.id)
				else
					MarketplaceService:PromptProductPurchase(LocalPlayer, item.id)
				end
			end)
			if not ok then
				warn("[Shop] Purchase prompt failed: " .. tostring(err))
			end
		end)

		local function setEnabled(value: boolean)
			enabled = value
			buyButton.AutoButtonColor = value
			buyButton.BackgroundColor3 = if value then PRICE_GREEN else C.gray
			buyButton.TextTransparency = if value then 0 else 0.5
		end

		local function update()
			local snapshot = snapshotValue()
			buyButton.Text = priceText(item)
			if item.kind == "cash" then
				local packs: any = snapshot.cashPacks
				local amount: any = if type(packs) == "table" then packs[item.key] else nil
				valueLabel.Text = if type(amount) == "number" then "+" .. Format.money(amount) else ""
			elseif item.kind == "boost" then
				local left: number = ClientState.boostRemaining()
				valueLabel.Text = if left > 0 then Localizer.t("shop_boost_left", formatClock(left)) else ""
			elseif item.kind == "instant" then
				local none = (snapshot.repairsActive or 0) <= 0
				setEnabled(not none)
				valueLabel.Text = if none then Localizer.t("shop_instant_none") else ""
				valueLabel.TextColor3 = if none then C.textDim else C.money
			elseif item.kind == "pass" then
				local owned: any = snapshot.gamepasses
				local isOwned = type(owned) == "table" and owned[item.key] == true
				buyButton.Visible = not isOwned
				ownedBadge.Visible = isOwned
			elseif item.kind == "item" then
				local owned: any = snapshot.itemsOwned
				local isOwned = type(owned) == "table" and owned[item.key] == true
				buyButton.Visible = not isOwned
				ownedBadge.Visible = isOwned
			end
		end

		table.insert(updaters, update)
		fetchPrice(item, function()
			if buyButton.Parent then
				buyButton.Text = priceText(item)
			end
		end)
		update()
	end

	----------------------------------------------------------------- tabs
	local tabButtons: { [string]: any } = {}

	local function renderTab()
		table.clear(updaters)
		for _, child in scroll:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		scroll.CanvasPosition = Vector2.zero
		for _, tab in TABS do
			if tab.id == currentTab then
				for index, item in tab.items() do
					buildCard(item, index)
				end
			end
		end
		for id, button in tabButtons do
			local selected = id == currentTab
			button.BackgroundColor3 = if selected then C.accent else C.gray
		end
	end

	local function refresh()
		for _, update in updaters do
			update()
		end
	end

	selectTab = function(id: string)
		for _, tab in TABS do
			if tab.id == id then
				currentTab = id
				if m.isOpen then
					renderTab()
				end
				return
			end
		end
	end

	for index, tab in TABS do
		local count = #TABS
		local button = Theme.button({
			Name = "Tab_" .. tab.id,
			Position = UDim2.new((index - 1) / count, 0, 0, 0),
			Size = UDim2.new(1 / count, -6, 1, 0),
			BackgroundColor3 = C.gray,
			TextSize = 20,
			TextScaled = true,
		}, tabBar)
		Theme.fitText(button, 11, 20)
		Localizer.bind(button, tab.labelKey)
		button.Activated:Connect(function()
			currentTab = tab.id
			renderTab()
		end)
		tabButtons[tab.id] = button
	end

	m.onOpen = function()
		renderTab()
	end

	ClientState.onChanged(function()
		if m.isOpen then
			refresh()
		end
	end)

	-- boost countdown ticks once a second while the shop is open
	task.spawn(function()
		while true do
			task.wait(1)
			if m.isOpen then
				refresh()
			end
		end
	end)

	Remotes.get("OpenUI").OnClientEvent:Connect(function(uiName: any, arg: any)
		if uiName == "Shop" then
			Shop.open(if type(arg) == "string" then arg else nil)
		end
	end)
end

return Shop
