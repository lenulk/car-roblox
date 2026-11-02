--!strict
-- Order is purchase order: each unlock can only be bought after the one before it is owned.
local list = {
	{ id = "Bay1", price = 0, kind = "Bay", bay = 1, station = "tire", startOwned = true, upgradable = true },
	{ id = "Cashier", price = 250, kind = "Cashier" },
	{ id = "Bay2", price = 800, kind = "Bay", bay = 2, station = "oil", upgradable = true },
	{ id = "Shelf1", price = 1500, kind = "Shelf", shelf = 1, product = "battery", upgradable = true },
	{ id = "Parking", price = 3000, kind = "Parking" },
	{ id = "Reception", price = 5000, kind = "Reception" },
	{ id = "Bay3", price = 8000, kind = "Bay", bay = 3, station = "lift", upgradable = true },
	{ id = "Shelf2", price = 12000, kind = "Shelf", shelf = 2, product = "tires", upgradable = true },
	{ id = "CarWash", price = 15000, kind = "Wash", station = "wash", upgradable = true },
	{ id = "Bay4", price = 22000, kind = "Bay", bay = 4, station = "paint", upgradable = true },
	{ id = "Diagnostics", price = 30000, kind = "Addon", station = "diagnostics" },
	{ id = "Shelf3", price = 40000, kind = "Shelf", shelf = 3, product = "oil", upgradable = true },
	{ id = "EngineBench", price = 55000, kind = "Addon", station = "engine" },
	{ id = "Office", price = 75000, kind = "Office" },
	{ id = "Shelf4", price = 95000, kind = "Shelf", shelf = 4, product = "rims", upgradable = true },
	{ id = "Dyno", price = 120000, kind = "Addon", station = "dyno" },
	{ id = "TuningRoom", price = 150000, kind = "TuningRoom" },
}
local byId = {}
for _, entry in list do
	byId[entry.id] = entry
end
return { list = list, byId = byId }
