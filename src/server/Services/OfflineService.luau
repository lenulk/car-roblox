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

local OfflineService = {}

-- Average pay per second of a bay worked by its mechanic/painter.
local function bayRate(player: Player, bayIndex: number, station: string, staffLevel: number): number
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
		return 0
	end
	local speed = Game.MECHANIC_SPEED[staffLevel] or Game.MECHANIC_SPEED[1]
	return (totalPay / count) / ((totalTime / count) / speed)
end

local function estimatePerSecond(player: Player): number
	local rate = 0
	local stations, bays = UnlockService.ownedBays(player)
	for _, bayIndex in bays do
		local staff = HireService.mechanicLevel(player, bayIndex)
		if staff then
			rate += bayRate(player, bayIndex, stations[bayIndex], staff)
		end
	end
	local stocker = HireService.stockerLevel(player)
	local restockSpeed = if stocker > 0 then Game.STOCKER_SPEED[stocker] or 1 else 1
	for _, shelfId in Shelves.order do
		local level = UnlockService.level(player, shelfId)
		if level > 0 then
			local price = Shelves.byId[shelfId].basePrice * Shelves.LEVELS[level].priceMult
			rate += price * restockSpeed / Shelves.RESTOCK_SECONDS
		end
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
