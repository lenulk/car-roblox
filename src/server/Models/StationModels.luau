--!strict
-- Builds the model for a station / shelf at a given upgrade level (docs/CONTRACT.md §12).
-- Each key has a builder module in ./Stations/<Key>.luau: `return function(level, accent, opts): Model`.
-- Art override: ReplicatedStorage.Models["Station_<key>_Lv<level>"] (or "Station_<key>") is cloned instead.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StationModels = {}

local MODULES: { [string]: string } = {
	tire = "Tire",
	oil = "Oil",
	lift = "Lift",
	paint = "Paint",
	wash = "Wash",
	diagnostics = "Diagnostics",
	engine = "Engine",
	dyno = "Dyno",
	shelf = "Shelf",
	reception = "Reception",
}

local builders: { [string]: (number, Color3, { [string]: any }?) -> Model } = {}

local function builderFor(key: string): ((number, Color3, { [string]: any }?) -> Model)?
	if builders[key] then
		return builders[key]
	end
	local moduleName = MODULES[key]
	local moduleScript = moduleName and script.Parent:WaitForChild("Stations"):FindFirstChild(moduleName)
	if not moduleScript then
		return nil
	end
	local ok, result = pcall(require, moduleScript :: ModuleScript)
	if not ok or type(result) ~= "function" then
		warn(`[StationModels] {moduleName} failed to load: {result}`)
		return nil
	end
	builders[key] = result
	return result
end

local function placeholder(key: string, accent: Color3): Model
	local model = Instance.new("Model")
	local pivot = Instance.new("Part")
	pivot.Name = "Pivot"
	pivot.Anchored = true
	pivot.Size = Vector3.new(3, 3, 3)
	pivot.CFrame = CFrame.new(0, 1.5, 0)
	pivot.Color = accent
	pivot.Material = Enum.Material.Neon
	pivot.Parent = model
	model.PrimaryPart = pivot
	model.Name = "Station"
	model:SetAttribute("StationKey", key)
	return model
end

local function artOverride(key: string, level: number): Model?
	local models = ReplicatedStorage:FindFirstChild("Models")
	if not models then
		return nil
	end
	local art = models:FindFirstChild(`Station_{key}_Lv{level}`) or models:FindFirstChild("Station_" .. key)
	if art and art:IsA("Model") then
		local clone = art:Clone()
		for _, d in clone:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end
		if not clone.PrimaryPart then
			clone.PrimaryPart = clone:FindFirstChildWhichIsA("BasePart", true)
		end
		return clone
	end
	return nil
end

-- Returns a Model named "Station", pivot at the origin (move it with PivotTo).
function StationModels.build(key: string, level: number, accent: Color3, opts: { [string]: any }?): Model
	level = math.clamp(math.floor(level), 1, 5)
	local model = artOverride(key, level)
	if not model then
		local build = builderFor(key)
		if build then
			local ok, result = pcall(build, level, accent, opts)
			if ok and typeof(result) == "Instance" and result:IsA("Model") then
				model = result
			else
				warn(`[StationModels] build {key} Lv{level} failed: {result}`)
			end
		end
	end
	local final = model or placeholder(key, accent)
	final.Name = "Station"
	final:SetAttribute("StationKey", key)
	final:SetAttribute("Level", level)
	return final
end

return StationModels
