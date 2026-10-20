--!strict
-- Products
-- Everything sold in the game. Create each one in the Creator Dashboard (your experience >
-- Monetization) and paste its ID into `id`:
--   kind "DeveloperProduct" -> Developer Products (bought again every time it's used)
--   kind "GamePass"         -> Passes (bought once, owned forever)
-- While an id is 0, buying in Studio grants it for free so you can test it;
-- in a live game the button says the item isn't available yet.
--
-- "Cheats" apply the moment they're bought. "Items" are Tools in the player's backpack:
-- locked (🔒) until owned, and equipping a locked one opens the purchase prompt.
-- "Coins" is the coin shop (paid with in-game coins, not Robux) - empty for now.
-- Container: ReplicatedStorage.Shared

export type Category = "Cheats" | "Items" | "Coins"
export type Kind = "DeveloperProduct" | "GamePass"

export type Product = {
	key: string,
	name: string,
	description: string,
	icon: string,
	category: Category,
	kind: Kind,
	price: number, -- shown until the real price loads from Roblox
	id: number,
}

local list: { Product } = {
	{
		key = "reveal1",
		name = "Reveal Next Row",
		description = "The safe tile in your next row glows for 10 seconds.",
		icon = "👁️",
		category = "Cheats",
		kind = "DeveloperProduct",
		price = 9,
		id = 0,
	},
	{
		key = "reveal5",
		name = "Reveal 5 Rows",
		description = "Shows the safe path for your next 5 rows.",
		icon = "🔮",
		category = "Cheats",
		kind = "DeveloperProduct",
		price = 29,
		id = 0,
	},
	{
		key = "skip5",
		name = "Skip 5 Rows",
		description = "Teleports you 5 rows ahead onto a safe tile.",
		icon = "⏩",
		category = "Cheats",
		kind = "DeveloperProduct",
		price = 25,
		id = 0,
	},
	{
		key = "skipEnd",
		name = "Skip to End",
		description = "Teleports you straight to the trophy.",
		icon = "🏆",
		category = "Cheats",
		kind = "DeveloperProduct",
		price = 99,
		id = 0,
	},
	{
		key = "shield",
		name = "Glass Shield",
		description = "Next time you pick wrong, you land on the safe tile instead.",
		icon = "🛡️",
		category = "Cheats",
		kind = "DeveloperProduct",
		price = 19,
		id = 0,
	},
	{
		key = "push",
		name = "Push",
		description = "Shove the player in front of you. Yours forever.",
		icon = "👊",
		category = "Items",
		kind = "GamePass",
		price = 50,
		id = 0,
	},
	{
		key = "killAll",
		name = "Kill All",
		description = "Everyone else on the server dies instantly. One use per purchase.",
		icon = "💀",
		category = "Items",
		kind = "DeveloperProduct",
		price = 150,
		id = 0,
	},
	{
		key = "carpet",
		name = "Flying Carpet",
		description = "Equip it to fly anywhere, right over the bridge. Yours forever.",
		icon = "🧞",
		category = "Items",
		kind = "GamePass",
		price = 500,
		id = 0,
	},
}

local byKey: { [string]: Product } = {}
for _, product in list do
	byKey[product.key] = product
end

local Products = {}

Products.list = list
Products.CATEGORIES = { "Cheats", "Items", "Coins" } :: { Category }

function Products.get(key: string): Product?
	return byKey[key]
end

local function findById(kind: Kind, id: number): Product?
	if id == 0 then
		return nil
	end
	for _, product in list do
		if product.kind == kind and product.id == id then
			return product
		end
	end
	return nil
end

function Products.getByProductId(productId: number): Product?
	return findById("DeveloperProduct", productId)
end

function Products.getByGamePassId(gamePassId: number): Product?
	return findById("GamePass", gamePassId)
end

-- Player attribute the server sets to true once a game pass item is owned
function Products.ownedAttribute(key: string): string
	return `Owns_{key}`
end

return Products
