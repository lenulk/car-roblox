--!strict
-- Parts shop: shelves restock themselves (faster with a stocker, who carries the items to the shelf),
-- walk-in shoppers buy items, and the shelf model shows how full it is (Product parts hidden above the stock).

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Layout = require(Shared.Layout)
local Remotes = require(Shared.Remotes)
local Format = require(Shared.Format)
local Shelves = require(Shared.Config.Shelves)
local Unlocks = require(Shared.Config.Unlocks)
local Game = require(Shared.Config.Game)

local PlayerData = require(script.Parent.PlayerData)
local PlotService = require(script.Parent.PlotService)
local UnlockService = require(script.Parent.UnlockService)
local HireService = require(script.Parent.HireService)
local EconomyService = require(script.Parent.EconomyService)
local MapBuilder = require(script.Parent.MapBuilder)
local ShopperService = require(script.Parent.ShopperService)
local EmployeeService = require(script.Parent.EmployeeService)
local DecorService = require(script.Parent.DecorService)

local ShopService = {}

local TICK = 0.5

-- pending: restocked items the stocker NPC still has to carry to the shelf.
type PlotShop = {
	player: Player,
	alive: boolean,
	restock: { [string]: number },
	pending: { [string]: number },
	shopperTimer: number,
}
local shops: { [number]: PlotShop } = {}

local function capacity(player: Player, shelfId: string): number
	local level = UnlockService.level(player, shelfId)
	return if level > 0 then Shelves.LEVELS[level].capacity else 0
end

local function price(player: Player, shelfId: string): number
	local level = math.max(1, UnlockService.level(player, shelfId))
	return math.floor(Shelves.byId[shelfId].basePrice * Shelves.LEVELS[level].priceMult)
end

local function shelfIndex(shelfId: string): number
	return Unlocks.byId[shelfId].shelf
end

local function stationOf(plotIndex: number, shelfId: string): Instance?
	local unlockables = MapBuilder.getPlot(plotIndex):FindFirstChild("Unlockables")
	local holder = unlockables and unlockables:FindFirstChild(shelfId)
	return holder and holder:FindFirstChild("Station")
end

-- Hide products above the current stock so the shelf visibly empties and refills.
function ShopService.refreshShelf(player: Player, shelfId: string)
	local plotIndex = PlotService.getPlotIndex(player)
	local data = PlayerData.get(player)
	local station = plotIndex and stationOf(plotIndex, shelfId)
	if not station or not data then
		return
	end
	local stock = data.stock[shelfId] or 0
	for _, d in station:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Product" then
			local index = d:GetAttribute("ProductIndex")
			local base = d:GetAttribute("BaseTransparency")
			local visible = type(index) == "number" and index <= stock
			d.Transparency = if visible then (if type(base) == "number" then base else 0) else 1
		end
	end
end

local function ownedShelves(player: Player): { string }
	local list = {}
	for _, shelfId in Shelves.order do
		if UnlockService.isOwned(player, shelfId) then
			table.insert(list, shelfId)
		end
	end
	return list
end

local function setStock(player: Player, shelfId: string, value: number)
	PlayerData.update(player, function(d)
		d.stock[shelfId] = math.clamp(value, 0, capacity(player, shelfId))
	end)
	ShopService.refreshShelf(player, shelfId)
end

local function sell(plotIndex: number, shop: PlotShop, shelfId: string)
	local player = shop.player
	local data = PlayerData.get(player)
	if not shop.alive or not data or PlotService.getPlotIndex(player) ~= plotIndex then
		return
	end
	local stock = data.stock[shelfId] or 0
	local count = math.min(stock, math.random(1, 2))
	if count <= 0 then
		return
	end
	setStock(player, shelfId, stock - count)
	local earned = EconomyService.earn(player, price(player, shelfId) * count)
	local position = Layout.shelfCFrame(plotIndex, shelfIndex(shelfId)).Position + Vector3.new(0, 8, -2)
	Remotes.get("Effect"):FireClient(player, "Coins", position, "+" .. Format.money(earned))
end

local function tick(plotIndex: number, shop: PlotShop, dt: number)
	local player = shop.player
	local data = PlayerData.get(player)
	if not data then
		return
	end
	local shelves = ownedShelves(player)
	if #shelves == 0 then
		return
	end

	-- Restock. With a stocker NPC on the plot the items are carried over (see deliverStock).
	local stocker = HireService.stockerLevel(player)
	local speed = if stocker > 0 then Game.STOCKER_SPEED[stocker] or 1 else 1
	local npc = if stocker > 0 then HireService.npcAt(plotIndex, "Stock") else nil
	local carried = npc ~= nil and npc.Parent ~= nil
	for _, shelfId in shelves do
		local cap = capacity(player, shelfId)
		local stock = data.stock[shelfId] or 0
		local pending = shop.pending[shelfId] or 0
		if pending > 0 and not carried then
			setStock(player, shelfId, stock + pending)
			stock = math.min(stock + pending, cap)
			pending = 0
			shop.pending[shelfId] = 0
		end
		if stock + pending < cap then
			local t = (shop.restock[shelfId] or 0) + dt * speed
			if t >= Shelves.RESTOCK_SECONDS then
				t -= Shelves.RESTOCK_SECONDS
				if carried then
					shop.pending[shelfId] = pending + 1
				else
					setStock(player, shelfId, stock + 1)
				end
			end
			shop.restock[shelfId] = t
		else
			shop.restock[shelfId] = 0
		end
	end

	-- Walk-in shoppers.
	shop.shopperTimer -= dt
	if shop.shopperTimer <= 0 then
		local reception = HireService.receptionistLevel(player)
		local interval = Shelves.SHOPPER_INTERVAL
			* (if reception > 0 then Game.RECEPTION_SPAWN_MULT[reception] or 1 else 1)
			* (1 - DecorService.bonus(player))
		shop.shopperTimer = interval * (0.75 + math.random() * 0.5)
		local stocked = {}
		for _, shelfId in shelves do
			if (data.stock[shelfId] or 0) > 0 then
				table.insert(stocked, shelfId)
			end
		end
		if #stocked > 0 then
			local shelfId = stocked[math.random(1, #stocked)]
			local ok, err = pcall(ShopperService.visit, plotIndex, shelfIndex(shelfId), function()
				sell(plotIndex, shop, shelfId)
			end)
			if not ok then
				warn("[ShopService] shopper visit failed: " .. tostring(err))
			end
		end
	end
end

-- Stocker NPC hooks (EmployeeService): the shelf with the most items waiting, and the hand-over.
local function stockTarget(plotIndex: number): number?
	local shop = shops[plotIndex]
	if not shop or not shop.alive then
		return nil
	end
	local best: string? = nil
	local bestCount = 0
	for _, shelfId in ownedShelves(shop.player) do
		local count = shop.pending[shelfId] or 0
		if count > bestCount then
			best, bestCount = shelfId, count
		end
	end
	return if best then shelfIndex(best) else nil
end

local function deliverStock(plotIndex: number, index: number)
	local shop = shops[plotIndex]
	local data = shop and PlayerData.get(shop.player)
	if not shop or not shop.alive or not data then
		return
	end
	for _, shelfId in Shelves.order do
		local count = shop.pending[shelfId] or 0
		if shelfIndex(shelfId) == index and count > 0 then
			shop.pending[shelfId] = 0
			setStock(shop.player, shelfId, (data.stock[shelfId] or 0) + count)
		end
	end
end

local function startPlot(player: Player, plotIndex: number)
	local shop: PlotShop = { player = player, alive = true, restock = {}, pending = {}, shopperTimer = 5 }
	shops[plotIndex] = shop
	-- UnlockService rebuilds shelf models on join in its own callback; refresh after that settles.
	task.delay(1.5, function()
		if shop.alive then
			for _, shelfId in ownedShelves(player) do
				ShopService.refreshShelf(player, shelfId)
			end
		end
	end)
	task.spawn(function()
		while shop.alive do
			task.wait(TICK)
			if shop.alive then
				local ok, err = pcall(tick, plotIndex, shop, TICK)
				if not ok then
					warn("[ShopService] " .. tostring(err))
				end
			end
		end
	end)
end

local function stopPlot(plotIndex: number)
	local shop = shops[plotIndex]
	if shop then
		shop.alive = false
		shops[plotIndex] = nil
	end
	pcall(ShopperService.clearPlot, plotIndex)
end

function ShopService.start()
	EmployeeService.setStockHandler(stockTarget, deliverStock)
	PlotService.onAssigned(startPlot)
	PlotService.onReleased(function(_player, plotIndex)
		stopPlot(plotIndex)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local plotIndex = PlotService.getPlotIndex(player)
		if plotIndex then
			stopPlot(plotIndex)
		end
	end)
	UnlockService.onUnlocked(function(player, id)
		if Shelves.byId[id] then
			setStock(player, id, capacity(player, id))
		end
	end)
	UnlockService.onUpgraded(function(player, id)
		if Shelves.byId[id] then
			-- The station model was rebuilt with more product slots: fill the new space.
			setStock(player, id, capacity(player, id))
		end
	end)
	PlayerData.addSnapshotField(function(player, data, snapshot)
		local stock = {}
		for _, shelfId in Shelves.order do
			if data.unlocks[shelfId] then
				stock[shelfId] = { stock = data.stock[shelfId] or 0, capacity = capacity(player, shelfId), price = price(player, shelfId) }
			end
		end
		snapshot.stock = stock
	end)
end

return ShopService
