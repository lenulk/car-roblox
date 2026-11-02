--!strict
-- Turns TextKey / TextArgs (TextLabel, TextButton) and ActionKey / ObjectKey (ProximityPrompt) attributes into
-- localized text, and keeps them up to date (new instances, attribute changes, language changes).
-- Other controllers use Localizer.t(key, ...) and Localizer.bind(instance, key, ...).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Strings: any = require(Shared:WaitForChild("Config"):WaitForChild("Strings") :: ModuleScript)
local Client = (script.Parent :: Instance).Parent :: Instance
local ClientState: any = require(Client:WaitForChild("ClientState") :: ModuleScript)

local LocalPlayer = Players.LocalPlayer

local Localizer = {}

-- Every instance whose text we manage (weak so destroyed instances can be collected).
local tracked: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function trim(s: string): string
	local result = string.match(s, "^%s*(.-)%s*$")
	return result or s
end

local function parseArgs(raw: any): { string }
	local args: { string } = {}
	if type(raw) == "number" then
		raw = tostring(raw)
	end
	if type(raw) ~= "string" or raw == "" then
		return args
	end
	for _, part in string.split(raw, ",") do
		table.insert(args, trim(part))
	end
	return args
end

local function apply(inst: Instance)
	local lang: string = ClientState.lang()
	if inst:IsA("TextLabel") or inst:IsA("TextButton") then
		local obj: any = inst
		local key = inst:GetAttribute("TextKey")
		if type(key) ~= "string" or key == "" then
			return
		end
		local rawArgs: any = inst:GetAttribute("TextArgs")
		local text: string
		if key == "plot_owner" and inst.Name == "OwnerLabel" then
			-- Gate sign: TextArgs is the owner's name (may contain commas, so it is not split).
			local owner = if type(rawArgs) == "string" then trim(rawArgs) else ""
			if owner == "" then
				text = Strings.get(lang, "plot_free")
			else
				text = Strings.get(lang, key, owner)
			end
		else
			local args = parseArgs(rawArgs)
			text = Strings.get(lang, key, table.unpack(args))
		end
		if obj.Text ~= text then
			obj.Text = text
		end
	elseif inst:IsA("ProximityPrompt") then
		local prompt: any = inst
		local actionKey = inst:GetAttribute("ActionKey")
		if type(actionKey) == "string" and actionKey ~= "" then
			local text: string = Strings.get(lang, actionKey)
			if prompt.ActionText ~= text then
				prompt.ActionText = text
			end
		end
		local objectKey = inst:GetAttribute("ObjectKey")
		if type(objectKey) == "string" and objectKey ~= "" then
			local text: string = Strings.get(lang, objectKey)
			if prompt.ObjectText ~= text then
				prompt.ObjectText = text
			end
		end
	end
end

local function track(inst: Instance)
	if tracked[inst] then
		return
	end
	tracked[inst] = true
	if inst:IsA("ProximityPrompt") then
		inst:GetAttributeChangedSignal("ActionKey"):Connect(function()
			apply(inst)
		end)
		inst:GetAttributeChangedSignal("ObjectKey"):Connect(function()
			apply(inst)
		end)
	else
		inst:GetAttributeChangedSignal("TextKey"):Connect(function()
			apply(inst)
		end)
		inst:GetAttributeChangedSignal("TextArgs"):Connect(function()
			apply(inst)
		end)
	end
	apply(inst)
end

-- alwaysTrack: Workspace content may get its attributes after being parented, so watch every text/prompt there.
local function consider(inst: Instance, alwaysTrack: boolean)
	if inst:IsA("TextLabel") or inst:IsA("TextButton") then
		if alwaysTrack or inst:GetAttribute("TextKey") ~= nil then
			track(inst)
		end
	elseif inst:IsA("ProximityPrompt") then
		if alwaysTrack or inst:GetAttribute("ActionKey") ~= nil or inst:GetAttribute("ObjectKey") ~= nil then
			track(inst)
		end
	end
end

-- Language change detection (module level so other controllers can subscribe before start() runs).
local langEvent = Instance.new("BindableEvent")
local lastLang: string? = nil

ClientState.onChanged(function(_snapshot: any)
	local lang: string = ClientState.lang()
	if lang == lastLang then
		return
	end
	lastLang = lang
	for inst in tracked do
		apply(inst)
	end
	langEvent:Fire(lang)
end)

-- Localized string for the current language.
function Localizer.t(key: string, ...: any): string
	return Strings.get(ClientState.lang(), key, ...)
end

-- Fires (lang) when the language actually changed.
function Localizer.onLangChanged(fn: (string) -> ()): RBXScriptConnection
	return langEvent.Event:Connect(fn)
end

-- Gives an instance a TextKey (+ optional args, joined with commas so avoid commas inside them),
-- sets its text now, and keeps it translated on language changes.
function Localizer.bind(inst: Instance, key: string, ...: any)
	inst:SetAttribute("TextKey", key)
	local count = select("#", ...)
	if count > 0 then
		local parts: { string } = {}
		for i = 1, count do
			parts[i] = tostring((select(i, ...)))
		end
		inst:SetAttribute("TextArgs", table.concat(parts, ","))
	else
		inst:SetAttribute("TextArgs", nil)
	end
	track(inst)
	apply(inst)
end

function Localizer.start()
	local function scan(root: Instance, alwaysTrack: boolean)
		root.DescendantAdded:Connect(function(descendant)
			consider(descendant, alwaysTrack)
		end)
		for _, descendant in root:GetDescendants() do
			consider(descendant, alwaysTrack)
		end
	end
	scan(Workspace, true)
	scan(LocalPlayer:WaitForChild("PlayerGui"), false)
end

return Localizer
