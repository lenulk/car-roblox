--!strict
return {
	STARTING_MONEY = 10000, -- wallet money for a new player
	DATASTORE_NAME = "GarageTycoon_v1", -- DataStore key name (bump the version to reset all saves)
	AUTOSAVE_INTERVAL = 60, -- seconds between autosaves
	QUEUE_CAPACITY_BASE = 3, -- cars that can wait in the queue before the Parking unlock
	QUEUE_CAPACITY_PARKING = 6, -- queue capacity once the Parking unlock is owned
	SPAWN_INTERVAL_BASE = 9, -- seconds between customers at 0 stars
	SPAWN_INTERVAL_PER_STAR = 0.8, -- seconds subtracted from the spawn interval per star level
	SPAWN_INTERVAL_MIN = 4, -- fastest possible spawn interval in seconds
	ROAD_SPEED = 32, -- studs per second on the ring road
	LOT_SPEED = 12, -- studs per second inside the plot lot
	TIP_PERCENT = 0.25, -- tip as a fraction of the pay
	TIP_WINDOW_FACTOR = 3, -- tip window = repairTime * this factor + TIP_WINDOW_BONUS seconds
	TIP_WINDOW_BONUS = 8, -- extra seconds added to the tip window
	STAR_THRESHOLDS = { 10, 40, 120, 300, 700 }, -- star points needed for 1..5 stars
	MECHANIC_SPEED = { 0.5, 0.625, 0.75, 0.875, 1 }, -- mechanic work speed as a fraction of player speed, by employee level
	CASHIER_COLLECT_INTERVAL = 2, -- seconds between cashier trips from the safe to the wallet
	OFFLINE_MAX_MINUTES = 120, -- cap on offline earnings accrual
	OFFLINE_EFFICIENCY = 0.4, -- fraction of normal income earned while offline
	DAILY_BASE = 500, -- daily reward on day 1 of the streak
	DAILY_MAX_STREAK = 7, -- streak length at which the daily reward stops growing
	DAY_LENGTH_MINUTES = 20, -- length of one in-game day/night cycle
	MUSIC_SOUND_ID = "", -- paste a Roblox audio asset id like "rbxassetid://123" here
	VIP_STAR_POINTS = 3, -- star points granted by a VIP customer
	CASHIER_BONUS = { 0, 0.03, 0.06, 0.09, 0.12 }, -- extra income fraction by employee level
	STOCKER_SPEED = { 2, 2.5, 3, 3.5, 4 }, -- stocker walk speed by employee level
	RECEPTION_SPAWN_MULT = { 0.85, 0.8, 0.75, 0.7, 0.65 }, -- customer spawn interval multiplier by receptionist level
	RECEPTION_TIP_BONUS = { 0.1, 0.15, 0.2, 0.25, 0.3 }, -- extra tip fraction by receptionist level
	MANAGER_SPEED = { 0.1, 0.15, 0.2, 0.25, 0.3 }, -- manager speed bonus by employee level
}
