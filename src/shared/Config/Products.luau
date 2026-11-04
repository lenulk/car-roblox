--!strict
-- Developer Products (Robux). id 0 = not created yet -> hidden in the shop (shown with a TEST tag in Studio).
-- The server owns every grant; the client only prompts the purchase. See PurchaseService.

export type CashPack = { key: string, id: number, robux: number, minutes: number, minimum: number }
export type Boost = { key: string, id: number, robux: number, minutes: number, mult: number }
export type Instant = { key: string, id: number, robux: number }
-- One-time Robux items. grant: part = "category:optionId" (ownedParts), theme, car, decor, money (bought cash, not earned).
-- once = name of a boolean Data field that makes the item buyable a single time (Starter Pack).
export type ItemGrant = { part: string?, theme: string?, car: string?, decor: string?, money: number? }
export type Item = { key: string, id: number, robux: number, grant: ItemGrant, once: string? }

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

-- One-time: owning it already -> still PurchaseGranted, notify "already owned", nothing else changes.
local Items: { Item } = {
	{ key = "PaintChrome", id = 0, robux = 49, grant = { part = "paint:Chrome" } },
	{ key = "PaintGold", id = 0, robux = 49, grant = { part = "paint:Gold" } },
	{ key = "PaintRainbow", id = 0, robux = 49, grant = { part = "paint:Rainbow" } },
	{ key = "NeonRainbow", id = 0, robux = 39, grant = { part = "neon:Rainbow" } },
	{ key = "SmokeGalaxy", id = 0, robux = 39, grant = { part = "smoke:Galaxy" } },
	{ key = "ThemeGold", id = 0, robux = 149, grant = { theme = "GoldGarage" } },
	{ key = "CarHyper", id = 0, robux = 399, grant = { car = "Hyper" } },
	{ key = "StarterPack", id = 0, robux = 49, grant = { money = 25000, part = "paint:Gold" }, once = "starterPackBought" },
	-- storefront decorations (Config/Decor.luau links to these through robuxProduct)
	{ key = "DecorBear", id = 0, robux = 99, grant = { decor = "MascotBear" } },
	{ key = "DecorRobot", id = 0, robux = 149, grant = { decor = "MechRobot" } },
	{ key = "DecorDragon", id = 0, robux = 199, grant = { decor = "NeonDragon" } },
	{ key = "DecorGold", id = 0, robux = 249, grant = { decor = "GoldStatue" } },
	{ key = "DecorFireworks", id = 0, robux = 129, grant = { decor = "Fireworks" } },
}

local Products = {
	-- Studio only: products/passes with id 0 are still shown, and buying them runs the real grant code through
	-- the DebugPurchase remote instead of MarketplaceService (so everything is testable before ids exist).
	DEBUG_FAKE_IN_STUDIO = true,

	CashPacks = CashPacks,
	Boosts = Boosts,
	Instant = Instants,
	Items = Items,

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
index(Items, "unlock")

return Products
