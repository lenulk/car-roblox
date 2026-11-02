--!strict
-- Job board, hiring (first hire per account is free), staff upgrades, and the staff NPCs.
-- Slots: "Bay1".."Bay4" (mechanic for bays 1-3, painter for bay 4), "Cashier", "Stock", "Reception", "Office".

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

local MAX_LEVEL = 5

local boardPrompts: { [number]: ProximityPrompt } = {}
local busy: { [Player]: boolean } = {}

local function employeesOf(player: Player): { PlayerData.Employee }
	local data = PlayerData.get(player)
	return if data then data.employees else {}
end

function HireService.employeeAt(player: Player, slot: string): PlayerData.Employee?
	for _, employee in employeesOf(player) do
		if employee.slot == slot then
			return employee
		end
	end
	return nil
end

local function levelOf(player: Player, slot: string, role: string): number
	local employee = HireService.employeeAt(player, slot)
	return if employee and employee.role == role then employee.level else 0
end

-- Level of the mechanic/painter working at a bay, or nil.
function HireService.mechanicLevel(player: Player, bayIndex: number): number?
	local employee = HireService.employeeAt(player, "Bay" .. bayIndex)
	if employee and (employee.role == "mechanic" or employee.role == "painter") then
		return employee.level
	end
	return nil
end

function HireService.cashierLevel(player: Player): number
	return levelOf(player, "Cashier", "cashier")
end

function HireService.stockerLevel(player: Player): number
	return levelOf(player, "Stock", "stocker")
end

function HireService.receptionistLevel(player: Player): number
	return levelOf(player, "Reception", "receptionist")
end

function HireService.managerLevel(player: Player): number
	return levelOf(player, "Office", "manager")
end

function HireService.hasCashier(player: Player): boolean
	return HireService.cashierLevel(player) > 0
end

-- The slot a new employee of this role would take, or nil + a Strings key explaining why not.
local function freeSlot(player: Player, role: string): (string?, string?)
	local config = Employees.byId[role]
	if not config or not PlayerData.get(player) then
		return nil, "hire_no_slot"
	end
	if config.requiresUnlock and not UnlockService.isOwned(player, config.requiresUnlock) then
		return nil, config.lockedKey or "hire_no_slot"
	end
	if config.slotKind == "Bay" then
		local _, owned = UnlockService.ownedBays(player)
		local allowed: { [number]: boolean } = {}
		for _, bay in config.bays or {} do
			allowed[bay] = true
		end
		for _, bayIndex in owned do
			local slot = "Bay" .. bayIndex
			if allowed[bayIndex] and not HireService.employeeAt(player, slot) then
				return slot, nil
			end
		end
		return nil, "hire_no_slot"
	end
	local slot = config.slotKind
	if HireService.employeeAt(player, slot) then
		return nil, "hire_no_slot"
	end
	return slot, nil
end

local function priceFor(player: Player, role: string): number
	local data = PlayerData.get(player)
	local config = Employees.byId[role]
	if not data or not config then
		return math.huge
	end
	return if data.freeHireUsed then config.price else 0
end

local function upgradeCost(employee: PlayerData.Employee): number?
	local config = Employees.byId[employee.role]
	if not config or employee.level >= MAX_LEVEL then
		return nil
	end
	return math.floor(config.price * Employees.UPGRADE_COST_MULT[employee.level])
end

-- Live NPC models per plot/slot so RepairService can toggle the "working" look.
local npcs: { [number]: { [string]: Model } } = {}

function HireService.npcAt(plotIndex: number, slot: string): Model?
	local plotNpcs = npcs[plotIndex]
	return if plotNpcs then plotNpcs[slot] else nil
end

local function spawnNpc(plotIndex: number, employee: PlayerData.Employee)
	npcs[plotIndex] = npcs[plotIndex] or {}
	local ok, model = pcall(EmployeeService.spawn, plotIndex, employee.role, employee.slot, employee.level)
	if ok and model then
		npcs[plotIndex][employee.slot] = model
	else
		warn("[HireService] Could not spawn employee: " .. tostring(model))
	end
end

local function notify(player: Player, key: string, args: { any }?)
	Remotes.get("Notify"):FireClient(player, key, args)
end

local function hire(player: Player, role: any): (boolean, string)
	if type(role) ~= "string" or not Employees.byId[role] or busy[player] then
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
		notify(player, key)
		return false, key
	end
	local price = priceFor(player, role)
	if data.money < price then
		notify(player, "notify_not_enough_money", { Format.money(price - data.money) })
		return false, "notify_not_enough_money"
	end

	busy[player] = true
	local employee: PlayerData.Employee = { role = role, level = 1, slot = slot :: string }
	PlayerData.update(player, function(d)
		d.money -= price
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
	notify(player, "notify_hired", { Strings.get(data.settings.lang, "role_" .. role) })
	busy[player] = nil
	return true, "hire_ok"
end

local function upgradeEmployee(player: Player, slot: any): (boolean, string)
	if type(slot) ~= "string" or busy[player] then
		return false, "hire_max_level"
	end
	local plotIndex = PlotService.getPlotIndex(player)
	local data = PlayerData.get(player)
	local employee = HireService.employeeAt(player, slot)
	if not plotIndex or not data or not employee then
		return false, "hire_max_level"
	end
	local cost = upgradeCost(employee)
	if not cost then
		notify(player, "hire_max_level")
		return false, "hire_max_level"
	end
	if data.money < cost then
		notify(player, "notify_not_enough_money", { Format.money(cost - data.money) })
		return false, "notify_not_enough_money"
	end
	busy[player] = true
	PlayerData.update(player, function(d)
		d.money -= cost
		employee.level += 1
	end)
	local npc = HireService.npcAt(plotIndex, slot)
	if npc then
		pcall(EmployeeService.setLevel, npc, employee.level)
		Remotes.get("Effect"):FireClient(player, "Level", npc:GetPivot().Position)
	end
	notify(player, "notify_employee_upgraded", { Strings.get(data.settings.lang, "role_" .. employee.role), employee.level })
	busy[player] = nil
	return true, "notify_employee_upgraded"
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

function HireService.spawnAll(player: Player, plotIndex: number)
	for _, employee in employeesOf(player) do
		spawnNpc(plotIndex, employee)
	end
end

function HireService.clearPlot(plotIndex: number)
	pcall(EmployeeService.clearPlot, plotIndex)
	npcs[plotIndex] = nil
end

function HireService.start()
	EconomyService.setCashierLevel(HireService.cashierLevel)

	for plotIndex = 1, Layout.PLOT_COUNT do
		createBoardPrompt(plotIndex)
	end

	Remotes.get("HireEmployee").OnServerInvoke = hire
	Remotes.get("UpgradeEmployee").OnServerInvoke = upgradeEmployee

	PlotService.onAssigned(function(player, plotIndex)
		local prompt = boardPrompts[plotIndex]
		if prompt then
			prompt:SetAttribute("OwnerUserId", player.UserId)
		end
		HireService.spawnAll(player, plotIndex)
	end)

	PlotService.onReleased(function(player, plotIndex)
		local prompt = boardPrompts[plotIndex]
		if prompt then
			prompt:SetAttribute("OwnerUserId", 0)
		end
		HireService.clearPlot(plotIndex)
		busy[player] = nil
	end)

	PlayerData.addSnapshotField(function(player, data, snapshot)
		local list = {}
		for _, employee in data.employees do
			table.insert(list, {
				role = employee.role,
				level = employee.level,
				slot = employee.slot,
				upgradeCost = upgradeCost(employee),
			})
		end
		snapshot.employees = list
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
