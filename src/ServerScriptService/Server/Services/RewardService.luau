--[[
	RewardService  (ModuleScript)
	Pfad: ServerScriptService/Server/Services/RewardService

	Berechnet und vergibt Belohnungen ausschließlich serverseitig:
		- Match-Belohnungen (Teilnahme, Platzierung, Ziel erreicht)
		- Statistiken (Rennen, Siege, Top 3, Bestzeiten ...)
		- Tägliche Aufgaben und Erfolge

	Schutz vor Mehrfachbelohnung:
		1. match.Rewarded[userId] (pro Match im Speicher)
		2. profile.RecentMatches (Match-IDs der letzten Rennen, gespeichert)
		3. Aufgaben/Erfolge haben ein Done-Flag bzw. stehen in Achievements.

	Öffentliche API:
		:GrantMatchRewards(match) -> { [userId] = summary }
		:OnGrapple(player, inRace)
		:OnPowerUpUsed(player, inRace)
		:EnsureDailyQuests(player)
		:CheckAchievements(player)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)
local QuestDefinitions = require(Shared.QuestDefinitions)

local RewardService = {}

function RewardService:Init(services)
	self.Services = services
end

function RewardService:Start()
	self.Services.PlayerDataService.ProfileLoaded:Connect(function(player)
		self:EnsureDailyQuests(player)
		self:CheckAchievements(player)
	end)
end

------------------------------------------------------------------------
-- Tägliche Aufgaben
------------------------------------------------------------------------

function RewardService:EnsureDailyQuests(player: Player)
	local data = self.Services.PlayerDataService
	local profile = data:GetProfile(player)
	if not profile then
		return
	end
	local day = Util.DayNumber()
	if profile.Quests.Day ~= day then
		local list = {}
		for _, id in QuestDefinitions.RollDaily(player.UserId, day) do
			table.insert(list, { Id = id, Progress = 0, Done = false })
		end
		profile.Quests = { Day = day, List = list }
		data:MarkDirty(player)
		data:PushProfile(player)
	end
end

--- Erhöht den Fortschritt aller Tagesaufgaben mit Statistik `stat`.
function RewardService:_questProgress(player: Player, stat: string, amount: number)
	self:EnsureDailyQuests(player)
	local services = self.Services
	local profile = services.PlayerDataService:GetProfile(player)
	if not profile then
		return {}
	end
	local completed = {}
	for _, entry in profile.Quests.List do
		local quest = QuestDefinitions.DailyLookup[entry.Id]
		if quest and quest.Stat == stat and not entry.Done then
			entry.Progress = math.min(quest.Goal, entry.Progress + amount)
			if entry.Progress >= quest.Goal then
				entry.Done = true
				services.EconomyService:AddCoins(player, quest.Coins, "Quest:" .. quest.Id)
				services.EconomyService:AddXP(player, quest.XP, "Quest:" .. quest.Id)
				Remotes.GameEvent:FireClient(player, "QuestCompleted", { Name = quest.Name, Coins = quest.Coins, XP = quest.XP })
				table.insert(completed, quest.Name)
			end
		end
	end
	services.PlayerDataService:MarkDirty(player)
	return completed
end

------------------------------------------------------------------------
-- Erfolge
------------------------------------------------------------------------

function RewardService:_statValue(player: Player, profile, stat: string): number
	if stat == "Level" then
		return profile.Level
	elseif stat == "Owned" then
		return self.Services.InventoryService:CountOwned(player)
	end
	return profile.Stats[stat] or 0
end

function RewardService:CheckAchievements(player: Player)
	local services = self.Services
	local profile = services.PlayerDataService:GetProfile(player)
	if not profile then
		return {}
	end
	local unlocked = {}
	for _, achievement in QuestDefinitions.Achievements do
		if not profile.Achievements[achievement.Id] and self:_statValue(player, profile, achievement.Stat) >= achievement.Goal then
			profile.Achievements[achievement.Id] = true
			-- Erst markieren, dann belohnen (verhindert Rekursion über Level-Ups)
			services.EconomyService:AddCoins(player, achievement.Coins, "Achievement:" .. achievement.Id)
			Remotes.GameEvent:FireClient(player, "AchievementUnlocked", { Name = achievement.Name, Coins = achievement.Coins })
			table.insert(unlocked, achievement.Name)
		end
	end
	if #unlocked > 0 then
		services.PlayerDataService:MarkDirty(player)
		services.PlayerDataService:PushProfile(player)
	end
	return unlocked
end

------------------------------------------------------------------------
-- Live-Zähler
------------------------------------------------------------------------

function RewardService:OnGrapple(player: Player, inRace: boolean)
	if not inRace then
		return
	end
	local profile = self.Services.PlayerDataService:GetProfile(player)
	if not profile then
		return
	end
	profile.Stats.Grapples += 1
	self:_questProgress(player, "Grapples", 1)
end

function RewardService:OnPowerUpUsed(player: Player, inRace: boolean)
	if not inRace then
		return
	end
	local profile = self.Services.PlayerDataService:GetProfile(player)
	if not profile then
		return
	end
	profile.Stats.PowerUps += 1
	self:_questProgress(player, "PowerUps", 1)
end

------------------------------------------------------------------------
-- Match-Belohnungen
------------------------------------------------------------------------

function RewardService:GrantMatchRewards(match)
	local services = self.Services
	local rewardsConfig = Config.Rewards
	local summaries = {}
	local participants = match.Participants
	local scale = math.clamp(participants / rewardsConfig.FullRewardPlayerCount, 0.4, 1)

	for _, racer in match.RacerList do
		local player = racer.Player
		if player and player.Parent and racer.Status ~= "Left" and not match.Rewarded[racer.UserId] then
			match.Rewarded[racer.UserId] = true
			local profile = services.PlayerDataService:GetProfile(player)
			if profile and not table.find(profile.RecentMatches, match.Id) then
				table.insert(profile.RecentMatches, match.Id)
				while #profile.RecentMatches > rewardsConfig.RecentMatchMemory do
					table.remove(profile.RecentMatches, 1)
				end

				local placement = racer.Placement or participants
				local isWinner = placement == 1 and (participants >= 2 or racer.Status == "Finished")
				local finished = racer.Status == "Finished"

				local coins = rewardsConfig.ParticipationCoins
				local xp = rewardsConfig.ParticipationXP
				if participants >= 2 and rewardsConfig.PlacementCoins[placement] then
					coins += math.floor(rewardsConfig.PlacementCoins[placement] * scale)
					xp += math.floor(rewardsConfig.PlacementXP[placement] * scale)
				end
				if finished then
					coins += rewardsConfig.FinishBonusCoins
					xp += rewardsConfig.FinishBonusXP
				end

				-- Statistiken
				local stats = profile.Stats
				stats.Races += 1
				stats.Distance += math.floor(racer.Distance)
				if racer.Status == "Eliminated" then
					stats.Eliminated += 1
				end
				if isWinner then
					stats.Wins += 1
					if racer.Respawns == 0 then
						stats.FlawlessWins += 1
					end
				end
				if placement <= 3 and participants >= 2 then
					stats.Top3 += 1
				end
				local newBest = false
				if finished and racer.FinishTime then
					stats.Finishes += 1
					local best = stats.BestTimes[match.MapId]
					if not best or racer.FinishTime < best then
						stats.BestTimes[match.MapId] = math.floor(racer.FinishTime * 100) / 100
						newBest = true
					end
				end

				services.EconomyService:AddCoins(player, coins, "Match:" .. match.Id)
				local xpResult = services.EconomyService:AddXP(player, xp, "Match:" .. match.Id)

				-- Aufgaben
				local quests = {}
				local function collect(list)
					for _, name in list do
						table.insert(quests, name)
					end
				end
				collect(self:_questProgress(player, "Races", 1))
				collect(self:_questProgress(player, "Distance", math.floor(racer.Distance)))
				if isWinner then
					collect(self:_questProgress(player, "Wins", 1))
				end
				if placement <= 3 and participants >= 2 then
					collect(self:_questProgress(player, "Top3", 1))
				end
				if finished then
					collect(self:_questProgress(player, "Finishes", 1))
				end

				local achievements = self:CheckAchievements(player)
				services.EconomyService:UpdateLeaderstats(player)
				services.PlayerDataService:MarkDirty(player)
				services.PlayerDataService:PushProfile(player)

				summaries[racer.UserId] = {
					Coins = coins,
					XP = xp,
					LevelsGained = xpResult.LevelsGained,
					NewLevel = xpResult.NewLevel,
					LevelBonusCoins = xpResult.BonusCoins,
					Placement = placement,
					Winner = isWinner,
					NewBestTime = if newBest then racer.FinishTime else nil,
					Quests = quests,
					Achievements = achievements,
				}
			end
		end
	end
	return summaries
end

return RewardService
