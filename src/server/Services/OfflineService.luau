--!strict
-- Staff keep working while the player is away: on join, pay an estimate of what the automated
-- bays and shelves would have earned (capped, at reduced efficiency) and show a popup.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Format = require(Shared.Format)
local Game = require(Shared.Config.Game)
local Problems = require(Shared.Config.Problems)
local Stations = require(Shared.Config.Stations)
local Shelves = require(Shared.Config.Shelves)

local PlayerData = require(script.Parent.PlayerData)
local PlotService = require(script.Parent.PlotService)
local UnlockService = require(script.Parent.UnlockService)
local HireService = require(script.Parent.HireService)
local EconomyService = require(script.Parent.EconomyService)
local CustomerService = require(script.Parent.CustomerService)

local OfflineService = {}

-- Average pay per second of a bay worked by its mechanic/painter (if it never waits for a car),
-- plus how many jobs per second that is.
local function bayRate(player: Player, bayIndex: number, station: string, staffLevel: number): (number, number)
	local level = math.max(1, UnlockService.stationLevel(player, station))
	local levelData = Stations.LEVELS[level]
	local totalPay, totalTime, count = 0, 0, 0
	for _, problem in Problems.list do
		local fixable = problem.station == station or problem.station == "any"
		local unlocked = problem.requiresUnlock == nil or UnlockService.isOwned(player, problem.requiresUnlock)
		if fixable and unlocked then
			totalPay += problem.basePay * levelData.payMult
			totalTime += problem.repairTime * levelData.timeMult
			count += 1
		end
	end
	if count == 0 or totalTime <= 0 then
		return 0, 0
	end
	local speed = Game.MECHANIC_SPEED[staffLevel] or Game.MECHANIC_SPEED[1]
	local manager = HireService.managerLevel(player)
	if manager > 0 then
		speed *= 1 + (Game.MANAGER_SPEED[manager] or 0)
	end
	local jobsPerSecond = speed / (totalTime / count)
	return (totalPay / count) * jobsPerSecond, jobsPerSecond
end

-- average items a walk-in shopper buys (ShopService.sell: math.random(1, 2))
local ITEMS_PER_SHOPPER = 1.5

local function estimatePerSecond(player: Player): number
	-- bays: staff can't fix more cars than customers bring in (one car per spawn interval)
	local bayPay, bayJobs = 0, 0
	local stations, bays = UnlockService.ownedBays(player)
	for _, bayIndex in bays do
		local staff = HireService.mechanicLevel(player, bayIndex)
		if staff then
			local pay, jobs = bayRate(player, bayIndex, stations[bayIndex], staff)
			bayPay += pay
			bayJobs += jobs
		end
	end
	local rate = bayPay
	local arrivals = 1 / math.max(CustomerService.spawnInterval(player), 0.1)
	if bayJobs > arrivals then
		rate *= arrivals / bayJobs
	end

	-- shelves: limited by both restocking and how many shoppers walk in (shared by all shelves)
	local stocker = HireService.stockerLevel(player)
	local restockSpeed = if stocker > 0 then Game.STOCKER_SPEED[stocker] or 1 else 1
	local restockRate, priceSum, shelfCount = 0, 0, 0
	for _, shelfId in Shelves.order do
		local level = UnlockService.level(player, shelfId)
		if level > 0 then
			local price = Shelves.byId[shelfId].basePrice * Shelves.LEVELS[level].priceMult
			restockRate += price * restockSpeed / Shelves.RESTOCK_SECONDS
			priceSum += price
			shelfCount += 1
		end
	end
	if shelfCount > 0 then
		local reception = HireService.receptionistLevel(player)
		local interval = Shelves.SHOPPER_INTERVAL * (if reception > 0 then Game.RECEPTION_SPAWN_MULT[reception] or 1 else 1)
		local demandRate = (priceSum / shelfCount) * ITEMS_PER_SHOPPER / interval
		rate += math.min(restockRate, demandRate)
	end
	return rate
end

local function grant(player: Player)
	local data = PlayerData.get(player)
	if not data or data.lastOnline <= 0 then
		return
	end
	local awaySeconds = math.min(os.time() - data.lastOnline, Game.OFFLINE_MAX_MINUTES * 60)
	if awaySeconds < 60 then
		return
	end
	local amount = math.floor(estimatePerSecond(player) * awaySeconds * Game.OFFLINE_EFFICIENCY * EconomyService.multiplier(player))
	if amount <= 0 then
		return
	end
	PlayerData.update(player, function(d)
		d.money += amount
		d.totalEarned += amount
	end)
	task.delay(2, function()
		if player.Parent then
			Remotes.get("OpenUI"):FireClient(player, "Offline", amount)
			Remotes.get("Notify"):FireClient(player, "notify_offline_earned", { Format.money(amount) })
		end
	end)
end

function OfflineService.start()
	PlotService.onAssigned(function(player)
		-- Let unlock/hire restoration finish so the estimate sees the whole garage.
		task.wait(1)
		grant(player)
	end)
end

return OfflineService
