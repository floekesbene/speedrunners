--[[
	CosmeticDefinitions  (ModuleScript)
	Pfad: ReplicatedStorage/Shared/CosmeticDefinitions

	Katalog aller kosmetischen Gegenstände. Alles wird ausschließlich aus
	Roblox-Standardteilen, Farben, Materialien, Trails und Partikeln gebaut –
	es werden keine externen Assets benötigt.

	WICHTIG: Kosmetik hat KEINEN Einfluss auf Hitbox, Geschwindigkeit oder
	Sprunghöhe. Accessoires sind Massless, CanCollide=false, CanQuery=false.

	Kategorien: Skins, Trails, Effects, Emotes, Victory, Colors
]]

local CosmeticDefinitions = {}

local rgb = Color3.fromRGB

CosmeticDefinitions.Categories = { "Skins", "Trails", "Effects", "Emotes", "Victory", "Colors" }

CosmeticDefinitions.CategoryNames = {
	Skins = "Skins",
	Trails = "Trails",
	Effects = "Effekte",
	Emotes = "Emotes",
	Victory = "Siegesanimationen",
	Colors = "Farbvarianten",
}

CosmeticDefinitions.Rarities = {
	Common = { Name = "Gewöhnlich", Color = rgb(160, 175, 200), Order = 1 },
	Rare = { Name = "Selten", Color = rgb(70, 150, 255), Order = 2 },
	Epic = { Name = "Episch", Color = rgb(180, 90, 255), Order = 3 },
	Legendary = { Name = "Legendär", Color = rgb(255, 190, 40), Order = 4 },
}

-- Wiederverwendbare Accessoire-Bausteine. Offsets sind relativ zum Mittelpunkt
-- des Körperteils (Blickrichtung des Rigs = -Z, Rücken = +Z).
-- Farbe: "Accent" | "Visor" | "Primary" | "Secondary" | "Dark" | Color3
local A = {}

A.Visor = {
	{ Attach = "Head", Shape = "Block", Size = Vector3.new(1.0, 0.38, 0.12), Offset = CFrame.new(0, 0.12, -0.66), Color = "Visor", Material = Enum.Material.Neon },
}
A.VisorWide = {
	{ Attach = "Head", Shape = "Block", Size = Vector3.new(1.18, 0.45, 0.12), Offset = CFrame.new(0, 0.1, -0.66), Color = "Visor", Material = Enum.Material.Neon },
}
A.Helmet = {
	{ Attach = "Head", Shape = "Block", Size = Vector3.new(1.38, 0.45, 1.38), Offset = CFrame.new(0, 0.5, 0), Color = "Primary" },
}
A.HelmetFin = {
	{ Attach = "Head", Shape = "Wedge", Size = Vector3.new(0.18, 0.55, 1.0), Offset = CFrame.new(0, 0.98, 0.1), Color = "Accent", Material = Enum.Material.Neon },
}
A.Antenna = {
	{ Attach = "Head", Shape = "Cylinder", Size = Vector3.new(1.1, 0.12, 0.12), Offset = CFrame.new(0.4, 1.15, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = "Dark" },
	{ Attach = "Head", Shape = "Ball", Size = Vector3.new(0.32, 0.32, 0.32), Offset = CFrame.new(0.4, 1.75, 0), Color = "Accent", Material = Enum.Material.Neon },
}
A.Goggles = {
	{ Attach = "Head", Shape = "Block", Size = Vector3.new(1.32, 0.16, 1.32), Offset = CFrame.new(0, 0.38, 0), Color = "Dark" },
	{ Attach = "Head", Shape = "Cylinder", Size = Vector3.new(0.2, 0.44, 0.44), Offset = CFrame.new(-0.28, 0.38, -0.66) * CFrame.Angles(0, math.rad(90), 0), Color = "Visor", Material = Enum.Material.Glass },
	{ Attach = "Head", Shape = "Cylinder", Size = Vector3.new(0.2, 0.44, 0.44), Offset = CFrame.new(0.28, 0.38, -0.66) * CFrame.Angles(0, math.rad(90), 0), Color = "Visor", Material = Enum.Material.Glass },
}
A.Mask = {
	{ Attach = "Head", Shape = "Block", Size = Vector3.new(1.05, 0.5, 0.12), Offset = CFrame.new(0, -0.3, -0.66), Color = "Dark" },
}
A.Horns = {
	{ Attach = "Head", Shape = "Wedge", Size = Vector3.new(0.22, 0.75, 0.4), Offset = CFrame.new(-0.48, 0.85, 0.05) * CFrame.Angles(0, 0, math.rad(18)), Color = "Accent", Material = Enum.Material.Neon },
	{ Attach = "Head", Shape = "Wedge", Size = Vector3.new(0.22, 0.75, 0.4), Offset = CFrame.new(0.48, 0.85, 0.05) * CFrame.Angles(0, 0, math.rad(-18)), Color = "Accent", Material = Enum.Material.Neon },
}
A.Crown = {
	{ Attach = "Head", Shape = "Block", Size = Vector3.new(1.32, 0.28, 1.32), Offset = CFrame.new(0, 0.74, 0), Color = "Accent", Material = Enum.Material.Foil },
	{ Attach = "Head", Shape = "Wedge", Size = Vector3.new(0.28, 0.45, 0.28), Offset = CFrame.new(-0.5, 1.08, -0.5), Color = "Accent", Material = Enum.Material.Foil },
	{ Attach = "Head", Shape = "Wedge", Size = Vector3.new(0.28, 0.45, 0.28), Offset = CFrame.new(0.5, 1.08, -0.5), Color = "Accent", Material = Enum.Material.Foil },
	{ Attach = "Head", Shape = "Wedge", Size = Vector3.new(0.28, 0.45, 0.28), Offset = CFrame.new(-0.5, 1.08, 0.5) * CFrame.Angles(0, math.rad(180), 0), Color = "Accent", Material = Enum.Material.Foil },
	{ Attach = "Head", Shape = "Wedge", Size = Vector3.new(0.28, 0.45, 0.28), Offset = CFrame.new(0.5, 1.08, 0.5) * CFrame.Angles(0, math.rad(180), 0), Color = "Accent", Material = Enum.Material.Foil },
	{ Attach = "Head", Shape = "Ball", Size = Vector3.new(0.26, 0.26, 0.26), Offset = CFrame.new(0, 0.78, -0.68), Color = rgb(200, 40, 90), Material = Enum.Material.Neon },
}
A.Halo = {
	{ Attach = "Head", Shape = "Cylinder", Size = Vector3.new(0.1, 1.5, 1.5), Offset = CFrame.new(0, 1.3, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = "Accent", Material = Enum.Material.Neon, Transparency = 0.25 },
}
A.ShoulderPads = {
	{ Attach = "LeftUpperArm", Shape = "Block", Size = Vector3.new(1.0, 0.35, 1.0), Offset = CFrame.new(-0.05, 0.56, 0), Color = "Secondary" },
	{ Attach = "RightUpperArm", Shape = "Block", Size = Vector3.new(1.0, 0.35, 1.0), Offset = CFrame.new(0.05, 0.56, 0), Color = "Secondary" },
}
A.IceSpikes = {
	{ Attach = "LeftUpperArm", Shape = "Wedge", Size = Vector3.new(0.3, 0.8, 0.35), Offset = CFrame.new(0, 0.9, 0), Color = "Accent", Material = Enum.Material.Neon },
	{ Attach = "RightUpperArm", Shape = "Wedge", Size = Vector3.new(0.3, 0.8, 0.35), Offset = CFrame.new(0, 0.9, 0), Color = "Accent", Material = Enum.Material.Neon },
	{ Attach = "Head", Shape = "Wedge", Size = Vector3.new(0.25, 0.6, 0.5), Offset = CFrame.new(0, 0.9, 0.1), Color = "Accent", Material = Enum.Material.Neon },
}
A.Backpack = {
	{ Attach = "UpperTorso", Shape = "Block", Size = Vector3.new(1.3, 1.0, 0.45), Offset = CFrame.new(0, 0.05, 0.73), Color = "Secondary" },
	{ Attach = "UpperTorso", Shape = "Cylinder", Size = Vector3.new(0.5, 0.36, 0.36), Offset = CFrame.new(-0.38, -0.6, 0.75) * CFrame.Angles(0, 0, math.rad(90)), Color = "Accent", Material = Enum.Material.Neon },
	{ Attach = "UpperTorso", Shape = "Cylinder", Size = Vector3.new(0.5, 0.36, 0.36), Offset = CFrame.new(0.38, -0.6, 0.75) * CFrame.Angles(0, 0, math.rad(90)), Color = "Accent", Material = Enum.Material.Neon },
}
A.Scarf = {
	{ Attach = "UpperTorso", Shape = "Block", Size = Vector3.new(1.5, 0.3, 1.15), Offset = CFrame.new(0, 0.62, 0), Color = "Accent" },
	{ Attach = "UpperTorso", Shape = "Block", Size = Vector3.new(0.4, 1.0, 0.12), Offset = CFrame.new(0.35, 0.25, 0.62) * CFrame.Angles(math.rad(18), 0, 0), Color = "Accent" },
}
A.CircuitLines = {
	{ Attach = "UpperTorso", Shape = "Block", Size = Vector3.new(0.14, 1.3, 0.05), Offset = CFrame.new(0, 0, -0.52), Color = "Accent", Material = Enum.Material.Neon },
	{ Attach = "UpperTorso", Shape = "Block", Size = Vector3.new(1.8, 0.12, 0.05), Offset = CFrame.new(0, 0.3, -0.52), Color = "Accent", Material = Enum.Material.Neon },
	{ Attach = "LeftLowerArm", Shape = "Block", Size = Vector3.new(0.8, 0.12, 0.8), Offset = CFrame.new(0, 0, 0), Color = "Accent", Material = Enum.Material.Neon },
	{ Attach = "RightLowerArm", Shape = "Block", Size = Vector3.new(0.8, 0.12, 0.8), Offset = CFrame.new(0, 0, 0), Color = "Accent", Material = Enum.Material.Neon },
	{ Attach = "LeftLowerLeg", Shape = "Block", Size = Vector3.new(0.85, 0.12, 0.85), Offset = CFrame.new(0, 0.1, 0), Color = "Accent", Material = Enum.Material.Neon },
	{ Attach = "RightLowerLeg", Shape = "Block", Size = Vector3.new(0.85, 0.12, 0.85), Offset = CFrame.new(0, 0.1, 0), Color = "Accent", Material = Enum.Material.Neon },
}
A.Belt = {
	{ Attach = "LowerTorso", Shape = "Block", Size = Vector3.new(1.96, 0.22, 1.06), Offset = CFrame.new(0, 0.12, 0), Color = "Dark" },
	{ Attach = "LowerTorso", Shape = "Block", Size = Vector3.new(0.4, 0.26, 0.08), Offset = CFrame.new(0, 0.12, -0.54), Color = "Accent", Material = Enum.Material.Neon },
}
A.Leaves = {
	{ Attach = "Head", Shape = "Wedge", Size = Vector3.new(0.15, 0.6, 0.7), Offset = CFrame.new(-0.68, 0.45, 0) * CFrame.Angles(0, 0, math.rad(25)), Color = "Accent" },
	{ Attach = "Head", Shape = "Wedge", Size = Vector3.new(0.15, 0.6, 0.7), Offset = CFrame.new(0.68, 0.45, 0) * CFrame.Angles(0, 0, math.rad(-25)), Color = "Accent" },
}
A.Stars = {
	{ Attach = "UpperTorso", Shape = "Ball", Size = Vector3.new(0.18, 0.18, 0.18), Offset = CFrame.new(-0.5, 0.35, -0.5), Color = rgb(255, 255, 255), Material = Enum.Material.Neon },
	{ Attach = "UpperTorso", Shape = "Ball", Size = Vector3.new(0.14, 0.14, 0.14), Offset = CFrame.new(0.4, -0.2, -0.5), Color = rgb(255, 255, 255), Material = Enum.Material.Neon },
	{ Attach = "UpperTorso", Shape = "Ball", Size = Vector3.new(0.22, 0.22, 0.22), Offset = CFrame.new(0.1, 0.45, -0.5), Color = "Accent", Material = Enum.Material.Neon },
	{ Attach = "LeftUpperLeg", Shape = "Ball", Size = Vector3.new(0.16, 0.16, 0.16), Offset = CFrame.new(0, 0.1, -0.42), Color = rgb(255, 255, 255), Material = Enum.Material.Neon },
	{ Attach = "RightLowerArm", Shape = "Ball", Size = Vector3.new(0.16, 0.16, 0.16), Offset = CFrame.new(0, 0.1, -0.38), Color = "Accent", Material = Enum.Material.Neon },
}
A.FlameFins = {
	{ Attach = "UpperTorso", Shape = "Wedge", Size = Vector3.new(0.15, 1.0, 0.7), Offset = CFrame.new(-0.4, 0.35, 0.8), Color = "Accent", Material = Enum.Material.Neon },
	{ Attach = "UpperTorso", Shape = "Wedge", Size = Vector3.new(0.15, 1.0, 0.7), Offset = CFrame.new(0.4, 0.35, 0.8), Color = "Accent", Material = Enum.Material.Neon },
}

CosmeticDefinitions.AccessoryPresets = A

CosmeticDefinitions.Items = {
	Skins = {
		{
			Id = "Rookie", Name = "Rookie", Rarity = "Common", Price = 0, Default = true,
			Description = "Der Standard-Runner. Solide, schnell, bereit.",
			Colors = { Head = rgb(235, 238, 245), Torso = rgb(60, 130, 255), Hips = rgb(40, 50, 75), Arms = rgb(60, 130, 255), Hands = rgb(235, 238, 245), Legs = rgb(40, 50, 75), Feet = rgb(25, 28, 36) },
			Primary = rgb(60, 130, 255), Secondary = rgb(40, 50, 75), Dark = rgb(25, 28, 36), Accent = rgb(0, 214, 255), Visor = rgb(0, 214, 255),
			Accessories = { "Visor", "Belt" },
		},
		{
			Id = "NeonPulse", Name = "Neon Pulse", Rarity = "Rare", Price = 750,
			Description = "Schwarzer Anzug mit pulsierenden Neonakzenten.",
			Colors = { Head = rgb(25, 25, 32), Torso = rgb(20, 20, 28), Hips = rgb(30, 30, 40), Arms = rgb(20, 20, 28), Hands = rgb(255, 60, 200), Legs = rgb(30, 30, 40), Feet = rgb(255, 60, 200) },
			Primary = rgb(20, 20, 28), Secondary = rgb(45, 45, 60), Dark = rgb(15, 15, 20), Accent = rgb(255, 60, 200), Visor = rgb(255, 60, 200),
			Accessories = { "VisorWide", "Backpack", "CircuitLines" },
		},
		{
			Id = "MagmaCore", Name = "Magma Core", Rarity = "Rare", Price = 900,
			Description = "Vulkangestein mit glühendem Kern.",
			Material = Enum.Material.Slate,
			Colors = { Head = rgb(60, 45, 40), Torso = rgb(55, 40, 35), Hips = rgb(40, 30, 28), Arms = rgb(55, 40, 35), Hands = rgb(255, 110, 20), Legs = rgb(40, 30, 28), Feet = rgb(30, 22, 20) },
			Primary = rgb(55, 40, 35), Secondary = rgb(80, 55, 45), Dark = rgb(25, 18, 16), Accent = rgb(255, 110, 20), Visor = rgb(255, 150, 30),
			Accessories = { "Visor", "Horns", "CircuitLines" },
		},
		{
			Id = "Frostbite", Name = "Frostbite", Rarity = "Rare", Price = 900,
			Description = "Eiskalte Panzerung mit Kristallspitzen.",
			Colors = { Head = rgb(235, 245, 255), Torso = rgb(200, 230, 255), Hips = rgb(150, 190, 230), Arms = rgb(200, 230, 255), Hands = rgb(150, 220, 255), Legs = rgb(150, 190, 230), Feet = rgb(90, 130, 180) },
			Materials = { Torso = Enum.Material.Ice, Arms = Enum.Material.Ice },
			Primary = rgb(200, 230, 255), Secondary = rgb(150, 190, 230), Dark = rgb(70, 100, 150), Accent = rgb(120, 220, 255), Visor = rgb(140, 240, 255),
			Accessories = { "Visor", "IceSpikes" },
		},
		{
			Id = "JungleScout", Name = "Jungle Scout", Rarity = "Common", Price = 400,
			Description = "Getarnt zwischen Lianen und Blättern.",
			Colors = { Head = rgb(225, 200, 160), Torso = rgb(70, 120, 60), Hips = rgb(95, 75, 50), Arms = rgb(70, 120, 60), Hands = rgb(225, 200, 160), Legs = rgb(95, 75, 50), Feet = rgb(60, 45, 30) },
			Primary = rgb(70, 120, 60), Secondary = rgb(95, 75, 50), Dark = rgb(50, 40, 28), Accent = rgb(120, 200, 70), Visor = rgb(255, 220, 90),
			Accessories = { "Visor", "Leaves", "Scarf" },
		},
		{
			Id = "SkyPilot", Name = "Sky Pilot", Rarity = "Common", Price = 500,
			Description = "Fliegerjacke, Schutzbrille und ein flatternder Schal.",
			Colors = { Head = rgb(230, 205, 175), Torso = rgb(130, 85, 50), Hips = rgb(70, 60, 50), Arms = rgb(130, 85, 50), Hands = rgb(60, 45, 35), Legs = rgb(70, 60, 50), Feet = rgb(45, 35, 28) },
			Materials = { Torso = Enum.Material.Fabric, Arms = Enum.Material.Fabric },
			Primary = rgb(130, 85, 50), Secondary = rgb(70, 60, 50), Dark = rgb(45, 35, 28), Accent = rgb(220, 50, 50), Visor = rgb(120, 200, 255),
			Accessories = { "Goggles", "Scarf" },
		},
		{
			Id = "ShadowOps", Name = "Shadow Ops", Rarity = "Epic", Price = 1800,
			Description = "Lautlos. Schwarz. Mit rotem Visier.",
			Colors = { Head = rgb(22, 22, 26), Torso = rgb(18, 18, 22), Hips = rgb(28, 28, 32), Arms = rgb(18, 18, 22), Hands = rgb(28, 28, 32), Legs = rgb(28, 28, 32), Feet = rgb(12, 12, 14) },
			Material = Enum.Material.Fabric,
			Primary = rgb(18, 18, 22), Secondary = rgb(40, 40, 46), Dark = rgb(10, 10, 12), Accent = rgb(255, 40, 40), Visor = rgb(255, 40, 40),
			Accessories = { "Visor", "Mask", "ShoulderPads", "Belt" },
		},
		{
			Id = "RoyalGold", Name = "Royal Gold", Rarity = "Legendary", Price = 5000,
			Description = "Für Champions. Goldene Rüstung samt Krone.",
			Material = Enum.Material.Foil,
			Colors = { Head = rgb(255, 205, 70), Torso = rgb(255, 190, 40), Hips = rgb(110, 40, 140), Arms = rgb(255, 190, 40), Hands = rgb(110, 40, 140), Legs = rgb(110, 40, 140), Feet = rgb(255, 190, 40) },
			Primary = rgb(255, 190, 40), Secondary = rgb(110, 40, 140), Dark = rgb(70, 25, 90), Accent = rgb(255, 215, 80), Visor = rgb(170, 80, 255),
			Accessories = { "Visor", "Crown", "ShoulderPads" },
		},
		{
			Id = "CircuitBreaker", Name = "Circuit Breaker", Rarity = "Epic", Price = 2200,
			Description = "Leiterbahnen voller Energie.",
			Colors = { Head = rgb(20, 30, 60), Torso = rgb(15, 25, 55), Hips = rgb(20, 35, 70), Arms = rgb(15, 25, 55), Hands = rgb(60, 255, 120), Legs = rgb(20, 35, 70), Feet = rgb(10, 15, 35) },
			Primary = rgb(15, 25, 55), Secondary = rgb(25, 45, 90), Dark = rgb(8, 12, 28), Accent = rgb(60, 255, 120), Visor = rgb(60, 255, 120),
			Accessories = { "VisorWide", "CircuitLines", "Antenna" },
		},
		{
			Id = "RetroArcade", Name = "Retro Arcade", Rarity = "Rare", Price = 1200,
			Description = "Knallige Primärfarben direkt aus dem Spielautomaten.",
			Colors = { Head = rgb(255, 220, 60), Torso = rgb(230, 40, 50), Hips = rgb(40, 90, 230), Arms = rgb(255, 220, 60), Hands = rgb(255, 255, 255), Legs = rgb(40, 90, 230), Feet = rgb(255, 255, 255) },
			Primary = rgb(230, 40, 50), Secondary = rgb(40, 90, 230), Dark = rgb(30, 30, 30), Accent = rgb(255, 220, 60), Visor = rgb(40, 40, 40),
			Accessories = { "Visor", "Antenna", "Belt" },
		},
		{
			Id = "ChromePhantom", Name = "Chrome Phantom", Rarity = "Legendary", Price = 6000,
			Description = "Spiegelnder Chrom mit leuchtendem Heiligenschein.",
			Material = Enum.Material.Metal,
			Colors = { Head = rgb(210, 215, 225), Torso = rgb(190, 195, 205), Hips = rgb(150, 155, 165), Arms = rgb(190, 195, 205), Hands = rgb(150, 155, 165), Legs = rgb(150, 155, 165), Feet = rgb(110, 115, 125) },
			Primary = rgb(190, 195, 205), Secondary = rgb(140, 145, 155), Dark = rgb(90, 95, 105), Accent = rgb(240, 250, 255), Visor = rgb(120, 230, 255),
			Accessories = { "VisorWide", "Halo", "ShoulderPads" },
		},
		{
			Id = "SolarFlare", Name = "Solar Flare", Rarity = "Epic", Price = 2000,
			Description = "Heiß wie eine Sonneneruption, mit Flammenflossen.",
			Colors = { Head = rgb(255, 200, 80), Torso = rgb(255, 120, 30), Hips = rgb(200, 60, 20), Arms = rgb(255, 120, 30), Hands = rgb(255, 230, 120), Legs = rgb(200, 60, 20), Feet = rgb(120, 30, 10) },
			Primary = rgb(255, 120, 30), Secondary = rgb(200, 60, 20), Dark = rgb(110, 30, 10), Accent = rgb(255, 230, 60), Visor = rgb(255, 250, 180),
			Accessories = { "VisorWide", "FlameFins", "HelmetFin" },
		},
		{
			Id = "GalaxyDrift", Name = "Galaxy Drift", Rarity = "Legendary", Price = 7500, LevelRequired = 20,
			Description = "Ein Anzug aus Sternenstaub. Ab Level 20.",
			Colors = { Head = rgb(40, 20, 80), Torso = rgb(30, 15, 70), Hips = rgb(20, 20, 60), Arms = rgb(30, 15, 70), Hands = rgb(120, 60, 220), Legs = rgb(20, 20, 60), Feet = rgb(10, 10, 30) },
			Primary = rgb(30, 15, 70), Secondary = rgb(60, 30, 120), Dark = rgb(10, 8, 30), Accent = rgb(170, 110, 255), Visor = rgb(255, 120, 230),
			Accessories = { "VisorWide", "Stars", "Halo", "Backpack" },
		},
	},
	Trails = {
		{ Id = "SpeedLines", Name = "Speed Lines", Rarity = "Common", Price = 300, Description = "Saubere weiße Speedlines.", ColorA = rgb(255, 255, 255), ColorB = rgb(180, 220, 255), Lifetime = 0.35, Width = 0.9, LightEmission = 0.4 },
		{ Id = "NeonStream", Name = "Neon Stream", Rarity = "Rare", Price = 800, Description = "Ein leuchtender Neonstrom.", ColorA = rgb(0, 230, 255), ColorB = rgb(255, 60, 200), Lifetime = 0.5, Width = 1.1, LightEmission = 1 },
		{ Id = "EmberTrail", Name = "Ember Trail", Rarity = "Rare", Price = 900, Description = "Glühende Glut hinter dir.", ColorA = rgb(255, 200, 60), ColorB = rgb(255, 50, 20), Lifetime = 0.45, Width = 1.0, LightEmission = 1 },
		{ Id = "FrostWake", Name = "Frost Wake", Rarity = "Rare", Price = 900, Description = "Eisiger Hauch.", ColorA = rgb(230, 250, 255), ColorB = rgb(90, 190, 255), Lifetime = 0.5, Width = 1.0, LightEmission = 0.7 },
		{ Id = "ShadowWake", Name = "Shadow Wake", Rarity = "Epic", Price = 1600, Description = "Ein Schatten, der dir folgt.", ColorA = rgb(60, 0, 80), ColorB = rgb(0, 0, 0), Lifetime = 0.6, Width = 1.3, LightEmission = 0 },
		{ Id = "RainbowRush", Name = "Rainbow Rush", Rarity = "Legendary", Price = 4000, Description = "Alle Farben. Volle Geschwindigkeit.", Rainbow = true, Lifetime = 0.6, Width = 1.2, LightEmission = 0.8 },
	},
	Effects = {
		{ Id = "Sparkles", Name = "Sparkles", Rarity = "Common", Price = 400, Description = "Funkelnde Partikel.", Color = rgb(255, 255, 200), Rate = 8, Size = 0.35, Speed = 1.5, LightEmission = 1 },
		{ Id = "Embers", Name = "Embers", Rarity = "Rare", Price = 900, Description = "Aufsteigende Glut.", Color = rgb(255, 120, 30), Rate = 12, Size = 0.3, Speed = 3, LightEmission = 1, Rise = 4 },
		{ Id = "Snowfall", Name = "Snowfall", Rarity = "Rare", Price = 900, Description = "Leise rieselnder Schnee.", Color = rgb(240, 250, 255), Rate = 10, Size = 0.3, Speed = 1, LightEmission = 0.3, Rise = -3 },
		{ Id = "Electric", Name = "Electric", Rarity = "Epic", Price = 1800, Description = "Knisternde Energie.", Color = rgb(120, 200, 255), Rate = 20, Size = 0.25, Speed = 6, LightEmission = 1 },
		{ Id = "Stardust", Name = "Stardust", Rarity = "Legendary", Price = 3500, Description = "Kosmischer Sternenstaub.", Color = rgb(200, 140, 255), Rate = 16, Size = 0.4, Speed = 2, LightEmission = 1, Rainbow = true },
	},
	Emotes = {
		{ Id = "Wave", Name = "Winken", Rarity = "Common", Price = 0, Default = true, Description = "Ein freundliches Hallo.", Duration = 2.5 },
		{ Id = "Dance", Name = "Tanz", Rarity = "Rare", Price = 400, Description = "Zeig deine Moves.", Duration = 4 },
		{ Id = "Flex", Name = "Flex", Rarity = "Common", Price = 500, Description = "Muskeln zeigen.", Duration = 2.5 },
		{ Id = "Spin", Name = "Pirouette", Rarity = "Epic", Price = 600, Description = "Eine schnelle Drehung.", Duration = 2 },
		{ Id = "Salute", Name = "Salut", Rarity = "Common", Price = 400, Description = "Respekt an die Konkurrenz.", Duration = 2.5 },
	},
	Victory = {
		{ Id = "Confetti", Name = "Konfetti", Rarity = "Common", Price = 600, Description = "Bunter Konfettiregen beim Sieg.", Effect = "Confetti" },
		{ Id = "Fireworks", Name = "Feuerwerk", Rarity = "Rare", Price = 1200, Description = "Raketen am Himmel.", Effect = "Fireworks" },
		{ Id = "Lightning", Name = "Blitzschlag", Rarity = "Epic", Price = 2000, Description = "Ein Blitz trifft den Champion.", Effect = "Lightning" },
		{ Id = "GoldenRain", Name = "Goldregen", Rarity = "Legendary", Price = 3500, Description = "Es regnet Gold.", Effect = "GoldenRain" },
	},
	Colors = {
		{ Id = "Crimson", Name = "Crimson", Rarity = "Common", Price = 200, Description = "Ersetzt die Akzentfarbe durch Rot.", Color = rgb(255, 50, 70) },
		{ Id = "Azure", Name = "Azure", Rarity = "Common", Price = 200, Description = "Ersetzt die Akzentfarbe durch Blau.", Color = rgb(50, 140, 255) },
		{ Id = "Lime", Name = "Lime", Rarity = "Common", Price = 200, Description = "Ersetzt die Akzentfarbe durch Grün.", Color = rgb(130, 255, 60) },
		{ Id = "Violet", Name = "Violet", Rarity = "Rare", Price = 350, Description = "Ersetzt die Akzentfarbe durch Violett.", Color = rgb(170, 80, 255) },
		{ Id = "Sunset", Name = "Sunset", Rarity = "Rare", Price = 350, Description = "Ersetzt die Akzentfarbe durch Orange.", Color = rgb(255, 140, 40) },
		{ Id = "Mint", Name = "Mint", Rarity = "Rare", Price = 350, Description = "Ersetzt die Akzentfarbe durch Mint.", Color = rgb(80, 255, 200) },
	},
}

-- Schneller Zugriff: Lookup[category][id] = item
CosmeticDefinitions.Lookup = {}
for category, list in CosmeticDefinitions.Items do
	local map = {}
	for index, item in list do
		item.Category = category
		item.Index = index
		map[item.Id] = item
	end
	CosmeticDefinitions.Lookup[category] = map
end

--- Liefert die Definition eines Items oder nil.
function CosmeticDefinitions.Get(category: string, id: string)
	local map = CosmeticDefinitions.Lookup[category]
	return map and map[id] or nil
end

--- True, wenn eine Kategorie existiert.
function CosmeticDefinitions.IsCategory(category: any): boolean
	return type(category) == "string" and CosmeticDefinitions.Lookup[category] ~= nil
end

--- Kategorien, in denen man nichts ausrüsten "muss" (Ablegen erlaubt).
CosmeticDefinitions.Unequippable = {
	Skins = false,
	Trails = true,
	Effects = true,
	Emotes = false,
	Victory = true,
	Colors = true,
}

CosmeticDefinitions.DefaultEquipped = {
	Skins = "Rookie",
	Trails = "",
	Effects = "",
	Emotes = "Wave",
	Victory = "",
	Colors = "",
}

return CosmeticDefinitions
