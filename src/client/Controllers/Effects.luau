--!strict
-- One-shot visual / sound effects requested by the server (Effect remote). Purely cosmetic and client-only.
-- Also exports Effects.confetti(guiParent, count?) and Effects.coinRain(guiParent, count?) for UI popups.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes: any = require(Shared:WaitForChild("Remotes") :: ModuleScript)
local SoundFx: any = require(Shared:WaitForChild("SoundFx") :: ModuleScript)
local Client = (script.Parent :: Instance).Parent :: Instance
local Theme: any = require(Client:WaitForChild("Theme") :: ModuleScript)

local Effects = {}

local PING_SOUND = "rbxasset://sounds/electronicpingshort.wav"

----------------------------------------------------------------------------------------------------
-- UI helpers other controllers can call (they only need a GuiObject to draw into; no start() needed).
----------------------------------------------------------------------------------------------------

-- Burst of confetti from the middle of `parent`, falling with gravity. Pieces clean themselves up.
function Effects.confetti(parent: any, count: number?)
	local C = Theme.colors
	local colors = { C.accent, C.star, C.money, Color3.fromRGB(90, 170, 255), Color3.fromRGB(255, 120, 170) }
	for _ = 1, count or 30 do
		local piece = Theme.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.42),
			Size = UDim2.fromOffset(math.random(7, 11), math.random(10, 16)),
			BackgroundColor3 = colors[math.random(1, #colors)],
			Rotation = math.random(0, 360),
			ZIndex = 50,
		}, parent)
		local dx = math.random(-300, 300)
		local up = math.random(40, 220)
		local fall = math.random(160, 360)
		local riseTime = 0.35 + math.random() * 0.2
		local fallTime = 0.9 + math.random() * 0.7
		Theme.tween(piece, { Position = UDim2.new(0.5, dx, 0.42, -up), Rotation = math.random(-360, 360) }, riseTime, Enum.EasingStyle.Quad)
		task.delay(riseTime, function()
			if piece.Parent then
				Theme.tween(
					piece,
					{ Position = UDim2.new(0.5, dx * 1.25, 0.42, fall), Rotation = math.random(-540, 540) },
					fallTime,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.In
				)
				task.delay(fallTime * 0.6, function()
					if piece.Parent then
						Theme.tween(piece, { BackgroundTransparency = 1 }, fallTime * 0.4)
					end
				end)
			end
		end)
		task.delay(riseTime + fallTime + 0.15, function()
			piece:Destroy()
		end)
	end
end

-- Gold coins ("$" discs) raining from the top edge of `parent`.
function Effects.coinRain(parent: any, count: number?)
	local C = Theme.colors
	for _ = 1, count or 36 do
		local size = math.random(26, 40)
		local startX = math.random()
		local endX = math.clamp(startX + (math.random() - 0.5) * 0.12, 0, 1)
		local delay = math.random() * 1.4
		local duration = 1.3 + math.random() * 1.0
		task.delay(delay, function()
			if parent.Parent == nil then
				return
			end
			local coin = Theme.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(startX, 0, 0, -40),
				Size = UDim2.fromOffset(size, size),
				BackgroundColor3 = C.star,
				ZIndex = 50,
			}, parent)
			Theme.corner(coin, math.floor(size / 2))
			Theme.stroke(coin, Color3.fromRGB(214, 150, 20), 2.5, 0)
			Theme.label({
				Size = UDim2.fromScale(1, 1),
				Text = "$",
				TextSize = math.floor(size * 0.62),
				TextColor3 = Color3.fromRGB(150, 96, 10),
				ZIndex = 51,
			}, coin)
			Theme.tween(
				coin,
				{ Position = UDim2.new(endX, 0, 1, 40), Rotation = math.random(-90, 90) },
				duration,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.In
			)
			task.delay(duration + 0.1, function()
				coin:Destroy()
			end)
		end)
	end
end

function Effects.start()
	local C = Theme.colors

	local folder = Instance.new("Folder")
	folder.Name = "ClientEffects"
	folder.Parent = Workspace

	local function anchorPart(name: string, position: Vector3, size: Vector3?): any
		return Theme.new("Part", {
			Name = name,
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Transparency = 1,
			Size = size or Vector3.new(1, 1, 1),
			CFrame = CFrame.new(position),
		}, folder)
	end

	local function cleanup(instance: Instance, seconds: number)
		task.delay(seconds, function()
			if instance.Parent then
				instance:Destroy()
			end
		end)
	end

	local function unlock(position: Vector3)
		local part = anchorPart("UnlockFx", position)

		local emitter = Instance.new("ParticleEmitter")
		emitter.Rate = 0
		emitter.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, C.accent),
			ColorSequenceKeypoint.new(0.5, C.star),
			ColorSequenceKeypoint.new(1, C.accent),
		})
		emitter.LightEmission = 1
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.9),
			NumberSequenceKeypoint.new(1, 0),
		})
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.7, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Lifetime = NumberRange.new(0.8, 1.6)
		emitter.Speed = NumberRange.new(14, 30)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Acceleration = Vector3.new(0, -12, 0)
		emitter.Drag = 1.5
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-180, 180)
		emitter.Parent = part
		emitter:Emit(60)

		-- expanding neon ring (flat cylinder, fades out)
		local ring = Theme.new("Part", {
			Name = "UnlockRing",
			Shape = Enum.PartType.Cylinder,
			Material = Enum.Material.Neon,
			Color = C.accent,
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Transparency = 0.2,
			Size = Vector3.new(0.3, 2, 2),
			CFrame = CFrame.new(position + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		}, folder)
		Theme.tween(ring, { Size = Vector3.new(0.3, 26, 26), Transparency = 1 }, 0.9, Enum.EasingStyle.Quad)

		local sound = Instance.new("Sound")
		sound.SoundId = PING_SOUND
		sound.Volume = 0.7
		sound.RollOffMaxDistance = 150
		sound.Parent = part
		sound:Play()

		cleanup(part, 3)
		cleanup(ring, 3)
	end

	local function cash(position: Vector3, text: string)
		if text == "" then
			return
		end
		local part = anchorPart("CashFx", position)
		local gui = Theme.new("BillboardGui", {
			Adornee = part,
			Size = UDim2.fromOffset(180, 50),
			StudsOffset = Vector3.new(0, 2, 0),
			AlwaysOnTop = true,
			MaxDistance = 200,
			LightInfluence = 0,
		}, part)
		local label = Theme.label({
			Size = UDim2.fromScale(1, 1),
			Text = text,
			TextSize = 34,
			TextColor3 = C.money,
			TextStrokeColor3 = C.black,
			TextStrokeTransparency = 0.35,
		}, gui)
		Theme.tween(gui, { StudsOffset = Vector3.new(0, 6, 0) }, 1.2, Enum.EasingStyle.Quad)
		task.delay(0.5, function()
			Theme.tween(label, { TextTransparency = 1, TextStrokeTransparency = 1 }, 0.7)
		end)
		cleanup(part, 1.5)
	end

	local function repair(position: Vector3)
		local part = anchorPart("RepairFx", position)
		local emitter = Instance.new("ParticleEmitter")
		emitter.Rate = 0
		emitter.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(140, 205, 255))
		emitter.LightEmission = 1
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(1, 0),
		})
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Lifetime = NumberRange.new(0.5, 0.9)
		emitter.Speed = NumberRange.new(6, 12)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Parent = part
		emitter:Emit(16)
		cleanup(part, 2)
	end

	-- "Level": big upward burst of stars + rising gold rings + a rising two-note ping.
	local function levelUp(position: Vector3)
		local part = anchorPart("LevelFx", position)

		local burst = Instance.new("ParticleEmitter")
		burst.Rate = 0
		burst.Color = ColorSequence.new(Color3.fromRGB(255, 244, 170), C.star)
		burst.LightEmission = 1
		burst.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.2),
			NumberSequenceKeypoint.new(1, 0),
		})
		burst.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.7, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		burst.Lifetime = NumberRange.new(1, 1.8)
		burst.Speed = NumberRange.new(20, 40)
		burst.SpreadAngle = Vector2.new(28, 28)
		burst.EmissionDirection = Enum.NormalId.Top
		burst.Acceleration = Vector3.new(0, -8, 0)
		burst.Drag = 0.8
		burst.Rotation = NumberRange.new(0, 360)
		burst.RotSpeed = NumberRange.new(-120, 120)
		burst.Parent = part
		burst:Emit(46)

		-- flying star glyphs
		for _ = 1, 14 do
			local gui = Theme.new("BillboardGui", {
				Adornee = part,
				Size = UDim2.fromOffset(44, 44),
				StudsOffset = Vector3.new((math.random() - 0.5) * 4, 1, (math.random() - 0.5) * 4),
				AlwaysOnTop = true,
				MaxDistance = 300,
				LightInfluence = 0,
			}, part)
			local star = Theme.label({
				Size = UDim2.fromScale(1, 1),
				Text = "★",
				TextSize = math.random(26, 44),
				TextColor3 = C.star,
				TextStrokeColor3 = C.accent,
				TextStrokeTransparency = 0.5,
			}, gui)
			local life = 1.1 + math.random() * 0.7
			Theme.tween(
				gui,
				{ StudsOffset = Vector3.new((math.random() - 0.5) * 14, 9 + math.random() * 9, (math.random() - 0.5) * 14) },
				life,
				Enum.EasingStyle.Quad
			)
			task.delay(life * 0.5, function()
				if star.Parent then
					Theme.tween(star, { TextTransparency = 1, TextStrokeTransparency = 1 }, life * 0.5)
				end
			end)
		end

		-- three rings that rise and expand
		for i = 1, 3 do
			task.delay((i - 1) * 0.2, function()
				if part.Parent == nil then
					return
				end
				local flat = CFrame.Angles(0, 0, math.rad(90))
				local ring = Theme.new("Part", {
					Name = "LevelRing",
					Shape = Enum.PartType.Cylinder,
					Material = Enum.Material.Neon,
					Color = C.star,
					Anchored = true,
					CanCollide = false,
					CanQuery = false,
					CanTouch = false,
					CastShadow = false,
					Transparency = 0.35,
					Size = Vector3.new(0.25, 3, 3),
					CFrame = CFrame.new(position + Vector3.new(0, 0.5, 0)) * flat,
				}, folder)
				Theme.tween(ring, {
					Size = Vector3.new(0.25, 14, 14),
					Transparency = 1,
					CFrame = CFrame.new(position + Vector3.new(0, 11, 0)) * flat,
				}, 1.1, Enum.EasingStyle.Quad)
				cleanup(ring, 1.5)
			end)
		end

		for i = 1, 2 do
			task.delay((i - 1) * 0.16, function()
				if part.Parent == nil then
					return
				end
				local sound = Instance.new("Sound")
				sound.SoundId = PING_SOUND
				sound.Volume = 0.7
				sound.PlaybackSpeed = if i == 1 then 1 else 1.5
				sound.RollOffMaxDistance = 200
				sound.Parent = part
				sound:Play()
			end)
		end
		cleanup(part, 3.5)
	end

	-- "Wash": soap bubbles burst out and drift up.
	local function wash(position: Vector3)
		local part = anchorPart("WashFx", position)

		local foam = Instance.new("ParticleEmitter")
		foam.Rate = 0
		foam.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 225, 255))
		foam.LightEmission = 0.4
		foam.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(0.4, 1.2),
			NumberSequenceKeypoint.new(1, 0.6),
		})
		foam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		foam.Lifetime = NumberRange.new(0.9, 1.8)
		foam.Speed = NumberRange.new(5, 12)
		foam.SpreadAngle = Vector2.new(180, 180)
		foam.Acceleration = Vector3.new(0, 5, 0)
		foam.Drag = 1
		foam.Parent = part
		foam:Emit(30)

		for _ = 1, 10 do
			local diameter = 0.5 + math.random() * 1.1
			local start = position + Vector3.new((math.random() - 0.5) * 6, math.random() * 1.5, (math.random() - 0.5) * 6)
			local bubble = Theme.new("Part", {
				Name = "WashBubble",
				Shape = Enum.PartType.Ball,
				Material = Enum.Material.SmoothPlastic,
				Color = Color3.fromRGB(190, 232, 255),
				Anchored = true,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				CastShadow = false,
				Transparency = 0.45,
				Size = Vector3.new(diameter, diameter, diameter),
				CFrame = CFrame.new(start),
			}, folder)
			local life = 1.1 + math.random() * 0.8
			Theme.tween(bubble, {
				Position = start + Vector3.new((math.random() - 0.5) * 3, 4 + math.random() * 5, (math.random() - 0.5) * 3),
				Size = Vector3.new(diameter * 1.35, diameter * 1.35, diameter * 1.35),
				Transparency = 1,
			}, life, Enum.EasingStyle.Sine)
			cleanup(bubble, life + 0.3)
		end
		cleanup(part, 2.5)
	end

	-- "Coins": small floating "+$X" in gold and a coin sparkle.
	local function coins(position: Vector3, text: string)
		local part = anchorPart("CoinsFx", position)

		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Rate = 0
		sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 244, 170), C.star)
		sparkle.LightEmission = 1
		sparkle.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(1, 0),
		})
		sparkle.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		sparkle.Lifetime = NumberRange.new(0.5, 0.9)
		sparkle.Speed = NumberRange.new(6, 14)
		sparkle.SpreadAngle = Vector2.new(180, 180)
		sparkle.Acceleration = Vector3.new(0, -14, 0)
		sparkle.Rotation = NumberRange.new(0, 360)
		sparkle.Parent = part
		sparkle:Emit(12)

		if text ~= "" then
			local gui = Theme.new("BillboardGui", {
				Adornee = part,
				Size = UDim2.fromOffset(150, 40),
				StudsOffset = Vector3.new(0, 2, 0),
				AlwaysOnTop = true,
				MaxDistance = 200,
				LightInfluence = 0,
			}, part)
			local label = Theme.label({
				Size = UDim2.fromScale(1, 1),
				Text = text,
				TextSize = 26,
				TextColor3 = C.star,
				TextStrokeColor3 = C.black,
				TextStrokeTransparency = 0.35,
			}, gui)
			Theme.tween(gui, { StudsOffset = Vector3.new(0, 5, 0) }, 1.1, Enum.EasingStyle.Quad)
			task.delay(0.5, function()
				if label.Parent then
					Theme.tween(label, { TextTransparency = 1, TextStrokeTransparency = 1 }, 0.5)
				end
			end)
		end

		local sound = Instance.new("Sound")
		sound.SoundId = PING_SOUND
		sound.Volume = 0.35
		sound.PlaybackSpeed = 1.6
		sound.RollOffMaxDistance = 100
		sound.Parent = part
		sound:Play()
		cleanup(part, 2)
	end

	Remotes.get("Effect").OnClientEvent:Connect(function(effect: any, position: any, text: any)
		if type(effect) ~= "string" or typeof(position) ~= "Vector3" then
			return
		end
		if effect == "Unlock" then
			unlock(position)
			SoundFx.play(SoundService, "purchase")
		elseif effect == "Cash" then
			cash(position, if type(text) == "string" then text else "")
		elseif effect == "Repair" then
			repair(position)
		elseif effect == "Level" then
			levelUp(position)
		elseif effect == "Wash" then
			wash(position)
		elseif effect == "Coins" then
			coins(position, if type(text) == "string" then text else "")
		elseif effect == "Purchase" then
			-- Robux purchase granted (PurchaseService)
			coins(position, if type(text) == "string" then text else "")
			SoundFx.play(SoundService, "purchase")
		end
	end)
end

return Effects
