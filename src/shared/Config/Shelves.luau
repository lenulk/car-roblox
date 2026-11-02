--!strict
-- basePrice = price per product at level 1; upgradeBase = base cost for the first shelf upgrade
local byId = {
	Shelf1 = { id = "Shelf1", product = "battery", basePrice = 40, upgradeBase = 750 },
	Shelf2 = { id = "Shelf2", product = "tires", basePrice = 60, upgradeBase = 6000 },
	Shelf3 = { id = "Shelf3", product = "oil", basePrice = 80, upgradeBase = 20000 },
	Shelf4 = { id = "Shelf4", product = "rims", basePrice = 150, upgradeBase = 47500 },
}
-- LEVELS[n] applies to shelf level n (1..5)
local LEVELS = {
	{ capacity = 10, priceMult = 1 },
	{ capacity = 20, priceMult = 1.2 },
	{ capacity = 30, priceMult = 1.45 },
	{ capacity = 40, priceMult = 1.75 },
	{ capacity = 50, priceMult = 2.2 },
}
return {
	byId = byId,
	LEVELS = LEVELS,
	-- cost to go from level n to n+1 = upgradeBase * UPGRADE_COST_MULT[n]
	UPGRADE_COST_MULT = { 0.5, 1, 2, 4 },
	RESTOCK_SECONDS = 8, -- seconds to restock one product
	SHOPPER_INTERVAL = 14, -- seconds between shoppers
	order = { "Shelf1", "Shelf2", "Shelf3", "Shelf4" },
}
