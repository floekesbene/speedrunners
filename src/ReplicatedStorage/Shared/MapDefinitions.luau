--[[
	MapDefinitions  (ModuleScript)
	Pfad: ReplicatedStorage/Shared/MapDefinitions

	Metadaten und visuelle Themes aller Maps. Die eigentliche Geometrie wird
	serverseitig von ServerStorage/MapTemplates/<Template> über den MapBuilder
	erzeugt. Der Client nutzt diese Daten für UI (Name, Beschreibung) und
	Beleuchtung.

	Neue Map hinzufügen:
		1. ServerStorage/MapTemplates/_Template kopieren und umbenennen.
		2. Hier einen Eintrag mit Id, Template-Name und Theme anlegen.
		3. Die Id in MapDefinitions.Order eintragen.
]]

local MapDefinitions = {}

local rgb = Color3.fromRGB

MapDefinitions.Maps = {
	NeonMetropolis = {
		Id = "NeonMetropolis",
		Name = "Neon Metropolis",
		Description = "Futuristische Häuserschluchten voller Neon, Laserbarrieren und Greifpunkte.",
		Template = "NeonMetropolis",
		Difficulty = 2,
		Seed = 1101,
		Theme = {
			Ground = rgb(34, 36, 52),
			GroundMaterial = Enum.Material.SmoothPlastic,
			Top = rgb(58, 62, 88),
			TopMaterial = Enum.Material.Metal,
			Wall = rgb(28, 30, 44),
			Accent = rgb(0, 230, 255),
			Accent2 = rgb(255, 60, 200),
			Hazard = rgb(255, 40, 90),
			HazardKind = "Laser",
			PitKind = "Laser",
			Anchor = rgb(0, 230, 255),
			EdgeGlow = true,
			Decor = "City",
			Lighting = {
				ClockTime = 0.3, Brightness = 1.2, Ambient = rgb(70, 60, 110), OutdoorAmbient = rgb(90, 70, 140),
				FogColor = rgb(35, 18, 65), FogStart = 220, FogEnd = 1100,
				AtmosphereDensity = 0.32, AtmosphereColor = rgb(120, 70, 200), AtmosphereDecay = rgb(60, 30, 120), Haze = 1.6, Glare = 0,
				Tint = rgb(235, 230, 255), Saturation = 0.15, Contrast = 0.08, BloomIntensity = 0.9, BloomSize = 28, BloomThreshold = 0.95,
			},
		},
	},
	MagmaWorks = {
		Id = "MagmaWorks",
		Name = "Magma Works",
		Description = "Eine Industrieanlage über einem Lavasee. Flammenwerfer, Rohre und heiße Böden.",
		Template = "MagmaWorks",
		Difficulty = 3,
		Seed = 2202,
		Theme = {
			Ground = rgb(58, 52, 48),
			GroundMaterial = Enum.Material.DiamondPlate,
			Top = rgb(80, 72, 66),
			TopMaterial = Enum.Material.DiamondPlate,
			Wall = rgb(45, 40, 38),
			Accent = rgb(255, 130, 30),
			Accent2 = rgb(255, 200, 60),
			Hazard = rgb(255, 80, 10),
			HazardKind = "Flame",
			PitKind = "Lava",
			Anchor = rgb(255, 170, 40),
			EdgeGlow = true,
			Decor = "Industrial",
			Lighting = {
				ClockTime = 18.6, Brightness = 1.6, Ambient = rgb(110, 60, 40), OutdoorAmbient = rgb(140, 70, 40),
				FogColor = rgb(70, 25, 10), FogStart = 180, FogEnd = 950,
				AtmosphereDensity = 0.42, AtmosphereColor = rgb(200, 90, 40), AtmosphereDecay = rgb(120, 40, 20), Haze = 2.2, Glare = 0.3,
				Tint = rgb(255, 235, 215), Saturation = 0.1, Contrast = 0.1, BloomIntensity = 0.8, BloomSize = 24, BloomThreshold = 0.95,
			},
		},
	},
	SkywayRuins = {
		Id = "SkywayRuins",
		Name = "Skyway Ruins",
		Description = "Schwebende Ruinen hoch über den Wolken. Viele Greifhaken-Passagen.",
		Template = "SkywayRuins",
		Difficulty = 2,
		Seed = 3303,
		Theme = {
			Ground = rgb(150, 140, 120),
			GroundMaterial = Enum.Material.Cobblestone,
			Top = rgb(110, 170, 80),
			TopMaterial = Enum.Material.Grass,
			Wall = rgb(190, 180, 160),
			Accent = rgb(255, 215, 120),
			Accent2 = rgb(120, 220, 255),
			Hazard = rgb(160, 90, 255),
			HazardKind = "Arcane",
			PitKind = "Void",
			Anchor = rgb(255, 215, 120),
			EdgeGlow = false,
			Decor = "Sky",
			Lighting = {
				ClockTime = 14.2, Brightness = 2.4, Ambient = rgb(120, 130, 150), OutdoorAmbient = rgb(150, 160, 180),
				FogColor = rgb(190, 215, 245), FogStart = 300, FogEnd = 1500,
				AtmosphereDensity = 0.28, AtmosphereColor = rgb(200, 225, 255), AtmosphereDecay = rgb(140, 170, 220), Haze = 1.2, Glare = 0.4,
				Tint = rgb(255, 252, 245), Saturation = 0.1, Contrast = 0.05, BloomIntensity = 0.5, BloomSize = 24, BloomThreshold = 1.2,
			},
		},
	},
	GlacierCircuit = {
		Id = "GlacierCircuit",
		Name = "Glacier Circuit",
		Description = "Rutschige Eisflächen, Eiszapfen und eisiges Wasser. Momentum ist alles.",
		Template = "GlacierCircuit",
		Difficulty = 2,
		Seed = 4404,
		Theme = {
			Ground = rgb(170, 200, 225),
			GroundMaterial = Enum.Material.Glacier,
			Top = rgb(245, 250, 255),
			TopMaterial = Enum.Material.Snow,
			Wall = rgb(140, 175, 210),
			Accent = rgb(120, 220, 255),
			Accent2 = rgb(200, 240, 255),
			Hazard = rgb(90, 200, 255),
			HazardKind = "Icicle",
			PitKind = "IceWater",
			Anchor = rgb(140, 240, 255),
			EdgeGlow = false,
			Decor = "Glacier",
			Lighting = {
				ClockTime = 9.5, Brightness = 2.2, Ambient = rgb(120, 140, 170), OutdoorAmbient = rgb(150, 170, 200),
				FogColor = rgb(215, 230, 245), FogStart = 200, FogEnd = 1000,
				AtmosphereDensity = 0.36, AtmosphereColor = rgb(220, 235, 255), AtmosphereDecay = rgb(160, 190, 230), Haze = 2, Glare = 0.2,
				Tint = rgb(240, 248, 255), Saturation = -0.05, Contrast = 0.06, BloomIntensity = 0.6, BloomSize = 24, BloomThreshold = 1.1,
			},
		},
	},
	JungleVelocity = {
		Id = "JungleVelocity",
		Name = "Jungle Velocity",
		Description = "Dichter Dschungel mit Baumkronen-Route, Flussläufen und Dornen.",
		Template = "JungleVelocity",
		Difficulty = 1,
		Seed = 5505,
		Theme = {
			Ground = rgb(90, 70, 50),
			GroundMaterial = Enum.Material.Ground,
			Top = rgb(80, 150, 60),
			TopMaterial = Enum.Material.Grass,
			Wall = rgb(100, 80, 55),
			Accent = rgb(150, 230, 80),
			Accent2 = rgb(255, 210, 80),
			Hazard = rgb(130, 40, 60),
			HazardKind = "Thorns",
			PitKind = "River",
			Anchor = rgb(255, 210, 80),
			EdgeGlow = false,
			Decor = "Jungle",
			Lighting = {
				ClockTime = 16.2, Brightness = 2, Ambient = rgb(90, 120, 80), OutdoorAmbient = rgb(120, 150, 100),
				FogColor = rgb(120, 160, 110), FogStart = 180, FogEnd = 900,
				AtmosphereDensity = 0.4, AtmosphereColor = rgb(170, 210, 150), AtmosphereDecay = rgb(90, 130, 80), Haze = 2.2, Glare = 0.2,
				Tint = rgb(250, 255, 240), Saturation = 0.15, Contrast = 0.06, BloomIntensity = 0.5, BloomSize = 24, BloomThreshold = 1.1,
			},
		},
	},
}

MapDefinitions.Order = { "NeonMetropolis", "MagmaWorks", "SkywayRuins", "GlacierCircuit", "JungleVelocity" }

MapDefinitions.Lobby = {
	Id = "Lobby",
	Name = "Velocity Hub",
	Template = "Lobby",
	Seed = 7,
	Theme = {
		Ground = rgb(30, 34, 54),
		GroundMaterial = Enum.Material.SmoothPlastic,
		Top = rgb(48, 54, 86),
		TopMaterial = Enum.Material.SmoothPlastic,
		Wall = rgb(26, 30, 48),
		Accent = rgb(0, 214, 255),
		Accent2 = rgb(255, 64, 129),
		Hazard = rgb(255, 60, 90),
		HazardKind = "Laser",
		PitKind = "Laser",
		Anchor = rgb(0, 214, 255),
		EdgeGlow = true,
		Decor = "Hub",
		Lighting = {
			ClockTime = 20.5, Brightness = 1.4, Ambient = rgb(80, 75, 120), OutdoorAmbient = rgb(100, 90, 150),
			FogColor = rgb(40, 30, 80), FogStart = 250, FogEnd = 1200,
			AtmosphereDensity = 0.3, AtmosphereColor = rgb(130, 100, 220), AtmosphereDecay = rgb(70, 50, 140), Haze = 1.4, Glare = 0,
			Tint = rgb(240, 238, 255), Saturation = 0.12, Contrast = 0.06, BloomIntensity = 0.8, BloomSize = 26, BloomThreshold = 0.95,
		},
	},
}

MapDefinitions.Tutorial = {
	Id = "Tutorial",
	Name = "Bewegungs-Tutorial",
	Description = "Lerne Laufen, Springen, Sliden, Wall-Jumps, Greifhaken und Power-ups Schritt für Schritt.",
	Template = "Tutorial",
	Difficulty = 1,
	Seed = 9,
	Theme = MapDefinitions.Lobby.Theme,
}

--- Liefert die Definition einer Rennstrecke (nicht Lobby/Tutorial).
function MapDefinitions.Get(id: string)
	return MapDefinitions.Maps[id]
end

--- Liefert die Definition für Rennstrecken, Lobby oder Tutorial.
function MapDefinitions.GetAny(id: string)
	if id == "Lobby" then
		return MapDefinitions.Lobby
	elseif id == "Tutorial" then
		return MapDefinitions.Tutorial
	end
	return MapDefinitions.Maps[id]
end

return MapDefinitions
