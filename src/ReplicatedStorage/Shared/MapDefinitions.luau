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

	Theme-Felder (alle Farben Color3, Materialien Enum.Material):
		Strecke (kollidierbare Teile – nur Farbe/Material):
			Ground, GroundMaterial      Unterbau der Plattformen
			Top, TopMaterial            Lauffläche (oberste 1 Stud)
			Wall, WallMaterial          Wände, Tunneldecken, Startwand/Endwand
		Zierteile (MapBuilder, nur Dekoration):
			Trim, TrimMaterial          Vorderkanten-Lippe und Eckleisten
			Detail, DetailMaterial      Rippen, Bänder, Paneele an der Vorderseite
			Support, SupportMaterial    Stützen unter den Plattformen
			RibStyle                    "Panel" | "Joint" | "Root" | "Pipe" | "Strata"
			SupportStyle                "Girder" | "Pillar" | "Hanging" | "Ice" | "Stilt"
			Props, PropSpacing          automatisch verteilte Requisiten (MapBuilder:Prop-Arten)
			Leaf                        Grundfarbe für Laub (Büsche, Bäume)
			Backdrop                    { Near, Mid, Far, Lights = { … } } Farben der Hintergrund-Ebenen
			Terrain                     { Ground, Cliff, Top, Liquid, Peak } Terrain-Materialien des Hintergrunds
		Spiel-Optik:
			Accent, Accent2, Hazard, Anchor, EdgeGlow
			HazardKind                  Art der zeitgesteuerten Gefahren
			PitKind                     Art der Gefahren in Gruben
			Decor                       Hintergrund-Stil ("City", "Industrial", "Sky", "Glacier",
			                            "Jungle", "Hub", "Academy")
		Lighting (vom Client angewendet; optionale Felder haben dort Standardwerte):
			ClockTime, Brightness, Ambient, OutdoorAmbient, FogColor, FogStart, FogEnd,
			AtmosphereDensity, AtmosphereColor, AtmosphereDecay, Haze, Glare,
			Tint, Saturation, Contrast, BloomIntensity, BloomSize, BloomThreshold,
			ExposureCompensation, EnvironmentDiffuseScale (0–1), EnvironmentSpecularScale (0–1),
			ShadowSoftness (0–1), SunRaysIntensity (0–1), SunRaysSpread (0–1),
			DofFarIntensity (0–1), DofInFocusRadius (Studs), StarCount, CelestialBodiesShown,
			SunAngularSize
]]

local MapDefinitions = {}

local rgb = Color3.fromRGB
local M = Enum.Material

MapDefinitions.Maps = {
	NeonMetropolis = {
		Id = "NeonMetropolis",
		Name = "Neon Metropolis",
		Description = "Futuristische Häuserschluchten voller Neon, Laserbarrieren und Greifpunkte.",
		Template = "NeonMetropolis",
		Difficulty = 2,
		Seed = 1101,
		Theme = {
			Ground = rgb(58, 62, 92),
			GroundMaterial = M.Concrete,
			Top = rgb(46, 48, 66),
			TopMaterial = M.Asphalt,
			Wall = rgb(52, 56, 86),
			WallMaterial = M.Metal,
			Trim = rgb(168, 178, 210),
			TrimMaterial = M.Metal,
			Detail = rgb(36, 39, 60),
			DetailMaterial = M.DiamondPlate,
			Support = rgb(78, 84, 118),
			SupportMaterial = M.Metal,
			RibStyle = "Panel",
			SupportStyle = "Girder",
			Props = { "Lamp", "Vent", "Crate", "Barrier", "HoloSign", "Antenna", "Crate", "Vent" },
			PropSpacing = 17,
			Leaf = rgb(60, 160, 120),
			Accent = rgb(0, 230, 255),
			Accent2 = rgb(255, 60, 200),
			Hazard = rgb(255, 40, 110),
			HazardKind = "Laser",
			PitKind = "Laser",
			Anchor = rgb(0, 230, 255),
			EdgeGlow = true,
			Decor = "City",
			Backdrop = {
				Near = rgb(34, 34, 60),
				Mid = rgb(50, 44, 90),
				Far = rgb(74, 58, 120),
				Lights = { rgb(255, 214, 140), rgb(0, 230, 255), rgb(255, 60, 200), rgb(150, 120, 255) },
			},
			Terrain = { Ground = M.Asphalt, Cliff = M.Slate, Top = M.Concrete, Liquid = M.Water, Peak = M.Slate },
			Lighting = {
				ClockTime = 21.4, Brightness = 2.2, Ambient = rgb(96, 88, 146), OutdoorAmbient = rgb(124, 112, 180),
				FogColor = rgb(70, 44, 120), FogStart = 400, FogEnd = 2600,
				AtmosphereDensity = 0.22, AtmosphereColor = rgb(170, 110, 255), AtmosphereDecay = rgb(255, 80, 190), Haze = 1.1, Glare = 0.2,
				Tint = rgb(242, 238, 255), Saturation = 0.22, Contrast = 0.14, BloomIntensity = 0.55, BloomSize = 26, BloomThreshold = 1.35,
				ExposureCompensation = 0.35, EnvironmentDiffuseScale = 0.55, EnvironmentSpecularScale = 0.9, ShadowSoftness = 0.35,
				SunRaysIntensity = 0.03, SunRaysSpread = 0.4, DofFarIntensity = 0.18, DofInFocusRadius = 120,
				StarCount = 4000, CelestialBodiesShown = true, SunAngularSize = 14,
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
			Ground = rgb(74, 62, 60),
			GroundMaterial = M.Basalt,
			Top = rgb(124, 116, 110),
			TopMaterial = M.DiamondPlate,
			Wall = rgb(92, 72, 62),
			WallMaterial = M.CorrodedMetal,
			Trim = rgb(240, 180, 46),
			TrimMaterial = M.DiamondPlate,
			Detail = rgb(140, 86, 54),
			DetailMaterial = M.CorrodedMetal,
			Support = rgb(104, 82, 72),
			SupportMaterial = M.CorrodedMetal,
			RibStyle = "Pipe",
			SupportStyle = "Pillar",
			Props = { "Barrel", "Crate", "Pipe", "WarningLamp", "Barrel", "Girder", "Crate", "Lamp" },
			PropSpacing = 16,
			Leaf = rgb(90, 110, 60),
			Accent = rgb(255, 130, 30),
			Accent2 = rgb(255, 200, 60),
			Hazard = rgb(255, 80, 10),
			HazardKind = "Flame",
			PitKind = "Lava",
			Anchor = rgb(255, 170, 40),
			EdgeGlow = true,
			Decor = "Industrial",
			Backdrop = {
				Near = rgb(64, 48, 44),
				Mid = rgb(100, 62, 50),
				Far = rgb(150, 86, 64),
				Lights = { rgb(255, 150, 40), rgb(255, 96, 24), rgb(255, 210, 90) },
			},
			Terrain = { Ground = M.Basalt, Cliff = M.Basalt, Top = M.Rock, Liquid = M.CrackedLava, Peak = M.Slate },
			Lighting = {
				ClockTime = 17.9, Brightness = 2.6, Ambient = rgb(128, 84, 66), OutdoorAmbient = rgb(160, 100, 76),
				FogColor = rgb(130, 66, 38), FogStart = 400, FogEnd = 2400,
				AtmosphereDensity = 0.27, AtmosphereColor = rgb(255, 150, 90), AtmosphereDecay = rgb(170, 70, 40), Haze = 1.2, Glare = 0.5,
				Tint = rgb(255, 238, 222), Saturation = 0.18, Contrast = 0.14, BloomIntensity = 0.5, BloomSize = 28, BloomThreshold = 1.35,
				ExposureCompensation = 0.15, EnvironmentDiffuseScale = 0.7, EnvironmentSpecularScale = 0.6, ShadowSoftness = 0.25,
				SunRaysIntensity = 0.16, SunRaysSpread = 0.35, DofFarIntensity = 0.2, DofInFocusRadius = 110,
				StarCount = 600, CelestialBodiesShown = true, SunAngularSize = 24,
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
			Ground = rgb(218, 200, 164),
			GroundMaterial = M.Limestone,
			Top = rgb(112, 186, 70),
			TopMaterial = M.LeafyGrass,
			Wall = rgb(226, 212, 182),
			WallMaterial = M.Sandstone,
			Trim = rgb(244, 240, 230),
			TrimMaterial = M.Marble,
			Detail = rgb(184, 158, 118),
			DetailMaterial = M.Sandstone,
			Support = rgb(170, 142, 104),
			SupportMaterial = M.Sandstone,
			RibStyle = "Joint",
			SupportStyle = "Hanging",
			Props = { "Column", "Bush", "Urn", "Flower", "Bush", "Rock", "Lamp", "Banner", "Tree" },
			PropSpacing = 18,
			Leaf = rgb(96, 176, 70),
			Accent = rgb(255, 205, 90),
			Accent2 = rgb(110, 210, 255),
			Hazard = rgb(160, 90, 255),
			HazardKind = "Arcane",
			PitKind = "Void",
			Anchor = rgb(255, 205, 90),
			EdgeGlow = false,
			Decor = "Sky",
			Backdrop = {
				Near = rgb(250, 252, 255),
				Mid = rgb(226, 236, 252),
				Far = rgb(206, 222, 246),
				Lights = { rgb(255, 205, 90), rgb(110, 210, 255) },
			},
			Terrain = { Ground = M.Sandstone, Cliff = M.Limestone, Top = M.LeafyGrass, Liquid = M.Water, Peak = M.Rock },
			Lighting = {
				ClockTime = 13.6, Brightness = 3, Ambient = rgb(142, 150, 172), OutdoorAmbient = rgb(168, 178, 200),
				FogColor = rgb(200, 225, 255), FogStart = 500, FogEnd = 3000,
				AtmosphereDensity = 0.18, AtmosphereColor = rgb(205, 228, 255), AtmosphereDecay = rgb(120, 170, 240), Haze = 0.4, Glare = 0.35,
				Tint = rgb(255, 252, 246), Saturation = 0.2, Contrast = 0.08, BloomIntensity = 0.35, BloomSize = 24, BloomThreshold = 1.6,
				ExposureCompensation = 0.1, EnvironmentDiffuseScale = 1, EnvironmentSpecularScale = 1, ShadowSoftness = 0.25,
				SunRaysIntensity = 0.14, SunRaysSpread = 0.25, DofFarIntensity = 0.12, DofInFocusRadius = 150,
				StarCount = 0, CelestialBodiesShown = true, SunAngularSize = 18,
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
			Ground = rgb(122, 178, 226),
			GroundMaterial = M.Glacier,
			Top = rgb(246, 250, 255),
			TopMaterial = M.Snow,
			Wall = rgb(106, 154, 204),
			WallMaterial = M.Glacier,
			Trim = rgb(214, 240, 255),
			TrimMaterial = M.Ice,
			Detail = rgb(84, 104, 134),
			DetailMaterial = M.Slate,
			Support = rgb(92, 110, 140),
			SupportMaterial = M.Slate,
			RibStyle = "Strata",
			SupportStyle = "Ice",
			Props = { "Pine", "SnowMound", "Crystal", "Rock", "Pine", "Lamp", "IceBlock", "SnowMound" },
			PropSpacing = 17,
			Leaf = rgb(36, 92, 70),
			Accent = rgb(90, 215, 255),
			Accent2 = rgb(200, 240, 255),
			Hazard = rgb(90, 200, 255),
			HazardKind = "Icicle",
			PitKind = "IceWater",
			Anchor = rgb(120, 235, 255),
			EdgeGlow = false,
			Decor = "Glacier",
			Backdrop = {
				Near = rgb(228, 240, 252),
				Mid = rgb(196, 218, 242),
				Far = rgb(176, 202, 234),
				Lights = { rgb(120, 230, 255), rgb(190, 160, 255) },
			},
			Terrain = { Ground = M.Snow, Cliff = M.Glacier, Top = M.Snow, Liquid = M.Water, Peak = M.Slate },
			Lighting = {
				ClockTime = 10.4, Brightness = 2.8, Ambient = rgb(140, 160, 188), OutdoorAmbient = rgb(170, 190, 218),
				FogColor = rgb(220, 235, 250), FogStart = 500, FogEnd = 2800,
				AtmosphereDensity = 0.22, AtmosphereColor = rgb(225, 240, 255), AtmosphereDecay = rgb(140, 185, 240), Haze = 0.6, Glare = 0.3,
				Tint = rgb(242, 248, 255), Saturation = 0.1, Contrast = 0.12, BloomIntensity = 0.4, BloomSize = 22, BloomThreshold = 1.6,
				ExposureCompensation = -0.05, EnvironmentDiffuseScale = 1, EnvironmentSpecularScale = 1, ShadowSoftness = 0.3,
				SunRaysIntensity = 0.12, SunRaysSpread = 0.3, DofFarIntensity = 0.15, DofInFocusRadius = 130,
				StarCount = 0, CelestialBodiesShown = true, SunAngularSize = 16,
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
			Ground = rgb(116, 82, 54),
			GroundMaterial = M.Ground,
			Top = rgb(92, 170, 58),
			TopMaterial = M.LeafyGrass,
			Wall = rgb(104, 100, 84),
			WallMaterial = M.Rock,
			Trim = rgb(72, 144, 50),
			TrimMaterial = M.LeafyGrass,
			Detail = rgb(86, 62, 42),
			DetailMaterial = M.Mud,
			Support = rgb(118, 84, 54),
			SupportMaterial = M.Wood,
			RibStyle = "Root",
			SupportStyle = "Stilt",
			Props = { "Bush", "Fern", "Mushroom", "Flower", "Rock", "Bush", "Log", "Torch", "Fern", "Tree" },
			PropSpacing = 14,
			Leaf = rgb(62, 150, 56),
			Accent = rgb(150, 235, 80),
			Accent2 = rgb(255, 205, 70),
			Hazard = rgb(130, 40, 60),
			HazardKind = "Thorns",
			PitKind = "River",
			Anchor = rgb(255, 205, 70),
			EdgeGlow = false,
			Decor = "Jungle",
			Backdrop = {
				Near = rgb(46, 100, 50),
				Mid = rgb(78, 132, 84),
				Far = rgb(118, 160, 128),
				Lights = { rgb(255, 230, 120), rgb(150, 235, 80) },
			},
			Terrain = { Ground = M.Mud, Cliff = M.Rock, Top = M.LeafyGrass, Liquid = M.Water, Peak = M.Ground },
			Lighting = {
				ClockTime = 15.4, Brightness = 2.7, Ambient = rgb(112, 136, 98), OutdoorAmbient = rgb(140, 166, 122),
				FogColor = rgb(170, 205, 160), FogStart = 400, FogEnd = 2400,
				AtmosphereDensity = 0.25, AtmosphereColor = rgb(195, 228, 175), AtmosphereDecay = rgb(110, 155, 95), Haze = 1, Glare = 0.3,
				Tint = rgb(255, 250, 232), Saturation = 0.25, Contrast = 0.1, BloomIntensity = 0.4, BloomSize = 24, BloomThreshold = 1.45,
				ExposureCompensation = 0.1, EnvironmentDiffuseScale = 0.9, EnvironmentSpecularScale = 0.7, ShadowSoftness = 0.3,
				SunRaysIntensity = 0.2, SunRaysSpread = 0.4, DofFarIntensity = 0.16, DofInFocusRadius = 120,
				StarCount = 0, CelestialBodiesShown = true, SunAngularSize = 20,
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
		Ground = rgb(64, 70, 104),
		GroundMaterial = M.Concrete,
		Top = rgb(82, 90, 128),
		TopMaterial = M.Pavement,
		Wall = rgb(56, 62, 94),
		WallMaterial = M.Metal,
		Trim = rgb(176, 186, 218),
		TrimMaterial = M.Metal,
		Detail = rgb(42, 46, 70),
		DetailMaterial = M.DiamondPlate,
		Support = rgb(84, 90, 124),
		SupportMaterial = M.Metal,
		RibStyle = "Panel",
		SupportStyle = "Girder",
		Props = { "Lamp", "Planter", "Bench", "HoloSign", "Planter" },
		PropSpacing = 20,
		Leaf = rgb(70, 170, 110),
		Accent = rgb(0, 214, 255),
		Accent2 = rgb(255, 64, 129),
		Hazard = rgb(255, 60, 90),
		HazardKind = "Laser",
		PitKind = "Laser",
		Anchor = rgb(0, 214, 255),
		EdgeGlow = true,
		Decor = "Hub",
		Backdrop = {
			Near = rgb(46, 46, 80),
			Mid = rgb(66, 62, 110),
			Far = rgb(96, 84, 144),
			Lights = { rgb(0, 214, 255), rgb(255, 64, 129), rgb(255, 214, 140) },
		},
		Terrain = { Ground = M.Concrete, Cliff = M.Slate, Top = M.Concrete, Liquid = M.Water, Peak = M.Slate },
		Lighting = {
			ClockTime = 17.6, Brightness = 2.4, Ambient = rgb(110, 100, 150), OutdoorAmbient = rgb(140, 128, 180),
			FogColor = rgb(110, 90, 160), FogStart = 400, FogEnd = 2600,
			AtmosphereDensity = 0.2, AtmosphereColor = rgb(190, 150, 255), AtmosphereDecay = rgb(255, 120, 170), Haze = 0.9, Glare = 0.4,
			Tint = rgb(248, 242, 255), Saturation = 0.2, Contrast = 0.12, BloomIntensity = 0.5, BloomSize = 26, BloomThreshold = 1.35,
			ExposureCompensation = 0.15, EnvironmentDiffuseScale = 0.8, EnvironmentSpecularScale = 0.8, ShadowSoftness = 0.3,
			SunRaysIntensity = 0.12, SunRaysSpread = 0.35, DofFarIntensity = 0.15, DofInFocusRadius = 120,
			StarCount = 1500, CelestialBodiesShown = true, SunAngularSize = 22,
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
	-- Eigenes, helles Theme: Trainingsgelände "Velocity Academy" bei Sonnenschein
	Theme = {
		Ground = rgb(208, 214, 226),
		GroundMaterial = M.Concrete,
		Top = rgb(216, 98, 72),
		TopMaterial = M.Pavement,
		Wall = rgb(232, 236, 244),
		WallMaterial = M.Concrete,
		Trim = rgb(255, 255, 255),
		TrimMaterial = M.SmoothPlastic,
		Detail = rgb(60, 140, 235),
		DetailMaterial = M.SmoothPlastic,
		Support = rgb(196, 202, 214),
		SupportMaterial = M.Concrete,
		RibStyle = "Panel",
		SupportStyle = "Pillar",
		Props = { "Cone", "Hurdle", "Bench", "Planter", "Lamp", "Cone", "Banner", "Tree" },
		PropSpacing = 18,
		Leaf = rgb(84, 170, 70),
		Accent = rgb(0, 190, 255),
		Accent2 = rgb(255, 180, 40),
		Hazard = rgb(255, 60, 90),
		HazardKind = "Laser",
		PitKind = "Laser",
		Anchor = rgb(0, 190, 255),
		EdgeGlow = false,
		Decor = "Academy",
		Backdrop = {
			Near = rgb(110, 176, 100),
			Mid = rgb(196, 214, 236),
			Far = rgb(206, 222, 244),
			Lights = { rgb(0, 190, 255), rgb(255, 180, 40), rgb(255, 90, 90) },
		},
		Terrain = { Ground = M.Ground, Cliff = M.Rock, Top = M.Grass, Liquid = M.Water, Peak = M.Rock },
		Lighting = {
			ClockTime = 13.2, Brightness = 3, Ambient = rgb(140, 145, 160), OutdoorAmbient = rgb(165, 170, 185),
			FogColor = rgb(205, 225, 250), FogStart = 500, FogEnd = 3000,
			AtmosphereDensity = 0.18, AtmosphereColor = rgb(210, 228, 255), AtmosphereDecay = rgb(130, 175, 240), Haze = 0.4, Glare = 0.3,
			Tint = rgb(255, 253, 248), Saturation = 0.18, Contrast = 0.08, BloomIntensity = 0.35, BloomSize = 24, BloomThreshold = 1.6,
			ExposureCompensation = 0.1, EnvironmentDiffuseScale = 1, EnvironmentSpecularScale = 1, ShadowSoftness = 0.25,
			SunRaysIntensity = 0.12, SunRaysSpread = 0.25, DofFarIntensity = 0.1, DofInFocusRadius = 150,
			StarCount = 0, CelestialBodiesShown = true, SunAngularSize = 18,
		},
	},
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
