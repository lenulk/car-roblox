--!strict
-- Settings panel: language + music. Toggle from anywhere with Settings.toggle().

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes: any = require(Shared:WaitForChild("Remotes") :: ModuleScript)
local Client = (script.Parent :: Instance).Parent :: Instance
local ClientState: any = require(Client:WaitForChild("ClientState") :: ModuleScript)
local Theme: any = require(Client:WaitForChild("Theme") :: ModuleScript)
local Localizer: any = require((script.Parent :: Instance):WaitForChild("Localizer") :: ModuleScript)
local Music: any = require((script.Parent :: Instance):WaitForChild("Music") :: ModuleScript)

local Settings = {}

local modal: any = nil

function Settings.toggle()
	if modal then
		modal.toggle()
	end
end

function Settings.open()
	if modal then
		modal.open()
	end
end

function Settings.close()
	if modal then
		modal.close()
	end
end

function Settings.start()
	local C = Theme.colors
	local m = Theme.modal("Settings", 30, 440, 400)
	modal = m
	local body = m.body

	local title = Theme.label({
		Name = "Title",
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(1, 0, 0, 40),
		TextSize = 30,
	}, body)
	Localizer.bind(title, "settings_title")

	local function sectionLabel(key: string, y: number)
		local label = Theme.label({
			Size = UDim2.new(1, -48, 0, 24),
			Position = UDim2.fromOffset(24, y),
			TextSize = 18,
			TextColor3 = C.textDim,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, body)
		Localizer.bind(label, key)
	end

	local function choiceRow(y: number): Frame
		return Theme.new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(24, y),
			Size = UDim2.new(1, -48, 0, Theme.buttonHeight),
		}, body)
	end

	local function choiceButton(row: Frame, key: string, side: number, onPress: () -> ()): any
		local button = Theme.button({
			Position = if side == 0 then UDim2.fromScale(0, 0) else UDim2.new(0.5, 6, 0, 0),
			Size = UDim2.new(0.5, -6, 1, 0),
			TextSize = 24,
		}, row)
		Localizer.bind(button, key)
		button.Activated:Connect(onPress)
		return button
	end

	local function styleChoice(button: any, selected: boolean)
		Theme.tween(button, {
			BackgroundColor3 = if selected then C.accent else C.panelLighter,
			TextColor3 = if selected then C.text else C.textDim,
		}, 0.15)
	end

	local setting = Remotes.get("SetSetting")

	sectionLabel("settings_lang", 70)
	local langRow = choiceRow(98)
	local thButton = choiceButton(langRow, "lang_th", 0, function()
		setting:FireServer("lang", "th")
	end)
	local enButton = choiceButton(langRow, "lang_en", 1, function()
		setting:FireServer("lang", "en")
	end)

	sectionLabel("settings_music", 182)
	local musicRow = choiceRow(210)
	local onButton = choiceButton(musicRow, "on", 0, function()
		setting:FireServer("music", true)
	end)
	local offButton = choiceButton(musicRow, "off", 1, function()
		setting:FireServer("music", false)
	end)

	local closeButton = Theme.button({
		Name = "Close",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(220, Theme.buttonHeight),
		BackgroundColor3 = C.gray,
		TextSize = 24,
	}, body)
	Localizer.bind(closeButton, "close")
	closeButton.Activated:Connect(function()
		m.close()
	end)

	ClientState.onChanged(function(snapshot: any)
		local settings = snapshot.settings
		local lang = if settings and settings.lang then settings.lang else ClientState.lang()
		local music = if settings then settings.music == true else false
		styleChoice(thButton, lang == "th")
		styleChoice(enButton, lang == "en")
		styleChoice(onButton, music)
		styleChoice(offButton, not music)
		-- Music.luau owns the Sound under SoundService; keep it in step with the setting.
		if settings and settings.music ~= nil then
			Music.setWanted(settings.music == true)
		end
	end)
end

return Settings
