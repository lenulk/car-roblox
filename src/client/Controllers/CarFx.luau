--!strict
-- Rainbow looks for the Robux paint / underglow. The server (CarBuilder) only tags the parts:
--   "RainbowPaint"  painted body parts of a car with the Rainbow paint
--   "RainbowNeon"   underglow parts (and their PointLight) of a car with the Rainbow underglow
-- Here one Heartbeat loop cycles the hue of tagged parts that are near the camera (cars further away keep their last colour).

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CarFx = {}

local TAG_PAINT = "RainbowPaint"
local TAG_NEON = "RainbowNeon"
local NEAR_DISTANCE = 150 -- studs from the camera
local UPDATE_RATE = 20 -- Hz
local PAINT_SPEED = 0.18 -- hue cycles per second
local NEON_SPEED = 0.3

function CarFx.start()
	local paintParts: { [BasePart]: boolean } = {}
	local neonParts: { [BasePart]: boolean } = {}

	local function track(set: { [BasePart]: boolean }, tag: string)
		local function add(inst: Instance)
			if inst:IsA("BasePart") then
				set[inst] = true
			end
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(add)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst)
			if inst:IsA("BasePart") then
				set[inst] = nil
			end
		end)
		for _, inst in CollectionService:GetTagged(tag) do
			add(inst)
		end
	end
	track(paintParts, TAG_PAINT)
	track(neonParts, TAG_NEON)

	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated < 1 / UPDATE_RATE then
			return
		end
		accumulated = 0
		if next(paintParts) == nil and next(neonParts) == nil then
			return
		end
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local origin = camera.CFrame.Position
		local clock = os.clock()
		local paintColor = Color3.fromHSV((clock * PAINT_SPEED) % 1, 0.8, 1)
		local neonColor = Color3.fromHSV((clock * NEON_SPEED) % 1, 0.9, 1)

		for part in paintParts do
			if part.Parent == nil then
				paintParts[part] = nil
			elseif (part.Position - origin).Magnitude < NEAR_DISTANCE then
				part.Color = paintColor
			end
		end
		for part in neonParts do
			if part.Parent == nil then
				neonParts[part] = nil
			elseif (part.Position - origin).Magnitude < NEAR_DISTANCE then
				part.Color = neonColor
				for _, child in part:GetChildren() do
					if child:IsA("PointLight") then
						child.Color = neonColor
					end
				end
			end
		end
	end)
end

return CarFx
