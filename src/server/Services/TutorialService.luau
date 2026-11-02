--!strict
-- Decides where the guide arrow points so players never have to wonder what to do next.
-- Tutorial steps themselves advance where the action happens (repair, hire, unlock).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Layout = require(Shared.Layout)

local PlayerData = require(script.Parent.PlayerData)
local PlotService = require(script.Parent.PlotService)
local UnlockService = require(script.Parent.UnlockService)

local TutorialService = {}

local function carWaitingInBay(player: Player): Vector3?
	local folder = workspace:FindFirstChild("CustomerCars")
	if not folder then
		return nil
	end
	for _, car in folder:GetChildren() do
		if car:IsA("Model") and car:GetAttribute("OwnerUserId") == player.UserId and car:GetAttribute("State") == "InBay" then
			return car:GetPivot().Position
		end
	end
	return nil
end

local function guideTarget(player: Player, data: PlayerData.Data): Vector3?
	local plotIndex = PlotService.getPlotIndex(player)
	if not plotIndex then
		return nil
	end
	local step = data.tutorialStep
	if step == 1 then
		return carWaitingInBay(player) or Layout.toWorld(plotIndex, Layout.BAYS[1].car).Position
	elseif step == 2 then
		return Layout.toWorld(plotIndex, Layout.HIRE_BOARD).Position
	end
	local nextEntry = UnlockService.nextUnlock(player)
	if not nextEntry then
		return nil
	end
	if data.money >= nextEntry.price then
		return UnlockService.nextButtonPosition(player)
	end
	-- Not enough in the wallet but enough waiting in the safe: go collect it.
	if data.safe > 0 and data.money + data.safe >= nextEntry.price then
		return Layout.toWorld(plotIndex, Layout.SAFE).Position
	end
	if step == 3 then
		return UnlockService.nextButtonPosition(player)
	end
	return nil
end

function TutorialService.start()
	PlayerData.addSnapshotField(function(player, data, snapshot)
		-- Everything already bought: nothing left to teach in step 3.
		if data.tutorialStep == 3 and UnlockService.nextUnlock(player) == nil then
			data.tutorialStep = 4
			snapshot.tutorialStep = 4
		end
		snapshot.guideTarget = guideTarget(player, data)
	end)
end

return TutorialService
