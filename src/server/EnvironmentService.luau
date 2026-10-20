--!strict
-- EnvironmentService
-- Bright "high in the sky" look: sunny lighting, soft haze and clouds overhead. Below the
-- bridge is open sky (the void).
-- Container: ServerScriptService.Server

----- Services -----
local Lighting = game:GetService("Lighting")

local EnvironmentService = {}

----- Private Functions -----
local function getOrCreate(parent: Instance, className: string): any
	local existing = parent:FindFirstChildOfClass(className)
	if existing then
		return existing
	end
	local instance = Instance.new(className)
	instance.Parent = parent
	return instance
end

local function setupLighting()
	Lighting.ClockTime = 14
	Lighting.Brightness = 2.5
	Lighting.Ambient = Color3.fromRGB(110, 110, 120)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 165)
	Lighting.GlobalShadows = true
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.6

	local atmosphere = getOrCreate(Lighting, "Atmosphere") :: Atmosphere
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.1
	atmosphere.Color = Color3.fromRGB(200, 225, 255)
	atmosphere.Decay = Color3.fromRGB(120, 170, 230)
	atmosphere.Glare = 0.2
	atmosphere.Haze = 1.2

	local bloom = getOrCreate(Lighting, "BloomEffect") :: BloomEffect
	bloom.Intensity = 0.35
	bloom.Size = 24
	bloom.Threshold = 1.6

	local colorCorrection = getOrCreate(Lighting, "ColorCorrectionEffect") :: ColorCorrectionEffect
	colorCorrection.Saturation = 0.18
	colorCorrection.Contrast = 0.05
	colorCorrection.Brightness = 0.02

	local sunRays = getOrCreate(Lighting, "SunRaysEffect") :: SunRaysEffect
	sunRays.Intensity = 0.06
	sunRays.Spread = 0.6

	local clouds = getOrCreate(workspace.Terrain, "Clouds") :: Clouds
	clouds.Cover = 0.55
	clouds.Density = 0.6
	clouds.Color = Color3.new(1, 1, 1)
end

----- Public -----
function EnvironmentService.build()
	setupLighting()
end

return EnvironmentService
