--!strict
-- Daily login reward with a 7-day streak (missing a day restarts the streak).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Format = require(Shared.Format)
local Game = require(Shared.Config.Game)

local PlayerData = require(script.Parent.PlayerData)
local PlotService = require(script.Parent.PlotService)
local EconomyService = require(script.Parent.EconomyService)

local DailyService = {}

local function today(): number
	return math.floor(os.time() / 86400)
end

-- (available, the streak day this claim would be, reward)
local function status(player: Player, data: PlayerData.Data): (boolean, number, number)
	local day = today()
	local available = data.lastDailyDay ~= day
	local streak = if data.lastDailyDay == day - 1 then data.dailyStreak + 1 else 1
	if not available then
		streak = math.max(1, data.dailyStreak)
	end
	streak = math.min(streak, Game.DAILY_MAX_STREAK)
	local reward = math.floor(Game.DAILY_BASE * streak * EconomyService.multiplier(player))
	return available, streak, reward
end

local claiming: { [Player]: boolean } = {}

local function claim(player: Player): (boolean, string)
	local data = PlayerData.get(player)
	if not data or claiming[player] then
		return false, "notify_daily_already"
	end
	local available, streak, reward = status(player, data)
	if not available then
		Remotes.get("Notify"):FireClient(player, "notify_daily_already")
		return false, "notify_daily_already"
	end
	claiming[player] = true
	PlayerData.update(player, function(d)
		d.lastDailyDay = today()
		d.dailyStreak = streak
		d.money += reward
		d.totalEarned += reward
	end)
	claiming[player] = nil
	Remotes.get("Notify"):FireClient(player, "notify_daily_claimed", { Format.money(reward) })
	return true, "notify_daily_claimed"
end

function DailyService.start()
	Remotes.get("ClaimDaily").OnServerInvoke = claim
	PlayerData.addSnapshotField(function(player, data, snapshot)
		local available, streak, reward = status(player, data)
		snapshot.daily = { available = available, streak = streak, reward = reward }
	end)
	PlotService.onAssigned(function(player)
		task.wait(4)
		local data = PlayerData.get(player)
		-- Don't interrupt the first-time tutorial.
		if data and data.tutorialStep >= 4 and (status(player, data)) then
			Remotes.get("OpenUI"):FireClient(player, "Daily")
		end
	end)
end

return DailyService
