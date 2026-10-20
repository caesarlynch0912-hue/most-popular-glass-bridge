--!strict
-- DataService
-- Saves each player's progress in a DataStore: Wins, Coins, unused Glass Shields and owned
-- coin-shop items. Bridge progress (checkpoints, rows) is deliberately NOT saved: every visit
-- starts at the lobby. Game-pass items (Push, Flying Carpet) are remembered by Roblox itself.
--   * loads on join (with retries) and adds the saved values onto the live leaderstats
--   * saves on leave, every AUTOSAVE_SECONDS and when the server shuts down (BindToClose)
--   * uses UpdateAsync, and never saves for a player whose data failed to load, so a DataStore
--     outage can't overwrite real progress with zeros
-- In Studio, saving only works in a published place with "Enable Studio Access to API Services"
-- turned on (Game Settings > Security). Without it the game still runs, it just doesn't save.
-- Container: ServerScriptService.Server

----- Services -----
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

----- Dependencies -----
local Remotes = require(script.Parent.Remotes)

----- Constants -----
local STORE_NAME = "PlayerProgress_v1"
local DATA_VERSION = 1
local MAX_ATTEMPTS = 4
local RETRY_BASE_SECONDS = 1.5
local AUTOSAVE_SECONDS = 120
local SHUTDOWN_WAIT_SECONDS = 25

----- Types -----
type SaveData = {
	dataVersion: number,
	wins: number,
	coins: number,
	shields: number,
	-- Coin-shop items the player owns, by item key (the coin shop is empty for now)
	items: { [string]: boolean },
}

----- Variables -----
local store: DataStore? = nil
-- Only players whose data loaded successfully are ever saved
local loaded: { [Player]: boolean } = {}
local ownedItems: { [Player]: { [string]: boolean } } = {}

local DataService = {}

----- Private Functions -----
local function keyFor(player: Player): string
	return `Player_{player.UserId}`
end

local function getStat(player: Player, name: string): IntValue?
	local leaderstats = player:FindFirstChild("leaderstats")
	local stat = leaderstats and leaderstats:FindFirstChild(name)
	return if stat and stat:IsA("IntValue") then stat else nil
end

local function waitForStat(player: Player, name: string): IntValue?
	local leaderstats = player:WaitForChild("leaderstats", 10)
	local stat = leaderstats and leaderstats:WaitForChild(name, 10)
	return if stat and stat:IsA("IntValue") then stat else nil
end

-- Fills in any fields missing from older saves
local function reconcile(raw: any): SaveData
	local data = if typeof(raw) == "table" then raw else {}
	local items = {}
	if typeof(data.items) == "table" then
		for key, owned in data.items do
			if typeof(key) == "string" and owned == true then
				items[key] = true
			end
		end
	end
	return {
		dataVersion = DATA_VERSION,
		wins = if typeof(data.wins) == "number" then data.wins else 0,
		coins = if typeof(data.coins) == "number" then data.coins else 0,
		shields = if typeof(data.shields) == "number" then data.shields else 0,
		items = items,
	}
end

local function snapshot(player: Player): SaveData
	local wins = getStat(player, "Wins")
	local coins = getStat(player, "Coins")
	local shields = player:GetAttribute("Shields")
	return {
		dataVersion = DATA_VERSION,
		wins = if wins then wins.Value else 0,
		coins = if coins then coins.Value else 0,
		shields = if typeof(shields) == "number" then shields else 0,
		items = table.clone(ownedItems[player] or {}),
	}
end

-- Runs a DataStore call with retries and a growing back-off
local function withRetries<T>(description: string, call: () -> T): (boolean, T?)
	for attempt = 1, MAX_ATTEMPTS do
		local ok, result = pcall(call)
		if ok then
			return true, result
		end
		warn(`[DataService] {description} failed (attempt {attempt}/{MAX_ATTEMPTS}):`, result)
		if attempt < MAX_ATTEMPTS then
			task.wait(RETRY_BASE_SECONDS * attempt)
		end
	end
	return false, nil
end

local function load(player: Player)
	local dataStore = store
	if not dataStore then
		return
	end
	local ok, raw = withRetries(`Loading {player.Name}`, function()
		return dataStore:GetAsync(keyFor(player))
	end)
	if not player.Parent then
		return
	end
	if not ok then
		if RunService:IsStudio() then
			Remotes.Notify:FireClient(player, "⚠️ Progress isn't saving in this Studio test.", "error")
		else
			player:Kick("Couldn't load your progress. Please rejoin in a moment!")
		end
		return
	end

	local data = reconcile(raw)
	-- Add onto anything earned while loading (e.g. AFK coins in the first seconds)
	local wins = waitForStat(player, "Wins")
	local coins = waitForStat(player, "Coins")
	if wins then
		wins.Value += data.wins
	end
	if coins then
		coins.Value += data.coins
	end
	local shields = player:GetAttribute("Shields")
	player:SetAttribute("Shields", (if typeof(shields) == "number" then shields else 0) + data.shields)
	-- Merge in case something was granted while loading
	local items = ownedItems[player] or {}
	for key in data.items do
		items[key] = true
	end
	ownedItems[player] = items
	loaded[player] = true
end

local function save(player: Player)
	local dataStore = store
	if not dataStore or not loaded[player] then
		return
	end
	local data = snapshot(player)
	withRetries(`Saving {player.Name}`, function()
		return dataStore:UpdateAsync(keyFor(player), function()
			return data
		end)
	end)
end

----- Public -----
-- For the coin shop (once it sells things): owned items are saved with the player's progress
function DataService.ownsItem(player: Player, key: string): boolean
	local items = ownedItems[player]
	return items ~= nil and items[key] == true
end

function DataService.grantItem(player: Player, key: string)
	local items = ownedItems[player] or {}
	items[key] = true
	ownedItems[player] = items
end

function DataService.start()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[DataService] DataStores unavailable, progress won't save:", result)
	end

	Players.PlayerAdded:Connect(function(player)
		load(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		save(player)
		loaded[player] = nil
		ownedItems[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_SECONDS)
			for _, player in Players:GetPlayers() do
				task.spawn(save, player)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for _, player in Players:GetPlayers() do
			pending += 1
			task.spawn(function()
				save(player)
				pending -= 1
			end)
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < SHUTDOWN_WAIT_SECONDS do
			task.wait(0.25)
		end
	end)
end

return DataService
