--!strict
-- Personal cars (tuning garage): buy/select cars, buy & apply customization parts, performance
-- upgrades, and spawning the drivable car on the connector road.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Layout = require(Shared.Layout)
local Remotes = require(Shared.Remotes)
local Format = require(Shared.Format)
local Strings = require(Shared.Config.Strings)
local CarBuilder = require(Shared.CarBuilder)
local PersonalCars = require(Shared.Config.PersonalCars)
local Customization = require(Shared.Config.Customization)

local PlayerData = require(script.Parent.PlayerData)
local PlotService = require(script.Parent.PlotService)
local UnlockService = require(script.Parent.UnlockService)
local MapBuilder = require(script.Parent.MapBuilder)
local VehicleFolder = script.Parent.Parent:WaitForChild("Vehicle")
local VehicleBuilder = require(VehicleFolder:WaitForChild("VehicleBuilder"))
local VehicleController = require(VehicleFolder:WaitForChild("VehicleController"))

local PersonalCarService = {}

local ROOM = "TuningRoom"

local carsFolder: Folder
local activeCars: { [Player]: Model } = {}
local busy: { [Player]: boolean } = {}

local function notify(player: Player, key: string, args: { any }?)
	Remotes.get("Notify"):FireClient(player, key, args)
end

local function langOf(player: Player): string
	local data = PlayerData.get(player)
	return if data then data.settings.lang else "th"
end

local function newCarSave(): PlayerData.CarSave
	local upgrades = {}
	for _, part in PersonalCars.UPGRADE_ORDER do
		upgrades[part] = 1
	end
	return { custom = table.clone(Customization.DEFAULTS), upgrades = upgrades }
end

local function ensureStarterCar(player: Player)
	local data = PlayerData.get(player)
	if not data or not data.unlocks[ROOM] or next(data.cars) ~= nil then
		return
	end
	PlayerData.update(player, function(d)
		d.cars.Sedan = newCarSave()
		d.selectedCar = "Sedan"
	end)
end

local function charge(player: Player, price: number): boolean
	local data = PlayerData.get(player)
	if not data then
		return false
	end
	if data.money < price then
		notify(player, "notify_not_enough_money", { Format.money(price - data.money) })
		return false
	end
	PlayerData.update(player, function(d)
		d.money -= price
	end)
	return true
end

-- Wraps a remote handler with the common checks (tuning room owned, one request at a time).
local function guarded(fn: (Player, PlayerData.Data, ...any) -> (boolean, string)): (Player, ...any) -> (boolean, string)
	return function(player: Player, ...: any)
		local data = PlayerData.get(player)
		if not data or busy[player] then
			return false, "notify_drive_unavailable"
		end
		if not data.unlocks[ROOM] then
			notify(player, "notify_drive_unavailable")
			return false, "notify_drive_unavailable"
		end
		busy[player] = true
		local ok, result, key = pcall(fn, player, data, ...)
		busy[player] = nil
		if not ok then
			warn("[PersonalCarService] " .. tostring(result))
			return false, "notify_drive_unavailable"
		end
		return result, key
	end
end

local function buyCar(player: Player, data: PlayerData.Data, carId: any): (boolean, string)
	local car = if type(carId) == "string" then PersonalCars.byId[carId] else nil
	if not car then
		return false, "notify_need_car"
	end
	if data.cars[car.id] then
		return true, "notify_car_bought"
	end
	if not charge(player, car.price) then
		return false, "notify_not_enough_money"
	end
	PlayerData.update(player, function(d)
		d.cars[car.id] = newCarSave()
		d.selectedCar = car.id
	end)
	notify(player, "notify_car_bought", { Strings.get(langOf(player), "car_" .. car.id) })
	return true, "notify_car_bought"
end

local function selectCar(player: Player, data: PlayerData.Data, carId: any): (boolean, string)
	if type(carId) ~= "string" or not data.cars[carId] then
		notify(player, "notify_need_car")
		return false, "notify_need_car"
	end
	PlayerData.update(player, function(d)
		d.selectedCar = carId
	end)
	notify(player, "notify_car_selected", { Strings.get(langOf(player), "car_" .. carId) })
	return true, "notify_car_selected"
end

local function findOption(category: any, optionId: any): any?
	if type(category) ~= "string" or type(optionId) ~= "string" then
		return nil
	end
	local cat = Customization.byId[category]
	if not cat then
		return nil
	end
	for _, option in cat.options do
		if option.id == optionId then
			return option
		end
	end
	return nil
end

local function customize(player: Player, data: PlayerData.Data, carId: any, category: any, optionId: any): (boolean, string)
	local save = if type(carId) == "string" then data.cars[carId] else nil
	local option = findOption(category, optionId)
	if not save or not option then
		return false, "notify_need_car"
	end
	local key = category .. ":" .. optionId
	local owned = option.price <= 0 or data.ownedParts[key] == true
	if not owned and not charge(player, option.price) then
		return false, "notify_not_enough_money"
	end
	PlayerData.update(player, function(d)
		d.ownedParts[key] = true
		d.cars[carId].custom[category] = optionId
	end)
	notify(player, if owned then "notify_part_applied" else "notify_part_bought")
	return true, if owned then "notify_part_applied" else "notify_part_bought"
end

local function upgradeCar(player: Player, data: PlayerData.Data, carId: any, part: any): (boolean, string)
	local save = if type(carId) == "string" then data.cars[carId] else nil
	local car = if type(carId) == "string" then PersonalCars.byId[carId] else nil
	if not save or not car or type(part) ~= "string" or not PersonalCars.UPGRADES[part] then
		return false, "notify_need_car"
	end
	local level = save.upgrades[part] or 1
	local cost = PersonalCars.upgradeCost(car.price, level)
	if not cost then
		notify(player, "notify_max_level")
		return false, "notify_max_level"
	end
	if not charge(player, cost) then
		return false, "notify_not_enough_money"
	end
	PlayerData.update(player, function(d)
		d.cars[carId].upgrades[part] = level + 1
	end)
	notify(player, "notify_car_upgraded", { Strings.get(langOf(player), "carpart_" .. part), level + 1 })
	return true, "notify_car_upgraded"
end

function PersonalCarService.despawn(player: Player)
	local car = activeCars[player]
	if car then
		activeCars[player] = nil
		pcall(VehicleController.detach, car)
		car:Destroy()
		PlayerData.push(player)
	end
end

local function driveCar(player: Player, data: PlayerData.Data, carId: any): (boolean, string)
	local plotIndex = PlotService.getPlotIndex(player)
	local save = if type(carId) == "string" then data.cars[carId] else nil
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not plotIndex or not save or not humanoid or humanoid.Health <= 0 then
		notify(player, "notify_need_car")
		return false, "notify_need_car"
	end
	PersonalCarService.despawn(player)

	local stats = PersonalCars.statsFor(carId, save.upgrades)
	local visual = CarBuilder.buildCustom(carId, save.custom)
	local car = VehicleBuilder.make(visual, stats)
	car.Name = player.Name .. "_Car"
	car:SetAttribute("OwnerUserId", player.UserId)
	car:PivotTo(Layout.toWorld(plotIndex, Layout.DRIVE_SPAWN) * CFrame.new(0, 1, 0))
	car.Parent = carsFolder
	VehicleController.attach(car, stats)
	activeCars[player] = car

	local seat = car:FindFirstChild("DriveSeat", true)
	if seat and seat:IsA("VehicleSeat") then
		-- Sit only once the car has reached the player's client: the default control script picks up a
		-- VehicleSeat only if it already exists there when the Humanoid sits, otherwise W/A/S/D do nothing.
		local sitDelay = math.clamp(0.3 + player:GetNetworkPing() * 3, 0.3, 2)
		task.delay(sitDelay, function()
			if humanoid.Parent and seat.Parent and activeCars[player] == car then
				seat:Sit(humanoid)
			end
		end)
		-- Leaving the seat sends the car back to the garage after a moment.
		seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			if seat.Occupant == nil then
				task.delay(3, function()
					if activeCars[player] == car and seat.Occupant == nil then
						PersonalCarService.despawn(player)
					end
				end)
			end
		end)
	end
	PlayerData.update(player, function(d)
		d.selectedCar = carId
	end)
	notify(player, "notify_drive_start")
	return true, "notify_drive_start"
end

local function returnCar(player: Player)
	local car = activeCars[player]
	if not car then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Sit = false
		humanoid.Jump = true
	end
	PersonalCarService.despawn(player)
	local plotIndex = PlotService.getPlotIndex(player)
	if plotIndex and character then
		task.defer(function()
			character:PivotTo(Layout.toWorld(plotIndex, CFrame.new(Layout.TUNING.terminal) * CFrame.new(0, 4, -6)))
		end)
	end
end

-- The tuning computer lives inside the TuningRoom unlockable (in storage while locked).
local terminalPrompts: { [number]: ProximityPrompt } = {}

local function findTerminal(plotIndex: number): BasePart?
	local plot = MapBuilder.getPlot(plotIndex)
	local room = plot:FindFirstChild("Unlockables") and plot.Unlockables:FindFirstChild(ROOM)
	if not room then
		local storage = ServerStorage:FindFirstChild("LockedUnlockables")
		local plotStorage = storage and storage:FindFirstChild("Plot" .. plotIndex)
		room = plotStorage and plotStorage:FindFirstChild("Unlockables_" .. ROOM)
	end
	local terminal = room and room:FindFirstChild("TuningTerminal", true)
	return if terminal and terminal:IsA("BasePart") then terminal else nil
end

local function createTerminalPrompt(plotIndex: number)
	local terminal = findTerminal(plotIndex)
	if not terminal then
		warn("[PersonalCarService] TuningTerminal missing on plot " .. plotIndex)
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = Strings.get("th", "prompt_tune")
	prompt.ObjectText = Strings.get("th", "object_tuning_terminal")
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("OwnerUserId", 0)
	prompt:SetAttribute("ActionKey", "prompt_tune")
	prompt:SetAttribute("ObjectKey", "object_tuning_terminal")
	prompt.Parent = terminal
	prompt.Triggered:Connect(function(player)
		if PlotService.getPlotIndex(player) == plotIndex and UnlockService.isOwned(player, ROOM) then
			ensureStarterCar(player)
			Remotes.get("OpenUI"):FireClient(player, "Tuning")
		end
	end)
	terminalPrompts[plotIndex] = prompt
end

function PersonalCarService.init()
	local folder = Instance.new("Folder")
	folder.Name = "PlayerCars"
	folder.Parent = workspace
	carsFolder = folder
end

function PersonalCarService.start()
	Remotes.get("BuyCar").OnServerInvoke = guarded(buyCar)
	Remotes.get("SelectCar").OnServerInvoke = guarded(selectCar)
	Remotes.get("Customize").OnServerInvoke = guarded(customize)
	Remotes.get("UpgradeCar").OnServerInvoke = guarded(upgradeCar)
	Remotes.get("DriveCar").OnServerInvoke = guarded(driveCar)
	Remotes.get("ReturnCar").OnServerEvent:Connect(returnCar)

	for plotIndex = 1, Layout.PLOT_COUNT do
		createTerminalPrompt(plotIndex)
	end

	PlotService.onAssigned(function(player, plotIndex)
		local prompt = terminalPrompts[plotIndex]
		if prompt then
			prompt:SetAttribute("OwnerUserId", player.UserId)
		end
		ensureStarterCar(player)
		player.CharacterRemoving:Connect(function()
			PersonalCarService.despawn(player)
		end)
	end)
	PlotService.onReleased(function(player, plotIndex)
		local prompt = terminalPrompts[plotIndex]
		if prompt then
			prompt:SetAttribute("OwnerUserId", 0)
		end
		PersonalCarService.despawn(player)
	end)
	Players.PlayerRemoving:Connect(PersonalCarService.despawn)
	UnlockService.onUnlocked(function(player, id)
		if id == ROOM then
			ensureStarterCar(player)
		end
	end)

	PlayerData.addSnapshotField(function(player, data, snapshot)
		local cars = {}
		local carStats = {}
		for carId, save in data.cars do
			cars[carId] = { custom = table.clone(save.custom), upgrades = table.clone(save.upgrades) }
			if PersonalCars.byId[carId] then
				carStats[carId] = PersonalCars.statsFor(carId, save.upgrades)
			end
		end
		snapshot.cars = cars
		snapshot.carStats = carStats
		snapshot.selectedCar = data.selectedCar
		snapshot.ownedParts = table.clone(data.ownedParts)
		snapshot.driving = activeCars[player] ~= nil
	end)
end

return PersonalCarService
