--!strict
-- HudController
-- Builds the in-game HUD in the style of current trending obbies:
--   top centre   progress bar with every player's avatar on it + "Row X / 67"
--   left         Wins / Coins / shield / AFK pills (coins pop "+N" when earned) and big
--                square Shop + Items buttons
--   right        quick-buy Skip / Reveal / Skip to End buttons
--   centre       shop window with Cheats / Items tabs (Items are the paylocked backpack tools)
--   top          toast messages (wins, purchases, reshuffles), reshuffle countdown
--   centre       big "YOU WIN!" banner; win / checkpoint sounds and looping background music
-- The lobby stalls' ProximityPrompts (attribute "OpenShop") also open the shop.
-- Container: StarterPlayer.StarterPlayerScripts.Client

----- Services -----
local Debris = game:GetService("Debris")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

----- Dependencies -----
local BridgeConfig = require(ReplicatedStorage.Shared.BridgeConfig)
local BridgeLayout = require(ReplicatedStorage.Shared.BridgeLayout)
local EconomyConfig = require(ReplicatedStorage.Shared.EconomyConfig)
local Products = require(ReplicatedStorage.Shared.Products)

----- Constants -----
local FONT = Enum.Font.FredokaOne
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(255, 200, 40)
local GREEN = Color3.fromRGB(70, 210, 90)
local BLUE = Color3.fromRGB(60, 150, 255)
local PURPLE = Color3.fromRGB(160, 80, 240)
local RED = Color3.fromRGB(235, 60, 60)
local DARK = Color3.fromRGB(30, 30, 42)

local CATEGORY_COLORS: { [string]: Color3 } = {
	Cheats = GREEN,
	Items = RED,
	Coins = GOLD,
}

local TOAST_COLORS: { [string]: Color3 } = {
	win = GOLD,
	purchase = PURPLE,
	shield = BLUE,
	round = DARK,
	reveal = GREEN,
	checkpoint = BLUE,
	coin = Color3.fromRGB(255, 160, 30),
	error = RED,
}

local REVEAL_SECONDS = 10
local TOAST_SECONDS = 3
local MAX_TOASTS = 4
local UPDATE_INTERVAL = 0.1

----- Variables -----
local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local notifyRemote = remotes:WaitForChild("Notify") :: RemoteEvent
local revealRemote = remotes:WaitForChild("RevealTiles") :: RemoteEvent
local testPurchaseRemote = remotes:WaitForChild("TestPurchase") :: RemoteEvent

local screenGui: ScreenGui
local uiScales: { UIScale } = {}
local priceLabels: { [string]: { TextLabel } } = {}
local priceTexts: { [string]: string } = {}
local avatars: { [Player]: ImageLabel } = {}
local activeReveals: { Highlight } = {}

local avatarLayer: Frame
local progressFill: Frame
local rowLabel: TextLabel
local roundLabel: TextLabel
local winBanner: TextLabel
local music: Sound? = nil
local toastList: Frame
local shopWindow: Frame
local shopCards: { [string]: Frame } = {}
local tabButtons: { [string]: TextButton } = {}
local emptyShopLabel: TextLabel

local HudController = {}

----- UI helpers -----
local function create(className: string, properties: { [string]: any }, children: { Instance }?): any
	local instance = Instance.new(className)
	for key, value in properties do
		if key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end
	for _, child in (children or {}) :: { Instance } do
		child.Parent = instance
	end
	if properties.Parent then
		instance.Parent = properties.Parent
	end
	return instance
end

local function corner(radius: number): any
	return create("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function outline(thickness: number): any
	return create("UIStroke", {
		Thickness = thickness,
		Color = BLACK,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

-- Light-to-dark vertical shine used on every chunky element
local function shine(): any
	return create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190)),
	})
end

local function label(properties: { [string]: any }): TextLabel
	local defaults: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = FONT,
		TextColor3 = WHITE,
		TextStrokeTransparency = 0,
		TextStrokeColor3 = BLACK,
		TextScaled = true,
	}
	for key, value in properties do
		defaults[key] = value
	end
	return create("TextLabel", defaults)
end

-- Groups anchored to a screen edge scale with the screen size
local function scaledGroup(properties: { [string]: any }): Frame
	properties.BackgroundTransparency = 1
	local frame = create("Frame", properties)
	local scale = create("UIScale", { Parent = frame })
	table.insert(uiScales, scale)
	return frame
end

local function addBounce(button: GuiButton)
	local scale = create("UIScale", { Parent = button })
	local tweenInfo = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local function tweenTo(value: number)
		TweenService:Create(scale, tweenInfo, { Scale = value }):Play()
	end
	button.MouseEnter:Connect(function()
		tweenTo(1.07)
	end)
	button.MouseLeave:Connect(function()
		tweenTo(1)
	end)
	button.MouseButton1Down:Connect(function()
		tweenTo(0.93)
	end)
	button.MouseButton1Up:Connect(function()
		tweenTo(1.07)
	end)
end

local function chunkyButton(properties: { [string]: any }, color: Color3): TextButton
	properties.BackgroundColor3 = color
	properties.Text = properties.Text or ""
	properties.AutoButtonColor = false
	local button = create("TextButton", properties, { corner(12), outline(3), shine() })
	addBounce(button)
	return button
end

local function updateScale()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	local scale = math.clamp(math.min(viewport.X / 1280, viewport.Y / 760), 0.55, 1.15)
	for _, uiScale in uiScales do
		uiScale.Scale = scale
	end
end

----- Toasts -----
local function showToast(text: string, kind: string?)
	local toasts = {}
	for _, child in toastList:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(toasts, child)
		end
	end
	if #toasts >= MAX_TOASTS then
		toasts[1]:Destroy()
	end

	local toast = label({
		Name = "Toast",
		Size = UDim2.new(1, 0, 0, 38),
		BackgroundTransparency = 0.1,
		BackgroundColor3 = TOAST_COLORS[kind or ""] or DARK,
		Text = text,
		LayoutOrder = math.floor(os.clock() * 1000),
		Parent = toastList,
	})
	corner(10).Parent = toast
	outline(2).Parent = toast
	create("UIPadding", {
		PaddingTop = UDim.new(0, 5),
		PaddingBottom = UDim.new(0, 5),
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
		Parent = toast,
	})

	task.delay(TOAST_SECONDS, function()
		if not toast.Parent then
			return
		end
		local fade = TweenInfo.new(0.4)
		local stroke = toast:FindFirstChildOfClass("UIStroke")
		TweenService:Create(toast, fade, {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
			BackgroundTransparency = 1,
		}):Play()
		if stroke then
			TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
		end
		Debris:AddItem(toast, 0.5)
	end)
end

----- Purchases -----
local function isOwned(product: Products.Product): boolean
	return product.kind == "GamePass" and player:GetAttribute(Products.ownedAttribute(product.key)) == true
end

local function buy(product: Products.Product)
	if isOwned(product) then
		showToast(`You already own {product.name}! It's in your backpack.`, "reveal")
	elseif product.id ~= 0 then
		if product.kind == "GamePass" then
			MarketplaceService:PromptGamePassPurchase(player, product.id)
		else
			MarketplaceService:PromptProductPurchase(player, product.id)
		end
	elseif RunService:IsStudio() then
		testPurchaseRemote:FireServer(product.key)
	else
		showToast("This item isn't available yet.", "error")
	end
end

local function priceText(price: number): string
	return `R$ {price}`
end

local function registerPriceLabel(product: Products.Product, priceLabel: TextLabel)
	priceTexts[product.key] = priceText(product.price)
	priceLabel.Text = priceTexts[product.key]
	local labels = priceLabels[product.key] or {}
	table.insert(labels, priceLabel)
	priceLabels[product.key] = labels
end

-- Swap the placeholder prices for the real ones set in the Creator Dashboard
local function loadLivePrices()
	for _, product in Products.list do
		if product.id ~= 0 then
			task.spawn(function()
				local infoType = if product.kind == "GamePass" then Enum.InfoType.GamePass else Enum.InfoType.Product
				local ok, info = pcall(function()
					return MarketplaceService:GetProductInfo(product.id, infoType)
				end)
				if ok and info and typeof(info.PriceInRobux) == "number" then
					priceTexts[product.key] = priceText(info.PriceInRobux)
				end
			end)
		end
	end
end

----- Shop window -----
local function selectTab(category: string)
	local anyVisible = false
	for key, card in shopCards do
		local product = Products.get(key)
		card.Visible = product ~= nil and product.category == category
		anyVisible = anyVisible or card.Visible
	end
	-- Tabs with nothing for sale yet (the coin shop) say so instead of showing a blank grid
	emptyShopLabel.Visible = not anyVisible
	for name, button in tabButtons do
		button.BackgroundColor3 = if name == category then CATEGORY_COLORS[name] else DARK
	end
end

local function openShop(category: string)
	selectTab(category)
	shopWindow.Visible = true
end

local function buildShopCard(product: Products.Product, parent: Instance)
	local color = CATEGORY_COLORS[product.category]
	local card = create("Frame", {
		Name = product.key,
		BackgroundColor3 = color,
		Parent = parent,
	}, { corner(14), outline(3), shine() })

	label({
		Text = product.icon,
		Size = UDim2.new(1, 0, 0.3, 0),
		Position = UDim2.fromScale(0, 0.04),
		Parent = card,
	})
	label({
		Text = product.name,
		Size = UDim2.new(0.92, 0, 0.13, 0),
		Position = UDim2.fromScale(0.04, 0.35),
		Parent = card,
	})
	label({
		Text = product.description,
		TextScaled = false,
		TextSize = 14,
		TextWrapped = true,
		TextStrokeTransparency = 0.4,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(0.9, 0, 0.27, 0),
		Position = UDim2.fromScale(0.05, 0.5),
		Parent = card,
	})

	local buyButton = chunkyButton({
		Size = UDim2.new(0.84, 0, 0.17, 0),
		Position = UDim2.fromScale(0.08, 0.79),
		Parent = card,
	}, GREEN)
	local priceLabel = label({
		Size = UDim2.new(1, -12, 1, -8),
		Position = UDim2.fromOffset(6, 4),
		Parent = buyButton,
	})
	registerPriceLabel(product, priceLabel)
	buyButton.Activated:Connect(function()
		buy(product)
	end)

	shopCards[product.key] = card
end

local function buildShop()
	shopWindow = scaledGroup({
		Name = "Shop",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(640, 460),
		Visible = false,
		Parent = screenGui,
	})
	local panel = create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(45, 45, 65),
		Parent = shopWindow,
	}, { corner(18), outline(4) })

	label({
		Text = "🛒 SHOP",
		Size = UDim2.new(0, 220, 0, 46),
		Position = UDim2.fromOffset(20, 10),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})

	local closeButton = chunkyButton({
		Text = "X",
		Font = FONT,
		TextScaled = true,
		TextColor3 = WHITE,
		Size = UDim2.fromOffset(46, 46),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Parent = panel,
	}, RED)
	closeButton.Activated:Connect(function()
		shopWindow.Visible = false
	end)

	local tabRow = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -40, 0, 42),
		Position = UDim2.fromOffset(20, 64),
		Parent = panel,
	}, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	for index, category in Products.CATEGORIES do
		local tab = chunkyButton({
			Text = category,
			Font = FONT,
			TextScaled = true,
			TextColor3 = WHITE,
			TextStrokeTransparency = 0,
			Size = UDim2.fromOffset(130, 42),
			LayoutOrder = index,
			Parent = tabRow,
		}, DARK)
		tab.Activated:Connect(function()
			selectTab(category)
		end)
		tabButtons[category] = tab
	end

	local grid = create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -40, 1, -130),
		Position = UDim2.fromOffset(20, 118),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = panel,
	}, {
		create("UIGridLayout", {
			CellSize = UDim2.fromOffset(182, 210),
			CellPadding = UDim2.fromOffset(14, 14),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		create("UIPadding", {
			PaddingTop = UDim.new(0, 6),
			PaddingLeft = UDim.new(0, 6),
		}),
	})

	emptyShopLabel = label({
		Text = "🪙 Coming soon!\nNew things to buy with your coins are on the way.",
		TextColor3 = GOLD,
		Size = UDim2.new(1, -80, 0, 110),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 190),
		Visible = false,
		Parent = panel,
	})

	for _, product in Products.list do
		buildShopCard(product, grid)
	end
	selectTab("Cheats")
end

----- Progress bar -----
local function buildProgressBar()
	local group = scaledGroup({
		Name = "Progress",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(560, 116),
		Parent = screenGui,
	})

	local bar = create("Frame", {
		Name = "Bar",
		BackgroundColor3 = DARK,
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.fromOffset(0, 40),
		Parent = group,
	}, { corner(11), outline(3) })

	progressFill = create("Frame", {
		Name = "Fill",
		BackgroundColor3 = WHITE,
		Size = UDim2.fromScale(0, 1),
		Parent = bar,
	}, {
		corner(11),
		create("UIGradient", {
			Color = ColorSequence.new(GREEN, GOLD),
		}),
	})

	-- A white notch on the bar for every checkpoint
	for checkpoint = 1, BridgeLayout.CHECKPOINT_COUNT do
		create("Frame", {
			Name = `Checkpoint{checkpoint}`,
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(BridgeLayout.progressAtZ(BridgeLayout.checkpointCenterZ(checkpoint)), 0),
			Size = UDim2.new(0, 4, 1, 0),
			ZIndex = 2,
			Parent = bar,
		})
	end

	label({
		Text = "🚩",
		Size = UDim2.fromOffset(30, 30),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		ZIndex = 3,
		Parent = bar,
	})
	label({
		Text = "🏆",
		Size = UDim2.fromOffset(34, 34),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		ZIndex = 3,
		Parent = bar,
	})

	avatarLayer = create("Frame", {
		Name = "Avatars",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 36),
		Position = UDim2.fromOffset(0, 2),
		Parent = group,
	})

	rowLabel = label({
		Text = `Row 0 / {BridgeConfig.ROW_COUNT}`,
		Size = UDim2.fromOffset(220, 24),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 66),
		Parent = group,
	})

	roundLabel = label({
		Text = "",
		TextColor3 = Color3.fromRGB(255, 230, 120),
		Size = UDim2.fromOffset(260, 20),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 92),
		Parent = group,
	})
end

local function addAvatar(other: Player)
	local isLocal = other == player
	local size = if isLocal then 36 else 28
	local avatar = create("ImageLabel", {
		Name = other.Name,
		BackgroundColor3 = Color3.fromRGB(200, 200, 210),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromOffset(size, size),
		ZIndex = if isLocal then 5 else 4,
		Parent = avatarLayer,
	}, {
		create("UICorner", { CornerRadius = UDim.new(1, 0) }),
		create("UIStroke", {
			Thickness = if isLocal then 3 else 2,
			Color = if isLocal then GOLD else WHITE,
		}),
	})
	avatars[other] = avatar

	task.spawn(function()
		local ok, image = pcall(function()
			return Players:GetUserThumbnailAsync(
				other.UserId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size48x48
			)
		end)
		if ok and avatar.Parent then
			avatar.Image = image
		end
	end)
end

local function removeAvatar(other: Player)
	local avatar = avatars[other]
	if avatar then
		avatar:Destroy()
		avatars[other] = nil
	end
end

local function getRootZ(other: Player): number?
	local character = other.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position.Z
	end
	return nil
end

local function updateProgress()
	for other, avatar in avatars do
		local z = getRootZ(other)
		avatar.Visible = z ~= nil
		if z then
			avatar.Position = UDim2.fromScale(BridgeLayout.progressAtZ(z), 1)
		end
	end

	local z = getRootZ(player)
	if z then
		progressFill.Size = UDim2.fromScale(BridgeLayout.progressAtZ(z), 1)
		local checkpoint = player:GetAttribute("Checkpoint")
		local checkpointText = if typeof(checkpoint) == "number" and checkpoint > 0
			then `   🚩 {checkpoint}/{BridgeLayout.CHECKPOINT_COUNT}`
			else ""
		rowLabel.Text = `Row {BridgeLayout.rowAtZ(z)} / {BridgeConfig.ROW_COUNT}{checkpointText}`
	end

	local roundEndsAt = workspace:GetAttribute("RoundEndsAt")
	if typeof(roundEndsAt) == "number" then
		local secondsLeft = math.max(0, math.ceil(roundEndsAt - workspace:GetServerTimeNow()))
		roundLabel.Text = string.format("🔀 Reshuffle in %d:%02d", secondsLeft // 60, secondsLeft % 60)
	end
end

----- Sounds & celebration -----
local function playSound(soundId: string, volume: number?)
	if soundId == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 0.8
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, 10)
end

local function buildWinBanner()
	local group = scaledGroup({
		Name = "WinBanner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.38),
		Size = UDim2.fromOffset(700, 130),
		Parent = screenGui,
	})
	winBanner = label({
		Text = "🏆 YOU WIN! 🏆",
		TextColor3 = GOLD,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = group,
	})
	create("UIStroke", { Thickness = 5, Color = BLACK, Parent = winBanner })
	create("UIScale", { Parent = winBanner })
end

local function showWinBanner()
	local scale = winBanner:FindFirstChildOfClass("UIScale")
	winBanner.Visible = true
	winBanner.TextTransparency = 0
	if scale then
		scale.Scale = 0.2
		TweenService:Create(scale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	task.delay(2.5, function()
		local fade = TweenService:Create(winBanner, TweenInfo.new(0.5), { TextTransparency = 1 })
		fade:Play()
		fade.Completed:Wait()
		winBanner.Visible = false
	end)
end

local function startMusic()
	if BridgeConfig.MUSIC_ID == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "BackgroundMusic"
	sound.SoundId = BridgeConfig.MUSIC_ID
	sound.Volume = BridgeConfig.MUSIC_VOLUME
	sound.Looped = true
	sound.Parent = SoundService
	sound:Play()
	music = sound
end

----- Left side -----
local function pill(name: string, color: Color3, order: number, parent: Instance): TextLabel
	local pillLabel = label({
		Name = name,
		BackgroundTransparency = 0,
		BackgroundColor3 = color,
		Size = UDim2.fromOffset(170, 42),
		LayoutOrder = order,
		Parent = parent,
	})
	corner(21).Parent = pillLabel
	outline(3).Parent = pillLabel
	shine().Parent = pillLabel
	create("UIPadding", {
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		Parent = pillLabel,
	})
	return pillLabel
end

local function squareButton(icon: string, text: string, color: Color3, order: number, parent: Instance): TextButton
	local button = chunkyButton({
		Size = UDim2.fromOffset(82, 82),
		LayoutOrder = order,
		Parent = parent,
	}, color)
	label({
		Text = icon,
		Size = UDim2.fromScale(1, 0.6),
		Position = UDim2.fromScale(0, 0.05),
		Parent = button,
	})
	label({
		Text = text,
		Size = UDim2.new(1, -8, 0.28, 0),
		Position = UDim2.new(0, 4, 0.66, 0),
		Parent = button,
	})
	return button
end

-- Price labels show the price, or OWNED for game passes the player already has
local function refreshPriceLabels()
	for key, labels in priceLabels do
		local product = Products.get(key)
		if product then
			local text = if isOwned(product) then "OWNED" else priceTexts[key]
			for _, priceLabel in labels do
				priceLabel.Text = text
			end
		end
	end
end

local function buildLeftSide(): () -> ()
	local group = scaledGroup({
		Name = "Left",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(180, 400),
		Parent = screenGui,
	})
	create("UIListLayout", {
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = group,
	})

	local winsPill = pill("Wins", GOLD, 1, group)
	winsPill.Text = "🏆 0"
	local coinsPill = pill("Coins", Color3.fromRGB(255, 160, 30), 2, group)
	coinsPill.Text = "🪙 0"
	local shieldPill = pill("Shields", BLUE, 3, group)
	local afkPill = pill("Afk", PURPLE, 4, group)

	local buttonRow = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(180, 82),
		LayoutOrder = 5,
		Parent = group,
	}, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	squareButton("🛒", "SHOP", GREEN, 1, buttonRow).Activated:Connect(function()
		openShop("Cheats")
	end)
	squareButton("🎒", "ITEMS", RED, 2, buttonRow).Activated:Connect(function()
		openShop("Items")
	end)

	local musicButton = chunkyButton({
		Text = "🔊 Music: ON",
		Font = FONT,
		TextScaled = true,
		TextColor3 = WHITE,
		TextStrokeTransparency = 0,
		Size = UDim2.fromOffset(174, 36),
		LayoutOrder = 6,
		Parent = group,
	}, PURPLE)
	create("UIPadding", {
		PaddingTop = UDim.new(0, 5),
		PaddingBottom = UDim.new(0, 5),
		Parent = musicButton,
	})
	musicButton.Activated:Connect(function()
		local sound = music
		if not sound then
			return
		end
		sound.Playing = not sound.Playing
		musicButton.Text = if sound.Playing then "🔊 Music: ON" else "🔇 Music: OFF"
	end)

	task.spawn(function()
		local leaderstats = player:WaitForChild("leaderstats")
		local wins = leaderstats:WaitForChild("Wins") :: IntValue
		local function refresh()
			winsPill.Text = `🏆 {wins.Value}`
		end
		wins.Changed:Connect(refresh)
		refresh()
	end)

	-- Coins: the pill counts up, and every gain floats a "+N" out to the right of it
	task.spawn(function()
		local leaderstats = player:WaitForChild("leaderstats")
		local coins = leaderstats:WaitForChild("Coins") :: IntValue
		local shown = coins.Value
		coinsPill.Text = `🪙 {shown}`
		coins.Changed:Connect(function()
			local gained = coins.Value - shown
			shown = coins.Value
			coinsPill.Text = `🪙 {shown}`
			if gained <= 0 then
				return
			end
			local popup = label({
				Text = `+{gained} 🪙`,
				TextColor3 = Color3.fromRGB(255, 225, 90),
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(1, 8, 0.5, 0),
				Size = UDim2.fromOffset(if gained >= 100 then 110 else 70, 30),
				ZIndex = 10,
				Parent = coinsPill,
			})
			local rise = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			TweenService:Create(popup, rise, {
				Position = UDim2.new(1, 8, 0.5, -36),
				TextTransparency = 1,
				TextStrokeTransparency = 1,
			}):Play()
			Debris:AddItem(popup, 1.1)
		end)
	end)

	-- Returns the per-tick refresher for the attribute-driven pills
	return function()
		local shields = player:GetAttribute("Shields")
		local shieldCount = if typeof(shields) == "number" then shields else 0
		shieldPill.Visible = shieldCount > 0
		shieldPill.Text = `🛡️ x{shieldCount}`

		-- AFK zone countdown to the next payout (the server sets "AfkRewardAt" while inside)
		local rewardAt = player:GetAttribute("AfkRewardAt")
		afkPill.Visible = typeof(rewardAt) == "number"
		if typeof(rewardAt) == "number" then
			local secondsLeft = math.max(0, math.ceil(rewardAt - workspace:GetServerTimeNow()))
			afkPill.Text = string.format("💤 +%d in %d:%02d", EconomyConfig.AFK_COINS, secondsLeft // 60, secondsLeft % 60)
		end
	end
end

----- Right side -----
local function quickBuyButton(key: string, color: Color3, order: number, parent: Instance)
	local product = Products.get(key)
	if not product then
		return
	end
	local button = chunkyButton({
		Size = UDim2.fromOffset(200, 64),
		LayoutOrder = order,
		Parent = parent,
	}, color)
	label({
		Text = `{product.icon} {product.name}`,
		Size = UDim2.new(1, -16, 0.55, 0),
		Position = UDim2.new(0, 8, 0.06, 0),
		Parent = button,
	})
	local priceLabel = label({
		Size = UDim2.new(1, -16, 0.34, 0),
		Position = UDim2.new(0, 8, 0.6, 0),
		TextColor3 = Color3.fromRGB(255, 255, 200),
		Parent = button,
	})
	registerPriceLabel(product, priceLabel)
	button.Activated:Connect(function()
		buy(product)
	end)
end

local function buildRightSide()
	local group = scaledGroup({
		Name = "Right",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.45, 0),
		Size = UDim2.fromOffset(200, 230),
		Parent = screenGui,
	})
	create("UIListLayout", {
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = group,
	})
	quickBuyButton("skip5", GREEN, 1, group)
	quickBuyButton("reveal1", BLUE, 2, group)
	quickBuyButton("skipEnd", GOLD, 3, group)
end

----- Reveals -----
local function clearReveals()
	for _, highlight in activeReveals do
		highlight:Destroy()
	end
	table.clear(activeReveals)
end

local function onRevealTiles(parts: { BasePart })
	for _, part in parts do
		if typeof(part) == "Instance" and part:IsA("BasePart") then
			local highlight = create("Highlight", {
				Adornee = part,
				FillColor = GREEN,
				FillTransparency = 0.25,
				OutlineColor = WHITE,
				DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
				Parent = part,
			})
			table.insert(activeReveals, highlight)
			Debris:AddItem(highlight, REVEAL_SECONDS)
		end
	end
	if #parts > 0 then
		showToast("👁️ Safe tiles revealed — only you can see them!", "reveal")
	end
end

----- Public -----
function HudController.start()
	screenGui = create("ScreenGui", {
		Name = "Hud",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})

	buildProgressBar()
	local refreshPills = buildLeftSide()
	buildRightSide()

	toastList = scaledGroup({
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 128),
		Size = UDim2.fromOffset(520, 200),
		Parent = screenGui,
	})
	create("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = toastList,
	})

	buildShop()
	buildWinBanner()
	loadLivePrices()
	startMusic()

	updateScale()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end

	for _, other in Players:GetPlayers() do
		addAvatar(other)
	end
	Players.PlayerAdded:Connect(addAvatar)
	Players.PlayerRemoving:Connect(removeAvatar)

	notifyRemote.OnClientEvent:Connect(function(text: string, kind: string?)
		if kind == "round" then
			clearReveals()
		elseif kind == "win" then
			showWinBanner()
			playSound(BridgeConfig.WIN_SOUND_ID, 1)
		elseif kind == "checkpoint" then
			playSound(BridgeConfig.CHECKPOINT_SOUND_ID, 0.9)
		end
		showToast(text, kind)
	end)
	revealRemote.OnClientEvent:Connect(onRevealTiles)

	-- Walking up to a lobby stall opens the shop on that stall's tab
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local tab = prompt:GetAttribute("OpenShop")
		if typeof(tab) == "string" then
			openShop(tab)
		end
	end)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(deltaTime)
		elapsed += deltaTime
		if elapsed < UPDATE_INTERVAL then
			return
		end
		elapsed = 0
		updateProgress()
		refreshPills()
		refreshPriceLabels()
	end)
end

return HudController
