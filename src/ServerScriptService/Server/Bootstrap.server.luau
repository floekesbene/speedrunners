--[[
	Bootstrap  (Script)
	Pfad: ServerScriptService/Server/Bootstrap

	Einstiegspunkt des Servers:
		1. Kollisionsgruppen und Physik konfigurieren
		2. Alle Services laden, :Init(services) aufrufen (keine Querverweise nötig)
		3. :Start() in definierter Reihenfolge (Lobby zuerst, Datenservice zuletzt)
		4. Gemeinsamer 10-Hz-Tick für Character-, Training-, Power-up- und
		   Anti-Exploit-Logik
		5. Geordnetes Aufräumen beim Verlassen (Profil wird zuletzt gespeichert)
]]

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

------------------------------------------------------------------------
-- Physik & Kollisionsgruppen
------------------------------------------------------------------------

workspace.Gravity = Config.World.Gravity

local function registerGroup(name: string)
	if not PhysicsService:IsCollisionGroupRegistered(name) then
		PhysicsService:RegisterCollisionGroup(name)
	end
end

registerGroup("Runner") -- unsichtbarer Kollider der Spielfigur
registerGroup("RunnerBody") -- sichtbare Körperteile und Kosmetik (keine Kollision)

PhysicsService:CollisionGroupSetCollidable("Runner", "Runner", false) -- Spieler gehen durcheinander
PhysicsService:CollisionGroupSetCollidable("RunnerBody", "Default", false)
PhysicsService:CollisionGroupSetCollidable("RunnerBody", "Runner", false)
PhysicsService:CollisionGroupSetCollidable("RunnerBody", "RunnerBody", false)

------------------------------------------------------------------------
-- Services
------------------------------------------------------------------------

local servicesFolder = script.Parent:WaitForChild("Services")

local INIT_ORDER = {
	"PlayerDataService",
	"EconomyService",
	"InventoryService",
	"ShopService",
	"GrappleService",
	"PowerUpService",
	"MapService",
	"HazardRingService",
	"CharacterService",
	"MatchmakingService",
	"RoundService",
	"PracticeService",
	"RewardService",
	"RankedService",
	"LeaderboardService",
	"AntiExploitService",
}

local START_ORDER = {
	"MapService",
	"HazardRingService",
	"GrappleService",
	"PowerUpService",
	"EconomyService",
	"InventoryService",
	"ShopService",
	"CharacterService",
	"MatchmakingService",
	"RoundService",
	"PracticeService",
	"RewardService",
	"RankedService",
	"LeaderboardService",
	"AntiExploitService",
	"PlayerDataService", -- zuletzt: Profile laden löst das Spawnen aus
}

local services = {}
for _, name in INIT_ORDER do
	services[name] = require(servicesFolder:WaitForChild(name))
end
for _, name in INIT_ORDER do
	services[name]:Init(services)
end
for _, name in START_ORDER do
	local ok, err = pcall(function()
		services[name]:Start()
	end)
	if not ok then
		warn(string.format("[Bootstrap] %s:Start() fehlgeschlagen: %s", name, tostring(err)))
	end
end

------------------------------------------------------------------------
-- Gemeinsamer Server-Tick (10 Hz)
------------------------------------------------------------------------

local TICKED = { "CharacterService", "PracticeService", "PowerUpService", "AntiExploitService" }
local tickInterval = 1 / Config.Round.TickRate
local accumulator = 0

RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < tickInterval then
		return
	end
	local step = accumulator
	accumulator = 0
	for _, name in TICKED do
		local service = services[name]
		local ok, err = pcall(service.Tick, service, step)
		if not ok then
			warn(string.format("[Bootstrap] %s:Tick fehlgeschlagen: %s", name, tostring(err)))
		end
	end
end)

------------------------------------------------------------------------
-- Verlassen: geordnetes Aufräumen, Profil zuletzt speichern
------------------------------------------------------------------------

local REMOVE_ORDER = {
	"MatchmakingService",
	"RoundService",
	"PracticeService",
	"PowerUpService",
	"GrappleService",
	"CharacterService",
	"ShopService",
	"EconomyService",
	"AntiExploitService",
}

Players.PlayerRemoving:Connect(function(player)
	for _, name in REMOVE_ORDER do
		local service = services[name]
		if service.OnPlayerRemoving then
			local ok, err = pcall(service.OnPlayerRemoving, service, player)
			if not ok then
				warn(string.format("[Bootstrap] %s:OnPlayerRemoving fehlgeschlagen: %s", name, tostring(err)))
			end
		end
	end
	services.PlayerDataService:Release(player)
end)

print(string.format("[%s] Server gestartet (Version %s)", Config.GameName, Config.Version))
