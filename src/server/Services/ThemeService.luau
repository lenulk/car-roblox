--!strict
-- Garage themes: recolors every part tagged with a ThemeRole attribute in a plot (including
-- unlockables waiting in storage) and the staff uniforms. Buying/applying via the BuyTheme remote.

local ServerStorage = game:GetService("ServerStorage")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Layout = require(Shared.Layout)
local Remotes = require(Shared.Remotes)
local Format = require(Shared.Format)
local Strings = require(Shared.Config.Strings)
local Themes = require(Shared.Config.Themes)

local PlayerData = require(script.Parent.PlayerData)
local PlotService = require(script.Parent.PlotService)
local MapBuilder = require(script.Parent.MapBuilder)
local EmployeeService = require(script.Parent.EmployeeService)

local ThemeService = {}

local CLASSIC = Themes.byId.Classic

-- Read from the owner's data every time so callers never depend on event ordering.
local function themeOf(plotIndex: number): any
	local owner = PlotService.getOwner(plotIndex)
	local data = owner and PlayerData.get(owner)
	return (data and Themes.byId[data.theme]) or CLASSIC
end

function ThemeService.accentFor(plotIndex: number): Color3
	local theme = themeOf(plotIndex)
	return theme.accent or Layout.PLOT_ACCENTS[plotIndex]
end

local function colorForRole(plotIndex: number, role: string): Color3?
	local theme = themeOf(plotIndex)
	local accent = ThemeService.accentFor(plotIndex)
	if role == "Accent" then
		return accent
	elseif role == "Stripe" then
		return theme.stripe or accent
	elseif role == "Wall" then
		return theme.wall
	elseif role == "Floor" then
		return theme.floor
	elseif role == "Roof" then
		return theme.roof
	end
	return nil
end

-- Recolors tagged parts under `root` for this plot's theme.
function ThemeService.applyTo(plotIndex: number, root: Instance)
	local function paint(inst: Instance)
		if not inst:IsA("BasePart") then
			return
		end
		local role = inst:GetAttribute("ThemeRole")
		if type(role) ~= "string" then
			return
		end
		local color = colorForRole(plotIndex, role)
		if color then
			inst.Color = color
			if role == "Accent" then
				for _, child in inst:GetChildren() do
					if child:IsA("Light") and not child:GetAttribute("NightLight") then
						child.Color = color
					end
				end
			end
		end
	end
	paint(root)
	for _, d in root:GetDescendants() do
		paint(d)
	end
end

function ThemeService.applyPlot(plotIndex: number)
	ThemeService.applyTo(plotIndex, MapBuilder.getPlot(plotIndex))
	local storage = ServerStorage:FindFirstChild("LockedUnlockables")
	local plotStorage = storage and storage:FindFirstChild("Plot" .. plotIndex)
	if plotStorage then
		ThemeService.applyTo(plotIndex, plotStorage)
	end
	local theme = themeOf(plotIndex)
	pcall(EmployeeService.setUniform, plotIndex, if theme.id == "Classic" then nil else theme.uniform)
end

local busy: { [Player]: boolean } = {}

local function buyTheme(player: Player, themeId: any): (boolean, string)
	local theme = if type(themeId) == "string" then Themes.byId[themeId] else nil
	local data = PlayerData.get(player)
	local plotIndex = PlotService.getPlotIndex(player)
	if not theme or not data or not plotIndex or busy[player] then
		return false, "notify_max_level"
	end
	local name = Strings.get(data.settings.lang, "theme_" .. theme.id)
	if not data.ownedThemes[theme.id] then
		if data.money < theme.price then
			Remotes.get("Notify"):FireClient(player, "notify_not_enough_money", { Format.money(theme.price - data.money) })
			return false, "notify_not_enough_money"
		end
		busy[player] = true
		PlayerData.update(player, function(d)
			d.money -= theme.price
			d.ownedThemes[theme.id] = true
		end)
		busy[player] = nil
		Remotes.get("Notify"):FireClient(player, "notify_theme_bought", { name })
	else
		Remotes.get("Notify"):FireClient(player, "notify_theme_applied", { name })
	end
	PlayerData.update(player, function(d)
		d.theme = theme.id
	end)
	ThemeService.applyPlot(plotIndex)
	Remotes.get("Effect"):FireClient(player, "Level", Layout.toWorld(plotIndex, Layout.GATE).Position + Vector3.new(0, 16, 0))
	return true, "notify_theme_applied"
end

function ThemeService.start()
	Remotes.get("BuyTheme").OnServerInvoke = buyTheme
	for plotIndex = 1, Layout.PLOT_COUNT do
		ThemeService.applyPlot(plotIndex)
	end
	PlotService.onAssigned(function(_player, plotIndex)
		ThemeService.applyPlot(plotIndex)
	end)
	PlotService.onReleased(function(_player, plotIndex)
		-- The owner is cleared right after release callbacks; recolor once that happened.
		task.defer(ThemeService.applyPlot, plotIndex)
	end)
	PlayerData.addSnapshotField(function(_player, data, snapshot)
		snapshot.themes = { current = data.theme, owned = table.clone(data.ownedThemes) }
	end)
end

return ThemeService
