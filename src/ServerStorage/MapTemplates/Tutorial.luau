--[[
	Tutorial  (ModuleScript)
	Pfad: ServerStorage/MapTemplates/Tutorial

	Bewegungs-Tutorial für den Trainingsmodus. Jede Station erklärt eine
	Mechanik per Schild. Kein Wettbewerb, keine Belohnungen.
]]

return function(B)
	B.CheckpointSpacing = 90

	B:Start(60)
	B:Sign(10, B.Y + 13, "WILLKOMMEN!", "A/D oder Pfeiltasten: laufen")
	B:Flat(40)
	B:Sign(B.X - 10, B.Y + 13, "SPRINGEN", "Leertaste / W – länger halten = höher")
	B:Climb(4, 24)
	B:Climb(6, 30)
	B:Gap(10, 0, 30)
	B:Sign(B.X - 15, B.Y + 13, "MOMENTUM", "Anlauf nehmen für weite Sprünge")
	B:Gap(20, 0, 40)
	B:Sign(B.X - 20, B.Y + 13, "SLIDEN", "Shift / S bei Tempo – unter Hindernissen durch")
	B:Flat(30)
	B:SlideTunnel(30)
	B:Flat(20)
	B:Sign(B.X + 10, B.Y + 34, "WALL-JUMP", "In der Luft gegen eine Wand springen")
	B:Flat(20)
	B:WallClimb(18, 14)
	B:Flat(30)
	B:Sign(B.X - 10, B.Y + 15, "GREIFHAKEN", "E / Maus halten zum Schwingen, loslassen zum Abspringen")
	B:Flat(20)
	B:GrappleGap(50, { AnchorHeight = 22 })
	B:GrappleGap(80, { Anchors = 2, AnchorHeight = 24 })
	B:Sign(B.X - 10, B.Y + 13, "AIR-DASH", "In der Luft Shift / S: kurzer Dash nach vorn")
	B:Flat(10)
	B:Gap(24, 0, 30)
	B:Sign(B.X - 10, B.Y + 13, "PADS", "Boost-Pads geben Tempo, Sprungpads bringen dich hoch")
	B:BoostStrip(60, 85)
	B:JumpPadUp(16, 30)
	B:Sign(B.X - 10, B.Y + 13, "POWER-UPS", "Box einsammeln, mit Q / F einsetzen")
	B:PickupRow(3, 30)
	B:Flat(20)
	B:Sign(B.X + 10, B.Y + 22, "TIMING", "Warte, bis die Barriere ausgeschaltet ist")
	B:TimedBarrier(40, { Period = 2.6, OnTime = 1.1 })
	B:Sign(B.X - 10, B.Y + 13, "GEFAHRENZONE", "Im Rennen jagt dich eine Energiewand – bleib vorn!")
	B:Flat(30)
	B:Finish(60)
	-- Optik (rein dekorativ): Trainingstore
	B:Gates(2, B.Theme.Accent2)
	B:Decorate()
end
