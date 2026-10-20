--!strict
-- LobbyBuilder
-- Dresses the 100x100 lobby baseplate (top at Y = 0, bridge leaves from the +Z edge):
--   * entrance arch over the bridge start with the game's title
--   * "How to play" board and a live "Top Wins" leaderboard either side of the spawns
--   * a colourful checkerboard floor in the bridge's tile colours
--   * a raised round spawn plaza with glowing spawn pads and lamp posts
--   * an AFK zone at the back (pays coins over time, see EconomyConfig / CoinService)
--   * Shop, Items and Coin Shop stalls on wooden decks; walking up to one shows a prompt that opens the shop
--   * railings around the edge (open at the bridge entrance)
-- Container: ServerScriptService.Server

----- Services -----
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

----- Dependencies -----
local BridgeConfig = require(ReplicatedStorage.Shared.BridgeConfig)
local EconomyConfig = require(ReplicatedStorage.Shared.EconomyConfig)

----- Constants -----
local LOBBY_HALF = 50
local ENTRANCE_HALF_WIDTH = 17
local RAIL_HEIGHT = 3.5
local POST_SPACING = 8
local LEADERBOARD_ROWS = 8
local LEADERBOARD_REFRESH_SECONDS = 2

local WHITE = Color3.new(1, 1, 1)
local PINK = Color3.fromRGB(240, 70, 150)
local PURPLE = Color3.fromRGB(130, 70, 230)
local GOLD = Color3.fromRGB(255, 200, 40)
local SKY = Color3.fromRGB(110, 190, 255)
local DARK = Color3.fromRGB(30, 30, 45)

local FLOOR_TILE_SIZE = 10
-- How far the floor colours are softened towards white (0 = as bright as the bridge tiles)
local FLOOR_SOFTEN = 0.2
-- The checkerboard is the lobby's walking surface (top at Y = 0); the baseplate sits directly
-- underneath it (top at -FLOOR_THICKNESS, see default.project.json), so nothing overlaps
local FLOOR_THICKNESS = 0.4

local HOW_TO_PLAY = table.concat({
	"1️⃣  Every row has 2 tiles. Only ONE is safe!",
	"2️⃣  Step on the one that's MORE POPULAR",
	"3️⃣  Wrong pick? The glass shatters 💥",
	`4️⃣  🚩 Checkpoints every {BridgeConfig.CHECKPOINT_INTERVAL} rows`,
	"5️⃣  Reach the 🏆 trophy to WIN",
}, "\n")

----- Variables -----
local leaderboardLabels: { TextLabel } = {}

local LobbyBuilder = {}

----- Helpers -----
local function makePart(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function makeLabel(properties: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = WHITE
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	for key, value in properties do
		(label :: any)[key] = value
	end
	return label
end

-- A sign whose readable side is the part's Front face
local function makeSign(text: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): SurfaceGui
	local sign = makePart("Sign", size, cframe, color, parent)
	sign.CanCollide = false
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 30
	surface.LightInfluence = 0
	surface.Parent = sign
	if text ~= "" then
		makeLabel({
			Text = text,
			Size = UDim2.fromScale(0.94, 0.86),
			Position = UDim2.fromScale(0.03, 0.07),
			Parent = surface,
		})
	end
	return surface
end

----- Pieces -----
-- Posts along a straight, axis-aligned run from `from` to `to`. `posts` collects every post
-- position (keyed so corner posts shared by two runs are only built once).
local function railingPosts(from: Vector3, to: Vector3, posts: { [string]: Vector3 }): { Vector3 }
	local offset = to - from
	local length = offset.Magnitude
	local direction = offset.Unit
	local postCount = math.max(1, math.floor(length / POST_SPACING))
	local run = {}
	for index = 0, postCount do
		local position = from + direction * (length * index / postCount)
		posts[string.format("%.2f,%.2f", position.X, position.Z)] = position
		table.insert(run, position)
	end
	return run
end

-- Rails fill the gap between neighbouring posts exactly (touching, never passing through)
local function buildRails(run: { Vector3 }, parent: Instance)
	for index = 1, #run - 1 do
		local a, b = run[index], run[index + 1]
		local gap = (b - a).Magnitude - 1 -- posts are 1 stud thick
		local middle = (a + b) / 2
		for _, height in { RAIL_HEIGHT - 0.3, RAIL_HEIGHT / 2 } do
			local rail = makePart(
				"Rail",
				Vector3.new(0.6, 0.6, gap),
				CFrame.lookAt(middle + Vector3.new(0, height, 0), b + Vector3.new(0, height, 0)),
				SKY,
				parent
			)
			rail.Material = Enum.Material.Neon
		end
	end
end

-- Covers the lobby with a checkerboard of the bridge's colours, cycling diagonally
local function buildFloor(parent: Instance)
	local model = Instance.new("Model")
	model.Name = "Floor"
	model.Parent = parent

	local colors = BridgeConfig.TILE_COLORS
	local count = (LOBBY_HALF * 2) // FLOOR_TILE_SIZE
	local thickness = FLOOR_THICKNESS
	for column = 0, count - 1 do
		for row = 0, count - 1 do
			local color = colors[(column + row) % #colors + 1]:Lerp(WHITE, FLOOR_SOFTEN)
			local x = -LOBBY_HALF + FLOOR_TILE_SIZE * (column + 0.5)
			local z = -LOBBY_HALF + FLOOR_TILE_SIZE * (row + 0.5)
			local tile = makePart(
				"FloorTile",
				Vector3.new(FLOOR_TILE_SIZE, thickness, FLOOR_TILE_SIZE),
				CFrame.new(x, -thickness / 2, z),
				color,
				model
			)
			-- Flat ground never needs to cast a shadow, and skipping it avoids shadow shimmer
			tile.CastShadow = false
		end
	end
end

-- The checkerboard is the visible floor now. Tuck the baseplate directly underneath it and make
-- it invisible, so the two can never draw at the same height and flicker - even if Studio's
-- copy of the baseplate isn't where default.project.json says (e.g. Rojo didn't sync it).
-- It keeps its collision as a safety net under the tiles.
local function tuckBaseplate()
	local baseplate = workspace:FindFirstChild("Baseplate")
	if not baseplate or not baseplate:IsA("BasePart") then
		return
	end
	local size = baseplate.Size
	baseplate.CFrame = CFrame.new(0, -FLOOR_THICKNESS - size.Y / 2, 0)
	baseplate.Transparency = 1
	baseplate.CastShadow = false
	for _, child in baseplate:GetChildren() do
		if child:IsA("Texture") or child:IsA("Decal") then
			child.Transparency = 1
		end
	end
end

local function buildRailings(parent: Instance)
	local edge = LOBBY_HALF - 0.5
	local runs = {
		{ Vector3.new(-edge, 0, -edge), Vector3.new(-edge, 0, edge) },
		{ Vector3.new(edge, 0, -edge), Vector3.new(edge, 0, edge) },
		{ Vector3.new(-edge, 0, -edge), Vector3.new(edge, 0, -edge) },
		-- Front edge, leaving the bridge entrance open
		{ Vector3.new(-edge, 0, edge), Vector3.new(-ENTRANCE_HALF_WIDTH, 0, edge) },
		{ Vector3.new(ENTRANCE_HALF_WIDTH, 0, edge), Vector3.new(edge, 0, edge) },
	}
	local posts: { [string]: Vector3 } = {}
	for _, run in runs do
		buildRails(railingPosts(run[1], run[2], posts), parent)
	end
	for _, position in posts do
		makePart("Post", Vector3.new(1, RAIL_HEIGHT, 1), CFrame.new(position + Vector3.new(0, RAIL_HEIGHT / 2, 0)), WHITE, parent)
	end
end

local function buildEntranceArch(parent: Instance)
	local z = BridgeConfig.BRIDGE_START.Z - 2.5
	for _, side in { -1, 1 } do
		local pillar = makePart(
			"Pillar",
			Vector3.new(3, 22, 3),
			CFrame.new(side * ENTRANCE_HALF_WIDTH, 11, z),
			WHITE,
			parent
		)
		pillar.Material = Enum.Material.Marble
		local cap = makePart("Cap", Vector3.new(4, 1, 4), CFrame.new(side * ENTRANCE_HALF_WIDTH, 22.5, z), GOLD, parent)
		cap.Material = Enum.Material.Neon
	end
	-- The signs hang just in front of the pillars (towards the spawns, -Z) so they never cut
	-- through them. An unrotated part's Front face points at -Z, so players read them walking up.
	local pillarFront = z - 1.5
	makeSign(
		"WHICH IS MORE POPULAR?",
		Vector3.new(ENTRANCE_HALF_WIDTH * 2 + 4, 4.8, 0.8),
		CFrame.new(0, 19.5, pillarFront - 0.4),
		PINK,
		parent
	)
	makeSign(
		"Pick the right tile... or FALL! 😱",
		Vector3.new(26, 2.6, 0.6),
		CFrame.new(0, 15.6, pillarFront - 0.3),
		PURPLE,
		parent
	)
end

-- A framed board on two legs, turned to face `lookAt`; returns the board's SurfaceGui
local function buildBoard(position: Vector3, lookAt: Vector3, frameColor: Color3, parent: Instance): SurfaceGui
	local cframe = CFrame.lookAt(position, Vector3.new(lookAt.X, position.Y, lookAt.Z))
	-- Sign (0.4 thick) at the front, frame (0.6) right behind it, legs (1) right behind that
	local frame = makePart("Frame", Vector3.new(21, 14, 0.6), cframe * CFrame.new(0, 0, 0.5), frameColor, parent)
	frame.Material = Enum.Material.Neon
	for _, side in { -1, 1 } do
		makePart(
			"Leg",
			Vector3.new(1, position.Y, 1),
			cframe * CFrame.new(side * 8, -position.Y / 2, 1.3),
			WHITE,
			parent
		)
	end
	return makeSign("", Vector3.new(20, 13, 0.4), cframe, DARK, parent)
end

local function buildHowToPlay(parent: Instance)
	-- Front corners, angled back towards the spawns so they're in view when you spawn
	local surface = buildBoard(Vector3.new(-32, 9, 40), Vector3.new(0, 0, 18), PINK, parent)
	makeLabel({
		Text = "❓ HOW TO PLAY",
		Size = UDim2.fromScale(0.9, 0.18),
		Position = UDim2.fromScale(0.05, 0.04),
		TextColor3 = GOLD,
		Parent = surface,
	})
	makeLabel({
		Text = HOW_TO_PLAY,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		LineHeight = 1.15,
		Size = UDim2.fromScale(0.88, 0.7),
		Position = UDim2.fromScale(0.06, 0.26),
		Parent = surface,
	})
end

local function buildLeaderboard(parent: Instance)
	local surface = buildBoard(Vector3.new(32, 9, 40), Vector3.new(0, 0, 18), GOLD, parent)
	makeLabel({
		Text = "🏆 TOP WINS",
		Size = UDim2.fromScale(0.9, 0.16),
		Position = UDim2.fromScale(0.05, 0.03),
		TextColor3 = GOLD,
		Parent = surface,
	})
	local rowHeight = 0.76 / LEADERBOARD_ROWS
	for index = 1, LEADERBOARD_ROWS do
		local label = makeLabel({
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.fromScale(0.86, rowHeight * 0.85),
			Position = UDim2.fromScale(0.07, 0.21 + (index - 1) * rowHeight),
			TextColor3 = if index == 1 then GOLD elseif index <= 3 then Color3.fromRGB(220, 220, 235) else WHITE,
			Parent = surface,
		})
		table.insert(leaderboardLabels, label)
	end
end

-- Upright cylinder (Roblox cylinders run along X, so turn them on their side)
local function makeDisc(name: string, diameter: number, height: number, center: Vector3, color: Color3, parent: Instance): Part
	local disc = makePart(
		name,
		Vector3.new(height, diameter, diameter),
		CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2),
		color,
		parent
	)
	disc.Shape = Enum.PartType.Cylinder
	-- Thin flat layers shimmer when they cast shadows onto each other, so they don't
	disc.CastShadow = false
	return disc
end

local function buildLamp(position: Vector3, parent: Instance)
	local baseHeight, poleHeight, globeSize = 0.6, 9, 2.2
	local base = makeDisc("LampBase", 2.2, baseHeight, position + Vector3.new(0, baseHeight / 2, 0), DARK, parent)
	base.Material = Enum.Material.Metal
	local pole = makeDisc("LampPole", 0.6, poleHeight, position + Vector3.new(0, baseHeight + poleHeight / 2, 0), DARK, parent)
	pole.Material = Enum.Material.Metal
	pole.CastShadow = true -- tall enough to cast a proper shadow
	local globe = makePart(
		"LampGlobe",
		Vector3.one * globeSize,
		CFrame.new(position + Vector3.new(0, baseHeight + poleHeight + globeSize / 2, 0)),
		Color3.fromRGB(255, 240, 200),
		parent
	)
	globe.Shape = Enum.PartType.Ball
	globe.Material = Enum.Material.Neon
	local light = Instance.new("PointLight")
	light.Range = 18
	light.Brightness = 1.2
	light.Color = Color3.fromRGB(255, 235, 190)
	light.Parent = globe
end

-- Raised round plaza in front of the bridge: white marble with a glowing pink rim and a blue
-- inner ring, one glowing pad under each spawn point, and lamp posts around the edge
local function buildSpawnPlaza(parent: Instance)
	local model = Instance.new("Model")
	model.Name = "SpawnPlaza"
	model.Parent = parent

	local height = BridgeConfig.SPAWN_PLAZA_HEIGHT
	local spawnZ = BridgeConfig.BRIDGE_START.Z - BridgeConfig.SPAWN_DISTANCE_FROM_BRIDGE
	-- Centred so the plaza's front edge meets the bridge entrance
	local radius = 19
	local center = Vector3.new(0, 0, BridgeConfig.BRIDGE_START.Z - radius - 1)

	-- Stacked layers, each resting on the one below (nothing overlaps, so nothing flickers):
	--   pink glowing rim (widest) -> white marble floor -> blue ring -> white centre
	local rimHeight = height / 2
	local layerHeight = 0.1
	local rim = makeDisc("Rim", radius * 2 + 2, rimHeight, center + Vector3.new(0, rimHeight / 2, 0), PINK, model)
	rim.Material = Enum.Material.Neon
	local floor = makeDisc("Floor", radius * 2, height - rimHeight, center + Vector3.new(0, rimHeight + (height - rimHeight) / 2, 0), WHITE, model)
	floor.Material = Enum.Material.Marble
	local ring = makeDisc("Ring", 26, layerHeight, center + Vector3.new(0, height + layerHeight / 2, 0), SKY, model)
	ring.Material = Enum.Material.Neon
	local inner = makeDisc("Inner", 24, layerHeight, center + Vector3.new(0, height + layerHeight * 1.5, 0), WHITE, model)
	inner.Material = Enum.Material.Marble
	local plazaTop = height + layerHeight * 2

	-- Glowing pad (with rising sparkles) under every spawn point
	local firstX = -(BridgeConfig.SPAWN_COUNT - 1) * BridgeConfig.SPAWN_SPACING / 2
	for index = 1, BridgeConfig.SPAWN_COUNT do
		local padX = firstX + (index - 1) * BridgeConfig.SPAWN_SPACING
		local padRim = makeDisc("PadRim", 6.6, layerHeight, Vector3.new(padX, plazaTop + layerHeight / 2, spawnZ), WHITE, model)
		padRim.Material = Enum.Material.Neon
		local pad = makeDisc("SpawnPad", 5.6, layerHeight, Vector3.new(padX, plazaTop + layerHeight * 1.5, spawnZ), SKY, model)
		pad.Material = Enum.Material.Neon

		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkles.Rate = 6
		sparkles.Lifetime = NumberRange.new(1, 1.6)
		sparkles.Speed = NumberRange.new(3, 5)
		sparkles.SpreadAngle = Vector2.new(15, 15)
		sparkles.Size = NumberSequence.new(0.4, 0)
		sparkles.LightEmission = 1
		sparkles.Color = ColorSequence.new(SKY)
		-- The disc is turned on its side, so its "Right" face points up
		sparkles.EmissionDirection = Enum.NormalId.Right
		sparkles.Parent = pad
	end

	for _, offset in { Vector3.new(-15, 0, 9), Vector3.new(15, 0, 9), Vector3.new(-12, 0, -13), Vector3.new(12, 0, -13) } do
		buildLamp(center + offset + Vector3.new(0, height, 0), model)
	end
end

-- Purple floor with a glowing border, cushions to "sit" on, a sign at the back and floating
-- Zzz. Matches the area CoinService pays out for (EconomyConfig.AFK_ZONE_*).
local function buildAfkZone(parent: Instance)
	local model = Instance.new("Model")
	model.Name = "AfkZone"
	model.Parent = parent

	local center = EconomyConfig.AFK_ZONE_CENTER
	local size = EconomyConfig.AFK_ZONE_SIZE
	local height = 0.3
	local border = 1
	local cyan = Color3.fromRGB(80, 230, 255)

	-- Inner floor plus four border strips laid around it edge to edge (none overlap)
	local floor = makePart(
		"Floor",
		Vector3.new(size.X - border * 2, height, size.Z - border * 2),
		CFrame.new(center.X, height / 2, center.Z),
		Color3.fromRGB(125, 85, 215),
		model
	)
	floor.CastShadow = false
	for _, side in { -1, 1 } do
		local alongX = makePart(
			"Border",
			Vector3.new(size.X, height, border),
			CFrame.new(center.X, height / 2, center.Z + side * (size.Z / 2 - border / 2)),
			cyan,
			model
		)
		local alongZ = makePart(
			"Border",
			Vector3.new(border, height, size.Z - border * 2),
			CFrame.new(center.X + side * (size.X / 2 - border / 2), height / 2, center.Z),
			cyan,
			model
		)
		for _, strip in { alongX, alongZ } do
			strip.Material = Enum.Material.Neon
			strip.CastShadow = false
		end
	end

	-- Round cushions in the corners
	local cushionColors = { PINK, SKY, GOLD, Color3.fromRGB(70, 200, 90) }
	local corners = { Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, 1) }
	for index, corner in corners do
		local position = center + Vector3.new(corner.X * (size.X / 2 - 5), height + 0.6, corner.Z * (size.Z / 2 - 5))
		local cushion = makeDisc("Cushion", 4.5, 1.2, position, cushionColors[index], model)
		cushion.Material = Enum.Material.Fabric
	end

	-- Sign just behind the back edge, facing the rest of the lobby (+Z), on two posts behind it
	local signDepth, postSize = 0.4, 0.8
	local signZ = center.Z - size.Z / 2 - 1 - signDepth / 2
	local signPosition = Vector3.new(center.X, 7, signZ)
	local surface = makeSign("", Vector3.new(16, 4, signDepth), CFrame.lookAt(signPosition, signPosition + Vector3.zAxis), PURPLE, model)
	makeLabel({
		Text = "💤 AFK ZONE",
		Size = UDim2.fromScale(0.9, 0.55),
		Position = UDim2.fromScale(0.05, 0.05),
		Parent = surface,
	})
	makeLabel({
		Text = `+{EconomyConfig.AFK_COINS} 🪙 every {EconomyConfig.AFK_INTERVAL_TEXT}`,
		TextColor3 = GOLD,
		Size = UDim2.fromScale(0.9, 0.32),
		Position = UDim2.fromScale(0.05, 0.62),
		Parent = surface,
	})
	for _, side in { -1, 1 } do
		makePart(
			"Post",
			Vector3.new(postSize, 9, postSize),
			CFrame.new(center.X + side * 6, 4.5, signZ - signDepth / 2 - postSize / 2),
			WHITE,
			model
		)
	end

	-- Floating Zzz over the middle of the zone
	local anchor = makePart("ZzzAnchor", Vector3.one, CFrame.new(center.X, 9, center.Z), WHITE, model)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(8, 3)
	billboard.LightInfluence = 0
	billboard.MaxDistance = 120
	billboard.Parent = anchor
	makeLabel({
		Text = "💤 Z z z",
		Size = UDim2.fromScale(1, 1),
		TextColor3 = Color3.fromRGB(200, 180, 255),
		Parent = billboard,
	})
end

local function getWins(player: Player): number
	local leaderstats = player:FindFirstChild("leaderstats")
	local wins = leaderstats and leaderstats:FindFirstChild("Wins")
	return if wins and wins:IsA("IntValue") then wins.Value else 0
end

local function refreshLeaderboard()
	local players = Players:GetPlayers()
	table.sort(players, function(a, b)
		return getWins(a) > getWins(b)
	end)
	local medals = { "🥇", "🥈", "🥉" }
	for index, label in leaderboardLabels do
		local player = players[index]
		if player then
			label.Text = `{medals[index] or `{index}.`}  {player.DisplayName}  —  {getWins(player)}`
		else
			label.Text = if index == 1 then "Be the first to win!" else ""
		end
	end
end

-- A market stall; its front (counter side) faces `facing`
local function buildStall(position: Vector3, facing: Vector3, title: string, shopTab: string, colors: { Color3 }, parent: Instance)
	local model = Instance.new("Model")
	model.Name = `{shopTab}Stall`
	model.Parent = parent
	local deckHeight = 0.6
	local deck = makePart(
		"Deck",
		Vector3.new(13, deckHeight, 10),
		CFrame.lookAt(position, position + facing) * CFrame.new(0, deckHeight / 2, -0.8),
		Color3.fromRGB(190, 140, 90),
		model
	)
	deck.Material = Enum.Material.WoodPlanks
	-- Everything else stands on top of the deck
	local raised = position + Vector3.new(0, deckHeight, 0)
	local base = CFrame.lookAt(raised, raised + facing)

	-- Local layout (front = -Z): counter at the front, back wall at the back, two posts just
	-- outside the counter's front corners, a flat awning resting on the posts and the wall, and
	-- the title sign standing on the awning. Every piece touches its neighbours without overlapping.
	local counterWidth, counterHeight, counterDepth = 10, 3.5, 2
	local counterZ = -2.5
	local roofY = 9.5 -- underside of the awning
	local postSize = 0.6

	local counter = makePart(
		"Counter",
		Vector3.new(counterWidth, counterHeight, counterDepth),
		base * CFrame.new(0, counterHeight / 2, counterZ),
		Color3.fromRGB(150, 100, 60),
		model
	)
	counter.Material = Enum.Material.Wood
	local top = makePart(
		"CounterTop",
		Vector3.new(counterWidth, 0.4, counterDepth + 0.6),
		base * CFrame.new(0, counterHeight + 0.2, counterZ),
		WHITE,
		model
	)
	top.Material = Enum.Material.Marble
	makePart("BackWall", Vector3.new(counterWidth, roofY, 0.6), base * CFrame.new(0, roofY / 2, 2.5), colors[1], model)
	for _, side in { -1, 1 } do
		makePart(
			"Post",
			Vector3.new(postSize, roofY, postSize),
			base * CFrame.new(side * (counterWidth / 2 + postSize / 2), roofY / 2, counterZ - counterDepth / 2 + postSize / 2),
			WHITE,
			model
		)
	end

	-- Striped awning, flat on top of the posts and the back wall
	local awningWidth = counterWidth + postSize * 2 + 0.6
	local awningFront = counterZ - counterDepth / 2 - 1
	local awningBack = 2.8
	local stripeCount = 6
	local stripeWidth = awningWidth / stripeCount
	for index = 1, stripeCount do
		makePart(
			"Awning",
			Vector3.new(stripeWidth, 0.4, awningBack - awningFront),
			base * CFrame.new(-awningWidth / 2 + stripeWidth * (index - 0.5), roofY + 0.2, (awningFront + awningBack) / 2),
			if index % 2 == 0 then WHITE else colors[2],
			model
		)
	end
	makeSign(title, Vector3.new(9, 2.6, 0.4), base * CFrame.new(0, roofY + 0.4 + 1.3, awningFront + 0.6), colors[2], model)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open"
	prompt.ObjectText = title
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	-- The client's HUD opens the shop on this tab when the prompt is triggered
	prompt:SetAttribute("OpenShop", shopTab)
	prompt.Parent = counter
end

----- Public -----
function LobbyBuilder.build()
	local folder = Instance.new("Folder")
	folder.Name = "Lobby"
	folder.Parent = workspace

	tuckBaseplate()
	buildFloor(folder)
	buildRailings(folder)
	buildSpawnPlaza(folder)
	buildEntranceArch(folder)
	buildHowToPlay(folder)
	buildLeaderboard(folder)
	buildStall(Vector3.new(-36, 0, -6), Vector3.xAxis, "🛒 SHOP", "Cheats", { SKY, Color3.fromRGB(70, 200, 90) }, folder)
	buildStall(Vector3.new(36, 0, -6), -Vector3.xAxis, "🎒 ITEMS", "Items", { SKY, Color3.fromRGB(235, 60, 60) }, folder)
	-- Coin shop: nothing for sale yet, the shop window shows "Coming soon"
	buildStall(Vector3.new(-36, 0, -32), Vector3.xAxis, "🪙 COIN SHOP", "Coins", { SKY, GOLD }, folder)
	buildAfkZone(folder)

	task.spawn(function()
		while true do
			refreshLeaderboard()
			task.wait(LEADERBOARD_REFRESH_SECONDS)
		end
	end)
end

return LobbyBuilder
