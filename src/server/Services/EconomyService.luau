--!strict
-- Where earned money goes: into the plot's safe (walk over the pad to collect) or, with a cashier
-- or the AutoCollect pass, straight into the wallet. Applies the income multiplier
-- (DoubleMoney pass × cashier bonus). Owns star points and the player-list leaderstats.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Layout = require(Shared.Layout)
local Remotes = require(Shared.Remotes)
local Format = require(Shared.Format)
local Game = require(Shared.Config.Game)

local PlayerData = require(script.Parent.PlayerData)
local PlotService = require(script.Parent.PlotService)
local MapBuilder = require(script.Parent.MapBuilder)
local GamePassService = require(script.Parent.GamePassService)

local EconomyService = {}

-- HireService registers the cashier's level here (0 = no cashier); avoids a require cycle.
local cashierLevel: (Player) -> number = function()
	return 0
end

function EconomyService.setCashierLevel(fn: (Player) -> number)
	cashierLevel = fn
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

-- DoubleMoney pass. Shown in the HUD.
function EconomyService.multiplier(player: Player): number
	local m = 1
	if GamePassService.owns(player, "DoubleMoney") then
		m *= GamePassService.value("DoubleMoney")
	end
	return m
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

local function goesToWallet(player: Player): boolean
	return cashierLevel(player) > 0 or GamePassService.owns(player, "AutoCollect")
end

-- Pays the player for finished work; returns the final amount after multipliers.
function EconomyService.earn(player: Player, baseAmount: number): number
	local level = cashierLevel(player)
	local bonus = if level > 0 then (Game.CASHIER_BONUS[level] or 0) else 0
	local amount = math.floor(baseAmount * EconomyService.multiplier(player) * (1 + bonus) + 0.5)
	if amount <= 0 then
		return 0
	end
	local direct = goesToWallet(player)
	PlayerData.update(player, function(data)
		if direct then
			data.money += amount
		else
			data.safe += amount
		end
		data.totalEarned += amount
	end)
	local plotIndex = PlotService.getPlotIndex(player)
	local data = PlayerData.get(player)
	if plotIndex and data then
		refreshSafeLabel(plotIndex, data.safe)
	end
	return amount
end

function EconomyService.collectSafe(player: Player, quiet: boolean?)
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
	if not quiet then
		Remotes.get("Notify"):FireClient(player, "notify_collected", { Format.money(amount) })
	end
end

function EconomyService.addStarPoint(player: Player, points: number?)
	local data = PlayerData.get(player)
	if not data then
		return
	end
	local before = EconomyService.starLevel(data.starPoints)
	PlayerData.update(player, function(d)
		d.starPoints += points or 1
	end)
	local after = EconomyService.starLevel(data.starPoints)
	if after > before then
		Remotes.get("Notify"):FireClient(player, "notify_star_up", { after })
		local plotIndex = PlotService.getPlotIndex(player)
		if plotIndex then
			Remotes.get("Effect"):FireClient(player, "Level", Layout.toWorld(plotIndex, Layout.GATE).Position + Vector3.new(0, 16, 0))
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

local function leaderstats(player: Player): (IntValue?, IntValue?)
	local folder = player:FindFirstChild("leaderstats")
	if not folder then
		local f = Instance.new("Folder")
		f.Name = "leaderstats"
		local money = Instance.new("IntValue")
		money.Name = "Money"
		money.Parent = f
		local stars = Instance.new("IntValue")
		stars.Name = "Stars"
		stars.Parent = f
		f.Parent = player
		folder = f
	end
	local money = (folder :: Instance):FindFirstChild("Money")
	local stars = (folder :: Instance):FindFirstChild("Stars")
	return (if money and money:IsA("IntValue") then money else nil), (if stars and stars:IsA("IntValue") then stars else nil)
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

	PlayerData.addSnapshotField(function(player, data, snapshot)
		local level = EconomyService.starLevel(data.starPoints)
		snapshot.starLevel = level
		snapshot.nextStarAt = Game.STAR_THRESHOLDS[level + 1]
		snapshot.multiplier = EconomyService.multiplier(player)
		local money, stars = leaderstats(player)
		if money then
			money.Value = math.clamp(math.floor(data.money), 0, 2 ^ 31 - 1)
		end
		if stars then
			stars.Value = level
		end
	end)

	-- Cashier / AutoCollect empty whatever is still in the safe (e.g. from before hiring).
	task.spawn(function()
		while true do
			task.wait(Game.CASHIER_COLLECT_INTERVAL)
			for _, player in Players:GetPlayers() do
				local data = PlayerData.get(player)
				if data and data.safe > 0 and goesToWallet(player) then
					EconomyService.collectSafe(player, true)
				end
			end
		end
	end)
end

return EconomyService
