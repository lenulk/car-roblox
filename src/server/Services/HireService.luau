--!strict
-- Job board, hiring (first hire per account is free), and the staff NPCs on each plot.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Layout = require(Shared.Layout)
local Remotes = require(Shared.Remotes)
local Format = require(Shared.Format)
local Strings = require(Shared.Config.Strings)
local Employees = require(Shared.Config.Employees)

local PlayerData = require(script.Parent.PlayerData)
local PlotService = require(script.Parent.PlotService)
local UnlockService = require(script.Parent.UnlockService)
local EconomyService = require(script.Parent.EconomyService)
local EmployeeService = require(script.Parent.EmployeeService)
local MapBuilder = require(script.Parent.MapBuilder)

local HireService = {}

local boardPrompts: { [number]: ProximityPrompt } = {}
local hiring: { [Player]: boolean } = {}

-- The slot a new employee of this role would take, or nil + reason string key.
local function freeSlot(player: Player, role: string): (string?, string?)
	local config = Employees.byId[role]
	local data = PlayerData.get(player)
	if not config or not data then
		return nil, "hire_no_slot"
	end
	if config.requiresUnlock and not UnlockService.isOwned(player, config.requiresUnlock) then
		return nil, "hire_locked_needs_cashier"
	end
	local taken: { [string]: boolean } = {}
	for _, employee in data.employees do
		taken[employee.slot] = true
	end
	if config.slotKind == "Cashier" then
		return if taken.Cashier then nil else "Cashier", if taken.Cashier then "hire_no_slot" else nil
	end
	local _, bays = UnlockService.ownedBays(player)
	for _, bayIndex in bays do
		local slot = "Bay" .. bayIndex
		if not taken[slot] then
			return slot, nil
		end
	end
	return nil, "hire_no_slot"
end

local function priceFor(player: Player, role: string): number
	local data = PlayerData.get(player)
	local config = Employees.byId[role]
	if not data or not config then
		return math.huge
	end
	return if data.freeHireUsed then config.price else 0
end

function HireService.employeeAt(player: Player, slot: string): PlayerData.Employee?
	local data = PlayerData.get(player)
	if not data then
		return nil
	end
	for _, employee in data.employees do
		if employee.slot == slot then
			return employee
		end
	end
	return nil
end

function HireService.mechanicLevel(player: Player, bayIndex: number): number?
	local employee = HireService.employeeAt(player, "Bay" .. bayIndex)
	return if employee and employee.role == "mechanic" then employee.level else nil
end

function HireService.hasCashier(player: Player): boolean
	local employee = HireService.employeeAt(player, "Cashier")
	return employee ~= nil and employee.role == "cashier"
end

-- Live NPC models, so RepairService can toggle the "working" look.
local npcs: { [number]: { [string]: Model } } = {}

function HireService.npcAt(plotIndex: number, slot: string): Model?
	local plotNpcs = npcs[plotIndex]
	return if plotNpcs then plotNpcs[slot] else nil
end

local function spawnNpc(plotIndex: number, employee: PlayerData.Employee)
	npcs[plotIndex] = npcs[plotIndex] or {}
	local ok, model = pcall(EmployeeService.spawn, plotIndex, employee.role, employee.slot, employee.level)
	if ok then
		npcs[plotIndex][employee.slot] = model
	else
		warn("[HireService] Could not spawn employee: " .. tostring(model))
	end
end

local function hire(player: Player, role: any): (boolean, string)
	if type(role) ~= "string" or not Employees.byId[role] then
		return false, "hire_no_slot"
	end
	if hiring[player] then
		return false, "hire_no_slot"
	end
	local plotIndex = PlotService.getPlotIndex(player)
	local data = PlayerData.get(player)
	if not plotIndex or not data then
		return false, "hire_no_slot"
	end
	local slot, reason = freeSlot(player, role)
	if not slot then
		local key = reason or "hire_no_slot"
		Remotes.get("Notify"):FireClient(player, key)
		return false, key
	end
	local price = priceFor(player, role)
	if data.money < price then
		Remotes.get("Notify"):FireClient(player, "notify_not_enough_money", { Format.money(price - data.money) })
		return false, "notify_not_enough_money"
	end

	hiring[player] = true
	local ok = price == 0 or PlayerData.trySpend(player, price)
	if ok then
		local employee: PlayerData.Employee = { role = role, level = 1, slot = slot :: string }
		PlayerData.update(player, function(d)
			table.insert(d.employees, employee)
			d.freeHireUsed = true
			if d.tutorialStep < 3 then
				d.tutorialStep = 3
			end
		end)
		spawnNpc(plotIndex, employee)
		local npc = HireService.npcAt(plotIndex, employee.slot)
		local position = if npc then npc:GetPivot().Position else Layout.toWorld(plotIndex, Layout.HIRE_BOARD).Position
		Remotes.get("Effect"):FireClient(player, "Unlock", position)
		Remotes.get("Notify"):FireClient(player, "notify_hired", { Strings.get(data.settings.lang, "role_" .. role) })
	end
	hiring[player] = nil
	return ok, if ok then "hire_ok" else "notify_not_enough_money"
end

local function createBoardPrompt(plotIndex: number)
	local plot = MapBuilder.getPlot(plotIndex)
	local board = plot:WaitForChild("Static"):WaitForChild("HireBoard")
	local anchor = (board :: Model).PrimaryPart or board:FindFirstChildWhichIsA("BasePart", true)
	if not anchor then
		warn("[HireService] HireBoard has no part on plot " .. plotIndex)
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = Strings.get("th", "prompt_hire")
	prompt.ObjectText = Strings.get("th", "object_hire_board")
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("OwnerUserId", 0)
	prompt:SetAttribute("ActionKey", "prompt_hire")
	prompt:SetAttribute("ObjectKey", "object_hire_board")
	prompt.Parent = anchor
	prompt.Triggered:Connect(function(player)
		if PlotService.getPlotIndex(player) == plotIndex then
			Remotes.get("OpenUI"):FireClient(player, "Hire")
		end
	end)
	boardPrompts[plotIndex] = prompt
end

function HireService.start()
	EconomyService.setCashierCheck(HireService.hasCashier)

	for plotIndex = 1, Layout.PLOT_COUNT do
		createBoardPrompt(plotIndex)
	end

	Remotes.get("HireEmployee").OnServerInvoke = function(player: Player, role: any)
		return hire(player, role)
	end

	PlotService.onAssigned(function(player, plotIndex)
		local prompt = boardPrompts[plotIndex]
		if prompt then
			prompt:SetAttribute("OwnerUserId", player.UserId)
		end
		local data = PlayerData.get(player)
		if data then
			for _, employee in data.employees do
				spawnNpc(plotIndex, employee)
			end
		end
	end)

	PlotService.onReleased(function(player, plotIndex)
		local prompt = boardPrompts[plotIndex]
		if prompt then
			prompt:SetAttribute("OwnerUserId", 0)
		end
		EmployeeService.clearPlot(plotIndex)
		npcs[plotIndex] = nil
		hiring[player] = nil
	end)

	PlayerData.addSnapshotField(function(player, data, snapshot)
		snapshot.employees = table.clone(data.employees)
		local options = {}
		for _, config in Employees.list do
			local slot, reason = freeSlot(player, config.id)
			table.insert(options, {
				role = config.id,
				price = priceFor(player, config.id),
				available = slot ~= nil,
				reasonKey = reason,
			})
		end
		snapshot.hireOptions = options
	end)
end

return HireService
