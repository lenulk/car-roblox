--!strict
-- accent = neon trim color (omitted = plot's own color); stripe = wall stripe (omitted = none)
local list = {
	{
		id = "Classic",
		price = 0,
		wall = Color3.fromRGB(236, 238, 242),
		floor = Color3.fromRGB(224, 226, 230),
		roof = Color3.fromRGB(70, 74, 84),
		uniform = Color3.fromRGB(235, 120, 30),
	},
	{
		id = "NeonCyber",
		price = 25000,
		accent = Color3.fromRGB(0, 240, 255),
		wall = Color3.fromRGB(28, 30, 46),
		floor = Color3.fromRGB(40, 44, 64),
		roof = Color3.fromRGB(14, 16, 26),
		stripe = Color3.fromRGB(255, 0, 170),
		uniform = Color3.fromRGB(20, 24, 40),
	},
	{
		id = "JDM",
		price = 60000,
		accent = Color3.fromRGB(255, 40, 60),
		wall = Color3.fromRGB(245, 245, 245),
		floor = Color3.fromRGB(60, 62, 70),
		roof = Color3.fromRGB(25, 25, 30),
		stripe = Color3.fromRGB(20, 20, 20),
		uniform = Color3.fromRGB(250, 250, 250),
	},
	{
		id = "Luxury",
		price = 120000,
		accent = Color3.fromRGB(255, 200, 80),
		wall = Color3.fromRGB(22, 20, 18),
		floor = Color3.fromRGB(40, 34, 28),
		roof = Color3.fromRGB(12, 10, 8),
		stripe = Color3.fromRGB(200, 160, 60),
		uniform = Color3.fromRGB(20, 18, 16),
	},
}
local byId = {}
for _, entry in list do
	byId[entry.id] = entry
end
return { list = list, byId = byId }
