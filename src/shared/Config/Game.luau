--!strict
return {
	STARTING_MONEY = 100, -- wallet money for a new player
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
}
