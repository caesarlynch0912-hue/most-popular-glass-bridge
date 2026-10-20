--!strict
-- Client
-- Client entry point: HUD, backpack items (carpet / push) and shift lock.
-- Each controller starts in its own thread with its own error handling, so a problem in one
-- (an error, or something it waits for that never arrives) can't stop the others from running.
-- Container: StarterPlayer.StarterPlayerScripts

local CONTROLLERS = { "HudController", "ItemsController", "ShiftLockController" }

for _, name in CONTROLLERS do
	task.spawn(function()
		local ok, err = pcall(function()
			local controller = require(script:WaitForChild(name) :: ModuleScript) :: any
			controller.start()
		end)
		if not ok then
			warn(`[Client] {name} failed to start:`, err)
		end
	end)
end
