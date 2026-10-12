--[[
	Remotes  (ModuleScript)
	Pfad: ReplicatedStorage/Shared/Remotes

	Definiert die komplette Server-Client-Kommunikation an einer Stelle.
	Der Server erzeugt beim ersten require() den Ordner ReplicatedStorage/Remotes
	mit allen RemoteEvents/RemoteFunctions. Der Client wartet auf diese Instanzen.

	Client -> Server (RemoteEvent):
		QueueRequest(action: "Join"|"Leave", mode: "QuickPlay"|"Ranked")
		PracticeRequest(action: "Enter"|"Leave"|"Reset", courseId: string?)
		MoveState(state: string, facing: number)
		GrappleRequest(action: "Attach"|"Release", anchorId: number?)
		UsePowerUp()
		PlayEmote()
		SaveSettings(settings: table)
		RequestRespawn()
	Server -> Client (RemoteEvent):
		GameEvent(name: string, payload: table)
		ProfileUpdate(snapshot: table)
	Client -> Server (RemoteFunction):
		GetProfile() -> snapshot
		ShopRequest(action: "Buy"|"Equip"|"Unequip", category: string, itemId: string?) -> result
		GetLeaderboard() -> boards
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENTS = {
	"QueueRequest",
	"PracticeRequest",
	"MoveState",
	"GrappleRequest",
	"UsePowerUp",
	"PlayEmote",
	"SaveSettings",
	"RequestRespawn",
	"GameEvent",
	"ProfileUpdate",
}

local FUNCTIONS = {
	"GetProfile",
	"ShopRequest",
	"GetLeaderboard",
}

local Remotes = {}

local folder: Instance
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
	end
	for _, name in EVENTS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
	for _, name in FUNCTIONS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = folder
		end
	end
	folder.Parent = ReplicatedStorage
else
	folder = ReplicatedStorage:WaitForChild("Remotes")
end

for _, name in EVENTS do
	Remotes[name] = folder:WaitForChild(name)
end
for _, name in FUNCTIONS do
	Remotes[name] = folder:WaitForChild(name)
end

return Remotes
