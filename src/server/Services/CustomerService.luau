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
local HireService = require(script.Parent.HireService)
local MapBuilder = require(script.Parent.MapBuilder)
local DecorService = require(script.Parent.DecorService)

local WASH_SLOW_SPEED = 6

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

-- Upgrade level of the bay doing the work (problems marked "any" use whichever bay they are in).
local function bayLevel(player: Player, bayStation: string): number
	return math.max(1, UnlockService.stationLevel(player, bayStation))
end

local function repairTimeFor(player: Player, bayStation: string, problemId: string): number
	local problem = Problems.byId[problemId]
	return problem.repairTime * Stations.LEVELS[bayLevel(player, bayStation)].timeMult
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

local function starsOf(player: Player): number
	local data = PlayerData.get(player)
	return if data then EconomyService.starLevel(data.starPoints) else 0
end

-- Weighted pick among car types the garage's star rating unlocks (fancier cars at more stars).
local function pickCarType(player: Player): string
	local stars = starsOf(player)
	local eligible = {}
	local total = 0
	for _, carType in CarTypes.list do
		if (carType.minStars or 0) <= stars then
			table.insert(eligible, carType)
			total += carType.weight
		end
	end
	local roll = math.random() * total
	for _, carType in eligible do
		roll -= carType.weight
		if roll <= 0 then
			return carType.id
		end
	end
	return CarTypes.list[1].id
end

local function spawnInterval(player: Player): number
	local interval = math.max(Game.SPAWN_INTERVAL_MIN, Game.SPAWN_INTERVAL_BASE - starsOf(player) * Game.SPAWN_INTERVAL_PER_STAR)
	local reception = HireService.receptionistLevel(player)
	if reception > 0 then
		interval *= Game.RECEPTION_SPAWN_MULT[reception] or 1
	end
	-- storefront decorations apply AFTER the minimum clamp, so they can go below SPAWN_INTERVAL_MIN
	return interval * (1 - DecorService.bonus(player))
end
CustomerService.spawnInterval = spawnInterval -- used by OfflineService

----------------------------------------------------------------------------------------------------
-- Car wash: foam on while a car rolls through, bonus on the bill
----------------------------------------------------------------------------------------------------

local foamUsers: { [number]: number } = {}

local function setFoam(plotIndex: number, delta: number)
	foamUsers[plotIndex] = math.max(0, (foamUsers[plotIndex] or 0) + delta)
	local wash = MapBuilder.getPlot(plotIndex):FindFirstChild("Unlockables")
	wash = wash and wash:FindFirstChild("CarWash")
	local station = wash and wash:FindFirstChild("Station")
	if not station then
		return
	end
	local on = foamUsers[plotIndex] > 0
	for _, d in station:GetDescendants() do
		if d:IsA("ParticleEmitter") and d.Name == "WashFoam" then
			d.Enabled = on
		end
	end
end

local function hasWash(player: Player): boolean
	return UnlockService.isOwned(player, "CarWash")
end

local function washBonusFraction(player: Player): number
	local level = UnlockService.level(player, "CarWash")
	return if level > 0 then Stations.WASH_BONUS[level] or 0 else 0
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

-- Drives a finished car out: bay -> exit lane (-> through the wash) -> connector -> ring.
local function driveAway(plotIndex: number, state: PlotState, customer: Customer, bayIndex: number, washed: boolean)
	local model = customer.model
	local bx = Layout.BAYS[bayIndex].car.Position.X
	local ex = Layout.EXIT_LANE_X
	local function w(x: number, z: number): Vector3
		return Layout.pointToWorld(plotIndex, Vector3.new(x, 0, z))
	end
	local ok = TrafficService.drive(model, { w(bx, Layout.BAY_LANE_Z), w(ex, Layout.BAY_LANE_Z) }, Game.LOT_SPEED)
	if ok and washed then
		local washZ = Layout.STATIONS.wash.Z
		ok = TrafficService.drive(model, { w(ex, washZ + 6) }, Game.LOT_SPEED)
		if ok then
			setFoam(plotIndex, 1)
			ok = TrafficService.drive(model, { w(ex, washZ - 6) }, WASH_SLOW_SPEED)
			setFoam(plotIndex, -1)
			if ok then
				Remotes.get("Effect"):FireClient(state.player, "Wash", w(ex, washZ) + Vector3.new(0, 4, 0))
			end
		end
	end
	if ok then
		local a = Layout.plotAngle(plotIndex)
		local road = { w(ex, Layout.CONNECTOR_RING_Z) }
		for _, p in Layout.ringArc(a + math.rad(4), a + math.rad(70)) do
			table.insert(road, p)
		end
		TrafficService.drive(model, road, Game.ROAD_SPEED)
	end
	if state.customers[customer] then
		removeCustomer(state, customer)
	end
end

local function pay(
	plotIndex: number,
	state: PlotState,
	customer: Customer,
	bayIndex: number,
	bayStation: string,
	startedAt: number,
	repairTime: number
)
	local player = state.player
	local problem = Problems.byId[customer.problemId]
	local carType = CarTypes.byId[customer.carTypeId]
	local level = bayLevel(player, bayStation)
	local amount = math.floor(problem.basePay * carType.payMult * Stations.LEVELS[level].payMult + 0.5)

	local fast = os.clock() - startedAt <= repairTime * Game.TIP_WINDOW_FACTOR + Game.TIP_WINDOW_BONUS
	local tipPercent = Game.TIP_PERCENT
	local reception = HireService.receptionistLevel(player)
	if reception > 0 then
		tipPercent += Game.RECEPTION_TIP_BONUS[reception] or 0
	end
	local tip = if fast then math.max(1, math.floor(amount * tipPercent + 0.5)) else 0

	local washed = hasWash(player)
	local washBonus = if washed then math.floor(amount * washBonusFraction(player) + 0.5) else 0

	local earned = EconomyService.earn(player, amount + tip + washBonus)
	EconomyService.addStarPoint(player, if carType.vip then Game.VIP_STAR_POINTS else 1)
	PlayerData.update(player, function(data)
		data.carsRepaired += 1
		if data.tutorialStep == 1 then
			data.tutorialStep = 2
		end
	end)

	local root = customer.model.PrimaryPart
	local position = if root then root.Position + Vector3.new(0, 6, 0) else Layout.pointToWorld(plotIndex, Vector3.zero)
	Remotes.get("Effect"):FireClient(player, "Cash", position, "+" .. Format.money(earned))
	Remotes.get("Notify"):FireClient(player, "notify_repaired", { Format.money(earned) })
	if tip > 0 then
		Remotes.get("Notify"):FireClient(player, "notify_tip", { Format.money(tip) })
	end

	-- Leave the bay and free it for the next car.
	setState(customer, "Leaving")
	state.bays[bayIndex] = nil
	customer.bayIndex = nil
	dispatch(plotIndex)
	driveAway(plotIndex, state, customer, bayIndex, washed)
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
	local repairTime = repairTimeFor(state.player, bayStation, customer.problemId)
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
				pay(plotIndex, state, customer, bayIndex, bayStation, startedAt, repairTime)
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
	if not queueIndex then
		DecorService.noteQueueFull(plotIndex) -- "buy parking" hint in the decor window
	end
	if not queueIndex or #problems == 0 then
		return
	end
	local problemId = problems[math.random(1, #problems)]
	local carTypeId = pickCarType(state.player)
	local model = CarBuilder.build(carTypeId)
	model:SetAttribute("PlotIndex", plotIndex)
	model:SetAttribute("OwnerUserId", state.player.UserId)
	model:SetAttribute("ProblemId", problemId)
	model:SetAttribute("RepairProgress", 0)
	if CarTypes.byId[carTypeId].vip then
		model:SetAttribute("VIP", true)
		Remotes.get("Notify"):FireClient(state.player, "notify_vip_arrived")
	end

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

	DecorService.noteArrival(plotIndex) -- welcome fireworks

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
			-- one failed spawn must not end the loop (the plot would get no customers until rejoin)
			local ok, err = pcall(spawnCustomer, plotIndex, state)
			if not ok then
				warn("[CustomerService] spawnCustomer failed: " .. tostring(err))
			end
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
	foamUsers[plotIndex] = 0
	setFoam(plotIndex, 0)
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
