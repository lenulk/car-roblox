--!strict
-- Starter Pack popup (Products.Items.StarterPack: cash + Gold paint, one time only).
-- Shown right after the tutorial finishes, and again at the start of later sessions, until the pack is bought or the
-- player has closed the popup 3 times. Each close is reported to the server (SetSetting "starterPackDismissed"), which
-- keeps the count in Data.starterPackDismissals. The pack is also always listed in the Shop's Special tab.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes: any = require(Shared:WaitForChild("Remotes") :: ModuleScript)
local Format: any = require(Shared:WaitForChild("Format") :: ModuleScript)
local Products: any = require(Shared:WaitForChild("Config"):WaitForChild("Products") :: ModuleScript)
local Controllers = script.Parent :: Instance
local Client = Controllers.Parent :: Instance
local ClientState: any = require(Client:WaitForChild("ClientState") :: ModuleScript)
local Theme: any = require(Client:WaitForChild("Theme") :: ModuleScript)
local RobuxBuy: any = require(Client:WaitForChild("RobuxBuy") :: ModuleScript)
local Localizer: any = require(Controllers:WaitForChild("Localizer") :: ModuleScript)

local StarterPack = {}

local PRODUCT = "StarterPack"
local TUTORIAL_LAST_STEP = 3 -- Tutorial.luau TOTAL_STEPS: tutorialStep > 3 means the tutorial is done
local DELAY_AFTER_TUTORIAL = 7 -- the tutorial's own celebration card lasts about 4 s
local DELAY_AT_JOIN = 12
local MAX_DISMISSALS = 3

function StarterPack.start()
	local C = Theme.colors
	local entry: any = Products.byKey[PRODUCT]
	if not entry then
		return
	end

	local m = Theme.modal("StarterPack", 23, 480, 420)
	local body = m.body

	local gift = Theme.label({
		Name = "Gift",
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(1, 0, 0, 84),
		Text = "🎁",
		TextSize = 70,
	}, body)
	gift.TextScaled = false

	local title = Theme.label({
		Name = "Title",
		Position = UDim2.fromOffset(16, 112),
		Size = UDim2.new(1, -32, 0, 40),
		TextScaled = true,
		TextColor3 = RobuxBuy.GOLD,
	}, body)
	Theme.fitText(title, 18, 32)
	Localizer.bind(title, "starter_title")

	local text = Theme.label({
		Name = "Description",
		Position = UDim2.fromOffset(24, 158),
		Size = UDim2.new(1, -48, 0, 70),
		Font = Theme.fontMedium,
		TextScaled = true,
		TextWrapped = true,
		TextColor3 = C.textDim,
	}, body)
	Theme.fitText(text, 13, 22)
	local grant: any = entry.grant
	Localizer.bind(text, "starter_body", Format.money(if type(grant) == "table" and type(grant.money) == "number" then grant.money else 0))

	local buy = Theme.button({
		Name = "Buy",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -92),
		Size = UDim2.fromOffset(280, 64),
		BackgroundColor3 = RobuxBuy.BUTTON,
		TextSize = 26,
	}, body)

	local later = Theme.button({
		Name = "Later",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(220, 56),
		BackgroundColor3 = C.gray,
		TextSize = 22,
	}, body)
	Localizer.bind(later, "starter_later")

	local function refreshPrice()
		buy.Text = RobuxBuy.priceText(PRODUCT, function()
			if m.isOpen then
				buy.Text = RobuxBuy.priceText(PRODUCT)
			end
		end)
	end
	refreshPrice()

	-- closing without buying counts as a dismissal (3 of them and the popup never comes back)
	local purchased = false
	m.onClose = function()
		if not purchased then
			Remotes.get("SetSetting"):FireServer("starterPackDismissed", true)
		end
	end
	buy.Activated:Connect(function()
		RobuxBuy.buy(PRODUCT)
	end)
	later.Activated:Connect(function()
		m.close()
	end)

	local sawTutorial = false
	local scheduled = false
	local shownThisSession = false

	local function eligible(snapshot: any): boolean
		local pack: any = snapshot.starterPack
		if type(pack) ~= "table" or pack.bought == true or (pack.dismissals or 0) >= MAX_DISMISSALS then
			return false
		end
		return RobuxBuy.available(PRODUCT)
	end

	ClientState.onChanged(function(snapshot: any)
		local pack: any = snapshot.starterPack
		-- bought while the popup is open: close without counting a dismissal
		if m.isOpen and type(pack) == "table" and pack.bought == true then
			purchased = true
			m.close()
			return
		end
		local step: any = snapshot.tutorialStep
		if type(step) ~= "number" then
			return
		end
		if step <= TUTORIAL_LAST_STEP then
			sawTutorial = true
			return
		end
		if shownThisSession or scheduled or not eligible(snapshot) or snapshot.prologueDone == false then
			return
		end
		scheduled = true
		task.delay(if sawTutorial then DELAY_AFTER_TUTORIAL else DELAY_AT_JOIN, function()
			local latest: any = ClientState.snapshot
			if latest and eligible(latest) and latest.driving ~= true and not m.isOpen then
				shownThisSession = true
				purchased = false
				refreshPrice()
				m.open()
			else
				scheduled = false
			end
		end)
	end)
end

return StarterPack
