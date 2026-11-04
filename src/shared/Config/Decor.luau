--!strict
-- Storefront decorations. Each placed item shortens the time between customers (CustomerService, ShopService,
-- OfflineService); the total is capped by MAX_BONUS. Items with robuxProduct are bought with Robux
-- (Config/Products.Items); the others cost money (price).

export type DecorItem = { id: string, price: number?, bonus: number, robuxProduct: string? }

local items: { DecorItem } = {
	-- money
	{ id = "Bunting", price = 2000, bonus = 0.03 },
	{ id = "OpenSign", price = 6000, bonus = 0.04 }, -- blinking neon "OPEN"
	{ id = "TubeMan", price = 15000, bonus = 0.06 }, -- inflatable dancing tube man
	{ id = "BalloonArch", price = 30000, bonus = 0.06 },
	{ id = "ClassicStatue", price = 70000, bonus = 0.08 }, -- classic car on a plinth
	{ id = "Searchlight", price = 150000, bonus = 0.08 }, -- sky beam, stands out at night
	-- Robux
	{ id = "MascotBear", robuxProduct = "DecorBear", bonus = 0.10 }, -- 99 R$
	{ id = "MechRobot", robuxProduct = "DecorRobot", bonus = 0.10 }, -- 149 R$
	{ id = "NeonDragon", robuxProduct = "DecorDragon", bonus = 0.12 }, -- 199 R$
	{ id = "GoldStatue", robuxProduct = "DecorGold", bonus = 0.12 }, -- 249 R$
	{ id = "Fireworks", robuxProduct = "DecorFireworks", bonus = 0.08 }, -- 129 R$
}

local byId: { [string]: DecorItem } = {}
for _, item in items do
	byId[item.id] = item
end

local SLOTS = 6
local MAX_BONUS = 0.35 -- total spawn-interval reduction cap

-- Total bonus of the items placed in `placed` (slot string -> id), capped at MAX_BONUS.
local function totalBonus(placed: { [string]: string }): number
	local sum = 0
	for _, id in placed do
		local item = byId[id]
		if item then
			sum += item.bonus
		end
	end
	return math.min(MAX_BONUS, sum)
end

return {
	SLOTS = SLOTS,
	MAX_BONUS = MAX_BONUS,
	items = items,
	byId = byId,
	totalBonus = totalBonus,
}
