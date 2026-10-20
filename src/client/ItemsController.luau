--!strict
-- ItemsController
-- Client half of the backpack items (the server half is ItemService):
--   Flying Carpet: while the owned carpet tool is equipped you fly where the camera points.
--                  Move = WASD / thumbstick, rise = Space or E, sink = Left Ctrl or Q,
--                  touch screens get ▲ / ▼ buttons. Each client owns its character's physics,
--                  so the flight forces live here.
--   Push:          when someone pushes you the server asks this client to apply the shove.
-- Container: StarterPlayer.StarterPlayerScripts.Client

----- Services -----
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

----- Dependencies -----
local Products = require(ReplicatedStorage.Shared.Products)

----- Constants -----
local FLY_SPEED = 55
local VERTICAL_SPEED = 30
local ACCELERATION = 5 -- how quickly velocity catches up with input (higher = snappier)
local MAX_LEAN = math.rad(18)
local MAX_BANK = math.rad(22)
local HOVER_BOB = 1.2
local RENDER_STEP_NAME = "FlyingCarpet"
local FALL_DOWN_SECONDS = 1.2
local RISE_KEYS = { Enum.KeyCode.Space, Enum.KeyCode.E }
local SINK_KEYS = { Enum.KeyCode.LeftControl, Enum.KeyCode.Q }

----- Types -----
type Flight = {
	humanoid: Humanoid,
	attachment: Attachment,
	velocity: LinearVelocity,
	orientation: AlignOrientation,
	diedConnection: RBXScriptConnection,
}

----- Variables -----
local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local pushedRemote = remotes:WaitForChild("Pushed") :: RemoteEvent

local flight: Flight? = nil
local touchRise = false
local touchSink = false
local mobileControls: ScreenGui? = nil

local ItemsController = {}

----- Input -----
local function anyKeyDown(keys: { Enum.KeyCode }): boolean
	if UserInputService:GetFocusedTextBox() then
		return false
	end
	for _, key in keys do
		if UserInputService:IsKeyDown(key) then
			return true
		end
	end
	return false
end

local function flatten(vector: Vector3): Vector3
	local flat = Vector3.new(vector.X, 0, vector.Z)
	return if flat.Magnitude > 0.001 then flat.Unit else Vector3.zero
end

-- Direction to fly in. Uses Humanoid.MoveDirection (the walk input in world space, from
-- keyboard, gamepad or thumbstick), falling back to reading WASD directly. The input is then
-- re-expressed against the camera so looking up or down while moving flies up or down.
-- (Deliberately not using PlayerModule: it isn't in PlayerScripts in every Studio version,
-- and waiting for it froze this whole client script.)
local function getFlyDirection(humanoid: Humanoid, cameraCFrame: CFrame): Vector3
	local flatLook = flatten(cameraCFrame.LookVector)
	local flatRight = flatten(cameraCFrame.RightVector)

	local move = humanoid.MoveDirection
	if move.Magnitude < 0.01 and not UserInputService:GetFocusedTextBox() then
		local x = (if UserInputService:IsKeyDown(Enum.KeyCode.D) then 1 else 0)
			- (if UserInputService:IsKeyDown(Enum.KeyCode.A) then 1 else 0)
		local forward = (if UserInputService:IsKeyDown(Enum.KeyCode.W) then 1 else 0)
			- (if UserInputService:IsKeyDown(Enum.KeyCode.S) then 1 else 0)
		move = flatRight * x + flatLook * forward
	end
	if move.Magnitude < 0.01 then
		return Vector3.zero
	end

	local direction = cameraCFrame.LookVector * move:Dot(flatLook) + cameraCFrame.RightVector * move:Dot(flatRight)
	return if direction.Magnitude > 1 then direction.Unit else direction
end

----- Touch buttons -----
local function holdButton(text: string, position: UDim2, parent: Instance, onHold: (boolean) -> ())
	local button = Instance.new("TextButton")
	button.Text = text
	button.Font = Enum.Font.FredokaOne
	button.TextScaled = true
	button.TextColor3 = Color3.new(1, 1, 1)
	button.BackgroundColor3 = Color3.fromRGB(150, 20, 45)
	button.BackgroundTransparency = 0.15
	button.AnchorPoint = Vector2.new(1, 1)
	button.Position = position
	button.Size = UDim2.fromOffset(64, 64)
	button.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(235, 180, 45)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button
	button.MouseButton1Down:Connect(function()
		onHold(true)
	end)
	button.MouseButton1Up:Connect(function()
		onHold(false)
	end)
	button.MouseLeave:Connect(function()
		onHold(false)
	end)
end

local function setMobileControlsVisible(visible: boolean)
	if not UserInputService.TouchEnabled then
		return
	end
	if not mobileControls then
		local gui = Instance.new("ScreenGui")
		gui.Name = "FlyControls"
		gui.ResetOnSpawn = false
		gui.Parent = player:WaitForChild("PlayerGui")
		-- Stacked above the default jump button
		holdButton("▲", UDim2.new(1, -24, 1, -190), gui, function(held)
			touchRise = held
		end)
		holdButton("▼", UDim2.new(1, -96, 1, -150), gui, function(held)
			touchSink = held
		end)
		mobileControls = gui
	end
	local gui = mobileControls :: ScreenGui
	gui.Enabled = visible
	if not visible then
		touchRise = false
		touchSink = false
	end
end

----- Flying carpet -----
local function stopFlying()
	RunService:UnbindFromRenderStep(RENDER_STEP_NAME)
	local current = flight
	if not current then
		return
	end
	flight = nil
	current.diedConnection:Disconnect()
	current.velocity:Destroy()
	current.orientation:Destroy()
	current.attachment:Destroy()
	current.humanoid.PlatformStand = false
	setMobileControlsVisible(false)
end

local function startFlying(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return
	end
	stopFlying()

	local attachment = Instance.new("Attachment")
	attachment.Name = "CarpetAttachment"
	attachment.Parent = root

	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "CarpetVelocity"
	velocity.Attachment0 = attachment
	velocity.MaxForce = 1e6
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VectorVelocity = Vector3.zero
	velocity.Parent = root

	local orientation = Instance.new("AlignOrientation")
	orientation.Name = "CarpetOrientation"
	orientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	orientation.Attachment0 = attachment
	orientation.MaxTorque = 1e6
	orientation.Responsiveness = 25
	orientation.CFrame = root.CFrame.Rotation
	orientation.Parent = root

	-- Stops the walk / fall logic from fighting the carpet
	humanoid.PlatformStand = true
	root.AssemblyLinearVelocity = Vector3.zero

	flight = {
		humanoid = humanoid,
		attachment = attachment,
		velocity = velocity,
		orientation = orientation,
		diedConnection = humanoid.Died:Connect(stopFlying),
	}
	setMobileControlsVisible(true)

	local currentVelocity = Vector3.zero
	local elapsed = 0
	RunService:BindToRenderStep(RENDER_STEP_NAME, Enum.RenderPriority.Character.Value, function(deltaTime: number)
		local camera = workspace.CurrentCamera
		if not camera or humanoid.Health <= 0 or not root.Parent then
			stopFlying()
			return
		end
		elapsed += deltaTime
		-- Keep PlatformStand on in case something (a respawn script, a seat) turned it off
		humanoid.PlatformStand = true

		local cameraCFrame = camera.CFrame
		local direction = getFlyDirection(humanoid, cameraCFrame)

		local vertical = 0
		if anyKeyDown(RISE_KEYS) or touchRise then
			vertical += 1
		end
		if anyKeyDown(SINK_KEYS) or touchSink then
			vertical -= 1
		end

		local target = direction * FLY_SPEED + Vector3.new(0, vertical * VERTICAL_SPEED, 0)
		if target.Magnitude < 0.1 then
			-- Gentle hover bob while idle
			target = Vector3.new(0, math.sin(elapsed * 2) * HOVER_BOB, 0)
		end
		currentVelocity = currentVelocity:Lerp(target, math.min(1, deltaTime * ACCELERATION))
		velocity.VectorVelocity = currentVelocity

		-- Face where the camera looks; lean into forward speed and bank into sideways speed
		local flatLook = Vector3.new(cameraCFrame.LookVector.X, 0, cameraCFrame.LookVector.Z)
		if flatLook.Magnitude > 0.01 then
			local facing = CFrame.lookAt(Vector3.zero, flatLook)
			local localVelocity = facing:VectorToObjectSpace(currentVelocity) / FLY_SPEED
			local lean = math.clamp(localVelocity.Z, -1, 1) * MAX_LEAN -- forward speed is -Z
			local bank = math.clamp(-localVelocity.X, -1, 1) * MAX_BANK
			orientation.CFrame = facing * CFrame.Angles(lean, 0, bank)
		end
	end)
end

local function isCarpetTool(instance: Instance): boolean
	return instance:IsA("Tool") and instance:GetAttribute("ItemKey") == "carpet"
end

local function ownsCarpet(): boolean
	return player:GetAttribute(Products.ownedAttribute("carpet")) == true
end

local function watchCharacter(character: Model)
	stopFlying()
	-- Equipping a tool parents it to the character; unequipping moves it back to the backpack
	character.ChildAdded:Connect(function(child)
		if isCarpetTool(child) and ownsCarpet() then
			startFlying(character)
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if isCarpetTool(child) then
			stopFlying()
		end
	end)
end

----- Push -----
local function onPushed(velocity: Vector3)
	if typeof(velocity) ~= "Vector3" then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") or humanoid.Health <= 0 then
		return
	end
	-- A push knocks you off your carpet too
	local tool = character and character:FindFirstChildOfClass("Tool")
	if tool and isCarpetTool(tool) then
		humanoid:UnequipTools()
	end
	stopFlying()
	-- Knock them over briefly so the shove actually carries them
	humanoid:ChangeState(Enum.HumanoidStateType.FallingDown)
	root.AssemblyLinearVelocity = velocity
	task.delay(FALL_DOWN_SECONDS, function()
		if humanoid.Health > 0 then
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
end

----- Public -----
function ItemsController.start()
	if player.Character then
		watchCharacter(player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)
	pushedRemote.OnClientEvent:Connect(onPushed)

	-- Bought the carpet while already holding it: take off straight away
	player:GetAttributeChangedSignal(Products.ownedAttribute("carpet")):Connect(function()
		local character = player.Character
		local tool = character and character:FindFirstChildOfClass("Tool")
		if character and tool and isCarpetTool(tool) and ownsCarpet() and not flight then
			startFlying(character)
		end
	end)
end

return ItemsController
