--!strict
-- SoundFx: the only sound player (server and client). Reads Config/Sounds.luau; a key whose id is empty
-- or 0 does nothing at all (returns nil, creates no Instance). Parent a sound under a BasePart for 3D
-- sound (server-created sounds replicate by themselves) or under any non-part (e.g. SoundService) for 2D.

local Debris = game:GetService("Debris")

local Sounds: any = require(script.Parent:WaitForChild("Config"):WaitForChild("Sounds") :: ModuleScript)

local SoundFx = {}

local DEFAULT_COOLDOWN = 0.08
local DEFAULT_DISTANCE = 60
local LOOP_NAME_PREFIX = "SoundFx_"
local LIFETIME_FALLBACK = 10 -- a one-shot is removed after this long even if Ended never fires

local rng = Random.new()
-- key -> last play time, per parent (weak so destroyed parents do not leak).
local lastPlayed: { [Instance]: { [string]: number } } = setmetatable({}, { __mode = "k" }) :: any

local function resolveId(entry: any): string?
	if type(entry) ~= "table" then
		return nil
	end
	local id: any = entry.id
	if type(id) == "number" then
		if id > 0 then
			return "rbxassetid://" .. tostring(math.floor(id))
		end
		return nil
	end
	if type(id) == "string" and id ~= "" and id ~= "0" then
		if tonumber(id) ~= nil then
			return "rbxassetid://" .. id
		end
		return id
	end
	return nil
end

local function create(parent: Instance, key: string, entry: any, soundId: string, looped: boolean): Sound
	local sound = Instance.new("Sound")
	sound.Name = LOOP_NAME_PREFIX .. key
	sound.SoundId = soundId
	sound.Volume = if type(entry.volume) == "number" then entry.volume else 0.5
	sound.Looped = looped
	sound.RollOffMaxDistance = if type(entry.maxDistance) == "number" then entry.maxDistance else DEFAULT_DISTANCE
	local jitter: any = entry.pitchJitter
	if type(jitter) == "number" and jitter > 0 then
		sound.PlaybackSpeed = 1 + rng:NextNumber(-jitter, jitter)
	end
	sound.Parent = parent
	return sound
end

--[[
	Plays a one-shot sound under `parent`. Returns the Sound, or nil when the key is off / unknown or the
	same key played on this parent less than its cooldown ago (keeps rapid events from stacking up).
]]
function SoundFx.play(parent: Instance, key: string): Sound?
	local entry: any = Sounds[key]
	local soundId = resolveId(entry)
	if soundId == nil then
		return nil
	end
	local now = os.clock()
	local perParent = lastPlayed[parent]
	if perParent == nil then
		perParent = {}
		lastPlayed[parent] = perParent
	end
	local times = perParent :: { [string]: number }
	local cooldown = if type(entry.cooldown) == "number" then entry.cooldown else DEFAULT_COOLDOWN
	local previous = times[key]
	if previous ~= nil and now - previous < cooldown then
		return nil
	end
	times[key] = now

	local sound = create(parent, key, entry, soundId, false)
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	Debris:AddItem(sound, LIFETIME_FALLBACK)
	sound:Play()
	return sound
end

--[[
	Starts a looping sound under `parent` and returns it (an existing one for the same key is reused).
	Stop it with SoundFx.release; it is also removed with its parent. Returns nil when the key is off.
]]
function SoundFx.attach(parent: Instance, key: string): Sound?
	local entry: any = Sounds[key]
	local soundId = resolveId(entry)
	if soundId == nil then
		return nil
	end
	local existing = parent:FindFirstChild(LOOP_NAME_PREFIX .. key)
	if existing ~= nil and existing:IsA("Sound") then
		if not existing.IsPlaying then
			existing:Play()
		end
		return existing
	end
	local sound = create(parent, key, entry, soundId, true)
	sound:Play()
	return sound
end

-- Stops and removes a sound returned by SoundFx.attach (nil is fine).
function SoundFx.release(sound: Sound?)
	if sound == nil then
		return
	end
	sound:Stop()
	sound:Destroy()
end

return SoundFx
