--[[
	CosmeticDefinitions  (ModuleScript)
	Pfad: ReplicatedStorage/Shared/CosmeticDefinitions

	Katalog aller kosmetischen Gegenstände. Alles wird ausschließlich aus
	Roblox-Standardteilen (Block, Kugel, Zylinder, Keil, SpecialMesh "Sphere"
	als Ellipsoid), Farben, Materialien, Trails und Partikeln gebaut – es
	werden keine externen Assets benötigt.

	WICHTIG: Kosmetik hat KEINEN Einfluss auf Hitbox, Geschwindigkeit oder
	Sprunghöhe. Accessoires sind Massless, CanCollide=false, CanQuery=false.

	Kategorien: Skins, Trails, Effects, Emotes, Victory, Colors

	Skin-Felder (siehe CosmeticApplier):
		Colors        Farben je Körpergruppe (Head, Torso, Hips, Arms, Hands, Legs, Feet)
		Primary, Secondary, Dark, Accent, Visor   Palette (Primary/Secondary/Accent
		              dienen auch als Farbfelder im Shop)
		Trim, Ears, Joint, Collar, Belt, Sole     optionale Zusatzfarben der Körperhülle
		              (Fallback: Trim→Secondary, Ears→Primary, Collar→Joint,
		              Sole/Belt/Joint→Dark)
		Material      Grundmaterial der Körpergruppen und von "Primary"-Teilen
		TrimMaterial  Material für Trim/Dark/Secondary-Teile (Standard SmoothPlastic)
		Materials     Material je Slot/Gruppe, überschreibt alles (z.B. Hands = Neon)
		Reflectance   Glanz der Körpergruppen (z.B. Chrom)
		HideBase      Liste von Hüllen-Tags, die ausgeblendet werden
		              (Ears, Plate, Emblem, Back, Belt, Stripes – siehe RunnerRig)
		Accessories   Liste von AccessoryPresets
]]

local CosmeticDefinitions = {}

local rgb = Color3.fromRGB
local V = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local rad = math.rad

local NEON = Enum.Material.Neon
local GLASS = Enum.Material.Glass
local METAL = Enum.Material.Metal
local FABRIC = Enum.Material.Fabric
local FOIL = Enum.Material.Foil

local CYL_Y = ANG(0, 0, rad(90)) -- Zylinderachse senkrecht (Y)
local CYL_Z = ANG(0, rad(90), 0) -- Zylinderachse nach vorn (Z)

-- Mitte des Kugelhelms relativ zur Kopfmitte (Radius 0.68, siehe RunnerRig)
local HELMET_Y = 0.02
local BRASS = rgb(204, 168, 96)
local WHITE = rgb(255, 255, 255)

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

------------------------------------------------------------------------
-- Accessoire-Bausteine
------------------------------------------------------------------------
-- Offsets sind relativ zur Mitte des Körperteils (Blickrichtung des Rigs = -Z,
-- Rücken = +Z, rechts = +X). Die Spielkamera sieht die Figur im Profil, der
-- Shop von vorn – Silhouetten (Spitzen, Flossen, Bänder) wirken daher in der
-- YZ-Ebene am stärksten.
-- Shape: "Block" | "Ball" | "Cylinder" (Achse X) | "Wedge" | "Ellipsoid"
-- Color: Farbslot ("Primary", "Secondary", "Dark", "Accent", "Glow" = Akzent
--        leuchtend, "Visor", "Trim", eine Körpergruppe wie "Head") oder Color3
-- Optional: Material, Transparency, Reflectance, Shadow (wirft Schatten)
local A = {}

--- Spitze aus zwei Keilen: im Profil (Blick entlang X) ein gleichschenkliges
--- Dreieck. base = Fußpunkt, die Spitze zeigt entlang +Y von base.
local function spike(list, attach: string, base: CFrame, width: number, height: number, depth: number, color, material: Enum.Material?, transparency: number?)
	local size = V(width, height, depth / 2)
	table.insert(list, {
		Attach = attach,
		Shape = "Wedge",
		Size = size,
		Offset = base * CF(0, height / 2, -depth / 4),
		Color = color,
		Material = material,
		Transparency = transparency,
	})
	table.insert(list, {
		Attach = attach,
		Shape = "Wedge",
		Size = size,
		Offset = base * CF(0, height / 2, depth / 4) * ANG(0, math.pi, 0),
		Color = color,
		Material = material,
		Transparency = transparency,
	})
end

--- Ring aus kurzen Segmenten (Heiligenschein, Orbit). center = Ringmitte inkl. Neigung.
local function ring(list, attach: string, center: CFrame, radius: number, count: number, thickness: number, height: number, color, transparency: number?)
	local length = 2 * math.pi * radius / count * 1.08
	for i = 0, count - 1 do
		table.insert(list, {
			Attach = attach,
			Shape = "Block",
			Size = V(thickness, height, length),
			Offset = center * ANG(0, i / count * 2 * math.pi, 0) * CF(radius, 0, 0),
			Color = color,
			Transparency = transparency,
		})
	end
end

--- Punkt auf/unter der Helmoberfläche in Richtung des Winkels (0° = oben, + = nach hinten),
--- ausgerichtet entlang dieser Richtung (für Kämme, Flammen, Eisspitzen).
local function onHelmet(angle: number, radius: number, extraTilt: number?): CFrame
	local r = rad(angle)
	return CF(0, HELMET_Y + radius * math.cos(r), radius * math.sin(r)) * ANG(r + rad(extraTilt or 0), 0, 0)
end

local SIDES = { { Name = "Left", Sign = -1 }, { Name = "Right", Sign = 1 } }

-- Visiere -------------------------------------------------------------

-- Gewölbte Linse mit dunklem Rahmen vorn am Helm. Die Linse ist breiter als der
-- Rahmen, damit sie auch im Profil sichtbar ist; der Rahmen zeigt sich oben/unten.
A.Visor = {
	{ Attach = "Head", Shape = "Ellipsoid", Size = V(1.3, 0.62, 0.74), Offset = CF(0, 0.1, -0.34), Color = "Dark" },
	{ Attach = "Head", Shape = "Ellipsoid", Size = V(1.34, 0.5, 0.84), Offset = CF(0, 0.1, -0.36), Color = "Visor" },
}
-- Breites Band, das bis über die Ohrkapseln reicht (im Profil gut sichtbar)
A.VisorWide = {
	{ Attach = "Head", Shape = "Ellipsoid", Size = V(1.5, 0.6, 1.3), Offset = CF(0, 0.12, -0.1), Color = "Dark" },
	{ Attach = "Head", Shape = "Ellipsoid", Size = V(1.54, 0.46, 1.36), Offset = CF(0, 0.12, -0.14), Color = "Visor" },
}
-- Dunkle Gesichtsplatte mit schmalem Leuchtschlitz (breiter als die Platte -> auch im Profil sichtbar)
A.VisorSlit = {
	{ Attach = "Head", Shape = "Ellipsoid", Size = V(1.2, 0.74, 0.76), Offset = CF(0, 0.02, -0.36), Color = "Dark" },
	{ Attach = "Head", Shape = "Ellipsoid", Size = V(1.26, 0.13, 0.84), Offset = CF(0, 0.1, -0.38), Color = "Visor" },
}
-- Fliegerbrille: Kopfband, Messingfassungen, Glaslinsen
A.Goggles = {
	{ Attach = "Head", Shape = "Cylinder", Size = V(0.2, 1.42, 1.42), Offset = CF(0, 0.3, 0.08) * CYL_Y, Color = "Dark" },
	{ Attach = "Head", Shape = "Cylinder", Size = V(0.12, 0.5, 0.5), Offset = CF(-0.25, 0.3, -0.6) * CYL_Z, Color = BRASS, Material = METAL },
	{ Attach = "Head", Shape = "Cylinder", Size = V(0.12, 0.5, 0.5), Offset = CF(0.25, 0.3, -0.6) * CYL_Z, Color = BRASS, Material = METAL },
	{ Attach = "Head", Shape = "Cylinder", Size = V(0.1, 0.4, 0.4), Offset = CF(-0.25, 0.3, -0.65) * CYL_Z, Color = "Visor", Material = GLASS },
	{ Attach = "Head", Shape = "Cylinder", Size = V(0.1, 0.4, 0.4), Offset = CF(0.25, 0.3, -0.65) * CYL_Z, Color = "Visor", Material = GLASS },
}

-- Kopfschmuck ----------------------------------------------------------

-- Rennstreifen über den Helm (von vorn/oben sichtbar)
A.HeadStripe = {
	{ Attach = "Head", Shape = "Cylinder", Size = V(0.24, 1.4, 1.4), Offset = CF(0, HELMET_Y, 0), Color = "Primary" },
}

-- Irokesen aus Leuchtspitzen
do
	local list = {}
	local heights = { 0.5, 0.62, 0.58, 0.46 }
	for i, angle in { -25, 5, 35, 65 } do
		spike(list, "Head", onHelmet(angle, 0.6), 0.12, heights[i], 0.36, "Glow")
	end
	A.PunkSpikes = list
end

-- Nach hinten gewehte Flammenzungen
do
	local list = {}
	local heights = { 0.62, 0.8, 0.72, 0.5 }
	for i, angle in { -5, 25, 55, 85 } do
		local color = if i % 2 == 1 then "Glow" else rgb(255, 110, 20)
		spike(list, "Head", onHelmet(angle, 0.58, 22), 0.14, heights[i], 0.42, color, NEON)
	end
	A.FlameCrest = list
end

-- Eine Antenne mit Leuchtkugel, leicht nach hinten/außen geneigt
do
	local base = CF(0.3, 0.6, 0.1)
	local tilt = base * ANG(rad(15), 0, rad(-10))
	A.Antenna = {
		{ Attach = "Head", Shape = "Cylinder", Size = V(0.14, 0.26, 0.26), Offset = base * CYL_Y, Color = "Trim" },
		{ Attach = "Head", Shape = "Cylinder", Size = V(0.8, 0.08, 0.08), Offset = tilt * CF(0, 0.4, 0) * CYL_Y, Color = "Dark" },
		{ Attach = "Head", Shape = "Ball", Size = V(0.26, 0.26, 0.26), Offset = tilt * CF(0, 0.84, 0), Color = "Glow" },
	}
end

-- Gebogene Hörner: dunkler Ansatz, glühende Spitze
do
	local list = {}
	for _, side in SIDES do
		local s = side.Sign
		local base = CF(s * 0.4, 0.5, 0) * ANG(rad(18), 0, rad(-s * 28))
		table.insert(list, { Attach = "Head", Shape = "Ellipsoid", Size = V(0.34, 0.8, 0.34), Offset = base * CF(0, 0.3, 0), Color = "Dark" })
		spike(list, "Head", base * CF(0, 0.55, 0) * ANG(rad(-35), 0, 0), 0.2, 0.5, 0.26, "Glow")
	end
	A.Horns = list
end

-- Krone: Reif, sechs Zacken (Rauten), drei Edelsteine
do
	local list = {
		{ Attach = "Head", Shape = "Cylinder", Size = V(0.28, 1.26, 1.26), Offset = CF(0, 0.5, 0) * CYL_Y, Color = "Primary" },
	}
	for i = 0, 5 do
		table.insert(list, {
			Attach = "Head",
			Shape = "Block",
			Size = V(0.3, 0.3, 0.07),
			Offset = ANG(0, rad(i * 60), 0) * CF(0, 0.64, -0.62) * ANG(0, 0, rad(45)),
			Color = "Primary",
		})
	end
	table.insert(list, { Attach = "Head", Shape = "Ball", Size = V(0.2, 0.2, 0.2), Offset = CF(0, 0.5, -0.64), Color = rgb(235, 30, 80), Material = NEON })
	table.insert(list, { Attach = "Head", Shape = "Ball", Size = V(0.17, 0.17, 0.17), Offset = CF(-0.64, 0.5, 0), Color = "Visor" })
	table.insert(list, { Attach = "Head", Shape = "Ball", Size = V(0.17, 0.17, 0.17), Offset = CF(0.64, 0.5, 0), Color = "Visor" })
	A.Crown = list
end

-- Schwebender Heiligenschein, leicht nach hinten gekippt
do
	local list = {}
	ring(list, "Head", CF(0, 1.0, 0.08) * ANG(rad(16), 0, 0), 0.52, 10, 0.1, 0.07, "Glow", 0.05)
	A.Halo = list
end

-- Planetenring um den Kopf mit zwei Monden
do
	local list = {}
	local center = CF(0, HELMET_Y, 0) * ANG(rad(22), 0, rad(-18))
	ring(list, "Head", center, 0.98, 12, 0.12, 0.05, "Glow", 0.1)
	table.insert(list, { Attach = "Head", Shape = "Ball", Size = V(0.2, 0.2, 0.2), Offset = center * ANG(0, rad(40), 0) * CF(0.98, 0, 0), Color = WHITE, Material = NEON })
	table.insert(list, { Attach = "Head", Shape = "Ball", Size = V(0.16, 0.16, 0.16), Offset = center * ANG(0, rad(220), 0) * CF(0.98, 0, 0), Color = "Visor" })
	A.OrbitRing = list
end

-- Tropenhelm-Krempe mit Hutband (Kuppel = Helm in Kopffarbe)
A.SafariBrim = {
	{ Attach = "Head", Shape = "Ellipsoid", Size = V(1.96, 0.12, 1.96), Offset = CF(0, 0.36, 0.02), Color = "Head", Shadow = true },
	{ Attach = "Head", Shape = "Cylinder", Size = V(0.14, 1.18, 1.18), Offset = CF(0, 0.49, 0.02) * CYL_Y, Color = "Dark" },
}

-- Blätter im Hutband
do
	local list = {}
	for _, side in SIDES do
		local s = side.Sign
		table.insert(list, { Attach = "Head", Shape = "Ellipsoid", Size = V(0.1, 0.55, 0.28), Offset = CF(s * 0.56, 0.58, 0.1) * ANG(rad(-15), 0, rad(-s * 40)), Color = "Accent" })
		table.insert(list, { Attach = "Head", Shape = "Ellipsoid", Size = V(0.1, 0.45, 0.24), Offset = CF(s * 0.58, 0.52, -0.12) * ANG(rad(20), 0, rad(-s * 62)), Color = "Primary" })
	end
	table.insert(list, { Attach = "Head", Shape = "Ellipsoid", Size = V(0.1, 0.5, 0.26), Offset = CF(0.1, 0.62, 0.5) * ANG(rad(50), 0, 0), Color = "Accent" })
	A.Leaves = list
end

-- Propellermütze mit Schirm
do
	local hub = CF(0, 1.04, 0.06) * ANG(0, rad(25), 0)
	A.PropellerCap = {
		{ Attach = "Head", Shape = "Ellipsoid", Size = V(1.44, 1.0, 1.44), Offset = CF(0, 0.34, 0.06), Color = "Primary", Shadow = true },
		{ Attach = "Head", Shape = "Ellipsoid", Size = V(0.95, 0.1, 0.8), Offset = CF(0, 0.36, -0.66), Color = "Secondary" },
		{ Attach = "Head", Shape = "Cylinder", Size = V(0.24, 0.07, 0.07), Offset = CF(0, 0.92, 0.06) * CYL_Y, Color = "Dark" },
		{ Attach = "Head", Shape = "Block", Size = V(0.62, 0.04, 0.18), Offset = hub * CF(0.31, 0, 0), Color = "Accent" },
		{ Attach = "Head", Shape = "Block", Size = V(0.62, 0.04, 0.18), Offset = hub * CF(-0.31, 0, 0), Color = "Secondary" },
		{ Attach = "Head", Shape = "Ball", Size = V(0.14, 0.14, 0.14), Offset = CF(0, 1.06, 0.06), Color = "Accent" },
	}
end

-- Stirnband mit Knoten und zwei flatternden Bändern
A.Headband = {
	{ Attach = "Head", Shape = "Cylinder", Size = V(0.18, 1.36, 1.36), Offset = CF(0, 0.34, 0) * CYL_Y, Color = "Accent" },
	{ Attach = "Head", Shape = "Ball", Size = V(0.22, 0.22, 0.22), Offset = CF(0, 0.34, 0.68), Color = "Accent" },
	{ Attach = "Head", Shape = "Block", Size = V(0.05, 0.2, 0.95), Offset = CF(0.06, 0.32, 0.7) * ANG(rad(18), rad(6), 0) * CF(0, 0, 0.47), Color = "Accent" },
	{ Attach = "Head", Shape = "Block", Size = V(0.05, 0.17, 0.75), Offset = CF(-0.06, 0.3, 0.7) * ANG(rad(34), rad(-8), 0) * CF(0, 0, 0.37), Color = "Accent" },
}

-- Eiskristalle auf Schultern und Kopf
do
	local list = {}
	for _, side in SIDES do
		local s = side.Sign
		local attach = side.Name .. "UpperArm"
		spike(list, attach, CF(s * 0.12, 0.5, -0.05) * ANG(rad(-12), 0, rad(-s * 28)), 0.16, 0.8, 0.38, "Visor", GLASS, 0.1)
		spike(list, attach, CF(s * 0.06, 0.45, 0.22) * ANG(rad(30), 0, rad(-s * 16)), 0.14, 0.58, 0.3, "Glow")
	end
	local heights = { 0.55, 0.72, 0.58 }
	for i, angle in { -20, 15, 50 } do
		spike(list, "Head", onHelmet(angle, 0.58, 8), 0.14, heights[i], 0.34, "Glow")
	end
	A.IceSpikes = list
end

-- Schultern ------------------------------------------------------------

-- Runde Schulterpanzer mit Leuchtkante
do
	local list = {}
	for _, side in SIDES do
		local s = side.Sign
		local attach = side.Name .. "UpperArm"
		table.insert(list, { Attach = attach, Shape = "Ellipsoid", Size = V(1.02, 0.6, 1.0), Offset = CF(s * 0.06, 0.44, 0) * ANG(0, 0, rad(-s * 14)), Color = "Trim", Shadow = true })
		table.insert(list, { Attach = attach, Shape = "Ellipsoid", Size = V(1.08, 0.24, 1.06), Offset = CF(s * 0.08, 0.3, 0) * ANG(0, 0, rad(-s * 14)), Color = "Glow" })
	end
	A.Pauldrons = list
end

-- Geschichtete Panzerplatten (Ninja)
do
	local list = {}
	for _, side in SIDES do
		local s = side.Sign
		local attach = side.Name .. "UpperArm"
		table.insert(list, { Attach = attach, Shape = "Block", Size = V(0.95, 0.14, 0.92), Offset = CF(s * 0.14, 0.62, 0) * ANG(0, 0, rad(-s * 22)), Color = "Secondary" })
		table.insert(list, { Attach = attach, Shape = "Block", Size = V(0.8, 0.13, 0.86), Offset = CF(s * 0.32, 0.42, 0) * ANG(0, 0, rad(-s * 40)), Color = "Secondary" })
	end
	A.ShoulderPlates = list
end

-- Rücken ---------------------------------------------------------------

-- Flacher Neon-Rucksack mit seitlichen Lichtern
A.Backpack = {
	{ Attach = "UpperTorso", Shape = "Block", Size = V(1.16, 1.0, 0.36), Offset = CF(0, 0.02, 0.78), Color = "Secondary", Shadow = true },
	{ Attach = "UpperTorso", Shape = "Cylinder", Size = V(1.16, 0.36, 0.36), Offset = CF(0, 0.52, 0.78), Color = "Secondary" },
	{ Attach = "UpperTorso", Shape = "Block", Size = V(0.08, 0.84, 0.06), Offset = CF(-0.32, 0.02, 0.97), Color = "Glow" },
	{ Attach = "UpperTorso", Shape = "Block", Size = V(0.08, 0.84, 0.06), Offset = CF(0.32, 0.02, 0.97), Color = "Glow" },
	{ Attach = "UpperTorso", Shape = "Cylinder", Size = V(1.2, 0.22, 0.22), Offset = CF(0, 0.12, 0.78), Color = "Visor" },
}

-- Jetpack: Gehäuse, zwei Tanks mit Kuppeln, Düsen und Flammen
do
	local list = {
		{ Attach = "UpperTorso", Shape = "Block", Size = V(0.9, 0.95, 0.4), Offset = CF(0, 0.05, 0.78), Color = "Secondary", Shadow = true },
	}
	for _, side in SIDES do
		local x = side.Sign * 0.38
		table.insert(list, { Attach = "UpperTorso", Shape = "Cylinder", Size = V(1.05, 0.44, 0.44), Offset = CF(x, 0, 0.98) * CYL_Y, Color = "Trim", Shadow = true })
		table.insert(list, { Attach = "UpperTorso", Shape = "Ball", Size = V(0.44, 0.44, 0.44), Offset = CF(x, 0.52, 0.98), Color = "Trim" })
		table.insert(list, { Attach = "UpperTorso", Shape = "Cylinder", Size = V(0.2, 0.34, 0.34), Offset = CF(x, -0.6, 0.98) * CYL_Y, Color = "Dark" })
		table.insert(list, { Attach = "UpperTorso", Shape = "Ellipsoid", Size = V(0.26, 0.6, 0.26), Offset = CF(x, -0.98, 0.98), Color = "Glow", Transparency = 0.15 })
	end
	A.Jetpack = list
end

-- Umhang: Spange über den Schultern, oben ein Keil (im Profil ein Dreieck),
-- unten ein nach hinten wehendes Stück
A.Cape = {
	{ Attach = "UpperTorso", Shape = "Cylinder", Size = V(1.7, 0.26, 0.26), Offset = CF(0, 0.62, 0.56), Color = "Trim" },
	{ Attach = "UpperTorso", Shape = "Wedge", Size = V(1.6, 1.3, 0.44), Offset = CF(0, -0.03, 0.82) * ANG(0, math.pi, 0), Color = "Secondary", Shadow = true },
	{ Attach = "UpperTorso", Shape = "Block", Size = V(1.66, 1.0, 0.44), Offset = CF(0, -0.68, 0.82) * ANG(rad(-28), 0, 0) * CF(0, -0.5, 0), Color = "Secondary", Shadow = true },
}

-- Katana schräg auf dem Rücken, Griff ragt über die rechte Schulter
do
	local k = CF(-0.1, 0, 0.74) * ANG(0, 0, rad(-38))
	A.Katana = {
		{ Attach = "UpperTorso", Shape = "Block", Size = V(0.16, 1.6, 0.24), Offset = k, Color = "Dark", Shadow = true },
		{ Attach = "UpperTorso", Shape = "Block", Size = V(0.32, 0.06, 0.32), Offset = k * CF(0, 0.83, 0), Color = BRASS, Material = METAL },
		{ Attach = "UpperTorso", Shape = "Block", Size = V(0.12, 0.56, 0.15), Offset = k * CF(0, 1.14, 0), Color = "Accent" },
		{ Attach = "UpperTorso", Shape = "Ball", Size = V(0.17, 0.17, 0.17), Offset = k * CF(0, 1.46, 0), Color = BRASS, Material = METAL },
	}
end

-- Flammenflossen und Sonnenkern auf dem Rücken
do
	local list = {}
	spike(list, "UpperTorso", CF(0, 0.3, 0.56) * ANG(rad(52), 0, 0), 0.14, 1.05, 0.5, "Glow")
	spike(list, "UpperTorso", CF(-0.34, 0.15, 0.56) * ANG(rad(62), 0, rad(14)), 0.12, 0.8, 0.42, rgb(255, 110, 20), NEON)
	spike(list, "UpperTorso", CF(0.34, 0.15, 0.56) * ANG(rad(62), 0, rad(-14)), 0.12, 0.8, 0.42, rgb(255, 110, 20), NEON)
	table.insert(list, { Attach = "UpperTorso", Shape = "Ellipsoid", Size = V(0.62, 0.62, 0.22), Offset = CF(0, 0.12, 0.68), Color = "Glow" })
	A.FlameFins = list
end

-- Geisterflügel aus drei leuchtenden Federn je Seite
do
	local list = {}
	local feathers = { { Angle = 40, Length = 1.4 }, { Angle = 64, Length = 1.15 }, { Angle = 88, Length = 0.9 } }
	for _, side in SIDES do
		local s = side.Sign
		for k, feather in feathers do
			local base = CF(s * 0.32, 0.4 - k * 0.08, 0.56) * ANG(rad(feather.Angle), 0, rad(-s * 14))
			table.insert(list, {
				Attach = "UpperTorso",
				Shape = "Ellipsoid",
				Size = V(0.08, feather.Length, 0.34),
				Offset = base * CF(0, feather.Length / 2, 0),
				Color = "Glow",
				Transparency = 0.3,
			})
		end
	end
	A.SpectralWings = list
end

-- Hals und Oberkörper --------------------------------------------------

-- Schal mit Knoten und zwei wehenden Enden
A.Scarf = {
	{ Attach = "UpperTorso", Shape = "Cylinder", Size = V(0.32, 1.24, 1.24), Offset = CF(0, 0.7, 0) * CYL_Y, Color = "Accent" },
	{ Attach = "UpperTorso", Shape = "Ball", Size = V(0.34, 0.34, 0.34), Offset = CF(0.12, 0.64, 0.6), Color = "Accent" },
	{ Attach = "UpperTorso", Shape = "Block", Size = V(0.06, 0.34, 1.25), Offset = CF(0.14, 0.62, 0.64) * ANG(rad(10), rad(8), 0) * CF(0, 0, 0.62), Color = "Accent" },
	{ Attach = "UpperTorso", Shape = "Block", Size = V(0.06, 0.3, 1.0), Offset = CF(0.06, 0.54, 0.64) * ANG(rad(30), rad(-4), 0) * CF(0, 0, 0.5), Color = "Accent" },
}

-- Umhängeriemen mit Tasche (rechts) und Beutel (links)
A.Satchel = {
	{ Attach = "UpperTorso", Shape = "Block", Size = V(0.2, 1.6, 1.28), Offset = CF(0, 0.05, 0) * ANG(0, 0, rad(38)), Color = "Dark" },
	{ Attach = "LowerTorso", Shape = "Block", Size = V(0.24, 0.48, 0.5), Offset = CF(0.86, -0.08, 0.1), Color = "Trim", Shadow = true },
	{ Attach = "LowerTorso", Shape = "Block", Size = V(0.26, 0.16, 0.52), Offset = CF(0.87, 0.12, 0.1), Color = "Dark" },
	{ Attach = "LowerTorso", Shape = "Block", Size = V(0.2, 0.32, 0.36), Offset = CF(-0.84, 0, 0.05), Color = "Trim" },
}

-- Leuchtende Ringe um Arme/Beine und ein Gürtel aus Licht
do
	local list = {}
	for _, side in SIDES do
		local name = side.Name
		table.insert(list, { Attach = name .. "UpperArm", Shape = "Cylinder", Size = V(0.07, 0.62, 0.62), Offset = CF(0, -0.38, 0) * CYL_Y, Color = "Glow" })
		table.insert(list, { Attach = name .. "LowerArm", Shape = "Cylinder", Size = V(0.07, 0.56, 0.56), Offset = CF(0, 0.15, 0) * CYL_Y, Color = "Glow" })
		table.insert(list, { Attach = name .. "UpperLeg", Shape = "Cylinder", Size = V(0.07, 0.78, 0.78), Offset = CF(0, -0.28, 0) * CYL_Y, Color = "Glow" })
		table.insert(list, { Attach = name .. "LowerLeg", Shape = "Cylinder", Size = V(0.07, 0.68, 0.68), Offset = CF(0, 0.12, 0) * CYL_Y, Color = "Glow" })
	end
	table.insert(list, { Attach = "UpperTorso", Shape = "Block", Size = V(1.54, 0.07, 1.1), Offset = CF(0, -0.56, 0), Color = "Glow" })
	table.insert(list, { Attach = "UpperTorso", Shape = "Block", Size = V(0.07, 0.3, 0.06), Offset = CF(0, -0.41, -0.55), Color = "Glow" })
	A.CircuitLines = list
end

-- Schräge, glühende Magma-Adern
do
	local list = {}
	for _, side in SIDES do
		local s = side.Sign
		local name = side.Name
		table.insert(list, { Attach = name .. "UpperArm", Shape = "Cylinder", Size = V(0.07, 0.66, 0.66), Offset = CF(0, -0.3, 0) * ANG(rad(16), 0, rad(s * 12)) * CYL_Y, Color = "Glow" })
		table.insert(list, { Attach = name .. "UpperLeg", Shape = "Cylinder", Size = V(0.07, 0.84, 0.84), Offset = CF(0, -0.15, 0) * ANG(rad(-14), 0, rad(-s * 10)) * CYL_Y, Color = "Glow" })
		table.insert(list, { Attach = name .. "LowerLeg", Shape = "Cylinder", Size = V(0.07, 0.72, 0.72), Offset = CF(0, 0.12, 0) * ANG(rad(12), 0, rad(s * 14)) * CYL_Y, Color = "Glow" })
	end
	table.insert(list, { Attach = "UpperTorso", Shape = "Block", Size = V(0.08, 0.7, 0.06), Offset = CF(-0.3, -0.35, -0.55) * ANG(0, 0, rad(25)), Color = "Glow" })
	table.insert(list, { Attach = "UpperTorso", Shape = "Block", Size = V(0.08, 0.5, 0.06), Offset = CF(0.32, -0.4, -0.55) * ANG(0, 0, rad(-30)), Color = "Glow" })
	table.insert(list, { Attach = "UpperTorso", Shape = "Block", Size = V(1.54, 0.07, 1.1), Offset = CF(0, -0.6, 0) * ANG(0, 0, rad(6)), Color = "Glow" })
	A.MagmaVeins = list
end

-- Sternenfunkeln auf Brust, Armen, Beinen und Helm
A.Stars = {
	{ Attach = "UpperTorso", Shape = "Ball", Size = V(0.2, 0.2, 0.2), Offset = CF(-0.45, 0.32, -0.6), Color = WHITE, Material = NEON },
	{ Attach = "UpperTorso", Shape = "Ball", Size = V(0.14, 0.14, 0.14), Offset = CF(0.5, -0.3, -0.54), Color = "Glow" },
	{ Attach = "LeftUpperArm", Shape = "Ball", Size = V(0.16, 0.16, 0.16), Offset = CF(-0.29, -0.25, 0.05), Color = WHITE, Material = NEON },
	{ Attach = "RightUpperArm", Shape = "Ball", Size = V(0.16, 0.16, 0.16), Offset = CF(0.29, -0.05, -0.08), Color = "Glow" },
	{ Attach = "LeftLowerLeg", Shape = "Ball", Size = V(0.15, 0.15, 0.15), Offset = CF(-0.32, 0.1, 0), Color = "Glow" },
	{ Attach = "RightUpperLeg", Shape = "Ball", Size = V(0.18, 0.18, 0.18), Offset = CF(0.37, -0.2, 0.05), Color = WHITE, Material = NEON },
	{ Attach = "Head", Shape = "Ball", Size = V(0.12, 0.12, 0.12), Offset = CF(0.5, 0.4, 0.2), Color = WHITE, Material = NEON },
}

-- Arme und Füße ----------------------------------------------------------

A.WristBands = {
	{ Attach = "LeftLowerArm", Shape = "Cylinder", Size = V(0.14, 0.72, 0.72), Offset = CF(0, -0.12, 0) * CYL_Y, Color = "Visor" },
	{ Attach = "RightLowerArm", Shape = "Cylinder", Size = V(0.14, 0.72, 0.72), Offset = CF(0, -0.12, 0) * CYL_Y, Color = "Visor" },
}

-- Fersen-Düsen mit Flammen (zeigen nach hinten, nie unter die Sohle)
do
	local list = {}
	for _, side in SIDES do
		local attach = side.Name .. "Foot"
		table.insert(list, { Attach = attach, Shape = "Cylinder", Size = V(0.26, 0.3, 0.3), Offset = CF(0, 0.08, 0.52) * CYL_Z, Color = "Dark" })
		table.insert(list, { Attach = attach, Shape = "Ellipsoid", Size = V(0.2, 0.2, 0.55), Offset = CF(0, 0.08, 0.86), Color = "Glow", Transparency = 0.15 })
	end
	A.RocketBoots = list
end

CosmeticDefinitions.AccessoryPresets = A

------------------------------------------------------------------------
-- Katalog
------------------------------------------------------------------------

CosmeticDefinitions.Items = {
	Skins = {
		{
			Id = "Rookie", Name = "Rookie", Rarity = "Common", Price = 0, Default = true,
			Description = "Der Standard-Runner. Solide, schnell, bereit.",
			Colors = { Head = rgb(242, 245, 252), Torso = rgb(36, 120, 255), Hips = rgb(28, 36, 62), Arms = rgb(36, 120, 255), Hands = rgb(242, 245, 252), Legs = rgb(34, 46, 82), Feet = rgb(242, 245, 252) },
			Primary = rgb(36, 120, 255), Secondary = rgb(242, 245, 252), Dark = rgb(22, 26, 40), Accent = rgb(0, 214, 255), Visor = rgb(70, 230, 255),
			Sole = rgb(255, 186, 40),
			Accessories = { "Visor", "HeadStripe" },
		},
		{
			Id = "NeonPulse", Name = "Neon Pulse", Rarity = "Rare", Price = 750,
			Description = "Schwarzer Anzug mit pulsierenden Neonakzenten.",
			Colors = { Head = rgb(28, 26, 38), Torso = rgb(24, 22, 32), Hips = rgb(34, 30, 46), Arms = rgb(24, 22, 32), Hands = rgb(255, 70, 200), Legs = rgb(34, 30, 46), Feet = rgb(24, 22, 32) },
			Materials = { Sole = NEON },
			Primary = rgb(24, 22, 32), Secondary = rgb(54, 48, 76), Dark = rgb(12, 10, 18), Accent = rgb(255, 50, 190), Visor = rgb(0, 235, 255),
			Sole = rgb(0, 235, 255),
			Accessories = { "VisorWide", "PunkSpikes", "Backpack", "WristBands" },
		},
		{
			Id = "MagmaCore", Name = "Magma Core", Rarity = "Rare", Price = 900,
			Description = "Vulkangestein mit glühendem Kern.",
			Material = Enum.Material.Basalt, TrimMaterial = Enum.Material.Slate,
			Colors = { Head = rgb(62, 44, 38), Torso = rgb(56, 38, 32), Hips = rgb(40, 29, 26), Arms = rgb(56, 38, 32), Hands = rgb(255, 96, 20), Legs = rgb(40, 29, 26), Feet = rgb(30, 22, 20) },
			Materials = { Hands = NEON, Sole = NEON },
			Primary = rgb(56, 38, 32), Secondary = rgb(84, 56, 44), Dark = rgb(26, 18, 16), Accent = rgb(255, 100, 20), Visor = rgb(255, 170, 40),
			Sole = rgb(255, 100, 20),
			Accessories = { "Visor", "Horns", "MagmaVeins" },
		},
		{
			Id = "Frostbite", Name = "Frostbite", Rarity = "Rare", Price = 900,
			Description = "Eiskalte Panzerung mit Kristallspitzen.",
			Colors = { Head = rgb(236, 246, 255), Torso = rgb(186, 222, 255), Hips = rgb(118, 168, 226), Arms = rgb(186, 222, 255), Hands = rgb(140, 214, 255), Legs = rgb(118, 168, 226), Feet = rgb(66, 104, 168) },
			Materials = { Torso = Enum.Material.Ice, Arms = Enum.Material.Ice, Accent = FABRIC },
			Primary = rgb(186, 222, 255), Secondary = rgb(236, 246, 255), Dark = rgb(56, 86, 140), Accent = rgb(110, 220, 255), Visor = rgb(150, 245, 255),
			Accessories = { "VisorWide", "IceSpikes", "Scarf" },
		},
		{
			Id = "JungleScout", Name = "Jungle Scout", Rarity = "Common", Price = 400,
			Description = "Getarnt zwischen Lianen und Blättern.",
			Colors = { Head = rgb(214, 190, 140), Torso = rgb(74, 126, 60), Hips = rgb(104, 82, 56), Arms = rgb(74, 126, 60), Hands = rgb(150, 104, 60), Legs = rgb(104, 82, 56), Feet = rgb(86, 60, 38) },
			Materials = { Torso = FABRIC, Arms = FABRIC, Hips = FABRIC, Legs = FABRIC },
			Primary = rgb(74, 126, 60), Secondary = rgb(214, 190, 140), Dark = rgb(52, 40, 28), Accent = rgb(130, 210, 70), Visor = rgb(255, 214, 90),
			HideBase = { "Stripes" },
			Accessories = { "Visor", "SafariBrim", "Leaves", "Satchel" },
		},
		{
			Id = "SkyPilot", Name = "Sky Pilot", Rarity = "Common", Price = 500,
			Description = "Fliegerjacke, Schutzbrille und ein flatternder Schal.",
			Colors = { Head = rgb(112, 72, 44), Torso = rgb(130, 84, 50), Hips = rgb(72, 64, 56), Arms = rgb(130, 84, 50), Hands = rgb(58, 44, 34), Legs = rgb(72, 64, 56), Feet = rgb(46, 36, 28) },
			Materials = { Head = FABRIC, Torso = FABRIC, Arms = FABRIC, Accent = FABRIC, Trim = FABRIC, Collar = FABRIC },
			Primary = rgb(130, 84, 50), Secondary = rgb(232, 220, 196), Dark = rgb(40, 32, 26), Accent = rgb(225, 45, 45), Visor = rgb(120, 200, 255),
			Collar = rgb(232, 220, 196), Ears = rgb(92, 58, 36),
			HideBase = { "Stripes" },
			Accessories = { "Goggles", "Scarf" },
		},
		{
			Id = "ShadowOps", Name = "Shadow Ops", Rarity = "Epic", Price = 1800,
			Description = "Lautlos. Schwarz. Mit rotem Visier.",
			Material = FABRIC, TrimMaterial = METAL,
			Colors = { Head = rgb(26, 26, 32), Torso = rgb(20, 20, 26), Hips = rgb(30, 30, 36), Arms = rgb(20, 20, 26), Hands = rgb(36, 36, 44), Legs = rgb(30, 30, 36), Feet = rgb(14, 14, 18) },
			Materials = { Accent = FABRIC },
			Primary = rgb(20, 20, 26), Secondary = rgb(50, 50, 60), Dark = rgb(10, 10, 12), Accent = rgb(255, 36, 48), Visor = rgb(255, 36, 48),
			Accessories = { "VisorSlit", "Headband", "Katana", "ShoulderPlates" },
		},
		{
			Id = "RoyalGold", Name = "Royal Gold", Rarity = "Legendary", Price = 5000,
			Description = "Für Champions. Goldene Rüstung, Krone und Königsumhang.",
			Material = FOIL, TrimMaterial = FOIL,
			Colors = { Head = rgb(255, 206, 70), Torso = rgb(255, 192, 46), Hips = rgb(104, 36, 140), Arms = rgb(255, 192, 46), Hands = rgb(104, 36, 140), Legs = rgb(104, 36, 140), Feet = rgb(255, 192, 46) },
			Materials = { Hips = FABRIC, Legs = FABRIC, Hands = FABRIC, Secondary = FABRIC },
			Primary = rgb(255, 192, 46), Secondary = rgb(110, 40, 150), Dark = rgb(64, 22, 86), Accent = rgb(255, 214, 80), Visor = rgb(190, 100, 255),
			Trim = rgb(255, 232, 150),
			Accessories = { "Visor", "Crown", "Pauldrons", "Cape" },
		},
		{
			Id = "CircuitBreaker", Name = "Circuit Breaker", Rarity = "Epic", Price = 2200,
			Description = "Leiterbahnen voller Energie.",
			Colors = { Head = rgb(22, 32, 66), Torso = rgb(16, 26, 58), Hips = rgb(22, 36, 74), Arms = rgb(16, 26, 58), Hands = rgb(30, 46, 94), Legs = rgb(22, 36, 74), Feet = rgb(12, 18, 42) },
			Primary = rgb(16, 26, 58), Secondary = rgb(34, 56, 110), Dark = rgb(8, 12, 28), Accent = rgb(60, 255, 130), Visor = rgb(60, 255, 130),
			Accessories = { "VisorWide", "CircuitLines", "Antenna" },
		},
		{
			Id = "RetroArcade", Name = "Retro Arcade", Rarity = "Rare", Price = 1200,
			Description = "Knallige Primärfarben und eine Propellermütze direkt aus dem Spielautomaten.",
			Colors = { Head = rgb(250, 250, 250), Torso = rgb(232, 40, 52), Hips = rgb(36, 88, 232), Arms = rgb(255, 214, 50), Hands = rgb(255, 255, 255), Legs = rgb(36, 88, 232), Feet = rgb(255, 255, 255) },
			Materials = { Visor = GLASS },
			Primary = rgb(232, 40, 52), Secondary = rgb(36, 88, 232), Dark = rgb(30, 30, 36), Accent = rgb(255, 214, 50), Visor = rgb(36, 36, 44),
			Trim = rgb(255, 214, 50), Sole = rgb(232, 40, 52),
			Accessories = { "Visor", "PropellerCap" },
		},
		{
			Id = "ChromePhantom", Name = "Chrome Phantom", Rarity = "Legendary", Price = 6000,
			Description = "Spiegelnder Chrom, Geisterflügel und ein leuchtender Heiligenschein.",
			Material = METAL, TrimMaterial = METAL, Reflectance = 0.15,
			Colors = { Head = rgb(216, 222, 232), Torso = rgb(196, 202, 214), Hips = rgb(150, 156, 170), Arms = rgb(196, 202, 214), Hands = rgb(150, 156, 170), Legs = rgb(150, 156, 170), Feet = rgb(110, 116, 130) },
			Primary = rgb(196, 202, 214), Secondary = rgb(140, 146, 160), Dark = rgb(70, 76, 90), Accent = rgb(235, 250, 255), Visor = rgb(110, 230, 255),
			Trim = rgb(240, 244, 250),
			Accessories = { "VisorWide", "Halo", "Pauldrons", "SpectralWings" },
		},
		{
			Id = "SolarFlare", Name = "Solar Flare", Rarity = "Epic", Price = 2000,
			Description = "Heiß wie eine Sonneneruption – mit Flammenkamm und Raketenstiefeln.",
			Colors = { Head = rgb(255, 200, 70), Torso = rgb(255, 118, 28), Hips = rgb(200, 56, 20), Arms = rgb(255, 118, 28), Hands = rgb(255, 226, 110), Legs = rgb(200, 56, 20), Feet = rgb(110, 28, 10) },
			Primary = rgb(255, 118, 28), Secondary = rgb(255, 200, 70), Dark = rgb(100, 26, 10), Accent = rgb(255, 232, 60), Visor = rgb(255, 250, 190),
			Accessories = { "VisorWide", "FlameCrest", "FlameFins", "RocketBoots" },
		},
		{
			Id = "GalaxyDrift", Name = "Galaxy Drift", Rarity = "Legendary", Price = 7500, LevelRequired = 20,
			Description = "Ein Anzug aus Sternenstaub mit Planetenring und Jetpack. Ab Level 20.",
			TrimMaterial = METAL,
			Colors = { Head = rgb(40, 22, 88), Torso = rgb(30, 16, 72), Hips = rgb(20, 20, 62), Arms = rgb(30, 16, 72), Hands = rgb(124, 66, 226), Legs = rgb(20, 20, 62), Feet = rgb(12, 10, 32) },
			Primary = rgb(30, 16, 72), Secondary = rgb(64, 34, 128), Dark = rgb(10, 8, 30), Accent = rgb(176, 116, 255), Visor = rgb(255, 120, 230),
			Trim = rgb(196, 200, 228),
			Accessories = { "VisorWide", "Stars", "OrbitRing", "Jetpack" },
		},
	},
	-- Trails: Farbverlauf ColorA → (ColorMid) → ColorB, Width = Breite am Körper,
	-- WidthEnd = Breite am Ende, Core = optionaler heller Kernstreifen.
	Trails = {
		{
			Id = "SpeedLines", Name = "Speed Lines", Rarity = "Common", Price = 300,
			Description = "Saubere weiße Speedlines.",
			ColorA = rgb(255, 255, 255), ColorB = rgb(170, 215, 255),
			Lifetime = 0.38, Width = 1.0, WidthEnd = 0.15, LightEmission = 0.5, Transparency = 0.3,
		},
		{
			Id = "NeonStream", Name = "Neon Stream", Rarity = "Rare", Price = 800,
			Description = "Ein leuchtender Neonstrom.",
			ColorA = rgb(0, 235, 255), ColorMid = rgb(130, 110, 255), ColorB = rgb(255, 60, 200),
			Lifetime = 0.55, Width = 1.2, WidthEnd = 0.2, LightEmission = 1, Core = rgb(225, 255, 255),
		},
		{
			Id = "EmberTrail", Name = "Ember Trail", Rarity = "Rare", Price = 900,
			Description = "Glühende Glut hinter dir.",
			ColorA = rgb(255, 225, 90), ColorMid = rgb(255, 130, 30), ColorB = rgb(220, 30, 10),
			Lifetime = 0.5, Width = 1.1, WidthEnd = 0.1, LightEmission = 1, Core = rgb(255, 245, 200),
		},
		{
			Id = "FrostWake", Name = "Frost Wake", Rarity = "Rare", Price = 900,
			Description = "Eisiger Hauch.",
			ColorA = rgb(240, 252, 255), ColorMid = rgb(150, 225, 255), ColorB = rgb(70, 160, 255),
			Lifetime = 0.55, Width = 1.1, WidthEnd = 0.25, LightEmission = 0.8, Core = rgb(255, 255, 255),
		},
		{
			Id = "ShadowWake", Name = "Shadow Wake", Rarity = "Epic", Price = 1600,
			Description = "Ein Schatten, der dir folgt.",
			ColorA = rgb(120, 30, 170), ColorMid = rgb(50, 10, 80), ColorB = rgb(0, 0, 0),
			Lifetime = 0.65, Width = 1.35, WidthEnd = 0.4, LightEmission = 0, Transparency = 0.1, Core = rgb(200, 80, 255),
		},
		{
			Id = "RainbowRush", Name = "Rainbow Rush", Rarity = "Legendary", Price = 4000,
			Description = "Alle Farben. Volle Geschwindigkeit.",
			Rainbow = true, Lifetime = 0.65, Width = 1.25, WidthEnd = 0.2, LightEmission = 0.85, Core = rgb(255, 255, 255),
		},
	},
	-- Effekte: Color → Color2 Farbverlauf über die Lebenszeit, Rise = Auftrieb,
	-- Spin = Drehgeschwindigkeit (Grad/s), Twinkle = Funkeln (Größe pulsiert).
	Effects = {
		{
			Id = "Sparkles", Name = "Sparkles", Rarity = "Common", Price = 400,
			Description = "Funkelnde Partikel.",
			Color = rgb(255, 250, 200), Color2 = rgb(255, 205, 80),
			Rate = 10, Size = 0.4, Speed = 1.5, Lifetime = 1.0, LightEmission = 1, Spin = 120, Twinkle = true,
		},
		{
			Id = "Embers", Name = "Embers", Rarity = "Rare", Price = 900,
			Description = "Aufsteigende Glut.",
			Color = rgb(255, 170, 50), Color2 = rgb(230, 40, 10),
			Rate = 14, Size = 0.3, Speed = 2.5, Lifetime = 1.2, LightEmission = 1, Rise = 5, Drag = 1,
		},
		{
			Id = "Snowfall", Name = "Snowfall", Rarity = "Rare", Price = 900,
			Description = "Leise rieselnder Schnee.",
			Color = rgb(245, 252, 255), Color2 = rgb(170, 220, 255),
			Rate = 12, Size = 0.32, Speed = 1, Lifetime = 1.4, LightEmission = 0.4, Rise = -2.5, Spin = 60,
		},
		{
			Id = "Electric", Name = "Electric", Rarity = "Epic", Price = 1800,
			Description = "Knisternde Energie.",
			Color = rgb(255, 255, 255), Color2 = rgb(90, 190, 255),
			Rate = 24, Size = 0.26, Speed = 7, Lifetime = 0.35, LightEmission = 1, Drag = 6,
		},
		{
			Id = "Stardust", Name = "Stardust", Rarity = "Legendary", Price = 3500,
			Description = "Kosmischer Sternenstaub.",
			Color = rgb(200, 140, 255),
			Rate = 16, Size = 0.45, Speed = 1.8, Lifetime = 1.3, LightEmission = 1, Rainbow = true, Spin = 90, Twinkle = true,
		},
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
