--[[
	RoundService  (ModuleScript)
	Pfad: ServerScriptService/Server/Services/RoundService

	Serverautoritativer Rundenablauf (Quick Play und Ranked):

		Waiting   -> Warteschlange hat < MinPlayers
		Starting  -> genug Spieler; Countdown (verkürzt bei voller Lobby)
		Loading   -> Map wird gebaut, Spieler an Spawnpunkte gesetzt
		Countdown -> 3-2-1-GO, Spieler eingefroren
		Racing    -> Rennen läuft (10 Hz Server-Tick)
		Results   -> Ergebnisse + Belohnungen, danach zurück zur Lobby

	REGELN (eindeutig):
		Sieg:       a) Wer zuerst die Ziellinie überquert, gewinnt sofort.
		            b) Ist nur noch ein Spieler übrig (bei ≥ 2 Startern), gewinnt er.
		            c) Nach MaxRaceTime gewinnt, wer am weitesten vorn ist.
		Ausscheiden: Wer EliminationDelay Sekunden hinter der Gefahrenwand ist.
		            Platzierung = Anzahl der zu diesem Zeitpunkt noch aktiven Spieler.
		Respawn:    Sturz in Gefahr/Abgrund -> letzter Checkpoint, kurz eingefroren.
		            Kein Respawn nach dem Ausscheiden (Zuschauer in der Lobby).
		Verlassen:  Zählt als Ausscheiden ("Left"), keine Belohnung, Ranked-Strafe.
		            Bricht ein Match vor dem Start unter MinPlayers ab, kommen die
		            übrigen Spieler zurück in die Warteschlange.

	Doppelte Rundenenden sind ausgeschlossen: _endMatch prüft match.Ended und
	läuft ohne Yield bis zur Vergabe der Ergebnisse.

	Repliziert über ReplicatedStorage/GameState (Attribute) und
	GameState/Racers/<UserId> (Attribute pro Rennfahrer).

	Öffentliche API:
		:GetPhase() -> string
		:IsActiveRacer(player) -> boolean   (im laufenden Match, nicht ausgeschieden)
		:IsInMatch(player) -> boolean       (Teilnehmer, noch nicht zurück in der Lobby)
		:GetRacer(player) -> racer?
		:GetPlacementInfo(player) -> (placement?, aliveCount?)
		:RespawnRacer(player, reason)
		:GetRespawnCFrame(player) -> CFrame?
		:OnPlayerRemoving(player)
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local RoundService = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

function RoundService:Init(services)
	self.Services = services
	self.Phase = "Waiting"
	self.Match = nil

	local state = ReplicatedStorage:FindFirstChild("GameState")
	if not state then
		state = Instance.new("Folder")
		state.Name = "GameState"
		state.Parent = ReplicatedStorage
	end
	local racers = state:FindFirstChild("Racers")
	if not racers then
		racers = Instance.new("Folder")
		racers.Name = "Racers"
		racers.Parent = state
	end
	self.State = state
	self.RacersFolder = racers

	local defaults = {
		Phase = "Waiting",
		PhaseEndsAt = 0,
		MatchId = "",
		Mode = "",
		MapId = "",
		NextMapId = "",
		QueueQuickPlay = 0,
		QueueRanked = 0,
		RaceStartedAt = 0,
		Alive = 0,
		Participants = 0,
		StartX = 0,
		FinishX = 0,
		CheckpointXs = "",
		MinPlayers = self:_minPlayers(),
		MaxPlayers = Config.Round.MaxPlayers,
		ZoneState = "Inactive",
		ZoneX = -1e6,
		ZoneLength = 0,
		ZoneWarnAt = 0,
		ZoneShrinkAt = 0,
	}
	for key, value in defaults do
		state:SetAttribute(key, value)
	end
end

function RoundService:Start()
	self.Services.CharacterService.CharacterReady:Connect(function(player, character)
		local racer = self:GetRacer(player)
		if racer and self.Match and not self.Match.Ended then
			if self.Phase == "Loading" or self.Phase == "Countdown" or racer.RespawnLock then
				character:SetAttribute("Frozen", true)
			end
		end
	end)
	task.spawn(function()
		self:_runLoop()
	end)
end

function RoundService:_minPlayers(): number
	return if Config.Debug.AllowSoloRace then 1 else Config.Round.MinPlayers
end

function RoundService:_setPhase(phase: string, endsAt: number)
	self.Phase = phase
	self.State:SetAttribute("Phase", phase)
	self.State:SetAttribute("PhaseEndsAt", endsAt)
end

------------------------------------------------------------------------
-- Öffentliche API
------------------------------------------------------------------------

function RoundService:GetPhase(): string
	return self.Phase
end

function RoundService:GetRacer(player: Player)
	local match = self.Match
	return match and match.Racers[player] or nil
end

function RoundService:IsActiveRacer(player: Player): boolean
	local match = self.Match
	if not match or match.Ended then
		return false
	end
	local racer = match.Racers[player]
	return racer ~= nil and racer.Status == "Racing"
end

function RoundService:IsInMatch(player: Player): boolean
	return self:GetRacer(player) ~= nil and player:GetAttribute("InRace") == true
end

function RoundService:GetPlacementInfo(player: Player): (number?, number?)
	local racer = self:GetRacer(player)
	if not racer or not self.Match then
		return nil, nil
	end
	return racer.Placement, self.Match.AliveCount or 0
end

function RoundService:GetRespawnCFrame(player: Player): CFrame?
	if not self:IsActiveRacer(player) then
		return nil
	end
	local racer = self:GetRacer(player)
	local map = self.Match.Map
	if not map then
		return nil
	end
	local checkpoint = map.Checkpoints[racer.Checkpoint] or map.Checkpoints[1]
	if checkpoint then
		return checkpoint.CFrame
	end
	return map.Spawns[1]
end

function RoundService:RespawnRacer(player: Player, reason: string)
	if self.Phase ~= "Racing" then
		return
	end
	local racer = self:GetRacer(player)
	if racer and racer.Status == "Racing" then
		self:_respawnRacer(self.Match, racer, reason)
	end
end

function RoundService:OnPlayerRemoving(player: Player)
	local match = self.Match
	if not match then
		return
	end
	local racer = match.Racers[player]
	if not racer then
		return
	end
	racer.Player = nil
	racer.LeftGame = true
	if match.Ended or racer.Status ~= "Racing" then
		return
	end
	if self.Phase == "Racing" then
		self:_eliminate(match, racer, "Left", player)
	else
		-- Vor dem Start verlassen: zählt als Letzter, Match prüft Abbruch selbst.
		racer.Status = "Left"
		racer.Placement = self:_aliveCount(match) + 1
		if match.Mode == "Ranked" then
			self.Services.RankedService:ApplyLeavePenalty(match, racer, player)
		end
	end
end

------------------------------------------------------------------------
-- Ablauf
------------------------------------------------------------------------

function RoundService:_runLoop()
	while true do
		local ok, err = xpcall(function()
			local mode = self:_waitForQueue()
			if self:_startingCountdown(mode) then
				local players = self.Services.MatchmakingService:TakePlayers(mode, Config.Round.MaxPlayers)
				if #players >= self:_minPlayers() then
					self:_runMatch(mode, players)
				else
					for _, player in players do
						self.Services.MatchmakingService:Join(player, mode)
					end
				end
			end
		end, debug.traceback)
		if not ok then
			warn("[RoundService] Fehler im Rundenablauf:\n" .. tostring(err))
			self:_emergencyCleanup()
		end
		self:_setPhase("Waiting", 0)
		task.wait(0.5)
	end
end

function RoundService:_waitForQueue(): string
	self:_setPhase("Waiting", 0)
	while true do
		local mode = self.Services.MatchmakingService:GetReadyMode(self:_minPlayers())
		if mode then
			return mode
		end
		task.wait(0.5)
	end
end

function RoundService:_startingCountdown(mode: string): boolean
	local matchmaking = self.Services.MatchmakingService
	local endsAt = now() + Config.Round.StartingCountdown
	self.State:SetAttribute("Mode", mode)
	self:_setPhase("Starting", endsAt)
	while true do
		local count = matchmaking:GetCount(mode)
		if count < self:_minPlayers() then
			self.State:SetAttribute("Mode", "")
			return false
		end
		if count >= Config.Round.MaxPlayers then
			local short = now() + Config.Round.FullLobbyCountdown
			if short < endsAt then
				endsAt = short
				self.State:SetAttribute("PhaseEndsAt", endsAt)
			end
		end
		if now() >= endsAt then
			return true
		end
		task.wait(0.25)
	end
end

function RoundService:_aliveCount(match): number
	local alive = 0
	for _, racer in match.RacerList do
		if racer.Status == "Racing" then
			alive += 1
		end
	end
	return alive
end

function RoundService:_runMatch(mode: string, players: { Player })
	local services = self.Services
	local mapId = services.MapService:AdvanceRotation()
	self:_setPhase("Loading", 0)

	local match = {
		Id = HttpService:GenerateGUID(false),
		Mode = mode,
		MapId = mapId,
		Racers = {},
		RacerList = {},
		StartedAt = 0,
		Ended = false,
		Participants = #players,
		AliveCount = #players,
		Rewarded = {},
	}
	self.Match = match

	for index, player in players do
		local racer = {
			Player = player,
			UserId = player.UserId,
			Name = player.DisplayName,
			Status = "Racing",
			Placement = index,
			Checkpoint = 1,
			DangerTime = 0,
			Respawns = 0,
			Distance = 0,
			LastPosition = nil,
			FinishTime = nil,
			RespawnLock = false,
		}
		match.Racers[player] = racer
		table.insert(match.RacerList, racer)
		services.PracticeService:ForceLeave(player)
		player:SetAttribute("InRace", true)
	end

	self.State:SetAttribute("MatchId", match.Id)
	self.State:SetAttribute("Mode", mode)
	self.State:SetAttribute("MapId", mapId)
	self.State:SetAttribute("Participants", #players)

	local map = services.MapService:LoadRaceMap(mapId)
	match.Map = map
	local checkpointXs = {}
	for _, checkpoint in map.Checkpoints do
		table.insert(checkpointXs, tostring(math.floor(checkpoint.X)))
	end
	self.State:SetAttribute("StartX", map.StartX)
	self.State:SetAttribute("FinishX", map.FinishX or 0)
	self.State:SetAttribute("CheckpointXs", table.concat(checkpointXs, ","))

	for _, racer in match.RacerList do
		self:_createRacerFolder(racer)
	end

	if self:_aliveCount(match) < self:_minPlayers() then
		self:_abortMatch(match)
		return
	end

	-- Spieler an Spawnpunkte setzen
	for index, racer in match.RacerList do
		local player = racer.Player
		if player and racer.Status == "Racing" then
			local spawnCFrame = map.Spawns[((index - 1) % #map.Spawns) + 1]
			services.CharacterService:ClearStatus(player)
			services.PowerUpService:ClearPlayer(player)
			services.CharacterService:SetFrozen(player, true)
			if not services.CharacterService:Teleport(player, spawnCFrame) then
				services.CharacterService:Spawn(player)
			end
			racer.LastPosition = spawnCFrame.Position
		end
	end

	-- Countdown
	local countdownEnd = now() + Config.Round.CountdownDuration
	self:_setPhase("Countdown", countdownEnd)
	Remotes.GameEvent:FireAllClients("MatchStarted", { MatchId = match.Id, MapId = mapId, Mode = mode })
	while now() < countdownEnd do
		task.wait(0.1)
		if self:_aliveCount(match) < self:_minPlayers() then
			self:_abortMatch(match)
			return
		end
	end

	-- Start
	match.StartedAt = now()
	self.State:SetAttribute("RaceStartedAt", match.StartedAt)
	for _, racer in match.RacerList do
		if racer.Player and racer.Status == "Racing" then
			services.CharacterService:SetFrozen(racer.Player, false)
		end
	end
	services.HazardRingService:Begin(match)
	self:_setPhase("Racing", match.StartedAt + Config.Round.MaxRaceTime)

	local tick = 1 / Config.Round.TickRate
	while not match.Ended do
		local dt = task.wait(tick)
		local ok, err = xpcall(function()
			self:_raceTick(match, dt)
		end, debug.traceback)
		if not ok then
			warn("[RoundService] Fehler im Renn-Tick:\n" .. tostring(err))
		end
	end

	-- Ergebnisphase (Phase wurde in _endMatch gesetzt)
	task.wait(Config.Round.ReturnToLobbyDelay)
	for _, racer in match.RacerList do
		local player = racer.Player
		if player and player.Parent and player:GetAttribute("InRace") then
			self:_returnToLobby(player)
		end
	end
	while now() < (self.State:GetAttribute("PhaseEndsAt") or 0) do
		task.wait(0.25)
	end
	self:_cleanupMatch(match, true)
end

function RoundService:_returnToLobby(player: Player)
	local services = self.Services
	player:SetAttribute("InRace", false)
	services.GrappleService:Release(player, true)
	services.PowerUpService:ClearPlayer(player)
	services.CharacterService:ClearStatus(player)
	services.CharacterService:SetFrozen(player, false)
	services.CharacterService:SendToLobby(player)
end

function RoundService:_abortMatch(match)
	Remotes.GameEvent:FireAllClients("Notify", {
		Text = "Rennen abgebrochen – zu wenige Spieler. Zurück in die Warteschlange.",
		Kind = "Warning",
	})
	match.Ended = true
	for _, racer in match.RacerList do
		local player = racer.Player
		if player and player.Parent then
			self:_returnToLobby(player)
			if racer.Status == "Racing" then
				self.Services.MatchmakingService:Join(player, match.Mode)
			end
		end
	end
	self:_cleanupMatch(match, false)
end

function RoundService:_cleanupMatch(match, requeue: boolean)
	local services = self.Services
	services.HazardRingService:Reset()
	services.MapService:UnloadRaceMap()
	self.RacersFolder:ClearAllChildren()
	for _, key in { "MatchId", "Mode", "MapId", "CheckpointXs" } do
		self.State:SetAttribute(key, "")
	end
	for _, key in { "RaceStartedAt", "Alive", "Participants", "StartX", "FinishX" } do
		self.State:SetAttribute(key, 0)
	end
	if self.Match == match then
		self.Match = nil
	end
	for _, racer in match.RacerList do
		local player = racer.Player
		if player and player.Parent then
			player:SetAttribute("InRace", false)
			if requeue then
				local profile = services.PlayerDataService:GetProfile(player)
				if profile and profile.Settings.AutoRequeue then
					services.MatchmakingService:Join(player, match.Mode)
				end
			end
		end
	end
end

function RoundService:_emergencyCleanup()
	local match = self.Match
	if not match then
		return
	end
	match.Ended = true
	for _, racer in match.RacerList do
		local player = racer.Player
		if player and player.Parent then
			pcall(function()
				self:_returnToLobby(player)
			end)
		end
	end
	pcall(function()
		self:_cleanupMatch(match, false)
	end)
	self.Match = nil
end

------------------------------------------------------------------------
-- Renn-Tick
------------------------------------------------------------------------

function RoundService:_createRacerFolder(racer)
	local folder = Instance.new("Configuration")
	folder.Name = tostring(racer.UserId)
	folder:SetAttribute("UserId", racer.UserId)
	folder:SetAttribute("Name", racer.Name)
	folder:SetAttribute("Status", racer.Status)
	folder:SetAttribute("Placement", racer.Placement)
	folder:SetAttribute("Progress", 0)
	folder:SetAttribute("DangerTime", 0)
	folder:SetAttribute("Checkpoint", 1)
	folder:SetAttribute("Respawns", 0)
	folder.Parent = self.RacersFolder
	racer.Folder = folder
end

function RoundService:_raceTick(match, dt: number)
	if match.Ended then
		return
	end
	local services = self.Services
	local map = match.Map
	for _, racer in match.RacerList do
		if racer.Status == "Racing" and racer.Player then
			local root = services.CharacterService:GetRoot(racer.Player)
			if root then
				local position = root.Position
				local previous = racer.LastPosition
				racer.LastPosition = position
				if previous then
					racer.Distance += math.max(0, position.X - previous.X)
				end
				local checkpointIndex = services.MapService:FindCheckpointIndex(map, position.X)
				if checkpointIndex > racer.Checkpoint then
					racer.Checkpoint = checkpointIndex
				end
				if not racer.RespawnLock then
					local hit, kind = services.MapService:IsInHazard(map, position, previous)
					if hit then
						self:_respawnRacer(match, racer, kind or "Hazard")
					end
				end
				if map.FinishX and position.X >= map.FinishX and racer.Checkpoint >= #map.Checkpoints and not racer.RespawnLock then
					self:_finish(match, racer)
					return
				end
			end
		end
	end

	for _, racer in services.HazardRingService:Update(match, dt) do
		self:_eliminate(match, racer, "Zone")
		if match.Ended then
			return
		end
	end

	self:_updateStandings(match)

	if now() >= match.StartedAt + Config.Round.MaxRaceTime then
		self:_endMatch(match, "Timeout")
		return
	end
	self:_checkEnd(match)
end

function RoundService:_updateStandings(match)
	local alive = {}
	for _, racer in match.RacerList do
		if racer.Status == "Racing" then
			table.insert(alive, racer)
		end
	end
	table.sort(alive, function(a, b)
		local ax = a.LastPosition and a.LastPosition.X or -math.huge
		local bx = b.LastPosition and b.LastPosition.X or -math.huge
		return ax > bx
	end)
	for index, racer in alive do
		racer.Placement = index
	end
	match.AliveCount = #alive
	self.State:SetAttribute("Alive", #alive)
	local startX = match.Map.StartX
	for _, racer in match.RacerList do
		local folder = racer.Folder
		if folder then
			folder:SetAttribute("Status", racer.Status)
			folder:SetAttribute("Placement", racer.Placement or 0)
			if racer.LastPosition then
				folder:SetAttribute("Progress", math.floor(racer.LastPosition.X - startX))
			end
			folder:SetAttribute("DangerTime", math.floor(racer.DangerTime * 10) / 10)
			folder:SetAttribute("Checkpoint", racer.Checkpoint)
			folder:SetAttribute("Respawns", racer.Respawns)
		end
	end
end

function RoundService:_respawnRacer(match, racer, reason: string)
	if racer.RespawnLock or racer.Status ~= "Racing" or not racer.Player then
		return
	end
	local services = self.Services
	local player = racer.Player
	local map = match.Map
	racer.RespawnLock = true
	racer.Respawns += 1
	local checkpoint = map.Checkpoints[racer.Checkpoint] or map.Checkpoints[1]
	Remotes.GameEvent:FireAllClients("RacerRespawn", {
		UserId = racer.UserId,
		From = racer.LastPosition,
		To = checkpoint.CFrame.Position,
		Reason = reason,
	})
	services.CharacterService:Teleport(player, checkpoint.CFrame)
	services.CharacterService:SetFrozen(player, true)
	racer.LastPosition = checkpoint.CFrame.Position
	task.delay(Config.Round.RespawnFreezeTime, function()
		racer.RespawnLock = false
		if racer.Status == "Racing" and racer.Player and not match.Ended then
			services.CharacterService:SetFrozen(racer.Player, false)
		end
	end)
end

function RoundService:_eliminate(match, racer, reason: string, leavingPlayer: Player?)
	if racer.Status ~= "Racing" or match.Ended then
		return
	end
	local services = self.Services
	racer.Placement = self:_aliveCount(match)
	racer.Status = if reason == "Left" then "Left" else "Eliminated"
	racer.EliminatedAt = now()
	local player = racer.Player or leavingPlayer
	Remotes.GameEvent:FireAllClients("RacerEliminated", {
		UserId = racer.UserId,
		Name = racer.Name,
		Placement = racer.Placement,
		Position = racer.LastPosition,
		Reason = reason,
	})
	if racer.Folder then
		racer.Folder:SetAttribute("Status", racer.Status)
		racer.Folder:SetAttribute("Placement", racer.Placement)
	end
	if reason == "Left" then
		if match.Mode == "Ranked" then
			services.RankedService:ApplyLeavePenalty(match, racer, player)
		end
	elseif player then
		services.GrappleService:Release(player, true)
		services.PowerUpService:ClearPlayer(player)
		services.CharacterService:SetFrozen(player, true)
		task.delay(1.2, function()
			if player.Parent and racer.Player == player and player:GetAttribute("InRace") then
				self:_returnToLobby(player)
			end
		end)
	end
	self:_checkEnd(match)
end

function RoundService:_finish(match, racer)
	if match.Ended or racer.Status ~= "Racing" then
		return
	end
	racer.Status = "Finished"
	racer.FinishTime = now() - match.StartedAt
	Remotes.GameEvent:FireAllClients("RacerFinished", {
		UserId = racer.UserId,
		Name = racer.Name,
		Time = racer.FinishTime,
	})
	self:_endMatch(match, "Finish")
end

function RoundService:_checkEnd(match)
	if match.Ended then
		return
	end
	local alive = {}
	for _, racer in match.RacerList do
		if racer.Status == "Racing" then
			table.insert(alive, racer)
		end
	end
	if #alive == 0 then
		self:_endMatch(match, "NoRacers")
	elseif match.Participants >= 2 and #alive == 1 then
		self:_endMatch(match, "LastStanding")
	end
end

--- Beendet das Match genau einmal: Platzierungen, Belohnungen, Ergebnisse.
function RoundService:_endMatch(match, reason: string)
	if match.Ended then
		return
	end
	match.Ended = true
	match.EndReason = reason
	match.Duration = now() - match.StartedAt
	local services = self.Services
	services.HazardRingService:Reset()

	-- Endplatzierungen der noch nicht ausgeschiedenen Spieler
	local standing = {}
	for _, racer in match.RacerList do
		if racer.Status == "Racing" or racer.Status == "Finished" then
			table.insert(standing, racer)
		end
	end
	table.sort(standing, function(a, b)
		if (a.Status == "Finished") ~= (b.Status == "Finished") then
			return a.Status == "Finished"
		end
		local ax = a.LastPosition and a.LastPosition.X or -math.huge
		local bx = b.LastPosition and b.LastPosition.X or -math.huge
		return ax > bx
	end)
	for index, racer in standing do
		racer.Placement = index
		if racer.Status == "Racing" then
			racer.Status = "Survived"
		end
	end
	local winner = standing[1]
	match.Winner = winner

	-- Belohnungen (serverseitig, einmalig pro Match und Spieler)
	local summaries = {}
	local ok, err = pcall(function()
		summaries = services.RewardService:GrantMatchRewards(match)
	end)
	if not ok then
		warn("[RoundService] Belohnungen fehlgeschlagen: " .. tostring(err))
	end
	if match.Mode == "Ranked" then
		local rankedOk, rankedErr = pcall(function()
			services.RankedService:ApplyMatch(match, summaries)
		end)
		if not rankedOk then
			warn("[RoundService] Ranked-Wertung fehlgeschlagen: " .. tostring(rankedErr))
		end
	end
	pcall(function()
		services.LeaderboardService:OnMatchEnded(match)
	end)

	local results = {}
	for _, racer in match.RacerList do
		local summary = summaries[racer.UserId]
		table.insert(results, {
			UserId = racer.UserId,
			Name = racer.Name,
			Placement = racer.Placement or #match.RacerList,
			Status = racer.Status,
			Time = racer.FinishTime,
			Progress = if racer.LastPosition then math.floor(racer.LastPosition.X - match.Map.StartX) else 0,
			Respawns = racer.Respawns,
			RatingChange = if summary then summary.RatingChange else nil,
		})
	end
	table.sort(results, function(a, b)
		return a.Placement < b.Placement
	end)
	self:_updateStandings(match)

	self:_setPhase("Results", now() + Config.Round.ResultsDuration)

	-- Alle verbleibenden Rennfahrer anhalten, Effekte bereinigen
	for _, racer in match.RacerList do
		local player = racer.Player
		if player and player.Parent and player:GetAttribute("InRace") then
			services.GrappleService:Release(player, true)
			services.PowerUpService:ClearPlayer(player)
			services.CharacterService:SetFrozen(player, true)
		end
	end
	services.MapService:ResetRaceMap()

	-- Siegesanimation
	if winner and winner.Player and winner.Player.Parent then
		local character = winner.Player.Character
		local equipped = services.InventoryService:GetEquipped(winner.Player)
		local victoryId = if equipped.Victory ~= "" then equipped.Victory else "Default"
		if character then
			character:SetAttribute("Victory", victoryId)
			character:SetAttribute("VictoryAt", now())
		end
	end

	for _, player in Players:GetPlayers() do
		Remotes.GameEvent:FireClient(player, "MatchResults", {
			MatchId = match.Id,
			MapId = match.MapId,
			Mode = match.Mode,
			Reason = reason,
			Duration = match.Duration,
			WinnerUserId = if winner then winner.UserId else 0,
			Results = results,
			Rewards = summaries[player.UserId],
		})
	end
end

return RoundService
