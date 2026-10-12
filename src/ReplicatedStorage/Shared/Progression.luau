--[[
	Progression  (ModuleScript)
	Pfad: ReplicatedStorage/Shared/Progression

	Levelkurve (XP) und Ranked-Stufen. Wird vom Server zur Berechnung und vom
	Client zur Anzeige verwendet.
]]

local Progression = {}

Progression.MaxLevel = 100

--- XP, die benötigt werden, um von `level` auf `level + 1` zu steigen.
function Progression.XPForLevel(level: number): number
	return 100 + (level - 1) * 40
end

--- Berechnet Level, XP im aktuellen Level und XP bis zum nächsten Level aus Gesamt-XP.
function Progression.FromTotalXP(totalXP: number): (number, number, number)
	local level = 1
	local remaining = math.max(0, math.floor(totalXP))
	while level < Progression.MaxLevel do
		local needed = Progression.XPForLevel(level)
		if remaining < needed then
			return level, remaining, needed
		end
		remaining -= needed
		level += 1
	end
	return Progression.MaxLevel, 0, 0
end

Progression.Tiers = {
	{ Name = "Bronze", MinRating = 0, Color = Color3.fromRGB(205, 127, 50) },
	{ Name = "Silber", MinRating = 1100, Color = Color3.fromRGB(192, 200, 215) },
	{ Name = "Gold", MinRating = 1300, Color = Color3.fromRGB(255, 200, 40) },
	{ Name = "Platin", MinRating = 1500, Color = Color3.fromRGB(80, 230, 210) },
	{ Name = "Diamant", MinRating = 1700, Color = Color3.fromRGB(120, 170, 255) },
	{ Name = "Velocity-Elite", MinRating = 1900, Color = Color3.fromRGB(255, 70, 160) },
}

--- Liefert die Stufe (Tabelle mit Name, MinRating, Color) für ein Rating.
function Progression.GetTier(rating: number)
	local result = Progression.Tiers[1]
	for _, tier in Progression.Tiers do
		if rating >= tier.MinRating then
			result = tier
		end
	end
	return result
end

--- Elo-artige Mehrspieler-Wertung.
--- `entries` = { {Key=any, Rating=number, Placement=number}, ... }
--- Rückgabe: { [Key] = Delta }
function Progression.ComputeRatingDeltas(entries: { any }, kFactor: number): { [any]: number }
	local deltas = {}
	local n = #entries
	if n < 2 then
		for _, entry in entries do
			deltas[entry.Key] = 0
		end
		return deltas
	end
	for i, a in entries do
		local sum = 0
		for j, b in entries do
			if i ~= j then
				local expected = 1 / (1 + 10 ^ ((b.Rating - a.Rating) / 400))
				local actual
				if a.Placement < b.Placement then
					actual = 1
				elseif a.Placement > b.Placement then
					actual = 0
				else
					actual = 0.5
				end
				sum += actual - expected
			end
		end
		deltas[a.Key] = math.floor(kFactor * sum / (n - 1) + 0.5)
	end
	return deltas
end

return Progression
