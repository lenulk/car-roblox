--!strict
-- Robux developer products. The ONLY place MarketplaceService.ProcessReceipt is assigned.
-- Grants are plugged in as "kinds": PurchaseService.registerKind(kind, handler[, afterGrant]).
--   handler(player, data, entry) -> (ok, notifyKey?, args?)   runs INSIDE PlayerData.update: only mutate `data`.
--   afterGrant(player, entry)                                  runs after the update (side-effect services).
-- Every entry in Config/Products maps to a kind via entry.kind (see Products.luau).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Format = require(Shared.Format)
local Strings = require(Shared.Config.Strings)
local Products = require(Shared.Config.Products)
local GamePasses = require(Shared.Config.GamePasses)

local PlayerData = require(script.Parent.PlayerData)
local GamePassService = require(script.Parent.GamePassService)
local EconomyService = require(script.Parent.EconomyService)

local PurchaseService = {}

export type Handler = (player: Player, data: PlayerData.Data, entry: any) -> (boolean, string?, { any }?)
export type AfterGrant = (player: Player, entry: any) -> ()

local MAX_RECEIPTS = 200
local CASH_CACHE_SECONDS = 20

local kinds: { [string]: { handler: Handler, after: AfterGrant? } } = {}
local inFlight: { [string]: boolean } = {}

-- Services that depend on this one (or are loaded later) are required lazily to avoid load-order problems.
local function offlineService(): any
	return require(script.Parent.OfflineService)
end

local function repairService(): any
	return require(script.Parent.RepairService)
end

function PurchaseService.registerKind(kind: string, handler: Handler, after: AfterGrant?)
	kinds[kind] = { handler = handler, after = after }
end

----------------------------------------------------------------------------------------------------
-- Cash pack amounts
----------------------------------------------------------------------------------------------------

-- 12,437 -> 12,000 (two significant digits)
local function roundTwoDigits(n: number): number
	n = math.floor(n)
	if n < 100 then
		return n
	end
	local magnitude = 10 ^ (math.floor(math.log10(n)) - 1)
	return math.floor(n / magnitude + 0.5) * magnitude
end

local cashCache: { [Player]: { at: number, amounts: { [string]: number } } } = {}

-- { CashS = n, ... }, recomputed at most every CASH_CACHE_SECONDS per player. Grants use the same numbers
-- the shop showed.
function PurchaseService.cashAmounts(player: Player): { [string]: number }
	local cached = cashCache[player]
	local now = os.clock()
	if cached and now - cached.at < CASH_CACHE_SECONDS then
		return cached.amounts
	end
	local perMinute = 0
	local ok, perSecond = pcall(function()
		return offlineService().estimatePerSecond(player) * EconomyService.multiplier(player, true) -- the paid boost must not inflate packs
	end)
	if ok and type(perSecond) == "number" then
		perMinute = perSecond * 60
	end
	local amounts: { [string]: number } = {}
	for _, pack in Products.CashPacks do
		amounts[pack.key] = roundTwoDigits(math.max(pack.minimum, math.floor(perMinute * pack.minutes)))
	end
	cashCache[player] = { at = now, amounts = amounts }
	return amounts
end

----------------------------------------------------------------------------------------------------
-- Granting
----------------------------------------------------------------------------------------------------

-- Steps 4-6 of the receipt flow. Returns true when the purchase is granted AND saved.
local function grant(player: Player, entry: any, purchaseId: string): boolean
	local kind = kinds[entry.kind]
	if not kind then
		warn("[PurchaseService] No grant handler for kind " .. tostring(entry.kind))
		return false
	end
	if not PlayerData.get(player) then
		return false
	end

	local notifyKey: string? = nil
	local notifyArgs: { any }? = nil
	local granted = false
	PlayerData.update(player, function(data)
		local ok, key, args = kind.handler(player, data, entry)
		if not ok then
			return
		end
		granted = true
		notifyKey, notifyArgs = key, args
		data.receipts[purchaseId] = os.time()
		-- keep only the newest MAX_RECEIPTS
		local count = 0
		for _ in data.receipts do
			count += 1
		end
		if count > MAX_RECEIPTS then
			local ids: { string } = {}
			for id in data.receipts do
				table.insert(ids, id)
			end
			table.sort(ids, function(a, b)
				return data.receipts[a] > data.receipts[b]
			end)
			for i = MAX_RECEIPTS + 1, #ids do
				data.receipts[ids[i]] = nil
			end
		end
	end)
	if not granted then
		return false
	end
	if kind.after then
		local ok, err = pcall(kind.after, player, entry)
		if not ok then
			warn("[PurchaseService] afterGrant failed: " .. tostring(err))
		end
	end

	local saved = PlayerData.saveNow(player)

	-- feedback (even if the save failed: the grant is in memory and Roblox retries the receipt)
	if player.Parent then
		if notifyKey then
			Remotes.get("Notify"):FireClient(player, notifyKey, notifyArgs)
		end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local text = if notifyArgs and entry.kind == "cash" then "+" .. tostring(notifyArgs[1]) else ""
			Remotes.get("Effect"):FireClient(player, "Purchase", root.Position + Vector3.new(0, 3, 0), text)
		end
	end
	return saved
end

local function processReceipt(receiptInfo: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player or not PlayerData.get(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local entry = Products.byId[receiptInfo.ProductId]
	if not entry then
		warn("[PurchaseService] Unknown ProductId " .. tostring(receiptInfo.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(receiptInfo.PurchaseId)
	local data = PlayerData.get(player)
	if data and data.receipts[purchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	if inFlight[purchaseId] then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	inFlight[purchaseId] = true
	local ok, result = pcall(grant, player, entry, purchaseId)
	inFlight[purchaseId] = nil
	if not ok then
		warn("[PurchaseService] ProcessReceipt error: " .. tostring(result))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return if result then Enum.ProductPurchaseDecision.PurchaseGranted else Enum.ProductPurchaseDecision.NotProcessedYet
end

----------------------------------------------------------------------------------------------------
-- Studio-only fake purchases
----------------------------------------------------------------------------------------------------

local lastDebug: { [Player]: number } = {}

local function onDebugPurchase(player: Player, key: any)
	if not RunService:IsStudio() or not Products.DEBUG_FAKE_IN_STUDIO or type(key) ~= "string" then
		return
	end
	local now = os.clock()
	if lastDebug[player] and now - lastDebug[player] < 0.5 then
		return
	end
	lastDebug[player] = now

	local entry = Products.byKey[key]
	if entry then
		grant(player, entry, "debug-" .. tostring(os.clock()))
	elseif (GamePasses :: any)[key] and table.find(GamePasses.order, key) then
		GamePassService.debugGrant(player, key)
		Remotes.get("Notify"):FireClient(player, "notify_gamepass_thanks")
	end
end

----------------------------------------------------------------------------------------------------
-- Round 1 kinds
----------------------------------------------------------------------------------------------------

local function registerBuiltInKinds()
	-- bought money: not counted as earned
	PurchaseService.registerKind("cash", function(player, data, entry)
		local amount = PurchaseService.cashAmounts(player)[entry.key] or entry.minimum
		data.money += amount
		return true, "notify_cash_bought", { Format.money(amount) }
	end)

	PurchaseService.registerKind("boost", function(_player, data, entry)
		data.boostUntil = math.max(data.boostUntil, os.time()) + entry.minutes * 60
		return true, "notify_boost_bought", { entry.minutes }
	end, function(player)
		EconomyService.scheduleBoostExpiry(player)
	end)

	PurchaseService.registerKind("instantRepair", function(player, data, _entry)
		if repairService().activeCount(player) > 0 then
			return true, "notify_instant_done", nil
		end
		-- nothing was repairing: give the smallest cash pack instead
		local pack = Products.byKey.CashS
		local amount = PurchaseService.cashAmounts(player).CashS or (pack and pack.minimum) or 0
		data.money += amount
		return true, "notify_instant_repair_none", { Format.money(amount) }
	end, function(player)
		repairService().finishAll(player)
	end)
end

----------------------------------------------------------------------------------------------------
-- Round 2 kind: one-time Robux items (Config/Products.Items)
----------------------------------------------------------------------------------------------------

-- True when the player already has everything this item would give (money does not count: it is not "owned").
-- Items with `once` are owned when their Data flag is set.
local function itemOwned(data: PlayerData.Data, entry: any): boolean
	local grant: Products.ItemGrant = entry.grant
	if entry.once then
		return (data :: any)[entry.once] == true
	end
	local hasGrant = false
	if grant.part then
		hasGrant = true
		if data.ownedParts[grant.part] ~= true then
			return false
		end
	end
	if grant.theme then
		hasGrant = true
		if data.ownedThemes[grant.theme] ~= true then
			return false
		end
	end
	if grant.car then
		hasGrant = true
		if data.cars[grant.car] == nil then
			return false
		end
	end
	if grant.decor then
		hasGrant = true
		if data.decorOwned[grant.decor] ~= true then
			return false
		end
	end
	return hasGrant
end

local function registerUnlockKind()
	PurchaseService.registerKind("unlock", function(_player, data, entry)
		local grant: Products.ItemGrant = entry.grant
		local name = Strings.get(data.settings.lang, "item_" .. entry.key)
		if itemOwned(data, entry) then
			-- bought twice (e.g. two servers): the receipt is still granted, nothing changes
			return true, "notify_already_owned", { name }
		end
		if grant.part then
			data.ownedParts[grant.part] = true
		end
		if grant.theme then
			data.ownedThemes[grant.theme] = true
		end
		if grant.car and data.cars[grant.car] == nil then
			-- same as BuyCar; a player with no car yet also gets the starter Sedan (ensureStarterCar skips non-empty garages)
			local personalCars: any = require(script.Parent.PersonalCarService)
			if next(data.cars) == nil then
				data.cars.Sedan = personalCars.newCarSave()
			end
			data.cars[grant.car] = personalCars.newCarSave()
			data.selectedCar = grant.car
		end
		if grant.decor then
			data.decorOwned[grant.decor] = true
		end
		if grant.money then
			data.money += grant.money -- bought money, not counted as earned
		end
		if entry.once then
			(data :: any)[entry.once] = true
		end
		if grant.decor then
			return true, "notify_decor_bought", { name }
		end
		return true, "notify_item_bought", { name }
	end, function(player, entry)
		local grant: Products.ItemGrant = entry.grant
		if grant.car then
			local ok, err = pcall(function()
				require(script.Parent.ShowcaseService).refresh(player)
			end)
			if not ok then
				warn("[PurchaseService] showcase refresh failed: " .. tostring(err))
			end
		end
	end)
end

function PurchaseService.init()
	registerBuiltInKinds()
	registerUnlockKind()
end

function PurchaseService.start()
	MarketplaceService.ProcessReceipt = processReceipt :: any

	Remotes.get("DebugPurchase").OnServerEvent:Connect(onDebugPurchase)

	PlayerData.addSnapshotField(function(player, data, snapshot)
		snapshot.cashPacks = PurchaseService.cashAmounts(player)
		-- one-time Robux items the player already has (the shop shows an "Owned" badge)
		local itemsOwned: { [string]: boolean } = {}
		for _, entry in Products.Items do
			if itemOwned(data, entry) then
				itemsOwned[entry.key] = true
			end
		end
		snapshot.itemsOwned = itemsOwned
		snapshot.starterPack = { bought = data.starterPackBought, dismissals = data.starterPackDismissals }
	end)

	Players.PlayerRemoving:Connect(function(player)
		cashCache[player] = nil
		lastDebug[player] = nil
	end)
end

return PurchaseService
