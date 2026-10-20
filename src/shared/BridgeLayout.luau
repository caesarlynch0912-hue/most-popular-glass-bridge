--!strict
-- BridgeLayout
-- Bridge geometry shared by the server (building, teleports) and the client (progress bar).
-- Along +Z: lobby | gap | row 1 | gap | row 2 ... row 10 | gap | checkpoint 1 | gap | row 11 ...
-- Container: ReplicatedStorage.Shared

local BridgeConfig = require(script.Parent.BridgeConfig)

local TILE_DEPTH = BridgeConfig.TILE_SIZE.Z
local GAP = BridgeConfig.ROW_GAP
local INTERVAL = BridgeConfig.CHECKPOINT_INTERVAL
local ROW_COUNT = BridgeConfig.ROW_COUNT

local BridgeLayout = {}

-- Checkpoints sit after rows INTERVAL, 2*INTERVAL, ... but never after the last row
BridgeLayout.CHECKPOINT_COUNT = if INTERVAL > 0 then math.floor((ROW_COUNT - 1) / INTERVAL) else 0

local function checkpointsBeforeRow(index: number): number
	if INTERVAL <= 0 then
		return 0
	end
	return math.min(math.floor((index - 1) / INTERVAL), BridgeLayout.CHECKPOINT_COUNT)
end

function BridgeLayout.rowFrontZ(index: number): number
	return BridgeConfig.BRIDGE_START.Z
		+ GAP
		+ (index - 1) * (TILE_DEPTH + GAP)
		+ checkpointsBeforeRow(index) * (BridgeConfig.CHECKPOINT_DEPTH + GAP)
end

function BridgeLayout.rowCenterZ(index: number): number
	return BridgeLayout.rowFrontZ(index) + TILE_DEPTH / 2
end

-- Row index a checkpoint comes after (checkpoint 1 -> row 10)
function BridgeLayout.checkpointAfterRow(checkpoint: number): number
	return checkpoint * INTERVAL
end

function BridgeLayout.checkpointCenterZ(checkpoint: number): number
	local row = BridgeLayout.checkpointAfterRow(checkpoint)
	return BridgeLayout.rowFrontZ(row) + TILE_DEPTH + GAP + BridgeConfig.CHECKPOINT_DEPTH / 2
end

-- Z where the last row ends and the finish platform begins
function BridgeLayout.bridgeEndZ(): number
	return BridgeLayout.rowFrontZ(ROW_COUNT) + TILE_DEPTH + GAP
end

-- Furthest row a position has reached: 0 = still in the lobby, ROW_COUNT = past the last row
function BridgeLayout.rowAtZ(z: number): number
	local reached = 0
	for index = 1, ROW_COUNT do
		if z >= BridgeLayout.rowFrontZ(index) then
			reached = index
		else
			break
		end
	end
	return reached
end

-- 0 at the start of the bridge, 1 at the finish
function BridgeLayout.progressAtZ(z: number): number
	local startZ = BridgeConfig.BRIDGE_START.Z
	return math.clamp((z - startZ) / (BridgeLayout.bridgeEndZ() - startZ), 0, 1)
end

return BridgeLayout
