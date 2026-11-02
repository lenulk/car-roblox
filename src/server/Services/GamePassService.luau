--!strict
-- Game pass ownership (Config.GamePasses; id 0 = disabled). Checked once on join, updated on purchase.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local GamePasses = require(Shared.Config.GamePasses)

local PlayerData = require(script.Parent.PlayerData)

local GamePassService = {}

local owned: { [Player]: { [string]: boolean } } = {}

local function passKeyForId(id: number): string?
	for _, key in GamePasses.order do
		local pass = (GamePasses :: any)[key]
		if pass and pass.id == id and id ~= 0 then
			return key
		end
	end
	return nil
end

function GamePassService.owns(player: Player, key: string): boolean
	local set = owned[player]
	return set ~= nil and set[key] == true
end

function GamePassService.value(key: string): number
	local pass = (GamePasses :: any)[key]
	return if pass and type(pass.value) == "number" then pass.value else 1
end

local function check(player: Player)
	local set: { [string]: boolean } = {}
	owned[player] = set
	for _, key in GamePasses.order do
		local pass = (GamePasses :: any)[key]
		if pass and pass.id ~= 0 then
			local ok, has = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.id)
			end)
			set[key] = ok and has == true
		end
	end
	PlayerData.push(player)
end

function GamePassService.start()
	PlayerData.addSnapshotField(function(player, _data, snapshot)
		local passes = {}
		for _, key in GamePasses.order do
			passes[key] = GamePassService.owns(player, key)
		end
		snapshot.gamepasses = passes
	end)
	PlayerData.onLoaded(function(player)
		check(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		owned[player] = nil
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		local key = passKeyForId(passId)
		if key and owned[player] then
			owned[player][key] = true
			PlayerData.push(player)
			Remotes.get("Notify"):FireClient(player, "notify_gamepass_thanks")
		end
	end)
end

return GamePassService
