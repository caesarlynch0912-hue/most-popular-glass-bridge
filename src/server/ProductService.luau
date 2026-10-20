--!strict
-- ProductService
-- Handles developer product receipts and free Studio test purchases (see Shared.Products).
-- Cheats apply here; Items (Push / Kill All / Flying Carpet) are handed to ItemService.
-- Container: ServerScriptService.Server

----- Services -----
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

----- Dependencies -----
local BridgeService = require(script.Parent.BridgeService)
local ItemService = require(script.Parent.ItemService)
local Products = require(ReplicatedStorage.Shared.Products)
local Remotes = require(script.Parent.Remotes)

----- Variables -----
-- Receipts already granted on this server. Nothing in this game is saved, so in-memory is enough
-- to stop a receipt that Roblox re-sends from being granted twice.
local grantedPurchases: { [string]: boolean } = {}

local ProductService = {}

----- Private Functions -----
-- Each cheat returns true once it has been applied
local cheats: { [string]: (Player) -> boolean } = {
	reveal1 = function(player)
		return BridgeService.revealRows(player, 1)
	end,
	reveal5 = function(player)
		return BridgeService.revealRows(player, 5)
	end,
	skip5 = function(player)
		return BridgeService.skipRows(player, 5)
	end,
	skipEnd = function(player)
		return BridgeService.skipToEnd(player)
	end,
	shield = function(player)
		BridgeService.addShield(player)
		return true
	end,
}

local function grant(player: Player, product: Products.Product): boolean
	if product.category == "Items" then
		return ItemService.grant(player, product)
	end

	local handler = cheats[product.key]
	if not handler then
		warn(`[ProductService] No handler for "{product.key}"`)
		return false
	end
	local ok, applied = pcall(handler, player)
	if not ok then
		warn(`[ProductService] "{product.key}" errored:`, applied)
		return false
	end
	if applied then
		Remotes.Notify:FireAllClients(`{product.icon} {player.DisplayName} used {product.name}!`, "purchase")
	end
	return applied == true
end

local function processReceipt(receiptInfo: { [string]: any }): Enum.ProductPurchaseDecision
	if grantedPurchases[receiptInfo.PurchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local product = Products.getByProductId(receiptInfo.ProductId)
	if not product then
		warn("[ProductService] Unknown product id:", receiptInfo.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Not granted (e.g. the player was mid-respawn for a skip): Roblox retries the receipt later
	if not grant(player, product) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	grantedPurchases[receiptInfo.PurchaseId] = true
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

----- Public -----
function ProductService.start()
	MarketplaceService.ProcessReceipt = processReceipt

	-- Studio-only: free test "purchases" for products that don't have an ID yet.
	-- RunService:IsStudio() is false on live servers, so this can't be abused in the real game.
	Remotes.TestPurchase.OnServerEvent:Connect(function(player: Player, key: unknown)
		if not RunService:IsStudio() or typeof(key) ~= "string" then
			return
		end
		local product = Products.get(key)
		if product and product.id == 0 then
			grant(player, product)
		end
	end)

	local function onPlayerAdded(player: Player)
		player:SetAttribute("Shields", 0)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return ProductService
