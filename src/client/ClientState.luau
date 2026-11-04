--!strict
-- Holds the latest snapshot from the server. Controllers read ClientState.snapshot and
-- subscribe with ClientState.onChanged(fn) (fn is called immediately if a snapshot already exists).

local Remotes = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Remotes"))

local ClientState = {}
ClientState.snapshot = nil :: any
ClientState.receivedAt = os.clock() -- local clock when the latest snapshot arrived

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

-- Seconds of paid income boost left (counted down locally from the snapshot's server clock), 0 = none.
function ClientState.boostRemaining(): number
	local s = ClientState.snapshot
	if not s or type(s.boostEndsAt) ~= "number" or type(s.serverTime) ~= "number" then
		return 0
	end
	local serverNow = s.serverTime + (os.clock() - ClientState.receivedAt)
	return math.max(0, s.boostEndsAt - serverNow)
end

Remotes.get("DataChanged").OnClientEvent:Connect(function(snapshot)
	ClientState.snapshot = snapshot
	ClientState.receivedAt = os.clock()
	changed:Fire(snapshot)
end)
-- The server's first push can race this listener; ask once we are surely listening.
Remotes.get("RequestSnapshot"):FireServer()

return ClientState
