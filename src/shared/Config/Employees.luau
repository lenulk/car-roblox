--!strict
local list = {
	{
		id = "mechanic",
		price = 1000,
		slotKind = "Bay",
		shirtColor = Color3.fromRGB(235, 120, 30),
		pantsColor = Color3.fromRGB(40, 45, 60),
	},
	{
		id = "cashier",
		price = 1500,
		slotKind = "Cashier",
		requiresUnlock = "Cashier",
		shirtColor = Color3.fromRGB(40, 120, 220),
		pantsColor = Color3.fromRGB(30, 30, 35),
	},
}
local byId = {}
for _, entry in list do
	byId[entry.id] = entry
end
return { list = list, byId = byId }
