--!strict
-- Animates every NPC the server tagged "NpcRig" (walk / idle / work / held poses). Joint Transforms written
-- on the server are not replicated, so the animation runs here from the Attributes NpcBuilder publishes.
-- See Shared/NpcAnim for the attribute list and the pose math.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NpcAnim = require(Shared:WaitForChild("NpcAnim") :: ModuleScript)

local NpcAnimator = {}

local MAX_DISTANCE = 220 -- studs from the camera; farther characters keep their last pose

local rigs: { [Model]: NpcAnim.Rig } = {}

local function track(instance: Instance)
	if instance:IsA("Model") and rigs[instance] == nil then
		rigs[instance] = NpcAnim.newRig(instance)
	end
end

local function step(dt: number)
	dt = math.min(dt, 0.1)
	local camera = workspace.CurrentCamera
	local cameraPosition = if camera then camera.CFrame.Position else nil
	local now = workspace:GetServerTimeNow()
	for model, rig in rigs do
		if model.Parent == nil then
			rigs[model] = nil
			continue
		end
		local root = model.PrimaryPart
		if cameraPosition and root and (root.Position - cameraPosition).Magnitude > MAX_DISTANCE then
			continue
		end
		NpcAnim.update(rig, dt, now)
	end
end

function NpcAnimator.start()
	for _, instance in CollectionService:GetTagged(NpcAnim.TAG) do
		track(instance)
	end
	CollectionService:GetInstanceAddedSignal(NpcAnim.TAG):Connect(track)
	CollectionService:GetInstanceRemovedSignal(NpcAnim.TAG):Connect(function(instance: Instance)
		if instance:IsA("Model") then
			rigs[instance] = nil
		end
	end)
	-- Joint Transforms are applied right after PreSimulation (see AnimationConstraint.Transform).
	RunService.PreSimulation:Connect(step)
end

return NpcAnimator
