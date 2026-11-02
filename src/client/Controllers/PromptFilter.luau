--!strict
-- Hides (locally) every server prompt that belongs to another player's garage.
-- Only prompts that carry an OwnerUserId attribute are ever touched.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local PromptFilter = {}

local handled: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local disabledByUs: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function handle(inst: Instance)
	if not inst:IsA("ProximityPrompt") then
		return
	end
	if handled[inst] then
		return
	end
	handled[inst] = true
	local prompt = inst

	local function owner(): number?
		local value = prompt:GetAttribute("OwnerUserId")
		if type(value) == "number" then
			return value
		end
		return nil
	end

	local function recheck()
		local ownerId = owner()
		if ownerId == nil then
			-- attribute missing: not ours to manage; give back what we took (if anything)
			if disabledByUs[prompt] then
				disabledByUs[prompt] = nil
				prompt.Enabled = true
			end
			return
		end
		if ownerId ~= LocalPlayer.UserId then
			disabledByUs[prompt] = true
			if prompt.Enabled then
				prompt.Enabled = false
			end
		elseif disabledByUs[prompt] then
			disabledByUs[prompt] = nil
			prompt.Enabled = true
		end
	end

	recheck()
	prompt:GetAttributeChangedSignal("OwnerUserId"):Connect(recheck)
	-- If the server turns a foreign prompt back on, switch it off again locally.
	prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
		local ownerId = owner()
		if ownerId ~= nil and ownerId ~= LocalPlayer.UserId and prompt.Enabled then
			prompt.Enabled = false
		end
	end)
end

function PromptFilter.start()
	Workspace.DescendantAdded:Connect(handle)
	for _, descendant in Workspace:GetDescendants() do
		handle(descendant)
	end
end

return PromptFilter
