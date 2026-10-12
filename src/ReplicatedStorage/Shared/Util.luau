--[[
	Util  (ModuleScript)
	Pfad: ReplicatedStorage/Shared/Util

	Kleine, zustandslose Hilfsfunktionen für Mathematik, Tabellen und Formatierung.
]]

local Util = {}

--- Bewegt `current` um höchstens `maxDelta` in Richtung `target`.
function Util.MoveToward(current: number, target: number, maxDelta: number): number
	if current < target then
		return math.min(current + maxDelta, target)
	end
	return math.max(current - maxDelta, target)
end

--- Lineare Interpolation.
function Util.Lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

--- Bildratenunabhängiges Glätten: nähert `a` mit Schärfe `sharpness` an `b` an.
function Util.Damp(a: number, b: number, sharpness: number, dt: number): number
	return a + (b - a) * (1 - math.exp(-sharpness * dt))
end

--- Vorzeichen, wobei 0 als 0 zurückgegeben wird.
function Util.Sign(x: number): number
	if x > 0 then
		return 1
	elseif x < 0 then
		return -1
	end
	return 0
end

--- Rundet auf ein Vielfaches von `step`.
function Util.Round(x: number, step: number?): number
	local s = step or 1
	return math.floor(x / s + 0.5) * s
end

--- Tiefe Kopie einer Tabelle (ohne Metatabellen, ohne Zyklen).
function Util.DeepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[Util.DeepCopy(k)] = Util.DeepCopy(v)
	end
	return copy
end

--- Ergänzt fehlende Schlüssel in `target` rekursiv aus `template`.
function Util.Reconcile(target: { [any]: any }, template: { [any]: any })
	for key, value in template do
		if target[key] == nil then
			target[key] = Util.DeepCopy(value)
		elseif type(value) == "table" and type(target[key]) == "table" then
			-- Nur echte "Struktur"-Tabellen rekursiv abgleichen (keine Listen).
			if #value == 0 then
				Util.Reconcile(target[key], value)
			end
		end
	end
end

--- Formatiert eine Zahl mit Tausenderpunkten (12345 -> "12.345").
function Util.FormatNumber(n: number): string
	local negative = n < 0
	local s = tostring(math.floor(math.abs(n)))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
	if formatted:sub(1, 1) == "." then
		formatted = formatted:sub(2)
	end
	return (negative and "-" or "") .. formatted
end

--- Formatiert Sekunden als m:ss.hh
function Util.FormatTime(seconds: number): string
	seconds = math.max(0, seconds)
	local minutes = math.floor(seconds / 60)
	local rest = seconds - minutes * 60
	return string.format("%d:%05.2f", minutes, rest)
end

--- Mischt eine Liste in-place (Fisher-Yates).
function Util.Shuffle(list: { any }, rng: Random?)
	local random = rng or Random.new()
	for i = #list, 2, -1 do
		local j = random:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

--- Gewichtete Zufallsauswahl. `entries` = { {Value=..., Weight=number}, ... }
function Util.WeightedPick(entries: { any }, rng: Random?): any
	local random = rng or Random.new()
	local total = 0
	for _, entry in entries do
		total += math.max(0, entry.Weight)
	end
	if total <= 0 then
		return nil
	end
	local roll = random:NextNumber() * total
	for _, entry in entries do
		roll -= math.max(0, entry.Weight)
		if roll <= 0 then
			return entry.Value
		end
	end
	return entries[#entries].Value
end

--- Zählt die Schlüssel einer Tabelle.
function Util.Count(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

--- Liefert die aktuelle "Tagesnummer" (UTC) für tägliche Aufgaben.
function Util.DayNumber(): number
	return math.floor(os.time() / 86400)
end

return Util
