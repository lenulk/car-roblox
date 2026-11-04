--!strict
-- Server entry point: create remotes, then init() every service, then start() every service.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
require(Shared.Remotes).init()

local Services = script.Parent:WaitForChild("Services")

-- Order matters: a service's init/start runs after the services it depends on.
local ORDER = {
	"MapBuilder",
	"PlayerData",
	"PlotService",
	"GamePassService",
	"PurchaseService",
	"TrafficService",
	"EmployeeService",
	"ShopperService",
	"ThemeService",
	"UnlockService",
	"DecorService",
	"EconomyService",
	"HireService",
	"RepairService",
	"CustomerService",
	"ShopService",
	"OfflineService",
	"DailyService",
	"PersonalCarService",
	"ShowcaseService",
	"RaceTrackService",
	"LightingService",
	"TutorialService",
}

local modules: { { name: string, module: any } } = {}
for _, name in ORDER do
	local moduleScript = Services:WaitForChild(name)
	table.insert(modules, { name = name, module = require(moduleScript :: ModuleScript) })
end

for _, entry in modules do
	if type(entry.module.init) == "function" then
		local ok, err = pcall(entry.module.init)
		if not ok then
			warn(`[Main] {entry.name}.init failed: {err}`)
		end
	end
end

for _, entry in modules do
	if type(entry.module.start) == "function" then
		local ok, err = pcall(entry.module.start)
		if not ok then
			warn(`[Main] {entry.name}.start failed: {err}`)
		end
	end
end

require(Services.PlayerData).beginLoading()
