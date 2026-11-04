--!strict
-- Every tunable of the opening scene (Prologue). Distances in studs, speeds in studs/s, times in seconds.
-- The scene is built and played on the client only; the server just stores `prologueDone`.

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

return {
	ARENA_ORIGIN = Vector3.new(0, 0, 5000), -- far away from the garage map
	FORCE_IN_STUDIO = false, -- true = play the scene on every join in Studio (testing only)
	SNAPSHOT_TIMEOUT = 40, -- give up waiting for the first snapshot after this long

	-- track ----------------------------------------------------------------------------------
	TRACK_SCALE = 0.85, -- control points are authored at 1.0, this scales the whole circuit
	TRACK_STEP = 16, -- spacing of the track points
	TRACK_WIDTH = 44,
	GRID_SLOTS = 7, -- the player takes the last slot
	GRID_FIRST = 18, -- distance behind the start line of slot 1
	GRID_SPACING = 20,
	GRID_LATERAL = 8.5,

	-- player car ------------------------------------------------------------------------------
	PLAYER_CAR = "Super",
	PLAYER_COLOR = rgb(222, 28, 40),
	CRUISE_SPEED = 75, -- automatic speed with no input
	MAX_SPEED = 95, -- holding forward
	BRAKE_SPEED = 24, -- holding back
	ACCEL = 26,
	DECEL = 45,
	STEER_SPEED = 26, -- sideways studs/s at standstill (shrinks with speed)
	STEER_RESPONSE = 90, -- how fast sideways speed follows the stick
	WALL_SPEED_LOSS = 0.3, -- fraction of speed lost on touching a wall
	SMOKE_SPEED_FACTOR = 0.88, -- top speed multiplier while the engine smokes
	COAST_DECAY = 1.3, -- exp(-k t) speed decay after the engine blows (~3 s to stop)

	-- rivals (6): car type, paint, base speed, preferred lane (sideways offset) ------------------
	RIVALS = {
		{ car = "Sports", color = rgb(30, 190, 230), speed = 73, lane = -10 },
		{ car = "Muscle", color = rgb(240, 120, 20), speed = 72, lane = 9 },
		{ car = "Super", color = rgb(24, 24, 28), speed = 74, lane = -4 },
		{ car = "Sports", color = rgb(120, 230, 40), speed = 71, lane = 11 },
		{ car = "Muscle", color = rgb(245, 205, 30), speed = 73.5, lane = 3 },
		{ car = "Super", color = rgb(245, 245, 250), speed = 70.5, lane = -12 },
	},
	RIVAL_ACCEL = 24,
	RIVAL_DECEL = 40,
	CORNER_GRIP = 110, -- lateral "acceleration" used to slow rivals in bends: v = sqrt(grip * radius)
	-- rubber band: a rival ahead runs at RUBBER_AHEAD_PACE x the player's speed (never below base x (1 - RUBBER_SLOW)),
	-- so the player gains ~4% and takes the lead late in the lap. A rival behind runs at RUBBER_BEHIND_PACE x when
	-- close and up to RUBBER_CATCHUP_PACE x when RUBBER_BEHIND_RANGE back, so the pack stays on the player's tail.
	RUBBER_AHEAD_PACE = 0.96,
	RUBBER_SLOW = 0.25,
	RUBBER_BEHIND_RANGE = 120,
	RUBBER_BEHIND_PACE = 0.97,
	RUBBER_CATCHUP_PACE = 1.1,
	BLOWN_RIVAL_BOOST = 1.2, -- rivals charge past the burning car
	AVOID_RATE = 22, -- max sideways studs/s of a rival dodging a car
	AVOID_GAIN = 2.2, -- sideways speed per stud of distance to the target lane (eases into the lane)
	AVOID_RESPONSE = 40, -- how fast a rival's sideways speed can change (studs/s^2)
	DODGE_HOLD = 0.8, -- seconds a rival keeps its passing line after the car ahead is clear

	-- timeline ---------------------------------------------------------------------------------
	INTRO_SECONDS = 7.5,
	COUNTDOWN_STEP = 0.95,
	GO_HOLD = 0.8,
	IDLE_TIMEOUT = 120, -- seconds of racing before the engine trouble is forced
	SMOKE_AT = 0.84, -- lap fraction where the smoke starts (inside the last corner approach)
	BLOW_AT = 0.885, -- lap fraction of the explosion (middle of the last corner)
	FORCED_BLOW_DELAY = 3, -- smoke -> blow when forced by IDLE_TIMEOUT
	SMOKE_TO_BLOW_MAX = 10, -- smoke -> blow at the latest
	BLOW_WATCH_SECONDS = 6.5, -- cinematic after the explosion
	STORY_FADE = 0.7,
	STORY_CARD_SECONDS = 3.2,
	WELCOME_SECONDS = 2.2,
	COMMENT_SECONDS = 2.5,
	COMMENT_COOLDOWN = 3.5,

	-- camera -------------------------------------------------------------------------------------
	-- Intro shots in track space: { s, d, height } for the camera and for the look target.
	INTRO_SHOTS = {
		{ cam = { 290, 95, 52 }, look = { 90, -55, 12 } },
		{ cam = { 120, 62, 30 }, look = { -20, -48, 12 } },
		{ cam = { -40, 20, 9 }, look = { -130, -2, 3 } },
		{ cam = { -190, -26, 7 }, look = { -138, -8, 2.5 } },
	},
	CHASE_BACK = 22,
	CHASE_UP = 8.5,
	CHASE_LOOK_AHEAD = 26,
	CHASE_FOV = 68,
	CHASE_FOV_BOOST = 14,
	ORBIT_RADIUS = 38,
	ORBIT_HEIGHT = 11,
	ORBIT_SPEED = 0.38, -- radians/s

	-- arena ----------------------------------------------------------------------------------------
	STAND_ROWS = 6,
	STAND_RISER = 2.2,
	STAND_DEPTH = 3.6,
	STAND_GAP = 18, -- road edge -> first row
	-- Stands in lap fractions. side: 1 = right of travel, -1 = left, 0 = outside of the bend.
	STANDS = {
		{ from = -0.015, to = 0.055, side = -1, roof = true, fill = 1.0, chunk = 60 }, -- main straight, outside
		{ from = -0.010, to = 0.040, side = 1, roof = true, fill = 0.8, chunk = 60 }, -- main straight, infield
		{ from = 0.862, to = 0.905, side = 0, roof = false, fill = 0.8, chunk = 20 }, -- last corner (the incident)
		{ from = 0.322, to = 0.352, side = 0, roof = false, fill = 0.6, chunk = 20 }, -- hairpin elbow
	},

	-- crowd ------------------------------------------------------------------------------------------
	CROWD_COUNT = 800,
	SEAT_SPACING = 2.1,
	CROWD_CULL = 300, -- only people closer than this to the camera animate
	CROWD_UPDATE_HZ = 30,
	CROWD_FLAG_RATIO = 0.1,
}
