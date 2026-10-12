--[[
	ItemDefinitions  (ModuleScript)
	Pfad: ReplicatedStorage/Shared/ItemDefinitions

	Zentrale Definition aller Power-ups. Der Server (PowerUpService) nutzt die
	Werte für Effekte und Validierung, der Client für Anzeige und Effekte.

	Spawnregeln:
		Power-ups liegen in Item-Boxen an festen Spawnpunkten jeder Map.
		Eine Box respawnt nach Config.PowerUps.RespawnTime Sekunden.
		Jeder Spieler kann genau ein Item halten. Die Auswahl ist gewichtet nach
		Rennposition (Führende bekommen seltener starke Items -> Aufholmechanik).
	Verbrauch:
		Jedes Item wird bei Benutzung sofort verbraucht (Schutz vor Doppelnutzung).
		Ausnahme: Teleport Beacon ohne gültiges Ziel wird nicht verbraucht.
]]

local ItemDefinitions = {}

ItemDefinitions.Items = {
	SpeedBoost = {
		Id = "SpeedBoost",
		Name = "Speed Boost",
		Short = "BOOST",
		Description = "Kurzer Schub: höhere Maximalgeschwindigkeit für 3 Sekunden.",
		Color = Color3.fromRGB(255, 170, 0),
		Duration = 3,
		Offensive = false,
		Weights = { Leader = 30, Front = 25, Back = 22 },
	},
	Shield = {
		Id = "Shield",
		Name = "Shield",
		Short = "SCHILD",
		Description = "Blockt den nächsten gegnerischen Effekt (Freeze, Falle) für 6 Sekunden.",
		Color = Color3.fromRGB(80, 200, 255),
		Duration = 6,
		Offensive = false,
		Weights = { Leader = 30, Front = 20, Back = 12 },
	},
	FreezeBurst = {
		Id = "FreezeBurst",
		Name = "Freeze Burst",
		Short = "FREEZE",
		Description = "Verlangsamt alle Gegner im Umkreis von 45 Studs für 1,8 Sekunden.",
		Color = Color3.fromRGB(150, 230, 255),
		Radius = 45,
		Duration = 1.8,
		Offensive = true,
		Weights = { Leader = 8, Front = 18, Back = 22 },
	},
	GrappleUpgrade = {
		Id = "GrappleUpgrade",
		Name = "Grapple Upgrade",
		Short = "HAKEN+",
		Description = "8 Sekunden lang: größere Reichweite, schnelleres Einholen, kein Cooldown.",
		Color = Color3.fromRGB(190, 110, 255),
		Duration = 8,
		Offensive = false,
		Weights = { Leader = 18, Front = 20, Back = 18 },
	},
	TeleportBeacon = {
		Id = "TeleportBeacon",
		Name = "Teleport Beacon",
		Short = "TELEPORT",
		Description = "Teleportiert dich zum nächsten sicheren Punkt bis zu 48 Studs voraus.",
		Color = Color3.fromRGB(60, 255, 170),
		Range = 48,
		MinDistance = 10,
		Offensive = false,
		Weights = { Leader = 2, Front = 10, Back = 18 },
	},
	Trap = {
		Id = "Trap",
		Name = "Trap",
		Short = "FALLE",
		Description = "Platziert eine sichtbare Falle (15 s). Gegner werden 1,2 s betäubt.",
		Color = Color3.fromRGB(255, 70, 70),
		Lifetime = 15,
		StunDuration = 1.2,
		TriggerRadius = 3.4,
		Offensive = true,
		Weights = { Leader = 12, Front = 7, Back = 8 },
	},
}

ItemDefinitions.Order = { "SpeedBoost", "Shield", "FreezeBurst", "GrappleUpgrade", "TeleportBeacon", "Trap" }

function ItemDefinitions.Get(id: string)
	return ItemDefinitions.Items[id]
end

--- Liefert die Gewichtungsliste für eine Positionskategorie ("Leader"|"Front"|"Back").
function ItemDefinitions.GetWeightedList(bucket: string)
	local list = {}
	for _, id in ItemDefinitions.Order do
		local item = ItemDefinitions.Items[id]
		table.insert(list, { Value = id, Weight = item.Weights[bucket] or 10 })
	end
	return list
end

return ItemDefinitions
