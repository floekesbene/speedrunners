--[[
	Lobby  (ModuleScript)
	Pfad: ServerStorage/MapTemplates/Lobby

	Die Lobby ist ebenfalls eine 2D-Bühne: Spieler können sich während der
	Wartezeit bewegen, den Greifhaken ausprobieren und Portale nutzen.
	Portale lösen Aktionen aus (Quick Play, Ranked, Training), wenn man darin
	stehen bleibt. Dieselben Aktionen gibt es im Lobby-Menü.
]]

return function(B)
	local theme = B.Theme
	B.AutoCheckpoints = false

	B:Ground(-160, 170, 0, { Thickness = 12 })
	B:Box(-172, -12, -160, 95, { Name = "Wall", Color = theme.Wall })
	B:Box(170, -12, 182, 95, { Name = "Wall", Color = theme.Wall })

	for i = 0, 7 do
		B:SpawnPoint(-12 + i * 3.5, 0)
	end

	B:Sign(0, 44, "VELOCITY RUSH", "Multiplayer-Speedrace · Menü links benutzen", { Width = 46, Height = 10 })

	B:Portal(-130, 0, "QuickPlay", "SCHNELLES SPIEL", theme.Accent)
	B:Portal(-95, 0, "Ranked", "RANKED", Color3.fromRGB(255, 200, 40))
	B:Portal(-60, 0, "Practice", "TRAINING", Color3.fromRGB(80, 255, 140))

	-- Parkour-Spielplatz zum Aufwärmen
	B:JumpPad(24, 0, 75)
	B:Ground(34, 52, 8, { Thickness = 2 })
	B:Ground(60, 78, 15, { Thickness = 2 })
	B:Ground(86, 104, 22, { Thickness = 2 })
	B:Anchor(72, 42)
	B:Anchor(112, 46)
	B:Box(120, 9, 122, 60, { Name = "WallJumpWall", Color = theme.Wall })
	B:Box(136, 0, 140, 48, { Name = "WallJumpBlock", Color = theme.Wall })
	B:Ground(136, 170, 48, { Thickness = 2 })
	B:BoostPad(-40, -24, 0, 70)
	B:Sign(110, 30, "SPIELPLATZ", "Greifhaken: E · Wall-Jump: an der Wand springen", { Width = 30, Height = 7 })

	B:Decorate()
end
