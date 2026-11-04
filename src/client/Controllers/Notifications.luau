--!strict
-- Toast messages from the server (Notify remote): stacked below the HUD, max 4, auto-hide after 3 seconds.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes: any = require(Shared:WaitForChild("Remotes") :: ModuleScript)
local Client = (script.Parent :: Instance).Parent :: Instance
local Theme: any = require(Client:WaitForChild("Theme") :: ModuleScript)
local Localizer: any = require((script.Parent :: Instance):WaitForChild("Localizer") :: ModuleScript)
local Shop: any = require((script.Parent :: Instance):WaitForChild("Shop") :: ModuleScript)

local Notifications = {}

local MAX_TOASTS = 4
local SHOW_SECONDS = 3

local function startsWith(text: string, prefix: string): boolean
	return string.sub(text, 1, #prefix) == prefix
end

-- Returns (background, stroke) colors for a message key.
local function colorsFor(key: string): (Color3, Color3)
	local C = Theme.colors
	if startsWith(key, "notify_not_enough") or startsWith(key, "hire_no_slot") or startsWith(key, "hire_locked") then
		return Color3.fromRGB(70, 30, 36), C.danger
	elseif startsWith(key, "notify_unlocked") or startsWith(key, "notify_star_up") then
		return Color3.fromRGB(62, 50, 16), C.star
	end
	return C.panel, C.stroke
end

function Notifications.start()
	local _gui, root = Theme.newGui("Notifications", 8, false)

	local container = Theme.new("Frame", {
		Name = "Toasts",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 80),
		Size = UDim2.fromOffset(400, 10),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, root)
	Theme.list(container, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)

	local active: { Frame } = {} -- oldest first
	local dismissed: { [Frame]: boolean } = {}
	local counter = 0

	local function dismiss(wrapper: Frame)
		if dismissed[wrapper] or not wrapper.Parent then
			return
		end
		dismissed[wrapper] = true
		local index = table.find(active, wrapper)
		if index then
			table.remove(active, index)
		end
		local toast = wrapper:FindFirstChild("Body")
		if toast then
			Theme.tween(toast, { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, -10) }, 0.25)
			local label = toast:FindFirstChild("Message")
			if label then
				Theme.tween(label, { TextTransparency = 1 }, 0.25)
			end
			local stroke = toast:FindFirstChildOfClass("UIStroke")
			if stroke then
				Theme.tween(stroke, { Transparency = 1 }, 0.25)
			end
		end
		task.delay(0.3, function()
			wrapper:Destroy()
			dismissed[wrapper] = nil
		end)
	end

	local function show(key: any, args: any)
		if type(key) ~= "string" then
			return
		end
		local argList: { any } = if type(args) == "table" then args else {}
		local text: string = Localizer.t(key, table.unpack(argList))
		local background, strokeColor = colorsFor(key)

		counter += 1
		local wrapper: Frame = Theme.new("Frame", {
			Name = "Toast",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 52),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = counter,
		}, container)

		local toast = Theme.new("Frame", {
			Name = "Body",
			BackgroundColor3 = background,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, -16),
			Size = UDim2.new(1, 0, 0, 52),
			AutomaticSize = Enum.AutomaticSize.Y,
		}, wrapper)
		Theme.corner(toast, 16)
		local stroke = Theme.stroke(toast, strokeColor, 2, 1)
		Theme.padding(toast, 10, 16)

		local label = Theme.label({
			Name = "Message",
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Text = text,
			TextSize = 20,
			TextWrapped = true,
			TextTransparency = 1,
		}, toast)

		local showSeconds = SHOW_SECONDS
		if key == "notify_not_enough_money" then
			-- "Get cash" shortcut to the Shop's Cash tab
			Theme.list(toast, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center)
			label.LayoutOrder = 1
			local getCash = Theme.button({
				Name = "GetCash",
				Size = UDim2.fromOffset(170, 44),
				BackgroundColor3 = Color3.fromRGB(38, 160, 78),
				TextSize = 20,
				LayoutOrder = 2,
			}, toast)
			Localizer.bind(getCash, "notify_get_cash")
			getCash.Activated:Connect(function()
				Shop.open("cash")
				dismiss(wrapper)
			end)
			showSeconds = 5
		end

		Theme.tween(toast, { BackgroundTransparency = 0.08, Position = UDim2.fromOffset(0, 0) }, 0.3, Enum.EasingStyle.Back)
		Theme.tween(stroke, { Transparency = 0.15 }, 0.3)
		Theme.tween(label, { TextTransparency = 0 }, 0.3)

		table.insert(active, wrapper)
		while #active > MAX_TOASTS do
			dismiss(active[1])
		end

		task.delay(showSeconds, function()
			dismiss(wrapper)
		end)
	end

	Remotes.get("Notify").OnClientEvent:Connect(show)
end

return Notifications
