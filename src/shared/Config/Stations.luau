--!strict
return {
	byId = {
		tire = { id = "tire", baseCost = 400 },
		oil = { id = "oil", baseCost = 800 },
		lift = { id = "lift", baseCost = 4000 },
		paint = { id = "paint", baseCost = 11000 },
		wash = { id = "wash", baseCost = 7500 },
	},
	-- LEVELS[n] applies to station level n (1..5)
	LEVELS = {
		{ timeMult = 1, payMult = 1 },
		{ timeMult = 0.85, payMult = 1.2 },
		{ timeMult = 0.7, payMult = 1.45 },
		{ timeMult = 0.55, payMult = 1.75 },
		{ timeMult = 0.4, payMult = 2.2 },
	},
	-- cost to go from level n to n+1 = baseCost * UPGRADE_COST_MULT[n]
	UPGRADE_COST_MULT = { 0.5, 1, 2, 4 },
	-- fraction of a repair's pay added when the car drives through the wash, by wash level
	WASH_BONUS = { 0.10, 0.14, 0.18, 0.24, 0.30 },
}
