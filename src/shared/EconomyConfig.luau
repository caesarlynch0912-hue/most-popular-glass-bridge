--!strict
-- EconomyConfig
-- Coin rewards and the lobby's AFK zone. Coins live in leaderstats and are saved between
-- visits by DataService.
-- Container: ReplicatedStorage.Shared

local AFK_INTERVAL_SECONDS = 30

return {
	-- Paid the first time you reach each row during a run (a run ends when you win)
	COINS_PER_ROW = 1,
	-- Extra coins for reaching the trophy
	FINISH_BONUS_COINS = 133,

	-- Standing in the AFK zone pays AFK_COINS for every full AFK_INTERVAL_SECONDS inside it.
	-- Leaving the zone resets the timer.
	AFK_COINS = 10,
	AFK_INTERVAL_SECONDS = AFK_INTERVAL_SECONDS,
	-- How the interval reads on signs and messages, e.g. "30 sec" or "1 min"
	AFK_INTERVAL_TEXT = if AFK_INTERVAL_SECONDS % 60 == 0
		then `{AFK_INTERVAL_SECONDS // 60} min`
		else `{AFK_INTERVAL_SECONDS} sec`,
	-- Floor area of the zone at the back of the lobby (Y is ignored; any height counts)
	AFK_ZONE_CENTER = Vector3.new(0, 0, -32),
	AFK_ZONE_SIZE = Vector3.new(28, 0, 26),
}
