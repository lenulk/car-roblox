--!strict
-- Floating info card above each of the local player's customer cars: problem, state, repair progress.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Client = (script.Parent :: Instance).Parent :: Instance
local Theme: any = require(Client:WaitForChild("Theme") :: ModuleScript)
local Localizer: any = require((script.Parent :: Instance):WaitForChild("Localizer") :: ModuleScript)

local LocalPlayer = Players.LocalPlayer

local CarBillboards = {}

function CarBillboards.start()
	local C = Theme.colors
	local cars = Workspace:WaitForChild("CustomerCars")

	-- entry: { removed: boolean, conns: {RBXScriptConnection}, gui: BillboardGui?, update: (() -> ())? }
	local entries: { [Instance]: any } = {}

	local function attach(child: Instance)
		if not child:IsA("Model") or entries[child] then
			return
		end
		local car: Model = child
		local entry: any = { removed = false, conns = {}, gui = nil, update = nil }
		entries[car] = entry

		task.spawn(function()
			local root = car:WaitForChild("Root", 10)
			if root == nil or entry.removed then
				return
			end
			local anchor: Instance = root:WaitForChild("TopAttachment", 5) or root
			if entry.removed then
				return
			end

			local gui = Theme.new("BillboardGui", {
				Name = "CarInfo",
				Adornee = anchor,
				Size = UDim2.fromOffset(150, 54),
				StudsOffset = Vector3.new(0, 0.5, 0),
				MaxDistance = 120,
				AlwaysOnTop = true,
				LightInfluence = 0,
				Enabled = false,
			}, root)
			entry.gui = gui

			local card = Theme.new("Frame", {
				Name = "Card",
				BackgroundColor3 = C.panel,
				BackgroundTransparency = 0.12,
				Size = UDim2.fromScale(1, 1),
			}, gui)
			Theme.corner(card, 12)
			Theme.stroke(card, C.stroke, 1.5, 0.6)

			local problemLabel = Theme.label({
				Name = "Problem",
				Position = UDim2.fromOffset(8, 4),
				Size = UDim2.new(1, -16, 0, 20),
				TextSize = 15,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}, card)
			local stateLabel = Theme.label({
				Name = "State",
				Position = UDim2.fromOffset(8, 24),
				Size = UDim2.new(1, -16, 0, 16),
				Font = Theme.fontMedium,
				TextSize = 13,
				TextColor3 = C.textDim,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}, card)
			local track = Theme.new("Frame", {
				Name = "BarTrack",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 43),
				Size = UDim2.new(1, -16, 0, 7),
				BackgroundColor3 = C.starDim,
				Visible = false,
			}, card)
			Theme.corner(track, 4)
			local fill = Theme.new("Frame", {
				Name = "Fill",
				BackgroundColor3 = C.accent,
				Size = UDim2.fromScale(0, 1),
			}, track)
			Theme.corner(fill, 4)

			local function updateProgress()
				local progress = car:GetAttribute("RepairProgress")
				local fraction = if type(progress) == "number" then math.clamp(progress, 0, 1) else 0
				Theme.tween(fill, { Size = UDim2.fromScale(fraction, 1) }, 0.2, Enum.EasingStyle.Linear)
			end

			local function update()
				local mine = car:GetAttribute("OwnerUserId") == LocalPlayer.UserId
				gui.Enabled = mine
				if not mine then
					return
				end
				local problemId = car:GetAttribute("ProblemId")
				local state = car:GetAttribute("State")
				local problemName = if type(problemId) == "string" then Localizer.t("problem_" .. problemId) else ""
				problemLabel.Text = "🔧 " .. problemName
				stateLabel.Text = if type(state) == "string" then Localizer.t("car_state_" .. state) else ""
				track.Visible = state == "InBay"
				updateProgress()
			end
			entry.update = update

			local conns: { RBXScriptConnection } = entry.conns
			for _, attribute in { "OwnerUserId", "ProblemId", "State" } do
				table.insert(conns, car:GetAttributeChangedSignal(attribute):Connect(update))
			end
			table.insert(conns, car:GetAttributeChangedSignal("RepairProgress"):Connect(updateProgress))
			update()
		end)
	end

	local function detach(child: Instance)
		local entry = entries[child]
		if entry == nil then
			return
		end
		entries[child] = nil
		entry.removed = true
		for _, conn in entry.conns do
			conn:Disconnect()
		end
		if entry.gui then
			entry.gui:Destroy()
		end
	end

	cars.ChildAdded:Connect(attach)
	cars.ChildRemoved:Connect(detach)
	for _, child in cars:GetChildren() do
		attach(child)
	end

	Localizer.onLangChanged(function()
		for _, entry in entries do
			if entry.update then
				entry.update()
			end
		end
	end)
end

return CarBillboards
