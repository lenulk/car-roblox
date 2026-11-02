--!strict
local list = {
	{ id = "flat_tire", station = "tire", repairTime = 5, basePay = 40 },
	{ id = "oil_change", station = "oil", repairTime = 7, basePay = 70 },
	{ id = "battery", station = "any", repairTime = 4, basePay = 90, requiresUnlock = "Shelf1" },
}
local byId = {}
for _, entry in list do
	byId[entry.id] = entry
end
return { list = list, byId = byId }
