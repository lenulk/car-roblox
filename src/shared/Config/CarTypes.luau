--!strict
-- size = Vector3.new(width, height, length)
-- minStars = shop star level needed before this car shows up; vip = VIP customer
local list = {
	{
		id = "Sedan",
		payMult = 1,
		weight = 3,
		minStars = 0,
		size = Vector3.new(7, 4.5, 14),
		colors = {
			Color3.fromRGB(200, 40, 40),
			Color3.fromRGB(240, 240, 240),
			Color3.fromRGB(30, 30, 35),
			Color3.fromRGB(40, 90, 200),
			Color3.fromRGB(150, 150, 155),
		},
	},
	{
		id = "Pickup",
		payMult = 1.3,
		weight = 2,
		minStars = 0,
		size = Vector3.new(7.5, 5.5, 15),
		colors = {
			Color3.fromRGB(230, 180, 30),
			Color3.fromRGB(60, 110, 60),
			Color3.fromRGB(240, 240, 240),
			Color3.fromRGB(110, 70, 40),
		},
	},
	{
		id = "Muscle",
		payMult = 1.7,
		weight = 1.2,
		minStars = 1,
		size = Vector3.new(7.4, 4.6, 15.5),
		colors = {
			Color3.fromRGB(230, 90, 20),
			Color3.fromRGB(20, 20, 24),
			Color3.fromRGB(20, 80, 50),
			Color3.fromRGB(245, 200, 30),
		},
	},
	{
		id = "Truck",
		payMult = 1.5,
		weight = 1,
		minStars = 1,
		size = Vector3.new(8, 6.5, 17),
		colors = {
			Color3.fromRGB(240, 240, 240),
			Color3.fromRGB(40, 70, 160),
			Color3.fromRGB(180, 30, 30),
			Color3.fromRGB(110, 115, 125),
		},
	},
	{
		id = "Sports",
		payMult = 2,
		weight = 1,
		minStars = 2,
		size = Vector3.new(7.2, 4, 14.5),
		colors = {
			Color3.fromRGB(220, 20, 30),
			Color3.fromRGB(120, 230, 40),
			Color3.fromRGB(20, 200, 230),
			Color3.fromRGB(245, 245, 250),
			Color3.fromRGB(130, 50, 210),
		},
	},
	{
		id = "Super",
		payMult = 4,
		weight = 0.5,
		minStars = 3,
		vip = true,
		size = Vector3.new(7.6, 3.7, 15.5),
		colors = {
			Color3.fromRGB(230, 180, 40),
			Color3.fromRGB(18, 18, 20),
			Color3.fromRGB(250, 248, 240),
			Color3.fromRGB(255, 60, 160),
		},
	},
}

-- Bodies that exist only as personal cars (bought with Robux): CarBuilder can build them, but they never show up
-- as customers, so they are NOT in `list` (CustomerService / TrafficService pick from `list`).
local personalOnly = {
	{
		id = "Hyper",
		payMult = 4,
		weight = 0,
		minStars = 99,
		size = Vector3.new(8.0, 3.4, 15.8),
		colors = {
			Color3.fromRGB(255, 196, 48),
			Color3.fromRGB(18, 18, 20),
			Color3.fromRGB(0, 200, 230),
		},
	},
}

local byId = {}
for _, entry in list do
	byId[entry.id] = entry
end
for _, entry in personalOnly do
	byId[entry.id] = entry
end
return { list = list, byId = byId }
