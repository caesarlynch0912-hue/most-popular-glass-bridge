--!strict
-- Server
-- Entry point: environment, lobby, leaderstats (Wins, Coins), the glass bridge, coins/AFK,
-- saved progress, items and the shop.
-- Container: ServerScriptService

local Players = game:GetService("Players")

local BridgeService = require(script.BridgeService)
local CoinService = require(script.CoinService)
local DataService = require(script.DataService)
local EnvironmentService = require(script.EnvironmentService)
local ItemService = require(script.ItemService)
local LobbyBuilder = require(script.LobbyBuilder)
local ProductService = require(script.ProductService)

local function onPlayerAdded(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local wins = Instance.new("IntValue")
	wins.Name = "Wins"
	wins.Parent = leaderstats

	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Parent = leaderstats

	leaderstats.Parent = player
end

local function onPlayerWon(player: Player)
	local leaderstats = player:FindFirstChild("leaderstats")
	local wins = leaderstats and leaderstats:FindFirstChild("Wins")
	if wins and wins:IsA("IntValue") then
		wins.Value += 1
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

EnvironmentService.build()
LobbyBuilder.build()
BridgeService.start(onPlayerWon)
CoinService.start()
DataService.start()
ItemService.start()
ProductService.start()
