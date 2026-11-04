--!strict
-- Showcase car: the player's selected car (with installed parts) stands on the Tuning room turntable.
-- Built once per change of selectedCar/custom; removed while driving and when the plot is released.
-- The client rotates it (Controllers/Showcase.luau).

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Layout = require(Shared.Layout)
local CarBuilder = require(Shared.CarBuilder)
local PersonalCars = require(Shared.Config.PersonalCars)

local PlayerData = require(script.Parent.PlayerData)
local PlotService = require(script.Parent.PlotService)
local UnlockService = require(script.Parent.UnlockService)

local ShowcaseService = {}

local ROOM = "TuningRoom"

local folder: Folder? = nil
local showcases: { [Player]: { model: Model, signature: string } } = {}
local driving: { [Player]: boolean } = {}

local function getFolder(): Folder
	local existing = folder
	if existing then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "Showcases"
	created.Parent = workspace
	folder = created
	return created
end

local function remove(player: Player)
	local entry = showcases[player]
	if entry then
		showcases[player] = nil
		entry.model:Destroy()
	end
end

-- Stable text for "which car looks like what" (dictionary order is not stable, so sort keys).
local function signatureOf(carId: string, custom: { [string]: string }): string
	local keys = {}
	for key in custom do
		table.insert(keys, key)
	end
	table.sort(keys)
	local parts = { carId }
	for _, key in keys do
		table.insert(parts, key .. "=" .. custom[key])
	end
	return table.concat(parts, ";")
end

local function freeze(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
		end
	end
end

-- Builds, replaces or removes the player's showcase car so it matches their current data.
function ShowcaseService.refresh(player: Player)
	local data = PlayerData.get(player)
	local plotIndex = PlotService.getPlotIndex(player)
	if not data or not plotIndex or player.Parent == nil then
		remove(player)
		return
	end
	local carId = data.selectedCar
	local save = if carId then data.cars[carId] else nil
	if not data.unlocks[ROOM] or driving[player] or not carId or not save or not PersonalCars.byId[carId] then
		remove(player)
		return
	end

	local id = carId :: string
	local custom = (save :: PlayerData.CarSave).custom
	local signature = signatureOf(id, custom)
	local current = showcases[player]
	if current and current.signature == signature and current.model.Parent ~= nil then
		return
	end

	-- build first: if it fails, keep the previous car instead of leaving the turntable empty
	local ok, result = pcall(function()
		local model = CarBuilder.buildCustom(id, custom)
		model.Name = "ShowcaseCar"
		model:SetAttribute("ShowcaseOwner", player.UserId)
		freeze(model)
		local base = Layout.toWorld(plotIndex, Layout.TUNING.turntable) * CFrame.new(0, 0.6, 0)
		model:PivotTo(base)
		-- the client spins each part around this (parts replicate one by one, so it can't trust GetPivot)
		model:SetAttribute("ShowcaseBase", base)
		return model
	end)
	if not ok then
		warn("[ShowcaseService] build failed: " .. tostring(result))
		return
	end
	remove(player)
	local model = result :: Model
	model.Parent = getFolder()
	showcases[player] = { model = model, signature = signature }
end

-- Called by PersonalCarService: true while the player's drivable car exists.
function ShowcaseService.setDriving(player: Player, isDriving: boolean)
	driving[player] = if isDriving then true else nil
	ShowcaseService.refresh(player)
end

function ShowcaseService.init()
	getFolder()
end

function ShowcaseService.start()
	PlotService.onAssigned(function(player, _plotIndex)
		ShowcaseService.refresh(player)
	end)
	PlotService.onReleased(function(player, _plotIndex)
		driving[player] = nil
		remove(player)
	end)
	UnlockService.onUnlocked(function(player, id)
		if id == ROOM then
			ShowcaseService.refresh(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		driving[player] = nil
		remove(player)
	end)
end

return ShowcaseService
