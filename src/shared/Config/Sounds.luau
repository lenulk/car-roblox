--!strict
-- Sound effects. An empty id means that sound is off (SoundFx creates nothing).
-- To enable one: upload assets/sounds_draft/<key>.wav, then paste "rbxassetid://<number>" as the id.
-- Fields: id (string or number, "" / 0 = off), volume, pitchJitter (random +- playback speed),
--         looped (use SoundFx.attach), cooldown (seconds between plays per key and parent, default 0.08),
--         maxDistance (3D roll-off distance in studs, default 60).
-- Adding a sound: one line here + one SoundFx.play(parent, "key") call where it should be heard.
return {
	hammerStrike = { id = "rbxassetid://115558479847711", volume = 0.6, pitchJitter = 0.1 },
	wrench = { id = "rbxassetid://130619859186477", volume = 0.5, pitchJitter = 0.1 },
	spray = { id = "rbxassetid://78380289112926", volume = 0.35, looped = true },
	greet = { id = "rbxassetid://122293261122306", volume = 0.45, pitchJitter = 0.05, cooldown = 1 },
	crateDrop = { id = "rbxassetid://84092922276822", volume = 0.6, pitchJitter = 0.08 },
	shopperBuy = { id = "rbxassetid://92843313807987", volume = 0.5, pitchJitter = 0.08 },
	repairDone = { id = "rbxassetid://100620890674842", volume = 0.6, maxDistance = 90 },
	purchase = { id = "rbxassetid://115870602105854", volume = 0.6 }, -- client UI sound (not 3D)

	-- Opening scene (Prologue). Ids are empty on purpose: upload your own files, then paste the ids.
	crowdLoop = { id = "", volume = 0.5, looped = true }, -- stadium crowd ambience
	crowdCheer = { id = "", volume = 0.7, cooldown = 1.5 },
	crowdGasp = { id = "", volume = 0.8, cooldown = 1.5 },
	countdownBeep = { id = "", volume = 0.6, cooldown = 0.3 },
	countdownGo = { id = "", volume = 0.7, cooldown = 0.3 },
	raceEngine = { id = "", volume = 0.5, looped = true, maxDistance = 200 }, -- PlaybackSpeed follows speed
	engineSputter = { id = "", volume = 0.7, maxDistance = 200, cooldown = 1 },
	engineBlow = { id = "", volume = 1, maxDistance = 400, cooldown = 1 },
}
