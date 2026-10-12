--[[
	MatchmakingService  (ModuleScript)
	Pfad: ServerScriptService/Server/Services/MatchmakingService

	Warteschlangen innerhalb EINES Roblox-Servers (Quick Play und Ranked).
	Der RoundService fragt regelmäßig, ob eine Warteschlange startbereit ist,
	und entnimmt dann bis zu 8 Spieler.

	Quick Play: Reihenfolge des Beitritts (FIFO).
	Ranked:     Spieler werden nach Rating sortiert; gewählt wird das Fenster
	            mit der geringsten Rating-Spanne, das den am längsten wartenden
	            Spieler enthält (Matchmaking nach Spielstärke).

	Serverübergreifendes Matchmaking (MemoryStoreService + TeleportService) ist
	bewusst noch nicht aktiv – siehe README, Abschnitt "Nächste Schritte".

	Öffentliche API:
		:Join(player, mode) -> (boolean, string)
		:Leave(player)
		:IsQueued(player) -> mode?
		:GetCount(mode) -> number
		:GetReadyMode(minPlayers) -> mode?
		:TakePlayers(mode, max) -> { Player }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)

local RateLimiter = require(script.Parent.Parent.Modules.RateLimiter)

local MatchmakingService = {}

local MODES = { QuickPlay = true, Ranked = true }

function MatchmakingService:Init(services)
	self.Services = services
	self.Queues = { QuickPlay = {}, Ranked = {} }
	self.Limiter = RateLimiter.ForRemote("QueueRequest")
end

function MatchmakingService:Start()
	Remotes.QueueRequest.OnServerEvent:Connect(function(player, action, mode)
		if not self.Limiter:Check(player) then
			return
		end
		if action == "Join" then
			local ok, message = self:Join(player, mode)
			Remotes.GameEvent:FireClient(player, "Notify", {
				Text = message,
				Kind = if ok then "Success" else "Warning",
			})
		elseif action == "Leave" then
			if self:IsQueued(player) then
				self:Leave(player)
				Remotes.GameEvent:FireClient(player, "Notify", { Text = "Warteschlange verlassen.", Kind = "Info" })
			end
		end
	end)
	self:_publish()
end

function MatchmakingService:OnPlayerRemoving(player: Player)
	self:Leave(player)
end

function MatchmakingService:Join(player: Player, mode: any): (boolean, string)
	if type(mode) ~= "string" or not MODES[mode] then
		return false, "Ungültiger Spielmodus."
	end
	local services = self.Services
	if not services.PlayerDataService:GetProfile(player) then
		return false, "Dein Profil wird noch geladen."
	end
	if services.RoundService:IsInMatch(player) then
		return false, "Du bist bereits in einem Rennen."
	end
	if self:IsQueued(player) == mode then
		return true, "Du bist bereits in der Warteschlange."
	end
	self:_remove(player)
	table.insert(self.Queues[mode], { Player = player, JoinedAt = os.clock() })
	player:SetAttribute("Queue", mode)
	self:_publish()
	local label = if mode == "Ranked" then "Ranked" else "Schnelles Spiel"
	return true, label .. ": Warteschlange beigetreten."
end

function MatchmakingService:_remove(player: Player): boolean
	local removed = false
	for _, queue in self.Queues do
		for i = #queue, 1, -1 do
			if queue[i].Player == player then
				table.remove(queue, i)
				removed = true
			end
		end
	end
	return removed
end

function MatchmakingService:Leave(player: Player)
	self:_remove(player)
	if player.Parent then
		player:SetAttribute("Queue", "")
	end
	self:_publish()
end

function MatchmakingService:IsQueued(player: Player): string?
	for mode, queue in self.Queues do
		for _, entry in queue do
			if entry.Player == player then
				return mode
			end
		end
	end
	return nil
end

function MatchmakingService:GetCount(mode: string): number
	local queue = self.Queues[mode]
	return if queue then #queue else 0
end

--- Liefert den Modus, der zuerst starten sollte (genug Spieler, längste Wartezeit).
function MatchmakingService:GetReadyMode(minPlayers: number): string?
	local best, bestTime = nil, math.huge
	for mode, queue in self.Queues do
		if #queue >= minPlayers and queue[1].JoinedAt < bestTime then
			best = mode
			bestTime = queue[1].JoinedAt
		end
	end
	return best
end

function MatchmakingService:_rating(player: Player): number
	local profile = self.Services.PlayerDataService:GetProfile(player)
	return profile and profile.Ranked.Rating or 1000
end

--- Entnimmt bis zu `max` Spieler aus der Warteschlange.
function MatchmakingService:TakePlayers(mode: string, max: number): { Player }
	local queue = self.Queues[mode]
	if not queue or #queue == 0 then
		return {}
	end
	local chosen = {}
	if mode == "Ranked" and #queue > max then
		local oldest = queue[1]
		local sorted = table.clone(queue)
		table.sort(sorted, function(a, b)
			return self:_rating(a.Player) < self:_rating(b.Player)
		end)
		local oldestIndex = table.find(sorted, oldest) or 1
		local bestStart, bestSpread = 1, math.huge
		for start = math.max(1, oldestIndex - max + 1), math.min(oldestIndex, #sorted - max + 1) do
			local spread = self:_rating(sorted[start + max - 1].Player) - self:_rating(sorted[start].Player)
			if spread < bestSpread then
				bestSpread = spread
				bestStart = start
			end
		end
		for i = bestStart, bestStart + max - 1 do
			table.insert(chosen, sorted[i].Player)
		end
	else
		for i = 1, math.min(max, #queue) do
			table.insert(chosen, queue[i].Player)
		end
	end
	for _, player in chosen do
		self:_remove(player)
		player:SetAttribute("Queue", "")
	end
	self:_publish()
	return chosen
end

function MatchmakingService:_publish()
	local state = ReplicatedStorage:FindFirstChild("GameState")
	if state then
		state:SetAttribute("QueueQuickPlay", #self.Queues.QuickPlay)
		state:SetAttribute("QueueRanked", #self.Queues.Ranked)
	end
end

return MatchmakingService
