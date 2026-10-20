--!strict
-- ItemService
-- Gives every player the "Items" from Products as Tools in their backpack, behind a paylock:
--   locked tool  -> named "🔒 <name>"; equipping it opens the purchase prompt
--   Push         -> game pass; click to shove the nearest player in front of you
--   Kill All     -> developer product; every purchase kills everyone else once
--   Flying Carpet-> game pass; while equipped a carpet appears and the client flies (ItemsController)
-- Container: ServerScriptService.Server

----- Services -----
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

----- Dependencies -----
local Products = require(ReplicatedStorage.Shared.Products)
local Remotes = require(script.Parent.Remotes)

----- Constants -----
local PUSH_RANGE = 10
local PUSH_COOLDOWN_SECONDS = 1.5
local PUSH_FORWARD_SPEED = 80
local PUSH_UP_SPEED = 35
-- Width, thickness and total length of the flying carpet
local CARPET_SIZE = Vector3.new(5, 0.25, 9)
local CARPET_COLOR = Color3.fromRGB(150, 20, 45)
local CARPET_TRIM_COLOR = Color3.fromRGB(235, 180, 45)
local ITEM_KEYS = { "push", "killAll", "carpet" }

----- Variables -----
local lastPush: { [Player]: number } = {}

local ItemService = {}

----- Private Functions -----
local function owns(player: Player, key: string): boolean
	return player:GetAttribute(Products.ownedAttribute(key)) == true
end

-- Developer products are never "owned": every use is a fresh purchase
local function isUnlocked(player: Player, product: Products.Product): boolean
	return product.kind == "GamePass" and owns(player, product.key)
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function toolName(player: Player, product: Products.Product): string
	return if isUnlocked(player, product) then product.name else `🔒 {product.name}`
end

local function refreshToolNames(player: Player)
	local containers: { Instance? } = { player:FindFirstChildOfClass("Backpack"), player.Character }
	for _, container in containers do
		if container then
			for _, tool in container:GetChildren() do
				local key = tool:GetAttribute("ItemKey")
				local product = if typeof(key) == "string" then Products.get(key) else nil
				if tool:IsA("Tool") and product then
					tool.Name = toolName(player, product)
					tool.ToolTip = if isUnlocked(player, product)
						then product.description
						else `R$ {product.price}: {product.description}`
				end
			end
		end
	end
end

local function killAll(player: Player): boolean
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local character = other.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Health = 0
			end
		end
	end
	return true
end

-- Opens the right purchase prompt, or in Studio (while the id is 0) grants it for free
local function promptPurchase(player: Player, product: Products.Product)
	if product.id == 0 then
		if RunService:IsStudio() then
			ItemService.grant(player, product)
		else
			Remotes.Notify:FireClient(player, "This item isn't available yet.", "error")
		end
		return
	end
	if product.kind == "GamePass" then
		MarketplaceService:PromptGamePassPurchase(player, product.id)
	else
		MarketplaceService:PromptProductPurchase(player, product.id)
	end
end

local function push(player: Player)
	local now = os.clock()
	if now - (lastPush[player] or 0) < PUSH_COOLDOWN_SECONDS then
		return
	end
	local root = getRoot(player)
	if not root then
		return
	end

	-- Closest living player in front of us within range
	local target: Player? = nil
	local targetRoot: BasePart? = nil
	local closest = PUSH_RANGE
	for _, other in Players:GetPlayers() do
		local otherRoot = if other ~= player then getRoot(other) else nil
		if otherRoot then
			local offset = otherRoot.Position - root.Position
			local distance = offset.Magnitude
			if distance < closest and root.CFrame.LookVector:Dot(offset.Unit) > 0.2 then
				closest = distance
				target = other
				targetRoot = otherRoot
			end
		end
	end
	if not target or not targetRoot then
		return
	end
	lastPush[player] = now

	-- The victim's own client owns their physics, so it applies the shove (ItemsController)
	local direction = targetRoot.Position - root.Position
	local flat = Vector3.new(direction.X, 0, direction.Z)
	flat = if flat.Magnitude > 0.01 then flat.Unit else root.CFrame.LookVector
	Remotes.Pushed:FireClient(target, flat * PUSH_FORWARD_SPEED + Vector3.new(0, PUSH_UP_SPEED, 0))
	Remotes.Notify:FireClient(target, `👊 {player.DisplayName} pushed you!`, "error")
end

local function removeCarpet(character: Model)
	local carpet = character:FindFirstChild("FlyingCarpet")
	if carpet then
		carpet:Destroy()
	end
end

-- Flags every part of the carpet as weightless, ghost-like decoration welded to `anchor`
local function attachCarpetPart(part: BasePart, anchor: BasePart, model: Model)
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if part ~= anchor then
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = anchor
		weld.Part1 = part
		weld.Parent = part
	end
	part.Parent = model
end

local function carpetPart(name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.Fabric
	return part
end

-- Builds a Persian-style rug: three fabric panels (front and back curl upwards), gold trim,
-- a diamond medallion, tassels on both ends and a trail of sparkles. Length runs along Z.
local function buildCarpetModel(center: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "FlyingCarpet"

	local width = CARPET_SIZE.X
	local thickness = CARPET_SIZE.Y
	local middleLength = CARPET_SIZE.Z * 0.5
	local endLength = CARPET_SIZE.Z * 0.25

	local body = carpetPart("Body", Vector3.new(width, thickness, middleLength), center, CARPET_COLOR)
	attachCarpetPart(body, body, model)
	model.PrimaryPart = body

	local function addSideTrim(cframe: CFrame, length: number)
		for _, side in { -1, 1 } do
			local trim = carpetPart(
				"Trim",
				Vector3.new(0.35, thickness + 0.06, length),
				cframe * CFrame.new(side * (width / 2 - 0.17), 0, 0),
				CARPET_TRIM_COLOR
			)
			attachCarpetPart(trim, body, model)
		end
	end
	addSideTrim(center, middleLength)

	-- End panels hinge up from the middle panel's edges; tassels hang off their outer edge
	for _, direction in { -1, 1 } do
		local hinge = center * CFrame.new(0, 0, direction * middleLength / 2)
		-- A positive X rotation lifts the -Z end; a negative one lifts the +Z end
		local tilt = CFrame.Angles(math.rad(if direction < 0 then 14 else -10), 0, 0)
		local panelCFrame = hinge * tilt * CFrame.new(0, 0, direction * endLength / 2)
		attachCarpetPart(carpetPart("EndPanel", Vector3.new(width, thickness, endLength), panelCFrame, CARPET_COLOR), body, model)
		addSideTrim(panelCFrame, endLength)

		local outerEdge = panelCFrame * CFrame.new(0, 0, direction * (endLength / 2 - 0.17))
		attachCarpetPart(
			carpetPart("EndTrim", Vector3.new(width, thickness + 0.06, 0.35), outerEdge, CARPET_TRIM_COLOR),
			body,
			model
		)
		for index = -2, 2 do
			local tassel = carpetPart(
				"Tassel",
				Vector3.new(0.18, 0.18, 0.8),
				outerEdge * CFrame.new(index * (width / 5), 0, direction * 0.55),
				CARPET_TRIM_COLOR
			)
			attachCarpetPart(tassel, body, model)
		end
	end

	-- Diamond medallion: gold diamond, navy centre, small gold dot
	local top = center * CFrame.new(0, thickness / 2, 0) * CFrame.Angles(0, math.rad(45), 0)
	local layers = {
		{ size = 2.4, height = 0.02, color = CARPET_TRIM_COLOR },
		{ size = 1.7, height = 0.04, color = Color3.fromRGB(25, 35, 90) },
		{ size = 0.6, height = 0.06, color = CARPET_TRIM_COLOR },
	}
	for _, layer in layers do
		local piece = carpetPart(
			"Medallion",
			Vector3.new(layer.size, 0.05, layer.size),
			top * CFrame.new(0, layer.height, 0),
			layer.color
		)
		attachCarpetPart(piece, body, model)
	end

	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Rate = 18
	sparkles.Lifetime = NumberRange.new(0.6, 1.1)
	sparkles.Speed = NumberRange.new(0.5, 1.5)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Size = NumberSequence.new(0.35, 0)
	sparkles.LightEmission = 1
	sparkles.Color = ColorSequence.new(CARPET_TRIM_COLOR)
	sparkles.EmissionDirection = Enum.NormalId.Bottom
	sparkles.Parent = body

	return model
end

local function addCarpet(player: Player)
	local character = player.Character
	local root = getRoot(player)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not root or not humanoid then
		return
	end
	removeCarpet(character)

	-- Put the rug just under the feet: R15 feet sit HipHeight below the bottom of the root
	local feetDrop = if humanoid.RigType == Enum.HumanoidRigType.R15
		then humanoid.HipHeight + root.Size.Y / 2
		else root.Size.Y / 2 + 2
	local center = root.CFrame * CFrame.new(0, -(feetDrop + CARPET_SIZE.Y / 2 + 0.05), 0)
	local model = buildCarpetModel(center)

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = model.PrimaryPart :: BasePart
	weld.Parent = model
	model.Parent = character
end

local function onToolEquipped(player: Player, product: Products.Product)
	-- Paylock: offer it for sale (in Studio, while the id is 0, this unlocks it instantly)
	if not isUnlocked(player, product) then
		promptPurchase(player, product)
	end
	-- Still locked (prompt open, or Kill All which is never "owned"): put it away
	if not isUnlocked(player, product) then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			task.defer(function()
				humanoid:UnequipTools()
			end)
		end
		return
	end
	if product.key == "carpet" then
		addCarpet(player)
	end
end

local function makeTool(player: Player, product: Products.Product): Tool
	local tool = Instance.new("Tool")
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool:SetAttribute("ItemKey", product.key)
	tool.Name = toolName(player, product)

	tool.Equipped:Connect(function()
		onToolEquipped(player, product)
	end)
	tool.Unequipped:Connect(function()
		local character = player.Character
		if product.key == "carpet" and character then
			removeCarpet(character)
		end
	end)
	tool.Activated:Connect(function()
		if product.key == "push" and isUnlocked(player, product) then
			push(player)
		end
	end)
	return tool
end

local function giveTools(player: Player)
	local backpack = player:WaitForChild("Backpack")
	for _, key in ITEM_KEYS do
		local product = Products.get(key)
		if product then
			makeTool(player, product).Parent = backpack
		end
	end
	refreshToolNames(player)
end

local function checkGamePasses(player: Player)
	for _, product in Products.list do
		if product.kind == "GamePass" and product.id ~= 0 then
			local ok, hasPass = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, product.id)
			end)
			if ok and hasPass then
				player:SetAttribute(Products.ownedAttribute(product.key), true)
			end
		end
	end
	refreshToolNames(player)
end

----- Public -----
-- Called after a successful purchase (or a free Studio test). Returns true once granted.
function ItemService.grant(player: Player, product: Products.Product): boolean
	if product.key == "killAll" then
		killAll(player)
		Remotes.Notify:FireAllClients(`💀 {player.DisplayName} used Kill All!`, "purchase")
		return true
	end
	if product.kind == "GamePass" then
		player:SetAttribute(Products.ownedAttribute(product.key), true)
		refreshToolNames(player)
		-- Hand the freshly bought tool straight to them (unless they're already holding it)
		local backpack = player:FindFirstChildOfClass("Backpack")
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if backpack and humanoid and humanoid.Health > 0 then
			for _, tool in backpack:GetChildren() do
				if tool:IsA("Tool") and tool:GetAttribute("ItemKey") == product.key then
					task.defer(function()
						humanoid:EquipTool(tool)
					end)
					break
				end
			end
		end
		Remotes.Notify:FireAllClients(`{product.icon} {player.DisplayName} unlocked {product.name}!`, "purchase")
		return true
	end
	return false
end

function ItemService.start()
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, gamePassId: number, wasPurchased: boolean)
			local product = Products.getByGamePassId(gamePassId)
			if wasPurchased and product then
				ItemService.grant(player, product)
			end
		end
	)

	local function onPlayerAdded(player: Player)
		player.CharacterAdded:Connect(function()
			-- The backpack is emptied on every respawn, so hand the tools out again
			giveTools(player)
		end)
		if player.Character then
			giveTools(player)
		end
		checkGamePasses(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastPush[player] = nil
	end)
end

return ItemService
