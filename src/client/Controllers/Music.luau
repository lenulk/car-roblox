--!strict
-- Background music: a looping Sound named "Music" under SoundService (Volume 0.35), created here when
-- Game.MUSIC_SOUND_ID is set. Plays or pauses with snapshot.settings.music. Settings.luau calls
-- Music.setWanted() too, so both always agree.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig: any = require(Shared:WaitForChild("Config"):WaitForChild("Game") :: ModuleScript)
local Client = (script.Parent :: Instance).Parent :: Instance
local ClientState: any = require(Client:WaitForChild("ClientState") :: ModuleScript)

local Music = {}

local VOLUME = 0.35

local sound: Sound? = nil
local wanted: boolean? = nil

local function apply()
	local s = sound
	if s == nil or wanted == nil then
		return
	end
	if wanted then
		if not s.IsPlaying then
			s:Play()
		end
	else
		if s.IsPlaying then
			s:Pause()
		end
	end
end

-- true = music should play, false = paused.
function Music.setWanted(value: boolean)
	wanted = value
	apply()
end

function Music.start()
	local id: any = GameConfig.MUSIC_SOUND_ID
	if type(id) ~= "string" or id == "" then
		return
	end

	local existing = SoundService:FindFirstChild("Music")
	local music: Sound
	if existing ~= nil and existing:IsA("Sound") then
		music = existing
	else
		music = Instance.new("Sound")
		music.Name = "Music"
		music.Parent = SoundService
	end
	music.SoundId = id
	music.Looped = true
	music.Volume = VOLUME
	sound = music

	ClientState.onChanged(function(snapshot: any)
		local settings: any = snapshot.settings
		if settings ~= nil and settings.music ~= nil then
			wanted = settings.music == true
		end
		apply()
	end)
	apply()
end

return Music
