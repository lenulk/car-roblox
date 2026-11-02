--!strict
-- Loads every controller and starts it. One broken controller must never stop the others.

local Client = script.Parent :: Instance

-- Require ClientState first so the DataChanged listener is connected as early as possible.
local okState, stateError = pcall(function()
	require(Client:WaitForChild("ClientState") :: ModuleScript)
end)
if not okState then
	warn("[Client] ClientState failed to load: " .. tostring(stateError))
end

local Controllers = Client:WaitForChild("Controllers")

for _, child in Controllers:GetChildren() do
	if child:IsA("ModuleScript") then
		local module: ModuleScript = child
		task.spawn(function()
			local okRequire, controller = pcall(require, module)
			if not okRequire then
				warn(`[Client] Controller {module.Name} failed to load: {controller}`)
				return
			end
			local controllerTable: any = controller
			if type(controllerTable) ~= "table" or type(controllerTable.start) ~= "function" then
				warn(`[Client] Controller {module.Name} has no start()`)
				return
			end
			local okStart, startError = pcall(controllerTable.start)
			if not okStart then
				warn(`[Client] Controller {module.Name} failed to start: {startError}`)
			end
		end)
	end
end
