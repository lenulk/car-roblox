--!strict
-- Where earned money goes: into the plot's safe (walk over the pad to collect) or, with a
-- cashier hired, straight into the wallet. Also owns star points / star level.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Layout = require(Shared.Layout)
local Remotes = require(Shared.Remotes)
local Format = require(Shared.Format)
local Game = require(Shared.Config.Game)

local PlayerData = require(script.Parent.PlayerData)
local PlotService = require(script.Parent.PlotService)
local MapBuilder = require(script.Parent.MapBuilder)

local EconomyService = {}

local hasCashier: (Player) -> boolean = function()
	return false
end

-- HireService registers itself here (avoids a require cycle).
function EconomyService.setCashierCheck(fn: (Player) -> boolean)
	hasCashier = fn
end

function EconomyService.starLevel(points: number): number
	local level = 0
	for i, threshold in Game.STAR_THRESHOLDS do
		if points >= threshold then
			level = i
		end
	end
	return level
end

local function safeLabel(plotIndex: number): TextLabel?
	local plot = MapBuilder.getPlot(plotIndex)
	local static = plot:FindFirstChild("Static")
	local safe = static and static:FindFirstChild("Safe")
	local label = safe and safe:FindFirstChild("AmountLabel", true)
	return if label and label:IsA("TextLabel") then label else nil
end

local function refreshSafeLabel(plotIndex: number, amount: number)
	local label = safeLabel(plotIndex)
	if label then
		label.Text = Format.money(amount)
	end
end

local function safePosition(plotIndex: number): Vector3
	return Layout.toWorld(plotIndex, Layout.SAFE).Position + Vector3.new(0, 4, 0)
end

-- Pays the player for finished work. Returns where it went: "wallet" or "safe".
function EconomyService.earn(player: Player, amount: number): string
	amount = math.floor(amount)
	local direct = hasCashier(player)
	PlayerData.update(player, function(data)
		if direct then
			data.money += amount
		else
			data.safe += amount
		end
	end)
	local plotIndex = PlotService.getPlotIndex(player)
	local data = PlayerData.get(player)
	if plotIndex and data then
		refreshSafeLabel(plotIndex, data.safe)
	end
	return if direct then "wallet" else "safe"
end

function EconomyService.collectSafe(player: Player)
	local data = PlayerData.get(player)
	local plotIndex = PlotService.getPlotIndex(player)
	if not data or not plotIndex or data.safe <= 0 then
		return
	end
	local amount = data.safe
	PlayerData.update(player, function(d)
		d.money += d.safe
		d.safe = 0
	end)
	refreshSafeLabel(plotIndex, 0)
	Remotes.get("Effect"):FireClient(player, "Cash", safePosition(plotIndex), "+" .. Format.money(amount))
	Remotes.get("Notify"):FireClient(player, "notify_collected", { Format.money(amount) })
end

function EconomyService.addStarPoint(player: Player)
	local data = PlayerData.get(player)
	if not data then
		return
	end
	local before = EconomyService.starLevel(data.starPoints)
	PlayerData.update(player, function(d)
		d.starPoints += 1
	end)
	local after = EconomyService.starLevel(data.starPoints)
	if after > before then
		Remotes.get("Notify"):FireClient(player, "notify_star_up", { after })
		local plotIndex = PlotService.getPlotIndex(player)
		if plotIndex then
			Remotes.get("Effect"):FireClient(player, "Unlock", Layout.toWorld(plotIndex, Layout.GATE).Position + Vector3.new(0, 16, 0))
		end
	end
end

local lastTouch: { [Player]: number } = {}

local function connectPad(plotIndex: number)
	local plot = MapBuilder.getPlot(plotIndex)
	local static = plot:WaitForChild("Static")
	local safe = static:WaitForChild("Safe")
	local pad = safe:FindFirstChild("CollectPad") or static:FindFirstChild("CollectPad", true)
	if not pad or not pad:IsA("BasePart") then
		warn("[EconomyService] CollectPad missing on plot " .. plotIndex)
		return
	end
	pad.Touched:Connect(function(hit)
		local character: any = hit.Parent
		local player = if character then Players:GetPlayerFromCharacter(character) else nil
		if not player or PlotService.getPlotIndex(player) ~= plotIndex then
			return
		end
		local now = os.clock()
		if lastTouch[player] and now - lastTouch[player] < 0.5 then
			return
		end
		lastTouch[player] = now
		EconomyService.collectSafe(player)
	end)
end

function EconomyService.start()
	for plotIndex = 1, Layout.PLOT_COUNT do
		connectPad(plotIndex)
		refreshSafeLabel(plotIndex, 0)
	end

	PlotService.onAssigned(function(player, plotIndex)
		local data = PlayerData.get(player)
		refreshSafeLabel(plotIndex, if data then data.safe else 0)
	end)
	PlotService.onReleased(function(player, plotIndex)
		refreshSafeLabel(plotIndex, 0)
		lastTouch[player] = nil
	end)

	PlayerData.addSnapshotField(function(_player, data, snapshot)
		local level = EconomyService.starLevel(data.starPoints)
		snapshot.starLevel = level
		snapshot.nextStarAt = Game.STAR_THRESHOLDS[level + 1]
	end)

	-- A hired cashier empties the safe into the wallet on a timer.
	task.spawn(function()
		while true do
			task.wait(Game.CASHIER_COLLECT_INTERVAL)
			for _, player in Players:GetPlayers() do
				local data = PlayerData.get(player)
				if data and data.safe > 0 and hasCashier(player) then
					EconomyService.collectSafe(player)
				end
			end
		end
	end)
end

return EconomyService
