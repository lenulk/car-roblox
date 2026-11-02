--!strict
-- Game pass shop (HUD button or OpenUI("Shop")). Only passes whose id in Config/GamePasses is not 0 are shown.
-- Buying prompts Roblox's own purchase dialog; the server listens for the result and updates snapshot.gamepasses.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes: any = require(Shared:WaitForChild("Remotes") :: ModuleScript)
local GamePasses: any = require(Shared:WaitForChild("Config"):WaitForChild("GamePasses") :: ModuleScript)
local Controllers = script.Parent :: Instance
local Client = Controllers.Parent :: Instance
local ClientState: any = require(Client:WaitForChild("ClientState") :: ModuleScript)
local Theme: any = require(Client:WaitForChild("Theme") :: ModuleScript)
local Localizer: any = require(Controllers:WaitForChild("Localizer") :: ModuleScript)

local LocalPlayer = Players.LocalPlayer

local Shop = {}

local ICONS: { [string]: string } = {
	DoubleMoney = "💰",
	AutoCollect = "🧲",
	FastStaff = "⚡",
}
local DARK_TEXT = Color3.fromRGB(60, 40, 0)

local modal: any = nil

-- Names of the passes that are enabled (id ~= 0), in display order.
local function activePasses(): { string }
	local names: { string } = {}
	local order: any = GamePasses.order
	if type(order) ~= "table" then
		order = {}
		for name, entry in GamePasses do
			if type(entry) == "table" and entry.id ~= nil then
				table.insert(order, name)
			end
		end
		table.sort(order)
	end
	for _, name in order do
		local entry: any = GamePasses[name]
		if type(entry) == "table" and type(entry.id) == "number" and entry.id ~= 0 then
			table.insert(names, name)
		end
	end
	return names
end

-- True when at least one game pass is configured (the HUD hides the Shop button otherwise).
function Shop.available(): boolean
	return #activePasses() > 0
end

function Shop.open()
	if modal and Shop.available() then
		modal.open()
	end
end

function Shop.close()
	if modal then
		modal.close()
	end
end

function Shop.toggle()
	if modal and Shop.available() then
		modal.toggle()
	end
end

function Shop.start()
	local C = Theme.colors
	local names = activePasses()
	if #names == 0 then
		return
	end

	local m = Theme.modal("Shop", 21, 560, 520)
	modal = m
	local body = m.body

	local title = Theme.label({
		Name = "Title",
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(1, 0, 0, 40),
		TextSize = 30,
	}, body)
	Localizer.bind(title, "shop_title")

	local scroll = Theme.new("ScrollingFrame", {
		Name = "Passes",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 64),
		Size = UDim2.new(1, -32, 1, -64 - 88),
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
	Theme.list(scroll, Enum.FillDirection.Vertical, 12)

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

	----------------------------------------------------------------- pass rows
	local entries: { { name: string, buyButton: any, ownedBadge: any } } = {}

	for index, name in names do
		local passId: number = GamePasses[name].id

		local row = Theme.new("Frame", {
			Name = "Pass_" .. name,
			BackgroundColor3 = C.panelLight,
			Size = UDim2.new(1, 0, 0, 104),
			LayoutOrder = index,
		}, scroll)
		Theme.corner(row, 16)
		Theme.stroke(row, C.stroke, 1.5, 0.75)

		local iconBadge = Theme.new("Frame", {
			Name = "Icon",
			Position = UDim2.fromOffset(14, 20),
			Size = UDim2.fromOffset(64, 64),
			BackgroundColor3 = C.panelLighter,
		}, row)
		Theme.corner(iconBadge, 32)
		Theme.stroke(iconBadge, C.star, 2, 0.4)
		Theme.label({
			Size = UDim2.fromScale(1, 1),
			Text = ICONS[name] or "★",
			TextSize = 32,
		}, iconBadge)

		local nameLabel = Theme.label({
			Name = "PassName",
			Position = UDim2.fromOffset(92, 14),
			Size = UDim2.new(1, -92 - 160, 0, 30),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextScaled = true,
		}, row)
		Theme.fitText(nameLabel, 13, 24)
		Localizer.bind(nameLabel, "pass_" .. name)

		local descLabel = Theme.label({
			Name = "PassDescription",
			Position = UDim2.fromOffset(92, 46),
			Size = UDim2.new(1, -92 - 160, 0, 46),
			Font = Theme.fontRegular,
			TextColor3 = C.textDim,
			TextScaled = true,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
		}, row)
		Theme.fitText(descLabel, 11, 16)
		Localizer.bind(descLabel, "pass_" .. name .. "_desc")

		local buyButton = Theme.button({
			Name = "BuyButton",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(136, Theme.buttonHeight),
			TextSize = 24,
		}, row)
		Localizer.bind(buyButton, "shop_buy")
		buyButton.Activated:Connect(function()
			local ok, err = pcall(function()
				MarketplaceService:PromptGamePassPurchase(LocalPlayer, passId)
			end)
			if not ok then
				warn("[Shop] PromptGamePassPurchase failed: " .. tostring(err))
			end
		end)

		local ownedBadge = Theme.new("Frame", {
			Name = "OwnedBadge",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(136, 48),
			BackgroundColor3 = C.star,
			Visible = false,
		}, row)
		Theme.corner(ownedBadge, 24)
		local ownedText = Theme.label({
			Size = UDim2.fromScale(1, 1),
			TextSize = 20,
			TextColor3 = DARK_TEXT,
		}, ownedBadge)
		Localizer.bind(ownedText, "ui_owned")

		table.insert(entries, { name = name, buyButton = buyButton, ownedBadge = ownedBadge })
	end

	local function render()
		local snapshot: any = ClientState.snapshot
		local owned: any = if snapshot and type(snapshot.gamepasses) == "table" then snapshot.gamepasses else {}
		for _, entry in entries do
			local isOwned = owned[entry.name] == true
			entry.buyButton.Visible = not isOwned
			entry.ownedBadge.Visible = isOwned
		end
	end

	m.onOpen = function()
		render()
	end

	ClientState.onChanged(function()
		if m.isOpen then
			render()
		end
	end)

	Remotes.get("OpenUI").OnClientEvent:Connect(function(uiName: any)
		if uiName == "Shop" then
			m.open()
		end
	end)
end

return Shop
