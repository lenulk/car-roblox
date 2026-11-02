--!strict
-- Gives each loaded player a free plot, writes their name on the gate, spawns them there,
-- and frees the plot when they leave.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Layout = require(Shared.Layout)
local Remotes = require(Shared.Remotes)

local PlayerData = require(script.Parent.PlayerData)
local MapBuilder = require(script.Parent.MapBuilder)

local PlotService = {}

local owners: { [number]: Player } = {}
local plotOf: { [Player]: number } = {}
local assignedCallbacks: { (Player, number) -> () } = {}
local releasedCallbacks: { (Player, number) -> () } = {}

function PlotService.getPlotIndex(player: Player): number?
	return plotOf[player]
end

function PlotService.getOwner(plotIndex: number): Player?
	return owners[plotIndex]
end

function PlotService.getPlot(plotIndex: number): Model
	return MapBuilder.getPlot(plotIndex)
end

function PlotService.onAssigned(fn: (Player, number) -> ())
	table.insert(assignedCallbacks, fn)
end

function PlotService.onReleased(fn: (Player, number) -> ())
	table.insert(releasedCallbacks, fn)
end

local function setSign(plotIndex: number, player: Player?)
	local plot = MapBuilder.getPlot(plotIndex)
	local label = plot:FindFirstChild("OwnerLabel", true)
	if label and label:IsA("TextLabel") then
		if player then
			label:SetAttribute("TextKey", "plot_owner")
			label:SetAttribute("TextArgs", player.DisplayName)
			label.Text = player.DisplayName
		else
			label:SetAttribute("TextKey", "plot_free")
			label:SetAttribute("TextArgs", "")
			label.Text = ""
		end
	end
end

local function spawnAtPlot(player: Player)
	local plotIndex = plotOf[player]
	local character = player.Character
	if not plotIndex or not character then
		return
	end
	local spawnCFrame = Layout.toWorld(plotIndex, Layout.PLAYER_SPAWN) * CFrame.new(0, 4, 0)
	character:PivotTo(spawnCFrame)
end

local function assign(player: Player)
	if plotOf[player] then
		return
	end
	local free: number? = nil
	for i = 1, Layout.PLOT_COUNT do
		if not owners[i] then
			free = i
			break
		end
	end
	if not free then
		Remotes.get("Notify"):FireClient(player, "notify_no_plot")
		return
	end
	local plotIndex = free :: number
	owners[plotIndex] = player
	plotOf[player] = plotIndex
	MapBuilder.getPlot(plotIndex):SetAttribute("OwnerUserId", player.UserId)
	setSign(plotIndex, player)

	for _, fn in assignedCallbacks do
		task.spawn(fn, player, plotIndex)
	end

	player.CharacterAdded:Connect(function(character)
		-- Wait for the default spawn to finish placing the character, then move it home.
		character:WaitForChild("HumanoidRootPart", 10)
		task.wait()
		spawnAtPlot(player)
	end)
	if player.Character then
		spawnAtPlot(player)
	end

	PlayerData.push(player)
	Remotes.get("Notify"):FireClient(player, "notify_welcome")
end

local function release(player: Player)
	local plotIndex = plotOf[player]
	if not plotIndex then
		return
	end
	for _, fn in releasedCallbacks do
		local ok, err = pcall(fn, player, plotIndex)
		if not ok then
			warn("[PlotService] release callback failed: " .. tostring(err))
		end
	end
	plotOf[player] = nil
	owners[plotIndex] = nil
	MapBuilder.getPlot(plotIndex):SetAttribute("OwnerUserId", 0)
	setSign(plotIndex, nil)
end

function PlotService.start()
	for i = 1, Layout.PLOT_COUNT do
		setSign(i, nil)
	end
	PlayerData.addSnapshotField(function(player, _data, snapshot)
		snapshot.plotIndex = plotOf[player]
	end)
	PlayerData.onLoaded(function(player)
		assign(player)
	end)
	Players.PlayerRemoving:Connect(release)
end

return PlotService
