--!strict
-- station = "any" means any owned bay can fix it
local list = {
	{ id = "flat_tire", station = "tire", repairTime = 5, basePay = 40 },
	{ id = "oil_change", station = "oil", repairTime = 7, basePay = 70 },
	{ id = "battery", station = "any", repairTime = 4, basePay = 90, requiresUnlock = "Shelf1" },
	{ id = "suspension", station = "lift", repairTime = 12, basePay = 200 },
	{ id = "paint_scratch", station = "paint", repairTime = 15, basePay = 350 },
	{ id = "check_engine", station = "any", repairTime = 10, basePay = 300, requiresUnlock = "Diagnostics" },
	{ id = "engine_repair", station = "lift", repairTime = 25, basePay = 800, requiresUnlock = "EngineBench" },
	{ id = "tune_up", station = "lift", repairTime = 30, basePay = 2000, requiresUnlock = "Dyno" },
}
local byId = {}
for _, entry in list do
	byId[entry.id] = entry
end
return { list = list, byId = byId }
