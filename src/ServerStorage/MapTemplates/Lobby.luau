--[[
	Lobby  (ModuleScript)
	Pfad: ServerStorage/MapTemplates/Lobby

	"Velocity Hub" – die Lobby ist wie die Strecken eine 2.5D-Bühne. Spieler können
	sich während der Wartezeit bewegen, den Greifhaken ausprobieren und Portale nutzen.
	Portale lösen Aktionen aus (Quick Play, Ranked, Training), wenn man darin stehen
	bleibt. Dieselben Aktionen gibt es im Lobby-Menü.

	Aufbau (lokales x; Spielebene z = 0, Boden y = 0):
		-172 … -160  Endwand links (dahinter ein Torturm)
		-160 …  -36  Portal-Halle: Quick Play (-130), Ranked (-95), Training (-60);
		             Boost-Pad (-40 … -24) am Übergang zum Startplatz
		 -36 …   36  Startplatz: 8 Spawnpunkte (x -12 … 12.5), Brunnen, Anzeigetafel,
		             Siegerpodest mit Pokal
		  36 …  170  Spielplatz: Sprungpad, schwebende Plattformen (y 8 / 15 / 22),
		             2 Greifhaken-Anker, Wall-Jump-Schacht zwischen Wand (120–122) und
		             Block (136–140), Gipfel auf y = 48
		 170 …  182  Endwand rechts (dahinter ein Torturm)

	Optik (rein dekorativ – keine Kollision, keine Abfragen, alles über B:Deco):
		- Spielebene: Bodenbeläge je Bereich, Namensschild "VELOCITY HUB" (unter den
		  Spawns, zwischen den Rippen von Decorate) und Fensterreihe auf der
		  Bodenvorderseite, Leuchtfelder unter den Portalen, Zierleisten an Endwänden,
		  Kletterwand und Block
		- Terrasse hinter der Spur in zwei Stufen (z -5 … -15 auf y = 0, z -15 … -24
		  auf y = 3) mit Brunnen, Podest, Anzeigetafel, Bänken, Pflanzkübeln, Palmen,
		  Laternen, Wimpelkette und Glasgeländer
		- Grünstreifen aus Terrain (z -25 … -35) mit Hügeln und Bäumen, Wolken
		- Decorate(): automatische Bodenverzierung (Lippe, Leuchtkante, Rippen, Stützen)
		  und Hintergrund "Hub" (Türme, Bucht, Holo-Ringe, Lichtsäulen); Requisiten
		  setzt diese Vorlage selbst (B.AutoProps = false)
	Vor z = +5 liegen nur flache Blenden auf Vorderseiten unterhalb der Oberkanten.
]]

local M = Enum.Material
local NEON = M.Neon
local BALL = Enum.PartType.Ball
local CYL = Enum.PartType.Cylinder
local SPHERE = Enum.MeshType.Sphere
local rgb = Color3.fromRGB

local VERTICAL = CFrame.Angles(0, 0, math.rad(90)) -- Zylinderachse (X) senkrecht stellen
local FACING = CFrame.Angles(0, math.rad(90), 0) -- Zylinderachse zur Kamera (Scheibe)
-- Wimpel: Keil mit gerader Oberkante, Spitze nach unten
local PENNANT = CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(math.rad(180), 0, 0)

local FACE_Z = 5 -- Vorderseite der Spur (Config.World.TrackDepth / 2)
local FRONT_Z = FACE_Z + 0.06 -- flache Blenden auf Vorderseiten

-- Terrasse hinter der Spur
local DECK_X1, DECK_X2 = -240, 252
local LOWER_Z = -15 -- Grenze zwischen unterer (y = 0) und oberer Stufe
local BACK_Z = -24 -- Hinterkante mit Geländer
local UPPER_Y = 3 -- Höhe der oberen Stufe

local WHITE = rgb(255, 255, 255)
local GOLD = rgb(255, 200, 40)
local GREEN = rgb(80, 255, 140)
local WARM = rgb(255, 214, 150)
local STEEL = rgb(40, 44, 66)
local STONE = rgb(228, 230, 242)
local WOOD = rgb(156, 112, 76)
local WATER = rgb(90, 196, 255)
local BLOSSOMS = { rgb(255, 120, 170), rgb(255, 222, 80), rgb(255, 255, 255), rgb(190, 120, 255) }

------------------------------------------------------------------------
-- Hilfsfunktionen
------------------------------------------------------------------------

--- Deko-Teil mit Mittelpunkt (x, y, z) und optionaler Drehung.
local function piece(B, size: Vector3, x: number, y: number, z: number, color: Color3, material, extra, rotation: CFrame?)
	local cframe = CFrame.new(B:W(x, y, z))
	if rotation then
		cframe = cframe * rotation
	end
	return B:Deco(size, cframe, color, material, extra)
end

--- Achsparalleler Deko-Quader zwischen zwei Ecken.
local function block(B, x1: number, y1: number, z1: number, x2: number, y2: number, z2: number, color: Color3, material, extra)
	local size = Vector3.new(math.abs(x2 - x1), math.abs(y2 - y1), math.abs(z2 - z1))
	return piece(B, size, (x1 + x2) / 2, (y1 + y2) / 2, (z1 + z2) / 2, color, material, extra)
end

--- Balken von (ax, ay) nach (bx, by) in der Tiefe z (Symbole, Schnüre, Streifen).
local function bar(B, ax: number, ay: number, bx: number, by: number, z: number, thickness: number, color: Color3, material, name: string?)
	local dx, dy = bx - ax, by - ay
	local length = math.sqrt(dx * dx + dy * dy)
	local size = Vector3.new(length + thickness * 0.5, thickness, 0.3)
	return piece(B, size, (ax + bx) / 2, (ay + by) / 2, z, color, material or NEON, { Name = name or "Emblem" }, CFrame.Angles(0, 0, math.atan2(dy, dx)))
end

--- Leichte zufällige Helligkeitsvariation.
local function jitter(B, color: Color3, amount: number): Color3
	local f = 1 + B.Rng:NextNumber(-amount, amount)
	return Color3.new(math.clamp(color.R * f, 0, 1), math.clamp(color.G * f, 0, 1), math.clamp(color.B * f, 0, 1))
end

local function emitter(parent: Instance, props)
	local e = Instance.new("ParticleEmitter")
	for key, value in props do
		e[key] = value
	end
	e.Parent = parent
	return e
end

--- Text auf der Kameraseite (+Z = NormalId.Back) eines Teils.
--- opts: Font, Color, Stroke (Kontur), Gradient (unterer Farbton), Size, Position, PixelsPerStud
local function surfaceText(part: BasePart, text: string, opts)
	opts = opts or {}
	local gui = part:FindFirstChildOfClass("SurfaceGui")
	if not gui then
		gui = Instance.new("SurfaceGui")
		gui.Name = "Label"
		gui.Face = Enum.NormalId.Back
		gui.LightInfluence = 0
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = opts.PixelsPerStud or 30
		gui.Parent = part
	end
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = opts.Size or UDim2.fromScale(1, 1)
	label.Position = opts.Position or UDim2.fromScale(0, 0)
	label.Font = opts.Font or Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = opts.Color or WHITE
	label.Text = text
	if opts.Stroke then
		local stroke = Instance.new("UIStroke")
		stroke.Color = opts.Stroke
		stroke.Thickness = opts.StrokeThickness or 3
		stroke.Parent = label
	end
	if opts.Gradient then
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new(WHITE, opts.Gradient)
		gradient.Rotation = 90
		gradient.Parent = label
	end
	label.Parent = gui
	return label
end

------------------------------------------------------------------------
-- Bausteine der Kulisse
------------------------------------------------------------------------

--- Zweistufige Terrasse hinter der Spur mit Bordstein und Glasgeländer.
local function terrace(B)
	local theme = B.Theme
	local trim = theme.Trim or STONE
	local body = rgb(46, 50, 84)
	-- untere Stufe (Oberkante knapp unter der Spielebene)
	block(B, DECK_X1, -40, LOWER_Z, DECK_X2, -0.4, -5.05, body, M.Concrete, { Name = "Terrace" })
	block(B, DECK_X1, -0.4, LOWER_Z, DECK_X2, -0.04, -5.05, rgb(150, 156, 200), M.Marble, { Name = "TerraceFloor" })
	block(B, DECK_X1, -0.04, -5.5, DECK_X2, 0.14, -5.05, trim, M.Metal, { Name = "Curb" })
	-- obere Stufe mit Holzdeck, heller Kante und Leuchtlinie am Absatz
	block(B, DECK_X1, -40, BACK_Z, DECK_X2, UPPER_Y - 0.35, LOWER_Z, body, M.Concrete, { Name = "Terrace" })
	block(B, DECK_X1, UPPER_Y - 0.35, BACK_Z, DECK_X2, UPPER_Y, LOWER_Z, WOOD, M.WoodPlanks, { Name = "TerraceDeck" })
	block(B, DECK_X1, UPPER_Y - 0.45, LOWER_Z - 0.05, DECK_X2, UPPER_Y + 0.08, LOWER_Z + 0.3, trim, M.Metal, { Name = "StepTrim" })
	block(B, DECK_X1, 0.55, LOWER_Z, DECK_X2, 0.75, LOWER_Z + 0.08, theme.Accent2 or theme.Accent, NEON, { Name = "StepGlow", Transparency = 0.15 })
	-- Glasgeländer an der Hinterkante
	local gz = BACK_Z + 0.5
	block(B, DECK_X1, UPPER_Y, gz - 0.1, DECK_X2, UPPER_Y + 2.6, gz + 0.1, rgb(170, 220, 255), M.Glass, { Name = "Railing", Transparency = 0.6 })
	block(B, DECK_X1, UPPER_Y + 2.6, gz - 0.25, DECK_X2, UPPER_Y + 2.95, gz + 0.25, trim, M.Metal, { Name = "RailingTop" })
	block(B, DECK_X1, UPPER_Y + 0.05, gz + 0.1, DECK_X2, UPPER_Y + 0.22, gz + 0.2, theme.Accent, NEON, { Name = "RailingGlow", Transparency = 0.2 })
	for x = DECK_X1 + 6, DECK_X2 - 6, 24 do
		block(B, x - 0.25, UPPER_Y, gz - 0.3, x + 0.25, UPPER_Y + 2.9, gz + 0.3, STEEL, M.Metal, { Name = "RailingPost" })
	end
end

--- Grünstreifen aus Terrain hinter dem Geländer (z -25 … -35) mit Hügeln und Bäumen.
local function greenBelt(B)
	local rng = B.Rng
	local x = -310
	while x < 320 do
		local w = math.min(316, 320 - x)
		B:TerrainBlock(x + w / 2, -18, -30, Vector3.new(w, 40, 10), M.Rock)
		B:TerrainBlock(x + w / 2, 3, -30, Vector3.new(w, 4, 10), M.LeafyGrass)
		x += w
	end
	x = -300
	local palm = false
	while x < 310 do
		local r = rng:NextNumber(5, 7.5)
		local cy = rng:NextNumber(1, 3)
		B:TerrainBall(x, cy, -25 - r, r, M.LeafyGrass)
		local top = cy + r * 0.8
		if palm then
			B:Tree(x + rng:NextNumber(-3, 3), top - 1, -30, { Kind = "Palm", Scale = rng:NextNumber(1.5, 1.9) })
		else
			B:Tree(x + rng:NextNumber(-3, 3), top - 1, -30, { Kind = "Round", Scale = rng:NextNumber(1.5, 2.1) })
		end
		palm = not palm
		x += rng:NextNumber(26, 38)
	end
end

--- Torturm hinter einer Endwand (Glasfassade, Stockwerksbänder, Leuchtkanten, Krone).
local function gateTower(B, x1: number, x2: number, accent: Color3)
	local rng = B.Rng
	local front, back, top = -5.6, -32, 118
	block(B, x1, -40, back, x2, top, front, rgb(58, 62, 102), M.Concrete, { Name = "GateTower" })
	block(B, x1 + 3, -36, front, x2 - 3, top - 8, front + 0.1, rgb(46, 60, 108), M.Glass, { Name = "TowerGlass" })
	for y = -32, top - 8, 12 do
		block(B, x1 + 2, y - 0.5, front, x2 - 2, y + 0.5, front + 0.35, rgb(92, 98, 140), M.Metal, { Name = "TowerBand" })
		if rng:NextNumber() < 0.6 then
			local w = rng:NextNumber(8, 20)
			local wx = rng:NextNumber(x1 + 4 + w / 2, x2 - 4 - w / 2)
			block(B, wx - w / 2, y + 3, front + 0.1, wx + w / 2, y + 9, front + 0.18, WARM, NEON, { Name = "TowerWindow", Transparency = 0.25 })
		end
	end
	for _, ex in { x1 + 1, x2 - 1 } do
		block(B, ex - 0.4, -36, front, ex + 0.4, top, front + 0.3, accent, NEON, { Name = "TowerEdge" })
	end
	-- Krone mit Antenne
	block(B, x1 + 6, top, back + 6, x2 - 6, top + 8, front - 4, rgb(52, 56, 92), M.Metal, { Name = "TowerCrown" })
	block(B, x1 + 6, top + 6.4, front - 4, x2 - 6, top + 7.2, front - 3.8, accent, NEON, { Name = "TowerCrownGlow" })
	local ax, az = (x1 + x2) / 2, (front + back) / 2
	piece(B, Vector3.new(24, 0.6, 0.6), ax, top + 20, az, rgb(200, 204, 220), M.Metal, { Name = "TowerAntenna", Shape = CYL }, VERTICAL)
	piece(B, Vector3.new(1.6, 1.6, 1.6), ax, top + 32.5, az, rgb(255, 60, 80), NEON, { Name = "TowerBeacon", Shape = BALL })
end

--- Vorderseite einer Endwand: helle Kanten, eingelassenes Riffelblech-Paneel mit
--- Leuchtstreifen und Pfeilmarken (flach auf der Wand, unterhalb der Oberkante).
local function wallFace(B, x1: number, x2: number, y1: number, y2: number, accent: Color3)
	local trim = B.Theme.Trim or STONE
	local cx = (x1 + x2) / 2
	for _, ex in { x1 + 0.35, x2 - 0.35 } do
		block(B, ex - 0.35, y1, FACE_Z, ex + 0.35, y2, FRONT_Z + 0.02, trim, M.Metal, { Name = "WallTrim" })
	end
	block(B, x1 + 1.6, y1 + 1.5, FACE_Z, x2 - 1.6, y2 - 2, FRONT_Z, rgb(42, 46, 76), M.DiamondPlate, { Name = "WallPanel" })
	block(B, cx - 0.3, y1 + 3, FACE_Z, cx + 0.3, y2 - 4, FRONT_Z + 0.04, accent, NEON, { Name = "WallGlow" })
	for y = 18, y2 - 12, 22 do
		block(B, x1 + 2.4, y - 1.6, FACE_Z, x2 - 2.4, y + 1.6, FRONT_Z + 0.03, STEEL, M.Metal, { Name = "WallPlate" })
		block(B, x1 + 2.8, y - 0.25, FACE_Z, x2 - 2.8, y + 0.25, FRONT_Z + 0.07, accent, NEON, { Name = "WallMark", Transparency = 0.2 })
	end
end

--- Fensterreihe auf der Vorderseite des Hauptbodens (zwischen den Rippen von Decorate).
--- Fenster, die das Namensschild (Mitte cx, halbe Breite skip) berühren, entfallen.
--- colorAt(x) liefert die Lichtfarbe; jedes dritte Fenster bleibt dunkel.
local function floorWindows(B, x1: number, x2: number, cx: number, skip: number, colorAt)
	local index = 0
	for wx = x1, x2, 12 do
		if math.abs(wx - cx) - 4.3 >= skip then
			index += 1
			block(B, wx - 4.3, -7.7, FACE_Z, wx + 4.3, -2.3, FRONT_Z, STEEL, M.Metal, { Name = "FaceWindowFrame" })
			if index % 3 ~= 0 then
				block(B, wx - 3.8, -7.2, FACE_Z, wx + 3.8, -2.8, FRONT_Z + 0.04, colorAt(wx), NEON, { Name = "FaceWindow", Transparency = 0.5 })
			else
				block(B, wx - 3.8, -7.2, FACE_Z, wx + 3.8, -2.8, FRONT_Z + 0.04, rgb(54, 66, 110), M.Glass, { Name = "FaceWindow" })
			end
			block(B, wx - 3.8, -5.15, FACE_Z, wx + 3.8, -4.85, FRONT_Z + 0.07, STEEL, M.Metal, { Name = "FaceWindowBar" })
			block(B, wx - 0.15, -7.2, FACE_Z, wx + 0.15, -2.8, FRONT_Z + 0.07, STEEL, M.Metal, { Name = "FaceWindowBar" })
		end
	end
end

--- Leuchtendes Namensschild "VELOCITY HUB" auf der Bodenvorderseite (Mitte cx, halbe Breite).
local function namePlate(B, cx: number, half: number)
	local theme = B.Theme
	local accent, accent2 = theme.Accent, theme.Accent2 or theme.Accent
	-- etwas weiter vorn als die Rippen von Decorate (z ≤ 5.14), damit diese verdeckt sind
	block(B, cx - half, -8, FACE_Z, cx + half, -2, FRONT_Z + 0.1, STEEL, M.Metal, { Name = "NamePlateFrame" })
	local plate = block(B, cx - half + 0.5, -7.5, FACE_Z, cx + half - 0.5, -2.5, FRONT_Z + 0.14, rgb(30, 22, 70), NEON, { Name = "NamePlate" })
	surfaceText(plate, "VELOCITY HUB", {
		Font = Enum.Font.LuckiestGuy,
		Size = UDim2.fromScale(0.9, 0.78),
		Position = UDim2.fromScale(0.05, 0.12),
		Stroke = rgb(12, 8, 34),
		StrokeThickness = 4,
		Gradient = accent,
		PixelsPerStud = 24,
	})
	block(B, cx - half + 0.5, -2.62, FACE_Z, cx + half - 0.5, -2.38, FRONT_Z + 0.18, accent, NEON, { Name = "NamePlateGlow" })
	block(B, cx - half + 0.5, -7.62, FACE_Z, cx + half - 0.5, -7.38, FRONT_Z + 0.18, accent2, NEON, { Name = "NamePlateGlow" })
end

--- Pflanzkübel mit Hecke und Blüten (y = Standfläche).
local function planter(B, x: number, y: number, z: number, width: number)
	local rng = B.Rng
	local leaf = B.Theme.Leaf or rgb(70, 170, 110)
	block(B, x - width / 2, y, z - 1.3, x + width / 2, y + 1.3, z + 1.3, STONE, M.Concrete, { Name = "Planter" })
	block(B, x - width / 2 - 0.1, y + 1.2, z - 1.4, x + width / 2 + 0.1, y + 1.5, z + 1.4, STEEL, M.Metal, { Name = "PlanterRim" })
	local n = math.max(2, math.floor(width / 1.8))
	for i = 1, n do
		local bx = x - width / 2 + width * (i - 0.5) / n
		local d = rng:NextNumber(2, 2.6)
		piece(B, Vector3.new(d, d, d), bx, y + 1.5 + d * 0.22, z, jitter(B, leaf, 0.12), M.Grass, { Name = "PlanterBush", Shape = BALL })
		if i % 2 == 1 then
			piece(B, Vector3.new(0.6, 0.6, 0.6), bx + 0.3, y + 2.3 + d * 0.2, z + 0.9, BLOSSOMS[rng:NextInteger(1, #BLOSSOMS)], M.SmoothPlastic, { Name = "Blossom", Shape = BALL })
		end
	end
end

--- Parkbank (Holz, Metallbeine), Lehne hinten.
local function bench(B, x: number, y: number, z: number)
	block(B, x - 1.8, y + 0.85, z - 0.55, x + 1.8, y + 1.1, z + 0.55, WOOD, M.WoodPlanks, { Name = "BenchSeat" })
	block(B, x - 1.8, y + 1.25, z - 0.75, x + 1.8, y + 2.05, z - 0.55, WOOD, M.WoodPlanks, { Name = "BenchBack" })
	for _, side in { -1, 1 } do
		block(B, x + side * 1.5 - 0.12, y, z - 0.7, x + side * 1.5 + 0.12, y + 0.85, z + 0.5, STEEL, M.Metal, { Name = "BenchLeg" })
	end
end

--- Brunnen mit Wasserspiel (Mitte x, z; steht auf y = 0).
local function fountain(B, x: number, z: number)
	local accent = B.Theme.Accent
	piece(B, Vector3.new(1.4, 10, 10), x, 0.7, z, STONE, M.Marble, { Name = "FountainBasin", Shape = CYL }, VERTICAL)
	piece(B, Vector3.new(0.14, 10.3, 10.3), x, 1.05, z, accent, NEON, { Name = "FountainRim", Shape = CYL }, VERTICAL)
	piece(B, Vector3.new(0.2, 9, 9), x, 1.35, z, WATER, M.Glass, {
		Name = "FountainWater",
		Shape = CYL,
		Transparency = 0.25,
		Light = { Range = 14, Brightness = 1.2, Color = WATER },
	}, VERTICAL)
	piece(B, Vector3.new(4, 1.2, 1.2), x, 3.4, z, STONE, M.Marble, { Name = "FountainColumn", Shape = CYL }, VERTICAL)
	piece(B, Vector3.new(0.6, 4.4, 4.4), x, 5.3, z, STONE, M.Marble, { Name = "FountainBowl", Shape = CYL }, VERTICAL)
	piece(B, Vector3.new(0.16, 3.8, 3.8), x, 5.62, z, WATER, M.Glass, { Name = "FountainWater", Shape = CYL, Transparency = 0.2 }, VERTICAL)
	local spout = piece(B, Vector3.new(0.9, 0.9, 0.9), x, 6.1, z, WATER, M.Glass, { Name = "FountainSpout", Shape = BALL, Transparency = 0.15 })
	emitter(spout, {
		Rate = 26,
		Lifetime = NumberRange.new(0.9, 1.3),
		Speed = NumberRange.new(9, 12),
		SpreadAngle = Vector2.new(14, 14),
		Acceleration = Vector3.new(0, -26, 0),
		EmissionDirection = Enum.NormalId.Top,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.15) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 0.9) }),
		Color = ColorSequence.new(WHITE, rgb(150, 220, 255)),
		LightEmission = 0.35,
	})
end

--- Pokal (y = Standfläche, s = Größe).
local function trophy(B, x: number, y: number, z: number, s: number)
	local gold = rgb(255, 196, 46)
	piece(B, Vector3.new(2.6 * s, 0.9 * s, 2.6 * s), x, y + 0.45 * s, z, rgb(36, 38, 58), M.Marble, { Name = "TrophyBase" })
	piece(B, Vector3.new(2.7 * s, 0.14 * s, 0.1), x, y + 0.45 * s, z + 1.32 * s, gold, NEON, { Name = "TrophyPlate" })
	piece(B, Vector3.new(1.4 * s, 0.6 * s, 0.6 * s), x, y + 1.6 * s, z, gold, M.Metal, { Name = "TrophyStem", Shape = CYL }, VERTICAL)
	piece(B, Vector3.new(1 * s, 1 * s, 1 * s), x, y + 2.3 * s, z, gold, M.Metal, { Name = "TrophyKnot", Shape = BALL })
	local cup = piece(B, Vector3.new(3.2 * s, 2.8 * s, 3.2 * s), x, y + 3.7 * s, z, gold, M.Metal, {
		Name = "TrophyCup",
		Mesh = SPHERE,
		Light = { Range = 16, Brightness = 1.4, Color = GOLD },
	})
	cup.Reflectance = 0.2
	piece(B, Vector3.new(1.5 * s, 3.2 * s, 3.2 * s), x, y + 4.75 * s, z, gold, M.Metal, { Name = "TrophyCup", Shape = CYL }, VERTICAL)
	piece(B, Vector3.new(0.3 * s, 3.5 * s, 3.5 * s), x, y + 5.5 * s, z, rgb(255, 226, 120), M.Metal, { Name = "TrophyRim", Shape = CYL }, VERTICAL)
	for _, side in { -1, 1 } do
		local hx = x + side * 1.95 * s
		bar(B, x + side * 1.4 * s, y + 5 * s, hx, y + 5 * s, z, 0.4 * s, gold, M.Metal, "TrophyHandle")
		bar(B, hx, y + 5 * s, hx, y + 3.6 * s, z, 0.4 * s, gold, M.Metal, "TrophyHandle")
		bar(B, hx, y + 3.6 * s, x + side * 1.2 * s, y + 3.3 * s, z, 0.4 * s, gold, M.Metal, "TrophyHandle")
	end
	piece(B, Vector3.new(0.75 * s, 0.75 * s, 0.75 * s), x, y + 3.9 * s, z + 1.45 * s, B.Theme.Accent2 or GOLD, NEON, { Name = "TrophyGem", Shape = BALL })
	emitter(cup, {
		Rate = 5,
		Lifetime = NumberRange.new(1, 1.6),
		Speed = NumberRange.new(0.5, 1.5),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3 * s), NumberSequenceKeypoint.new(1, 0) }),
		Color = ColorSequence.new(rgb(255, 250, 210), GOLD),
		LightEmission = 1,
	})
end

--- Siegerpodest (1 / 2 / 3) mit Pokal auf dem Siegertreppchen.
local function podium(B, x: number, z: number)
	block(B, x - 7.2, 0, z - 2.4, x + 7.2, 0.35, z + 2.4, STEEL, M.Metal, { Name = "PodiumBase" })
	for _, step in { { -4.6, 3, rgb(206, 212, 230), "2" }, { 0, 4.6, GOLD, "1" }, { 4.6, 2, rgb(214, 140, 80), "3" } } do
		local sx, h = x + step[1], step[2]
		local part = block(B, sx - 2.2, 0.35, z - 2, sx + 2.2, h, z + 2, step[3], M.Metal, { Name = "Podium" })
		block(B, sx - 2.25, h - 0.14, z + 1.96, sx + 2.25, h + 0.02, z + 2.06, WHITE, NEON, { Name = "PodiumEdge" })
		surfaceText(part, step[4], { Color = rgb(30, 30, 44), PixelsPerStud = 40 })
	end
	trophy(B, x, 4.6, z, 1.05)
	B:Sign(x, 15, "WERDE CHAMPION!", nil, { Style = "Banner", Width = 17, Height = 3.4, Z = z, Color = GOLD })
end

--- Anzeigetafel mit Spieltitel (auf der oberen Terrassenstufe).
local function titleBoard(B, cx: number, z: number)
	local theme = B.Theme
	local accent, accent2 = theme.Accent, theme.Accent2 or theme.Accent
	local x1, x2, y1, y2 = cx - 25, cx + 25, 14, 31
	for _, side in { -1, 1 } do
		local px = cx + side * 19
		block(B, px - 1, UPPER_Y, z - 1.4, px + 1, y1 - 0.5, z - 0.2, STEEL, M.Metal, { Name = "BoardLeg" })
		block(B, px - 0.15, UPPER_Y + 1, z - 0.2, px + 0.15, y1 - 1.5, z - 0.12, accent, NEON, { Name = "BoardLegGlow" })
	end
	block(B, x1 - 1.2, y1 - 1.2, z - 1.6, x2 + 1.2, y2 + 1.2, z - 0.4, STEEL, M.Metal, { Name = "BoardFrame" })
	-- Bildschirm in drei Tönen (Verlauf), Titel als SurfaceGui
	local h = (y2 - y1) / 3
	block(B, x1, y1 + 2 * h, z - 0.4, x2, y2, z - 0.2, rgb(52, 34, 108), NEON, { Name = "BoardScreen" })
	block(B, x1, y1 + h, z - 0.4, x2, y1 + 2 * h, z - 0.2, rgb(38, 28, 86), NEON, { Name = "BoardScreen" })
	block(B, x1, y1, z - 0.4, x2, y1 + h, z - 0.2, rgb(28, 22, 66), NEON, { Name = "BoardScreen" })
	local face = block(B, x1, y1, z - 0.2, x2, y2, z - 0.16, WHITE, M.SmoothPlastic, {
		Name = "BoardText",
		Transparency = 1,
		Light = { Range = 30, Brightness = 1.2, Color = accent },
	})
	surfaceText(face, "VELOCITY RUSH", {
		Font = Enum.Font.LuckiestGuy,
		Size = UDim2.fromScale(0.92, 0.5),
		Position = UDim2.fromScale(0.04, 0.12),
		Stroke = rgb(14, 10, 40),
		StrokeThickness = 6,
		Gradient = accent,
		PixelsPerStud = 24,
	})
	surfaceText(face, "MULTIPLAYER-SPEEDRACE", {
		Font = Enum.Font.FredokaOne,
		Size = UDim2.fromScale(0.6, 0.16),
		Position = UDim2.fromScale(0.2, 0.68),
		Color = accent2,
		Stroke = rgb(14, 10, 40),
	})
	-- Leuchtrahmen
	block(B, x1 - 0.4, y2, z - 0.25, x2 + 0.4, y2 + 0.4, z - 0.1, accent, NEON, { Name = "BoardGlow" })
	block(B, x1 - 0.4, y1 - 0.4, z - 0.25, x2 + 0.4, y1, z - 0.1, accent2, NEON, { Name = "BoardGlow" })
	for _, ex in { x1 - 0.2, x2 + 0.2 } do
		block(B, ex - 0.2, y1, z - 0.25, ex + 0.2, y2, z - 0.1, accent2, NEON, { Name = "BoardGlow" })
	end
	for _, ex in { x1, x2 } do
		for _, ey in { y1, y2 } do
			block(B, ex - 0.9, ey - 0.9, z - 0.3, ex + 0.9, ey + 0.9, z - 0.05, GOLD, NEON, { Name = "BoardCorner" })
		end
	end
end

--- Wimpelkette zwischen (x1, y) und (x2, y) mit Durchhang `sag`.
local function pennants(B, x1: number, x2: number, y: number, sag: number, z: number)
	local theme = B.Theme
	local colors = { theme.Accent, WHITE, theme.Accent2 or theme.Accent, GOLD }
	local function yAt(t)
		return y - sag * 4 * t * (1 - t)
	end
	local segments = 6
	for i = 0, segments - 1 do
		local ta, tb = i / segments, (i + 1) / segments
		bar(B, x1 + (x2 - x1) * ta, yAt(ta), x1 + (x2 - x1) * tb, yAt(tb), z, 0.12, rgb(230, 230, 240), M.Fabric, "PennantRope")
	end
	local count = math.floor((x2 - x1) / 3.4)
	for i = 1, count do
		local t = (i - 0.5) / count
		piece(B, Vector3.new(0.1, 1.5, 1.4), x1 + (x2 - x1) * t, yAt(t) - 0.8, z, colors[(i - 1) % #colors + 1], M.Fabric, { Name = "Pennant", Wedge = true }, PENNANT)
	end
end

--- Luftballons an Schnüren (x, y = Befestigungspunkt).
local function balloons(B, x: number, y: number, z: number)
	local theme = B.Theme
	local colors = { theme.Accent2 or theme.Accent, GOLD, theme.Accent, rgb(150, 110, 255), WHITE }
	for i, color in colors do
		local bx = x + (i - 3) * 1.25 + B.Rng:NextNumber(-0.3, 0.3)
		local by = y + 6.5 + (i % 2) * 1.3 + B.Rng:NextNumber(-0.3, 0.3)
		piece(B, Vector3.new(1.7, 2.1, 1.7), bx, by, z, color, M.SmoothPlastic, { Name = "Balloon", Mesh = SPHERE })
		bar(B, x, y, bx, by - 1, z, 0.06, WHITE, M.SmoothPlastic, "BalloonString")
	end
end

------------------------------------------------------------------------
-- Portale
------------------------------------------------------------------------

--- Symbol "Blitz" (Quick Play).
local function emblemBolt(B, x: number, y: number, z: number, color: Color3)
	bar(B, x + 1, y + 2.5, x - 0.6, y, z, 0.85, color)
	bar(B, x - 0.6, y, x + 0.6, y, z, 0.85, color)
	bar(B, x + 0.6, y, x - 1, y - 2.5, z, 0.85, color)
end

--- Symbol "Krone" (Ranked).
local function emblemCrown(B, x: number, y: number, z: number, color: Color3)
	local points = { { -2.1, -1.4 }, { -2.1, 1.5 }, { -1, 0.1 }, { 0, 2 }, { 1, 0.1 }, { 2.1, 1.5 }, { 2.1, -1.4 } }
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		bar(B, x + a[1], y + a[2], x + b[1], y + b[2], z, 0.6, color)
	end
	bar(B, x - 2.1, y - 1.4, x + 2.1, y - 1.4, z, 0.9, color)
	for _, tip in { points[2], points[4], points[6] } do
		piece(B, Vector3.new(0.85, 0.85, 0.85), x + tip[1], y + tip[2] + 0.2, z + 0.1, WHITE, NEON, { Name = "Emblem", Shape = BALL })
	end
end

--- Symbol "Zielscheibe" (Training).
local function emblemTarget(B, x: number, y: number, z: number, color: Color3)
	piece(B, Vector3.new(0.1, 5, 5), x, y, z, color, NEON, { Name = "Emblem", Shape = CYL }, FACING)
	piece(B, Vector3.new(0.1, 3.6, 3.6), x, y, z + 0.08, STEEL, M.Metal, { Name = "Emblem", Shape = CYL }, FACING)
	piece(B, Vector3.new(0.1, 2.3, 2.3), x, y, z + 0.16, color, NEON, { Name = "Emblem", Shape = CYL }, FACING)
	piece(B, Vector3.new(0.1, 0.9, 0.9), x, y, z + 0.24, WHITE, NEON, { Name = "Emblem", Shape = CYL }, FACING)
end

--- Portal mit großem Torbogen, Symbol-Medaillon, Leuchtfeld und Fahne.
local function portalGate(B, px: number, action: string, label: string, color: Color3, emblem)
	B:Portal(px, 0, action, label, color)
	B:Arch(px, 0, 19, 20, color, { Z = -8.6, Depth = 2.2, FrameColor = rgb(46, 50, 80) })
	local my, mz = 26.4, -8.4
	block(B, px - 0.7, 22.2, mz - 0.9, px + 0.7, my - 3.2, mz + 0.1, STEEL, M.Metal, { Name = "MedallionStem" })
	piece(B, Vector3.new(0.5, 7.2, 7.2), px, my, mz - 0.3, STEEL, M.Metal, { Name = "Medallion", Shape = CYL }, FACING)
	piece(B, Vector3.new(0.3, 8.2, 8.2), px, my, mz - 0.6, color, NEON, { Name = "MedallionRim", Shape = CYL }, FACING)
	emblem(B, px, my, mz + 0.05, color:Lerp(WHITE, 0.45))
	-- Standfläche: Leuchtfeld auf dem Boden, farbiger Streifen auf der Bodenvorderseite
	block(B, px - 5, 0.01, -4.6, px + 5, 0.07, 4.6, color, NEON, { Name = "PortalPad", Transparency = 0.65 })
	block(B, px - 5, -1.42, FACE_Z, px + 5, -1.02, FRONT_Z + 0.04, color, NEON, { Name = "PortalStrip" })
	B:Banner(px + 12.5, 0, color, { Height = 14, Width = 3.2, Z = -7, Color2 = WHITE })
end

------------------------------------------------------------------------
-- Aufbau
------------------------------------------------------------------------

return function(B)
	local theme = B.Theme
	local accent, accent2 = theme.Accent, theme.Accent2 or theme.Accent
	local wallMaterial = theme.WallMaterial or theme.GroundMaterial
	B.AutoCheckpoints = false
	B.AutoProps = false -- Requisiten werden unten von Hand gesetzt

	-- Boden -160 … 170 in drei Bereichen (gleiche Kollision wie ein durchgehender Boden;
	-- für Decorate ein Lauf: Rippen alle 12 Studs ab x = -154, also bei -10, 2, 14 …)
	B:Ground(-160, -36, 0, { Thickness = 12, TopColor = rgb(92, 98, 150), TopMaterial = M.Marble })
	B:Ground(-36, 36, 0, { Thickness = 12, TopColor = rgb(132, 138, 190), TopMaterial = M.Marble })
	B:Ground(36, 170, 0, { Thickness = 12, TopColor = rgb(70, 92, 140), TopMaterial = M.Pavement })
	B:Box(-172, -12, -160, 95, { Name = "Wall", Color = theme.Wall, Material = wallMaterial })
	B:Box(170, -12, 182, 95, { Name = "Wall", Color = theme.Wall, Material = wallMaterial })

	-- Startplatz
	for i = 0, 7 do
		B:SpawnPoint(-12 + i * 3.5, 0)
	end

	-- Portal-Halle
	portalGate(B, -130, "QuickPlay", "SCHNELLES SPIEL", accent, emblemBolt)
	portalGate(B, -95, "Ranked", "RANKED", GOLD, emblemCrown)
	portalGate(B, -60, "Practice", "TRAINING", GREEN, emblemTarget)
	B:BoostPad(-40, -24, 0, 70)

	-- Parkour-Spielplatz zum Aufwärmen
	B:JumpPad(24, 0, 75)
	B:Ground(34, 52, 8, { Thickness = 2, TopColor = rgb(240, 170, 60), TopMaterial = M.Plastic })
	B:Ground(60, 78, 15, { Thickness = 2, TopColor = rgb(230, 80, 140), TopMaterial = M.Plastic })
	B:Ground(86, 104, 22, { Thickness = 2, TopColor = rgb(40, 180, 230), TopMaterial = M.Plastic })
	B:Anchor(72, 42)
	B:Anchor(112, 46)
	B:Box(120, 9, 122, 60, { Name = "WallJumpWall", Color = theme.Wall, Material = wallMaterial })
	B:Box(136, 0, 140, 48, { Name = "WallJumpBlock", Color = theme.Wall, Material = wallMaterial })
	B:Ground(136, 170, 48, { Thickness = 2, TopColor = rgb(90, 200, 120), TopMaterial = M.Plastic })
	B:Sign(66, 32, "GREIFHAKEN", "E / Maus halten: schwingen · loslassen: abspringen", { Width = 22, Height = 6, Z = -6 })
	B:Sign(108, 34, "WALL-JUMP", "In der Luft gegen die Wand springen", { Width = 18, Height = 6, Z = -6, Color = accent2 })

	------------------------------------------------------------------
	-- Optik (rein dekorativ)
	------------------------------------------------------------------
	terrace(B)
	gateTower(B, -216, -158, accent)
	gateTower(B, 168, 226, accent2)
	wallFace(B, -172, -160, -12, 95, accent)
	wallFace(B, 170, 182, -12, 95, accent2)
	-- Namensschild mittig zwischen den Rippen bei -22 und 26 (deckt -10, 2, 14 ab)
	namePlate(B, 2, 17.6)
	floorWindows(B, -148, 164, 2, 17.6, function(wx)
		if wx < -36 then
			return WARM
		elseif wx < 36 then
			return rgb(150, 230, 255)
		end
		local cycle = { accent2, GOLD, accent }
		return cycle[math.floor((wx - 36) / 12) % #cycle + 1]
	end)

	-- Portal-Halle: zwischen den Torbögen je Laterne, Pflanzkübel, Bank und Palme
	for _, lx in { -145, -112.5, -77.5 } do
		B:Lamp(lx, 0, -6.5)
		planter(B, lx - 4.5, 0, -11, 4)
		B:Tree(lx + 2, UPPER_Y, -19.5, { Kind = "Palm", Scale = 1.5 })
		if lx > -140 then
			bench(B, lx + 4, 0, -11.5)
		end
	end
	B:Arch(-36, 0, 14, 13, accent, { Label = "◀ PORTALE", Z = -7, LabelWidth = 16 })

	-- Startplatz: Brunnen, Anzeigetafel, Podest, Wimpelkette, Palmen
	fountain(B, 0, -10)
	titleBoard(B, 0, -21.4)
	planter(B, -11, UPPER_Y, -17, 7)
	planter(B, 11, UPPER_Y, -17, 7)
	podium(B, -20, -10)
	pennants(B, -29, 31, 13.6, 4, -7.2)
	B:Tree(-31, UPPER_Y, -19.5, { Kind = "Palm", Scale = 1.7 })
	B:Tree(31, UPPER_Y, -19.5, { Kind = "Palm", Scale = 1.7 })
	bench(B, 14, 0, -11.5)
	planter(B, 21, 0, -11, 4)
	B:Arch(38, 0, 14, 13, accent2, { Label = "SPIELPLATZ ▶", Z = -7, LabelWidth = 18 })
	balloons(B, 46.5, 0, -8)

	-- Spielplatz: Klettergerüst, Trampoline, Streifen an Kletterwand und Block, Gipfel
	for _, gx in { 62, 68, 74 } do
		piece(B, Vector3.new(9, 0.6, 0.6), gx, 4.5, -11, accent2, M.Plastic, { Name = "GymPost", Shape = CYL }, VERTICAL)
		piece(B, Vector3.new(0.9, 0.9, 0.9), gx, 9.2, -11, GOLD, M.Plastic, { Name = "GymKnob", Shape = BALL })
	end
	for _, gy in { 3, 6, 9 } do
		piece(B, Vector3.new(12, 0.45, 0.45), 68, gy, -11, accent, M.Plastic, { Name = "GymBar", Shape = CYL })
	end
	for _, tx in { 92, 99.5 } do
		piece(B, Vector3.new(0.5, 5.8, 5.8), tx, 1.2, -11, accent2, M.Plastic, { Name = "TrampolineRim", Shape = CYL }, VERTICAL)
		piece(B, Vector3.new(0.5, 5, 5), tx, 1.3, -11, rgb(30, 32, 44), M.Fabric, { Name = "TrampolineMat", Shape = CYL }, VERTICAL)
		block(B, tx - 2.2, 0, -11.3, tx - 1.8, 1, -10.7, STEEL, M.Metal, { Name = "TrampolineLeg" })
		block(B, tx + 1.8, 0, -11.3, tx + 2.2, 1, -10.7, STEEL, M.Metal, { Name = "TrampolineLeg" })
	end
	B:Lamp(56, 0, -6.5)
	B:Lamp(112, 0, -6.5)
	B:Tree(84, UPPER_Y, -19.5, { Kind = "Palm", Scale = 1.6 })
	B:Tree(128, UPPER_Y, -19.5, { Kind = "Round", Scale = 1.8 })
	planter(B, 106, 0, -11, 5)
	-- Wall-Jump-Wand: Streifen; Block: Klettergriffe; Hohlraum unter dem Gipfel: Wandbild
	for y = 12, 56, 8 do
		block(B, 120.1, y, FACE_Z, 121.9, y + 4, FRONT_Z, accent2, M.SmoothPlastic, { Name = "WallStripe" })
	end
	for i = 0, 11 do
		local hy = 3 + i * 3.7
		local hx = 137 + (i % 3) * 1
		piece(B, Vector3.new(0.12, 0.9, 0.9), hx, hy, FRONT_Z, ({ accent, GOLD, accent2 })[i % 3 + 1], M.Plastic, { Name = "ClimbHold", Shape = CYL }, FACING)
	end
	block(B, 140, 0, -5.6, 170, 46, -5.2, rgb(52, 56, 96), M.Concrete, { Name = "Mural" })
	for i, color in { accent2, GOLD, accent } do
		local ox = 140 + i * 6
		bar(B, ox - 4, 2, ox + 14, 44, -5.15, 2.4, color, M.SmoothPlastic, "MuralStripe")
	end
	B:Banner(162, 48, GOLD, { Height = 11, Width = 3.4, Z = -4.2, Color2 = WHITE })
	trophy(B, 150, 48, -3.6, 0.8)
	B:Sign(150, 58.5, "GIPFEL ERREICHT!", nil, { Style = "Banner", Width = 16, Height = 3.4, Z = -6, Color = GOLD })
	local confetti = block(B, 141, 62, -5, 167, 63, -3, WHITE, nil, { Name = "Confetti", Transparency = 1 })
	emitter(confetti, {
		Rate = 6,
		Lifetime = NumberRange.new(3, 5),
		Speed = NumberRange.new(1, 3),
		EmissionDirection = Enum.NormalId.Bottom,
		Size = NumberSequence.new(0.3),
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, rgb(255, 80, 80)),
			ColorSequenceKeypoint.new(0.25, rgb(255, 220, 60)),
			ColorSequenceKeypoint.new(0.5, rgb(80, 230, 120)),
			ColorSequenceKeypoint.new(0.75, rgb(60, 200, 255)),
			ColorSequenceKeypoint.new(1, rgb(240, 90, 255)),
		}),
		LightEmission = 0.4,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-180, 180),
		Acceleration = Vector3.new(0, -4, 0),
		SpreadAngle = Vector2.new(35, 35),
	})

	-- Schwebende Lichtpunkte über der Terrasse
	local motes = block(B, -150, 18, -16, 160, 19, -8, WHITE, nil, { Name = "Motes", Transparency = 1 })
	emitter(motes, {
		Rate = 5,
		Lifetime = NumberRange.new(6, 9),
		Speed = NumberRange.new(0.3, 1.2),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.3), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(WARM, accent),
		LightEmission = 1,
	})

	B:Decorate()

	-- Hintergrund vor den Hub-Türmen: Grünstreifen und Abendwolken
	greenBelt(B)
	local rng = B.Rng
	for i = 1, 7 do
		B:Cloud(-300 + i * 75 + rng:NextNumber(-15, 15), rng:NextNumber(85, 118), -rng:NextNumber(230, 260), rng:NextNumber(2.2, 3.4), {
			Color = rgb(255, 214, 236),
			Puffs = 4,
		})
	end
end
