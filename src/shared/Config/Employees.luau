--!strict
local list = {
	{
		id = "mechanic",
		price = 1000,
		slotKind = "Bay",
		bays = { 1, 2, 3 },
		accessory = "cap",
		shirtColor = Color3.fromRGB(235, 120, 30),
		pantsColor = Color3.fromRGB(40, 45, 60),
	},
	{
		id = "painter",
		price = 8000,
		slotKind = "Bay",
		bays = { 4 },
		requiresUnlock = "Bay4",
		lockedKey = "hire_locked_needs_bay4",
		accessory = "mask",
		shirtColor = Color3.fromRGB(240, 240, 245),
		pantsColor = Color3.fromRGB(120, 126, 140),
	},
	{
		id = "cashier",
		price = 1500,
		slotKind = "Cashier",
		requiresUnlock = "Cashier",
		lockedKey = "hire_locked_needs_cashier",
		accessory = "badge",
		shirtColor = Color3.fromRGB(40, 120, 220),
		pantsColor = Color3.fromRGB(30, 30, 35),
	},
	{
		id = "stocker",
		price = 3000,
		slotKind = "Stock",
		requiresUnlock = "Shelf1",
		lockedKey = "hire_locked_needs_shelf",
		accessory = "apron",
		shirtColor = Color3.fromRGB(60, 160, 80),
		pantsColor = Color3.fromRGB(50, 50, 55),
	},
	{
		id = "receptionist",
		price = 5000,
		slotKind = "Reception",
		requiresUnlock = "Reception",
		lockedKey = "hire_locked_needs_reception",
		accessory = "headset",
		shirtColor = Color3.fromRGB(230, 90, 140),
		pantsColor = Color3.fromRGB(40, 40, 48),
	},
	{
		id = "manager",
		price = 50000,
		slotKind = "Office",
		requiresUnlock = "Office",
		lockedKey = "hire_locked_needs_office",
		accessory = "tie",
		shirtColor = Color3.fromRGB(35, 38, 50),
		pantsColor = Color3.fromRGB(30, 32, 40),
	},
}
local byId = {}
for _, entry in list do
	byId[entry.id] = entry
end
-- cost to go from level n to n+1 = price × UPGRADE_COST_MULT[n]
local UPGRADE_COST_MULT = { 0.5, 1, 2, 4 }
return { list = list, byId = byId, UPGRADE_COST_MULT = UPGRADE_COST_MULT }
