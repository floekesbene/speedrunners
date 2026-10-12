--[[
	QuestDefinitions  (ModuleScript)
	Pfad: ReplicatedStorage/Shared/QuestDefinitions

	Tägliche Aufgaben und Erfolge. Der Fortschritt wird ausschließlich auf dem
	Server gezählt (RewardService). Belohnungen werden genau einmal vergeben.

	Zähler (Stat-Schlüssel), die der Server erhöht:
		Races, Wins, Top3, Finishes, Grapples, PowerUps, Distance
]]

local QuestDefinitions = {}

QuestDefinitions.DailyCount = 3

QuestDefinitions.Daily = {
	{ Id = "PlayRaces", Name = "Spiele 3 Rennen", Stat = "Races", Goal = 3, Coins = 80, XP = 60 },
	{ Id = "PlayRacesLong", Name = "Spiele 6 Rennen", Stat = "Races", Goal = 6, Coins = 150, XP = 120 },
	{ Id = "Top3", Name = "Erreiche 2× die Top 3", Stat = "Top3", Goal = 2, Coins = 120, XP = 90 },
	{ Id = "WinOne", Name = "Gewinne ein Rennen", Stat = "Wins", Goal = 1, Coins = 150, XP = 120 },
	{ Id = "Grapples", Name = "Nutze den Greifhaken 25× im Rennen", Stat = "Grapples", Goal = 25, Coins = 90, XP = 70 },
	{ Id = "PowerUps", Name = "Setze 5 Power-ups im Rennen ein", Stat = "PowerUps", Goal = 5, Coins = 90, XP = 70 },
	{ Id = "Distance", Name = "Lege 5.000 Studs im Rennen zurück", Stat = "Distance", Goal = 5000, Coins = 100, XP = 80 },
	{ Id = "Finish", Name = "Überquere 1× die Ziellinie", Stat = "Finishes", Goal = 1, Coins = 110, XP = 90 },
}

QuestDefinitions.Achievements = {
	{ Id = "FirstRace", Name = "Startschuss", Description = "Spiele dein erstes Rennen.", Stat = "Races", Goal = 1, Coins = 50 },
	{ Id = "FirstWin", Name = "Erster Sieg", Description = "Gewinne ein Rennen.", Stat = "Wins", Goal = 1, Coins = 150 },
	{ Id = "TenWins", Name = "Seriensieger", Description = "Gewinne 10 Rennen.", Stat = "Wins", Goal = 10, Coins = 500 },
	{ Id = "FiftyRaces", Name = "Marathon", Description = "Spiele 50 Rennen.", Stat = "Races", Goal = 50, Coins = 400 },
	{ Id = "GrappleMaster", Name = "Hakenmeister", Description = "Nutze den Greifhaken 500× im Rennen.", Stat = "Grapples", Goal = 500, Coins = 400 },
	{ Id = "ItemFan", Name = "Taktiker", Description = "Setze 100 Power-ups ein.", Stat = "PowerUps", Goal = 100, Coins = 300 },
	{ Id = "Level10", Name = "Aufsteiger", Description = "Erreiche Level 10.", Stat = "Level", Goal = 10, Coins = 300 },
	{ Id = "Level25", Name = "Veteran", Description = "Erreiche Level 25.", Stat = "Level", Goal = 25, Coins = 800 },
	{ Id = "Collector", Name = "Sammler", Description = "Besitze 10 kosmetische Gegenstände.", Stat = "Owned", Goal = 10, Coins = 400 },
	{ Id = "Flawless", Name = "Makellos", Description = "Gewinne ein Rennen ohne Respawn.", Stat = "FlawlessWins", Goal = 1, Coins = 300 },
}

QuestDefinitions.DailyLookup = {}
for _, quest in QuestDefinitions.Daily do
	QuestDefinitions.DailyLookup[quest.Id] = quest
end

QuestDefinitions.AchievementLookup = {}
for _, achievement in QuestDefinitions.Achievements do
	QuestDefinitions.AchievementLookup[achievement.Id] = achievement
end

--- Wählt deterministisch die Tagesaufgaben für einen Spieler und Tag.
function QuestDefinitions.RollDaily(userId: number, day: number): { string }
	local rng = Random.new(userId * 31 + day * 7919)
	local pool = {}
	for _, quest in QuestDefinitions.Daily do
		table.insert(pool, quest.Id)
	end
	local result = {}
	for _ = 1, math.min(QuestDefinitions.DailyCount, #pool) do
		local index = rng:NextInteger(1, #pool)
		local id = table.remove(pool, index)
		-- Keine zwei Aufgaben mit derselben Statistik am selben Tag.
		local stat = QuestDefinitions.DailyLookup[id].Stat
		for i = #pool, 1, -1 do
			if QuestDefinitions.DailyLookup[pool[i]].Stat == stat then
				table.remove(pool, i)
			end
		end
		table.insert(result, id)
		if #pool == 0 then
			break
		end
	end
	return result
end

return QuestDefinitions
