--!strict
-- BridgeService
-- Builds the "which is more popular?" bridge and runs it:
--   * rows of two image tiles over the void; the server alone knows which tile is safe
--   * steel girders and cross beams under the glass, row numbers along the side
--   * a checkpoint platform every CHECKPOINT_INTERVAL rows (respawn there after falling)
--   * a finish stage with the #1 trophy, confetti and a short celebration
--   * reshuffles every ROUND_SECONDS (workspace attribute "RoundEndsAt" drives the HUD timer)
--   * coins: +COINS_PER_ROW the first time a row is reached in a run, +FINISH_BONUS_COINS at the end
-- Container: ServerScriptService.Server

----- Services -----
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

----- Dependencies -----
local BridgeConfig = require(ReplicatedStorage.Shared.BridgeConfig)
local BridgeLayout = require(ReplicatedStorage.Shared.BridgeLayout)
local CoinService = require(script.Parent.CoinService)
local EconomyConfig = require(ReplicatedStorage.Shared.EconomyConfig)
local QuestionBank = require(script.Parent.QuestionBank)
local Remotes = require(script.Parent.Remotes)

----- Constants -----
local SAFE_HIGHLIGHT = Color3.fromRGB(90, 255, 120)
local GOLD = Color3.fromRGB(255, 200, 40)
local STEEL = Color3.fromRGB(70, 75, 85)
local CHECKPOINT_BLUE = Color3.fromRGB(60, 170, 255)
local SHARD_COUNT = 10
local SAFE_HIGHLIGHT_SECONDS = 5
local SURFACE_PIXELS_PER_STUD = 40
local FINISH_DEPTH = 30
local CHECKPOINT_ATTRIBUTE = "Checkpoint"

----- Types -----
type Tile = {
	part: BasePart,
	rowIndex: number,
	baseColor: Color3,
	image: ImageLabel,
	label: TextLabel,
	surface: SurfaceGui,
}

type Row = {
	tiles: { Tile },
}

----- Variables -----
local rows: { Row } = {}
local safeTiles: { [BasePart]: boolean } = {}
local brokenTiles: { [BasePart]: boolean } = {}
-- Bumped on every highlight so only the latest one's timer turns the tile back
local highlightVersion: { [BasePart]: number } = {}
local celebrating: { [Player]: boolean } = {}
-- Furthest row each player has been paid for in their current run (reset when they win)
local paidRow: { [Player]: number } = {}
local spawns: { SpawnLocation } = {}
local checkpointPlatforms: { BasePart } = {}
local finishPlatform: BasePart? = nil
local confetti: ParticleEmitter? = nil
local onPlayerWon: (Player) -> () = function() end

local BridgeService = {}

----- Helpers -----
local function makePart(name: string, size: Vector3, cframe: CFrame, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = parent
	return part
end

-- Scenery: nothing can stand on it, touch it or hit it with a raycast
local function makeDecor(name: string, size: Vector3, cframe: CFrame, parent: Instance): Part
	local part = makePart(name, size, cframe, parent)
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	return part
end

-- A flat sign whose front face points at -Z (towards players walking down the bridge)
local function makeBanner(text: string, size: Vector3, position: Vector3, color: Color3, parent: Instance): Part
	local banner = makeDecor("Banner", size, CFrame.lookAt(position, position - Vector3.zAxis), parent)
	banner.Color = color
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 30
	surface.LightInfluence = 0
	surface.Parent = banner
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Parent = surface
	return banner
end

local function getLivingPlayer(hit: BasePart): (Player?, Humanoid?)
	local character = hit.Parent
	if not character then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil, nil
	end
	return Players:GetPlayerFromCharacter(character), humanoid
end

local function getLivingCharacter(player: Player): (Model?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil
	end
	return character, root
end

-- Stand a character on top of a part, facing down the bridge
local function teleportOnto(character: Model, part: BasePart)
	local position = part.Position + Vector3.new(0, part.Size.Y / 2 + 3, 0)
	character:PivotTo(CFrame.lookAt(position, position + Vector3.zAxis))
end

local function getSpawnCFrame(): CFrame
	local spawnLocation = spawns[math.random(1, #spawns)]
	return spawnLocation.CFrame + Vector3.new(0, 4, 0)
end

local function getCheckpoint(player: Player): number
	local checkpoint = player:GetAttribute(CHECKPOINT_ATTRIBUTE)
	return if typeof(checkpoint) == "number" then checkpoint else 0
end

----- Tiles -----
local function setTileIntact(tile: Tile)
	brokenTiles[tile.part] = nil
	tile.part.CanCollide = true
	tile.part.Transparency = 0
	tile.part.Color = tile.baseColor
	tile.surface.Enabled = true
end

local function spawnShards(part: BasePart)
	for _ = 1, SHARD_COUNT do
		local shard = Instance.new("Part")
		shard.Size = Vector3.new(math.random(10, 25) / 10, 0.2, math.random(10, 25) / 10)
		shard.Material = Enum.Material.Glass
		shard.Color = part.Color
		shard.CanCollide = false
		shard.CanQuery = false
		shard.CanTouch = false
		shard.CFrame = part.CFrame
			* CFrame.new(math.random(-50, 50) / 10, 0, math.random(-50, 50) / 10)
			* CFrame.Angles(math.random() * math.pi, math.random() * math.pi, 0)
		shard.Parent = workspace
		shard.AssemblyLinearVelocity = Vector3.new(math.random(-15, 15), math.random(0, 15), math.random(-15, 15))
		Debris:AddItem(shard, 2)
	end

	if BridgeConfig.GLASS_BREAK_SOUND_ID ~= "" then
		local sound = Instance.new("Sound")
		sound.SoundId = BridgeConfig.GLASS_BREAK_SOUND_ID
		sound.Volume = BridgeConfig.GLASS_BREAK_VOLUME
		sound.Parent = part
		sound:Play()
		Debris:AddItem(sound, 3)
	end
end

local function breakTile(tile: Tile)
	brokenTiles[tile.part] = true
	spawnShards(tile.part)
	tile.part.CanCollide = false
	tile.part.Transparency = 1
	tile.surface.Enabled = false

	task.delay(BridgeConfig.BROKEN_TILE_RESET_SECONDS, function()
		if brokenTiles[tile.part] then
			setTileIntact(tile)
		end
	end)
end

local function getSafeTile(rowIndex: number): Tile?
	local row = rows[rowIndex]
	if not row then
		return nil
	end
	for _, tile in row.tiles do
		if safeTiles[tile.part] then
			return tile
		end
	end
	return nil
end

local function consumeShield(player: Player): boolean
	local shields = player:GetAttribute("Shields")
	if typeof(shields) ~= "number" or shields <= 0 then
		return false
	end
	player:SetAttribute("Shields", shields - 1)
	return true
end

local function onTileTouched(tile: Tile, hit: BasePart)
	if brokenTiles[tile.part] then
		return
	end
	local player = getLivingPlayer(hit)
	if not player then
		return
	end

	if safeTiles[tile.part] then
		-- Coins for each new row reached this run. Rows before your checkpoint count as paid, so
		-- falling back to a checkpoint (or rejoining at one) never pays the same rows twice.
		local alreadyPaid = math.max(paidRow[player] or 0, BridgeLayout.checkpointAfterRow(getCheckpoint(player)))
		if tile.rowIndex > alreadyPaid then
			paidRow[player] = tile.rowIndex
			CoinService.add(player, EconomyConfig.COINS_PER_ROW)
		end

		-- Briefly reveal the safe side so watchers can learn from whoever goes first
		tile.part.Color = SAFE_HIGHLIGHT
		local version = (highlightVersion[tile.part] or 0) + 1
		highlightVersion[tile.part] = version
		task.delay(SAFE_HIGHLIGHT_SECONDS, function()
			if highlightVersion[tile.part] == version and not brokenTiles[tile.part] then
				tile.part.Color = tile.baseColor
			end
		end)
		return
	end

	breakTile(tile)
	local character = player.Character
	local safeTile = getSafeTile(tile.rowIndex)
	if character and safeTile and consumeShield(player) then
		teleportOnto(character, safeTile.part)
		Remotes.Notify:FireClient(player, "🛡️ Your shield saved you!", "shield")
	else
		Remotes.Notify:FireClient(player, "💥 Wrong one! It was the other side...", "error")
	end
end

local function shuffled<T>(list: { T }): { T }
	local copy = table.clone(list)
	for i = #copy, 2, -1 do
		local j = math.random(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

local function showOption(tile: Tile, image: string, label: string)
	tile.image.Image = image
	tile.image.Visible = image ~= ""
	tile.label.Text = label
	-- With no image, let the text fill the whole tile
	tile.label.Size = if image ~= "" then UDim2.fromScale(1, 0.25) else UDim2.fromScale(1, 1)
	tile.label.Position = if image ~= "" then UDim2.fromScale(0, 0.75) else UDim2.fromScale(0, 0)
end

local function startNewRound()
	local questions = shuffled(QuestionBank)
	table.clear(safeTiles)

	for index, row in rows do
		local question = questions[index]
		local safeSide = math.random(1, 2)

		for side, tile in row.tiles do
			setTileIntact(tile)
			local isSafe = side == safeSide
			if question then
				local option = if isSafe then question.correct else question.wrong
				showOption(tile, option.image, option.label)
			else
				showOption(tile, "", "?")
			end
			if isSafe then
				safeTiles[tile.part] = true
			end
		end
	end

	workspace:SetAttribute("RoundEndsAt", workspace:GetServerTimeNow() + BridgeConfig.ROUND_SECONDS)
	Remotes.Notify:FireAllClients("🔀 The bridge has been reshuffled!", "round")
end

local function createTile(name: string, rowIndex: number, cframe: CFrame, color: Color3, parent: Instance): Tile
	local config = BridgeConfig
	if config.TILE_SURFACE_FLIPPED then
		cframe *= CFrame.Angles(0, math.pi, 0)
	end
	local part = makePart(name, config.TILE_SIZE, cframe, parent)
	part.Color = color

	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Top
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = SURFACE_PIXELS_PER_STUD
	surface.LightInfluence = 0
	surface.Parent = part

	local image = Instance.new("ImageLabel")
	image.Name = "Meme"
	image.AnchorPoint = Vector2.new(0.5, 0)
	image.Position = UDim2.fromScale(0.5, 0.05)
	image.Size = UDim2.fromScale(0.9, 0.68)
	image.BackgroundTransparency = 1
	image.ScaleType = Enum.ScaleType.Fit
	image.Visible = false
	image.Parent = surface

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Parent = surface

	return { part = part, rowIndex = rowIndex, baseColor = color, image = image, label = label, surface = surface }
end

----- Construction -----
local function buildSpawns(folder: Instance)
	local config = BridgeConfig
	-- Remove every other spawn (e.g. the template's grey pad in the middle of the lobby)
	for _, descendant in workspace:GetDescendants() do
		if descendant:IsA("SpawnLocation") then
			descendant:Destroy()
		end
	end

	local spawnZ = config.BRIDGE_START.Z - config.SPAWN_DISTANCE_FROM_BRIDGE
	local firstX = -(config.SPAWN_COUNT - 1) * config.SPAWN_SPACING / 2
	for index = 1, config.SPAWN_COUNT do
		local position = Vector3.new(firstX + (index - 1) * config.SPAWN_SPACING, config.SPAWN_PLAZA_HEIGHT + 0.5, spawnZ)
		local spawnLocation = Instance.new("SpawnLocation")
		spawnLocation.Name = `Spawn{index}`
		spawnLocation.Anchored = true
		spawnLocation.Size = Vector3.new(6, 1, 6)
		-- Spawned players face the way the spawn faces, so point it down the bridge
		spawnLocation.CFrame = CFrame.lookAt(position, position + Vector3.zAxis)
		spawnLocation.Duration = 0
		spawnLocation.Neutral = true
		-- Invisible: the glowing pad under it is drawn by LobbyBuilder
		spawnLocation.Transparency = 1
		spawnLocation.CanCollide = false
		spawnLocation.CanQuery = false
		spawnLocation.Parent = folder
		table.insert(spawns, spawnLocation)
	end
end

local function buildTrophy(baseCFrame: CFrame, parent: Instance): BasePart
	local model = Instance.new("Model")
	model.Name = "Trophy"
	model.Parent = parent

	local upright = CFrame.Angles(0, 0, math.pi / 2) -- cylinders run along X; stand them up

	local pieces = {
		makePart("Base", Vector3.new(7, 1.5, 7), baseCFrame * CFrame.new(0, 0.75, 0), model),
		makePart("Stem", Vector3.new(4, 1.6, 1.6), baseCFrame * CFrame.new(0, 3.5, 0) * upright, model),
		makePart("Cup", Vector3.new(5.5, 7, 7), baseCFrame * CFrame.new(0, 8.25, 0) * upright, model),
		-- Handles touch the cup's side (cup radius 3.5 + handle radius 1.25)
		makePart("LeftHandle", Vector3.new(2.5, 2.5, 2.5), baseCFrame * CFrame.new(-4.75, 9, 0), model),
		makePart("RightHandle", Vector3.new(2.5, 2.5, 2.5), baseCFrame * CFrame.new(4.75, 9, 0), model),
	}
	for _, piece in pieces do
		piece.Color = GOLD
		piece.Material = Enum.Material.Metal
		piece.Reflectance = 0.2
		if piece.Name == "Stem" or piece.Name == "Cup" then
			piece.Shape = Enum.PartType.Cylinder
		elseif piece.Name ~= "Base" then
			piece.Shape = Enum.PartType.Ball
		end
	end

	local cup = pieces[3]
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(6, 3)
	billboard.StudsOffset = Vector3.new(0, 6, 0)
	billboard.LightInfluence = 0
	billboard.Parent = cup

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "#1"
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = GOLD
	label.TextStrokeTransparency = 0
	label.Parent = billboard

	local sparkle = Instance.new("Sparkles")
	sparkle.SparkleColor = GOLD
	sparkle.Parent = cup

	return cup
end

-- Steel girders along both sides plus a cross beam under every row, like a real glass bridge.
-- All non-collidable so they never give anyone a way around the glass.
local function buildSupports(folder: Instance)
	local config = BridgeConfig
	local girderX = config.TILE_SIZE.X + config.CENTER_GAP / 2 + 0.75
	local startZ = config.BRIDGE_START.Z
	local length = BridgeLayout.bridgeEndZ() - startZ
	for _, side in { -1, 1 } do
		local girder = makeDecor(
			"Girder",
			Vector3.new(1.5, 3, length),
			CFrame.new(side * girderX, -2.5, startZ + length / 2),
			folder
		)
		girder.Material = Enum.Material.DiamondPlate
		girder.Color = STEEL
	end
	for index = 1, config.ROW_COUNT do
		local beam = makeDecor(
			"CrossBeam",
			-- Spans exactly between the girders' inner faces
			Vector3.new((girderX - 0.75) * 2, 1, 1.5),
			CFrame.new(0, -1.6, BridgeLayout.rowCenterZ(index)),
			folder
		)
		beam.Material = Enum.Material.DiamondPlate
		beam.Color = STEEL
	end
end

local function buildRowNumber(index: number, folder: Instance)
	local config = BridgeConfig
	local x = config.TILE_SIZE.X + config.CENTER_GAP / 2 + 3
	local anchor = makeDecor("RowNumber", Vector3.one, CFrame.new(-x, 1.5, BridgeLayout.rowCenterZ(index)), folder)
	anchor.Transparency = 1

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(3, 1.6)
	billboard.MaxDistance = 70
	billboard.LightInfluence = 0
	billboard.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = tostring(index)
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Parent = billboard
end

local function buildCheckpoint(checkpoint: number, folder: Instance)
	local config = BridgeConfig
	local width = config.TILE_SIZE.X * 2 + config.CENTER_GAP + 6
	local z = BridgeLayout.checkpointCenterZ(checkpoint)
	local model = Instance.new("Model")
	model.Name = `Checkpoint{checkpoint}`
	model.Parent = folder

	-- A walkable platform with a glowing strip along its front and back edge. The strips sit
	-- beside the platform (not inside it) so the surfaces never overlap and flicker.
	local stripDepth = 0.6
	local platform = makePart(
		"Platform",
		Vector3.new(width, 1, config.CHECKPOINT_DEPTH - stripDepth * 2),
		CFrame.new(0, config.BRIDGE_START.Y, z),
		model
	)
	platform.Color = Color3.fromRGB(235, 240, 250)
	table.insert(checkpointPlatforms, platform)

	for _, edge in { -1, 1 } do
		local strip = makePart(
			"EdgeGlow",
			Vector3.new(width, 1, stripDepth),
			CFrame.new(0, config.BRIDGE_START.Y, z + edge * (config.CHECKPOINT_DEPTH / 2 - stripDepth / 2)),
			model
		)
		strip.Material = Enum.Material.Neon
		strip.Color = CHECKPOINT_BLUE
	end

	-- Two poles holding an overhead banner, like a race checkpoint
	local poleX = width / 2 - 1
	for _, side in { -1, 1 } do
		local pole = makePart("Pole", Vector3.new(1, 12, 1), CFrame.new(side * poleX, 6, z), model)
		pole.Color = Color3.new(1, 1, 1)
		pole.Material = Enum.Material.Metal
	end
	makeBanner(
		`🚩 CHECKPOINT {checkpoint}/{BridgeLayout.CHECKPOINT_COUNT}`,
		Vector3.new(width - 2, 3.5, 0.4),
		-- Just in front of the poles (they're 1 thick), so it never cuts through them
		Vector3.new(0, 11, z - 0.5 - 0.2),
		CHECKPOINT_BLUE,
		model
	)

	platform.Touched:Connect(function(hit: BasePart)
		local player = getLivingPlayer(hit)
		if player and checkpoint > getCheckpoint(player) then
			player:SetAttribute(CHECKPOINT_ATTRIBUTE, checkpoint)
			Remotes.Notify:FireClient(player, `🚩 Checkpoint {checkpoint} reached!`, "checkpoint")
		end
	end)
end

local function sendToLobby(player: Player)
	local character = getLivingCharacter(player)
	if character then
		character:PivotTo(getSpawnCFrame())
	end
end

local function onFinishTouched(hit: BasePart)
	local player = getLivingPlayer(hit)
	if not player or celebrating[player] then
		return
	end
	celebrating[player] = true
	player:SetAttribute(CHECKPOINT_ATTRIBUTE, 0)
	-- A win ends the run: the next crossing pays for every row again
	paidRow[player] = 0
	onPlayerWon(player)
	CoinService.add(player, EconomyConfig.FINISH_BONUS_COINS)
	Remotes.Notify:FireClient(player, `🏆 YOU WIN! +1 WIN  +{EconomyConfig.FINISH_BONUS_COINS} 🪙`, "win")
	Remotes.Notify:FireAllClients(`🏆 {player.DisplayName} reached the trophy!`, "purchase")
	if confetti then
		confetti:Emit(80)
	end

	task.delay(BridgeConfig.CELEBRATE_SECONDS, function()
		celebrating[player] = nil
		if player.Parent then
			sendToLobby(player)
		end
	end)
end

local function buildFinish(folder: Instance)
	local config = BridgeConfig
	local endZ = BridgeLayout.bridgeEndZ()
	local width = config.TILE_SIZE.X * 2 + config.CENTER_GAP + 14
	local model = Instance.new("Model")
	model.Name = "Finish"
	model.Parent = folder

	local finish = makePart(
		"Platform",
		Vector3.new(width, 1, FINISH_DEPTH),
		CFrame.new(0, config.BRIDGE_START.Y, endZ + FINISH_DEPTH / 2),
		model
	)
	finish.Color = GOLD
	finish.Material = Enum.Material.Neon
	finishPlatform = finish
	finish.Touched:Connect(onFinishTouched)

	-- Arch over the entrance
	local archZ = endZ + 1
	for _, side in { -1, 1 } do
		local pillar = makePart("Pillar", Vector3.new(2, 16, 2), CFrame.new(side * (width / 2 - 1), 8, archZ), model)
		pillar.Color = Color3.new(1, 1, 1)
		pillar.Material = Enum.Material.Marble
	end
	-- Banner hangs just in front of the pillars (they're 2 thick)
	makeBanner("🏆 FINISH 🏆", Vector3.new(width, 4, 0.6), Vector3.new(0, 15, archZ - 1 - 0.3), Color3.fromRGB(230, 60, 60), model)

	-- Trophy on a marble stage at the back
	local stageZ = endZ + FINISH_DEPTH - 8
	local stage = makePart("Stage", Vector3.new(14, 1, 10), CFrame.new(0, 0.5, stageZ), model)
	stage.Color = Color3.new(1, 1, 1)
	stage.Material = Enum.Material.Marble
	local cup = buildTrophy(CFrame.new(0, 1, stageZ), model)

	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(2, 4)
	emitter.Speed = NumberRange.new(25, 40)
	emitter.SpreadAngle = Vector2.new(60, 60)
	emitter.Acceleration = Vector3.new(0, -30, 0)
	emitter.RotSpeed = NumberRange.new(-200, 200)
	emitter.Size = NumberSequence.new(0.6)
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
		ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 220, 60)),
		ColorSequenceKeypoint.new(0.66, Color3.fromRGB(80, 200, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 90, 255)),
	})
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Parent = cup
	confetti = emitter
end

local function buildBridge()
	local config = BridgeConfig
	local folder = Instance.new("Folder")
	folder.Name = "GlassBridge"
	folder.Parent = workspace

	buildSpawns(folder)
	buildSupports(folder)

	local tileOffsetX = config.TILE_SIZE.X / 2 + config.CENTER_GAP / 2
	for index = 1, config.ROW_COUNT do
		local rowZ = BridgeLayout.rowCenterZ(index)
		local rowFolder = Instance.new("Folder")
		rowFolder.Name = `Row{index}`
		rowFolder.Parent = folder

		local row: Row = { tiles = {} }
		for side, x in { -tileOffsetX, tileOffsetX } do
			-- Alternate colours so neighbouring tiles never match
			local colorIndex = ((index - 1) * 2 + side - 1) % #config.TILE_COLORS + 1
			local tile = createTile(
				`Tile{side}`,
				index,
				CFrame.new(x, config.BRIDGE_START.Y, rowZ),
				config.TILE_COLORS[colorIndex],
				rowFolder
			)
			table.insert(row.tiles, tile)
			tile.part.Touched:Connect(function(hit: BasePart)
				onTileTouched(tile, hit)
			end)
		end
		table.insert(rows, row)
		buildRowNumber(index, rowFolder)
	end

	for checkpoint = 1, BridgeLayout.CHECKPOINT_COUNT do
		buildCheckpoint(checkpoint, folder)
	end
	buildFinish(folder)

	-- Kill zone so players who fall respawn quickly instead of waiting for the -500 void.
	-- Centred on the bridge so it covers the lobby, all the rows and the finish.
	local middleZ = (config.BRIDGE_START.Z + BridgeLayout.bridgeEndZ()) / 2
	local killZone = makePart("KillZone", Vector3.new(2048, 1, 2048), CFrame.new(0, config.KILL_HEIGHT, middleZ), folder)
	killZone.Transparency = 1
	killZone.CanCollide = false
	killZone.CanQuery = false
	killZone.Touched:Connect(function(hit: BasePart)
		local _, humanoid = getLivingPlayer(hit)
		if humanoid then
			humanoid.Health = 0
		end
	end)
end

-- Respawned players go to their last checkpoint instead of the lobby
local function onCharacterAdded(player: Player, character: Model)
	local checkpoint = getCheckpoint(player)
	local platform = checkpointPlatforms[checkpoint]
	if checkpoint <= 0 or not platform then
		return
	end
	character:WaitForChild("HumanoidRootPart")
	task.wait() -- let the default spawn finish first
	if character.Parent then
		teleportOnto(character, platform)
	end
end

----- Public -----
-- Furthest row the player is standing at (0 = lobby), or nil if they have no living character
function BridgeService.getPlayerRow(player: Player): number?
	local _, root = getLivingCharacter(player)
	if not root then
		return nil
	end
	return BridgeLayout.rowAtZ(root.Position.Z)
end

-- Sends the buyer (only) the safe tiles of their next `count` rows
function BridgeService.revealRows(player: Player, count: number): boolean
	local currentRow = BridgeService.getPlayerRow(player) or 0
	local parts: { BasePart } = {}
	for rowIndex = currentRow + 1, math.min(currentRow + count, BridgeConfig.ROW_COUNT) do
		local safeTile = getSafeTile(rowIndex)
		if safeTile then
			table.insert(parts, safeTile.part)
		end
	end
	Remotes.RevealTiles:FireClient(player, parts)
	return true
end

function BridgeService.skipToEnd(player: Player): boolean
	local character = getLivingCharacter(player)
	if not character or not finishPlatform then
		return false
	end
	-- Land at the front of the finish platform; touching it awards the win as usual
	local position = Vector3.new(0, 4, BridgeLayout.bridgeEndZ() + 6)
	character:PivotTo(CFrame.lookAt(position, position + Vector3.zAxis))
	return true
end

function BridgeService.skipRows(player: Player, count: number): boolean
	local character = getLivingCharacter(player)
	local currentRow = BridgeService.getPlayerRow(player)
	if not character or not currentRow then
		return false
	end
	local targetRow = currentRow + count
	if targetRow > BridgeConfig.ROW_COUNT then
		return BridgeService.skipToEnd(player)
	end
	local safeTile = getSafeTile(targetRow)
	if not safeTile then
		return false
	end
	teleportOnto(character, safeTile.part)
	return true
end

function BridgeService.addShield(player: Player)
	local shields = player:GetAttribute("Shields")
	player:SetAttribute("Shields", (if typeof(shields) == "number" then shields else 0) + 1)
end

function BridgeService.start(wonCallback: (Player) -> ())
	onPlayerWon = wonCallback
	Players.RespawnTime = BridgeConfig.RESPAWN_SECONDS

	buildBridge()

	local function onPlayerAdded(player: Player)
		player:SetAttribute(CHECKPOINT_ATTRIBUTE, 0)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		celebrating[player] = nil
		paidRow[player] = nil
	end)

	task.spawn(function()
		while true do
			startNewRound()
			task.wait(BridgeConfig.ROUND_SECONDS)
		end
	end)
end

return BridgeService
