--!strict
-- kind "color": option ids are hex "RRGGBB"; kind "choice": option ids are names
local categories = {
	{
		id = "paint",
		kind = "color",
		options = {
			{ id = "E8E8EC", price = 0 },
			{ id = "1E1E22", price = 0 },
			{ id = "C8282D", price = 0 },
			{ id = "2F5BD3", price = 0 },
			{ id = "F5C518", price = 500 },
			{ id = "2FB35A", price = 500 },
			{ id = "FF7A1A", price = 500 },
			{ id = "8E3BD9", price = 500 },
			{ id = "19C3D6", price = 800 },
			{ id = "FF4FA3", price = 800 },
			{ id = "7A4A2A", price = 500 },
			{ id = "9EA3AD", price = 500 },
			{ id = "0B2A5B", price = 800 },
			{ id = "B00020", price = 800 },
			{ id = "6BFF3A", price = 1500 },
			{ id = "FFD700", price = 2500 },
		},
	},
	{
		id = "material",
		kind = "choice",
		options = {
			{ id = "Gloss", price = 0 },
			{ id = "Matte", price = 1000 },
			{ id = "Metallic", price = 3000 },
			{ id = "Pearl", price = 5000 },
			{ id = "Carbon", price = 8000 },
			{ id = "Chrome", price = 12000 },
			{ id = "Neon", price = 15000 },
		},
	},
	{
		id = "wheel",
		kind = "choice",
		options = {
			{ id = "Classic", price = 0 },
			{ id = "Sport", price = 1500 },
			{ id = "Turbo", price = 3000 },
			{ id = "Mesh", price = 4000 },
			{ id = "OffRoad", price = 4000 },
			{ id = "DeepDish", price = 5000 },
			{ id = "Spinner", price = 7000 },
			{ id = "NeonRim", price = 10000 },
		},
	},
	{
		id = "rim",
		kind = "color",
		options = {
			{ id = "D8DBE2", price = 0 },
			{ id = "1A1A1E", price = 300 },
			{ id = "C8282D", price = 300 },
			{ id = "2F5BD3", price = 300 },
			{ id = "19C3D6", price = 500 },
			{ id = "FFD700", price = 800 },
		},
	},
	{
		id = "caliper",
		kind = "color",
		options = {
			{ id = "9EA3AD", price = 0 },
			{ id = "C8282D", price = 300 },
			{ id = "F5C518", price = 300 },
			{ id = "2F5BD3", price = 300 },
			{ id = "2FB35A", price = 300 },
			{ id = "FF7A1A", price = 300 },
		},
	},
	{
		id = "spoiler",
		kind = "choice",
		options = {
			{ id = "None", price = 0 },
			{ id = "Lip", price = 1000 },
			{ id = "Ducktail", price = 2000 },
			{ id = "Wing", price = 3000 },
			{ id = "GTWing", price = 6000 },
		},
	},
	{
		id = "kit",
		kind = "choice",
		options = {
			{ id = "Stock", price = 0 },
			{ id = "Street", price = 4000 },
			{ id = "Race", price = 9000 },
		},
	},
	{
		id = "hood",
		kind = "choice",
		options = {
			{ id = "Stock", price = 0 },
			{ id = "Scoop", price = 2500 },
			{ id = "Carbon", price = 3000 },
		},
	},
	{
		id = "tint",
		kind = "choice",
		options = {
			{ id = "Clear", price = 0 },
			{ id = "Smoke", price = 500 },
			{ id = "Black", price = 1000 },
		},
	},
	{
		id = "neon",
		kind = "color",
		options = {
			{ id = "None", price = 0 },
			{ id = "19C3D6", price = 2000 },
			{ id = "FF4FA3", price = 2000 },
			{ id = "6BFF3A", price = 2000 },
			{ id = "8E3BD9", price = 2000 },
			{ id = "FF7A1A", price = 2000 },
			{ id = "FFFFFF", price = 2000 },
		},
	},
	{
		id = "headlight",
		kind = "color",
		options = {
			{ id = "FFF4D0", price = 0 },
			{ id = "FFFFFF", price = 400 },
			{ id = "7FC8FF", price = 800 },
			{ id = "B48CFF", price = 800 },
			{ id = "6BFF3A", price = 800 },
			{ id = "FF4040", price = 800 },
		},
	},
	{
		id = "flames",
		kind = "choice",
		options = {
			{ id = "Off", price = 0 },
			{ id = "Orange", price = 5000 },
			{ id = "Blue", price = 8000 },
		},
	},
	{
		id = "smoke",
		kind = "color",
		options = {
			{ id = "None", price = 0 },
			{ id = "FFFFFF", price = 1500 },
			{ id = "19C3D6", price = 3000 },
			{ id = "FF4FA3", price = 3000 },
			{ id = "8E3BD9", price = 3000 },
		},
	},
	{
		id = "decal",
		kind = "choice",
		options = {
			{ id = "None", price = 0 },
			{ id = "Number", price = 1000 },
			{ id = "Stripes", price = 1500 },
			{ id = "Checker", price = 2500 },
			{ id = "Flames", price = 3000 },
		},
	},
}

local byId = {}
for _, category in categories do
	byId[category.id] = category
end

local DEFAULTS = {
	paint = "E8E8EC",
	material = "Gloss",
	wheel = "Classic",
	rim = "D8DBE2",
	caliper = "9EA3AD",
	spoiler = "None",
	kit = "Stock",
	hood = "Stock",
	tint = "Clear",
	neon = "None",
	headlight = "FFF4D0",
	flames = "Off",
	smoke = "None",
	decal = "None",
}

-- "RRGGBB" to Color3, white if the hex is invalid
local function hexToColor(hex: string): Color3
	local ok, color = pcall(Color3.fromHex, "#" .. hex)
	if ok then
		return color
	end
	return Color3.new(1, 1, 1)
end

-- price of one option in a category, nil if either id is unknown
local function price(category: string, optionId: string): number?
	local cat = byId[category]
	if cat == nil then
		return nil
	end
	for _, option in cat.options do
		if option.id == optionId then
			return option.price
		end
	end
	return nil
end

return {
	categories = categories,
	byId = byId,
	DEFAULTS = DEFAULTS,
	hexToColor = hexToColor,
	price = price,
}
