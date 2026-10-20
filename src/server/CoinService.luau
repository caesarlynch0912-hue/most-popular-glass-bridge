--!strict
-- CoinService
-- Gives out coins (leaderstats "Coins") and runs the AFK zone.
--   * CoinService.add(player, amount) is used by the bridge for row and finish rewards
--   * Standing in the AFK zone pays AFK_COINS every AFK_INTERVAL_SECONDS. The player attribute
--     "AfkRewardAt" (server time of the next payout) drives the HUD countdown; it is nil outside.
-- Container: ServerScriptService.Server

----- Services -----
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

----- Dependencies -----
local EconomyConfig = require(ReplicatedStorage.Shared.EconomyConfig)
local Remotes = require(script.Parent.Remotes)

----- Constants -----
local AFK_CHECK_SECONDS = 1
local AFK_ATTRIBUTE = "AfkRewardAt"

local CoinService = {}

----- Private Functions -----
local function getCoinsValue(player: Player): IntValue?
	local leaderstats = player:FindFirstChild("leaderstats")
	local coins = leaderstats and leaderstats:FindFirstChild("Coins")
	return if coins and coins:IsA("IntValue") then coins else nil
end

local function isInAfkZone(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return false
	end
	local offset = root.Position - EconomyConfig.AFK_ZONE_CENTER
	local half = EconomyConfig.AFK_ZONE_SIZE / 2
	return math.abs(offset.X) <= half.X and math.abs(offset.Z) <= half.Z and root.Position.Y < 20
end

local function updateAfk(player: Player, now: number)
	local rewardAt = player:GetAttribute(AFK_ATTRIBUTE)
	if not isInAfkZone(player) then
		if rewardAt ~= nil then
			player:SetAttribute(AFK_ATTRIBUTE, nil)
		end
		return
	end
	if typeof(rewardAt) ~= "number" then
		-- Just walked in: start the timer
		player:SetAttribute(AFK_ATTRIBUTE, now + EconomyConfig.AFK_INTERVAL_SECONDS)
		Remotes.Notify:FireClient(
			player,
			`💤 AFK zone: +{EconomyConfig.AFK_COINS} coins every {EconomyConfig.AFK_INTERVAL_TEXT}`,
			"coin"
		)
	elseif now >= rewardAt then
		CoinService.add(player, EconomyConfig.AFK_COINS)
		player:SetAttribute(AFK_ATTRIBUTE, rewardAt + EconomyConfig.AFK_INTERVAL_SECONDS)
	end
end

----- Public -----
function CoinService.add(player: Player, amount: number)
	local coins = getCoinsValue(player)
	if coins and amount > 0 then
		coins.Value += amount
	end
end

function CoinService.start()
	task.spawn(function()
		while true do
			local now = workspace:GetServerTimeNow()
			for _, player in Players:GetPlayers() do
				updateAfk(player, now)
			end
			task.wait(AFK_CHECK_SECONDS)
		end
	end)
end

return CoinService
