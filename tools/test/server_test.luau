--[[
	server_test.luau – End-to-End-Simulation von Velocity Rush im Mock.

	Aufruf: luau-runner --run tools/test/server_test.luau <repo-root> <tree.luau> [-v]

	Ablauf:
		1. Server starten (Bootstrap + alle Services), Lobby bauen
		2. Spieler beitreten (einer davon mit kompletter Client-Logik + UI)
		3. Shop: Kauf ohne Guthaben, Kauf, Doppelkauf, Ausrüsten
		4. Training betreten/verlassen, Tutorial wird gebaut
		5. Quick Play mit 3 Spielern: Countdown, Rennen (simulierte Bewegung),
		   Gefahrenzone, Items, Greifhaken, Ergebnis, Belohnungen
		6. Zweites Match (Auto-Requeue): Spieler verlassen mitten im Rennen
		7. Ranked-Match: Rating-Änderung
		8. Herunterfahren: Profile werden gespeichert
]]

local ROOT = __args[1]
local TREE = __args[2]
local env = setmetatable({}, { __index = _G })
local Mock = __compile(__readfile(ROOT .. "/tools/test/mock.luau"), "mock", env)()
Mock.Verbose = __args[3] == "-v"
Mock.IsStudio = false
local CFrame = Mock.CFrame

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

local tree = __compile(__readfile(TREE), "tree", env)()
Mock.BuildTree(tree)

local Services = Mock.Services
local function serverModule(name)
	local folder = Services.ServerScriptService.Server.Services
	local env2 = Mock.MakeEnv(folder)
	local previous = Mock.Context
	Mock.Context = "server"
	local value = env2.require(folder:FindFirstChild(name))
	Mock.Context = previous
	return value
end

print("== 1. Serverstart")
for _, d in Services.ServerScriptService:GetDescendants() do
	if d.ClassName == "Script" then
		Mock.RunScript(d, "server")
	end
end
Mock.Run(1)
local workspace = Mock.Workspace
check(workspace:FindFirstChild("Lobby") and #workspace.Lobby:GetChildren() > 0, "Lobby wurde gebaut")
check(Services.StarterPlayer:FindFirstChild("StarterCharacter") ~= nil, "StarterCharacter angelegt")
check(Services.ReplicatedStorage:FindFirstChild("Remotes") ~= nil, "Remotes angelegt")
local gameState = Services.ReplicatedStorage:FindFirstChild("GameState")
check(gameState ~= nil and gameState:GetAttribute("Phase") == "Waiting", "GameState: Phase = Waiting")
check((gameState:GetAttribute("NextMapId") or "") ~= "", "Nächste Map angekündigt: " .. tostring(gameState:GetAttribute("NextMapId")))

local PlayerData = serverModule("PlayerDataService")
local Round = serverModule("RoundService")
local MapService = serverModule("MapService")

print("== 2. Spieler treten bei")
local alpha = Mock.AddPlayer(1001, "Alpha", true)
local bravo = Mock.AddPlayer(1002, "Bravo", false)
local charlie = Mock.AddPlayer(1003, "Charlie", false)
Mock.Run(3)
for _, p in { alpha, bravo, charlie } do
	local character = p.Character
	check(character ~= nil and character:FindFirstChild("HumanoidRootPart") ~= nil, p.Name .. " hat eine Spielfigur")
	check(PlayerData:GetProfile(p) ~= nil, p.Name .. " Profil geladen")
	check(p:FindFirstChild("leaderstats") ~= nil, p.Name .. " leaderstats")
	if character then
		check(character:FindFirstChild("VR_Collider") ~= nil, p.Name .. " hat Kollider")
		check(character:FindFirstChild("VR_Cosmetics") ~= nil, p.Name .. " Kosmetik angewendet")
		local root = character.HumanoidRootPart
		check(math.abs(root.Position.X - (-3000)) < 200, p.Name .. " steht in der Lobby (X=" .. math.floor(root.Position.X) .. ")")
	end
end
local playerGui = alpha:FindFirstChild("PlayerGui")
check(playerGui:FindFirstChild("VelocityRushUI") ~= nil, "Client-UI für Alpha erstellt")

print("== 3. Shop")
local result = Mock.ClientInvoke(bravo, "ShopRequest", "Buy", "Skins", "SkyPilot")
check(result and result.Ok == false, "Kauf ohne genug Coins abgelehnt: " .. tostring(result and result.Message))
result = Mock.ClientInvoke(bravo, "ShopRequest", "Buy", "Colors", "Crimson")
check(result and result.Ok == true, "Kauf Farbvariante: " .. tostring(result and result.Message))
check(PlayerData:GetProfile(bravo).Coins == 100, "Coins abgebucht (300 -> 100)")
result = Mock.ClientInvoke(bravo, "ShopRequest", "Buy", "Colors", "Crimson")
check(result and result.Ok == false, "Doppelkauf verhindert: " .. tostring(result and result.Message))
result = Mock.ClientInvoke(bravo, "ShopRequest", "Equip", "Colors", "Crimson")
check(result and result.Ok == true, "Ausrüsten")
result = Mock.ClientInvoke(bravo, "ShopRequest", "Equip", "Skins", "RoyalGold")
check(result and result.Ok == false, "Nicht besessenen Skin ausrüsten abgelehnt")
result = Mock.ClientInvoke(bravo, "ShopRequest", "Buy", "Skins", "DoesNotExist")
check(result and result.Ok == false, "Unbekanntes Item abgelehnt")
result = Mock.ClientInvoke(bravo, "ShopRequest", "Unequip", "Skins")
check(result and result.Ok == false, "Skin kann nicht abgelegt werden")
result = Mock.ClientInvoke(bravo, "ShopRequest", "Buy", 123, {})
check(result and result.Ok == false, "Manipulierte Argumente abgelehnt")

print("== 4. Training")
Mock.ClientFire(bravo, "PracticeRequest", "Enter", "Tutorial")
Mock.Run(1)
check(bravo:GetAttribute("PracticeCourse") == "Tutorial", "Bravo ist im Tutorial")
check(MapService:GetRegion("Tutorial") ~= nil, "Tutorial-Region gebaut")
local bravoRoot = bravo.Character.HumanoidRootPart
check(math.abs(bravoRoot.Position.X - (-10000)) < 100, "Bravo wurde ins Tutorial teleportiert")
Mock.ClientFire(bravo, "PracticeRequest", "Enter", "MagmaWorks")
Mock.Run(1)
check(MapService:GetRegion("Practice_MagmaWorks") ~= nil, "Trainingskopie MagmaWorks gebaut")
-- In eine Gefahr laufen -> Respawn am Checkpoint
local region = MapService:GetRegion("Practice_MagmaWorks")
bravoRoot.CFrame = CFrame.new(region.Spawns[1].Position.X + 40, region.KillY - 5, 0)
Mock.Run(0.5)
check(bravoRoot.Position.Y > region.KillY, "Absturz im Training -> Respawn")
Mock.ClientFire(bravo, "PracticeRequest", "Leave")
Mock.Run(1)
check(bravo:GetAttribute("PracticeCourse") == "", "Training verlassen")

print("== 5. Quick Play")
for _, p in { alpha, bravo, charlie } do
	Mock.ClientFire(p, "QueueRequest", "Join", "QuickPlay")
end
Mock.Run(1)
check(gameState:GetAttribute("Phase") == "Starting", "Phase Starting nach Beitritt von 3 Spielern")
check(gameState:GetAttribute("QueueQuickPlay") == 3, "Warteschlange zählt 3 Spieler")
Mock.Run(10.5)
local phase = gameState:GetAttribute("Phase")
check(phase == "Countdown" or phase == "Racing", "Match gestartet (Phase " .. tostring(phase) .. ")")
check(alpha:GetAttribute("InRace") == true, "Alpha ist im Rennen")
check(alpha.Character:GetAttribute("Frozen") == true or phase == "Racing", "Spieler im Countdown eingefroren")
local raceMap = MapService:GetRaceMap()
check(raceMap ~= nil, "Rennstrecke geladen: " .. tostring(raceMap and raceMap.MapId))
check(raceMap and #raceMap.Checkpoints >= 5, "Checkpoints vorhanden (" .. tostring(raceMap and #raceMap.Checkpoints) .. ")")
check(raceMap and raceMap.FinishX ~= nil and raceMap.FinishX > 1200, "Ziellinie bei X=" .. tostring(raceMap and raceMap.FinishX))

-- Bewegungssimulation entlang der sicheren Punkte der Strecke
local function groundY(map, x)
	local best, bestDistance = nil, math.huge
	for _, node in map.TeleportNodes do
		local d = math.abs(node.X - x)
		if d < bestDistance or (d < 30 and best and node.Y > best.Y) then
			if d < 30 or d < bestDistance then
				best = node
				bestDistance = math.min(d, bestDistance)
			end
		end
	end
	return if best then best.Y else 3
end

local speeds = { [alpha] = 47, [bravo] = 40, [charlie] = 12 }
local flyers = {} -- Spieler, die über allen Hindernissen "fliegen" (für Ziellinien-Test)
local actionTimer = 0
local function simulateRace(dt)
	local map = MapService:GetRaceMap()
	if not map then
		return
	end
	actionTimer += dt
	for player, speed in speeds do
		if player.Parent and player:GetAttribute("InRace") and player.Character then
			local character = player.Character
			local root = character:FindFirstChild("HumanoidRootPart")
			if root and not character:GetAttribute("Frozen") and gameState:GetAttribute("Phase") == "Racing" then
				local x = root.Position.X + speed * dt
				root.CFrame = CFrame.new(x, groundY(map, x) + (if flyers[player] then 20 else 0), 0)
			end
			if actionTimer >= 0.5 and player ~= alpha then
				Mock.ClientFire(player, "MoveState", "Run", 1)
				if player:GetAttribute("HeldItem") ~= "" then
					Mock.ClientFire(player, "UsePowerUp")
				end
				for _, anchor in map.Anchors do
					if (anchor.Position - root.Position).Magnitude < 50 then
						Mock.ClientFire(player, "GrappleRequest", "Attach", anchor:GetAttribute("AnchorId"))
						Mock.ClientFire(player, "GrappleRequest", "Release")
						break
					end
				end
				-- Manipuliertes Ziel (zu weit weg) muss abgelehnt werden
				Mock.ClientFire(player, "GrappleRequest", "Attach", map.Anchors[#map.Anchors]:GetAttribute("AnchorId"))
			end
		end
	end
	if actionTimer >= 0.5 then
		actionTimer = 0
	end
end

local logStart = #Mock.Log
local elapsed = 0
while gameState:GetAttribute("Phase") ~= "Results" and elapsed < 260 do
	Mock.Run(1, simulateRace)
	elapsed += 1
end
check(gameState:GetAttribute("Phase") == "Results", string.format("Rennen beendet nach %d s", elapsed))
local results, eliminated, pickups, rejected, used = nil, 0, 0, 0, 0
for i = logStart + 1, #Mock.Log do
	local entry = Mock.Log[i]
	if entry.Remote == "GameEvent" then
		local name, payload = entry.Args[1], entry.Args[2]
		if name == "MatchResults" and entry.Player == alpha then
			results = payload
		elseif name == "RacerEliminated" then
			eliminated += 1
		elseif name == "ItemPickup" then
			pickups += 1
		elseif name == "GrappleRejected" then
			rejected += 1
		elseif name == "PowerUpUsed" then
			used += 1
		end
	end
end
check(results ~= nil, "Ergebnisse an Clients gesendet (Grund: " .. tostring(results and results.Reason) .. ")")
check(eliminated >= 1, "Langsamer Spieler von der Gefahrenzone eliminiert (" .. eliminated .. ")")
check(pickups >= 1, "Items eingesammelt (" .. pickups .. ")")
check(used >= 1, "Items eingesetzt (" .. used .. ")")
check(rejected >= 1, "Ungültige Greifhaken-Ziele abgelehnt (" .. rejected .. ")")
if results then
	for _, r in results.Results do
		print(string.format("     Platz %d: %s (%s) Fortschritt %s", r.Placement, r.Name, r.Status, tostring(r.Progress)))
	end
	check(results.Results[1].Placement == 1, "Eindeutiger Gewinner")
	check(results.Rewards ~= nil and results.Rewards.Coins > 0, "Alpha erhält Belohnungen (+" .. tostring(results.Rewards and results.Rewards.Coins) .. " Coins)")
end
local alphaProfile = PlayerData:GetProfile(alpha)
check(alphaProfile.Stats.Races == 1, "Statistik Rennen = 1")
check(alphaProfile.TotalXP > 0, "XP gutgeschrieben (" .. alphaProfile.TotalXP .. ")")
check(#alphaProfile.RecentMatches == 1, "Match-ID gegen Doppelbelohnung gespeichert")

-- Doppelvergabe-Versuch: Rewards erneut aufrufen darf nichts ändern
local Rewards = serverModule("RewardService")
local coinsBefore = alphaProfile.Coins
local fakeMatch = { Id = alphaProfile.RecentMatches[1], Participants = 3, Rewarded = {}, MapId = "X", RacerList = { { Player = alpha, UserId = alpha.UserId, Status = "Finished", Placement = 1, Distance = 0, Respawns = 0 } } }
Rewards:GrantMatchRewards(fakeMatch)
check(alphaProfile.Coins == coinsBefore, "Doppelte Belohnung für dieselbe Match-ID verhindert")

Mock.Run(12)
check(gameState:GetAttribute("Phase") ~= "Results", "Ergebnisphase beendet")
check(alpha:GetAttribute("InRace") == false, "Alpha zurück in der Lobby")
check(#workspace.ActiveMap:GetChildren() == 0 or MapService:GetRaceMap() == nil or gameState:GetAttribute("Phase") ~= "Waiting", "Rennstrecke entladen bzw. neues Match")

print("== 6. Zweites Match (Auto-Requeue) mit Spielern, die verlassen")
local waited = 0
while gameState:GetAttribute("Phase") ~= "Racing" and waited < 30 do
	Mock.Run(1)
	waited += 1
end
check(gameState:GetAttribute("Phase") == "Racing", "Zweites Match läuft (Auto-Requeue)")
local participants = gameState:GetAttribute("Participants")
check(participants >= 2, "Teilnehmer im zweiten Match: " .. tostring(participants))
Mock.Run(3, simulateRace)
Mock.RemovePlayer(charlie)
Mock.Run(1, simulateRace)
Mock.RemovePlayer(bravo)
Mock.Run(1, simulateRace)
local reason = nil
for i = #Mock.Log, 1, -1 do
	local entry = Mock.Log[i]
	if entry.Remote == "GameEvent" and entry.Args[1] == "MatchResults" then
		reason = entry.Args[2].Reason
		break
	end
end
check(reason == "LastStanding", "Letzter verbleibender Spieler gewinnt nach Verlassen (" .. tostring(reason) .. ")")
check(PlayerData:GetProfile(alpha).Stats.Wins >= 1, "Sieg gezählt")
local saved = Mock.Stores.VelocityRush_Profiles_v1 and Mock.Stores.VelocityRush_Profiles_v1.Player_1002
check(saved ~= nil and saved._Lock == nil, "Profil von Bravo beim Verlassen gespeichert und Lock freigegeben")
Mock.Run(12)

print("== 7. Ranked")
local delta = Mock.AddPlayer(1004, "Delta", false)
Mock.Run(3)
Mock.ClientFire(alpha, "QueueRequest", "Leave", "QuickPlay")
Mock.Run(0.5)
Mock.ClientFire(alpha, "QueueRequest", "Join", "Ranked")
Mock.ClientFire(delta, "QueueRequest", "Join", "Ranked")
speeds = { [alpha] = 46, [delta] = 44 }
flyers = { [alpha] = true, [delta] = true }
local ratingBefore = PlayerData:GetProfile(alpha).Ranked.Rating
waited = 0
while gameState:GetAttribute("Phase") ~= "Racing" and waited < 30 do
	Mock.Run(1)
	waited += 1
end
check(gameState:GetAttribute("Mode") == "Ranked", "Ranked-Match gestartet")
elapsed = 0
while gameState:GetAttribute("Phase") ~= "Results" and elapsed < 260 do
	Mock.Run(1, simulateRace)
	elapsed += 1
end
local rankedReason = nil
for i = #Mock.Log, 1, -1 do
	local entry = Mock.Log[i]
	if entry.Remote == "GameEvent" and entry.Args[1] == "MatchResults" then
		rankedReason = entry.Args[2].Reason
		break
	end
end
check(rankedReason == "Finish", "Ranked-Rennen über die Ziellinie entschieden (" .. tostring(rankedReason) .. ")")
check(alpha:GetAttribute("InRace") == true and alpha.Character.HumanoidRootPart.Position.X > 0, "Sieger bleibt zur Siegerehrung auf der Strecke")
check(alpha.Character:GetAttribute("Victory") ~= "", "Siegesanimation gesetzt (" .. tostring(alpha.Character:GetAttribute("Victory")) .. ")")
local bestTime = PlayerData:GetProfile(alpha).Stats.BestTimes
local hasBest = false
for _, t in bestTime do
	hasBest = hasBest or t > 0
end
check(hasBest, "Bestzeit gespeichert")
local ratingAfter = PlayerData:GetProfile(alpha).Ranked.Rating
check(ratingAfter ~= ratingBefore, string.format("Rating geändert: %d -> %d", ratingBefore, ratingAfter))
check(PlayerData:GetProfile(delta).Ranked.Rating < 1000, "Verlierer verliert Rating")
Mock.Run(14)

print("== 8. Herunterfahren")
for _, handler in Mock.CloseHandlers do
	Mock.task.spawn(handler)
end
Mock.Run(3)
local stored = Mock.Stores.VelocityRush_Profiles_v1.Player_1001
check(stored ~= nil and stored.Stats.Races >= 2, "Profil von Alpha gespeichert (Rennen: " .. tostring(stored and stored.Stats.Races) .. ")")

print("")
print(string.format("Ergebnis: %d bestanden, %d fehlgeschlagen, %d Laufzeitfehler, %d Warnungen", passed, failed, #Mock.Errors, #Mock.Warnings))
local unknown = {}
for key, count in Mock.UnknownReads do
	table.insert(unknown, key .. " (" .. count .. ")")
end
table.sort(unknown)
if #unknown > 0 then
	print("Unbekannte Eigenschaften gelesen (zur Prüfung): " .. table.concat(unknown, ", "))
end
local seen = {}
for _, w in Mock.Warnings do
	if not seen[w] then
		seen[w] = true
		print("WARNUNG: " .. w)
	end
end
if failed > 0 or #Mock.Errors > 0 then
	error("Tests fehlgeschlagen")
end
