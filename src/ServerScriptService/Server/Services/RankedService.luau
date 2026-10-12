--[[
	RankedService  (ModuleScript)
	Pfad: ServerScriptService/Server/Services/RankedService

	Rangpunkte (Elo-artig, mehrspielerfähig) für den Ranked-Modus.
	- Berechnung ausschließlich auf dem Server nach Matchende.
	- Jedes Match wird pro Spieler genau einmal gewertet (match.RankedApplied).
	- Leaver werden beim Verlassen sofort als Letzter gewertet.
	- Saisonwechsel: Rating wird weich zurückgesetzt, Saisonstatistik neu.

	Öffentliche API:
		:EnsureSeason(player)
		:ApplyMatch(match, summaries)
		:ApplyLeavePenalty(match, racer, player)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Progression = require(Shared.Progression)

local RankedService = {}

function RankedService:Init(services)
	self.Services = services
end

function RankedService:Start()
	self.Services.PlayerDataService.ProfileLoaded:Connect(function(player)
		self:EnsureSeason(player)
	end)
end

function RankedService:EnsureSeason(player: Player)
	local data = self.Services.PlayerDataService
	local profile = data:GetProfile(player)
	if not profile then
		return
	end
	local ranked = profile.Ranked
	if ranked.Season ~= Config.Ranked.Season then
		ranked.Rating = math.floor((ranked.Rating + Config.Ranked.StartRating) / 2)
		ranked.Season = Config.Ranked.Season
		ranked.Games = 0
		ranked.Wins = 0
		ranked.Peak = ranked.Rating
		data:MarkDirty(player)
	end
end

function RankedService:_entries(match, includeLeaver)
	local entries = {}
	for _, racer in match.RacerList do
		local player = racer.Player or (includeLeaver and racer == includeLeaver.Racer and includeLeaver.Player)
		local rating = racer.RatingAtStart
		if not rating and player then
			local profile = self.Services.PlayerDataService:GetProfile(player)
			rating = profile and profile.Ranked.Rating or Config.Ranked.StartRating
		end
		racer.RatingAtStart = rating or Config.Ranked.StartRating
		table.insert(entries, {
			Key = racer,
			Rating = racer.RatingAtStart,
			Placement = racer.Placement or #match.RacerList,
		})
	end
	return entries
end

function RankedService:_apply(player: Player, racer, delta: number)
	local data = self.Services.PlayerDataService
	local profile = data:GetProfile(player)
	if not profile then
		return nil
	end
	local ranked = profile.Ranked
	local old = ranked.Rating
	ranked.Rating = math.max(Config.Ranked.MinRating, old + delta)
	ranked.Games += 1
	if racer.Placement == 1 then
		ranked.Wins += 1
	end
	ranked.Peak = math.max(ranked.Peak, ranked.Rating)
	data:MarkDirty(player)
	data:PushProfile(player)
	self.Services.EconomyService:UpdateLeaderstats(player)
	return ranked.Rating - old, ranked.Rating
end

--- Wertet ein beendetes Ranked-Match (nur noch nicht gewertete Spieler).
function RankedService:ApplyMatch(match, summaries)
	match.RankedApplied = match.RankedApplied or {}
	local entries = self:_entries(match)
	local deltas = Progression.ComputeRatingDeltas(entries, Config.Ranked.KFactor)
	for _, racer in match.RacerList do
		local player = racer.Player
		if player and player.Parent and not match.RankedApplied[racer.UserId] and racer.Status ~= "Left" then
			match.RankedApplied[racer.UserId] = true
			local change, newRating = self:_apply(player, racer, deltas[racer] or 0)
			local summary = summaries[racer.UserId]
			if summary and change then
				summary.RatingChange = change
				summary.NewRating = newRating
				summary.Tier = Progression.GetTier(newRating).Name
			end
		end
	end
end

--- Sofortige Wertung als Letzter, wenn ein Spieler ein Ranked-Match verlässt.
function RankedService:ApplyLeavePenalty(match, racer, player: Player?)
	if not player then
		return
	end
	match.RankedApplied = match.RankedApplied or {}
	if match.RankedApplied[racer.UserId] then
		return
	end
	match.RankedApplied[racer.UserId] = true
	local entries = self:_entries(match, { Racer = racer, Player = player })
	for _, entry in entries do
		if entry.Key == racer then
			entry.Placement = #match.RacerList + 1
		end
	end
	local deltas = Progression.ComputeRatingDeltas(entries, Config.Ranked.KFactor)
	local delta = math.min(0, deltas[racer] or 0) * Config.Ranked.LeavePenaltyFactor
	self:_apply(player, racer, math.floor(delta))
end

return RankedService
