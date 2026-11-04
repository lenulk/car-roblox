--!strict
-- Personal-car tuning garage. Opened by the server with OpenUI("Tuning") when the player uses the tuning computer.
-- Shows a premium customization screen with a live 3D preview of the car on the turntable (client-only model,
-- orbit camera), tabs (Cars, Paint, Wheels, Body, Lights, Effects, Performance) and a big DRIVE button.
-- The server answers every purchase with a Notify toast, so no toast is shown here.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes: any = require(Shared:WaitForChild("Remotes") :: ModuleScript)
local Format: any = require(Shared:WaitForChild("Format") :: ModuleScript)
local Layout: any = require(Shared:WaitForChild("Layout") :: ModuleScript)
local CarBuilder: any = require(Shared:WaitForChild("CarBuilder") :: ModuleScript)
local Customization: any = require(Shared:WaitForChild("Config"):WaitForChild("Customization") :: ModuleScript)
local PersonalCars: any = require(Shared:WaitForChild("Config"):WaitForChild("PersonalCars") :: ModuleScript)
local Client = (script.Parent :: Instance).Parent :: Instance
local ClientState: any = require(Client:WaitForChild("ClientState") :: ModuleScript)
local Theme: any = require(Client:WaitForChild("Theme") :: ModuleScript)
local Localizer: any = require((script.Parent :: Instance):WaitForChild("Localizer") :: ModuleScript)

local LocalPlayer = Players.LocalPlayer

local Tuning = {}

----------------------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------------------

local CLOSE_DISTANCE = 30 -- studs from the terminal
local PITCH_MIN = math.rad(5)
local PITCH_MAX = math.rad(40)
local DIST_MIN = 14
local DIST_MAX = 34
local START_YAW = 0.55
local START_PITCH = math.rad(16)
local START_DIST = 22
local TUNING_FOV = 50
local HIDE_GUIS = { "HUD", "Tutorial" }
local RENDER_STEP_NAME = "GarageTuningCamera"
local GREEN = Color3.fromRGB(52, 176, 96)

type Tab = { id: string, icon: string, sections: { string }, fx: boolean? }

-- Icons are plain unicode (escaped) so no asset ids are needed.
local TABS: { Tab } = {
	{ id = "cars", icon = "\u{1F697}", sections = {} },
	{ id = "paint", icon = "\u{1F3A8}", sections = { "paint", "material" } },
	{ id = "wheels", icon = "\u{1F4BF}", sections = { "wheel", "rim", "caliper" } },
	{ id = "body", icon = "\u{1F3CE}", sections = { "spoiler", "kit", "hood", "decal" } },
	{ id = "lights", icon = "\u{1F4A1}", sections = { "headlight", "neon", "tint" } },
	{ id = "effects", icon = "\u{2728}", sections = { "flames", "smoke" }, fx = true },
	{ id = "performance", icon = "\u{26A1}", sections = {} },
}
local TAB_BY_ID: { [string]: Tab } = {}
for _, tab in TABS do
	TAB_BY_ID[tab.id] = tab
end

-- PersonalCars stat key -> localized label key
local STAT_LABEL: { [string]: string } = {
	maxSpeed = "tuning_stat_speed",
	accel = "tuning_stat_accel",
	handling = "tuning_stat_handling",
	braking = "tuning_stat_braking",
	grip = "tuning_stat_grip",
}
-- Normalization caps for the little stat bars on the car cards
local STAT_BAR: { { key: string, cap: number } } = {
	{ key = "maxSpeed", cap = 150 },
	{ key = "accel", cap = 2 },
	{ key = "handling", cap = 1.8 },
}

local function copyTable(source: { [string]: any }): { [string]: any }
	local out: { [string]: any } = {}
	for k, v in source do
		out[k] = v
	end
	return out
end

local function contrastColor(c: Color3): Color3
	local lum = c.R * 0.299 + c.G * 0.587 + c.B * 0.114
	if lum > 0.6 then
		return Color3.fromRGB(20, 24, 34)
	end
	return Color3.new(1, 1, 1)
end

local function formatStat(stat: string, value: number): string
	if stat == "maxSpeed" then
		return tostring(math.floor(value + 0.5))
	end
	return string.format("x%.2f", value)
end

function Tuning.start()
	local C = Theme.colors

	----------------------------------------------------------------------------------------------
	-- State
	----------------------------------------------------------------------------------------------
	local isOpen = false
	local busy = false
	local currentTab = "cars"
	local previewCarId: string = PersonalCars.list[1].id
	local previewCustom: { [string]: string } = {}
	local previewFx = false
	local compactMode = false
	local contentWidth = 380
	local layoutKey = ""
	local lastTabsSig = ""
	local lastContentSig: string? = nil
	local popId: string? = nil

	local plotIndex = 1
	local plotCF = CFrame.new()
	local focusPos = Vector3.zero
	local turntableBase = CFrame.new()
	local terminalPos = Vector3.zero

	-- preview model
	local previewModel: Model? = nil
	local rebuildToken = 0
	local carYaw = 0

	-- camera
	local camYaw, camYawTarget = START_YAW, START_YAW
	local camPitch, camPitchTarget = START_PITCH, START_PITCH
	local camDist, camDistTarget = START_DIST, START_DIST
	local camStartCF: CFrame? = nil
	local camBlend = 1
	local savedCameraType: Enum.CameraType = Enum.CameraType.Custom
	local savedFov = 70
	local dragInput: InputObject? = nil
	local pinching = false
	local pinchStartDist = START_DIST
	local lastInteract = 0

	local hiddenGuis: { { gui: ScreenGui, enabled: boolean } } = {}
	local tabButtons: { [string]: any } = {}
	local pulseTweens: { Tween } = {}

	-- forward declarations
	local render: (resetScroll: boolean?) -> ()
	local close: () -> ()

	----------------------------------------------------------------------------------------------
	-- Snapshot helpers
	----------------------------------------------------------------------------------------------
	local function snap(): any
		return ClientState.snapshot
	end

	local function ownedCars(): any
		local s = snap()
		if s and type(s.cars) == "table" then
			return s.cars
		end
		return {}
	end

	local function hasCar(carId: string): boolean
		return ownedCars()[carId] ~= nil
	end

	local function hasAnyCar(): boolean
		local s = snap()
		return s ~= nil and s.selectedCar ~= nil and next(ownedCars()) ~= nil
	end

	local function serverCustom(carId: string): { [string]: string }
		local out: { [string]: string } = {}
		for k, v in Customization.DEFAULTS do
			out[k] = v
		end
		local car = ownedCars()[carId]
		if car and type(car.custom) == "table" then
			for k, v in car.custom do
				if type(v) == "string" then
					out[k] = v
				end
			end
		end
		return out
	end

	-- everything in the snapshot that the panel content depends on (nil = could not encode -> always render)
	local function contentSignature(): string?
		local s = snap()
		if not s then
			return nil
		end
		local ok, encoded = pcall(function()
			return HttpService:JSONEncode({ s.cars or {}, s.ownedParts or {}, s.selectedCar or "" })
		end)
		return if ok then encoded else nil
	end

	local function resetPreviewCustom()
		previewCustom = serverCustom(previewCarId)
	end

	local function isPartOwned(category: string, optionId: string, price: number): boolean
		if price <= 0 then
			return true
		end
		local s = snap()
		return s ~= nil and type(s.ownedParts) == "table" and s.ownedParts[category .. ":" .. optionId] == true
	end

	----------------------------------------------------------------------------------------------
	-- Preview car (client-only model on the turntable)
	----------------------------------------------------------------------------------------------
	local function applyFx()
		local model = previewModel
		if not model then
			return
		end
		for _, d in model:GetDescendants() do
			if d:IsA("ParticleEmitter") and (d.Name == "Flame" or d.Name == "TireSmoke") then
				d.Enabled = previewFx
			end
		end
	end

	local function destroyPreview()
		rebuildToken += 1
		local model = previewModel
		previewModel = nil
		if model then
			model:Destroy()
		end
	end

	local function buildPreview()
		if not isOpen then
			return
		end
		-- build first: if it fails, keep the previous car on the turntable instead of leaving it empty
		local ok, result = pcall(function()
			return CarBuilder.buildCustom(previewCarId, copyTable(previewCustom))
		end)
		if not ok or typeof(result) ~= "Instance" then
			warn("[Tuning] buildCustom failed: " .. tostring(result))
			return
		end
		local old = previewModel
		previewModel = nil
		if old then
			old:Destroy()
		end
		local model = result :: Model
		model.Name = "TuningPreviewCar"
		model:PivotTo(turntableBase * CFrame.Angles(0, carYaw, 0))
		model.Parent = Workspace.CurrentCamera or Workspace
		previewModel = model
		applyFx()
	end

	local function requestRebuild()
		rebuildToken += 1
		local mine = rebuildToken
		task.delay(0.1, function()
			if mine == rebuildToken and isOpen then
				buildPreview()
			end
		end)
	end

	----------------------------------------------------------------------------------------------
	-- Camera
	----------------------------------------------------------------------------------------------
	local function computeCameraCFrame(): CFrame
		local dir = Vector3.new(
			math.sin(camYaw) * math.cos(camPitch),
			math.sin(camPitch),
			-math.cos(camYaw) * math.cos(camPitch)
		)
		local pos = focusPos + plotCF:VectorToWorldSpace(dir * camDist)
		-- keep the camera inside the annex so walls never block the view
		local annex = Layout.ANNEX
		local lp = plotCF:PointToObjectSpace(pos)
		lp = Vector3.new(
			math.clamp(lp.X, annex.minX + 3, annex.maxX - 3),
			math.clamp(lp.Y, 1.5, annex.height - 1.5),
			math.clamp(lp.Z, annex.minZ + 3, annex.maxZ - 3)
		)
		pos = plotCF:PointToWorldSpace(lp)
		local cf = CFrame.lookAt(pos, focusPos)
		if compactMode then
			-- phones: the bottom sheet covers the lower part of the screen, so lift the car in the frame
			cf = cf * CFrame.new(0, -camDist * 0.11, 0)
		end
		return cf
	end

	local function onRenderStep(dt: number)
		if not isOpen then
			return
		end
		local cam = Workspace.CurrentCamera
		if not cam then
			return
		end
		if cam.CameraType ~= Enum.CameraType.Scriptable then
			cam.CameraType = Enum.CameraType.Scriptable
		end

		local idle = dragInput == nil and not pinching
		if idle and os.clock() - lastInteract > 3 then
			camYawTarget += dt * 0.07
		end
		local a = 1 - math.exp(-dt * 9)
		camYaw += (camYawTarget - camYaw) * a
		camPitch += (camPitchTarget - camPitch) * a
		camDist += (camDistTarget - camDist) * a

		if dragInput == nil then
			carYaw = (carYaw + dt * 0.35) % (math.pi * 2)
		end
		local model = previewModel
		if model then
			model:PivotTo(turntableBase * CFrame.Angles(0, carYaw, 0))
		end

		local target = computeCameraCFrame()
		if camBlend < 1 then
			camBlend = math.min(1, camBlend + dt / 0.9)
			local t = 1 - (1 - camBlend) ^ 3
			local startCF = camStartCF
			if startCF then
				target = startCF:Lerp(target, t)
			end
		end
		cam.CFrame = target
	end

	local function restoreCamera()
		pcall(function()
			RunService:UnbindFromRenderStep(RENDER_STEP_NAME)
		end)
		local cam = Workspace.CurrentCamera
		if cam then
			local char = LocalPlayer.Character
			local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
			if hum then
				cam.CameraSubject = hum
			end
			cam.CameraType = Enum.CameraType.Custom
			cam.FieldOfView = savedFov
		end
	end

	local function hideHud()
		hiddenGuis = {}
		local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
		if not playerGui then
			return
		end
		for _, name in HIDE_GUIS do
			local g = playerGui:FindFirstChild(name)
			if g and g:IsA("ScreenGui") then
				table.insert(hiddenGuis, { gui = g, enabled = g.Enabled })
				g.Enabled = false
			end
		end
	end

	local function restoreHud()
		for _, entry in hiddenGuis do
			if entry.gui.Parent then
				entry.gui.Enabled = entry.enabled
			end
		end
		hiddenGuis = {}
	end

	----------------------------------------------------------------------------------------------
	-- GUI skeleton
	----------------------------------------------------------------------------------------------
	local gui, root = Theme.newGui("Tuning", 6, true)
	gui.Enabled = false

	-- top bar -----------------------------------------------------------------------------------
	local topBar = Theme.new("Frame", {
		Name = "TopBar",
		BackgroundColor3 = C.black,
		BackgroundTransparency = 0,
		Size = UDim2.new(1, 0, 0, 88),
		ZIndex = 1,
	}, root)
	do
		local grad = Instance.new("UIGradient")
		grad.Rotation = 90
		grad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		grad.Parent = topBar
	end

	local titleSub = Theme.label({
		Name = "Subtitle",
		Position = UDim2.fromOffset(20, 10),
		Size = UDim2.fromOffset(300, 18),
		TextSize = 14,
		TextColor3 = C.accent,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
	}, topBar)
	Localizer.bind(titleSub, "tuning_title")

	local carName = Theme.label({
		Name = "CarName",
		Position = UDim2.fromOffset(20, 28),
		Size = UDim2.fromOffset(320, 40),
		TextSize = 32,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = true,
		ZIndex = 3,
	}, topBar)
	Theme.fitText(carName, 16, 32)

	local moneyPill = Theme.new("Frame", {
		Name = "Money",
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.15,
		Size = UDim2.fromOffset(150, 44),
		ZIndex = 3,
	}, topBar)
	Theme.corner(moneyPill, 22)
	Theme.stroke(moneyPill, C.stroke, 1.5, 0.6)
	local moneyLabel = Theme.label({
		Size = UDim2.fromScale(1, 1),
		TextSize = 22,
		TextColor3 = C.money,
		TextScaled = true,
		ZIndex = 4,
	}, moneyPill)
	Theme.fitText(moneyLabel, 12, 24)
	Theme.padding(moneyLabel, 4, 12)

	local driveHolder = Theme.new("Frame", {
		Name = "DriveHolder",
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(190, 56),
		ZIndex = 3,
	}, topBar)
	local driveGlow = Theme.new("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 22, 1, 22),
		BackgroundColor3 = C.accent,
		BackgroundTransparency = 0.6,
		ZIndex = 3,
	}, driveHolder)
	Theme.corner(driveGlow, 26)
	local driveBtn = Theme.button({
		Name = "Drive",
		Size = UDim2.fromScale(1, 1),
		TextSize = 26,
		TextScaled = true,
		ZIndex = 4,
	}, driveHolder)
	Theme.fitText(driveBtn, 14, 28)
	Localizer.bind(driveBtn, "tuning_drive")
	local driveGrad = Instance.new("UIGradient")
	driveGrad.Color = ColorSequence.new(Color3.fromRGB(255, 176, 70), C.accentDark)
	driveGrad.Rotation = 90
	driveGrad.Parent = driveBtn
	local driveStroke = Theme.stroke(driveBtn, Color3.fromRGB(255, 200, 110), 3, 0.1)

	-- TRACK button: drives onto the private race track (only visible once the player owns it)
	local trackBtn = Theme.button({
		Name = "TrackDrive",
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(190, 34),
		TextSize = 20,
		TextScaled = true,
		ZIndex = 4,
		Visible = false,
	}, topBar)
	Theme.fitText(trackBtn, 12, 22)
	Localizer.bind(trackBtn, "tuning_drive_track")
	local trackStroke = Theme.stroke(trackBtn, C.stroke, 2, 0.3)

	local closeBtn = Theme.button({
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(56, 56),
		BackgroundColor3 = C.panelLight,
		Text = "\u{2715}",
		TextSize = 26,
		ZIndex = 3,
	}, topBar)
	Theme.stroke(closeBtn, C.stroke, 1.5, 0.6)

	-- tab rail ----------------------------------------------------------------------------------
	local rail = Theme.new("ScrollingFrame", {
		Name = "Rail",
		BackgroundTransparency = 1,
		ScrollBarThickness = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.XY,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ClipsDescendants = true,
		ZIndex = 2,
	}, root)
	local railList = Theme.list(rail, Enum.FillDirection.Vertical, 8)

	-- content panel (right side / bottom sheet) -------------------------------------------------
	local panelC, panelBody = Theme.panel({
		Name = "Panel",
		Size = UDim2.fromOffset(440, 600),
		ZIndex = 2,
	}, root)
	panelBody.Active = true -- taps on the panel must not rotate the camera

	local scroll = Theme.new("ScrollingFrame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.new(1, -24, 1, -24),
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = C.gray,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 3,
	}, panelBody)
	Theme.list(scroll, Enum.FillDirection.Vertical, 10)
	do
		local pad = Instance.new("UIPadding")
		pad.PaddingRight = UDim.new(0, 6)
		pad.PaddingBottom = UDim.new(0, 8)
		pad.Parent = scroll
	end

	local hint = Theme.label({
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(520, 22),
		TextSize = 16,
		TextColor3 = C.textDim,
		TextTransparency = 0.2,
		ZIndex = 2,
	}, root)
	Localizer.bind(hint, "tuning_hint")

	----------------------------------------------------------------------------------------------
	-- Top bar refresh
	----------------------------------------------------------------------------------------------
	local shownTrack: boolean? = nil

	-- DRIVE alone fills the slot; with the race track owned, DRIVE and TRACK share it (stacked).
	local function layoutDriveButtons()
		local s = snap()
		local hasTrack = s ~= nil and s.hasTrack == true
		shownTrack = hasTrack
		trackBtn.Visible = hasTrack
		local width = if compactMode then 136 else 190
		local right = if compactMode then -(12 + 56 + 14) else -(16 + 56 + 16)
		local top = if compactMode then 8 else 14
		local fullHeight = 56
		if hasTrack then
			local barHeight = if compactMode then 72 else 88
			local height = if compactMode then 32 else 38
			local gap = barHeight - 2 * height - 8
			driveHolder.Size = UDim2.fromOffset(width, height)
			driveHolder.Position = UDim2.new(1, right, 0, 4 + math.max(gap, 0) / 2)
			trackBtn.Size = UDim2.fromOffset(width, height)
			trackBtn.Position = UDim2.new(1, right, 0, 4 + math.max(gap, 0) / 2 + height + 4)
		else
			driveHolder.Size = UDim2.fromOffset(width, fullHeight)
			driveHolder.Position = UDim2.new(1, right, 0, top)
		end
	end

	local function updateTopBar()
		local s = snap()
		moneyLabel.Text = Format.money(if s and type(s.money) == "number" then s.money else 0)
		Localizer.bind(carName, "car_" .. previewCarId)
		if shownTrack ~= (s ~= nil and s.hasTrack == true) then
			layoutDriveButtons()
		end
		-- DRIVE drives the car on the turntable, so it is off while previewing a car the player doesn't own
		local enabled = hasAnyCar() and hasCar(previewCarId) and not busy
		driveBtn.AutoButtonColor = enabled
		driveBtn.TextColor3 = if enabled then C.text else C.textDim
		driveGlow.Visible = enabled
		driveGrad.Enabled = enabled
		driveBtn.BackgroundColor3 = if enabled then C.accent else C.gray
		driveStroke.Enabled = enabled
		trackBtn.AutoButtonColor = enabled
		trackBtn.TextColor3 = if enabled then C.text else C.textDim
		trackBtn.BackgroundColor3 = if enabled then C.accentDark else C.gray
		trackStroke.Enabled = enabled
	end

	----------------------------------------------------------------------------------------------
	-- Server calls
	----------------------------------------------------------------------------------------------
	local function callServer(name: string, ...: any): boolean
		if busy then
			return false
		end
		busy = true
		render()
		local args = table.pack(...)
		local ok, result = pcall(function()
			local remote: any = Remotes.get(name)
			return remote:InvokeServer(table.unpack(args, 1, args.n))
		end)
		busy = false
		if not ok then
			warn("[Tuning] " .. name .. " failed: " .. tostring(result))
		end
		if isOpen then
			render()
		end
		return ok and result == true
	end

	local function setPreviewOption(category: string, optionId: string)
		if previewCustom[category] == optionId then
			return
		end
		previewCustom[category] = optionId
		popId = category .. ":" .. optionId
		requestRebuild()
		render()
	end

	local function setPreviewCar(carId: string)
		if previewCarId == carId then
			return
		end
		previewCarId = carId
		resetPreviewCustom()
		requestRebuild()
		render(true)
	end

	----------------------------------------------------------------------------------------------
	-- Content builders
	----------------------------------------------------------------------------------------------
	local function cellWidthFor(minWidth: number, gap: number): number
		local cols = math.max(1, math.floor((contentWidth + gap) / (minWidth + gap)))
		return math.floor((contentWidth - gap * (cols - 1)) / cols)
	end

	local function newGrid(cellW: number, cellH: number, gap: number, order: number): any
		local grid = Theme.new("Frame", {
			Name = "Grid",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order,
			ZIndex = 3,
		}, scroll)
		local layout = Instance.new("UIGridLayout")
		layout.CellSize = UDim2.fromOffset(cellW, cellH)
		layout.CellPadding = UDim2.fromOffset(gap, gap)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		layout.Parent = grid
		return grid
	end

	local function sectionHeader(key: string, order: number)
		local holder = Theme.new("Frame", {
			Name = "Header",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 34),
			LayoutOrder = order,
			ZIndex = 3,
		}, scroll)
		local bar = Theme.new("Frame", {
			BackgroundColor3 = C.accent,
			Position = UDim2.fromOffset(0, 6),
			Size = UDim2.fromOffset(4, 22),
			ZIndex = 4,
		}, holder)
		Theme.corner(bar, 2)
		local lbl = Theme.label({
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.new(1, -14, 1, 0),
			TextSize = 20,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextScaled = true,
			ZIndex = 4,
		}, holder)
		Theme.fitText(lbl, 12, 20)
		Localizer.bind(lbl, key)
	end

	local function popIn(inst: GuiObject)
		local s = Instance.new("UIScale")
		s.Scale = 0.82
		s.Parent = inst
		Theme.tween(s, { Scale = 1 }, 0.3, Enum.EasingStyle.Back)
	end

	-- Round color swatch with a check mark when selected.
	local function buildSwatch(grid: any, cat: any, option: any, order: number)
		local optionId: string = option.id
		local price: number = option.price or 0
		local selected = previewCustom[cat.id] == optionId
		local equipped = hasCar(previewCarId) and serverCustom(previewCarId)[cat.id] == optionId
		local owned = isPartOwned(cat.id, optionId, price)
		local isNone = optionId == "None"
		local color: Color3 = if isNone then C.panelLighter else Customization.hexToColor(optionId)

		local cell = Theme.new("Frame", {
			Name = "Swatch_" .. optionId,
			BackgroundTransparency = 1,
			LayoutOrder = order,
			ZIndex = 4,
		}, grid)
		local btn = Theme.new("TextButton", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 4),
			Size = UDim2.fromOffset(56, 56),
			BackgroundColor3 = color,
			Text = "",
			AutoButtonColor = false,
			ZIndex = 5,
		}, cell)
		Theme.corner(btn, 28)
		if selected then
			Theme.stroke(btn, C.accent, 4, 0)
		else
			Theme.stroke(btn, C.text, 1.5, 0.7)
		end
		if selected or isNone then
			local mark = Theme.label({
				Size = UDim2.fromScale(1, 1),
				Text = if selected then "\u{2713}" else "\u{2715}",
				TextSize = if selected then 32 else 22,
				TextColor3 = if selected then contrastColor(color) else C.textDim,
				ZIndex = 6,
			}, btn)
			mark.Name = "Mark"
		end
		if equipped then
			local dot = Theme.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(1, -6, 0, 6),
				Size = UDim2.fromOffset(14, 14),
				BackgroundColor3 = C.money,
				ZIndex = 7,
			}, btn)
			Theme.corner(dot, 7)
			Theme.stroke(dot, C.panel, 2, 0)
		end

		local sub = Theme.label({
			Position = UDim2.fromOffset(0, 64),
			Size = UDim2.new(1, 0, 0, 18),
			TextSize = 14,
			TextScaled = true,
			ZIndex = 5,
		}, cell)
		Theme.fitText(sub, 10, 14)
		if isNone then
			sub.TextColor3 = C.textDim
			Localizer.bind(sub, "tuning_opt_" .. cat.id .. "_None")
		elseif not owned then
			sub.TextColor3 = C.money
			sub.Text = Format.money(price)
		end

		if popId == cat.id .. ":" .. optionId then
			popIn(btn)
		end
		btn.Activated:Connect(function()
			setPreviewOption(cat.id, optionId)
		end)
	end

	-- Choice card with option name and price / owned badge.
	local function buildChoice(grid: any, cat: any, option: any, order: number)
		local optionId: string = option.id
		local price: number = option.price or 0
		local selected = previewCustom[cat.id] == optionId
		local equipped = hasCar(previewCarId) and serverCustom(previewCarId)[cat.id] == optionId
		local owned = isPartOwned(cat.id, optionId, price)

		local card = Theme.new("TextButton", {
			Name = "Choice_" .. optionId,
			BackgroundColor3 = if selected then C.panelLighter else C.panelLight,
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = order,
			ZIndex = 4,
		}, grid)
		Theme.corner(card, 14)
		if selected then
			Theme.stroke(card, C.accent, 3, 0)
		else
			Theme.stroke(card, C.stroke, 1.5, 0.75)
		end
		local name = Theme.label({
			Position = UDim2.fromOffset(12, 10),
			Size = UDim2.new(1, -24, 0, 32),
			TextSize = 20,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 5,
		}, card)
		Theme.fitText(name, 12, 20)
		Localizer.bind(name, "tuning_opt_" .. cat.id .. "_" .. optionId)

		local badge = Theme.label({
			Position = UDim2.fromOffset(12, 52),
			Size = UDim2.new(1, -24, 0, 24),
			TextSize = 17,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 5,
		}, card)
		Theme.fitText(badge, 11, 17)
		if equipped then
			badge.TextColor3 = C.money
			Localizer.bind(badge, "tuning_equipped")
		elseif owned then
			badge.TextColor3 = C.textDim
			Localizer.bind(badge, "tuning_owned")
		else
			badge.TextColor3 = C.money
			badge.Text = Format.money(price)
		end

		if popId == cat.id .. ":" .. optionId then
			popIn(card)
		end
		card.Activated:Connect(function()
			setPreviewOption(cat.id, optionId)
		end)
	end

	-- Equipped / Install / Buy button under a category grid.
	local function buildAction(cat: any, order: number)
		local want: string = previewCustom[cat.id]
		local price: number = Customization.price(cat.id, want) or 0
		local carId = previewCarId
		local btn = Theme.button({
			Name = "Action_" .. cat.id,
			Size = UDim2.new(1, 0, 0, 56),
			LayoutOrder = order,
			TextSize = 22,
			TextScaled = true,
			ZIndex = 4,
		}, scroll)
		Theme.fitText(btn, 12, 22)

		local enabled = true
		local color: Color3 = C.accent
		if not hasCar(carId) then
			enabled = false
			Localizer.bind(btn, "notify_need_car")
		elseif serverCustom(carId)[cat.id] == want then
			enabled = false
			Localizer.bind(btn, "tuning_equipped")
		elseif isPartOwned(cat.id, want, price) then
			color = GREEN
			Localizer.bind(btn, "tuning_install")
		else
			Localizer.bind(btn, "tuning_buy", Format.money(price))
		end
		if busy then
			enabled = false
		end
		btn.AutoButtonColor = enabled
		btn.BackgroundColor3 = if enabled then color else C.gray
		btn.TextColor3 = if enabled then C.text else C.textDim
		btn.Activated:Connect(function()
			if enabled and not busy then
				callServer("Customize", carId, cat.id, want)
			end
		end)
	end

	local function spacer(height: number, order: number)
		Theme.new("Frame", {
			Name = "Spacer",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, height),
			LayoutOrder = order,
		}, scroll)
	end

	local function buildCategory(cat: any, nextOrder: () -> number)
		sectionHeader("tuning_cat_" .. cat.id, nextOrder())
		local grid
		if cat.kind == "color" then
			grid = newGrid(64, 86, 8, nextOrder())
		else
			grid = newGrid(cellWidthFor(170, 10), 88, 10, nextOrder())
		end
		for i, option in cat.options do
			if cat.kind == "color" then
				buildSwatch(grid, cat, option, i)
			else
				buildChoice(grid, cat, option, i)
			end
		end
		buildAction(cat, nextOrder())
		spacer(6, nextOrder())
	end

	-- Switch row that toggles the Flame / TireSmoke emitters on the preview car.
	local function buildFxToggle(order: number)
		local row = Theme.new("TextButton", {
			Name = "FxToggle",
			BackgroundColor3 = C.panelLight,
			Size = UDim2.new(1, 0, 0, 64),
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = order,
			ZIndex = 4,
		}, scroll)
		Theme.corner(row, 14)
		Theme.stroke(row, if previewFx then C.accent else C.stroke, if previewFx then 2.5 else 1.5, if previewFx then 0 else 0.75)
		local lbl = Theme.label({
			Position = UDim2.fromOffset(16, 0),
			Size = UDim2.new(1, -110, 1, 0),
			TextSize = 20,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 5,
		}, row)
		Theme.fitText(lbl, 12, 20)
		Localizer.bind(lbl, "tuning_preview_fx")
		local track = Theme.new("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -16, 0.5, 0),
			Size = UDim2.fromOffset(64, 32),
			BackgroundColor3 = if previewFx then C.accent else C.gray,
			ZIndex = 5,
		}, row)
		Theme.corner(track, 16)
		local knob = Theme.new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = if previewFx then UDim2.new(1, -30, 0.5, 0) else UDim2.new(0, 4, 0.5, 0),
			Size = UDim2.fromOffset(26, 26),
			BackgroundColor3 = C.text,
			ZIndex = 6,
		}, track)
		Theme.corner(knob, 13)
		row.Activated:Connect(function()
			previewFx = not previewFx
			applyFx()
			render()
		end)
	end

	-- Cars tab ------------------------------------------------------------------------------------
	local function buildCarCard(grid: any, entry: any, order: number, cellW: number)
		local id: string = entry.id
		local owned = hasCar(id)
		local s = snap()
		local isSelectedServer = s ~= nil and s.selectedCar == id
		local isPreview = previewCarId == id
		local price: number = entry.price or 0

		local card = Theme.new("TextButton", {
			Name = "CarCard_" .. id,
			BackgroundColor3 = if isPreview then C.panelLighter else C.panelLight,
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = order,
			ZIndex = 4,
		}, grid)
		Theme.corner(card, 16)
		if isPreview then
			Theme.stroke(card, C.accent, 3, 0)
		else
			Theme.stroke(card, C.stroke, 1.5, 0.75)
		end

		local name = Theme.label({
			Position = UDim2.fromOffset(14, 10),
			Size = UDim2.new(1, -28, 0, 30),
			TextSize = 24,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 5,
		}, card)
		Theme.fitText(name, 14, 24)
		Localizer.bind(name, "car_" .. id)

		local status = Theme.label({
			Position = UDim2.fromOffset(14, 40),
			Size = UDim2.new(1, -28, 0, 22),
			TextSize = 18,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 5,
		}, card)
		Theme.fitText(status, 11, 18)
		if isSelectedServer then
			status.TextColor3 = C.star
			Localizer.bind(status, "tuning_selected")
		elseif owned then
			status.TextColor3 = C.textDim
			Localizer.bind(status, "tuning_owned")
		else
			status.TextColor3 = C.money
			status.Text = Format.money(price)
		end

		-- stat bars
		local car = ownedCars()[id]
		local stats: { [string]: number } =
			PersonalCars.statsFor(id, if car and type(car.upgrades) == "table" then car.upgrades else nil)
		for i, bar in STAT_BAR do
			local y = 68 + (i - 1) * 20
			local lbl = Theme.label({
				Position = UDim2.fromOffset(14, y),
				Size = UDim2.fromOffset(84, 16),
				TextSize = 14,
				TextScaled = true,
				TextColor3 = C.textDim,
				Font = Theme.fontMedium,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 5,
			}, card)
			Theme.fitText(lbl, 9, 14)
			Localizer.bind(lbl, STAT_LABEL[bar.key])
			local track = Theme.new("Frame", {
				Position = UDim2.fromOffset(104, y + 4),
				Size = UDim2.fromOffset(math.max(20, cellW - 104 - 16), 8),
				BackgroundColor3 = C.starDim,
				ZIndex = 5,
			}, card)
			Theme.corner(track, 4)
			local fraction = math.clamp((stats[bar.key] or 0) / bar.cap, 0.04, 1)
			local fill = Theme.new("Frame", {
				Size = UDim2.fromScale(fraction, 1),
				BackgroundColor3 = C.accent,
				ZIndex = 6,
			}, track)
			Theme.corner(fill, 4)
		end

		-- buy / select
		local btn = Theme.button({
			Name = "CarAction",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 14, 1, -12),
			Size = UDim2.new(1, -28, 0, 56),
			TextSize = 22,
			TextScaled = true,
			ZIndex = 6,
		}, card)
		Theme.fitText(btn, 12, 22)
		local enabled = true
		local color: Color3 = C.accent
		if not owned then
			if price > 0 then
				Localizer.bind(btn, "tuning_buy", Format.money(price))
			else
				Localizer.bind(btn, "tuning_get")
			end
		elseif isSelectedServer then
			enabled = false
			Localizer.bind(btn, "tuning_selected")
		else
			color = GREEN
			Localizer.bind(btn, "tuning_select")
		end
		if busy then
			enabled = false
		end
		btn.AutoButtonColor = enabled
		btn.BackgroundColor3 = if enabled then color else C.gray
		btn.TextColor3 = if enabled then C.text else C.textDim
		btn.Activated:Connect(function()
			if not enabled or busy then
				return
			end
			-- The preview car is the one DRIVE launches, so it follows a successful buy / select.
			local done = if owned then callServer("SelectCar", id) else callServer("BuyCar", id)
			if done and isOpen then
				setPreviewCar(id)
			end
		end)

		card.Activated:Connect(function()
			setPreviewCar(id)
		end)
	end

	local function buildCarsTab(nextOrder: () -> number)
		if not hasAnyCar() then
			local note = Theme.label({
				Name = "NoCar",
				Size = UDim2.new(1, 0, 0, 44),
				TextSize = 18,
				TextScaled = true,
				TextWrapped = true,
				TextColor3 = C.star,
				LayoutOrder = nextOrder(),
				ZIndex = 4,
			}, scroll)
			Theme.fitText(note, 12, 18)
			Localizer.bind(note, "tuning_no_car")
		end
		local cellW = cellWidthFor(330, 12)
		local grid = newGrid(cellW, 196, 12, nextOrder())
		for i, entry in PersonalCars.list do
			buildCarCard(grid, entry, i, cellW)
		end
	end

	-- Performance tab -----------------------------------------------------------------------------
	local function buildUpgradeRow(part: string, order: number, carId: string)
		local car = ownedCars()[carId]
		local owned = car ~= nil
		local upgrades: { [string]: number } = {}
		if car and type(car.upgrades) == "table" then
			for k, v in car.upgrades do
				if type(v) == "number" then
					upgrades[k] = v
				end
			end
		end
		local level: number = math.clamp(upgrades[part] or 1, 1, PersonalCars.MAX_LEVEL)
		local maxLevel: number = PersonalCars.MAX_LEVEL
		local up: any = PersonalCars.UPGRADES[part]
		local statKey: string = up.stat

		local nowStats = PersonalCars.statsFor(carId, upgrades)
		local nowText = formatStat(statKey, nowStats[statKey])
		local statText = nowText
		if level < maxLevel then
			local nextUpgrades = copyTable(upgrades)
			nextUpgrades[part] = level + 1
			local nextStats = PersonalCars.statsFor(carId, nextUpgrades)
			statText = nowText .. "  \u{2192}  " .. formatStat(statKey, nextStats[statKey])
		end

		local row = Theme.new("Frame", {
			Name = "Upgrade_" .. part,
			BackgroundColor3 = C.panelLight,
			Size = UDim2.new(1, 0, 0, 144),
			LayoutOrder = order,
			ZIndex = 4,
		}, scroll)
		Theme.corner(row, 16)
		Theme.stroke(row, C.stroke, 1.5, 0.75)

		local name = Theme.label({
			Position = UDim2.fromOffset(14, 10),
			Size = UDim2.new(1, -170, 0, 28),
			TextSize = 22,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 5,
		}, row)
		Theme.fitText(name, 12, 22)
		Localizer.bind(name, "carpart_" .. part)

		-- level pips 1..5
		local pips = Theme.new("Frame", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 19),
			Size = UDim2.fromOffset(maxLevel * 26 - 4, 10),
			BackgroundTransparency = 1,
			ZIndex = 5,
		}, row)
		for i = 1, maxLevel do
			local pip = Theme.new("Frame", {
				Position = UDim2.fromOffset((i - 1) * 26, 0),
				Size = UDim2.fromOffset(22, 10),
				BackgroundColor3 = if i <= level then C.accent else C.starDim,
				ZIndex = 6,
			}, pips)
			Theme.corner(pip, 5)
		end

		local statName = Theme.label({
			Position = UDim2.fromOffset(14, 46),
			Size = UDim2.new(0.4, -14, 0, 22),
			TextSize = 17,
			TextScaled = true,
			TextColor3 = C.textDim,
			Font = Theme.fontMedium,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 5,
		}, row)
		Theme.fitText(statName, 10, 17)
		Localizer.bind(statName, STAT_LABEL[statKey] or "tuning_stat_speed")
		local statValue = Theme.label({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 46),
			Size = UDim2.new(0.6, -14, 0, 22),
			TextSize = 18,
			TextScaled = true,
			TextColor3 = C.text,
			Text = statText,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 5,
		}, row)
		Theme.fitText(statValue, 10, 18)

		local btn = Theme.button({
			Name = "UpgradeButton",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 14, 1, -12),
			Size = UDim2.new(1, -28, 0, 56),
			TextSize = 22,
			TextScaled = true,
			ZIndex = 5,
		}, row)
		Theme.fitText(btn, 12, 22)
		local cost: number? = PersonalCars.upgradeCost(PersonalCars.byId[carId].price, level)
		local enabled = owned
		if cost == nil then
			enabled = false
			Localizer.bind(btn, "tuning_max")
		else
			Localizer.bind(btn, "tuning_upgrade", Format.money(cost))
		end
		if busy then
			enabled = false
		end
		btn.AutoButtonColor = enabled
		btn.BackgroundColor3 = if enabled then C.accent else C.gray
		btn.TextColor3 = if enabled then C.text else C.textDim
		btn.Activated:Connect(function()
			if enabled and not busy then
				callServer("UpgradeCar", carId, part)
			end
		end)
	end

	local function buildPerformanceTab(nextOrder: () -> number)
		sectionHeader("tuning_cat_performance", nextOrder())
		if not hasCar(previewCarId) then
			local note = Theme.label({
				Name = "NeedCar",
				Size = UDim2.new(1, 0, 0, 40),
				TextSize = 18,
				TextScaled = true,
				TextWrapped = true,
				TextColor3 = C.star,
				LayoutOrder = nextOrder(),
				ZIndex = 4,
			}, scroll)
			Theme.fitText(note, 12, 18)
			Localizer.bind(note, "notify_need_car")
		end
		for _, part in PersonalCars.UPGRADE_ORDER do
			buildUpgradeRow(part, nextOrder(), previewCarId)
		end
	end

	local function buildContent()
		if not snap() then
			return
		end
		local order = 0
		local function nextOrder(): number
			order += 1
			return order
		end
		if currentTab == "cars" then
			buildCarsTab(nextOrder)
		elseif currentTab == "performance" then
			buildPerformanceTab(nextOrder)
		else
			local tab = TAB_BY_ID[currentTab]
			if not tab then
				return
			end
			if tab.fx then
				buildFxToggle(nextOrder())
			end
			for _, catId in tab.sections do
				local cat = Customization.byId[catId]
				if cat then
					buildCategory(cat, nextOrder)
				end
			end
		end
	end

	render = function(resetScroll: boolean?)
		lastContentSig = contentSignature()
		local saved = scroll.CanvasPosition
		for _, child in scroll:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local ok, err = pcall(buildContent)
		if not ok then
			warn("[Tuning] render failed: " .. tostring(err))
		end
		popId = nil
		updateTopBar()
		if resetScroll then
			scroll.CanvasPosition = Vector2.zero
		else
			scroll.CanvasPosition = saved
			local conn: RBXScriptConnection? = nil
			conn = scroll:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(function()
				scroll.CanvasPosition = saved
				if conn then
					conn:Disconnect()
				end
			end)
			task.delay(0.3, function()
				if conn then
					conn:Disconnect()
				end
			end)
		end
	end

	----------------------------------------------------------------------------------------------
	-- Tabs
	----------------------------------------------------------------------------------------------
	local function availableTabs(): { Tab }
		if hasAnyCar() then
			return TABS
		end
		return { TABS[1] }
	end

	local function tabsSignature(): string
		local ids: { string } = {}
		for _, tab in availableTabs() do
			table.insert(ids, tab.id)
		end
		return table.concat(ids, ",") .. (if compactMode then "|c" else "|d")
	end

	local function refreshTabStyles()
		for id, button in tabButtons do
			local selected = id == currentTab
			Theme.tween(button, { BackgroundColor3 = if selected then C.accent else C.panelLight }, 0.15)
			button.BackgroundTransparency = if selected then 0 else 0.1
			local stroke = button:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Transparency = if selected then 1 else 0.75
			end
		end
	end

	local function buildTabs()
		for _, child in rail:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		tabButtons = {}
		lastTabsSig = tabsSignature()

		local tabs = availableTabs()
		local found = false
		for _, tab in tabs do
			if tab.id == currentTab then
				found = true
			end
		end
		if not found then
			currentTab = "cars"
		end

		for index, tab in tabs do
			local button = Theme.new("TextButton", {
				Name = "Tab_" .. tab.id,
				BackgroundColor3 = C.panelLight,
				Text = "",
				AutoButtonColor = false,
				Size = if compactMode then UDim2.fromOffset(150, 56) else UDim2.fromOffset(96, 84),
				LayoutOrder = index,
				ZIndex = 3,
			}, rail)
			Theme.corner(button, 14)
			Theme.stroke(button, C.stroke, 1.5, 0.75)
			local icon = Theme.label({
				Name = "Icon",
				Position = if compactMode then UDim2.fromOffset(8, 0) else UDim2.fromOffset(0, 6),
				Size = if compactMode then UDim2.new(0, 38, 1, 0) else UDim2.new(1, 0, 0, 42),
				Text = tab.icon,
				TextSize = if compactMode then 26 else 32,
				ZIndex = 4,
			}, button)
			icon.Name = "Icon"
			local label = Theme.label({
				Name = "Label",
				Position = if compactMode then UDim2.fromOffset(48, 0) else UDim2.fromOffset(4, 50),
				Size = if compactMode then UDim2.new(1, -54, 1, 0) else UDim2.new(1, -8, 0, 28),
				TextSize = 16,
				TextScaled = true,
				TextXAlignment = if compactMode then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
				ZIndex = 4,
			}, button)
			Theme.fitText(label, 9, 16)
			Localizer.bind(label, "tuning_tab_" .. tab.id)
			tabButtons[tab.id] = button
			button.Activated:Connect(function()
				if currentTab == tab.id then
					return
				end
				currentTab = tab.id
				refreshTabStyles()
				render(true)
			end)
		end
		refreshTabStyles()
	end

	----------------------------------------------------------------------------------------------
	-- Layout (desktop side panels / phone bottom sheet)
	----------------------------------------------------------------------------------------------
	local function applyLayout(): boolean
		local vp = Theme.viewportSize()
		local s: number = Theme.scaleFor(vp)
		local W = vp.X / s
		local H = vp.Y / s
		local compact: boolean = Theme.isCompact()
		compactMode = compact

		topBar.Position = UDim2.new()
		if compact then
			local topH = 72
			topBar.Size = UDim2.new(1, 0, 0, topH)
			closeBtn.Position = UDim2.new(1, -12, 0, 8)
			driveHolder.Size = UDim2.fromOffset(136, 56)
			driveHolder.Position = UDim2.new(1, -(12 + 56 + 14), 0, 8)
			moneyPill.Size = UDim2.fromOffset(130, 44)
			moneyPill.Position = UDim2.new(1, -(12 + 56 + 14 + 136 + 12), 0, 14)
			titleSub.Position = UDim2.fromOffset(14, 8)
			carName.Position = UDim2.fromOffset(14, 26)
			carName.Size = UDim2.fromOffset(math.max(120, math.min(260, W - 12 - 56 - 14 - 136 - 12 - 130 - 24)), 36)

			rail.AnchorPoint = Vector2.new(0, 0)
			rail.Position = UDim2.fromOffset(12, topH + 4)
			rail.Size = UDim2.fromOffset(W - 24, 60)
			rail.ScrollingDirection = Enum.ScrollingDirection.X
			rail.ScrollBarThickness = 0
			railList.FillDirection = Enum.FillDirection.Horizontal

			local sheetW = math.min(W - 24, 900)
			local sheetH = math.clamp(H * 0.42, 210, 330)
			panelC.AnchorPoint = Vector2.new(0.5, 1)
			panelC.Position = UDim2.new(0.5, 0, 1, -8)
			panelC.Size = UDim2.fromOffset(sheetW, sheetH)
			contentWidth = sheetW - 24 - 6 - 6
			hint.Visible = false
		else
			local topH = 88
			topBar.Size = UDim2.new(1, 0, 0, topH)
			closeBtn.Position = UDim2.new(1, -16, 0, 14)
			driveHolder.Size = UDim2.fromOffset(190, 56)
			driveHolder.Position = UDim2.new(1, -(16 + 56 + 16), 0, 14)
			moneyPill.Size = UDim2.fromOffset(160, 44)
			moneyPill.Position = UDim2.new(1, -(16 + 56 + 16 + 190 + 16), 0, 20)
			titleSub.Position = UDim2.fromOffset(20, 10)
			carName.Position = UDim2.fromOffset(20, 28)
			carName.Size = UDim2.fromOffset(320, 40)

			rail.AnchorPoint = Vector2.new(0, 0)
			rail.Position = UDim2.fromOffset(16, topH + 8)
			rail.Size = UDim2.fromOffset(96, math.max(200, H - topH - 28))
			rail.ScrollingDirection = Enum.ScrollingDirection.Y
			rail.ScrollBarThickness = 0
			railList.FillDirection = Enum.FillDirection.Vertical

			local panelW = math.min(440, math.max(300, W - 16 - 96 - 16 - 16 - 200))
			panelC.AnchorPoint = Vector2.new(1, 0)
			panelC.Position = UDim2.new(1, -16, 0, topH + 8)
			panelC.Size = UDim2.fromOffset(panelW, math.max(240, H - topH - 28))
			contentWidth = panelW - 24 - 6 - 6
			hint.Visible = true
		end

		layoutDriveButtons()

		local key = (if compact then "c" else "d") .. tostring(math.floor(contentWidth))
		local changed = key ~= layoutKey
		layoutKey = key
		return changed
	end

	Theme.onViewport(function()
		local changed = applyLayout()
		if changed and isOpen then
			buildTabs()
			render()
		end
	end)

	local function slideIn(obj: GuiObject, dx: number, dy: number)
		local target = obj.Position
		obj.Position = target + UDim2.fromOffset(dx, dy)
		Theme.tween(obj, { Position = target }, 0.5, Enum.EasingStyle.Quint)
	end

	----------------------------------------------------------------------------------------------
	-- Open / close
	----------------------------------------------------------------------------------------------
	local function startPulse()
		for _, t in pulseTweens do
			t:Cancel()
		end
		pulseTweens = {}
		local info = TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		driveStroke.Transparency = 0.05
		driveGlow.BackgroundTransparency = 0.55
		local t1 = TweenService:Create(driveStroke, info, { Transparency = 0.75 })
		local t2 = TweenService:Create(driveGlow, info, { BackgroundTransparency = 0.9 })
		t1:Play()
		t2:Play()
		table.insert(pulseTweens, t1)
		table.insert(pulseTweens, t2)
	end

	local function stopPulse()
		for _, t in pulseTweens do
			t:Cancel()
		end
		pulseTweens = {}
	end

	close = function()
		if not isOpen then
			return
		end
		isOpen = false
		LocalPlayer:SetAttribute("TuningOpen", false)
		dragInput = nil
		pinching = false
		restoreCamera()
		destroyPreview()
		restoreHud()
		stopPulse()
		gui.Enabled = false
		resetPreviewCustom() -- "On close, previewCustom resets to the server state"
		previewFx = false
	end

	local function open()
		if isOpen then
			return
		end
		local s = snap()
		if not s or type(s.plotIndex) ~= "number" then
			return
		end
		local cam = Workspace.CurrentCamera
		local char = LocalPlayer.Character
		local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
		if not cam or not hum or hum.Health <= 0 then
			return
		end

		plotIndex = s.plotIndex
		plotCF = Layout.plotCFrame(plotIndex)
		focusPos = Layout.toWorld(plotIndex, CFrame.new(Layout.TUNING.cameraFocus)).Position
		turntableBase = Layout.toWorld(plotIndex, Layout.TUNING.turntable) * CFrame.new(0, 0.6, 0)
		terminalPos = Layout.toWorld(plotIndex, CFrame.new(Layout.TUNING.terminal)).Position

		local selected = s.selectedCar
		if type(selected) == "string" and PersonalCars.byId[selected] then
			previewCarId = selected
		else
			previewCarId = PersonalCars.list[1].id
		end
		resetPreviewCustom()
		previewFx = false
		busy = false
		currentTab = if hasAnyCar() then "paint" else "cars"

		-- camera
		savedCameraType = cam.CameraType
		savedFov = cam.FieldOfView
		camStartCF = cam.CFrame
		camBlend = 0
		camYaw, camYawTarget = START_YAW, START_YAW
		camPitch, camPitchTarget = START_PITCH, START_PITCH
		camDist, camDistTarget = START_DIST, START_DIST
		carYaw = 0
		lastInteract = os.clock()
		dragInput = nil
		pinching = false

		isOpen = true
		LocalPlayer:SetAttribute("TuningOpen", true)
		cam.CameraType = Enum.CameraType.Scriptable
		cam.FieldOfView = TUNING_FOV
		pcall(function()
			RunService:UnbindFromRenderStep(RENDER_STEP_NAME)
		end)
		RunService:BindToRenderStep(RENDER_STEP_NAME, Enum.RenderPriority.Camera.Value + 1, onRenderStep)

		hideHud()
		gui.Enabled = true

		local ok, err = pcall(function()
			applyLayout()
			buildTabs()
			render(true)
			startPulse()
			if compactMode then
				slideIn(topBar, 0, -90)
				slideIn(rail, 0, -90)
				slideIn(panelC, 0, 420)
			else
				slideIn(topBar, 0, -100)
				slideIn(rail, -140, 0)
				slideIn(panelC, 500, 0)
			end
		end)
		if not ok then
			warn("[Tuning] open failed: " .. tostring(err))
		end
		buildPreview()
	end

	----------------------------------------------------------------------------------------------
	-- Buttons
	----------------------------------------------------------------------------------------------
	closeBtn.Activated:Connect(function()
		close()
	end)

	-- Shared by DRIVE (mode nil: connector road) and TRACK (mode "track": private race track).
	local function startDrive(mode: string?)
		if busy or not isOpen or not hasAnyCar() or not hasCar(previewCarId) then
			return
		end
		local carId = previewCarId
		-- install previewed parts that are already owned / free, so the player drives what they see
		-- (parts that still cost money are never bought implicitly)
		local saved = serverCustom(carId)
		for category, want in previewCustom do
			if saved[category] ~= want and isPartOwned(category, want, Customization.price(category, want) or 0) then
				callServer("Customize", carId, category, want)
				if not isOpen then
					return
				end
			end
		end
		local ok = if mode then callServer("DriveCar", carId, mode) else callServer("DriveCar", carId)
		if ok and isOpen then
			close()
		end
	end

	driveBtn.Activated:Connect(function()
		startDrive(nil)
	end)

	trackBtn.Activated:Connect(function()
		startDrive("track")
	end)

	----------------------------------------------------------------------------------------------
	-- Input: drag to orbit, wheel / pinch to zoom
	----------------------------------------------------------------------------------------------
	local function rotateBy(delta: Vector3)
		camYawTarget -= delta.X * 0.008
		camPitchTarget = math.clamp(camPitchTarget + delta.Y * 0.005, PITCH_MIN, PITCH_MAX)
		lastInteract = os.clock()
	end

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not isOpen or processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if dragInput == nil then
				dragInput = input
				lastInteract = os.clock()
			end
		end
	end)

	UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
		if not isOpen then
			return
		end
		local drag = dragInput
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			if not processed then
				camDistTarget = math.clamp(camDistTarget - input.Position.Z * 2, DIST_MIN, DIST_MAX)
				lastInteract = os.clock()
			end
		elseif drag and not pinching then
			if drag.UserInputType == Enum.UserInputType.MouseButton1 then
				if input.UserInputType == Enum.UserInputType.MouseMovement then
					rotateBy(input.Delta)
				end
			elseif input == drag then
				rotateBy(input.Delta)
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject, _processed: boolean)
		local drag = dragInput
		if not drag then
			return
		end
		if input == drag or (input.UserInputType == Enum.UserInputType.MouseButton1 and drag.UserInputType == Enum.UserInputType.MouseButton1) then
			dragInput = nil
		end
	end)

	UserInputService.TouchPinch:Connect(
		function(_positions: { Vector2 }, scale: number, _velocity: number, state: Enum.UserInputState, processed: boolean)
			if not isOpen then
				return
			end
			if state == Enum.UserInputState.Begin then
				if processed then
					return
				end
				pinching = true
				pinchStartDist = camDistTarget
			elseif state == Enum.UserInputState.Change then
				if pinching then
					camDistTarget = math.clamp(pinchStartDist / math.max(scale, 0.1), DIST_MIN, DIST_MAX)
					lastInteract = os.clock()
				end
			else
				pinching = false
			end
		end
	)

	----------------------------------------------------------------------------------------------
	-- Auto close: walking away, dying, respawning
	----------------------------------------------------------------------------------------------
	RunService.Heartbeat:Connect(function()
		if not isOpen then
			return
		end
		local char = LocalPlayer.Character
		local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
		if not char or not hum or hum.Health <= 0 then
			close()
			return
		end
		local rootPart = char:FindFirstChild("HumanoidRootPart")
		if rootPart and rootPart:IsA("BasePart") and (rootPart.Position - terminalPos).Magnitude > CLOSE_DISTANCE then
			close()
		end
	end)

	LocalPlayer.CharacterRemoving:Connect(function()
		close()
	end)

	gui.Destroying:Connect(function()
		close()
	end)

	----------------------------------------------------------------------------------------------
	-- Server events
	----------------------------------------------------------------------------------------------
	Remotes.get("OpenUI").OnClientEvent:Connect(function(uiName: any)
		if uiName == "Tuning" then
			open()
		end
	end)

	ClientState.onChanged(function(_snapshot: any)
		if not isOpen then
			return
		end
		if not PersonalCars.byId[previewCarId] then
			previewCarId = PersonalCars.list[1].id
			resetPreviewCustom()
			requestRebuild()
		end
		local tabsChanged = tabsSignature() ~= lastTabsSig
		if tabsChanged then
			buildTabs()
		end
		-- the panel only reads cars / ownedParts / selectedCar: money-only snapshots (income ticks every few
		-- seconds) just refresh the top bar, so cards are not rebuilt under the player's finger
		local sig = contentSignature()
		if tabsChanged or sig == nil or sig ~= lastContentSig then
			render()
		else
			updateTopBar()
		end
	end)
end

return Tuning
