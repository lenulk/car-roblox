--!strict
-- Shared look & feel for every client UI: palette, fonts, tiny helpers, viewport scaling and a modal helper.
--
-- Layout note: every ScreenGui made by Theme.newGui contains a full-screen transparent Frame called "Root".
-- Put all UI inside Root. Root is resized so that it exactly fills the screen even though a UIScale lives in
-- the ScreenGui (the engine behaviour is probed once at startup, see the probe at the bottom of this file).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local Theme = {}

Theme.colors = {
	panel = Color3.fromRGB(22, 26, 38),
	panelLight = Color3.fromRGB(34, 40, 58),
	panelLighter = Color3.fromRGB(48, 56, 80),
	stroke = Color3.fromRGB(110, 125, 165),
	accent = Color3.fromRGB(255, 140, 30),
	accentDark = Color3.fromRGB(214, 106, 8),
	money = Color3.fromRGB(90, 220, 110),
	star = Color3.fromRGB(255, 205, 60),
	starDim = Color3.fromRGB(64, 71, 92),
	text = Color3.fromRGB(255, 255, 255),
	textDim = Color3.fromRGB(172, 180, 204),
	danger = Color3.fromRGB(235, 100, 100),
	gray = Color3.fromRGB(70, 77, 98),
	black = Color3.fromRGB(0, 0, 0),
}

Theme.panelTransparency = 0.1
Theme.font = Enum.Font.GothamBold
Theme.fontMedium = Enum.Font.GothamMedium
Theme.fontRegular = Enum.Font.Gotham
-- Big touch targets: the viewport scale can shrink UI to 0.7, so base height 64 stays >= 44 px on phones.
Theme.buttonHeight = 64

local function merge(defaults: { [string]: any }, props: { [string]: any }?): { [string]: any }
	local out: { [string]: any } = {}
	for k, v in defaults do
		out[k] = v
	end
	if props then
		for k, v in props do
			out[k] = v
		end
	end
	return out
end

-- Create an instance, apply properties, then parent it (Parent last on purpose).
function Theme.new(className: string, props: { [string]: any }?, parent: Instance?): any
	local inst: any = Instance.new(className :: any)
	if inst:IsA("GuiObject") then
		inst.BorderSizePixel = 0
	end
	if props then
		for k, v in props do
			inst[k] = v
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Theme.corner(inst: Instance, px: number?): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, px or 12)
	c.Parent = inst
	return c
end

function Theme.stroke(inst: Instance, color: Color3?, thickness: number?, transparency: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color or Theme.colors.stroke
	s.Thickness = thickness or 1.5
	s.Transparency = transparency or 0.6
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
	return s
end

function Theme.padding(inst: Instance, vertical: number, horizontal: number?): UIPadding
	local p = Instance.new("UIPadding")
	local h = horizontal or vertical
	p.PaddingTop = UDim.new(0, vertical)
	p.PaddingBottom = UDim.new(0, vertical)
	p.PaddingLeft = UDim.new(0, h)
	p.PaddingRight = UDim.new(0, h)
	p.Parent = inst
	return p
end

function Theme.list(
	parent: Instance,
	direction: Enum.FillDirection?,
	padding: number?,
	hAlign: Enum.HorizontalAlignment?,
	vAlign: Enum.VerticalAlignment?
): UIListLayout
	local l = Instance.new("UIListLayout")
	l.FillDirection = direction or Enum.FillDirection.Vertical
	l.Padding = UDim.new(0, padding or 8)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left
	l.VerticalAlignment = vAlign or Enum.VerticalAlignment.Top
	l.Parent = parent
	return l
end

-- Keeps text inside its box (useful for Thai / long strings).
function Theme.fitText(label: Instance, minSize: number?, maxSize: number?): UITextSizeConstraint
	local c = Instance.new("UITextSizeConstraint")
	c.MinTextSize = minSize or 10
	c.MaxTextSize = maxSize or 20
	c.Parent = label
	return c
end

function Theme.tween(
	obj: Instance,
	props: { [string]: any },
	duration: number?,
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
): Tween
	local info = TweenInfo.new(
		duration or 0.25,
		style or Enum.EasingStyle.Quad,
		direction or Enum.EasingDirection.Out
	)
	local tween = TweenService:Create(obj, info, props)
	tween:Play()
	return tween
end

function Theme.label(props: { [string]: any }?, parent: Instance?): any
	return Theme.new(
		"TextLabel",
		merge({
			BackgroundTransparency = 1,
			Font = Theme.font,
			TextColor3 = Theme.colors.text,
			TextSize = 18,
			Text = "",
			Size = UDim2.fromOffset(100, 24),
		}, props),
		parent
	)
end

-- Rounded accent button. Use .Activated for clicks (works for mouse, touch and gamepad).
function Theme.button(props: { [string]: any }?, parent: Instance?): any
	local b = Theme.new(
		"TextButton",
		merge({
			BackgroundColor3 = Theme.colors.accent,
			Font = Theme.font,
			TextColor3 = Theme.colors.text,
			TextSize = 22,
			Text = "",
			AutoButtonColor = true,
			Size = UDim2.fromOffset(180, Theme.buttonHeight),
		}, props),
		parent
	)
	Theme.corner(b, 14)
	return b
end

-- Soft-shadowed rounded panel. Returns (container, body): put children into body; size/move the container.
function Theme.panel(props: { [string]: any }?, parent: Instance?): (any, any)
	local p = props or {}
	local radius: number = p.Radius or 18
	local container = Theme.new("Frame", {
		Name = p.Name or "Panel",
		BackgroundTransparency = 1,
		Size = p.Size or UDim2.fromOffset(300, 200),
		Position = p.Position or UDim2.new(),
		AnchorPoint = p.AnchorPoint or Vector2.new(0, 0),
		ZIndex = p.ZIndex or 1,
		Visible = if p.Visible == nil then true else p.Visible,
	})
	local shadow = Theme.new("Frame", {
		Name = "Shadow",
		BackgroundColor3 = Theme.colors.black,
		BackgroundTransparency = 0.72,
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
	}, container)
	Theme.corner(shadow, radius)
	local body = Theme.new("Frame", {
		Name = "Body",
		BackgroundColor3 = p.Color or Theme.colors.panel,
		BackgroundTransparency = Theme.panelTransparency,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
	}, container)
	Theme.corner(body, radius)
	Theme.stroke(body, Theme.colors.stroke, 1.5, 0.75)
	if parent then
		container.Parent = parent
	end
	return container, body
end

----------------------------------------------------------------------------------------------------
-- Viewport helpers
----------------------------------------------------------------------------------------------------

function Theme.viewportSize(): Vector2
	local cam = Workspace.CurrentCamera
	if cam and cam.ViewportSize.X > 0 and cam.ViewportSize.Y > 0 then
		return cam.ViewportSize
	end
	return Vector2.new(1280, 720)
end

function Theme.scaleFor(viewport: Vector2): number
	return math.clamp(viewport.Y / 900, 0.7, 1.15)
end

-- Phone-like screens (short or narrow).
function Theme.isCompact(): boolean
	local v = Theme.viewportSize()
	return v.Y < 520 or v.X < 700
end

-- Calls fn(viewportSize) now and whenever the viewport changes. Returns a disconnect function.
function Theme.onViewport(fn: (Vector2) -> ()): () -> ()
	local camConn: RBXScriptConnection? = nil
	local function hook()
		if camConn then
			camConn:Disconnect()
			camConn = nil
		end
		local cam = Workspace.CurrentCamera
		if cam then
			camConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				fn(Theme.viewportSize())
			end)
		end
		fn(Theme.viewportSize())
	end
	hook()
	local camSwap = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hook)
	return function()
		camSwap:Disconnect()
		if camConn then
			camConn:Disconnect()
			camConn = nil
		end
	end
end

----------------------------------------------------------------------------------------------------
-- UIScale + ScreenGui factory
----------------------------------------------------------------------------------------------------

-- Does a UIScale below 1 inside a ScreenGui shrink full-size (scale 1) children? Probed once below.
local compensateRoot = true
local fitters: { () -> () } = {}

-- Adds a UIScale (Scale = clamp(viewportY / 900, 0.7, 1.15)) that follows the viewport.
function Theme.applyScale(gui: ScreenGui): UIScale
	local scale = Instance.new("UIScale")
	scale.Name = "ViewportScale"
	scale.Parent = gui
	local function fit()
		local root = gui:FindFirstChild("Root")
		if root and root:IsA("GuiObject") then
			if compensateRoot then
				root.Size = UDim2.fromScale(1 / scale.Scale, 1 / scale.Scale)
			else
				root.Size = UDim2.fromScale(1, 1)
			end
		end
	end
	table.insert(fitters, fit)
	Theme.onViewport(function(viewport)
		scale.Scale = Theme.scaleFor(viewport)
		fit()
	end)
	return scale
end

-- Creates a ScreenGui in PlayerGui (ResetOnSpawn off, Sibling ZIndex, viewport scale) with a full-screen "Root".
function Theme.newGui(name: string, displayOrder: number?, ignoreInset: boolean?): (ScreenGui, Frame)
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.IgnoreGuiInset = ignoreInset == true
	gui.DisplayOrder = displayOrder or 1
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui
	Theme.applyScale(gui)
	gui.Parent = playerGui
	return gui, root
end

----------------------------------------------------------------------------------------------------
-- Modal helper: dimmed backdrop (tap to close) + centered panel with pop-in tween.
-- Returns a table: gui, root, backdrop, container, body, isOpen, open(), close(), toggle(), targetSize(),
-- and optional callbacks onOpen / onClose that the caller may assign.
----------------------------------------------------------------------------------------------------

function Theme.modal(name: string, displayOrder: number, preferredWidth: number, preferredHeight: number): any
	local gui, root = Theme.newGui(name, displayOrder, true)
	gui.Enabled = false

	local backdrop = Theme.new("TextButton", {
		Name = "Backdrop",
		BackgroundColor3 = Theme.colors.black,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		AutoButtonColor = false,
		ZIndex = 1,
	}, root)

	local container, body = Theme.panel({
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(preferredWidth, preferredHeight),
		ZIndex = 2,
	}, root)
	body.Active = true -- swallow taps so they do not reach the backdrop

	local m: any = {
		gui = gui,
		root = root,
		backdrop = backdrop,
		container = container,
		body = body,
		isOpen = false,
	}
	local token = 0

	function m.targetSize(): Vector2
		local vp = Theme.viewportSize()
		local s = Theme.scaleFor(vp)
		return Vector2.new(
			math.max(240, math.min(preferredWidth, vp.X / s - 24)),
			math.max(200, math.min(preferredHeight, vp.Y / s - 24))
		)
	end

	function m.open()
		if m.isOpen then
			return
		end
		m.isOpen = true
		token += 1
		gui.Enabled = true
		local size: Vector2 = m.targetSize()
		container.Size = UDim2.fromOffset(size.X * 0.88, size.Y * 0.88)
		backdrop.BackgroundTransparency = 1
		Theme.tween(backdrop, { BackgroundTransparency = 0.45 }, 0.2)
		Theme.tween(container, { Size = UDim2.fromOffset(size.X, size.Y) }, 0.3, Enum.EasingStyle.Back)
		if m.onOpen then
			m.onOpen()
		end
	end

	function m.close()
		if not m.isOpen then
			return
		end
		m.isOpen = false
		token += 1
		local mine = token
		local size: Vector2 = m.targetSize()
		Theme.tween(backdrop, { BackgroundTransparency = 1 }, 0.18)
		Theme.tween(container, { Size = UDim2.fromOffset(size.X * 0.92, size.Y * 0.92) }, 0.18)
		task.delay(0.2, function()
			if token == mine and not m.isOpen then
				gui.Enabled = false
			end
		end)
		if m.onClose then
			m.onClose()
		end
	end

	function m.toggle()
		if m.isOpen then
			m.close()
		else
			m.open()
		end
	end

	backdrop.Activated:Connect(function()
		m.close()
	end)

	Theme.onViewport(function()
		if m.isOpen then
			local size: Vector2 = m.targetSize()
			container.Size = UDim2.fromOffset(size.X, size.Y)
		end
	end)

	return m
end

----------------------------------------------------------------------------------------------------
-- Probe: find out whether UIScale < 1 on a ScreenGui shrinks scale-sized children (then Root must be
-- enlarged by 1/Scale to keep filling the screen). Runs once, in the background.
----------------------------------------------------------------------------------------------------
task.spawn(function()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local probeGui = Instance.new("ScreenGui")
	probeGui.Name = "ScaleProbe"
	probeGui.ResetOnSpawn = false
	probeGui.IgnoreGuiInset = true
	local probeScale = Instance.new("UIScale")
	probeScale.Scale = 0.5
	probeScale.Parent = probeGui
	local probeFrame = Instance.new("Frame")
	probeFrame.BackgroundTransparency = 1
	probeFrame.BorderSizePixel = 0
	probeFrame.Size = UDim2.fromScale(1, 1)
	probeFrame.Parent = probeGui
	probeGui.Parent = playerGui

	local waited = 0.0
	while (probeFrame.AbsoluteSize.X <= 0 or probeGui.AbsoluteSize.X <= 0) and waited < 2 do
		waited += task.wait()
	end
	if probeFrame.AbsoluteSize.X > 0 and probeGui.AbsoluteSize.X > 0 then
		compensateRoot = probeFrame.AbsoluteSize.X < probeGui.AbsoluteSize.X * 0.75
	end
	probeGui:Destroy()
	for _, fit in fitters do
		fit()
	end
end)

return Theme
