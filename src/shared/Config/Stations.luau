--!strict
return {
	byId = {
		tire = { id = "tire", baseCost = 400 },
		oil = { id = "oil", baseCost = 800 },
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
}
