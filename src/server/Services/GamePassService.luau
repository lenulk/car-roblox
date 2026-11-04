--!strict
-- Game pass ownership (Config.GamePasses; id 0 = disabled). Checked once on join, updated on purchase.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

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

-- Gold "VIP" tag above the owner's head (added on every spawn, removed if the pass is not owned).
local function applyVipTag(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local existing = head:FindFirstChild("VipTag")
	if not GamePassService.owns(player, "VIP") then
		if existing then
			existing:Destroy()
		end
		return
	end
	if existing then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "VipTag"
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(64, 26)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 60
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(255, 205, 60)
	label.BackgroundTransparency = 0.05
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(90, 55, 0)
	label.Text = "VIP"
	label.BorderSizePixel = 0
	label:SetAttribute("TextKey", "vip_tag")
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(214, 150, 20)
	stroke.Thickness = 2
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = head
end

-- Extra numeric config of a pass (e.g. VIP.dailyMult), or `default`.
function GamePassService.field(key: string, name: string, default: number): number
	local pass = (GamePasses :: any)[key]
	local value = if pass then pass[name] else nil
	return if type(value) == "number" then value else default
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
	applyVipTag(player)
	PlayerData.push(player)
end

-- Studio testing only (Config.Products.DEBUG_FAKE_IN_STUDIO): marks a pass owned in memory, never saved.
function GamePassService.debugGrant(player: Player, key: string)
	if not RunService:IsStudio() or not (GamePasses :: any)[key] then
		return
	end
	local set = owned[player]
	if not set then
		return
	end
	set[key] = true
	applyVipTag(player)
	PlayerData.push(player)
end

local function watchCharacters(player: Player)
	player.CharacterAdded:Connect(function()
		task.wait(0.5) -- let the Head exist
		applyVipTag(player)
	end)
	applyVipTag(player)
end

function GamePassService.start()
	Players.PlayerAdded:Connect(watchCharacters)
	for _, player in Players:GetPlayers() do
		watchCharacters(player)
	end
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
			applyVipTag(player)
			PlayerData.push(player)
			Remotes.get("Notify"):FireClient(player, "notify_gamepass_thanks")
		end
	end)
end

return GamePassService
