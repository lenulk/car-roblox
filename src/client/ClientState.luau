--!strict
-- Holds the latest snapshot from the server. Controllers read ClientState.snapshot and
-- subscribe with ClientState.onChanged(fn) (fn is called immediately if a snapshot already exists).

local Remotes = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Remotes"))

local ClientState = {}
ClientState.snapshot = nil :: any

local changed = Instance.new("BindableEvent")

function ClientState.onChanged(fn: (snapshot: any) -> ()): RBXScriptConnection
	local connection = changed.Event:Connect(fn)
	if ClientState.snapshot then
		task.spawn(fn, ClientState.snapshot)
	end
	return connection
end

function ClientState.lang(): string
	local s = ClientState.snapshot
	return if s and s.settings and s.settings.lang then s.settings.lang else "th"
end

Remotes.get("DataChanged").OnClientEvent:Connect(function(snapshot)
	ClientState.snapshot = snapshot
	changed:Fire(snapshot)
end)
-- The server's first push can race this listener; ask once we are surely listening.
Remotes.get("RequestSnapshot"):FireServer()

return ClientState
