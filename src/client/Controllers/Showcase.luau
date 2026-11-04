--!strict
-- Spins every showcase car (visual only) and hides the local player's own while the Tuning menu is open
-- (the menu draws its own preview car at the same spot).
-- Parts replicate one by one, so each part is spun from the CFrame the server gave it, around the
-- server's base CFrame (attribute ShowcaseBase). Spinning the whole model with PivotTo would leave
-- late parts at a different angle from the rest.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local Showcase = {}

local SPIN_DEGREES_PER_SECOND = 12
local FOLDER_NAME = "Showcases"
local CAR_NAME = "ShowcaseCar"

type Entry = {
	base: CFrame?,
	parts: { BasePart },
	offsets: { CFrame }, -- each part relative to base (filled once base is known)
	originals: { [BasePart]: CFrame }, -- server CFrame, recorded before we ever move the part
}

function Showcase.start()
	local entries: { [Model]: Entry } = {}
	local startTime = os.clock()

	local function isMine(model: Model): boolean
		return model:GetAttribute("ShowcaseOwner") == LocalPlayer.UserId
	end

	local function hiddenFor(model: Model): boolean
		return LocalPlayer:GetAttribute("TuningOpen") == true and isMine(model)
	end

	local function applyHidden(model: Model)
		local value = if hiddenFor(model) then 1 else 0
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d.LocalTransparencyModifier ~= value then
				d.LocalTransparencyModifier = value
			end
		end
	end

	local function rebuildOffsets(entry: Entry)
		local base = entry.base
		table.clear(entry.parts)
		table.clear(entry.offsets)
		if not base then
			return
		end
		for part, original in entry.originals do
			table.insert(entry.parts, part)
			table.insert(entry.offsets, base:ToObjectSpace(original))
		end
	end

	local function addPart(model: Model, entry: Entry, part: BasePart)
		if entry.originals[part] then
			return
		end
		entry.originals[part] = part.CFrame
		local base = entry.base
		if base then
			table.insert(entry.parts, part)
			table.insert(entry.offsets, base:ToObjectSpace(part.CFrame))
		end
		if hiddenFor(model) then
			part.LocalTransparencyModifier = 1
		end
	end

	local function track(child: Instance)
		if not child:IsA("Model") or child.Name ~= CAR_NAME then
			return
		end
		local model = child :: Model
		local entry: Entry = { base = nil, parts = {}, offsets = {}, originals = {} }
		entries[model] = entry
		local function readBase()
			local base = model:GetAttribute("ShowcaseBase")
			entry.base = if typeof(base) == "CFrame" then base else nil
			rebuildOffsets(entry)
		end
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				addPart(model, entry, d)
			end
		end
		readBase()
		model:GetAttributeChangedSignal("ShowcaseBase"):Connect(readBase)
		model.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") then
				addPart(model, entry, d)
			end
		end)
		model.DescendantRemoving:Connect(function(d)
			if d:IsA("BasePart") and entry.originals[d] then
				entry.originals[d] = nil
				rebuildOffsets(entry)
			end
		end)
		applyHidden(model)
	end

	local function watchFolder(folder: Instance)
		for _, child in folder:GetChildren() do
			track(child)
		end
		folder.ChildAdded:Connect(track)
		folder.ChildRemoved:Connect(function(child)
			if child:IsA("Model") then
				entries[child] = nil
			end
		end)
	end

	LocalPlayer:GetAttributeChangedSignal("TuningOpen"):Connect(function()
		for model in entries do
			applyHidden(model)
		end
	end)

	RunService.RenderStepped:Connect(function()
		local spin = CFrame.Angles(0, math.rad(SPIN_DEGREES_PER_SECOND) * (os.clock() - startTime), 0)
		for model, entry in entries do
			local base = entry.base
			if model.Parent and base and #entry.parts > 0 then
				local turned = base * spin
				local targets = table.create(#entry.offsets)
				for i, offset in entry.offsets do
					targets[i] = turned * offset
				end
				Workspace:BulkMoveTo(entry.parts, targets, Enum.BulkMoveMode.FireCFrameChanged)
			end
		end
	end)

	local folder = Workspace:FindFirstChild(FOLDER_NAME) or Workspace:WaitForChild(FOLDER_NAME, 30)
	if folder then
		watchFolder(folder)
	else
		warn("[Showcase] Showcases folder never appeared")
	end
end

return Showcase
