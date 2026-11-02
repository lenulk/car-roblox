--!strict
-- Order is purchase order: each unlock can only be bought after the one before it is owned.
local list = {
	{ id = "Bay1", price = 0, kind = "Bay", bay = 1, station = "tire", startOwned = true },
	{ id = "Cashier", price = 250, kind = "Cashier" },
	{ id = "Bay2", price = 800, kind = "Bay", bay = 2, station = "oil" },
	{ id = "Shelf1", price = 1500, kind = "Shelf", shelf = 1 },
	{ id = "Parking", price = 4000, kind = "Parking" },
}
local byId = {}
for _, entry in list do
	byId[entry.id] = entry
end
return { list = list, byId = byId }
