--!strict
-- Client helper for one-time Robux items (Config/Products.Items) used by Tuning, Themes, Shop, Decor and the
-- Starter Pack popup: availability, the price text and the purchase prompt. The server owns every price and grant;
-- this only shows the Robux price and asks Roblox to prompt the purchase (or, in Studio with
-- Products.DEBUG_FAKE_IN_STUDIO, fires the DebugPurchase remote so the real grant code runs).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes: any = require(Shared:WaitForChild("Remotes") :: ModuleScript)
local Format: any = require(Shared:WaitForChild("Format") :: ModuleScript)
local Products: any = require(Shared:WaitForChild("Config"):WaitForChild("Products") :: ModuleScript)

local RobuxBuy = {}

RobuxBuy.GLYPH = utf8.char(0xE002)
RobuxBuy.GOLD = Color3.fromRGB(255, 205, 60) -- border / price colour of Robux-only things
RobuxBuy.GOLD_DARK_TEXT = Color3.fromRGB(60, 40, 0)
RobuxBuy.BUTTON = Color3.fromRGB(38, 160, 78) -- the green Robux buy button used everywhere

local CLICK_DEBOUNCE = 1

local priceCache: { [number]: number | boolean } = {}
local pricePending: { [number]: { () -> () } } = {}
local lastClick: { [string]: number } = {}

-- A product that can be bought here: its id exists, or Studio testing is on.
function RobuxBuy.available(productKey: string): boolean
	local entry = Products.byKey[productKey]
	if not entry then
		return false
	end
	if entry.id ~= 0 then
		return true
	end
	return RunService:IsStudio() and Products.DEBUG_FAKE_IN_STUDIO == true
end

-- true when the product has no id yet and is only buyable through the Studio test path
function RobuxBuy.isTest(productKey: string): boolean
	local entry = Products.byKey[productKey]
	return entry ~= nil and entry.id == 0
end

-- The real Robux price (cached); `onReady` is called once it arrives if it was not cached yet.
local function fetchPrice(id: number, onReady: (() -> ())?)
	if id == 0 or priceCache[id] ~= nil then
		return
	end
	local waiting = pricePending[id]
	if waiting then
		if onReady then
			table.insert(waiting, onReady)
		end
		return
	end
	pricePending[id] = if onReady then { onReady } else {}
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(id, Enum.InfoType.Product)
		end)
		local price: any = if ok and type(info) == "table" then info.PriceInRobux else nil
		priceCache[id] = if type(price) == "number" then price else false
		local callbacks = pricePending[id]
		pricePending[id] = nil
		if callbacks then
			for _, fn in callbacks do
				fn()
			end
		end
	end)
end

-- Robux price as a number (real price when known, else the config fallback), nil for unknown products.
function RobuxBuy.price(productKey: string, onReady: (() -> ())?): number?
	local entry = Products.byKey[productKey]
	if not entry then
		return nil
	end
	fetchPrice(entry.id, onReady)
	local cached = priceCache[entry.id]
	if type(cached) == "number" then
		return cached
	end
	return entry.robux
end

-- "R$ 49" with the Robux glyph. onReady re-renders the caller when the real price arrives.
function RobuxBuy.priceText(productKey: string, onReady: (() -> ())?): string
	local price = RobuxBuy.price(productKey, onReady)
	if price then
		return RobuxBuy.GLYPH .. " " .. Format.number(price)
	end
	return RobuxBuy.GLYPH
end

-- Prompts the purchase (or the Studio test purchase). Debounced per product.
function RobuxBuy.buy(productKey: string)
	local entry = Products.byKey[productKey]
	if not entry or not RobuxBuy.available(productKey) then
		return
	end
	local now = os.clock()
	if lastClick[productKey] and now - lastClick[productKey] < CLICK_DEBOUNCE then
		return
	end
	lastClick[productKey] = now
	if entry.id == 0 then
		Remotes.get("DebugPurchase"):FireServer(productKey)
		return
	end
	local ok, err = pcall(function()
		MarketplaceService:PromptProductPurchase(Players.LocalPlayer, entry.id)
	end)
	if not ok then
		warn("[RobuxBuy] Purchase prompt failed: " .. tostring(err))
	end
end

return RobuxBuy
