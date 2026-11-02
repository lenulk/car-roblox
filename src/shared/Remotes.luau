--!strict
-- Every network call in the game is declared here. Server calls Remotes.init() once at startup;
-- any script can then call Remotes.get(name) (clients wait for the folder to replicate).
--
-- Server -> Client
--   DataChanged  (snapshot: Snapshot)                 full player snapshot, see docs/CONTRACT.md
--   Notify       (key: string, args: {any}?)           toast message; key is a Config/Strings key
--   OpenUI       (uiName: "Hire")                      ask the client to open a window
--   Effect       (effect: string, position: Vector3)   "Unlock" | "Cash" | "Repair" one-shot visuals/sounds
-- Client -> Server
--   HireEmployee (role: string) -> (ok: boolean, messageKey: string)
--   SetSetting   (key: "lang" | "music", value: any)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"

local DEFINITIONS: { [string]: string } = {
	DataChanged = "RemoteEvent",
	Notify = "RemoteEvent",
	OpenUI = "RemoteEvent",
	Effect = "RemoteEvent",
	HireEmployee = "RemoteFunction",
	SetSetting = "RemoteEvent",
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
