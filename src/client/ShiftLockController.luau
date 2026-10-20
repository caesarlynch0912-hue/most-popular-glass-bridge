--!strict
-- ShiftLockController
-- Custom shift lock, toggled by the on-screen button or Left Shift. The button sits in the
-- bottom-right corner on PC and top-right on touch screens (clear of the jump button).
-- Locks the mouse to the centre, offsets the camera over the shoulder and turns the character
-- to face where the camera looks. The built-in option is disabled in default.project.json.
-- Container: StarterPlayer.StarterPlayerScripts.Client

----- Services -----
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

----- Constants -----
local TOGGLE_KEY = Enum.KeyCode.LeftShift
local SHOW_BUTTON = true
local CAMERA_OFFSET = Vector3.new(1.75, 0, 0)
local RENDER_STEP_NAME = "CustomShiftLock"
-- Run after the default camera scripts so our MouseBehavior wins each frame
local RENDER_PRIORITY = Enum.RenderPriority.Camera.Value + 1

local ON_COLOR = Color3.fromRGB(60, 170, 255)
local OFF_COLOR = Color3.fromRGB(40, 40, 40)

----- Variables -----
local player = Players.LocalPlayer
local enabled = false
local toggleButton: TextButton

local ShiftLockController = {}

----- Private Functions -----
local function getHumanoidAndRoot(): (Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and not root:IsA("BasePart") then
		root = nil
	end
	return humanoid, root :: BasePart?
end

local function onRenderStep()
	local humanoid, root = getHumanoidAndRoot()
	local camera = workspace.CurrentCamera
	if not humanoid or not root or not camera or humanoid.Health <= 0 then
		return
	end

	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter

	-- While flying (PlatformStand) the carpet steers the body, so don't fight it
	if humanoid.PlatformStand then
		return
	end

	-- Face the camera's horizontal direction
	local look = camera.CFrame.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)
end

local function applyState()
	local humanoid = getHumanoidAndRoot()
	if humanoid then
		humanoid.AutoRotate = not enabled
		humanoid.CameraOffset = if enabled then CAMERA_OFFSET else Vector3.zero
	end

	if enabled then
		RunService:BindToRenderStep(RENDER_STEP_NAME, RENDER_PRIORITY, onRenderStep)
	else
		RunService:UnbindFromRenderStep(RENDER_STEP_NAME)
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end

	toggleButton.Text = if enabled then "Shift Lock: ON" else "Shift Lock: OFF"
	toggleButton.BackgroundColor3 = if enabled then ON_COLOR else OFF_COLOR
end

local function toggle()
	enabled = not enabled
	applyState()
end

local function createButton()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ShiftLockGui"
	screenGui.ResetOnSpawn = false
	screenGui.Enabled = SHOW_BUTTON
	screenGui.Parent = player:WaitForChild("PlayerGui")

	local button = Instance.new("TextButton")
	button.Name = "ShiftLockButton"
	if UserInputService.TouchEnabled then
		button.AnchorPoint = Vector2.new(1, 0)
		button.Position = UDim2.new(1, -16, 0, 12)
	else
		button.AnchorPoint = Vector2.new(1, 1)
		button.Position = UDim2.new(1, -16, 1, -16)
	end
	button.Size = UDim2.fromOffset(150, 44)
	button.Font = Enum.Font.FredokaOne
	button.TextScaled = true
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextStrokeTransparency = 0
	button.BackgroundTransparency = 0.1
	button.AutoButtonColor = true
	button.Parent = screenGui

	-- Same chunky black outline as the rest of the HUD
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.new(0, 0, 0)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = button

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.Parent = button

	button.Activated:Connect(toggle)
	toggleButton = button
end

----- Public -----
function ShiftLockController.start()
	createButton()
	applyState()

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if not gameProcessed and input.KeyCode == TOGGLE_KEY then
			toggle()
		end
	end)

	-- New characters get a fresh Humanoid, so reapply AutoRotate and the camera offset
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Humanoid")
		applyState()
	end)
end

return ShiftLockController
