--[[
	import_test.luau – prüft die Import-Variante (VelocityRush_Import.rbxm):
	frischer Place mit Baseplate/SpawnLocation -> Modell in den Workspace ->
	Installer ausführen -> Struktur prüfen -> Spiel starten und Spieler beitreten lassen.
	Aufruf: luau-runner --run tools/test/import_test.luau <repo-root> <import-tree.luau>
]]

local ROOT = __args[1]
local TREE = __args[2]
local env = setmetatable({}, { __index = _G })
local Mock = __compile(__readfile(ROOT .. "/tools/test/mock.luau"), "mock", env)()
Mock.IsStudio = true
local Services = Mock.Services
local Instance = Mock.Instance

local passed, failed = 0, 0
local function check(condition, message)
	if condition then
		passed += 1
		print("  ✓ " .. message)
	else
		failed += 1
		print("  ✗ FEHLER: " .. message)
	end
end

print("== Frischer Place mit Standardinhalt")
local baseplate = Instance.new("Part")
baseplate.Name = "Baseplate"
baseplate.Parent = Mock.Workspace
local spawnLocation = Instance.new("SpawnLocation")
spawnLocation.Name = "SpawnLocation"
spawnLocation.Parent = Mock.Workspace
Instance.new("StarterPlayerScripts", Services.StarterPlayer).Name = "StarterPlayerScripts"
Instance.new("StarterCharacterScripts", Services.StarterPlayer).Name = "StarterCharacterScripts"
Mock.Workspace.StreamingEnabled = true

print("== Modell importieren")
Mock.BuildTree(__compile(__readfile(TREE), "tree", env)())
-- BuildTree erzeugt den Wurzelordner ohne Parent: wie "Aus Datei einfügen" in den Workspace legen
local function findRoot()
	-- Der zuletzt gebaute Ordner mit Kind "Install"
	for _, candidate in Mock.Workspace:GetChildren() do
		if candidate:FindFirstChild("Install") then
			return candidate
		end
	end
	return nil
end
local importRoot = Mock.LastBuiltRoot
importRoot.Parent = Mock.Workspace
check(findRoot() ~= nil and importRoot.Name == "VelocityRush_Import", "Modell 'VelocityRush_Import' liegt im Workspace")
local bootstrap = importRoot.ServerScriptService.Server.Bootstrap
check(bootstrap.Disabled == true, "Bootstrap ist im Modell deaktiviert (läuft nicht versehentlich)")

print("== Installer ausführen (Befehlsleiste)")
Mock.Context = "server"
local requireEnv = Mock.MakeEnv(importRoot)
requireEnv.require(importRoot.Install)()
Mock.Run(0.1)
check(Services.ReplicatedStorage:FindFirstChild("Shared") ~= nil, "ReplicatedStorage.Shared installiert")
check(Services.ServerScriptService:FindFirstChild("Server") ~= nil, "ServerScriptService.Server installiert")
check(Services.ServerStorage:FindFirstChild("MapTemplates") ~= nil, "ServerStorage.MapTemplates installiert")
check(Services.StarterPlayer.StarterPlayerScripts:FindFirstChild("Client") ~= nil, "StarterPlayerScripts.Client installiert")
check(Services.StarterPlayer.StarterCharacterScripts:FindFirstChild("Animate") ~= nil, "StarterCharacterScripts.Animate installiert")
check(bootstrap.Disabled == false, "Bootstrap aktiviert")
check(Services.Players.CharacterAutoLoads == false, "CharacterAutoLoads = false")
check(Mock.Workspace.Gravity == 200, "Gravity = 200")
check(Mock.Workspace:FindFirstChild("Baseplate") == nil, "Baseplate entfernt")
check(Mock.Workspace:FindFirstChild("SpawnLocation") == nil, "SpawnLocation entfernt")
check(Mock.Workspace:FindFirstChild("VelocityRush_Import") == nil, "Import-Modell aufgeräumt")

print("== Spiel starten")
for _, d in Services.ServerScriptService:GetDescendants() do
	if d.ClassName == "Script" and d.Disabled ~= true then
		Mock.RunScript(d, "server")
	end
end
Mock.Run(1)
local player = Mock.AddPlayer(2001, "Tester", true)
Mock.Run(4)
check(Mock.Workspace:FindFirstChild("Lobby") ~= nil, "Lobby gebaut")
check(player.Character ~= nil and player.Character:FindFirstChild("VR_Collider") ~= nil, "Spieler hat Spielfigur")
check(player.PlayerGui:FindFirstChild("VelocityRushUI") ~= nil, "UI erstellt")
local gameState = Services.ReplicatedStorage.GameState
Mock.ClientFire(player, "QueueRequest", "Join", "QuickPlay")
Mock.Run(15)
check(gameState:GetAttribute("Phase") == "Racing" or gameState:GetAttribute("Phase") == "Countdown", "Solo-Rennen in Studio gestartet (" .. tostring(gameState:GetAttribute("Phase")) .. ")")

print(string.format("\nErgebnis: %d bestanden, %d fehlgeschlagen, %d Laufzeitfehler", passed, failed, #Mock.Errors))
if failed > 0 or #Mock.Errors > 0 then
	error("Import-Test fehlgeschlagen")
end
