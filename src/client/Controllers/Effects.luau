--!strict
-- One-shot visual / sound effects requested by the server (Effect remote). Purely cosmetic and client-only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes: any = require(Shared:WaitForChild("Remotes") :: ModuleScript)
local Client = (script.Parent :: Instance).Parent :: Instance
local Theme: any = require(Client:WaitForChild("Theme") :: ModuleScript)

local Effects = {}

local PING_SOUND = "rbxasset://sounds/electronicpingshort.wav"

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

	Remotes.get("Effect").OnClientEvent:Connect(function(effect: any, position: any, text: any)
		if type(effect) ~= "string" or typeof(position) ~= "Vector3" then
			return
		end
		if effect == "Unlock" then
			unlock(position)
		elseif effect == "Cash" then
			cash(position, if type(text) == "string" then text else "")
		elseif effect == "Repair" then
			repair(position)
		end
	end)
end

return Effects
