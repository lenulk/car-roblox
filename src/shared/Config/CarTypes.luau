--!strict
-- size = Vector3.new(width, height, length)
local list = {
	{
		id = "Sedan",
		payMult = 1,
		weight = 3,
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
		weight = 1,
		size = Vector3.new(7.5, 5.5, 15),
		colors = {
			Color3.fromRGB(230, 180, 30),
			Color3.fromRGB(60, 110, 60),
			Color3.fromRGB(240, 240, 240),
			Color3.fromRGB(110, 70, 40),
		},
	},
}
local byId = {}
for _, entry in list do
	byId[entry.id] = entry
end
return { list = list, byId = byId }
