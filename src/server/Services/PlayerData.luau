--!strict
-- Loads/saves player data and pushes the snapshot to the client.
-- Other services add their fields to the snapshot with PlayerData.addSnapshotField(fn).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Game = require(Shared.Config.Game)

export type Employee = { role: string, level: number, slot: string }
export type CarSave = { custom: { [string]: string }, upgrades: { [string]: number } }
export type Data = {
	version: number,
	money: number,
	safe: number,
	starPoints: number,
	carsRepaired: number,
	totalEarned: number,
	unlocks: { [string]: boolean },
	levels: { [string]: number },
	stock: { [string]: number },
	employees: { Employee },
	freeHireUsed: boolean,
	tutorialStep: number,
	settings: { lang: string, music: boolean },
	lastOnline: number,
	dailyStreak: number,
	lastDailyDay: number,
	rebirths: number,
	theme: string,
	ownedThemes: { [string]: boolean },
	cars: { [string]: CarSave },
	selectedCar: string?,
	ownedParts: { [string]: boolean },
}

type Profile = {
	data: Data,
	canSave: boolean,
	dirty: boolean,
	pushQueued: boolean,
}

local PlayerData = {}

local profiles: { [Player]: Profile } = {}
local loadedCallbacks: { (Player, Data) -> () } = {}
local snapshotFields: { (Player, Data, { [string]: any }) -> () } = {}
local store: DataStore? = nil
local warnedNoStore = false

local MAX_RETRIES = 3

local function defaultData(player: Player): Data
	local lang = if string.sub(player.LocaleId, 1, 2) == "th" then "th" else "en"
	return {
		version = 2,
		money = Game.STARTING_MONEY,
		safe = 0,
		starPoints = 0,
		carsRepaired = 0,
		totalEarned = 0,
		unlocks = {},
		levels = {},
		stock = {},
		employees = {},
		freeHireUsed = false,
		tutorialStep = 1,
		settings = { lang = lang, music = true },
		lastOnline = 0,
		dailyStreak = 0,
		lastDailyDay = 0,
		rebirths = 0,
		theme = "Classic",
		ownedThemes = { Classic = true },
		cars = {},
		selectedCar = nil,
		ownedParts = {},
	}
end

-- Fill keys missing from older saves so new fields never come back nil.
local function reconcile(saved: any, defaults: any): any
	for key, value in defaults do
		if saved[key] == nil then
			saved[key] = value
		elseif type(value) == "table" and type(saved[key]) == "table" and next(value) ~= nil and value[1] == nil then
			reconcile(saved[key], value)
		end
	end
	return saved
end

local function keyFor(player: Player): string
	return "player_" .. player.UserId
end

local function withRetries<T>(fn: () -> T): (boolean, T | string)
	local lastError: any = nil
	local attempts = if RunService:IsStudio() then 1 else MAX_RETRIES
	for attempt = 1, attempts do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastError = result
		if attempt < attempts then
			task.wait(attempt)
		end
	end
	return false, tostring(lastError)
end

local function save(player: Player, profile: Profile)
	if not profile.canSave or not store then
		return
	end
	profile.data.lastOnline = os.time()
	local dataStore = store :: DataStore
	local ok, err = withRetries(function()
		dataStore:SetAsync(keyFor(player), profile.data, { player.UserId })
		return true
	end)
	if ok then
		profile.dirty = false
	else
		warn(`[PlayerData] Save failed for {player.Name}: {err}`)
	end
end

local function buildSnapshot(player: Player, data: Data): { [string]: any }
	local snapshot: { [string]: any } = {
		money = data.money,
		safe = data.safe,
		starPoints = data.starPoints,
		carsRepaired = data.carsRepaired,
		unlocks = table.clone(data.unlocks),
		freeHireAvailable = not data.freeHireUsed,
		tutorialStep = data.tutorialStep,
		settings = table.clone(data.settings),
	}
	for _, field in snapshotFields do
		local ok, err = pcall(field, player, data, snapshot)
		if not ok then
			warn("[PlayerData] Snapshot field failed: " .. tostring(err))
		end
	end
	return snapshot
end

function PlayerData.get(player: Player): Data?
	local profile = profiles[player]
	return if profile then profile.data else nil
end

-- Sends a fresh snapshot (coalesced: many calls in one frame send once).
function PlayerData.push(player: Player)
	local profile = profiles[player]
	if not profile or profile.pushQueued then
		return
	end
	profile.pushQueued = true
	task.defer(function()
		profile.pushQueued = false
		if profiles[player] == profile and player.Parent then
			Remotes.get("DataChanged"):FireClient(player, buildSnapshot(player, profile.data))
		end
	end)
end

function PlayerData.update(player: Player, fn: (Data) -> ())
	local profile = profiles[player]
	if not profile then
		return
	end
	fn(profile.data)
	profile.dirty = true
	PlayerData.push(player)
end

function PlayerData.addMoney(player: Player, amount: number)
	PlayerData.update(player, function(data)
		data.money += math.floor(amount)
	end)
end

-- Returns true and deducts if the player can afford it.
function PlayerData.trySpend(player: Player, amount: number): boolean
	local profile = profiles[player]
	if not profile or profile.data.money < amount then
		return false
	end
	PlayerData.update(player, function(data)
		data.money -= amount
	end)
	return true
end

function PlayerData.addSnapshotField(fn: (Player, Data, { [string]: any }) -> ())
	table.insert(snapshotFields, fn)
end

function PlayerData.onLoaded(fn: (Player, Data) -> ())
	table.insert(loadedCallbacks, fn)
	for player, profile in profiles do
		task.spawn(fn, player, profile.data)
	end
end

local function load(player: Player)
	local data = defaultData(player)
	local canSave = false
	if store then
		local dataStore = store :: DataStore
		local ok, result = withRetries(function()
			return dataStore:GetAsync(keyFor(player))
		end)
		if ok then
			canSave = true
			if type(result) == "table" then
				data = reconcile(result, data)
			end
		else
			-- Never overwrite a save we could not read.
			warn(`[PlayerData] Load failed for {player.Name}, progress will not be saved this session: {result}`)
			if RunService:IsStudio() then
				store = nil
			end
		end
	end
	if not player.Parent then
		return
	end
	local profile: Profile = { data = data, canSave = canSave, dirty = false, pushQueued = false }
	profiles[player] = profile
	PlayerData.push(player)
	for _, fn in loadedCallbacks do
		task.spawn(fn, player, data)
	end
end

local function onSetSetting(player: Player, key: any, value: any)
	if key == "lang" and (value == "th" or value == "en") then
		PlayerData.update(player, function(data)
			data.settings.lang = value
		end)
	elseif key == "music" and type(value) == "boolean" then
		PlayerData.update(player, function(data)
			data.settings.music = value
		end)
	end
end

function PlayerData.init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Game.DATASTORE_NAME)
	end)
	if ok then
		store = result
	elseif not warnedNoStore then
		warnedNoStore = true
		warn("[PlayerData] DataStore unavailable (enable 'Studio Access to API Services'); progress will not save.")
	end
end

-- Called by Main after every service has started, so no player loads before all
-- onLoaded/onAssigned listeners exist.
function PlayerData.beginLoading()
	Players.PlayerAdded:Connect(load)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
end

function PlayerData.start()
	Remotes.get("SetSetting").OnServerEvent:Connect(onSetSetting)
	Remotes.get("RequestSnapshot").OnServerEvent:Connect(PlayerData.push)

	Players.PlayerRemoving:Connect(function(player)
		local profile = profiles[player]
		if profile then
			save(player, profile)
			profiles[player] = nil
		end
	end)

	task.spawn(function()
		while true do
			task.wait(Game.AUTOSAVE_INTERVAL)
			for player, profile in profiles do
				if profile.dirty then
					task.spawn(save, player, profile)
				end
			end
		end
	end)

	game:BindToClose(function()
		if RunService:IsStudio() and not store then
			return
		end
		local pending = 0
		for player, profile in profiles do
			pending += 1
			task.spawn(function()
				save(player, profile)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return PlayerData
