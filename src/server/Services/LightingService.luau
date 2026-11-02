--!strict
-- Gentle day-night cycle. Nights stay bright enough to play (ambient boost), and every light
-- tagged NightLight turns on at dusk and off at dawn.

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Game = require(Shared.Config.Game)

local LightingService = {}

local nightLights: { [Light]: boolean } = {}
local isNight: boolean? = nil

local DAY_AMBIENT = Color3.fromRGB(120, 120, 130)
local NIGHT_AMBIENT = Color3.fromRGB(70, 80, 120)

local function track(inst: Instance)
	if inst:IsA("Light") and inst:GetAttribute("NightLight") then
		nightLights[inst] = true
		inst.Enabled = isNight == true
	end
end

local function setNight(night: boolean)
	if isNight == night then
		return
	end
	isNight = night
	for light in nightLights do
		if light.Parent then
			light.Enabled = night
		else
			nightLights[light] = nil
		end
	end
end

function LightingService.start()
	Lighting.ClockTime = 9
	for _, d in workspace:GetDescendants() do
		track(d)
	end
	workspace.DescendantAdded:Connect(track)

	local hoursPerSecond = 24 / (Game.DAY_LENGTH_MINUTES * 60)
	RunService.Heartbeat:Connect(function(dt)
		local clock = (Lighting.ClockTime + dt * hoursPerSecond) % 24
		Lighting.ClockTime = clock
		local night = clock < 6.3 or clock > 18.2
		setNight(night)
		-- Smooth ambient between day and night so dark hours stay friendly.
		local daylight = math.clamp(math.sin((clock - 6) / 12 * math.pi), 0, 1)
		Lighting.Ambient = NIGHT_AMBIENT:Lerp(DAY_AMBIENT, daylight)
		Lighting.OutdoorAmbient = NIGHT_AMBIENT:Lerp(Color3.fromRGB(140, 140, 150), daylight)
	end)
end

return LightingService
