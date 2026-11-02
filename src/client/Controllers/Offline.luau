--!strict
-- "Welcome back" popup, opened by the server with OpenUI("Offline", amount): what the staff earned while the
-- player was away, with a coin rain and a count-up of the amount.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes: any = require(Shared:WaitForChild("Remotes") :: ModuleScript)
local Format: any = require(Shared:WaitForChild("Format") :: ModuleScript)
local Controllers = script.Parent :: Instance
local Client = Controllers.Parent :: Instance
local Theme: any = require(Client:WaitForChild("Theme") :: ModuleScript)
local Localizer: any = require(Controllers:WaitForChild("Localizer") :: ModuleScript)
local Effects: any = require(Controllers:WaitForChild("Effects") :: ModuleScript)

local Offline = {}

function Offline.start()
	local C = Theme.colors
	local m = Theme.modal("Offline", 40, 440, 430)
	local body = m.body

	-- big gold coin
	local coin = Theme.new("Frame", {
		Name = "Coin",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 22),
		Size = UDim2.fromOffset(84, 84),
		BackgroundColor3 = C.star,
	}, body)
	Theme.corner(coin, 42)
	Theme.stroke(coin, Color3.fromRGB(214, 150, 20), 4, 0)
	Theme.label({
		Size = UDim2.fromScale(1, 1),
		Text = "$",
		TextSize = 52,
		TextColor3 = Color3.fromRGB(150, 96, 10),
	}, coin)

	local title = Theme.label({
		Name = "Title",
		Position = UDim2.fromOffset(16, 118),
		Size = UDim2.new(1, -32, 0, 38),
		TextScaled = true,
	}, body)
	Theme.fitText(title, 16, 30)
	Localizer.bind(title, "offline_title")

	local amountLabel = Theme.label({
		Name = "Amount",
		Position = UDim2.fromOffset(16, 160),
		Size = UDim2.new(1, -32, 0, 66),
		Text = Format.money(0),
		TextScaled = true,
		TextColor3 = C.money,
	}, body)
	Theme.fitText(amountLabel, 24, 56)

	local message = Theme.label({
		Name = "Message",
		Position = UDim2.fromOffset(28, 230),
		Size = UDim2.new(1, -56, 0, 60),
		Font = Theme.fontMedium,
		TextColor3 = C.textDim,
		TextScaled = true,
		TextWrapped = true,
	}, body)
	Theme.fitText(message, 12, 19)
	Localizer.bind(message, "offline_line")

	local okButton = Theme.button({
		Name = "Ok",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -22),
		Size = UDim2.new(1, -56, 0, 72),
		TextSize = 30,
	}, body)
	Localizer.bind(okButton, "ui_ok")
	okButton.Activated:Connect(function()
		m.close()
	end)

	----------------------------------------------------------------- count-up
	local displayed = Instance.new("NumberValue")
	displayed.Value = 0
	displayed.Changed:Connect(function(value: number)
		amountLabel.Text = Format.money(math.floor(value + 0.5))
	end)

	local countTween: Tween? = nil
	local pendingAmount = 0

	m.onOpen = function()
		if countTween then
			countTween:Cancel()
		end
		displayed.Value = 0
		amountLabel.Text = Format.money(0)
		countTween = Theme.tween(displayed, { Value = pendingAmount }, 1.4, Enum.EasingStyle.Quad)

		-- little coin bounce
		coin.Position = UDim2.new(0.5, 0, 0, -30)
		Theme.tween(coin, { Position = UDim2.new(0.5, 0, 0, 22) }, 0.7, Enum.EasingStyle.Bounce)
		Effects.coinRain(m.root, 40)
	end

	Remotes.get("OpenUI").OnClientEvent:Connect(function(uiName: any, arg: any)
		if uiName ~= "Offline" then
			return
		end
		local amount = if type(arg) == "number" then arg else tonumber(arg)
		if amount == nil or amount <= 0 then
			return
		end
		pendingAmount = amount
		if m.isOpen then
			m.onOpen()
		else
			m.open()
		end
	end)
end

return Offline
