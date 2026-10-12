--[[
	_Template  (ModuleScript) – Vorlage für neue Maps
	Pfad: ServerStorage/MapTemplates/_Template

	So fügst du eine neue Strecke hinzu:
		1. Dieses Modul duplizieren und umbenennen (z.B. "DesertDash").
		2. In ReplicatedStorage/Shared/MapDefinitions einen Eintrag anlegen:
		      DesertDash = { Id = "DesertDash", Name = "Desert Dash", Template = "DesertDash",
		                     Difficulty = 2, Seed = 6606, Theme = { ... } }
		   und "DesertDash" in MapDefinitions.Order eintragen.
		3. Unten die Strecke mit Bausteinen beschreiben (siehe MapBuilder-Doku).

	Regeln für faire, spielbare Strecken:
		- Normale Sprunglücken ≤ 18 Studs, Stufen ≤ 6 Studs.
		- Greifhaken-Lücken 40–80 Studs, Anker ca. 22–26 Studs über dem Boden.
		- Alle ~200 Studs wird automatisch ein Checkpoint gesetzt.
		- Immer mit B:Start() beginnen und mit B:Finish() enden.
		- Zum Schluss B:Decorate() für den Hintergrund aufrufen.

	Diese Vorlage wird vom Spiel nicht geladen (kein Eintrag in MapDefinitions).
]]

return function(B)
	B:Start(60)
	B:Flat(40)
	B:Gap(B:D(12), 0, 30)
	B:Steps(3, 4, 12)
	B:PickupRow(3)
	B:SlideTunnel(30)
	B:Flat(20)
	B:GrappleGap(B:D(54), { AnchorHeight = 24 })
	B:Split({
		Length = 240,
		Depth = 28,
		Upper = function(b)
			b:Flat(10)
			b:GrappleGap(56, { Landing = 24 })
			b:BoostStrip(40, 85)
		end,
		Lower = function(b)
			b:Flat(40)
			b:Pit(32, { Pillars = 2, Landing = 30 })
			b:Flat(30)
		end,
	})
	B:WallClimb(18, 14)
	B:TimedBarrier(36, { Period = 2.4, OnTime = 1.0 })
	B:Flat(30)
	B:Finish(80)
	B:Decorate()
end
