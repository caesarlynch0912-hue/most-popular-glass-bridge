--!strict
-- BridgeConfig
-- Layout, timing and sounds for the quiz glass bridge ("which is more popular?" style).
-- Container: ReplicatedStorage.Shared

local TILE_SIZE = Vector3.new(12, 1, 12)

return {
	ROW_COUNT = 67,
	-- Each row is two tiles side by side, with a gap so nobody can stand on both at once
	TILE_SIZE = TILE_SIZE,
	CENTER_GAP = 3,
	-- Empty space between one row and the next (players hop across)
	ROW_GAP = 3,
	-- Front edge of the bridge: the far edge of the 100x100 lobby baseplate, top surface at Y = 0
	BRIDGE_START = Vector3.new(0, -TILE_SIZE.Y / 2, 50),

	-- A safe checkpoint platform after every N rows (0 = no checkpoints). Falling respawns you
	-- at the last one you reached; winning or leaving resets it.
	CHECKPOINT_INTERVAL = 10,
	CHECKPOINT_DEPTH = 12,

	-- Bright tile backgrounds, cycled along the bridge
	TILE_COLORS = {
		Color3.fromRGB(235, 50, 50),
		Color3.fromRGB(150, 70, 220),
		Color3.fromRGB(250, 215, 40),
		Color3.fromRGB(40, 210, 230),
		Color3.fromRGB(70, 200, 80),
		Color3.fromRGB(35, 35, 45),
		Color3.fromRGB(40, 90, 230),
		Color3.fromRGB(240, 90, 170),
		Color3.fromRGB(255, 140, 40),
	},

	-- Spawners on the lobby's raised spawn plaza, right in front of the first row
	SPAWN_PLAZA_HEIGHT = 1,
	SPAWN_COUNT = 3,
	SPAWN_SPACING = 8,
	SPAWN_DISTANCE_FROM_BRIDGE = 10,

	-- If the images/text on the tiles appear upside down, set this to true
	TILE_SURFACE_FLIPPED = false,

	ROUND_SECONDS = 120,
	BROKEN_TILE_RESET_SECONDS = 4,
	KILL_HEIGHT = -40,
	RESPAWN_SECONDS = 2,
	-- Time on the finish platform to celebrate before being sent back to the lobby
	CELEBRATE_SECONDS = 3,

	-- Sounds (all free Roblox-licensed audio from the Creator Store); "" for silence
	GLASS_BREAK_SOUND_ID = "rbxassetid://118987440163311", -- glass_shatter_01
	GLASS_BREAK_VOLUME = 1,
	WIN_SOUND_ID = "rbxassetid://1836473422", -- Victory Fanfare Sting (APM)
	CHECKPOINT_SOUND_ID = "rbxassetid://1840076509", -- Through the Roof sting (APM)
	MUSIC_ID = "rbxassetid://1835965883", -- Happy Carrousel (APM), loops
	MUSIC_VOLUME = 0.3,
}
