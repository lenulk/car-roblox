--!strict
-- Guide beam: shows an orange ribbon from the player's character to snapshot.guideTarget plus a bouncing arrow.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Client = (script.Parent :: Instance).Parent :: Instance
local ClientState: any = require(Client:WaitForChild("ClientState") :: ModuleScript)
local Theme: any = require(Client:WaitForChild("Theme") :: ModuleScript)

local LocalPlayer = Players.LocalPlayer

local Guide = {}

function Guide.start()
	local C = Theme.colors
	local camera: Instance = Workspace.CurrentCamera or Workspace:WaitForChild("Camera")

	local folder = Instance.new("Folder")
	folder.Name = "GuideClient"
	folder.Parent = camera

	-- invisible anchored part at the target
	local targetPart = Theme.new("Part", {
		Name = "GuideTarget",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Transparency = 1,
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(0, -1000, 0),
	}, folder)
	local targetAttachment = Instance.new("Attachment")
	targetAttachment.Name = "GuideEnd"
	targetAttachment.Parent = targetPart

	-- the beam (texture-free solid ribbon, gently pulsing width)
	local beam = Instance.new("Beam")
	beam.Name = "GuideBeam"
	beam.Color = ColorSequence.new(C.accent)
	beam.Transparency = NumberSequence.new(0.25)
	beam.Width0 = 1
	beam.Width1 = 1
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Segments = 20
	beam.CurveSize0 = 0.5
	beam.CurveSize1 = 0.5
	beam.TextureSpeed = 0
	beam.Attachment1 = targetAttachment
	beam.Enabled = false
	beam.Parent = folder
	TweenService:Create(
		beam,
		TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Width0 = 1.5, Width1 = 1.5 }
	):Play()

	-- the bouncing arrow
	local arrowGui = Theme.new("BillboardGui", {
		Name = "GuideArrow",
		Adornee = targetPart,
		Size = UDim2.fromOffset(80, 80),
		StudsOffset = Vector3.new(0, 3.5, 0),
		AlwaysOnTop = true,
		MaxDistance = math.huge,
		LightInfluence = 0,
		Enabled = false,
	}, targetPart)
	local arrow = Theme.label({
		Name = "Arrow",
		Size = UDim2.fromScale(1, 1),
		Text = "▼",
		TextSize = 64,
		TextColor3 = C.accent,
		TextStrokeColor3 = C.black,
		TextStrokeTransparency = 0.4,
	}, arrowGui)
	arrow.Position = UDim2.fromOffset(0, 0)
	TweenService:Create(
		arrow,
		TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = UDim2.fromOffset(0, -16) }
	):Play()

	local target: Vector3? = nil
	local characterAttachment: Attachment? = nil

	local function refresh()
		local t = target
		if t == nil then
			beam.Enabled = false
			arrowGui.Enabled = false
			return
		end
		targetPart.CFrame = CFrame.new(t + Vector3.new(0, 0.5, 0))
		arrowGui.Enabled = true
		local a = characterAttachment
		if a ~= nil and a.Parent ~= nil then
			beam.Attachment0 = a
			beam.Enabled = true
		else
			beam.Enabled = false
		end
	end

	local function bindCharacter(character: Model)
		characterAttachment = nil
		refresh()
		task.spawn(function()
			local root = character:WaitForChild("HumanoidRootPart", 15)
			if root == nil or LocalPlayer.Character ~= character then
				return
			end
			local existing = root:FindFirstChild("GuideAttachment")
			if existing ~= nil and existing:IsA("Attachment") then
				characterAttachment = existing
			else
				local created = Instance.new("Attachment")
				created.Name = "GuideAttachment"
				created.Parent = root
				characterAttachment = created
			end
			refresh()
		end)
	end

	LocalPlayer.CharacterAdded:Connect(bindCharacter)
	if LocalPlayer.Character then
		bindCharacter(LocalPlayer.Character)
	end

	ClientState.onChanged(function(snapshot: any)
		local guideTarget: any = snapshot.guideTarget
		if typeof(guideTarget) == "Vector3" then
			target = guideTarget
		else
			target = nil
		end
		refresh()
	end)
end

return Guide
