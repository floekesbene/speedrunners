--[[
	LeaderboardService  (ModuleScript)
	Pfad: ServerScriptService/Server/Services/LeaderboardService

	Globale Bestenlisten mit OrderedDataStore:
		- Siege (gesamt)
		- Ranked-Rating der aktuellen Saison
	Schreibzugriffe nur nach Matchende (gebündelt, asynchron), Lesezugriffe
	alle Config.Leaderboard.RefreshInterval Sekunden mit Cache.

	RemoteFunction "GetLeaderboard" liefert:
		{ Wins = {...}, Rating = {...}, Server = {...}, Available = boolean }
		Einträge: { Rank, UserId, Name, Value }

	Öffentliche API:
		:OnMatchEnded(match)
		:GetBoards() -> table
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local RateLimiter = require(script.Parent.Parent.Modules.RateLimiter)

local LeaderboardService = {}

function LeaderboardService:Init(services)
	self.Services = services
	self.Cache = { Wins = {}, Rating = {} }
	self.NameCache = {}
	self.Available = false
	self.Limiter = RateLimiter.ForRemote("GetLeaderboard")
	self.PendingWrites = {}
end

function LeaderboardService:Start()
	local data = self.Services.PlayerDataService
	if data:IsPersistent() then
		local ok = pcall(function()
			self.WinsStore = DataStoreService:GetOrderedDataStore(Config.Leaderboard.WinsStore)
			self.RatingStore = DataStoreService:GetOrderedDataStore(Config.Leaderboard.RatingStorePrefix .. tostring(Config.Ranked.Season))
		end)
		self.Available = ok
	end

	Remotes.GetLeaderboard.OnServerInvoke = function(player)
		if not self.Limiter:Check(player) then
			return nil
		end
		return self:GetBoards()
	end

	if self.Available then
		task.spawn(function()
			while true do
				self:_flushWrites()
				self:_refresh()
				task.wait(Config.Leaderboard.RefreshInterval)
			end
		end)
	end
end

function LeaderboardService:_name(userId: number): string
	local cached = self.NameCache[userId]
	if cached then
		return cached
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		self.NameCache[userId] = player.DisplayName
		return player.DisplayName
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = if ok and name then name else ("#" .. tostring(userId))
	self.NameCache[userId] = result
	return result
end

function LeaderboardService:_readStore(store)
	local entries = {}
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, Config.Leaderboard.Size)
	end)
	if not ok or not pages then
		return nil
	end
	local page = pages:GetCurrentPage()
	for rank, item in page do
		local userId = tonumber(item.key)
		if userId then
			table.insert(entries, { Rank = rank, UserId = userId, Name = self:_name(userId), Value = item.value })
		end
	end
	return entries
end

function LeaderboardService:_refresh()
	local wins = self:_readStore(self.WinsStore)
	if wins then
		self.Cache.Wins = wins
	end
	local rating = self:_readStore(self.RatingStore)
	if rating then
		self.Cache.Rating = rating
	end
end

function LeaderboardService:_flushWrites()
	local pending = self.PendingWrites
	self.PendingWrites = {}
	for userId, values in pending do
		pcall(function()
			self.WinsStore:SetAsync(tostring(userId), values.Wins)
		end)
		if values.Rating then
			pcall(function()
				self.RatingStore:SetAsync(tostring(userId), values.Rating)
			end)
		end
	end
end

--- Merkt Werte zum Schreiben vor (kein Yield – sicher aus dem Rundenende aufrufbar).
function LeaderboardService:OnMatchEnded(match)
	if not self.Available then
		return
	end
	for _, racer in match.RacerList do
		local player = racer.Player
		if player then
			local profile = self.Services.PlayerDataService:GetProfile(player)
			if profile then
				self.PendingWrites[player.UserId] = {
					Wins = profile.Stats.Wins,
					Rating = if match.Mode == "Ranked" then profile.Ranked.Rating else nil,
				}
			end
		end
	end
	task.delay(5, function()
		self:_flushWrites()
	end)
end

function LeaderboardService:GetBoards()
	local server = {}
	for _, player in Players:GetPlayers() do
		local profile = self.Services.PlayerDataService:GetProfile(player)
		if profile then
			table.insert(server, {
				UserId = player.UserId,
				Name = player.DisplayName,
				Level = profile.Level,
				Wins = profile.Stats.Wins,
				Rating = profile.Ranked.Rating,
			})
		end
	end
	table.sort(server, function(a, b)
		if a.Wins ~= b.Wins then
			return a.Wins > b.Wins
		end
		return a.Level > b.Level
	end)
	for rank, entry in server do
		entry.Rank = rank
		entry.Value = entry.Wins
	end
	return {
		Available = self.Available,
		Wins = self.Cache.Wins,
		Rating = self.Cache.Rating,
		Server = server,
	}
end

return LeaderboardService
