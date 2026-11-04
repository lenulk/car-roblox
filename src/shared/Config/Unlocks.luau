--!strict
-- Every unowned unlock can be bought at any time; list order is only the guide arrow's suggestion.
-- `anytime` unlocks are left out of the suggestion until everything else is owned.
local list = {
	{ id = "Bay1", price = 0, kind = "Bay", bay = 1, station = "tire", startOwned = true, upgradable = true },
	{ id = "Cashier", price = 250, kind = "Cashier" },
	{ id = "Bay2", price = 800, kind = "Bay", bay = 2, station = "oil", upgradable = true },
	{ id = "Shelf1", price = 1500, kind = "Shelf", shelf = 1, product = "battery", upgradable = true },
	{ id = "Parking", price = 3000, kind = "Parking" },
	{ id = "Reception", price = 3000, kind = "Reception" },
	{ id = "Shelf2", price = 6000, kind = "Shelf", shelf = 2, product = "tires", upgradable = true },
	{ id = "Bay3", price = 8000, kind = "Bay", bay = 3, station = "lift", upgradable = true },
	{ id = "CarWash", price = 9000, kind = "Wash", station = "wash", upgradable = true },
	{ id = "Shelf3", price = 15000, kind = "Shelf", shelf = 3, product = "oil", upgradable = true },
	{ id = "Diagnostics", price = 20000, kind = "Addon", station = "diagnostics" },
	{ id = "Bay4", price = 22000, kind = "Bay", bay = 4, station = "paint", upgradable = true },
	{ id = "Shelf4", price = 30000, kind = "Shelf", shelf = 4, product = "rims", upgradable = true },
	{ id = "Office", price = 40000, kind = "Office" },
	{ id = "EngineBench", price = 55000, kind = "Addon", station = "engine" },
	{ id = "Dyno", price = 120000, kind = "Addon", station = "dyno" },
	{ id = "TuningRoom", price = 10000, kind = "TuningRoom", anytime = true },
}
local byId = {}
for _, entry in list do
	byId[entry.id] = entry
end
return { list = list, byId = byId }
