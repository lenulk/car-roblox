--!strict
-- Rebirth: once everything in the garage is bought, restart it for a permanent income bonus.
-- Keeps cars, car parts, themes, settings, stars history counters and the free-hire flag.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Layout = require(Shared.Layout)
local Remotes = require(Shared.Remotes)
local Game = require(Shared.Config.Game)
local Unlocks = require(Shared.Config.Unlocks)

local PlayerData = require(script.Parent.PlayerData)
local PlotService = require(script.Parent.PlotService)
local UnlockService = require(script.Parent.UnlockService)
local HireService = require(script.Parent.HireService)
local ShowcaseService = require(script.Parent.ShowcaseService)
local CustomerService = require(script.Parent.CustomerService)
local ShopService = require(script.Parent.ShopService)
local ThemeService = require(script.Parent.ThemeService)
local EconomyService = require(script.Parent.EconomyService)

local RebirthService = {}

local busy: { [Player]: boolean } = {}

local function rebirth(player: Player): (boolean, string)
	local plotIndex = PlotService.getPlotIndex(player)
	local data = PlayerData.get(player)
	if not plotIndex or not data or busy[player] then
		return false, "notify_rebirth_locked"
	end
	if not UnlockService.allOwned(player) then
		Remotes.get("Notify"):FireClient(player, "notify_rebirth_locked")
		return false, "notify_rebirth_locked"
	end
	busy[player] = true
	-- always release the lock, even if a reset step errors
	local ok, err = pcall(function()
		HireService.clearPlot(plotIndex)
		UnlockService.resetPlot(plotIndex)
		PlayerData.update(player, function(d)
			d.rebirths += 1
			d.money = Game.STARTING_MONEY
			d.safe = 0
			d.starPoints = 0
			-- the race track is personal (like cars): it stays owned
			local kept: { [string]: boolean } = {}
			for _, entry in Unlocks.list do
				if (entry :: any).keepOnRebirth and d.unlocks[entry.id] then
					kept[entry.id] = true
				end
			end
			d.unlocks = kept
			d.levels = {}
			d.stock = {}
			d.employees = {}
			for _, entry in Unlocks.list do
				if entry.startOwned then
					d.unlocks[entry.id] = true
					if entry.upgradable then
						d.levels[entry.id] = 1
					end
				end
			end
		end)
		UnlockService.restorePlot(player, plotIndex)
		ShowcaseService.refresh(player)
		ThemeService.applyPlot(plotIndex)
		CustomerService.restart(player, plotIndex)
		ShopService.restart(player, plotIndex)
	
		local multiplier = EconomyService.multiplier(player)
		Remotes.get("Effect"):FireClient(player, "Level", Layout.toWorld(plotIndex, Layout.GATE).Position + Vector3.new(0, 16, 0))
		Remotes.get("Notify"):FireClient(player, "notify_rebirth_done", { string.format("%.1f", multiplier) })
	end)
	busy[player] = nil
	if not ok then
		warn("[RebirthService] rebirth failed: " .. tostring(err))
		return false, "notify_rebirth_locked"
	end
	return true, "notify_rebirth_done"
end

function RebirthService.start()
	Remotes.get("Rebirth").OnServerInvoke = rebirth
	PlayerData.addSnapshotField(function(player, data, snapshot)
		local multiplier = EconomyService.multiplier(player)
		snapshot.rebirth = {
			count = data.rebirths,
			multiplier = multiplier,
			canRebirth = UnlockService.allOwned(player),
			nextMultiplier = multiplier
				* (1 + (data.rebirths + 1) * Game.REBIRTH_BONUS)
				/ (1 + data.rebirths * Game.REBIRTH_BONUS),
		}
	end)
end

return RebirthService
