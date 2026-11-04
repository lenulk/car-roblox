--!strict
-- Developer Products (Robux). id 0 = not created yet -> hidden in the shop (shown with a TEST tag in Studio).
-- The server owns every grant; the client only prompts the purchase. See PurchaseService.

export type CashPack = { key: string, id: number, robux: number, minutes: number, minimum: number }
export type Boost = { key: string, id: number, robux: number, minutes: number, mult: number }
export type Instant = { key: string, id: number, robux: number }

local CashPacks: { CashPack } = {
	-- amount = max(minimum, floor(incomePerMinute * minutes)), rounded to 2 significant digits
	{ key = "CashS", id = 0, robux = 25, minutes = 10, minimum = 5000 },
	{ key = "CashM", id = 0, robux = 75, minutes = 35, minimum = 20000 },
	{ key = "CashL", id = 0, robux = 200, minutes = 100, minimum = 60000 },
	{ key = "CashXL", id = 0, robux = 500, minutes = 280, minimum = 180000 },
}

local Boosts: { Boost } = {
	{ key = "Boost2x", id = 0, robux = 35, minutes = 15, mult = 2 }, -- stacks: buying again adds time
}

local Instants: { Instant } = {
	{ key = "InstantRepair", id = 0, robux = 15 }, -- finishes every repair in progress
}

local Products = {
	-- Studio only: products/passes with id 0 are still shown, and buying them runs the real grant code through
	-- the DebugPurchase remote instead of MarketplaceService (so everything is testable before ids exist).
	DEBUG_FAKE_IN_STUDIO = true,

	CashPacks = CashPacks,
	Boosts = Boosts,
	Instant = Instants,

	-- filled below
	byKey = {} :: { [string]: any },
	byId = {} :: { [number]: any },
}

-- kind of grant handler (PurchaseService.registerKind) for each product list
local function index(list: { any }, kind: string)
	for _, entry in list do
		entry.kind = kind
		Products.byKey[entry.key] = entry
		if entry.id ~= 0 then
			Products.byId[entry.id] = entry
		end
	end
end

index(CashPacks, "cash")
index(Boosts, "boost")
index(Instants, "instantRepair")

return Products
