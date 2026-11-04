--!strict
-- Tutorial card: shows steps 1..3 (snapshot.tutorialStep), then a short celebration when the tutorial is done.

local Players = game:GetService("Players")

local Client = (script.Parent :: Instance).Parent :: Instance
local ClientState: any = require(Client:WaitForChild("ClientState") :: ModuleScript)
local Theme: any = require(Client:WaitForChild("Theme") :: ModuleScript)
local Localizer: any = require((script.Parent :: Instance):WaitForChild("Localizer") :: ModuleScript)

local LocalPlayer = Players.LocalPlayer

local Tutorial = {}

local TOTAL_STEPS = 3
local DONE_SECONDS = 4

function Tutorial.start()
	local C = Theme.colors
	local gui, root = Theme.newGui("Tutorial", 4, false)

	local container, body = Theme.panel({
		Name = "Card",
		Size = UDim2.fromOffset(300, 156),
		Radius = 18,
	}, root)

	local title = Theme.label({
		Name = "Title",
		Position = UDim2.fromOffset(14, 10),
		Size = UDim2.new(1, -86, 0, 26),
		TextColor3 = C.accent,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, body)
	Localizer.bind(title, "tutorial_title")

	local indicator = Theme.new("Frame", {
		Name = "Indicator",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 10),
		Size = UDim2.fromOffset(52, 26),
		BackgroundColor3 = C.panelLighter,
	}, body)
	Theme.corner(indicator, 13)
	local indicatorLabel = Theme.label({
		Size = UDim2.fromScale(1, 1),
		TextSize = 16,
		Text = "1/" .. TOTAL_STEPS,
	}, indicator)

	local message = Theme.label({
		Name = "Message",
		Position = UDim2.fromOffset(14, 42),
		Size = UDim2.new(1, -28, 1, -52),
		Font = Theme.fontMedium,
		TextScaled = true,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	}, body)
	local messageLimit = Theme.fitText(message, 11, 18)

	-- hidden while the opening scene (Prologue) plays
	local function syncPrologue()
		container.Visible = LocalPlayer:GetAttribute("InPrologue") ~= true
	end
	LocalPlayer:GetAttributeChangedSignal("InPrologue"):Connect(syncPrologue)
	syncPrologue()

	local finished = false
	local seenActive = false
	local currentStep = 0
	local shown = false
	local compact = false

	local function shownPosition(): UDim2
		if compact then
			return UDim2.fromOffset(12, 78)
		end
		return UDim2.new(0, 12, 0.5, 0)
	end

	local function hiddenPosition(): UDim2
		if compact then
			return UDim2.fromOffset(-300, 78)
		end
		return UDim2.new(0, -330, 0.5, 0)
	end

	local function layout()
		compact = Theme.isCompact()
		if compact then
			container.AnchorPoint = Vector2.new(0, 0)
			container.Size = UDim2.fromOffset(260, 128)
			messageLimit.MaxTextSize = 15
		else
			container.AnchorPoint = Vector2.new(0, 0.5)
			container.Size = UDim2.fromOffset(300, 156)
			messageLimit.MaxTextSize = 18
		end
		container.Position = if shown then shownPosition() else hiddenPosition()
	end
	Theme.onViewport(function()
		layout()
	end)
	container.Position = hiddenPosition()

	local function setStep(step: number)
		indicatorLabel.Text = `{step}/{TOTAL_STEPS}`
		Localizer.bind(message, "tutorial_" .. tostring(step))
		message.TextTransparency = 1
		Theme.tween(message, { TextTransparency = 0 }, 0.3)
	end

	local function show()
		if shown then
			return
		end
		shown = true
		Theme.tween(container, { Position = shownPosition() }, 0.45, Enum.EasingStyle.Back)
	end

	local function hide()
		shown = false
		Theme.tween(container, { Position = hiddenPosition() }, 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end

	local function confetti()
		local colors = { C.accent, C.star, C.money, Color3.fromRGB(90, 170, 255), Color3.fromRGB(255, 120, 170) }
		for _ = 1, 30 do
			local piece = Theme.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.4),
				Size = UDim2.fromOffset(math.random(6, 10), math.random(9, 14)),
				BackgroundColor3 = colors[math.random(1, #colors)],
				Rotation = math.random(0, 360),
				ZIndex = 5,
			}, container)
			local dx = math.random(-170, 170)
			local dy = math.random(-90, 130)
			Theme.tween(
				piece,
				{ Position = UDim2.new(0.5, dx, 0.4, dy), Rotation = math.random(-360, 360) },
				1.3,
				Enum.EasingStyle.Quad
			)
			task.delay(0.9, function()
				Theme.tween(piece, { BackgroundTransparency = 1 }, 0.5)
			end)
			task.delay(1.6, function()
				piece:Destroy()
			end)
		end
	end

	local function celebrate()
		indicatorLabel.Text = "✓"
		Localizer.bind(message, "tutorial_done")
		message.TextTransparency = 1
		Theme.tween(message, { TextTransparency = 0 }, 0.3)
		confetti()
		task.delay(DONE_SECONDS, function()
			hide()
			task.delay(0.5, function()
				gui:Destroy()
			end)
		end)
	end

	ClientState.onChanged(function(snapshot: any)
		if finished then
			return
		end
		local step: any = snapshot.tutorialStep
		if type(step) ~= "number" then
			return
		end
		if step >= 1 and step <= TOTAL_STEPS then
			seenActive = true
			if step ~= currentStep then
				currentStep = step
				setStep(step)
			end
			show()
		elseif step > TOTAL_STEPS then
			finished = true
			if seenActive then
				celebrate()
			else
				-- tutorial was already completed before this session: never show it
				gui:Destroy()
			end
		end
	end)
end

return Tutorial
