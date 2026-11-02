--!strict
-- stats are multipliers around 1 (maxSpeed in studs/s)
local list = {
	{ id = "Sedan", price = 0, stats = { maxSpeed = 70, accel = 1, handling = 1, braking = 1, grip = 1 } },
	{ id = "Pickup", price = 12000, stats = { maxSpeed = 68, accel = 1.1, handling = 0.95, braking = 1, grip = 1.05 } },
	{ id = "Truck", price = 28000, stats = { maxSpeed = 62, accel = 1.2, handling = 0.9, braking = 1.1, grip = 1.2 } },
	{ id = "Muscle", price = 35000, stats = { maxSpeed = 95, accel = 1.35, handling = 0.95, braking = 1, grip = 1 } },
	{ id = "Sports", price = 60000, stats = { maxSpeed = 108, accel = 1.3, handling = 1.25, braking = 1.2, grip = 1.15 } },
	{ id = "Super", price = 150000, stats = { maxSpeed = 125, accel = 1.5, handling = 1.35, braking = 1.3, grip = 1.25 } },
}
local byId = {}
for _, entry in list do
	byId[entry.id] = entry
end

-- stat = which stat the upgrade multiplies, perLevel = bonus per level above 1
local UPGRADES = {
	engine = { stat = "maxSpeed", perLevel = 0.08 },
	gearbox = { stat = "accel", perLevel = 0.12 },
	suspension = { stat = "handling", perLevel = 0.1 },
	brakes = { stat = "braking", perLevel = 0.15 },
	tires = { stat = "grip", perLevel = 0.1 },
}
local UPGRADE_ORDER = { "engine", "gearbox", "suspension", "brakes", "tires" }
local MAX_LEVEL = 5
local COST_MULT = { 1, 2, 3.5, 6 }

-- cost to go from level to level+1; nil at max level
local function upgradeCost(carPrice: number, level: number): number?
	if level >= MAX_LEVEL then
		return nil
	end
	return math.floor(math.max(1500, carPrice * 0.12) * COST_MULT[level])
end

-- copy of the car's stats with every upgrade applied
local function statsFor(carId: string, upgrades: { [string]: number }?): { [string]: number }
	local out: { [string]: number } = {}
	for key, value in pairs(byId[carId].stats) do
		out[key] = value
	end
	for upgradeId, up in pairs(UPGRADES) do
		local level = if upgrades then (upgrades[upgradeId] or 1) else 1
		out[up.stat] = out[up.stat] * (1 + up.perLevel * (level - 1))
	end
	return out
end

return {
	list = list,
	byId = byId,
	UPGRADES = UPGRADES,
	UPGRADE_ORDER = UPGRADE_ORDER,
	MAX_LEVEL = MAX_LEVEL,
	upgradeCost = upgradeCost,
	statsFor = statsFor,
}
