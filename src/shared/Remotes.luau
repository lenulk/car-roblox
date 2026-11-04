--!strict
-- Every network call in the game is declared here. Server calls Remotes.init() once at startup;
-- any script can then call Remotes.get(name) (clients wait for the folder to replicate).
-- Full argument/return contract: docs/CONTRACT.md §6 and §13.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"

local DEFINITIONS: { [string]: string } = {
	-- Server -> client
	DataChanged = "RemoteEvent", -- (snapshot)
	Notify = "RemoteEvent", -- (key, args?)
	OpenUI = "RemoteEvent", -- (uiName, arg?)
	Effect = "RemoteEvent", -- (effect, position, text?)
	-- Client -> server
	RequestSnapshot = "RemoteEvent", -- ()
	SetSetting = "RemoteEvent", -- (key, value)
	HireEmployee = "RemoteFunction", -- (role) -> ok, key
	UpgradeEmployee = "RemoteFunction", -- (slot) -> ok, key
	Upgrade = "RemoteFunction", -- (unlockId) -> ok, key
	ClaimDaily = "RemoteFunction", -- () -> ok, key
	BuyTheme = "RemoteFunction", -- (themeId) -> ok, key   (buys if needed, then applies)
	BuyCar = "RemoteFunction", -- (carId) -> ok, key
	SelectCar = "RemoteFunction", -- (carId) -> ok, key
	Customize = "RemoteFunction", -- (carId, category, optionId) -> ok, key (buys if needed, then applies)
	UpgradeCar = "RemoteFunction", -- (carId, part) -> ok, key
	DriveCar = "RemoteFunction", -- (carId, mode?) -> ok, key   (mode: nil = connector road, "track" = private race track)
	ReturnCar = "RemoteEvent", -- ()
	DebugPurchase = "RemoteEvent", -- (key) Studio-only fake purchase of a product / game pass (ignored in live games)
}

local Remotes = {}

function Remotes.init()
	assert(RunService:IsServer(), "Remotes.init must run on the server")
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME) or Instance.new("Folder")
	folder.Name = FOLDER_NAME
	for name, className in DEFINITIONS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new(className)
			remote.Name = name
			remote.Parent = folder
		end
	end
	folder.Parent = ReplicatedStorage
end

function Remotes.get(name: string): any
	assert(DEFINITIONS[name], "Unknown remote: " .. name)
	local folder = if RunService:IsServer()
		then ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		else ReplicatedStorage:WaitForChild(FOLDER_NAME)
	assert(folder, "Remotes.init() has not run yet")
	return if RunService:IsServer() then folder:FindFirstChild(name) else folder:WaitForChild(name)
end

return Remotes
