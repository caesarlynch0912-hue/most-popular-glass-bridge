--!strict
-- Remotes
-- Creates the RemoteEvents in ReplicatedStorage.Remotes (clients WaitForChild them).
--   Notify (server -> client): text: string, kind: string   toast messages
--   RevealTiles (server -> client): { BasePart }             safe tiles a buyer may see
--   Pushed (server -> client): velocity: Vector3             you were shoved by Push
--   TestPurchase (client -> server): key: string             Studio-only free test buys
-- Container: ServerScriptService.Server

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = Instance.new("Folder")
folder.Name = "Remotes"

local function makeRemote(name: string): RemoteEvent
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	return remote
end

local Remotes = {
	Notify = makeRemote("Notify"),
	RevealTiles = makeRemote("RevealTiles"),
	Pushed = makeRemote("Pushed"),
	TestPurchase = makeRemote("TestPurchase"),
}

folder.Parent = ReplicatedStorage

return Remotes
