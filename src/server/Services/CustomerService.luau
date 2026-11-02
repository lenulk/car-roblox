--!strict
-- Customer cars for each owned plot: spawn on the ring, wait in the queue, move into a matching
-- bay, get repaired (RepairService), pay, then drive away. Customers never leave unhappy.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Layout = require(Shared.Layout)
local Remotes = require(Shared.Remotes)
local Format = require(Shared.Format)
local CarBuilder = require(Shared.CarBuilder)
local Game = require(Shared.Config.Game)
local Problems = require(Shared.Config.Problems)
local CarTypes = require(Shared.Config.CarTypes)
local Stations = require(Shared.Config.Stations)

local PlayerData = require(script.Parent.PlayerData)
local PlotService = require(script.Parent.PlotService)
local UnlockService = require(script.Parent.UnlockService)
local EconomyService = require(script.Parent.EconomyService)
local TrafficService = require(script.Parent.TrafficService)
local RepairService = require(script.Parent.RepairService)

local CustomerService = {}

type Customer = {
	model: Model,
	problemId: string,
	carTypeId: string,
	queueIndex: number?,
	bayIndex: number?,
	queuedAt: number,
	state: string,
}

type PlotState = {
	player: Player,
	queue: { [number]: Customer },
	bays: { [number]: Customer },
	customers: { [Customer]: boolean },
	alive: boolean,
}

local plots: { [number]: PlotState } = {}
local carsFolder: Folder

local function setState(customer: Customer, state: string)
	customer.state = state
	customer.model:SetAttribute("State", state)
end

local function stationLevel(_player: Player, _stationId: string): number
	return 1 -- station upgrades arrive in phase 2
end

local function repairTimeFor(player: Player, problemId: string, bayStation: string): number
	local problem = Problems.byId[problemId]
	local stationId = if problem.station == "any" then bayStation else problem.station
	local level = stationLevel(player, stationId)
	return problem.repairTime * Stations.LEVELS[level].timeMult
end

local function availableProblems(player: Player): { string }
	local bayStations = UnlockService.ownedBays(player)
	local stationOwned: { [string]: boolean } = {}
	local anyBay = false
	for _, station in bayStations do
		stationOwned[station] = true
		anyBay = true
	end
	local result = {}
	for _, problem in Problems.list do
		local unlocked = problem.requiresUnlock == nil or UnlockService.isOwned(player, problem.requiresUnlock)
		local fixable = if problem.station == "any" then anyBay else stationOwned[problem.station] == true
		if unlocked and fixable then
			table.insert(result, problem.id)
		end
	end
	return result
end

local function pickCarType(): string
	local total = 0
	for _, carType in CarTypes.list do
		total += carType.weight
	end
	local roll = math.random() * total
	for _, carType in CarTypes.list do
		roll -= carType.weight
		if roll <= 0 then
			return carType.id
		end
	end
	return CarTypes.list[1].id
end

local function spawnInterval(player: Player): number
	local data = PlayerData.get(player)
	local stars = if data then EconomyService.starLevel(data.starPoints) else 0
	return math.max(Game.SPAWN_INTERVAL_MIN, Game.SPAWN_INTERVAL_BASE - stars * Game.SPAWN_INTERVAL_PER_STAR)
end

local function removeCustomer(state: PlotState, customer: Customer)
	state.customers[customer] = nil
	if customer.queueIndex and state.queue[customer.queueIndex] == customer then
		state.queue[customer.queueIndex] = nil
	end
	if customer.bayIndex and state.bays[customer.bayIndex] == customer then
		state.bays[customer.bayIndex] = nil
	end
	RepairService.detach(customer.model)
	TrafficService.stop(customer.model)
	customer.model:Destroy()
end

local dispatch: (plotIndex: number) -> ()

local function pay(plotIndex: number, state: PlotState, customer: Customer, bayIndex: number, startedAt: number, repairTime: number)
	local player = state.player
	local problem = Problems.byId[customer.problemId]
	local carType = CarTypes.byId[customer.carTypeId]
	local level = stationLevel(player, problem.station)
	local amount = math.floor(problem.basePay * carType.payMult * Stations.LEVELS[level].payMult + 0.5)
	local fast = os.clock() - startedAt <= repairTime * Game.TIP_WINDOW_FACTOR + Game.TIP_WINDOW_BONUS
	local tip = if fast then math.max(1, math.floor(amount * Game.TIP_PERCENT + 0.5)) else 0

	EconomyService.earn(player, amount + tip)
	EconomyService.addStarPoint(player)
	PlayerData.update(player, function(data)
		data.carsRepaired += 1
		if data.tutorialStep == 1 then
			data.tutorialStep = 2
		end
	end)

	local root = customer.model.PrimaryPart
	local position = if root then root.Position + Vector3.new(0, 6, 0) else Layout.pointToWorld(plotIndex, Vector3.zero)
	Remotes.get("Effect"):FireClient(player, "Cash", position, "+" .. Format.money(amount + tip))
	Remotes.get("Notify"):FireClient(player, "notify_repaired", { Format.money(amount) })
	if tip > 0 then
		Remotes.get("Notify"):FireClient(player, "notify_tip", { Format.money(tip) })
	end

	-- Leave the bay and free it for the next car.
	setState(customer, "Leaving")
	state.bays[bayIndex] = nil
	customer.bayIndex = nil
	dispatch(plotIndex)

	local path = Layout.departurePath(plotIndex, bayIndex)
	local lotPath = { path[1], path[2] }
	local roadPath = table.move(path, 3, #path, 1, {})
	if TrafficService.drive(customer.model, lotPath, Game.LOT_SPEED) then
		TrafficService.drive(customer.model, roadPath, Game.ROAD_SPEED)
	end
	if state.customers[customer] then
		removeCustomer(state, customer)
	end
end

local function moveToBay(plotIndex: number, state: PlotState, customer: Customer, bayIndex: number, bayStation: string)
	local queueIndex = customer.queueIndex :: number
	state.queue[queueIndex] = nil
	customer.queueIndex = nil
	customer.bayIndex = bayIndex
	state.bays[bayIndex] = customer
	setState(customer, "ToBay")

	local ok = TrafficService.drive(
		customer.model,
		Layout.queueToBayPath(plotIndex, queueIndex, bayIndex),
		Game.LOT_SPEED,
		Layout.toWorld(plotIndex, Layout.BAYS[bayIndex].car)
	)
	if not ok or not state.alive or not state.customers[customer] then
		return
	end

	setState(customer, "InBay")
	PlayerData.push(state.player) -- the guide arrow may now point at this car
	local repairTime = repairTimeFor(state.player, customer.problemId, bayStation)
	local startedAt = os.clock()
	RepairService.attach({
		model = customer.model,
		player = state.player,
		plotIndex = plotIndex,
		bayIndex = bayIndex,
		problemId = customer.problemId,
		repairTime = repairTime,
		onComplete = function()
			if state.alive and state.customers[customer] then
				pay(plotIndex, state, customer, bayIndex, startedAt, repairTime)
			end
		end,
	})
end

dispatch = function(plotIndex: number)
	local state = plots[plotIndex]
	if not state or not state.alive then
		return
	end
	local stations, bays = UnlockService.ownedBays(state.player)
	for _, bayIndex in bays do
		if not state.bays[bayIndex] then
			local station = stations[bayIndex]
			-- Oldest waiting car this bay can fix.
			local best: Customer? = nil
			for _, customer in state.queue do
				if customer.state == "Queued" then
					local problem = Problems.byId[customer.problemId]
					if problem.station == "any" or problem.station == station then
						if not best or customer.queuedAt < (best :: Customer).queuedAt then
							best = customer
						end
					end
				end
			end
			if best then
				task.spawn(moveToBay, plotIndex, state, best, bayIndex, station)
			end
		end
	end
end

local function freeQueueIndex(state: PlotState): number?
	local capacity = UnlockService.queueCapacity(state.player)
	for i = 1, capacity do
		if not state.queue[i] then
			return i
		end
	end
	return nil
end

local function spawnCustomer(plotIndex: number, state: PlotState)
	local queueIndex = freeQueueIndex(state)
	local problems = availableProblems(state.player)
	if not queueIndex or #problems == 0 then
		return
	end
	local problemId = problems[math.random(1, #problems)]
	local carTypeId = pickCarType()
	local model = CarBuilder.build(carTypeId)
	model:SetAttribute("PlotIndex", plotIndex)
	model:SetAttribute("OwnerUserId", state.player.UserId)
	model:SetAttribute("ProblemId", problemId)
	model:SetAttribute("RepairProgress", 0)

	local customer: Customer = {
		model = model,
		problemId = problemId,
		carTypeId = carTypeId,
		queueIndex = queueIndex,
		bayIndex = nil,
		queuedAt = math.huge,
		state = "Arriving",
	}
	setState(customer, "Arriving")
	state.queue[queueIndex] = customer
	state.customers[customer] = true

	local path = Layout.arrivalPath(plotIndex, queueIndex)
	local roadPath = table.move(path, 1, #path - 2, 1, {})
	local lotPath = { path[#path - 1], path[#path] }
	local first = roadPath[1]
	local second = roadPath[2] or lotPath[1]
	model:PivotTo(CFrame.lookAt(first, Vector3.new(second.X, first.Y, second.Z)))
	model.Parent = carsFolder

	task.spawn(function()
		local ok = TrafficService.drive(model, roadPath, Game.ROAD_SPEED)
			and TrafficService.drive(model, lotPath, Game.LOT_SPEED, Layout.toWorld(plotIndex, Layout.QUEUE[queueIndex]))
		if not ok or not state.alive or not state.customers[customer] then
			return
		end
		customer.queuedAt = os.clock()
		setState(customer, "Queued")
		dispatch(plotIndex)
	end)
end

local function startPlot(player: Player, plotIndex: number)
	local state: PlotState = {
		player = player,
		queue = {},
		bays = {},
		customers = {},
		alive = true,
	}
	plots[plotIndex] = state
	task.spawn(function()
		task.wait(2)
		while state.alive do
			spawnCustomer(plotIndex, state)
			task.wait(spawnInterval(player))
		end
	end)
end

local function stopPlot(plotIndex: number)
	local state = plots[plotIndex]
	if not state then
		return
	end
	state.alive = false
	plots[plotIndex] = nil
	for customer in state.customers do
		removeCustomer(state, customer)
	end
end

function CustomerService.init()
	local folder = Instance.new("Folder")
	folder.Name = "CustomerCars"
	folder.Parent = workspace
	carsFolder = folder
end

function CustomerService.start()
	PlotService.onAssigned(startPlot)
	PlotService.onReleased(function(_player, plotIndex)
		stopPlot(plotIndex)
	end)
	UnlockService.onUnlocked(function(player)
		local plotIndex = PlotService.getPlotIndex(player)
		if plotIndex then
			dispatch(plotIndex)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		local plotIndex = PlotService.getPlotIndex(player)
		if plotIndex then
			stopPlot(plotIndex)
		end
	end)
end

return CustomerService
