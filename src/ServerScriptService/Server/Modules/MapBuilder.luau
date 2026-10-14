--[[
	MapBuilder  (ModuleScript)
	Pfad: ServerScriptService/Server/Modules/MapBuilder

	Erzeugt Rennstrecken vollständig per Script aus Parts. Eine Map-Vorlage
	(ServerStorage/MapTemplates/*) ist eine Funktion, die einen MapBuilder erhält
	und mit "Bausteinen" die Strecke von links nach rechts aufbaut.

	Koordinaten:
		Lokale 2D-Koordinaten (x, y) relativ zum Ursprung der Map.
		x = Rennrichtung (Fortschritt), y = Höhe, z = Tiefe (Spielebene z = 0).
		Der "Cursor" (self.X, self.Y) zeigt immer auf das Ende des aktuellen Bodens.

	Physik-Richtwerte (siehe Config.Movement):
		Sprunghöhe ≈ 9,6 Studs, Sprungweite bei Maximaltempo ≈ 25 Studs.
		Normale Lücken ≤ 18, Stufen ≤ 6, Greifhaken-Lücken 40–80 Studs.

	Wichtige Bausteine (Cursor-basiert):
		Start(len)                 Startbereich mit 8 Spawnpunkten und Startbogen
		Flat(len, opts)            gerader Boden (opts.Ice = true für Eis)
		Gap(width, dy, landing)    Sprunglücke mit Gefahr am Boden
		Steps(count, rise, run)    Treppe (rise negativ = abwärts)
		Drop(height, landing)      Absatz nach unten
		Climb(height, landing)     Absatz nach oben (≤ 8 springbar)
		Ramp(length, rise)         Rampe
		SlideTunnel(len, opts)     niedrige Decke, nur rutschend passierbar
		WallClimb(height, width)   Schacht für Wall-Jumps (+ Hilfsanker)
		JumpPadUp(height, landing) Sprungpad zu höherer Ebene
		GrappleGap(width, opts)    breite Lücke mit Greifhaken-Ankern
		Pit(width, opts)           Gefahrengrube, optional mit Säulen
		TimedBarrier(len, opts)    zeitgesteuerte Gefahrenwand
		BoostStrip(len, power)     Boden mit Boost-Pad
		IceRun(len)                Eisfläche
		PickupRow(count, len)      Item-Boxen
		Split(opts)                zwei Routen (oben schnell/schwer, unten sicher)
		Finish(len)                Ziellinie mit Zielbogen
		Decorate()                 Bodenverzierung + Hintergrund passend zum Theme

	Freie Bausteine: Box, Ground, RampPart, Anchor, Hazard, BoostPad, JumpPad,
	Checkpoint, SpawnPoint, PickupSpot, Sign, Portal.

	Optik (rein dekorativ – keine Kollision, keine Abfragen, alles im Ordner "Decor"):
		Decorate() verziert alle Böden automatisch: Vorderkanten-Lippe, Leuchtkante,
		Zierbänder, Rippen/Fugen/Wurzeln, Eckleisten, Unterseiten (Eiszapfen, hängende
		Felsen, Lianen), Stützen bis in den Abgrund und Requisiten auf der hinteren
		Spurhälfte (z ≈ -3.5 … -4.8). Gesteuert über Theme-Felder (siehe
		MapDefinitions) sowie B.AutoDress / B.AutoSupports / B.AutoProps (false = aus).
		Dekoration liegt nie zwischen Kamera und Spielebene oberhalb der Lauffläche:
		vor z = +5 nur flache Blenden direkt auf Vorderseiten unterhalb der Oberkante.

	Öffentliche Deko-Bausteine (lokale Koordinaten, y = Oberkante des Bodens):
		Deco(size, cframe, color, material?, extra?) -> BasePart
			extra: Name, Transparency, Shape, Wedge, Mesh (Enum.MeshType), Light ({Range, Brightness, Color})
		Prop(kind, x, y, z?, opts?) -> {BasePart}
			kind: Crate, Barrel, Lamp, Torch, Bush, Rock, Crystal, Pine, SnowMound, IceBlock,
			      Column, Urn, Flower, Fern, Mushroom, Log, Vent, Barrier, HoloSign, Antenna,
			      Pipe, Girder, WarningLamp, Bench, Planter, Cone, Hurdle, Banner, Tree,
			      Temple, RuinArch, Tower  (die letzten drei sind große Wahrzeichen, opts.Scale)
			opts: Scale, Color (je nach Art)
		Lamp(x, y, z?, color?) -> {BasePart}               Laterne im Stil des Themes
		Pillar(x, yTop, yBottom, opts?) -> {BasePart}      Stütze (opts: Z, Width, Color, Material,
		                                                   Style "Girder"|"Pillar"|"Column"|"Ice"|"Stilt")
		Arch(x, y, width, height, color?, opts?) -> {BasePart}
		                                                   Torbogen hinter der Spur (opts: Label, Checker, Z, Depth)
		Banner(x, y, color?, opts?) -> {BasePart}          Fahne am Mast (opts: Height, Width, Z, Color2)
		Tree(x, y, z?, opts?) -> {BasePart}                Baum (opts: Kind "Round"|"Pine"|"Palm"|"Jungle",
		                                                   Scale, Height, Leaf)
		Cloud(x, y, z, scale?, opts?) -> {BasePart}        Wolke (opts: Color, Transparency, Puffs)
		Building(x, z, baseY, width, height, depth, opts?) -> {BasePart}
		                                                   Hochhaus (opts: Color, Material, Lights, WindowStyle 1–3, Roof)
		Waterfall(x, yTop, z, width, height)               Wasserfall mit Gischt
		Gates(count, color?, opts?)                        Torbögen über geraden Abschnitten, gleichmäßig
		                                                   über die Strecke verteilt (vor Decorate() aufrufen)
		Reserve(x1, x2)                                    Bereich ohne automatische Requisiten
		FloorAt(x) -> number?                              Oberkante des höchsten Bodens bei x

	Terrain-Bausteine (lokale Koordinaten). Terrain ist nur HINTER der Spur erlaubt:
	die Ausdehnung darf höchstens bis z = -12 reichen (sonst wird die Füllung mit
	Warnung übersprungen) – Boden-Raycasts der Spielfigur treffen so nie Terrain.
	Alle Füllungen werden aufgezeichnet (Result().TerrainFills) und von MapService
	beim Entladen der Region wieder gelöscht:
		TerrainBlock(x, y, z, size, material?, rotation?)
		TerrainBall(x, y, z, radius, material?)
		TerrainCylinder(x, y, z, height, radius, material?, rotation?)
		TerrainWedge(x, y, z, size, material?, rotation?)
		Mountain(x, z, baseY, height, width, opts?)        Berg (opts: Style "Round"|"Peak", Material, Cap,
		                                                   CapRatio, Depth)
		Island(x, y, z, radius, opts?) -> number           schwebende Insel (opts: Top, Rock, Cliff), liefert Oberkante
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local MapBuilder = {}
MapBuilder.__index = MapBuilder

local DEPTH = Config.World.TrackDepth
local FACE_Z = DEPTH / 2 -- Vorderseite der Spur (zur Kamera)
local BACK_Z = -4.2 -- Standardtiefe für Requisiten (hintere Spurhälfte)
local TERRAIN_MAX_Z = -12 -- Terrain darf höchstens bis hierher nach vorn reichen
local ROOT_HEIGHT = -Config.Character.FeetOffset + 0.3
local GRAVITY = Config.World.Gravity
local M = Enum.Material
local NEON = M.Neon
local BALL = Enum.PartType.Ball
local CYL = Enum.PartType.Cylinder
local SPHERE = Enum.MeshType.Sphere
local rgb = Color3.fromRGB

local VERTICAL = CFrame.Angles(0, 0, math.rad(90)) -- Zylinderachse (X) senkrecht stellen
local FACING = CFrame.Angles(0, math.rad(90), 0) -- Zylinderachse zur Kamera (Scheibe)
local WHITE = rgb(255, 255, 255)
local BLACK = rgb(22, 22, 28)
local STRIPE_YELLOW = rgb(250, 200, 40)
local ICE_TRIM = rgb(214, 244, 255)
local ICICLE = rgb(200, 238, 255)

local HAZARD_STYLE = {
	Lava = { Color = rgb(255, 92, 18), Material = NEON, Transparency = 0 },
	Laser = { Color = rgb(255, 45, 120), Material = NEON, Transparency = 0.2 },
	Flame = { Color = rgb(255, 120, 30), Material = NEON, Transparency = 0.15 },
	Arcane = { Color = rgb(175, 95, 255), Material = NEON, Transparency = 0.3 },
	Void = { Color = rgb(125, 80, 230), Material = NEON, Transparency = 0.7 },
	Icicle = { Color = rgb(185, 235, 255), Material = M.Glass, Transparency = 0.1 },
	IceWater = { Color = rgb(70, 160, 220), Material = M.Glass, Transparency = 0.3 },
	River = { Color = rgb(60, 150, 170), Material = M.Glass, Transparency = 0.3 },
	Thorns = { Color = rgb(110, 30, 50), Material = M.Slate, Transparency = 0 },
	Spikes = { Color = rgb(160, 162, 176), Material = M.Metal, Transparency = 0 },
}

local TEETH_KINDS = { Thorns = true, Spikes = true, Icicle = true }

-- Nur diese Materialien sind für Terrain gültig
local TERRAIN_MATERIALS = {}
for _, name in {
	"Water", "CrackedLava", "Grass", "LeafyGrass", "Rock", "Snow", "Glacier", "Sand", "Mud", "Basalt",
	"Ground", "Salt", "Limestone", "Sandstone", "Asphalt", "Slate", "Concrete",
} do
	TERRAIN_MATERIALS[M[name]] = true
end

-- Standardwerte für optionale Theme-Felder
local THEME_DEFAULTS = {
	Trim = rgb(176, 180, 196),
	TrimMaterial = M.Metal,
	Detail = rgb(62, 64, 80),
	DetailMaterial = M.Metal,
	Support = rgb(92, 94, 108),
	SupportMaterial = M.Metal,
	RibStyle = "Panel",
	SupportStyle = "Pillar",
	PropSpacing = 18,
	Leaf = rgb(70, 150, 60),
}

-- Höhe der Requisiten (für niedrige Decken)
local PROP_HEIGHT = {
	Lamp = 11, Torch = 6.5, Antenna = 9.5, Tree = 9, Banner = 9.8, Pine = 9.5, Column = 9.8, Girder = 6,
	HoloSign = 5, WarningLamp = 3.2, Crate = 4.4, Barrel = 3.2,
}

local RIB_SPACING = { Panel = 12, Joint = 10, Root = 8, Pipe = 12, Strata = 0 }

------------------------------------------------------------------------
-- Hilfsfunktionen
------------------------------------------------------------------------

--- Abdunkeln (factor < 1) oder Richtung Weiß aufhellen (factor > 1).
local function shade(color: Color3, factor: number): Color3
	if factor <= 1 then
		return Color3.new(color.R * factor, color.G * factor, color.B * factor)
	end
	return color:Lerp(WHITE, math.clamp(factor - 1, 0, 1))
end

--- Leichte zufällige Helligkeitsvariation.
local function jitter(rng, color: Color3, amount: number): Color3
	return shade(color, 1 + rng:NextNumber(-amount, amount))
end

local function emitter(parent: Instance, props)
	local e = Instance.new("ParticleEmitter")
	for key, value in props do
		e[key] = value
	end
	e.Parent = parent
	return e
end

--- Flammen-Partikel (Fackeln, Feuerschalen).
local function fireEmitter(parent: Instance, color: Color3, size: number)
	return emitter(parent, {
		Rate = 9,
		Lifetime = NumberRange.new(0.4, 0.8),
		Speed = NumberRange.new(2, 4),
		EmissionDirection = Enum.NormalId.Top,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(rgb(255, 236, 150), color),
		LightEmission = 1,
		SpreadAngle = Vector2.new(12, 12),
	})
end

--- Deko-Teil erzeugen und in eine Liste eintragen.
local function piece(builder, list, size: Vector3, cframe: CFrame, color: Color3, material, extra)
	local part = builder:Deco(size, cframe, color, material, extra)
	table.insert(list, part)
	return part
end

--- Erstellt einen neuen Builder.
--- params: Name, RegionId, MapId, Origin (Vector3), Theme, Difficulty (1–3), Seed
function MapBuilder.new(params)
	local self = setmetatable({}, MapBuilder)
	self.RegionId = params.RegionId
	self.MapId = params.MapId
	self.Origin = params.Origin or Vector3.zero
	self.Theme = params.Theme
	self.Difficulty = params.Difficulty or 2
	self.Rng = Random.new(params.Seed or 1)

	self.Model = Instance.new("Model")
	self.Model.Name = params.Name or params.MapId or "Map"
	self.Model:SetAttribute("RegionId", self.RegionId)
	self.Model:SetAttribute("MapId", self.MapId)

	self.Folders = {}
	for _, name in { "Geometry", "Hazards", "Anchors", "Pads", "Decor", "Pickups", "Runtime" } do
		local folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = self.Model
		self.Folders[name] = folder
	end

	self.X = 0
	self.Y = 0
	self.Thickness = 8
	self.NoPitHazard = false
	self.AutoCheckpoints = true
	self.CheckpointSpacing = 140
	self.LastCheckpointX = -math.huge

	self.MinX, self.MaxX, self.MinY, self.MaxY = 0, 0, 0, 0
	self.Spawns = {}
	self.Checkpoints = {}
	self.TeleportNodes = {}
	self.PickupSpawns = {}
	self.Anchors = {}
	self.Portals = {}
	self.StartLocalX = 0
	self.FinishLocalX = nil

	-- Optik: Aufzeichnungen für die automatische Verzierung in Decorate()
	self.Platforms = {} -- { X1, X2, Y, Bottom, Ice, Upper, NoDress }
	self.Ramps = {} -- { X1, Y1, X2, Y2, Bottom }
	self.Ceilings = {} -- { X1, X2, Y } Unterkanten von Decken (Tunnel, Kletterwand)
	self.Solids = {} -- { X1, X2, Y1, Y2 } Wände und Blöcke
	self.Reserved = {} -- { x1, x2 } Bereiche ohne automatische Requisiten
	self.TerrainFills = {} -- aufgezeichnete Terrain-Füllungen (Weltkoordinaten)
	self.AutoDress = true
	self.AutoSupports = true
	self.AutoProps = true
	self.LastLampX = -math.huge
	self.LightCount = 0
	self.MaxLights = 48
	return self
end

--- Lokale Koordinate -> Weltposition.
function MapBuilder:W(x: number, y: number, z: number?): Vector3
	return self.Origin + Vector3.new(x, y, z or 0)
end

--- Schwierigkeitsfaktor (0.9 / 1.0 / 1.1) für Lückenbreiten.
function MapBuilder:D(value: number): number
	return value * (0.8 + 0.1 * self.Difficulty)
end

function MapBuilder:_track(x1, y1, x2, y2)
	self.MinX = math.min(self.MinX, x1, x2)
	self.MaxX = math.max(self.MaxX, x1, x2)
	self.MinY = math.min(self.MinY, y1, y2)
	self.MaxY = math.max(self.MaxY, y1, y2)
end

--- Theme-Feld mit Standardwert.
function MapBuilder:_t(key: string)
	local value = self.Theme[key]
	if value == nil then
		return THEME_DEFAULTS[key]
	end
	return value
end

--- Material für Wände, Tunneldecken und Kletterblöcke.
function MapBuilder:_wallMaterial()
	return self.Theme.WallMaterial or self.Theme.GroundMaterial
end

------------------------------------------------------------------------
-- Primitive
------------------------------------------------------------------------

--- Erstellt einen verankerten Part. props: Size, CFrame, Color, Material, Transparency,
--- CanCollide, CanQuery, CastShadow, Parent, Shape, Wedge, Name
function MapBuilder:Part(props): BasePart
	local part: BasePart
	if props.Wedge then
		part = Instance.new("WedgePart")
	else
		local p = Instance.new("Part")
		if props.Shape then
			p.Shape = props.Shape
		end
		part = p
	end
	part.Name = props.Name or "Part"
	part.Anchored = true
	part.Size = props.Size
	part.CFrame = props.CFrame
	part.Color = props.Color or self.Theme.Ground
	part.Material = props.Material or self.Theme.GroundMaterial
	part.Transparency = props.Transparency or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	local collide = props.CanCollide ~= false
	part.CanCollide = collide
	if props.CanQuery ~= nil then
		part.CanQuery = props.CanQuery
	else
		part.CanQuery = collide
	end
	part.CanTouch = false
	if props.CastShadow ~= nil then
		part.CastShadow = props.CastShadow
	else
		part.CastShadow = collide
	end
	part.Parent = props.Parent or self.Folders.Geometry
	return part
end

--- Dekorations-Part (keine Kollision, keine Abfragen, kein Schatten).
--- extra: Name, Transparency, Shape, Wedge, Mesh (Enum.MeshType), Light ({Range, Brightness, Color})
function MapBuilder:Deco(size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, extra)
	local props = {
		Name = extra and extra.Name or "Deco",
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = material or M.SmoothPlastic,
		Transparency = extra and extra.Transparency or 0,
		Shape = extra and extra.Shape or nil,
		Wedge = extra and extra.Wedge or nil,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
		Parent = self.Folders.Decor,
	}
	local part = self:Part(props)
	if extra then
		if extra.Mesh then
			-- Eingebautes Mesh (z.B. Kugel) passt sich der Part-Größe an -> Ellipsoide
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = extra.Mesh
			mesh.Parent = part
		end
		if extra.Light and self.LightCount < self.MaxLights then
			self.LightCount += 1
			local light = Instance.new("PointLight")
			light.Range = extra.Light.Range or 12
			light.Brightness = extra.Light.Brightness or 1
			light.Color = extra.Light.Color or color
			light.Shadows = false
			light.Parent = part
		end
	end
	return part
end

--- Achsparalleler Block zwischen zwei lokalen Ecken (volle Spurtiefe).
function MapBuilder:Box(x1: number, y1: number, x2: number, y2: number, opts)
	opts = opts or {}
	if x2 < x1 then
		x1, x2 = x2, x1
	end
	if y2 < y1 then
		y1, y2 = y2, y1
	end
	local depth = opts.Depth or DEPTH
	local size = Vector3.new(math.max(x2 - x1, 0.05), math.max(y2 - y1, 0.05), depth)
	local cframe = CFrame.new(self:W((x1 + x2) / 2, (y1 + y2) / 2, opts.Z or 0))
	if opts.Track ~= false and opts.CanCollide ~= false then
		self:_track(x1, y1, x2, y2)
	end
	return self:Part({
		Name = opts.Name,
		Size = size,
		CFrame = cframe,
		Color = opts.Color,
		Material = opts.Material,
		Transparency = opts.Transparency,
		CanCollide = opts.CanCollide,
		CanQuery = opts.CanQuery,
		CastShadow = opts.CastShadow,
		Parent = opts.Parent,
		Shape = opts.Shape,
	})
end

--- Plattform mit Oberkante y. opts: Thickness, Ice, TopColor, TopMaterial, NoDress
--- (NoDress = true: keine automatische Verzierung in Decorate()).
function MapBuilder:Ground(x1: number, x2: number, y: number, opts)
	opts = opts or {}
	local theme = self.Theme
	local thickness = opts.Thickness or self.Thickness
	local topThickness = math.min(1, thickness)
	if thickness > topThickness then
		self:Box(x1, y - thickness, x2, y - topThickness, {
			Name = "Ground",
			Color = theme.Ground,
			Material = theme.GroundMaterial,
		})
	end
	local top = self:Box(x1, y - topThickness, x2, y, {
		Name = "Floor",
		Color = opts.TopColor or theme.Top,
		Material = opts.TopMaterial or theme.TopMaterial,
	})
	if opts.Ice then
		top:SetAttribute("Ice", true)
		top.Material = M.Ice
		top.Color = rgb(200, 238, 255)
	end
	table.insert(self.Platforms, {
		X1 = math.min(x1, x2),
		X2 = math.max(x1, x2),
		Y = y,
		Bottom = y - thickness,
		Ice = opts.Ice == true,
		Upper = self.NoPitHazard,
		NoDress = opts.NoDress == true,
	})
	return top
end

--- Rampe von (x1, y1) nach (x2, y2) inklusive Unterbau.
function MapBuilder:RampPart(x1: number, y1: number, x2: number, y2: number, opts)
	opts = opts or {}
	local theme = self.Theme
	local thickness = opts.Thickness or self.Thickness
	local low, high = math.min(y1, y2), math.max(y1, y2)
	local length = x2 - x1
	local rise = high - low
	if rise > 0.05 then
		-- Keil: hohe Seite liegt lokal bei +Z; Drehung um Y richtet sie entlang ±X aus.
		local angle = if y2 > y1 then math.rad(90) else math.rad(-90)
		self:Part({
			Wedge = true,
			Name = "Ramp",
			Size = Vector3.new(DEPTH, rise, length),
			CFrame = CFrame.new(self:W((x1 + x2) / 2, (low + high) / 2, 0)) * CFrame.Angles(0, angle, 0),
			Color = theme.Top,
			Material = theme.TopMaterial,
		})
	end
	self:Box(x1, low - thickness, x2, low, { Name = "RampBase", Color = theme.Ground, Material = theme.GroundMaterial })
	self:_track(x1, low - thickness, x2, high)
	table.insert(self.Ramps, { X1 = x1, Y1 = y1, X2 = x2, Y2 = y2, Bottom = low - thickness })
end

--- Greifhaken-Anker an lokaler Position.
function MapBuilder:Anchor(x: number, y: number)
	local theme = self.Theme
	local color = theme.Anchor or theme.Accent
	local position = self:W(x, y, 0)
	local part = self:Part({
		Name = "GrappleAnchor",
		Shape = BALL,
		Size = Vector3.new(1.8, 1.8, 1.8),
		CFrame = CFrame.new(position),
		Color = color,
		Material = NEON,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
		Parent = self.Folders.Anchors,
	})
	self:Deco(Vector3.new(0.25, 3.4, 3.4), CFrame.new(position) * FACING, color, NEON, {
		Name = "AnchorRing",
		Shape = CYL,
		Transparency = 0.45,
		Light = { Range = 14, Brightness = 1.2, Color = color },
	})
	-- Weicher Halo direkt hinter dem Anker
	self:Deco(Vector3.new(0.1, 5.4, 5.4), CFrame.new(position + Vector3.new(0, 0, -0.9)) * FACING, color, NEON, {
		Name = "AnchorHalo",
		Shape = CYL,
		Transparency = 0.82,
	})
	table.insert(self.Anchors, part)
	return part
end

--- Dreieck in der Seitenansicht aus zwei Keilen (Spitze oben oder unten).
--- yBase = Grundlinie (bei pointDown die Oberkante).
function MapBuilder:_triangle(cx, yBase, width, height, depth, z, color, material, pointDown, name, list)
	local half = width / 2
	local yCenter = if pointDown then yBase - height / 2 else yBase + height / 2
	local flip = if pointDown then CFrame.Angles(0, 0, math.rad(180)) else CFrame.identity
	local size = Vector3.new(depth, height, half)
	local a = self:Deco(size, CFrame.new(self:W(cx - half / 2, yCenter, z)) * flip * CFrame.Angles(0, math.rad(if pointDown then -90 else 90), 0), color, material, { Name = name, Wedge = true })
	local b = self:Deco(size, CFrame.new(self:W(cx + half / 2, yCenter, z)) * flip * CFrame.Angles(0, math.rad(if pointDown then 90 else -90), 0), color, material, { Name = name, Wedge = true })
	if list then
		table.insert(list, a)
		table.insert(list, b)
	end
end

--- Leuchtpfeil aus zwei Balken: dir "Up" (^) oder "Right" (>).
function MapBuilder:_chevron(cx, cy, z, size, color, dir, name, transparency)
	local len = size * 0.72
	local thick = size * 0.24
	local extra = { Name = name or "Chevron", Transparency = transparency or 0 }
	local bar = Vector3.new(len, thick, 0.14)
	if dir == "Up" then
		local a = math.atan2(0.6, 0.4)
		self:Deco(bar, CFrame.new(self:W(cx - size * 0.2, cy, z)) * CFrame.Angles(0, 0, a), color, NEON, extra)
		self:Deco(bar, CFrame.new(self:W(cx + size * 0.2, cy, z)) * CFrame.Angles(0, 0, -a), color, NEON, extra)
	else
		local a = math.atan2(0.4, 0.6)
		self:Deco(bar, CFrame.new(self:W(cx, cy + size * 0.2, z)) * CFrame.Angles(0, 0, -a), color, NEON, extra)
		self:Deco(bar, CFrame.new(self:W(cx, cy - size * 0.2, z)) * CFrame.Angles(0, 0, a), color, NEON, extra)
	end
end

--- Zacken-Dekoration (Dornen/Stacheln/Eiszapfen) entlang einer Kante.
function MapBuilder:_teeth(x1: number, x2: number, y: number, height: number, color: Color3, material, pointDown: boolean?)
	local width = x2 - x1
	local count = math.clamp(math.floor(width / 2.5), 1, 24)
	local toothWidth = width / count
	for i = 0, count - 1 do
		local cx = x1 + toothWidth * (i + 0.5)
		self:_triangle(cx, y, toothWidth, height, DEPTH * 0.8, 0, color, material, pointDown == true, "Tooth")
	end
end

--- Tödlicher Bereich. opts: Period, OnTime, Offset (zeitgesteuert), Depth, Color, Teeth
function MapBuilder:Hazard(x1: number, y1: number, x2: number, y2: number, kind: string, opts)
	opts = opts or {}
	local style = HAZARD_STYLE[kind] or HAZARD_STYLE.Laser
	local part = self:Box(x1, y1, x2, y2, {
		Name = "Hazard_" .. kind,
		Color = opts.Color or style.Color,
		Material = style.Material,
		Transparency = style.Transparency,
		CanCollide = false,
		CanQuery = true,
		CastShadow = false,
		Depth = opts.Depth,
		Parent = self.Folders.Hazards,
		Track = false,
	})
	part:SetAttribute("HazardKind", kind)
	if opts.Period then
		part:SetAttribute("HazardPeriod", opts.Period)
		part:SetAttribute("HazardOnTime", opts.OnTime or opts.Period / 2)
		part:SetAttribute("HazardOffset", opts.Offset or 0)
		CollectionService:AddTag(part, "TimedHazard")
	end
	if opts.Teeth ~= false and TEETH_KINDS[kind] and not opts.Period then
		self:_teeth(math.min(x1, x2), math.max(x1, x2), math.max(y1, y2), 1.6, style.Color, style.Material, false)
	end
	return part
end

--- Boost-Pad (beschleunigt in +X-Richtung).
function MapBuilder:BoostPad(x1: number, x2: number, y: number, power: number?)
	local pad = self:Box(x1, y - 0.1, x2, y + 0.06, {
		Name = "BoostPad",
		Color = rgb(255, 176, 20),
		Material = NEON,
		Depth = DEPTH - 1,
		Parent = self.Folders.Pads,
		Track = false,
	})
	pad:SetAttribute("BoostPad", power or 80)
	local lo, hi = math.min(x1, x2), math.max(x1, x2)
	self:Reserve(lo - 1, hi + 1)
	-- Pfeile (">") auf der Vorderseite des Bodens – gut sichtbar, verdecken nichts
	local count = math.clamp(math.floor((hi - lo) / 5), 1, 8)
	for i = 1, count do
		local cx = lo + (hi - lo) * i / (count + 1)
		self:_chevron(cx, y - 0.55, FACE_Z + 0.1, 0.95, rgb(255, 226, 120), "Right", "BoostArrow")
	end
	-- Leuchtschiene hinter dem Pad
	self:Deco(Vector3.new(hi - lo, 0.22, 0.22), CFrame.new(self:W((lo + hi) / 2, y + 1.1, -4.75)), rgb(255, 196, 60), NEON, { Name = "BoostRail" })
	for _, px in { lo + 0.3, hi - 0.3 } do
		self:Deco(Vector3.new(0.3, 1.1, 0.3), CFrame.new(self:W(px, y + 0.55, -4.75)), rgb(60, 62, 72), M.Metal, { Name = "BoostRailPost" })
	end
	return pad
end

--- Sprungpad mit vertikaler Startgeschwindigkeit `power`.
function MapBuilder:JumpPad(x: number, y: number, power: number)
	local pad = self:Box(x - 2.5, y - 0.1, x + 2.5, y + 0.3, {
		Name = "JumpPad",
		Color = rgb(80, 255, 140),
		Material = NEON,
		Depth = DEPTH - 2,
		Parent = self.Folders.Pads,
		Track = false,
	})
	pad:SetAttribute("JumpPad", power)
	self:Reserve(x - 4, x + 4)
	local glow = rgb(150, 255, 190)
	-- Gehäuserahmen (unterhalb der Pad-Oberkante)
	self:Deco(Vector3.new(6.2, 0.3, DEPTH - 1.2), CFrame.new(self:W(x, y + 0.05, 0)), rgb(48, 54, 66), M.Metal, { Name = "JumpPadFrame" })
	-- Pfeile nach oben: auf der Vorderseite des Bodens und gestaffelt hinter dem Pad
	self:_chevron(x - 1.1, y - 0.55, FACE_Z + 0.1, 0.9, glow, "Up", "JumpPadArrow")
	self:_chevron(x + 1.1, y - 0.55, FACE_Z + 0.1, 0.9, glow, "Up", "JumpPadArrow")
	for i = 1, 3 do
		self:_chevron(x, y + 0.6 + i * 1.4, -4.6, 1.6, glow, "Up", "JumpPadArrow", 0.1 + i * 0.2)
	end
	-- Aufsteigende Funken
	local holder = self:Deco(Vector3.new(4, 0.2, DEPTH - 3), CFrame.new(self:W(x, y + 0.4, 0)), glow, nil, { Name = "JumpPadSparks", Transparency = 1 })
	emitter(holder, {
		Rate = 6,
		Lifetime = NumberRange.new(0.6, 1.1),
		Speed = NumberRange.new(6, 11),
		EmissionDirection = Enum.NormalId.Top,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) }),
		Color = ColorSequence.new(glow),
		LightEmission = 1,
		SpreadAngle = Vector2.new(6, 6),
	})
	return pad
end

--- Spawnpunkt (Root-Position über dem Boden y, Blick nach +X).
function MapBuilder:SpawnPoint(x: number, y: number, z: number?)
	local position = self:W(x, y + ROOT_HEIGHT, z or 0)
	table.insert(self.Spawns, CFrame.lookAt(position, position + Vector3.new(1, 0, 0)))
end

--- Checkpoint für Respawns (inkl. Fahne mit Leuchtkugel).
function MapBuilder:Checkpoint(x: number?, y: number?)
	local cx = x or self.X
	local cy = y or self.Y
	local position = self:W(cx, cy + ROOT_HEIGHT, 0)
	table.insert(self.Checkpoints, {
		X = position.X,
		CFrame = CFrame.lookAt(position, position + Vector3.new(1, 0, 0)),
	})
	self.LastCheckpointX = cx
	self:Reserve(cx - 2.5, cx + 4.5)
	local theme = self.Theme
	local accent = theme.Accent
	local z = -DEPTH / 2 + 0.4
	self:Deco(Vector3.new(0.4, 2.2, 2.2), CFrame.new(self:W(cx, cy + 0.2, z)) * VERTICAL, rgb(52, 56, 70), M.Metal, { Name = "CheckpointBase", Shape = CYL })
	self:Deco(Vector3.new(9.4, 0.32, 0.32), CFrame.new(self:W(cx, cy + 4.9, z)) * VERTICAL, rgb(236, 238, 246), M.Metal, { Name = "CheckpointPole", Shape = CYL })
	self:Deco(Vector3.new(0.18, 0.56, 0.56), CFrame.new(self:W(cx, cy + 6.4, z)) * VERTICAL, theme.Accent2 or accent, NEON, { Name = "CheckpointRing", Shape = CYL })
	self:Deco(Vector3.new(0.9, 0.9, 0.9), CFrame.new(self:W(cx, cy + 9.85, z)), accent, NEON, {
		Name = "CheckpointOrb",
		Shape = BALL,
		Light = { Range = 12, Brightness = 1.3, Color = accent },
	})
	-- Wimpel: ein Keil, rechter Winkel oben am Mast, Spitze zeigt in Laufrichtung
	self:Deco(
		Vector3.new(0.14, 2.4, 3.4),
		CFrame.new(self:W(cx + 1.85, cy + 8.2, z)) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(math.rad(180), 0, 0),
		accent,
		NEON,
		{ Name = "CheckpointFlag", Wedge = true }
	)
end

function MapBuilder:_autoCheckpoint(x: number, y: number)
	if self.AutoCheckpoints and x - self.LastCheckpointX >= self.CheckpointSpacing then
		self:Checkpoint(x, y)
	end
end

function MapBuilder:_node(x: number, y: number)
	table.insert(self.TeleportNodes, self:W(x, y + ROOT_HEIGHT, 0))
end

--- Spawnpunkt für eine Item-Box (Box schwebt auf Brusthöhe).
function MapBuilder:PickupSpot(x: number, y: number)
	table.insert(self.PickupSpawns, self:W(x, y + 3, 0))
end

--- Schild (BillboardGui) an lokaler Position.
--- opts: Width, Height, Color, Transparent, Z, Style ("Banner" = nur große Schrift mit Kontur)
function MapBuilder:Sign(x: number, y: number, title: string, text: string?, opts)
	opts = opts or {}
	local accent = opts.Color or self.Theme.Accent
	local hasBody = text ~= nil and text ~= ""
	local banner = opts.Style == "Banner"
	local plain = banner or opts.Transparent == true
	local holder = self:Deco(Vector3.new(0.2, 0.2, 0.2), CFrame.new(self:W(x, y, opts.Z or -2)), Color3.new(), nil, { Name = "Sign", Transparency = 1 })
	local gui = Instance.new("BillboardGui")
	gui.Name = "SignGui"
	gui.Size = UDim2.new(opts.Width or 26, 0, opts.Height or (if hasBody then 7 else 4), 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 260
	gui.Adornee = holder

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = rgb(20, 24, 46)
	frame.BackgroundTransparency = if plain then 1 else 0.1
	frame.BorderSizePixel = 0
	frame.Parent = gui
	if not plain then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.16, 0)
		corner.Parent = frame
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new(rgb(255, 255, 255), rgb(150, 158, 200))
		gradient.Rotation = 90
		gradient.Parent = frame
		local stroke = Instance.new("UIStroke")
		stroke.Color = accent
		stroke.Thickness = 3
		stroke.Parent = frame
		-- Akzent-Reiter an der Oberkante
		local tab = Instance.new("Frame")
		tab.AnchorPoint = Vector2.new(0.5, 0.5)
		tab.Position = UDim2.fromScale(0.5, 0)
		tab.Size = UDim2.fromScale(0.36, 0.09)
		tab.BackgroundColor3 = accent
		tab.BorderSizePixel = 0
		tab.Parent = frame
		local tabCorner = Instance.new("UICorner")
		tabCorner.CornerRadius = UDim.new(1, 0)
		tabCorner.Parent = tab
	end

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = if hasBody then UDim2.fromScale(0.92, 0.46) else UDim2.fromScale(0.92, 0.8)
	titleLabel.Position = UDim2.fromScale(0.04, 0.1)
	titleLabel.Font = Enum.Font.FredokaOne
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = if banner then WHITE else accent
	titleLabel.TextStrokeColor3 = rgb(10, 12, 24)
	titleLabel.TextStrokeTransparency = if banner then 1 else 0.5
	titleLabel.Text = title
	titleLabel.Parent = frame
	if banner then
		local outline = Instance.new("UIStroke")
		outline.Color = rgb(12, 14, 26)
		outline.Thickness = 4
		outline.Parent = titleLabel
		local tint = Instance.new("UIGradient")
		tint.Color = ColorSequence.new(WHITE, accent)
		tint.Rotation = 90
		tint.Parent = titleLabel
	end

	if hasBody then
		local body = Instance.new("TextLabel")
		body.BackgroundTransparency = 1
		body.Size = UDim2.fromScale(0.92, 0.36)
		body.Position = UDim2.fromScale(0.04, 0.58)
		body.Font = Enum.Font.GothamBold
		body.TextScaled = true
		body.TextColor3 = rgb(236, 240, 255)
		body.TextStrokeColor3 = rgb(10, 12, 24)
		body.TextStrokeTransparency = 0.7
		body.Text = text
		body.Parent = frame
	end
	gui.Parent = holder
	return holder
end

--- Portal in der Lobby (Stehenbleiben löst eine Aktion aus).
function MapBuilder:Portal(x: number, y: number, action: string, label: string, color: Color3)
	local z = -3
	local frame = rgb(40, 44, 62)
	self:Reserve(x - 7.5, x + 7.5)
	self:Deco(Vector3.new(14, 0.4, 3.4), CFrame.new(self:W(x, y + 0.2, z)), frame, M.Metal, { Name = "PortalBase" })
	for _, side in { -1, 1 } do
		self:Deco(Vector3.new(1.4, 13, 2.4), CFrame.new(self:W(x + side * 5.6, y + 6.5, z)), frame, M.Metal, { Name = "PortalPost" })
		self:Deco(Vector3.new(0.35, 12.4, 2.5), CFrame.new(self:W(x + side * 4.95, y + 6.5, z)), color, NEON, { Name = "PortalPostGlow" })
	end
	self:Deco(Vector3.new(12.6, 1.4, 2.4), CFrame.new(self:W(x, y + 13.6, z)), frame, M.Metal, { Name = "PortalTop" })
	self:Deco(Vector3.new(10, 0.35, 2.5), CFrame.new(self:W(x, y + 12.95, z)), color, NEON, { Name = "PortalTopGlow" })
	local field = self:Deco(Vector3.new(9.6, 12.4, 0.4), CFrame.new(self:W(x, y + 6.5, z - 0.5)), color, M.ForceField, {
		Name = "PortalField",
		Transparency = 0.2,
		Light = { Range = 16, Brightness = 2, Color = color },
	})
	emitter(field, {
		Rate = 6,
		Lifetime = NumberRange.new(1.5, 2.5),
		Speed = NumberRange.new(1, 3),
		EmissionDirection = Enum.NormalId.Top,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) }),
		Color = ColorSequence.new(color),
		LightEmission = 1,
		SpreadAngle = Vector2.new(30, 30),
	})
	self:Sign(x, y + 17, label, "Hier stehen bleiben", { Width = 16, Height = 5, Color = color })
	local minCorner = self:W(x - 5, y, 0)
	local maxCorner = self:W(x + 5, y + 12, 0)
	table.insert(self.Portals, {
		Action = action,
		MinX = minCorner.X,
		MaxX = maxCorner.X,
		MinY = minCorner.Y,
		MaxY = maxCorner.Y,
	})
end

--- Markiert einen Bereich, in dem Decorate() keine Requisiten aufstellt.
function MapBuilder:Reserve(x1: number, x2: number)
	table.insert(self.Reserved, { math.min(x1, x2), math.max(x1, x2) })
end

function MapBuilder:_isReserved(x1: number, x2: number): boolean
	for _, r in self.Reserved do
		if x2 >= r[1] and x1 <= r[2] then
			return true
		end
	end
	return false
end

--- Höchste Oberkante bei x (Böden, Rampen; optional auch Wände/Blöcke).
--- maxY: nur Oberkanten unterhalb dieser Höhe berücksichtigen.
function MapBuilder:_topAt(x: number, maxY: number?, withSolids: boolean?): number?
	local best = nil
	local function consider(y)
		if (maxY == nil or y < maxY) and (best == nil or y > best) then
			best = y
		end
	end
	for _, p in self.Platforms do
		if x >= p.X1 - 0.01 and x <= p.X2 + 0.01 then
			consider(p.Y)
		end
	end
	for _, r in self.Ramps do
		if x >= r.X1 and x <= r.X2 then
			local t = (x - r.X1) / math.max(r.X2 - r.X1, 0.01)
			consider(r.Y1 + (r.Y2 - r.Y1) * t)
		end
	end
	if withSolids then
		for _, s in self.Solids do
			if x >= s.X1 - 0.01 and x <= s.X2 + 0.01 then
				consider(s.Y2)
			end
		end
	end
	return best
end

--- Oberkante des höchsten Bodens (oder der höchsten Rampe) bei x.
function MapBuilder:FloorAt(x: number): number?
	return self:_topAt(x)
end

------------------------------------------------------------------------
-- Cursor-Bausteine
------------------------------------------------------------------------

--- Zierleisten auf der Vorderseite einer Wand bzw. eines Blocks (x1..x2, y1..y2).
--- opts.NoCenter: keine Mittellinie/Bänder (z.B. wenn Pfeile darauf sitzen).
function MapBuilder:_wallFace(x1: number, x2: number, y1: number, y2: number, opts)
	opts = opts or {}
	local theme = self.Theme
	local trim, trimMat = self:_t("Trim"), self:_t("TrimMaterial")
	local w, h = x2 - x1, y2 - y1
	local cx, cy = (x1 + x2) / 2, (y1 + y2) / 2
	if w >= 3 then
		for _, ex in { x1 + 0.35, x2 - 0.35 } do
			self:Deco(Vector3.new(0.7, h - 0.5, 0.3), CFrame.new(self:W(ex, cy - 0.25, FACE_Z + 0.15)), trim, trimMat, { Name = "WallTrim" })
		end
	end
	self:Deco(Vector3.new(w + 0.3, 0.5, 0.7), CFrame.new(self:W(cx, y2 - 0.2, FACE_Z)), trim, trimMat, { Name = "Lip" })
	if opts.NoCenter then
		return
	end
	if theme.EdgeGlow then
		self:Deco(Vector3.new(0.22, math.max(h - 3, 0.5), 0.1), CFrame.new(self:W(cx, cy, FACE_Z + 0.06)), theme.Accent, NEON, { Name = "WallGlow" })
	elseif w >= 3 then
		local detail, detailMat = self:_t("Detail"), self:_t("DetailMaterial")
		local by = y2 - 4
		while by > y1 + 2 do
			self:Deco(Vector3.new(w - 1.6, 0.4, 0.12), CFrame.new(self:W(cx, by, FACE_Z + 0.06)), detail, detailMat, { Name = "WallBand" })
			by -= 14
		end
	end
end

--- Startbereich: Rückwand, Boden, 8 Spawnpunkte (gleiche X-Position, gestaffelte Tiefe), Startlinie.
function MapBuilder:Start(length: number?)
	local len = length or 60
	local theme = self.Theme
	local y = self.Y
	self:Box(-48, y - self.Thickness, -40, y + 70, { Name = "StartWall", Color = theme.Wall, Material = self:_wallMaterial() })
	table.insert(self.Solids, { X1 = -48, X2 = -40, Y1 = y - self.Thickness, Y2 = y + 70 })
	self:Ground(-40, len, y)
	for i = 0, 7 do
		self:SpawnPoint(22, y, -3.5 + i)
	end
	self:Checkpoint(22, y)
	self.StartLocalX = 34
	self:Deco(Vector3.new(0.6, 0.12, DEPTH), CFrame.new(self:W(34, y + 0.07, 0)), rgb(255, 255, 255), NEON, { Name = "StartLine" })
	self:_node(10, y)
	self.X = len

	-- Optik: Startbogen (mit Schriftzug), verzierte Startwand, Fahnen
	self:Reserve(-40, 50)
	self:Arch(34, y, 18, 16, theme.Accent, { Label = "START" })
	self:_wallFace(-48, -40, y - self.Thickness, y + 70)
	self:Banner(-30, y, theme.Accent, { Height = 12, Width = 3.4, Color2 = theme.Accent2 })
	self:Banner(-8, y, theme.Accent2 or theme.Accent, { Height = 12, Width = 3.4, Color2 = theme.Accent })
	self:Lamp(6, y)
	-- Startraster: Leuchtmarken auf der Vorderseite des Bodens
	for i = 0, 3 do
		self:Deco(Vector3.new(1.6, 0.35, 0.1), CFrame.new(self:W(22 + i * 3.2 - 4.8, y - 0.9, FACE_Z + 0.12)), WHITE, NEON, { Name = "GridMark", Transparency = 0.25 })
	end
end

--- Gerader Boden.
function MapBuilder:Flat(length: number, opts)
	local x1, x2 = self.X, self.X + length
	self:Ground(x1, x2, self.Y, opts)
	self:_node(x1 + length * 0.5, self.Y)
	self:_autoCheckpoint(x1 + math.min(8, length / 2), self.Y)
	self.X = x2
end

--- Gefahr am Grund einer Lücke (abhängig vom Theme).
function MapBuilder:_pitHazard(x1: number, x2: number, refY: number)
	if self.NoPitHazard then
		return
	end
	local kind = self.Theme.PitKind
	local bottom = refY - 24
	if kind == "Lava" then
		self:Hazard(x1 - 2, bottom - 4, x2 + 2, bottom, "Lava")
	elseif kind == "IceWater" or kind == "River" then
		self:Hazard(x1 - 2, bottom - 6, x2 + 2, bottom, kind)
	elseif kind == "Thorns" then
		self:Hazard(x1 - 2, bottom - 2, x2 + 2, bottom, "Thorns")
	elseif kind == "Void" then
		self:Hazard(x1 - 2, bottom - 12, x2 + 2, bottom - 11, "Void")
	else
		self:Hazard(x1 - 2, bottom - 0.6, x2 + 2, bottom, "Laser")
	end
	self:_track(x1, bottom - 6, x2, bottom - 6)
	self:_pitDecor(kind, x1 - 2, x2 + 2, bottom)
end

--- Optik der Grubengefahren (Kruste, Laser-Netz, Schaum, Nebel …).
function MapBuilder:_pitDecor(kind: string, x1: number, x2: number, surface: number)
	local rng = self.Rng
	local w = x2 - x1
	local cx = (x1 + x2) / 2
	if kind == "Lava" then
		for _ = 1, math.clamp(math.floor(w / 9), 1, 5) do
			self:Deco(
				Vector3.new(rng:NextNumber(2.5, 5), 0.5, rng:NextNumber(1.5, 3.5)),
				CFrame.new(self:W(rng:NextNumber(x1 + 2, x2 - 2), surface + 0.12, rng:NextNumber(-3.5, 3.5))) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 180)), 0),
				rgb(58, 40, 34),
				M.CrackedLava,
				{ Name = "LavaCrust" }
			)
		end
		local glow = self:Deco(Vector3.new(w, 0.4, DEPTH - 2), CFrame.new(self:W(cx, surface + 0.6, 0)), HAZARD_STYLE.Lava.Color, nil, {
			Name = "LavaGlow",
			Transparency = 1,
			Light = { Range = 26, Brightness = 2, Color = rgb(255, 120, 40) },
		})
		emitter(glow, {
			Rate = 5,
			Lifetime = NumberRange.new(1.5, 2.5),
			Speed = NumberRange.new(5, 10),
			EmissionDirection = Enum.NormalId.Top,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) }),
			Color = ColorSequence.new(rgb(255, 170, 60)),
			LightEmission = 1,
			SpreadAngle = Vector2.new(20, 20),
		})
	elseif kind == "IceWater" or kind == "River" then
		local deep = if kind == "River" then rgb(18, 70, 80) else rgb(20, 60, 120)
		local surfaceColor = if kind == "River" then rgb(150, 220, 210) else rgb(180, 232, 255)
		self:Deco(Vector3.new(w, 0.2, DEPTH - 0.4), CFrame.new(self:W(cx, surface - 0.08, 0)), surfaceColor, M.Glass, { Name = "WaterSurface", Transparency = 0.55 })
		self:Deco(Vector3.new(w, 2.4, DEPTH - 0.4), CFrame.new(self:W(cx, surface - 4.6, 0)), deep, M.SmoothPlastic, { Name = "WaterDeep", Transparency = 0.1 })
		for _ = 1, math.clamp(math.floor(w / 12), 1, 3) do
			local fx = rng:NextNumber(x1 + 2, x2 - 2)
			local fz = rng:NextNumber(-3, 3)
			if kind == "IceWater" then
				self:Deco(Vector3.new(rng:NextNumber(2.5, 4.5), 0.6, rng:NextNumber(2, 3.5)), CFrame.new(self:W(fx, surface + 0.05, fz)) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 180)), 0), rgb(226, 244, 255), M.Ice, { Name = "IceFloe" })
			else
				self:Deco(Vector3.new(0.15, 2.2, 2.2), CFrame.new(self:W(fx, surface + 0.08, fz)) * VERTICAL, rgb(80, 160, 70), M.Grass, { Name = "LilyPad", Shape = CYL })
			end
		end
	elseif kind == "Thorns" then
		for _ = 1, math.clamp(math.floor(w / 8), 1, 4) do
			local d = rng:NextNumber(2.2, 3.4)
			self:Deco(Vector3.new(d, d, d), CFrame.new(self:W(rng:NextNumber(x1 + 1, x2 - 1), surface + 0.4, rng:NextNumber(-4, -2.5))), rgb(46, 74, 40), M.Grass, { Name = "Bramble", Shape = BALL })
		end
	elseif kind == "Void" then
		local color = HAZARD_STYLE.Void.Color
		local mist = self:Deco(Vector3.new(w, 0.5, DEPTH - 2), CFrame.new(self:W(cx, surface - 11, 0)), color, nil, { Name = "VoidMist", Transparency = 1 })
		emitter(mist, {
			Rate = 4,
			Lifetime = NumberRange.new(2, 3.5),
			Speed = NumberRange.new(2, 5),
			EmissionDirection = Enum.NormalId.Top,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) }),
			Color = ColorSequence.new(color),
			LightEmission = 1,
			SpreadAngle = Vector2.new(25, 25),
		})
		for _ = 1, math.clamp(math.floor(w / 20), 1, 2) do
			local rx = rng:NextNumber(x1 + 3, x2 - 3)
			local ry = surface + rng:NextNumber(-6, 4)
			self:Deco(Vector3.new(0.15, 4.2, 4.2), CFrame.new(self:W(rx, ry, -4.6)) * FACING, color, NEON, { Name = "RuneRing", Shape = CYL, Transparency = 0.55 })
			self:Deco(Vector3.new(0.9, 0.9, 0.9), CFrame.new(self:W(rx, ry, -4.5)) * CFrame.Angles(0, 0, math.rad(45)), rgb(220, 190, 255), NEON, { Name = "RuneCrystal" })
		end
	else
		-- Laser-Netz mit Emitter-Gehäusen an beiden Enden
		local color = HAZARD_STYLE.Laser.Color
		for _, lz in { -3, 0, 3 } do
			self:Deco(Vector3.new(w, 0.12, 0.12), CFrame.new(self:W(cx, surface + 0.05, lz)), rgb(255, 150, 200), NEON, { Name = "LaserBeam" })
		end
		for _, ex in { x1 - 0.6, x2 + 0.6 } do
			self:Deco(Vector3.new(1.2, 1.6, DEPTH), CFrame.new(self:W(ex, surface - 0.3, 0)), rgb(44, 46, 60), M.Metal, { Name = "LaserHousing" })
		end
		self:Deco(Vector3.new(w, 0.3, DEPTH - 2), CFrame.new(self:W(cx, surface + 1.5, 0)), color, nil, {
			Name = "LaserGlow",
			Transparency = 1,
			Light = { Range = 18, Brightness = 1.4, Color = color },
		})
	end
end

--- Sprunglücke mit Landeplattform.
function MapBuilder:Gap(width: number, dy: number?, landing: number?)
	local rise = dy or 0
	self:_pitHazard(self.X, self.X + width, self.Y + math.min(0, rise))
	self.X += width
	self.Y += rise
	self:Flat(landing or 30)
end

--- Treppe mit `count` Stufen.
function MapBuilder:Steps(count: number, rise: number, run: number)
	local startY = self.Y
	local finalY = startY + rise * count
	local baseY = math.min(startY, finalY) - self.Thickness
	for i = 1, count do
		local top = startY + rise * i
		self:Ground(self.X, self.X + run, top, { Thickness = top - baseY })
		self.X += run
	end
	self.Y = finalY
	self:_node(self.X - run / 2, self.Y)
end

--- Absatz nach unten.
function MapBuilder:Drop(height: number, landing: number?)
	self.Y -= height
	self:Flat(landing or 40)
end

--- Absatz nach oben (Wand der Höhe `height`).
function MapBuilder:Climb(height: number, landing: number?)
	self.Y += height
	local len = landing or 30
	self:Ground(self.X, self.X + len, self.Y, { Thickness = height + self.Thickness })
	self:_node(self.X + len / 2, self.Y)
	self.X += len
end

--- Rampe über `length` Studs mit Höhenänderung `rise`.
function MapBuilder:Ramp(length: number, rise: number)
	self:RampPart(self.X, self.Y, self.X + length, self.Y + rise)
	self.X += length
	self.Y += rise
end

--- Tunnel mit niedriger Decke: nur rutschend passierbar.
--- opts.Lethal = true: Gefahrenstreifen an der Deckenunterkante.
function MapBuilder:SlideTunnel(length: number, opts)
	opts = opts or {}
	local theme = self.Theme
	local x1 = self.X
	local y = self.Y
	self:Flat(length + 8)
	local ceilingBottom = if opts.Lethal then y + 4.4 else y + 3.6
	self:Box(x1 + 4, ceilingBottom, x1 + 4 + length, y + 15.6, { Name = "TunnelCeiling", Color = theme.Wall, Material = self:_wallMaterial() })
	if opts.Lethal then
		self:Hazard(x1 + 4, y + 3.6, x1 + 4 + length, y + 4.4, theme.HazardKind, { Teeth = false })
		if TEETH_KINDS[theme.HazardKind] then
			local style = HAZARD_STYLE[theme.HazardKind]
			self:_teeth(x1 + 4, x1 + 4 + length, y + 4.4, 0.8, style.Color, style.Material, true)
		end
	else
		self:Deco(
			Vector3.new(length, 0.2, 0.2),
			CFrame.new(self:W(x1 + 4 + length / 2, y + 3.7, DEPTH / 2 + 0.1)),
			theme.Accent2 or theme.Accent,
			NEON,
			{ Name = "TunnelGlow" }
		)
	end
	table.insert(self.Ceilings, { X1 = x1 + 4, X2 = x1 + 4 + length, Y = y + 3.6 })
	table.insert(self.Solids, { X1 = x1 + 4, X2 = x1 + 4 + length, Y1 = ceilingBottom, Y2 = y + 15.6 })
	self:_tunnelDecor(x1 + 4, x1 + 4 + length, y, ceilingBottom, y + 15.6, opts.Lethal == true)
end

--- Optik der Tunneldecke: Portalrahmen, Warnstreifen, Lippe, Innenlicht.
function MapBuilder:_tunnelDecor(x1: number, x2: number, floorY: number, bottomY: number, topY: number, lethal: boolean)
	local theme = self.Theme
	local trim, trimMat = self:_t("Trim"), self:_t("TrimMaterial")
	local len = x2 - x1
	local cx = (x1 + x2) / 2
	for _, ex in { x1 + 0.5, x2 - 0.5 } do
		self:Deco(Vector3.new(1, topY - bottomY, 0.3), CFrame.new(self:W(ex, (topY + bottomY) / 2, FACE_Z + 0.15)), trim, trimMat, { Name = "TunnelFrame" })
	end
	self:Deco(Vector3.new(len + 0.3, 0.5, 0.7), CFrame.new(self:W(cx, topY - 0.2, FACE_Z)), trim, trimMat, { Name = "Lip" })
	-- Warnstreifen (gelb/schwarz) knapp über der Deckenunterkante
	local sy = bottomY + (if lethal then 0.55 else 0.75)
	if len > 3 then
		self:Deco(Vector3.new(len - 2, 0.8, 0.1), CFrame.new(self:W(cx, sy, FACE_Z + 0.05)), STRIPE_YELLOW, M.SmoothPlastic, { Name = "TunnelStripe" })
		local sx = x1 + 1.7
		while sx < x2 - 1.7 do
			self:Deco(Vector3.new(1.4, 0.8, 0.12), CFrame.new(self:W(sx, sy, FACE_Z + 0.07)), BLACK, M.SmoothPlastic, { Name = "TunnelStripe" })
			sx += 2.8
		end
	end
	-- Lichtleiste an der hinteren Deckenkante
	local lightColor = if lethal then theme.Hazard or theme.Accent else theme.Accent2 or theme.Accent
	self:Deco(Vector3.new(len, 0.18, 0.3), CFrame.new(self:W(cx, floorY + 3.45, -4.7)), lightColor, NEON, { Name = "TunnelLight" })
end

--- Schacht für Wall-Jumps. Rechts wartet die höhere Ebene.
function MapBuilder:WallClimb(height: number, width: number?, opts)
	opts = opts or {}
	local theme = self.Theme
	local shaft = width or 14
	local x0, y0 = self.X, self.Y
	local wallX = x0 + 4 + shaft
	local wallMat = self:_wallMaterial()
	self:Ground(x0, wallX, y0)
	-- Hängende linke Wand (unten offen, damit man hineinläuft)
	self:Box(x0 + 2, y0 + 7, x0 + 4, y0 + height + 12, { Name = "ClimbWall", Color = theme.Wall, Material = wallMat })
	-- Rechte Wand = Block bis zur oberen Ebene
	self:Box(wallX, y0 - self.Thickness, wallX + 8, y0 + height - 1, { Name = "ClimbBlock", Color = theme.Wall, Material = wallMat })
	self:Ground(wallX, wallX + 8, y0 + height, { Thickness = 1 })
	if opts.Anchor ~= false then
		self:Anchor(x0 + 4 + shaft * 0.5, y0 + height + 12)
	end
	self.X = wallX + 8
	self.Y = y0 + height
	self:_node(wallX + 4, self.Y)

	-- Optik
	table.insert(self.Ceilings, { X1 = x0 + 2, X2 = x0 + 4, Y = y0 + 7 })
	table.insert(self.Solids, { X1 = x0 + 2, X2 = x0 + 4, Y1 = y0 + 7, Y2 = y0 + height + 12 })
	table.insert(self.Solids, { X1 = wallX, X2 = wallX + 8, Y1 = y0 - self.Thickness, Y2 = y0 + height - 1 })
	self:_wallFace(x0 + 2, x0 + 4, y0 + 7, y0 + height + 12)
	self:_wallFace(wallX, wallX + 8, y0 - self.Thickness, y0 + height - 1, { NoCenter = true })
	local arrow = theme.Accent2 or theme.Accent
	for i = 1, 3 do
		self:_chevron(wallX + 4, y0 + height * i / 4, FACE_Z + 0.1, 2, arrow, "Up", "ClimbArrow", 0.4 - i * 0.12)
	end
end

--- Sprungpad, das auf eine höhere Ebene katapultiert.
function MapBuilder:JumpPadUp(height: number, landing: number?)
	local x0, y0 = self.X, self.Y
	local wallX = x0 + 18
	self:Ground(x0, wallX, y0)
	self:JumpPad(x0 + 5, y0, math.sqrt(2 * GRAVITY * (height + 7)))
	self.Y = y0 + height
	local len = landing or 30
	self:Ground(wallX, wallX + len, self.Y, { Thickness = height + self.Thickness })
	self:_node(wallX + len / 2, self.Y)
	self.X = wallX + len
end

--- Breite Lücke, die nur mit dem Greifhaken überwindbar ist.
--- opts: Anchors (Anzahl), AnchorHeight, Rise, Landing
function MapBuilder:GrappleGap(width: number, opts)
	opts = opts or {}
	local x0, y0 = self.X, self.Y
	local count = opts.Anchors or math.max(1, math.floor(width / 45 + 0.5))
	local anchorHeight = opts.AnchorHeight or 24
	for i = 1, count do
		self:Anchor(x0 + width * i / (count + 1), y0 + anchorHeight)
	end
	local rise = opts.Rise or 0
	self:_pitHazard(x0, x0 + width, y0 + math.min(0, rise))
	self.X = x0 + width
	self.Y = y0 + rise
	self:Flat(opts.Landing or 30)
end

--- Gefahrengrube, optional mit Säulen zum Hüpfen. opts: Pillars, PillarRise, Landing
function MapBuilder:Pit(width: number, opts)
	opts = opts or {}
	local x0, y0 = self.X, self.Y
	local pillars = opts.Pillars or 0
	self:_pitHazard(x0, x0 + width, y0)
	if pillars > 0 then
		local spacing = width / (pillars + 1)
		for i = 1, pillars do
			local cx = x0 + spacing * i
			local py = y0 + (if i % 2 == 0 then (opts.PillarRise or 0) else 0)
			local thickness = if self.NoPitHazard then self.Thickness else 24 + (py - y0)
			self:Ground(cx - 2.5, cx + 2.5, py, { Thickness = thickness })
		end
	end
	self.X = x0 + width
	self:Flat(opts.Landing or 30)
end

--- Zeitgesteuerte Gefahrenwand in der Mitte eines Bodenstücks.
function MapBuilder:TimedBarrier(length: number, opts)
	opts = opts or {}
	local theme = self.Theme
	local x0 = self.X
	self:Flat(length)
	local bx = x0 + length / 2
	self:Hazard(bx - 0.8, self.Y, bx + 0.8, self.Y + 16, theme.HazardKind, {
		Period = opts.Period or 2.4,
		OnTime = opts.OnTime or 1.1,
		Offset = opts.Offset or 0,
	})
	self:_barrierDecor(bx, self.Y, theme.HazardKind)
end

--- Optik der Barriere: Emitter-Gehäuse oben und unten, Pylon hinter der Spur.
function MapBuilder:_barrierDecor(bx: number, y: number, kind: string)
	local theme = self.Theme
	local style = HAZARD_STYLE[kind]
	local color = if style then style.Color else theme.Hazard or theme.Accent
	local housing = rgb(44, 46, 58)
	self:Reserve(bx - 4, bx + 4)
	self:Deco(Vector3.new(3, 1.6, DEPTH), CFrame.new(self:W(bx, y + 16.8, 0)), housing, M.Metal, { Name = "BarrierEmitter" })
	self:Deco(Vector3.new(1.9, 0.22, DEPTH - 0.6), CFrame.new(self:W(bx, y + 15.95, 0)), color, NEON, { Name = "BarrierLens" })
	self:Deco(Vector3.new(3.02, 0.35, 0.1), CFrame.new(self:W(bx, y + 17.25, FACE_Z + 0.05)), STRIPE_YELLOW, M.SmoothPlastic, { Name = "BarrierStripe" })
	self:Deco(Vector3.new(3, 0.24, DEPTH), CFrame.new(self:W(bx, y + 0.12, 0)), housing, M.Metal, { Name = "BarrierBase" })
	self:Deco(Vector3.new(1.9, 0.08, DEPTH - 0.6), CFrame.new(self:W(bx, y + 0.27, 0)), color, NEON, { Name = "BarrierLens" })
	self:Deco(Vector3.new(1.1, 17.6, 1.1), CFrame.new(self:W(bx, y + 8.8, -5.7)), housing, M.Metal, { Name = "BarrierPylon" })
	self:Deco(Vector3.new(0.25, 15, 0.12), CFrame.new(self:W(bx, y + 8.4, -5.12)), color, NEON, { Name = "BarrierPylonGlow", Transparency = 0.2 })
	if kind == "Flame" then
		for _, nz in { -3, 0, 3 } do
			self:Deco(Vector3.new(0.7, 0.7, 0.7), CFrame.new(self:W(bx, y + 15.7, nz)) * VERTICAL, rgb(70, 64, 60), M.Metal, { Name = "FlameNozzle", Shape = CYL })
		end
	elseif kind == "Arcane" then
		self:Deco(Vector3.new(1.2, 1.2, 1.2), CFrame.new(self:W(bx, y + 18.4, 0)) * CFrame.Angles(0, 0, math.rad(45)), color, NEON, { Name = "RuneCrystal" })
	elseif kind == "Icicle" then
		self:Deco(Vector3.new(3.4, 0.5, DEPTH + 0.2), CFrame.new(self:W(bx, y + 17.85, 0)), rgb(244, 250, 255), M.Snow, { Name = "SnowCap" })
	elseif kind == "Thorns" then
		for i = 1, 3 do
			self:Deco(Vector3.new(0.5, 1.5, 1.5), CFrame.new(self:W(bx, y + 3 + i * 4, -5.7)) * VERTICAL, rgb(60, 120, 50), M.Grass, { Name = "Vine", Shape = CYL })
		end
	end
end

--- Boden mit Boost-Pad.
function MapBuilder:BoostStrip(length: number, power: number?)
	local x0 = self.X
	self:Flat(length)
	self:BoostPad(x0 + length * 0.2, x0 + length * 0.7, self.Y, power or 80)
end

--- Eisfläche (wenig Reibung, Momentum bleibt erhalten).
function MapBuilder:IceRun(length: number)
	self:Flat(length, { Ice = true })
end

--- Bodenstück mit Item-Boxen.
function MapBuilder:PickupRow(count: number?, length: number?)
	local len = length or 24
	local n = count or 3
	local x0 = self.X
	self:Flat(len)
	for i = 1, n do
		self:PickupSpot(x0 + len * i / (n + 1), self.Y)
	end
end

--- Zwei Routen: oben (schneller, Skill) und unten (sicherer, länger).
--- opts: Length, Depth, Upper = function(builder), Lower = function(builder)
--- Wer oben scheitert, fällt in die untere Route (kein Tod). Am Ende bringt ein
--- Sprungpad die untere Route wieder nach oben.
function MapBuilder:Split(opts)
	local x0, y0 = self.X, self.Y
	local depth = opts.Depth or 28
	local length = opts.Length or 240
	local wasAuto = self.AutoCheckpoints
	self.AutoCheckpoints = false

	-- Untere Route
	self.X = x0
	self.Y = y0 - depth
	self:Ground(x0 - 12, x0, self.Y)
	if opts.Lower then
		opts.Lower(self)
	end
	local lowerEndX, lowerY = self.X, self.Y

	-- Obere Route (dünne Plattformen, keine Grubengefahren)
	local oldThickness, oldNoPit = self.Thickness, self.NoPitHazard
	self.X = x0
	self.Y = y0
	self.Thickness = 3
	self.NoPitHazard = true
	if opts.Upper then
		opts.Upper(self)
	end
	local upperEndX, upperY = self.X, self.Y

	local mergeX = math.max(lowerEndX + 16, upperEndX + 18, x0 + length)
	if upperEndX < mergeX - 18 then
		self:Ground(upperEndX, mergeX - 18, upperY)
	end
	self.Thickness = oldThickness
	self.NoPitHazard = oldNoPit

	-- Untere Route bis zum Sprungpad verlängern
	if lowerEndX < mergeX then
		self:Ground(lowerEndX, mergeX, lowerY)
	end
	local climb = y0 - lowerY
	self:JumpPad(mergeX - 10, lowerY, math.sqrt(2 * GRAVITY * (climb + 9)))

	-- Zusammenführung
	self:Ground(mergeX, mergeX + 40, y0, { Thickness = climb + self.Thickness })
	self.X = mergeX + 40
	self.Y = y0
	self.AutoCheckpoints = wasAuto
	self:Checkpoint(mergeX + 8, y0)
	self:_node(mergeX + 20, y0)
end

--- Ziellinie mit Auslaufzone, Zielbogen, Siegerpodest und Endwand.
function MapBuilder:Finish(length: number?)
	local len = length or 70
	local theme = self.Theme
	local x0 = self.X
	local y = self.Y
	self:Ground(x0, x0 + len, y)
	local fx = x0 + 14
	self.FinishLocalX = fx
	self:Deco(Vector3.new(0.8, 0.14, DEPTH), CFrame.new(self:W(fx, y + 0.08, 0)), rgb(255, 255, 255), NEON, { Name = "FinishLine" })
	self:Box(x0 + len, y - self.Thickness, x0 + len + 8, y + 70, { Name = "EndWall", Color = theme.Wall, Material = self:_wallMaterial() })
	table.insert(self.Solids, { X1 = x0 + len, X2 = x0 + len + 8, Y1 = y - self.Thickness, Y2 = y + 70 })
	self.X = x0 + len

	-- Optik: Zielbogen mit Schachbrett, Schachbrett auf der Bodenkante, Konfetti, Podest
	local gold = rgb(255, 220, 80)
	self:Reserve(fx - 12, fx + 12)
	self:Arch(fx, y, 18, 18, gold, { Label = "ZIEL", Checker = true })
	for row = 0, 1 do
		for col = -3, 2 do
			local white = (row + col) % 2 == 0
			self:Deco(Vector3.new(0.7, 0.7, 0.1), CFrame.new(self:W(fx + col * 0.7 + 0.35, y - 1.25 - row * 0.7, FACE_Z + 0.12)), if white then WHITE else BLACK, M.SmoothPlastic, { Name = "FinishChecker" })
		end
	end
	local confetti = self:Deco(Vector3.new(18, 1, 1.5), CFrame.new(self:W(fx, y + 21, -6.4)), WHITE, nil, { Name = "Confetti", Transparency = 1 })
	emitter(confetti, {
		Rate = 10,
		Lifetime = NumberRange.new(3, 5),
		Speed = NumberRange.new(2, 5),
		EmissionDirection = Enum.NormalId.Bottom,
		Size = NumberSequence.new(0.35),
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
	-- Siegerpodest im Auslauf
	local px = x0 + len - 18
	self:Reserve(px - 6, px + 6)
	for _, step in { { -3, 1.6, rgb(200, 206, 220), "2" }, { 0, 2.6, gold, "1" }, { 3, 1.0, rgb(214, 140, 80), "3" } } do
		local block = self:Deco(Vector3.new(3, step[2], 2.6), CFrame.new(self:W(px + step[1], y + step[2] / 2, -3.6)), step[3], M.Metal, { Name = "Podium" })
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Back
		gui.LightInfluence = 0
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = rgb(30, 30, 40)
		label.Text = step[4]
		label.Parent = gui
		gui.Parent = block
	end
	self:_wallFace(x0 + len, x0 + len + 8, y - self.Thickness, y + 70)
	self:Banner(x0 + len - 4, y, theme.Accent, { Height = 12, Width = 3.4, Color2 = theme.Accent2 })
end

------------------------------------------------------------------------
-- Öffentliche Deko-Bausteine
------------------------------------------------------------------------

--- Laterne im Stil des Themes (Straßenlampe, Arbeitslampe, Feuerschale, Laterne, Fackel).
function MapBuilder:Lamp(x: number, y: number, z: number?, color: Color3?)
	local decor = self.Theme.Decor
	local style = "Street"
	if decor == "Industrial" then
		style = "Work"
	elseif decor == "Sky" then
		style = "Brazier"
	elseif decor == "Glacier" then
		style = "Lantern"
	elseif decor == "Jungle" then
		style = "Torch"
	end
	return self:_lamp(style, x, y, z or -4.4, color)
end

function MapBuilder:_lamp(style: string, x: number, y: number, z: number, color: Color3?)
	local theme = self.Theme
	local list = {}
	local warm = rgb(255, 214, 150)
	if style == "Work" then
		local glow = color or theme.Accent
		piece(self, list, Vector3.new(8, 0.4, 0.4), CFrame.new(self:W(x, y + 4, z)) * VERTICAL, rgb(74, 70, 66), M.Metal, { Name = "LampPole", Shape = CYL })
		piece(self, list, Vector3.new(0.9, 1.1, 0.9), CFrame.new(self:W(x, y + 8.4, z)), glow, NEON, { Name = "LampHead", Light = { Range = 16, Brightness = 1.4, Color = glow } })
		piece(self, list, Vector3.new(1.4, 0.3, 1.4), CFrame.new(self:W(x, y + 9.1, z)), rgb(50, 46, 44), M.Metal, { Name = "LampCap" })
	elseif style == "Brazier" then
		local glow = color or rgb(255, 170, 60)
		piece(self, list, Vector3.new(3.2, 1.3, 1.3), CFrame.new(self:W(x, y + 1.6, z)) * VERTICAL, self:_t("Trim"), M.Marble, { Name = "BrazierStand", Shape = CYL })
		piece(self, list, Vector3.new(0.6, 2.2, 2.2), CFrame.new(self:W(x, y + 3.5, z)) * VERTICAL, rgb(150, 120, 90), M.Sandstone, { Name = "BrazierBowl", Shape = CYL })
		local flame = piece(self, list, Vector3.new(1.1, 1.1, 1.1), CFrame.new(self:W(x, y + 4.2, z)), glow, NEON, { Name = "Flame", Shape = BALL, Light = { Range = 14, Brightness = 1.3, Color = glow } })
		fireEmitter(flame, glow, 0.8)
	elseif style == "Lantern" then
		local glow = color or warm
		piece(self, list, Vector3.new(6.5, 0.3, 0.3), CFrame.new(self:W(x, y + 3.25, z)) * VERTICAL, rgb(70, 52, 42), M.Wood, { Name = "LampPole", Shape = CYL })
		piece(self, list, Vector3.new(0.25, 0.25, 1.4), CFrame.new(self:W(x, y + 6.3, z + 0.6)), rgb(70, 52, 42), M.Wood, { Name = "LampArm" })
		piece(self, list, Vector3.new(0.8, 1.1, 0.8), CFrame.new(self:W(x, y + 5.5, z + 1.2)), glow, NEON, { Name = "Lantern", Light = { Range = 13, Brightness = 1.3, Color = glow } })
		piece(self, list, Vector3.new(1.1, 0.25, 1.1), CFrame.new(self:W(x, y + 6.15, z + 1.2)), rgb(40, 40, 48), M.Metal, { Name = "LanternRoof" })
	elseif style == "Torch" then
		local glow = color or rgb(255, 150, 50)
		piece(self, list, Vector3.new(5.6, 0.4, 0.4), CFrame.new(self:W(x, y + 2.8, z)) * VERTICAL, rgb(184, 150, 92), M.Wood, { Name = "TorchPole", Shape = CYL })
		piece(self, list, Vector3.new(0.6, 1.1, 1.1), CFrame.new(self:W(x, y + 5.7, z)) * VERTICAL, rgb(70, 50, 36), M.Wood, { Name = "TorchBowl", Shape = CYL })
		local flame = piece(self, list, Vector3.new(0.85, 0.85, 0.85), CFrame.new(self:W(x, y + 6.3, z)), glow, NEON, { Name = "Flame", Shape = BALL, Light = { Range = 13, Brightness = 1.3, Color = glow } })
		fireEmitter(flame, glow, 0.7)
	else
		-- Moderne Straßenlampe mit Ausleger Richtung Spur (bleibt hinter der Spielebene)
		local glow = color or (if theme.Decor == "City" then theme.Accent else warm)
		local poleColor = if theme.Decor == "Academy" then rgb(236, 238, 244) else rgb(60, 64, 82)
		piece(self, list, Vector3.new(0.6, 1, 1), CFrame.new(self:W(x, y + 0.3, z)) * VERTICAL, poleColor, M.Metal, { Name = "LampBase", Shape = CYL })
		piece(self, list, Vector3.new(10.5, 0.45, 0.45), CFrame.new(self:W(x, y + 5.25, z)) * VERTICAL, poleColor, M.Metal, { Name = "LampPole", Shape = CYL })
		piece(self, list, Vector3.new(0.3, 0.3, 2.6), CFrame.new(self:W(x, y + 10.35, z + 1.2)), poleColor, M.Metal, { Name = "LampArm" })
		piece(self, list, Vector3.new(1.5, 0.45, 1), CFrame.new(self:W(x, y + 10.3, z + 2.4)), rgb(36, 38, 48), M.Metal, { Name = "LampHead" })
		piece(self, list, Vector3.new(1.3, 0.12, 0.8), CFrame.new(self:W(x, y + 10.02, z + 2.4)), glow, NEON, { Name = "LampGlow", Light = { Range = 16, Brightness = 1.5, Color = glow } })
	end
	return list
end

--- Stütze von yTop bis yBottom. opts: Z, Width, Color, Material,
--- Style ("Girder" | "Pillar" | "Column" | "Ice" | "Stilt"; Standard: Theme.SupportStyle)
function MapBuilder:Pillar(x: number, yTop: number, yBottom: number, opts)
	opts = opts or {}
	local theme = self.Theme
	local style = opts.Style or self:_t("SupportStyle")
	local z = opts.Z or -2.4
	local color = opts.Color or self:_t("Support")
	local material = opts.Material or self:_t("SupportMaterial")
	local trim, trimMat = self:_t("Trim"), self:_t("TrimMaterial")
	local list = {}
	local h = yTop - yBottom
	if h <= 0.2 then
		return list
	end
	local cy = (yTop + yBottom) / 2
	if style == "Stilt" then
		local w = opts.Width or 1.5
		piece(self, list, Vector3.new(h, w, w), CFrame.new(self:W(x, cy, z)) * VERTICAL, color, material, { Name = "Stilt", Shape = CYL })
		if h > 3 then
			piece(self, list, Vector3.new(0.5, w + 0.25, w + 0.25), CFrame.new(self:W(x, yTop - 1.2, z)) * VERTICAL, rgb(196, 160, 100), M.Fabric, { Name = "StiltRope", Shape = CYL })
		end
	elseif style == "Column" then
		local w = opts.Width or 1.8
		piece(self, list, Vector3.new(h, w, w), CFrame.new(self:W(x, cy, z)) * VERTICAL, color, material, { Name = "Column", Shape = CYL })
		piece(self, list, Vector3.new(w + 0.8, 0.6, w + 0.8), CFrame.new(self:W(x, yTop - 0.3, z)), trim, trimMat, { Name = "Capital" })
		piece(self, list, Vector3.new(w + 0.8, 0.6, w + 0.8), CFrame.new(self:W(x, yBottom + 0.3, z)), trim, trimMat, { Name = "Plinth" })
	elseif style == "Girder" then
		local w = opts.Width or 1.3
		piece(self, list, Vector3.new(w, h, w), CFrame.new(self:W(x, cy, z)), color, material, { Name = "Girder" })
		piece(self, list, Vector3.new(w + 1.1, 0.4, w + 1.1), CFrame.new(self:W(x, yTop - 0.2, z)), trim, trimMat, { Name = "GirderCap" })
		if theme.EdgeGlow then
			local glowLen = math.min(h - 1, 10)
			if glowLen > 0.5 then
				piece(self, list, Vector3.new(0.14, glowLen, 0.06), CFrame.new(self:W(x, yTop - 0.6 - glowLen / 2, z + w / 2 + 0.03)), theme.Accent, NEON, { Name = "GirderGlow" })
			end
		end
	elseif style == "Ice" then
		local w = opts.Width or 2.2
		piece(self, list, Vector3.new(w, h, w), CFrame.new(self:W(x, cy, z)), color, material, { Name = "RockPillar" })
		if h > 2.5 then
			piece(self, list, Vector3.new(w + 0.5, 1.2, w + 0.5), CFrame.new(self:W(x, yTop - 1.4, z)), ICICLE, M.Ice, { Name = "IceCollar", Transparency = 0.15 })
		end
	else
		local w = opts.Width or 1.8
		piece(self, list, Vector3.new(w, h, w), CFrame.new(self:W(x, cy, z)), color, material, { Name = "Pillar" })
		piece(self, list, Vector3.new(w + 1, 0.5, w + 1), CFrame.new(self:W(x, yTop - 0.25, z)), trim, trimMat, { Name = "PillarCap" })
		if h > 4 then
			piece(self, list, Vector3.new(w + 0.12, 0.8, w + 0.12), CFrame.new(self:W(x, yTop - 2.2, z)), theme.Accent2 or STRIPE_YELLOW, M.SmoothPlastic, { Name = "PillarBand" })
		end
	end
	return list
end

--- Torbogen hinter der Spur (Läufer laufen davor hindurch).
--- opts: Label (Schriftzug), Checker (Schachbrett-Balken), Z, Depth, FrameColor, Material, LabelWidth
function MapBuilder:Arch(x: number, y: number, width: number, height: number, color: Color3?, opts)
	opts = opts or {}
	local accent = color or self.Theme.Accent
	local z = opts.Z or -6.4
	local depth = opts.Depth or 1.8
	local frame = opts.FrameColor or rgb(46, 50, 66)
	local frameMat = opts.Material or M.Metal
	local list = {}
	local half = width / 2
	for _, side in { -1, 1 } do
		local px = x + side * half
		piece(self, list, Vector3.new(1.8, height, depth), CFrame.new(self:W(px, y + height / 2, z)), frame, frameMat, { Name = "ArchPost" })
		piece(self, list, Vector3.new(0.35, height - 1.2, 0.12), CFrame.new(self:W(px - side * 0.55, y + height / 2, z + depth / 2 + 0.05)), accent, NEON, { Name = "ArchGlow" })
		piece(self, list, Vector3.new(2.8, 0.6, depth + 0.8), CFrame.new(self:W(px, y + 0.3, z)), frame, frameMat, { Name = "ArchFoot" })
	end
	local beamY = y + height + 1.2
	piece(self, list, Vector3.new(width + 1.8, 2.4, depth), CFrame.new(self:W(x, beamY, z)), frame, frameMat, {
		Name = "ArchBeam",
		Light = { Range = 20, Brightness = 1.5, Color = accent },
	})
	if opts.Checker then
		local cell = 1.2
		local cols = math.floor((width + 1.4) / cell)
		local startX = x - cols * cell / 2 + cell / 2
		for row = 0, 1 do
			for col = 0, cols - 1 do
				local white = (row + col) % 2 == 0
				piece(self, list, Vector3.new(cell, 1.05, 0.12), CFrame.new(self:W(startX + col * cell, beamY + 0.55 - row * 1.1, z + depth / 2 + 0.06)), if white then WHITE else BLACK, M.SmoothPlastic, { Name = "ArchChecker" })
			end
		end
	else
		piece(self, list, Vector3.new(width + 1, 0.3, 0.12), CFrame.new(self:W(x, beamY - 0.8, z + depth / 2 + 0.06)), accent, NEON, { Name = "ArchGlow" })
	end
	if opts.Label then
		self:Sign(x, beamY + 4.4, opts.Label, nil, { Width = opts.LabelWidth or 14, Height = 4.4, Color = accent, Style = "Banner", Z = z })
	end
	return list
end

--- Fahne an einem Mast (Tuch hängt rechts am Querbalken).
--- opts: Height, Width, Z, Color2 (Zierstreifen), PoleColor
function MapBuilder:Banner(x: number, y: number, color: Color3?, opts)
	opts = opts or {}
	local theme = self.Theme
	local cloth = color or theme.Accent
	local h = opts.Height or 9
	local w = opts.Width or 2.6
	local z = opts.Z or -4.4
	local decor = theme.Decor
	local poleColor = opts.PoleColor or (if decor == "Jungle" or decor == "Sky" then rgb(120, 92, 62) else rgb(70, 72, 86))
	local list = {}
	piece(self, list, Vector3.new(h, 0.3, 0.3), CFrame.new(self:W(x, y + h / 2, z)) * VERTICAL, poleColor, M.Metal, { Name = "BannerPole", Shape = CYL })
	piece(self, list, Vector3.new(0.55, 0.55, 0.55), CFrame.new(self:W(x, y + h + 0.2, z)), rgb(255, 206, 90), M.Metal, { Name = "BannerFinial", Shape = BALL })
	piece(self, list, Vector3.new(w + 0.5, 0.2, 0.2), CFrame.new(self:W(x + w / 2, y + h - 0.35, z)), poleColor, M.Metal, { Name = "BannerBar" })
	local clothH = h * 0.5
	local clothY = y + h - 0.45 - clothH / 2
	piece(self, list, Vector3.new(w, clothH, 0.12), CFrame.new(self:W(x + w / 2 + 0.15, clothY, z)), cloth, M.Fabric, { Name = "BannerCloth" })
	piece(self, list, Vector3.new(w, clothH * 0.14, 0.14), CFrame.new(self:W(x + w / 2 + 0.15, clothY - clothH * 0.22, z)), opts.Color2 or WHITE, M.Fabric, { Name = "BannerStripe" })
	return list
end

--- Baum. opts: Kind ("Round" | "Pine" | "Palm" | "Jungle"), Scale, Height (Stammhöhe), Leaf (Farbe)
function MapBuilder:Tree(x: number, y: number, z: number?, opts)
	opts = opts or {}
	local decor = self.Theme.Decor
	local kind = opts.Kind
	if not kind then
		kind = if decor == "Glacier" then "Pine" elseif decor == "Jungle" then "Jungle" else "Round"
	end
	local s = opts.Scale or 1
	local leaf = opts.Leaf or self:_t("Leaf")
	local rng = self.Rng
	local tz = z or BACK_Z
	local list = {}
	local bark = rgb(104, 74, 50)
	if kind == "Pine" then
		piece(self, list, Vector3.new(1.8 * s, 0.7 * s, 0.7 * s), CFrame.new(self:W(x, y + 0.9 * s, tz)) * VERTICAL, bark, M.Wood, { Name = "Trunk", Shape = CYL })
		local widths = { 5.2, 4, 2.8 }
		local heights = { 3.2, 3, 2.8 }
		for i = 1, 3 do
			local w, h = widths[i] * s, heights[i] * s
			local color = if decor == "Glacier" and i == 3 then leaf:Lerp(WHITE, 0.55) else jitter(rng, leaf, 0.08)
			self:_triangle(x, y + (1.3 + (i - 1) * 2.1) * s, w, h, w * 0.85, tz, color, M.Grass, false, "PineTier", list)
		end
	elseif kind == "Jungle" then
		local trunkH = opts.Height or 10 * s
		local d = 1.1 * s
		piece(self, list, Vector3.new(trunkH, d, d), CFrame.new(self:W(x, y + trunkH / 2, tz)) * VERTICAL, rgb(96, 70, 48), M.Wood, { Name = "Trunk", Shape = CYL })
		local top = y + trunkH
		piece(self, list, Vector3.new(7 * s, 3.4 * s, 6 * s), CFrame.new(self:W(x, top + 0.8 * s, tz)), jitter(rng, leaf, 0.12), M.Grass, { Name = "Crown", Mesh = SPHERE })
		piece(self, list, Vector3.new(5 * s, 2.6 * s, 4.5 * s), CFrame.new(self:W(x + 2.6 * s, top - 1.2 * s, tz + 0.4 * s)), jitter(rng, leaf, 0.14), M.Grass, { Name = "Crown", Mesh = SPHERE })
		if rng:NextNumber() < 0.6 then
			piece(self, list, Vector3.new(4.4 * s, 2.2 * s, 4 * s), CFrame.new(self:W(x - 2.4 * s, top - 0.4 * s, tz - 0.4 * s)), jitter(rng, leaf, 0.14), M.Grass, { Name = "Crown", Mesh = SPHERE })
		end
		if rng:NextNumber() < 0.6 then
			local vl = rng:NextNumber(3, 7) * s
			piece(self, list, Vector3.new(vl, 0.18 * s, 0.18 * s), CFrame.new(self:W(x + 1.8 * s, top - 1.4 * s - vl / 2, tz + 1.2 * s)) * VERTICAL, shade(leaf, 0.75), M.Grass, { Name = "Vine", Shape = CYL })
		end
	elseif kind == "Palm" then
		local segH = 3 * s
		local px, py = x, y
		for i = 1, 3 do
			local tilt = math.rad(7 * i)
			piece(self, list, Vector3.new(segH + 0.2 * s, 0.8 * s, 0.8 * s), CFrame.new(self:W(px + math.sin(tilt) * segH / 2, py + math.cos(tilt) * segH / 2, tz)) * CFrame.Angles(0, 0, math.rad(90) - tilt), rgb(150, 120, 80), M.Wood, { Name = "PalmTrunk", Shape = CYL })
			px += math.sin(tilt) * segH
			py += math.cos(tilt) * segH
		end
		for _, angle in { 205, 145, 90, 35, -25 } do
			local leafLen = 4.2 * s
			piece(self, list, Vector3.new(leafLen, 0.2 * s, 1.1 * s), CFrame.new(self:W(px, py, tz)) * CFrame.Angles(0, 0, math.rad(angle)) * CFrame.new(leafLen / 2, 0, 0), jitter(rng, leaf, 0.1), M.Grass, { Name = "PalmLeaf" })
		end
	else
		piece(self, list, Vector3.new(4 * s, 0.75 * s, 0.75 * s), CFrame.new(self:W(x, y + 2 * s, tz)) * VERTICAL, bark, M.Wood, { Name = "Trunk", Shape = CYL })
		local main = 4.6 * s
		piece(self, list, Vector3.new(main, main, main), CFrame.new(self:W(x, y + 5.4 * s, tz)), jitter(rng, leaf, 0.1), M.Grass, { Name = "Crown", Shape = BALL })
		for _, side in { -1, 1 } do
			local d = 3.4 * s
			piece(self, list, Vector3.new(d, d, d), CFrame.new(self:W(x + side * 1.7 * s, y + 4.5 * s, tz + 0.2 * side * s)), jitter(rng, leaf, 0.12), M.Grass, { Name = "Crown", Shape = BALL })
		end
	end
	return list
end

--- Wolke aus Kugeln mit flacher Unterseite. opts: Color, Transparency, Puffs
function MapBuilder:Cloud(x: number, y: number, z: number, scale: number?, opts)
	opts = opts or {}
	local s = scale or 1
	local rng = self.Rng
	local color = opts.Color or WHITE
	local transparency = opts.Transparency or 0
	local puffs = opts.Puffs or 3
	local list = {}
	for i = 1, puffs do
		local d = s * rng:NextNumber(7, 11) * (if i == 1 or i == puffs then 0.8 else 1.15)
		local ox = (i - (puffs + 1) / 2) * s * 5.5
		piece(self, list, Vector3.new(d, d, d), CFrame.new(self:W(x + ox, y + d * 0.18, z)), color, M.SmoothPlastic, { Name = "Cloud", Shape = BALL, Transparency = transparency })
	end
	piece(self, list, Vector3.new(puffs * 5.5 * s + 6 * s, 4 * s, 8 * s), CFrame.new(self:W(x, y, z)), color, M.SmoothPlastic, { Name = "Cloud", Mesh = SPHERE, Transparency = transparency })
	return list
end

--- Hochhaus mit Fenstern und Dachaufbau. z = Mitte des Gebäudes in der Tiefe.
--- opts: Color, Material, Lights ({Color3}), WindowStyle (1 Bänder, 2 Streifen, 3 Einzelfenster), Roof (false = ohne)
function MapBuilder:Building(x: number, z: number, baseY: number, width: number, height: number, depth: number, opts)
	opts = opts or {}
	local theme, rng = self.Theme, self.Rng
	local back = theme.Backdrop or {}
	local color = opts.Color or back.Near or rgb(40, 40, 60)
	local lights = opts.Lights or back.Lights or { theme.Accent }
	local list = {}
	local topY = baseY + height
	local front = z + depth / 2
	piece(self, list, Vector3.new(width, height, depth), CFrame.new(self:W(x, baseY + height / 2, z)), color, opts.Material or M.Concrete, { Name = "Building" })
	local warm = lights[1]
	local style = opts.WindowStyle or rng:NextInteger(1, 3)
	if style == 1 then
		local bands = math.clamp(math.floor(height / 22), 1, 4)
		local wy = topY - 6
		for _ = 1, bands do
			if wy < baseY + 4 then
				break
			end
			local lit = if rng:NextNumber() < 0.75 then warm else lights[rng:NextInteger(1, #lights)]
			piece(self, list, Vector3.new(width * 0.84, 0.8, 0.2), CFrame.new(self:W(x, wy, front + 0.05)), lit, NEON, { Name = "Window", Transparency = 0.15 })
			wy -= rng:NextNumber(8, 14)
		end
	elseif style == 2 then
		local strips = math.clamp(math.floor(width / 9), 1, 3)
		local lit = lights[rng:NextInteger(1, #lights)]
		local stripH = math.min(height * 0.5, 60)
		for i = 1, strips do
			local sx = x - width / 2 + width * i / (strips + 1)
			piece(self, list, Vector3.new(0.7, stripH, 0.2), CFrame.new(self:W(sx, topY - 4 - stripH / 2, front + 0.05)), lit, NEON, { Name = "Window", Transparency = 0.2 })
		end
	else
		local maxDrop = math.max(4.5, math.min(height - 4, 50))
		for _ = 1, rng:NextInteger(3, 6) do
			local lit = if rng:NextNumber() < 0.7 then warm else lights[rng:NextInteger(1, #lights)]
			piece(self, list, Vector3.new(rng:NextNumber(1.6, 3), 1.2, 0.2), CFrame.new(self:W(x + rng:NextNumber(-width * 0.38, width * 0.38), topY - rng:NextNumber(4, maxDrop), front + 0.05)), lit, NEON, { Name = "Window", Transparency = 0.1 })
		end
	end
	piece(self, list, Vector3.new(width + 0.8, 0.8, depth + 0.8), CFrame.new(self:W(x, topY - 0.4, z)), shade(color, 1.18), M.Metal, { Name = "Roof" })
	if opts.Roof ~= false then
		local roll = rng:NextNumber()
		if roll < 0.35 then
			local h = rng:NextNumber(8, 16)
			local ax = x + rng:NextNumber(-width / 4, width / 4)
			piece(self, list, Vector3.new(h, 0.4, 0.4), CFrame.new(self:W(ax, topY + h / 2, z)) * VERTICAL, rgb(130, 134, 150), M.Metal, { Name = "Antenna", Shape = CYL })
			piece(self, list, Vector3.new(0.8, 0.8, 0.8), CFrame.new(self:W(ax, topY + h + 0.3, z)), rgb(255, 60, 60), NEON, { Name = "AntennaLight", Shape = BALL })
		elseif roll < 0.55 then
			local bw = width * 0.7
			local bh = width * 0.32
			local by = topY + bh / 2 + 1.2
			piece(self, list, Vector3.new(bw + 0.8, bh + 0.8, 0.6), CFrame.new(self:W(x, by, front - 1)), rgb(28, 28, 40), M.Metal, { Name = "RoofSign" })
			piece(self, list, Vector3.new(bw, bh, 0.2), CFrame.new(self:W(x, by, front - 0.62)), lights[rng:NextInteger(1, #lights)], NEON, { Name = "RoofSignGlow", Transparency = 0.25 })
		elseif roll < 0.7 then
			piece(self, list, Vector3.new(width * 0.4, 3, depth * 0.4), CFrame.new(self:W(x + rng:NextNumber(-width / 5, width / 5), topY + 1.5, z)), shade(color, 0.9), M.Metal, { Name = "RoofBox" })
		end
	end
	return list
end

--- Torbögen über geraden Abschnitten (mind. 24 Studs eben, genug Kopffreiheit),
--- gleichmäßig zwischen Start und Ziel verteilt. Vor Decorate() aufrufen, damit dort
--- keine Requisiten in den Pfosten stehen. opts wie bei Arch.
function MapBuilder:Gates(count: number, color: Color3?, opts)
	local startX = self.StartLocalX + 60
	local endX = (self.FinishLocalX or self.MaxX) - 60
	if endX <= startX then
		return
	end
	local accent = color or self.Theme.Accent2 or self.Theme.Accent
	for i = 1, count do
		local target = startX + (endX - startX) * (i - 0.5) / count
		for offset = 0, 120, 4 do
			local x = target + offset
			local y = self:FloorAt(x)
			if
				y
				and self:FloorAt(x - 12) == y
				and self:FloorAt(x + 12) == y
				and not self:_isReserved(x - 11, x + 11)
				and self:_clearanceAt(x, y) > 24
			then
				self:Arch(x, y, 20, 17, accent, opts)
				self:Reserve(x - 11, x + 11)
				break
			end
		end
	end
end

--- Wasserfall (Glas + Gischt) von yTop um `height` nach unten.
function MapBuilder:Waterfall(x: number, yTop: number, z: number, width: number, height: number)
	local list = {}
	piece(self, list, Vector3.new(width, height, 0.6), CFrame.new(self:W(x, yTop - height / 2, z)), rgb(180, 226, 255), M.Glass, { Name = "Waterfall", Transparency = 0.35 })
	piece(self, list, Vector3.new(width * 0.5, height, 0.7), CFrame.new(self:W(x, yTop - height / 2, z + 0.1)), WHITE, M.SmoothPlastic, { Name = "WaterfallFoam", Transparency = 0.55 })
	local mist = piece(self, list, Vector3.new(width, 1, 2), CFrame.new(self:W(x, yTop - height, z)), WHITE, nil, { Name = "WaterfallMist", Transparency = 1 })
	emitter(mist, {
		Rate = 5,
		Lifetime = NumberRange.new(2, 3),
		Speed = NumberRange.new(2, 4),
		EmissionDirection = Enum.NormalId.Top,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 8) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(WHITE),
		SpreadAngle = Vector2.new(60, 60),
	})
	return list
end

------------------------------------------------------------------------
-- Requisiten (Prop)
------------------------------------------------------------------------

local PROPS = {}

PROPS.Crate = function(B, x, y, z, opts)
	local rng, decor = B.Rng, B.Theme.Decor
	local list = {}
	local color, material, band = rgb(158, 112, 66), M.WoodPlanks, rgb(104, 72, 42)
	if decor == "City" or decor == "Hub" then
		color, material, band = (B.Theme.Accent2 or B.Theme.Accent):Lerp(rgb(40, 40, 60), 0.55), M.Metal, rgb(30, 32, 44)
	elseif decor == "Industrial" then
		color, material, band = rgb(118, 92, 70), M.CorrodedMetal, rgb(240, 180, 46)
	end
	color = opts.Color or color
	local s = (opts.Scale or 1) * rng:NextNumber(2.2, 2.9)
	z = math.max(z, -4.9 + s / 2)
	local base = CFrame.new(B:W(x, y + s / 2, z)) * CFrame.Angles(0, math.rad(rng:NextNumber(-12, 12)), 0)
	piece(B, list, Vector3.new(s, s, s), base, color, material, { Name = "Crate" })
	piece(B, list, Vector3.new(s + 0.08, 0.32, s + 0.08), base, band, M.Metal, { Name = "CrateBand" })
	if rng:NextNumber() < 0.35 then
		local s2 = s * 0.7
		local top = CFrame.new(B:W(x + rng:NextNumber(-0.4, 0.4), y + s + s2 / 2, z)) * CFrame.Angles(0, math.rad(rng:NextNumber(-25, 25)), 0)
		piece(B, list, Vector3.new(s2, s2, s2), top, shade(color, 1.12), material, { Name = "Crate" })
	end
	return list
end

PROPS.Barrel = function(B, x, y, z, opts)
	local rng = B.Rng
	local list = {}
	local palette = { rgb(200, 62, 40), rgb(236, 172, 40), rgb(60, 112, 176), rgb(70, 140, 80) }
	z = math.max(z, -3.8)
	for i = 1, if rng:NextNumber() < 0.35 then 2 else 1 do
		local bx = x + (i - 1) * 2.4
		local color = opts.Color or palette[rng:NextInteger(1, #palette)]
		piece(B, list, Vector3.new(3, 2.2, 2.2), CFrame.new(B:W(bx, y + 1.5, z)) * VERTICAL, color, M.Metal, { Name = "Barrel", Shape = CYL })
		piece(B, list, Vector3.new(0.3, 2.34, 2.34), CFrame.new(B:W(bx, y + 2.1, z)) * VERTICAL, shade(color, 0.6), M.Metal, { Name = "BarrelRing", Shape = CYL })
		if B.Theme.Decor == "Industrial" and rng:NextNumber() < 0.4 then
			piece(B, list, Vector3.new(0.1, 1.7, 1.7), CFrame.new(B:W(bx, y + 3.02, z)) * VERTICAL, B.Theme.Accent, NEON, { Name = "BarrelGlow", Shape = CYL })
		end
	end
	return list
end

PROPS.Lamp = function(B, x, y, z, opts)
	return B:Lamp(x, y, math.max(z, -4.6), opts.Color)
end

PROPS.Torch = function(B, x, y, z, opts)
	return B:_lamp("Torch", x, y, z, opts.Color)
end

PROPS.Bush = function(B, x, y, z, opts)
	local rng = B.Rng
	local list = {}
	local leaf = opts.Color or B:_t("Leaf")
	local r = rng:NextNumber(2.2, 3.1) * (opts.Scale or 1)
	z = math.max(z, -4.9 + r / 2)
	for i = 1, 3 do
		local d = r * (if i == 2 then 1 else rng:NextNumber(0.6, 0.8))
		piece(B, list, Vector3.new(d, d, d), CFrame.new(B:W(x + (i - 2) * r * 0.55, y + d * 0.32, z + rng:NextNumber(-0.3, 0.3))), jitter(rng, leaf, 0.12), M.Grass, { Name = "Bush", Shape = BALL })
	end
	local decor = B.Theme.Decor
	if (decor == "Sky" or decor == "Jungle" or decor == "Academy") and rng:NextNumber() < 0.45 then
		local bloom = if rng:NextNumber() < 0.5 then rgb(255, 120, 170) else rgb(255, 225, 90)
		for _, ox in { -0.5, 0.6 } do
			piece(B, list, Vector3.new(0.55, 0.55, 0.55), CFrame.new(B:W(x + ox * r, y + r * 0.75, z + r * 0.3)), bloom, M.SmoothPlastic, { Name = "Blossom", Shape = BALL })
		end
	end
	return list
end

PROPS.Rock = function(B, x, y, z, opts)
	local rng, decor = B.Rng, B.Theme.Decor
	local list = {}
	local material, color = M.Rock, rgb(124, 120, 112)
	if decor == "Glacier" then
		material, color = M.Slate, rgb(96, 112, 136)
	elseif decor == "Sky" then
		material, color = M.Limestone, rgb(206, 194, 166)
	elseif decor == "Industrial" then
		material, color = M.Basalt, rgb(72, 62, 60)
	elseif decor == "Jungle" then
		color = rgb(112, 114, 100)
	end
	color = opts.Color or color
	local s = opts.Scale or 1
	local w, h, d = rng:NextNumber(2.2, 3.4) * s, rng:NextNumber(1.4, 2.3) * s, rng:NextNumber(1.6, 2.4) * s
	z = math.max(z, -4.9 + d / 2)
	local cf = CFrame.new(B:W(x, y + h * 0.35, z)) * CFrame.Angles(math.rad(rng:NextNumber(-8, 8)), math.rad(rng:NextNumber(-30, 30)), math.rad(rng:NextNumber(-12, 12)))
	piece(B, list, Vector3.new(w, h, d), cf, color, material, { Name = "Rock" })
	piece(B, list, Vector3.new(w * 0.5, h * 0.55, d * 0.6), CFrame.new(B:W(x + w * 0.6, y + h * 0.2, z + 0.3)) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 90)), math.rad(rng:NextNumber(-20, 20))), shade(color, 0.9), material, { Name = "Rock" })
	if decor == "Glacier" then
		piece(B, list, Vector3.new(w * 0.9, 0.35, d * 0.9), cf * CFrame.new(0, h / 2, 0), rgb(246, 250, 255), M.Snow, { Name = "SnowCap" })
	elseif decor == "Jungle" then
		piece(B, list, Vector3.new(w * 0.8, 0.3, d * 0.8), cf * CFrame.new(0, h / 2, 0), rgb(80, 150, 60), M.Grass, { Name = "Moss" })
	end
	return list
end

PROPS.Crystal = function(B, x, y, z, opts)
	local rng, decor = B.Rng, B.Theme.Decor
	local list = {}
	local color = opts.Color or (if decor == "Glacier" then rgb(140, 230, 255) elseif decor == "Sky" then (B.Theme.Accent2 or B.Theme.Accent) else B.Theme.Accent)
	local s = opts.Scale or 1
	z = math.max(z, -4.9 + 0.8 * s)
	local shards = { { 0, 1, 0, 0.8 }, { -0.6, 0.7, -22, 0.6 }, { 0.65, 0.55, 25, 0.5 } }
	for i, shard in shards do
		local h = rng:NextNumber(2.6, 4.6) * shard[2] * s
		local w = shard[4] * s
		local material = if i == 1 then NEON else M.Glass
		piece(B, list, Vector3.new(w, h, w), CFrame.new(B:W(x + shard[1] * s, y + h * 0.4, z)) * CFrame.Angles(0, 0, math.rad(shard[3])) * CFrame.Angles(0, math.rad(45), 0), color, material, { Name = "Crystal", Transparency = if i == 1 then 0.1 else 0.2 })
	end
	return list
end

PROPS.Pine = function(B, x, y, z, opts)
	local s = (opts.Scale or 1) * B.Rng:NextNumber(0.75, 1)
	return B:Tree(x, y, math.max(z, -4.9 + 2.2 * s), { Kind = "Pine", Scale = s })
end

PROPS.Tree = function(B, x, y, z, opts)
	local s = (opts.Scale or 1) * B.Rng:NextNumber(0.55, 0.75)
	return B:Tree(x, y, math.max(z, -4.9 + 2.4 * s), { Scale = s })
end

PROPS.SnowMound = function(B, x, y, z, opts)
	local rng = B.Rng
	local list = {}
	local s = opts.Scale or 1
	local d = rng:NextNumber(2.6, 3.6) * s
	z = math.max(z, -4.9 + d / 2)
	piece(B, list, Vector3.new(d, d, d), CFrame.new(B:W(x, y + d * 0.1, z)), rgb(244, 248, 255), M.Snow, { Name = "SnowMound", Shape = BALL })
	local d2 = d * 0.65
	piece(B, list, Vector3.new(d2, d2, d2), CFrame.new(B:W(x + d * 0.55, y, z + 0.2)), rgb(236, 244, 255), M.Snow, { Name = "SnowMound", Shape = BALL })
	return list
end

PROPS.IceBlock = function(B, x, y, z, opts)
	local rng = B.Rng
	local list = {}
	local s = (opts.Scale or 1) * rng:NextNumber(2, 2.7)
	z = math.max(z, -4.9 + s * 0.7)
	piece(B, list, Vector3.new(s, s, s), CFrame.new(B:W(x, y + s * 0.4, z)) * CFrame.Angles(math.rad(rng:NextNumber(-10, 10)), math.rad(rng:NextNumber(0, 90)), math.rad(rng:NextNumber(-10, 10))), rgb(176, 224, 255), M.Ice, { Name = "IceBlock", Transparency = 0.15 })
	if rng:NextNumber() < 0.5 then
		local s2 = s * 0.6
		piece(B, list, Vector3.new(s2, s2, s2), CFrame.new(B:W(x + s * 0.7, y + s2 * 0.4, z + 0.3)) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 90)), 0), rgb(200, 236, 255), M.Ice, { Name = "IceBlock", Transparency = 0.15 })
	end
	return list
end

PROPS.Column = function(B, x, y, z, _opts)
	local rng = B.Rng
	local list = {}
	local marble, trim = rgb(240, 236, 226), B:_t("Trim")
	z = math.max(z, -3.7)
	local broken = rng:NextNumber() < 0.45
	local h = if broken then rng:NextNumber(2.5, 4.5) else rng:NextNumber(6.5, 8.8)
	piece(B, list, Vector3.new(2.4, 0.7, 2.4), CFrame.new(B:W(x, y + 0.35, z)), trim, M.Marble, { Name = "Plinth" })
	piece(B, list, Vector3.new(h, 1.5, 1.5), CFrame.new(B:W(x, y + 0.7 + h / 2, z)) * VERTICAL, marble, M.Marble, { Name = "Column", Shape = CYL })
	if broken then
		piece(B, list, Vector3.new(1.8, 1.5, 1.5), CFrame.new(B:W(x + 2.3, y + 0.75, z + 0.4)) * CFrame.Angles(0, math.rad(rng:NextNumber(-25, 25)), 0), shade(marble, 0.92), M.Marble, { Name = "ColumnPiece", Shape = CYL })
	else
		piece(B, list, Vector3.new(2.3, 0.6, 2.3), CFrame.new(B:W(x, y + 1 + h, z)), trim, M.Marble, { Name = "Capital" })
	end
	return list
end

PROPS.Urn = function(B, x, y, z, _opts)
	local rng = B.Rng
	local list = {}
	local clay = rgb(196, 112, 76)
	z = math.max(z, -3.9)
	piece(B, list, Vector3.new(1.8, 1.8, 1.8), CFrame.new(B:W(x, y + 0.95, z)), clay, M.Sandstone, { Name = "Urn", Shape = BALL })
	piece(B, list, Vector3.new(0.6, 0.9, 0.9), CFrame.new(B:W(x, y + 2, z)) * VERTICAL, shade(clay, 0.9), M.Sandstone, { Name = "UrnNeck", Shape = CYL })
	piece(B, list, Vector3.new(0.16, 1.25, 1.25), CFrame.new(B:W(x, y + 2.33, z)) * VERTICAL, rgb(236, 220, 190), M.Marble, { Name = "UrnRim", Shape = CYL })
	if rng:NextNumber() < 0.45 then
		piece(B, list, Vector3.new(1.5, 1.5, 1.5), CFrame.new(B:W(x, y + 2.8, z)), jitter(rng, B:_t("Leaf"), 0.1), M.Grass, { Name = "UrnPlant", Shape = BALL })
	end
	return list
end

PROPS.Flower = function(B, x, y, z, _opts)
	local rng = B.Rng
	local list = {}
	z = math.max(z, -3.8)
	local colors = { rgb(255, 120, 170), rgb(255, 222, 80), rgb(255, 255, 255), rgb(190, 120, 255), rgb(255, 104, 80) }
	piece(B, list, Vector3.new(1.8, 1.8, 1.8), CFrame.new(B:W(x, y + 0.3, z)), jitter(rng, B:_t("Leaf"), 0.1), M.Grass, { Name = "FlowerLeaves", Shape = BALL })
	for _, offset in { { -0.55, 0.95 }, { 0.15, 1.25 }, { 0.65, 0.9 } } do
		local d = rng:NextNumber(0.55, 0.8)
		piece(B, list, Vector3.new(d, d, d), CFrame.new(B:W(x + offset[1], y + offset[2], z + 0.5)), colors[rng:NextInteger(1, #colors)], M.SmoothPlastic, { Name = "Blossom", Shape = BALL })
	end
	return list
end

PROPS.Fern = function(B, x, y, z, _opts)
	local rng = B.Rng
	local list = {}
	z = math.max(z, -4.2)
	for _, angle in { -52, -18, 18, 52 } do
		local len = rng:NextNumber(2.4, 3.4)
		piece(B, list, Vector3.new(0.7, len, 0.16), CFrame.new(B:W(x, y, z)) * CFrame.Angles(0, math.rad(rng:NextNumber(-25, 25)), math.rad(angle)) * CFrame.new(0, len / 2, 0), jitter(rng, B:_t("Leaf"), 0.15), M.Grass, { Name = "Fern" })
	end
	return list
end

PROPS.Mushroom = function(B, x, y, z, _opts)
	local rng = B.Rng
	local list = {}
	z = math.max(z, -3.6)
	local caps = { rgb(215, 50, 50), rgb(240, 130, 40), rgb(170, 90, 220) }
	for i = 1, if rng:NextNumber() < 0.5 then 2 else 1 do
		local s = if i == 1 then 1 else 0.6
		local mx = x + (i - 1) * 1.7
		local h = rng:NextNumber(1.3, 2.1) * s
		local cap = caps[rng:NextInteger(1, #caps)]
		piece(B, list, Vector3.new(h, 0.55 * s, 0.55 * s), CFrame.new(B:W(mx, y + h / 2, z)) * VERTICAL, rgb(236, 226, 200), M.SmoothPlastic, { Name = "MushroomStem", Shape = CYL })
		piece(B, list, Vector3.new(2.4 * s, 1.1 * s, 2.4 * s), CFrame.new(B:W(mx, y + h, z)), cap, M.SmoothPlastic, { Name = "MushroomCap", Mesh = SPHERE })
		if i == 1 then
			for _, ox in { -0.5, 0.45 } do
				piece(B, list, Vector3.new(0.35, 0.35, 0.35), CFrame.new(B:W(mx + ox, y + h + 0.2, z + 1)), WHITE, M.SmoothPlastic, { Name = "MushroomDot", Shape = BALL })
			end
		end
	end
	return list
end

PROPS.Log = function(B, x, y, z, _opts)
	local rng = B.Rng
	local list = {}
	z = math.max(z, -4.1)
	local len = rng:NextNumber(4, 6)
	local cf = CFrame.new(B:W(x, y + 0.65, z)) * CFrame.Angles(0, math.rad(rng:NextNumber(-10, 10)), 0)
	piece(B, list, Vector3.new(len, 1.3, 1.3), cf, rgb(110, 78, 50), M.Wood, { Name = "Log", Shape = CYL })
	piece(B, list, Vector3.new(len * 0.55, 0.25, 0.9), cf * CFrame.new(rng:NextNumber(-0.5, 0.5), 0.65, 0), rgb(80, 150, 60), M.Grass, { Name = "Moss" })
	return list
end

PROPS.Vent = function(B, x, y, z, _opts)
	local list = {}
	z = math.max(z, -3.7)
	piece(B, list, Vector3.new(3, 2, 2.2), CFrame.new(B:W(x, y + 1, z)), rgb(92, 98, 118), M.Metal, { Name = "Vent" })
	piece(B, list, Vector3.new(0.15, 1.5, 1.5), CFrame.new(B:W(x - 0.5, y + 1, z + 1.12)) * FACING, rgb(40, 42, 52), M.DiamondPlate, { Name = "VentFan", Shape = CYL })
	piece(B, list, Vector3.new(0.3, 0.3, 0.1), CFrame.new(B:W(x + 1.05, y + 1.55, z + 1.12)), B.Theme.Accent, NEON, { Name = "VentLight" })
	return list
end

PROPS.Barrier = function(B, x, y, z, _opts)
	local list = {}
	z = math.max(z, -4.2)
	local concrete = rgb(170, 172, 182)
	piece(B, list, Vector3.new(4, 0.9, 1.4), CFrame.new(B:W(x, y + 0.45, z)), concrete, M.Concrete, { Name = "Barrier" })
	piece(B, list, Vector3.new(4, 0.8, 0.8), CFrame.new(B:W(x, y + 1.3, z)), concrete, M.Concrete, { Name = "Barrier" })
	piece(B, list, Vector3.new(4.02, 0.14, 0.06), CFrame.new(B:W(x, y + 1.35, z + 0.42)), B.Theme.Accent2 or B.Theme.Accent, NEON, { Name = "BarrierStripe" })
	return list
end

PROPS.HoloSign = function(B, x, y, z, _opts)
	local rng, theme = B.Rng, B.Theme
	local list = {}
	z = math.max(z, -4.6)
	local color = if rng:NextNumber() < 0.5 then theme.Accent else theme.Accent2 or theme.Accent
	piece(B, list, Vector3.new(0.25, 3.2, 0.25), CFrame.new(B:W(x, y + 1.6, z)), rgb(54, 58, 72), M.Metal, { Name = "HoloPost" })
	piece(B, list, Vector3.new(3, 1.7, 0.1), CFrame.new(B:W(x, y + 3.9, z - 0.08)), rgb(24, 26, 36), M.Metal, { Name = "HoloFrame" })
	piece(B, list, Vector3.new(2.7, 1.4, 0.1), CFrame.new(B:W(x, y + 3.9, z + 0.02)), color, NEON, { Name = "HoloPanel", Transparency = 0.35 })
	return list
end

PROPS.Antenna = function(B, x, y, z, _opts)
	local rng = B.Rng
	local list = {}
	z = math.max(z, -4.3)
	local h = rng:NextNumber(6.5, 9)
	piece(B, list, Vector3.new(0.8, 0.4, 0.8), CFrame.new(B:W(x, y + 0.2, z)), rgb(60, 62, 74), M.Metal, { Name = "AntennaBase" })
	piece(B, list, Vector3.new(h, 0.24, 0.24), CFrame.new(B:W(x, y + h / 2, z)) * VERTICAL, rgb(150, 155, 170), M.Metal, { Name = "Antenna", Shape = CYL })
	piece(B, list, Vector3.new(0.2, 1.6, 1.6), CFrame.new(B:W(x + 0.6, y + h * 0.6, z)) * CFrame.Angles(0, 0, math.rad(-30)), rgb(200, 204, 214), M.Metal, { Name = "AntennaDish", Shape = CYL })
	piece(B, list, Vector3.new(0.45, 0.45, 0.45), CFrame.new(B:W(x, y + h + 0.2, z)), rgb(255, 60, 60), NEON, { Name = "AntennaLight", Shape = BALL })
	return list
end

PROPS.Pipe = function(B, x, y, z, _opts)
	local rng = B.Rng
	local list = {}
	z = math.max(z, -4.3)
	local len = rng:NextNumber(5, 8)
	piece(B, list, Vector3.new(len, 1, 1), CFrame.new(B:W(x, y + 1.7, z)), rgb(150, 132, 112), M.Metal, { Name = "Pipe", Shape = CYL })
	for _, side in { -1, 1 } do
		piece(B, list, Vector3.new(0.35, 1.4, 0.35), CFrame.new(B:W(x + side * (len / 2 - 0.6), y + 0.7, z)), rgb(70, 64, 60), M.Metal, { Name = "PipeSupport" })
	end
	piece(B, list, Vector3.new(0.3, 1.25, 1.25), CFrame.new(B:W(x - len * 0.25, y + 1.7, z)), rgb(110, 96, 82), M.Metal, { Name = "PipeFlange", Shape = CYL })
	piece(B, list, Vector3.new(0.15, 1.1, 1.1), CFrame.new(B:W(x + len * 0.15, y + 1.7, z + 0.62)) * FACING, rgb(200, 50, 40), M.Metal, { Name = "PipeValve", Shape = CYL })
	return list
end

PROPS.Girder = function(B, x, y, z, _opts)
	local list = {}
	z = math.max(z, -4.4)
	local steel = rgb(230, 175, 45)
	for _, side in { -1, 1 } do
		piece(B, list, Vector3.new(0.4, 5.5, 0.4), CFrame.new(B:W(x + side * 1.6, y + 2.75, z)), steel, M.Metal, { Name = "GirderPost" })
	end
	piece(B, list, Vector3.new(3.8, 0.4, 0.4), CFrame.new(B:W(x, y + 5.5, z)), steel, M.Metal, { Name = "GirderBeam" })
	piece(B, list, Vector3.new(0.25, 6, 0.25), CFrame.new(B:W(x, y + 2.75, z)) * CFrame.Angles(0, 0, -math.atan2(3.2, 5.1)), shade(steel, 0.8), M.Metal, { Name = "GirderBrace" })
	return list
end

PROPS.WarningLamp = function(B, x, y, z, _opts)
	local list = {}
	z = math.max(z, -4.5)
	local glow = B.Theme.Accent
	piece(B, list, Vector3.new(0.3, 2.4, 0.3), CFrame.new(B:W(x, y + 1.2, z)), rgb(50, 48, 50), M.Metal, { Name = "WarningPost" })
	piece(B, list, Vector3.new(0.75, 0.75, 0.75), CFrame.new(B:W(x, y + 2.7, z)), glow, NEON, { Name = "WarningLight", Shape = BALL, Light = { Range = 10, Brightness = 1.2, Color = glow } })
	piece(B, list, Vector3.new(0.6, 0.2, 0.6), CFrame.new(B:W(x, y + 3.15, z)), rgb(50, 48, 50), M.Metal, { Name = "WarningCap" })
	return list
end

PROPS.Bench = function(B, x, y, z, _opts)
	local list = {}
	z = math.max(z, -4.3)
	local hub = B.Theme.Decor == "Hub"
	local seat = if hub then rgb(70, 76, 100) else rgb(150, 105, 65)
	local seatMat = if hub then M.Metal else M.WoodPlanks
	piece(B, list, Vector3.new(3.4, 0.25, 1), CFrame.new(B:W(x, y + 0.95, z)), seat, seatMat, { Name = "BenchSeat" })
	piece(B, list, Vector3.new(3.4, 0.8, 0.16), CFrame.new(B:W(x, y + 1.55, z - 0.42)), seat, seatMat, { Name = "BenchBack" })
	for _, side in { -1, 1 } do
		piece(B, list, Vector3.new(0.25, 0.85, 0.9), CFrame.new(B:W(x + side * 1.4, y + 0.42, z)), rgb(44, 46, 56), M.Metal, { Name = "BenchLeg" })
	end
	return list
end

PROPS.Planter = function(B, x, y, z, _opts)
	local rng, theme = B.Rng, B.Theme
	local list = {}
	z = math.max(z, -3.8)
	local boxColor = if theme.Decor == "Academy" then rgb(236, 238, 244) else rgb(52, 56, 76)
	piece(B, list, Vector3.new(2.8, 1.2, 2), CFrame.new(B:W(x, y + 0.6, z)), boxColor, M.Concrete, { Name = "Planter" })
	if theme.EdgeGlow then
		piece(B, list, Vector3.new(2.9, 0.12, 0.1), CFrame.new(B:W(x, y + 1.1, z + 1.02)), theme.Accent, NEON, { Name = "PlanterGlow" })
	end
	piece(B, list, Vector3.new(2.4, 2.4, 2.4), CFrame.new(B:W(x, y + 1.8, z)), jitter(rng, B:_t("Leaf"), 0.1), M.Grass, { Name = "PlanterBush", Shape = BALL })
	return list
end

PROPS.Cone = function(B, x, y, z, _opts)
	local rng = B.Rng
	local list = {}
	z = math.max(z, -4.1)
	local orange = rgb(255, 120, 30)
	for i = 1, if rng:NextNumber() < 0.5 then 2 else 1 do
		local cx = x + (i - 1) * 2
		piece(B, list, Vector3.new(1.5, 0.15, 1.5), CFrame.new(B:W(cx, y + 0.075, z)), orange, M.SmoothPlastic, { Name = "ConeBase" })
		piece(B, list, Vector3.new(0.8, 1.05, 1.05), CFrame.new(B:W(cx, y + 0.55, z)) * VERTICAL, orange, M.SmoothPlastic, { Name = "Cone", Shape = CYL })
		piece(B, list, Vector3.new(0.35, 0.8, 0.8), CFrame.new(B:W(cx, y + 1.12, z)) * VERTICAL, WHITE, M.SmoothPlastic, { Name = "ConeBand", Shape = CYL })
		piece(B, list, Vector3.new(0.4, 0.55, 0.55), CFrame.new(B:W(cx, y + 1.48, z)) * VERTICAL, orange, M.SmoothPlastic, { Name = "Cone", Shape = CYL })
	end
	return list
end

PROPS.Hurdle = function(B, x, y, z, _opts)
	local list = {}
	z = math.max(z, -4.4)
	for _, side in { -1, 1 } do
		piece(B, list, Vector3.new(0.25, 1.7, 0.25), CFrame.new(B:W(x + side * 1.6, y + 0.85, z)), WHITE, M.SmoothPlastic, { Name = "HurdlePost" })
		piece(B, list, Vector3.new(0.25, 0.12, 1), CFrame.new(B:W(x + side * 1.6, y + 0.06, z)), rgb(40, 42, 52), M.Metal, { Name = "HurdleFoot" })
	end
	piece(B, list, Vector3.new(3.6, 0.32, 0.16), CFrame.new(B:W(x, y + 1.6, z)), WHITE, M.SmoothPlastic, { Name = "HurdleBar" })
	piece(B, list, Vector3.new(1.2, 0.34, 0.18), CFrame.new(B:W(x, y + 1.6, z)), rgb(230, 50, 60), M.SmoothPlastic, { Name = "HurdleStripe" })
	return list
end

PROPS.Banner = function(B, x, y, z, opts)
	local theme = B.Theme
	local color = opts.Color or (if B.Rng:NextNumber() < 0.5 then theme.Accent else theme.Accent2 or theme.Accent)
	return B:Banner(x, y, color, { Z = math.max(z, -4.6), Color2 = WHITE })
end

-- Große Wahrzeichen für den Hintergrund (y = Fußpunkt, opts.Scale)
PROPS.Temple = function(B, x, y, z, opts)
	local s = opts.Scale or 1
	local list = {}
	local stone = opts.Color or rgb(120, 126, 104)
	for i = 0, 4 do
		local w = (40 - i * 7) * s
		local h = 6 * s
		piece(B, list, Vector3.new(w, h, w * 0.7), CFrame.new(B:W(x, y + h * (i + 0.5), z)), shade(stone, 1 - i * 0.04), M.Cobblestone, { Name = "Temple" })
		piece(B, list, Vector3.new(w + 0.4, 0.8 * s, w * 0.7 + 0.4), CFrame.new(B:W(x, y + h * (i + 1) - 0.2 * s, z)), rgb(78, 140, 62), M.Grass, { Name = "TempleMoss" })
	end
	piece(B, list, Vector3.new(8 * s, 8 * s, 8 * s), CFrame.new(B:W(x, y + 34 * s, z)), shade(stone, 0.85), M.Cobblestone, { Name = "TempleShrine" })
	piece(B, list, Vector3.new(3 * s, 4 * s, 0.4), CFrame.new(B:W(x, y + 33 * s, z + 4 * s + 0.1)), B.Theme.Accent2 or B.Theme.Accent, NEON, { Name = "TempleDoor", Light = { Range = 30, Brightness = 2, Color = B.Theme.Accent2 or B.Theme.Accent } })
	return list
end

PROPS.RuinArch = function(B, x, y, z, opts)
	local s = opts.Scale or 1
	local list = {}
	local marble = opts.Color or rgb(238, 232, 220)
	local h = 34 * s
	for _, side in { -1, 1 } do
		local px = x + side * 12 * s
		piece(B, list, Vector3.new(h, 4.2 * s, 4.2 * s), CFrame.new(B:W(px, y + h / 2, z)) * VERTICAL, marble, M.Marble, { Name = "RuinColumn", Shape = CYL })
		piece(B, list, Vector3.new(6 * s, 2 * s, 6 * s), CFrame.new(B:W(px, y + h + s, z)), shade(marble, 0.95), M.Marble, { Name = "RuinCapital" })
	end
	piece(B, list, Vector3.new(26 * s, 4 * s, 5 * s), CFrame.new(B:W(x - 2 * s, y + h + 4 * s, z)) * CFrame.Angles(0, 0, math.rad(4)), marble, M.Marble, { Name = "RuinLintel" })
	piece(B, list, Vector3.new(8 * s, 2.5 * s, 4 * s), CFrame.new(B:W(x + 4 * s, y + h + 7.2 * s, z)) * CFrame.Angles(0, 0, math.rad(-10)), shade(marble, 0.9), M.Marble, { Name = "RuinBlock" })
	local vine = rgb(90, 160, 70)
	for i = 1, 3 do
		local vl = (6 + i * 3) * s
		piece(B, list, Vector3.new(vl, 0.6 * s, 0.6 * s), CFrame.new(B:W(x - 9 * s + i * 6 * s, y + h + 2 * s - vl / 2, z + 2.6 * s)) * VERTICAL, vine, M.Grass, { Name = "RuinVine", Shape = CYL })
	end
	return list
end

PROPS.Tower = function(B, x, y, z, opts)
	local s = opts.Scale or 1
	local theme = B.Theme
	local list = {}
	local body = opts.Color or rgb(30, 30, 52)
	local h = 260 * s
	local w = 40 * s
	piece(B, list, Vector3.new(w, h, w * 0.8), CFrame.new(B:W(x, y + h / 2, z)), body, M.Glass, { Name = "Tower" })
	piece(B, list, Vector3.new(w * 0.6, 60 * s, w * 0.5), CFrame.new(B:W(x, y + h + 30 * s, z)), shade(body, 1.15), M.Metal, { Name = "TowerTop" })
	piece(B, list, Vector3.new(50 * s, 1.2, 1.2), CFrame.new(B:W(x, y + h + 85 * s, z)) * VERTICAL, rgb(200, 204, 220), M.Metal, { Name = "TowerSpire", Shape = CYL })
	piece(B, list, Vector3.new(2.5, 2.5, 2.5), CFrame.new(B:W(x, y + h + 111 * s, z)), rgb(255, 60, 80), NEON, { Name = "TowerBeacon", Shape = BALL })
	for _, side in { -1, 1 } do
		piece(B, list, Vector3.new(1.2, h * 0.9, 0.4), CFrame.new(B:W(x + side * w * 0.42, y + h * 0.55, z + w * 0.4 + 0.2)), if side < 0 then theme.Accent else theme.Accent2 or theme.Accent, NEON, { Name = "TowerGlow" })
	end
	for i = 1, 6 do
		piece(B, list, Vector3.new(w * 0.7, 1, 0.3), CFrame.new(B:W(x, y + h - i * 18 * s, z + w * 0.4 + 0.15)), rgb(255, 214, 140), NEON, { Name = "TowerWindow", Transparency = 0.15 })
	end
	return list
end

--- Stellt eine Requisite auf (y = Bodenoberkante, z Standard -4.2).
function MapBuilder:Prop(kind: string, x: number, y: number, z: number?, opts)
	local build = PROPS[kind]
	if not build then
		warn("[MapBuilder] Unbekannte Requisite: " .. tostring(kind))
		return {}
	end
	return build(self, x, y, z or BACK_Z, opts or {})
end

------------------------------------------------------------------------
-- Terrain (nur hinter der Spur; wird aufgezeichnet und beim Entladen gelöscht)
------------------------------------------------------------------------

local function terrainMaterial(material)
	if material and TERRAIN_MATERIALS[material] then
		return material
	end
	return M.Rock
end

--- Prüft die vordere Grenze (lokales z) einer Terrain-Füllung.
function MapBuilder:_terrainOk(maxZ: number, what: string): boolean
	if maxZ > TERRAIN_MAX_Z then
		warn(string.format("[MapBuilder] Terrain '%s' reicht bis z = %.1f (erlaubt ≤ %d) – übersprungen", what, maxZ, TERRAIN_MAX_Z))
		return false
	end
	return true
end

function MapBuilder:_fill(record, write)
	table.insert(self.TerrainFills, record)
	local ok, err = pcall(write, workspace.Terrain)
	if not ok then
		warn("[MapBuilder] Terrain-Füllung fehlgeschlagen: " .. tostring(err))
	end
end

--- Terrain-Quader (Mittelpunkt x, y, z; optional gedreht).
function MapBuilder:TerrainBlock(x: number, y: number, z: number, size: Vector3, material: Enum.Material?, rotation: CFrame?)
	local extent = if rotation then size.Magnitude / 2 else size.Z / 2
	if not self:_terrainOk(z + extent, "Block") then
		return
	end
	local cframe = CFrame.new(self:W(x, y, z)) * (rotation or CFrame.identity)
	local mat = terrainMaterial(material)
	self:_fill({ Kind = "Block", CFrame = cframe, Size = size }, function(terrain)
		terrain:FillBlock(cframe, size, mat)
	end)
end

--- Terrain-Kugel.
function MapBuilder:TerrainBall(x: number, y: number, z: number, radius: number, material: Enum.Material?)
	if not self:_terrainOk(z + radius, "Ball") then
		return
	end
	local center = self:W(x, y, z)
	local mat = terrainMaterial(material)
	self:_fill({ Kind = "Ball", Center = center, Radius = radius }, function(terrain)
		terrain:FillBall(center, radius, mat)
	end)
end

--- Terrain-Zylinder (Achse senkrecht, optional gedreht).
function MapBuilder:TerrainCylinder(x: number, y: number, z: number, height: number, radius: number, material: Enum.Material?, rotation: CFrame?)
	local extent = if rotation then math.sqrt(radius * radius + height * height / 4) else radius
	if not self:_terrainOk(z + extent, "Cylinder") then
		return
	end
	local cframe = CFrame.new(self:W(x, y, z)) * (rotation or CFrame.identity)
	local mat = terrainMaterial(material)
	self:_fill({ Kind = "Cylinder", CFrame = cframe, Height = height, Radius = radius }, function(terrain)
		terrain:FillCylinder(cframe, height, radius, mat)
	end)
end

--- Terrain-Keil (Form wie WedgePart; hohe Seite lokal bei +Z).
function MapBuilder:TerrainWedge(x: number, y: number, z: number, size: Vector3, material: Enum.Material?, rotation: CFrame?)
	local extent = if rotation then size.Magnitude / 2 else size.Z / 2
	if not self:_terrainOk(z + extent, "Wedge") then
		return
	end
	local cframe = CFrame.new(self:W(x, y, z)) * (rotation or CFrame.identity)
	local mat = terrainMaterial(material)
	self:_fill({ Kind = "Wedge", CFrame = cframe, Size = size }, function(terrain)
		terrain:FillWedge(cframe, size, mat)
	end)
end

--- Berg aus Terrain mit Gipfel bei baseY + height.
--- opts: Style ("Round" = Kugeln, "Peak" = spitzer Grat aus Keilen), Material, Cap (Gipfelmaterial),
--- CapRatio (Anteil der Gipfelkappe, Standard 0.3), Depth (Tiefe beim Grat, Standard 40)
function MapBuilder:Mountain(x: number, z: number, baseY: number, height: number, width: number, opts)
	opts = opts or {}
	local terrain = self.Theme.Terrain or {}
	local material = opts.Material or terrain.Peak or M.Rock
	local cap = opts.Cap
	local topY = baseY + height
	if opts.Style == "Peak" then
		local depth = opts.Depth or 40
		local half = width / 2
		self:TerrainWedge(x - half / 2, baseY + height / 2, z, Vector3.new(depth, height, half), material, CFrame.Angles(0, math.rad(90), 0))
		self:TerrainWedge(x + half / 2, baseY + height / 2, z, Vector3.new(depth, height, half), material, CFrame.Angles(0, math.rad(-90), 0))
		if cap then
			local ch = height * (opts.CapRatio or 0.3)
			local cw = half * ch / height
			local cy = topY - ch / 2 + 0.8
			self:TerrainWedge(x - cw / 2, cy, z, Vector3.new(depth + 2, ch, cw), cap, CFrame.Angles(0, math.rad(90), 0))
			self:TerrainWedge(x + cw / 2, cy, z, Vector3.new(depth + 2, ch, cw), cap, CFrame.Angles(0, math.rad(-90), 0))
		end
	else
		-- Kuppe aus einer Kugel (Radius = halbe Breite), darunter gestapelte Kugeln bis zum Fuß
		local rng = self.Rng
		local r = width / 2
		local cy = topY - r
		self:TerrainBall(x, cy, z, r, material)
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		self:TerrainBall(x + side * r * 0.75, cy - r * 0.3, z, r * 0.7, material)
		local guard = 0
		while cy - r > baseY and guard < 5 do
			guard += 1
			cy -= r * 1.1
			self:TerrainBall(x + rng:NextNumber(-r * 0.2, r * 0.2), cy, z, r * 1.05, material)
		end
		if cap then
			self:TerrainBall(x, topY - r * 0.26, z, r * 0.32, cap)
		end
	end
end

--- Schwebende Insel aus Terrain: flache Grasdecke, darunter spitz zulaufender Fels.
--- opts: Top, Rock, Cliff (Materialien). Liefert die Oberkante.
function MapBuilder:Island(x: number, y: number, z: number, radius: number, opts)
	opts = opts or {}
	local terrain = self.Theme.Terrain or {}
	local top = opts.Top or terrain.Top or M.Grass
	local rock = opts.Rock or terrain.Ground or M.Rock
	local cliff = opts.Cliff or terrain.Cliff or rock
	local r = radius
	self:TerrainCylinder(x, y - 2, z, 4, r, top)
	self:TerrainCylinder(x, y - 5.5, z, 4, r * 0.96, rock)
	self:TerrainBall(x, y - r * 0.85, z, r * 0.8, rock)
	self:TerrainBall(x + r * 0.12, y - r * 1.4, z, r * 0.5, cliff)
	self:TerrainBall(x - r * 0.08, y - r * 1.85, z, r * 0.26, cliff)
	return y
end

--- Terrain-Streifen über die gesamte sichtbare Breite (in Abschnitten ≤ 512 Studs).
function MapBuilder:_terrainStrip(zFront: number, zBack: number, yBottom: number, yTop: number, material)
	local x, xEnd = self:_span(zBack)
	local depth = math.abs(zFront - zBack)
	local zMid = (zFront + zBack) / 2
	while x < xEnd do
		local w = math.min(512, xEnd - x)
		self:TerrainBlock(x + w / 2, (yBottom + yTop) / 2, zMid, Vector3.new(w, yTop - yBottom, depth), material)
		x += w
	end
end

--- X-Bereich, der bei Tiefe z im Bild sein kann (inkl. Kamera-Zoom).
function MapBuilder:_span(z: number): (number, number)
	local pad = (80 + math.abs(z)) * 1.25
	return self.MinX - pad, self.MaxX + pad
end

--- Niedrigste und höchste Bodenoberkante der Strecke.
function MapBuilder:_floorRange(): (number, number)
	local lo, hi = math.huge, -math.huge
	for _, p in self.Platforms do
		lo = math.min(lo, p.Y)
		hi = math.max(hi, p.Y)
	end
	if lo > hi then
		return self.MinY, self.MaxY
	end
	return lo, hi
end

------------------------------------------------------------------------
-- Automatische Bodenverzierung
------------------------------------------------------------------------

--- Fasst angrenzende Böden gleicher Höhe zu "Läufen" zusammen.
function MapBuilder:_collectRuns()
	local list = {}
	for _, p in self.Platforms do
		if not p.NoDress and p.X2 - p.X1 > 0.05 then
			table.insert(list, p)
		end
	end
	table.sort(list, function(a, b)
		if a.X1 ~= b.X1 then
			return a.X1 < b.X1
		end
		return a.Y > b.Y
	end)
	local runs = {}
	for _, p in list do
		local merged = false
		for i = #runs, math.max(1, #runs - 8), -1 do
			local run = runs[i]
			if math.abs(run.Y - p.Y) < 0.01 and p.X1 <= run.X2 + 0.05 and run.Ice == p.Ice and run.Upper == p.Upper then
				run.X2 = math.max(run.X2, p.X2)
				table.insert(run.Parts, p)
				merged = true
				break
			end
		end
		if not merged then
			table.insert(runs, { X1 = p.X1, X2 = p.X2, Y = p.Y, Ice = p.Ice, Upper = p.Upper, Parts = { p } })
		end
	end
	return runs
end

--- Bodenteil eines Laufs an Position x (sonst das nächstgelegene).
function MapBuilder:_partAt(run, x: number)
	local best, bestDist = run.Parts[1], math.huge
	for _, p in run.Parts do
		if x >= p.X1 and x <= p.X2 then
			return p
		end
		local dist = math.min(math.abs(x - p.X1), math.abs(x - p.X2))
		if dist < bestDist then
			best, bestDist = p, dist
		end
	end
	return best
end

--- Wand/Block, der bei x direkt unter der Höhe y beginnt.
function MapBuilder:_solidAt(x: number, y: number)
	for _, s in self.Solids do
		if x >= s.X1 - 0.01 and x <= s.X2 + 0.01 and s.Y2 >= y - 0.5 and s.Y1 < y - 0.01 then
			return s
		end
	end
	return nil
end

--- Liegt unter (x, bottomY) mindestens `gap` Studs nichts?
function MapBuilder:_freeBelow(x: number, bottomY: number, gap: number): boolean
	local below = self:_topAt(x, bottomY - 0.05, true)
	return below == nil or below < bottomY - gap
end

--- Höchste begehbare Oberkante (Boden, Rampe, Wand/Block) unter bottomY im ganzen
--- Bereich x1..x2 – nil, wenn darunter nur Abgrund ist. Eine Rampe, die bis an
--- bottomY heranreicht, zählt mit bottomY (kein Platz für Deko).
function MapBuilder:_highestBelow(x1: number, x2: number, bottomY: number): number?
	local limit = bottomY - 0.05
	local best = nil
	local function consider(y)
		y = math.min(y, limit)
		if best == nil or y > best then
			best = y
		end
	end
	for _, p in self.Platforms do
		if p.X2 >= x1 and p.X1 <= x2 and p.Y < limit then
			consider(p.Y)
		end
	end
	for _, r in self.Ramps do
		if r.X2 >= x1 and r.X1 <= x2 then
			local span = math.max(r.X2 - r.X1, 0.01)
			local ya = r.Y1 + (r.Y2 - r.Y1) * (math.max(r.X1, x1) - r.X1) / span
			local yb = r.Y1 + (r.Y2 - r.Y1) * (math.min(r.X2, x2) - r.X1) / span
			if math.min(ya, yb) < limit then
				consider(math.max(ya, yb))
			end
		end
	end
	for _, s in self.Solids do
		if s.X2 >= x1 and s.X1 <= x2 and s.Y1 < limit then
			consider(s.Y2)
		end
	end
	return best
end

--- Freie Höhe über dem Boden (Decken, höhere Plattformen, Wände).
function MapBuilder:_clearanceAt(x: number, y: number): number
	local best = math.huge
	for _, c in self.Ceilings do
		if x >= c.X1 - 1.5 and x <= c.X2 + 1.5 and c.Y > y then
			best = math.min(best, c.Y - y)
		end
	end
	for _, p in self.Platforms do
		if x >= p.X1 - 1.5 and x <= p.X2 + 1.5 and p.Bottom > y + 0.1 then
			best = math.min(best, p.Bottom - y)
		end
	end
	for _, s in self.Solids do
		if x + 1.8 >= s.X1 and x - 1.8 <= s.X2 and s.Y2 > y + 0.2 then
			if s.Y1 <= y + 0.5 then
				return 0
			end
			best = math.min(best, s.Y1 - y)
		end
	end
	return best
end

--- Verzierung eines Laufs: Lippe, Leuchtkante, Bänder, Rippen, Ecken, Unterseite.
function MapBuilder:_dressRun(run)
	local theme, rng = self.Theme, self.Rng
	local len = run.X2 - run.X1
	if len < 0.5 then
		return
	end
	local cx = (run.X1 + run.X2) / 2
	local y = run.Y
	local style = self:_t("RibStyle")
	local trim = if run.Ice then ICE_TRIM else self:_t("Trim")
	local trimMat = if run.Ice then M.Ice else self:_t("TrimMaterial")
	local detail, detailMat = self:_t("Detail"), self:_t("DetailMaterial")
	local minThick = math.huge
	for _, p in run.Parts do
		minThick = math.min(minThick, p.Y - p.Bottom)
	end

	-- Lippe an der vorderen Oberkante (bei Gras etwas überhängend)
	local lipDepth = if style == "Root" then 1 else 0.7
	self:Deco(Vector3.new(len, 0.5, lipDepth), CFrame.new(self:W(cx, y - 0.2, FACE_Z + lipDepth / 2 - 0.35)), trim, trimMat, { Name = "Lip" })
	if theme.EdgeGlow and minThick >= 0.9 then
		self:Deco(Vector3.new(len, 0.16, 0.12), CFrame.new(self:W(cx, y - 0.62, FACE_Z + 0.36)), theme.Accent, NEON, { Name = "EdgeGlow" })
	end

	-- Zierbänder
	if style == "Strata" then
		if minThick >= 4 then
			self:Deco(Vector3.new(len, 0.6, 0.14), CFrame.new(self:W(cx, y - 2.4, FACE_Z + 0.07)), detail, detailMat, { Name = "Strata" })
		end
		if minThick >= 6.5 then
			self:Deco(Vector3.new(len, 0.4, 0.12), CFrame.new(self:W(cx, y - 4.9, FACE_Z + 0.06)), shade(theme.Ground, 1.25), M.Ice, { Name = "Strata" })
		end
	elseif style ~= "Root" and minThick >= 3.5 then
		self:Deco(Vector3.new(len, 0.34, 0.14), CFrame.new(self:W(cx, y - 1.75, FACE_Z + 0.07)), detail, detailMat, { Name = "Band" })
	end
	if style == "Pipe" and minThick >= 5.5 and len >= 6 then
		self:Deco(Vector3.new(len, 0.7, 0.7), CFrame.new(self:W(cx, y - 3.6, FACE_Z + 0.3)), rgb(150, 136, 120), M.Metal, { Name = "FacePipe", Shape = CYL })
	end

	-- Rippen / Fugen / Wurzeln auf der Vorderseite
	local spacing = RIB_SPACING[style] or 12
	if spacing > 0 and len >= spacing * 0.6 then
		local rx = run.X1 + spacing / 2
		while rx < run.X2 - 0.5 do
			local px = if style == "Root" then rx + rng:NextNumber(-2, 2) else rx
			px = math.clamp(px, run.X1 + 0.6, run.X2 - 0.6)
			local part = self:_partAt(run, px)
			if style == "Root" then
				local length = math.min(rng:NextNumber(1.6, 4.4), y - part.Bottom - 0.9)
				if length > 0.6 then
					local isRoot = rng:NextNumber() < 0.55
					self:Deco(
						Vector3.new(length, 0.3, 0.3),
						CFrame.new(self:W(px, y - 0.6 - length / 2, FACE_Z + 0.2)) * CFrame.Angles(0, 0, math.rad(90 + rng:NextNumber(-12, 12))),
						if isRoot then detail else shade(self:_t("Leaf"), 0.85),
						if isRoot then M.Wood else M.Grass,
						{ Name = "Root", Shape = CYL }
					)
				end
			else
				local thin = style == "Joint"
				local top = y - (if thin then 2 else 2.1)
				local bottom = math.max(part.Bottom + (if thin then 0.3 else 0.5), y - (if thin then 9 else 8))
				if top - bottom > 0.8 then
					if thin then
						self:Deco(Vector3.new(0.18, top - bottom, 0.1), CFrame.new(self:W(px, (top + bottom) / 2, FACE_Z + 0.05)), shade(theme.Ground, 0.78), M.SmoothPlastic, { Name = "Joint" })
					else
						self:Deco(Vector3.new(0.55, top - bottom, 0.14), CFrame.new(self:W(px, (top + bottom) / 2, FACE_Z + 0.07)), detail, detailMat, { Name = "Rib" })
					end
				end
			end
			rx += spacing
		end
	end

	-- Eckleisten an freiliegenden Enden
	for side = 1, 2 do
		local ex = if side == 1 then run.X1 else run.X2
		local neighbor = self:_topAt(if side == 1 then ex - 0.6 else ex + 0.6, nil, true)
		if neighbor == nil or neighbor < y - 0.4 then
			local part = self:_partAt(run, if side == 1 then ex + 0.1 else ex - 0.1)
			local low = math.max(part.Bottom, neighbor or -math.huge)
			local h = math.min(y - 0.45 - low, 14)
			if h >= 0.6 then
				self:Deco(Vector3.new(0.7, h, 0.75), CFrame.new(self:W(ex + (if side == 1 then 0.35 else -0.35), y - 0.45 - h / 2, FACE_Z)), trim, trimMat, { Name = "Corner" })
			end
		end
	end

	local supportStyle = self:_t("SupportStyle")
	if supportStyle == "Hanging" or supportStyle == "Ice" or supportStyle == "Stilt" then
		self:_underside(run, supportStyle)
	end
end

--- Platz, den eine tiefere Route unter hängender Deko braucht (Figur + Sprung).
local RUNNER_CLEARANCE = 12

--- Wie weit darf Deko unter bottomY im Bereich x1..x2 hängen? Liefert die maximale
--- Länge (math.huge über dem Abgrund) und ob darunter eine begehbare Fläche liegt.
function MapBuilder:_hangRoom(x1: number, x2: number, bottomY: number): (number, boolean)
	local below = self:_highestBelow(x1, x2, bottomY)
	if below == nil then
		return math.huge, false
	end
	return bottomY - below - RUNNER_CLEARANCE, true
end

--- Details unter freiliegenden Unterseiten (hängende Felsen, Eiszapfen, Wurzeln).
--- Liegt darunter eine tiefere Route, bleibt über ihr RUNNER_CLEARANCE frei und die
--- Felsen rücken hinter die Spielebene (Vorderkante z ≤ -1.7), damit sie niemanden verdecken.
function MapBuilder:_underside(run, style: string)
	local rng = self.Rng
	local len = run.X2 - run.X1
	if style == "Hanging" then
		local rock, rockMat = self:_t("Support"), self:_t("SupportMaterial")
		local segments = math.max(1, math.ceil(len / 36))
		local segLen = len / segments
		if segLen < 4 then
			return
		end
		for i = 1, segments do
			local sx = run.X1 + segLen * (i - 0.5)
			local part = self:_partAt(run, sx)
			local w = segLen * 0.9
			local room, routeBelow = self:_hangRoom(sx - w / 2, sx + w / 2, part.Bottom)
			if room >= 4 then
				local h = math.min(math.clamp(segLen * 0.55, 4, 24) * rng:NextNumber(0.8, 1.2), room)
				local z1, depth1, z2, depth2, vineZ = -0.6, DEPTH - 1.6, -1.2, DEPTH - 3, 3.2
				if routeBelow then
					z1, depth1, z2, depth2, vineZ = -3.2, 3, -3.4, 2.4, -2.2
				end
				self:_triangle(sx, part.Bottom + 0.2, w, h, depth1, z1, rock, rockMat, true, "HangingRock")
				if rng:NextNumber() < 0.55 then
					local h2 = math.min(h * rng:NextNumber(1.2, 1.6), room)
					self:_triangle(sx + w * rng:NextNumber(-0.25, 0.25), part.Bottom + 0.2, w * 0.45, h2, depth2, z2, shade(rock, 0.85), rockMat, true, "HangingRock")
				end
				if rng:NextNumber() < 0.6 then
					local vl = math.min(rng:NextNumber(3, 8), room)
					self:Deco(Vector3.new(vl, 0.3, 0.3), CFrame.new(self:W(sx + rng:NextNumber(-w * 0.3, w * 0.3), part.Bottom - vl / 2, vineZ)) * VERTICAL, shade(self:_t("Leaf"), 0.85), M.Grass, { Name = "Vine", Shape = CYL })
				end
			end
		end
	elseif style == "Ice" then
		local ix = run.X1 + rng:NextNumber(1, 4)
		local flip = false
		while ix < run.X2 - 1 do
			local part = self:_partAt(run, ix)
			local w = rng:NextNumber(0.8, 1.4)
			local h = rng:NextNumber(1.4, 4.2)
			local room = self:_hangRoom(ix - w, ix + w, part.Bottom)
			h = math.min(h, room)
			if h >= 1.2 then
				self:Deco(
					Vector3.new(w, h, w),
					CFrame.new(self:W(ix, part.Bottom - h / 2 + 0.05, FACE_Z - 0.8)) * CFrame.Angles(0, math.rad(if flip then -90 else 90), 0) * CFrame.Angles(math.rad(180), 0, 0),
					ICICLE,
					M.Ice,
					{ Name = "Icicle", Wedge = true, Transparency = 0.05 }
				)
				flip = not flip
			end
			ix += rng:NextNumber(4.5, 8)
		end
	elseif style == "Stilt" then
		local vx = run.X1 + rng:NextNumber(2, 6)
		while vx < run.X2 - 1 do
			local part = self:_partAt(run, vx)
			local vl = math.min(rng:NextNumber(2.5, 8), (self:_hangRoom(vx - 1, vx + 1, part.Bottom)))
			if vl >= 1.5 then
				local isRoot = rng:NextNumber() < 0.5
				local thick = if isRoot then 0.32 else 0.22
				self:Deco(
					Vector3.new(vl, thick, thick),
					CFrame.new(self:W(vx, part.Bottom - vl / 2 + 0.2, FACE_Z - 0.8)) * CFrame.Angles(0, 0, math.rad(90 + rng:NextNumber(-8, 8))),
					if isRoot then self:_t("Detail") else shade(self:_t("Leaf"), 0.8),
					if isRoot then M.Wood else M.Grass,
					{ Name = if isRoot then "HangingRoot" else "HangingVine", Shape = CYL }
				)
			end
			vx += rng:NextNumber(6, 11)
		end
	end
end

--- Lippe entlang der Vorderkante einer Rampe.
function MapBuilder:_dressRamp(ramp)
	local theme = self.Theme
	local dx = ramp.X2 - ramp.X1
	local dy = ramp.Y2 - ramp.Y1
	if math.abs(dy) < 0.05 or dx <= 0 then
		return
	end
	local len = math.sqrt(dx * dx + dy * dy)
	local slope = CFrame.new(self:W((ramp.X1 + ramp.X2) / 2, (ramp.Y1 + ramp.Y2) / 2, FACE_Z)) * CFrame.Angles(0, 0, math.atan2(dy, dx))
	self:Deco(Vector3.new(len, 0.5, 0.7), slope * CFrame.new(0, -0.2, 0), self:_t("Trim"), self:_t("TrimMaterial"), { Name = "RampLip" })
	if theme.EdgeGlow then
		self:Deco(Vector3.new(len, 0.16, 0.12), slope * CFrame.new(0, -0.62, 0.36), theme.Accent, NEON, { Name = "EdgeGlow" })
	end
end

--- Stützen unter einem Lauf: bis zum nächsten Boden darunter oder in den Abgrund.
function MapBuilder:_supportRun(run)
	local style = self:_t("SupportStyle")
	if style == "Hanging" then
		return -- schwebende Ruinen tragen sich selbst
	end
	local len = run.X2 - run.X1
	if len < 10 then
		return
	end
	local abyss = self.MinY - 45
	local n = math.clamp(math.floor(len / 34) + 1, 1, 5)
	for i = 1, n do
		local px = run.X1 + len * (i - 0.5) / n
		local top = self:_partAt(run, px).Bottom
		for _ = 1, 4 do
			local solid = self:_solidAt(px, top)
			if not solid then
				break
			end
			top = solid.Y1
		end
		local below = self:_topAt(px, top - 0.3, true)
		local bottomY = below or abyss
		if top - bottomY >= 2 then
			self:Pillar(px, top, bottomY, { Z = if below then -4 else -2.4 })
		end
	end
end

--- Requisiten auf der hinteren Spurhälfte eines Laufs.
function MapBuilder:_propsRun(run)
	local kinds = self.Theme.Props
	if type(kinds) ~= "table" or #kinds == 0 then
		return
	end
	if run.X2 - run.X1 < 10 then
		return
	end
	local rng = self.Rng
	local spacing = self:_t("PropSpacing")
	local x = run.X1 + rng:NextNumber(2.5, math.max(3, spacing * 0.6))
	while x < run.X2 - 2.5 do
		if not self:_isReserved(x - 2, x + 2) then
			local clearance = self:_clearanceAt(x, run.Y)
			local start = rng:NextInteger(1, #kinds)
			for k = 0, #kinds - 1 do
				local kind = kinds[(start + k - 1) % #kinds + 1]
				local tall = PROP_HEIGHT[kind] or 3
				local isLight = kind == "Lamp" or kind == "Torch"
				if tall + 0.5 <= clearance and not (isLight and x - self.LastLampX < 34) then
					if isLight then
						self.LastLampX = x
					end
					self:Prop(kind, x, run.Y, -rng:NextNumber(3.6, 4.5))
					break
				end
			end
		end
		x += spacing * rng:NextNumber(0.75, 1.3)
	end
end

--- Verziert alle aufgezeichneten Böden und Rampen.
function MapBuilder:_dressPlatforms()
	local runs = self:_collectRuns()
	for _, run in runs do
		self:_dressRun(run)
	end
	for _, ramp in self.Ramps do
		self:_dressRamp(ramp)
	end
	if self.AutoSupports ~= false then
		for _, run in runs do
			self:_supportRun(run)
		end
	end
	if self.AutoProps ~= false then
		for _, run in runs do
			self:_propsRun(run)
		end
	end
end

------------------------------------------------------------------------
-- Hintergründe (Parallax-Ebenen aus Parts + Terrain)
------------------------------------------------------------------------

local BILLBOARD_TEXTS = { "VELOCITY RUSH", "NEON NIGHTS", "GO FAST!", "SPEED CITY" }

function MapBuilder:_decorCity()
	local theme, rng = self.Theme, self.Rng
	local back = theme.Backdrop or {}
	local terrain = theme.Terrain or {}
	local lights = back.Lights or { theme.Accent, theme.Accent2 }
	local _, hi = self:_floorRange()
	local base = self.MinY - 60
	-- Terrain: Stadtboden, Bucht, gegenüberliegendes Ufer
	self:_terrainStrip(-24, -250, base - 8, base, terrain.Ground or M.Asphalt)
	self:_terrainStrip(-250, -320, base - 10, base - 3, terrain.Liquid or M.Water)
	self:_terrainStrip(-320, -390, base - 8, base + 2, terrain.Top or M.Concrete)
	-- Nahe Häuserzeile
	local x, xEnd = self:_span(-50)
	while x < xEnd do
		local w = rng:NextNumber(16, 30)
		local d = rng:NextNumber(14, 24)
		local front = -rng:NextNumber(24, 44)
		local top = hi + rng:NextNumber(-25, 75)
		self:Building(x + w / 2, front - d / 2, base, w, top - base, d, {
			Color = jitter(rng, back.Near or rgb(34, 34, 60), 0.18),
			Material = if rng:NextNumber() < 0.3 then M.Glass else M.Concrete,
			Lights = lights,
		})
		x += w + rng:NextNumber(3, 9)
	end
	-- Mittlere Ebene: Türme
	x, xEnd = self:_span(-160)
	while x < xEnd do
		local w = rng:NextNumber(28, 52)
		local top = hi + rng:NextNumber(10, 200)
		self:Building(x + w / 2, -rng:NextNumber(135, 175), base, w, top - base, 30, {
			Color = jitter(rng, back.Mid or rgb(50, 44, 90), 0.1),
			Lights = lights,
			WindowStyle = if rng:NextNumber() < 0.6 then 2 else 1,
			Roof = rng:NextNumber() < 0.5,
		})
		x += w + rng:NextNumber(6, 24)
	end
	-- Ferne Skyline (Silhouetten)
	x, xEnd = self:_span(-350)
	while x < xEnd do
		local w = rng:NextNumber(50, 100)
		local h = (hi - base) + rng:NextNumber(60, 330)
		self:Deco(Vector3.new(w, h, 40), CFrame.new(self:W(x + w / 2, base + h / 2, -355)), jitter(rng, back.Far or rgb(74, 58, 120), 0.08), M.SmoothPlastic, { Name = "Skyline" })
		if rng:NextNumber() < 0.45 then
			self:Deco(Vector3.new(w * 0.7, 1.2, 0.3), CFrame.new(self:W(x + w / 2, base + h * rng:NextNumber(0.55, 0.92), -334.8)), lights[rng:NextInteger(1, #lights)], NEON, { Name = "SkylineLight", Transparency = 0.3 })
		end
		x += w + rng:NextNumber(4, 20)
	end
	-- Flugverkehr: lange Lichtspuren zwischen den Ebenen
	local laneX0, laneX1 = self:_span(-110)
	for _, lane in { { -96, hi + 36, lights[2] or theme.Accent }, { -104, hi + 54, lights[3] or theme.Accent2 }, { -112, hi + 18, lights[1] or theme.Accent } } do
		local sx = laneX0
		while sx < laneX1 do
			local segLen = math.min(1600, laneX1 - sx)
			self:Deco(Vector3.new(segLen, 0.4, 0.4), CFrame.new(self:W(sx + segLen / 2, lane[2], lane[1])), lane[3], NEON, { Name = "SkyLane", Transparency = 0.25 })
			sx += segLen
		end
	end
	-- Holo-Werbetafeln
	for i = 1, 3 do
		local bx = self.MinX + (self.MaxX - self.MinX) * (i - 0.5) / 3 + rng:NextNumber(-60, 60)
		local by = hi + rng:NextNumber(30, 55)
		local color = if i % 2 == 0 then theme.Accent2 or theme.Accent else theme.Accent
		self:Deco(Vector3.new(48, 24, 1.5), CFrame.new(self:W(bx, by, -92)), rgb(24, 24, 36), M.Metal, { Name = "Billboard" })
		local holo = self:Deco(Vector3.new(45, 21, 0.4), CFrame.new(self:W(bx, by, -91.1)), color, M.ForceField, { Name = "BillboardHolo" })
		self:Deco(Vector3.new(48.6, 0.5, 0.5), CFrame.new(self:W(bx, by - 12.3, -91.2)), color, NEON, { Name = "BillboardGlow" })
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Back
		gui.LightInfluence = 0
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 12
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(0.9, 0.7)
		label.Position = UDim2.fromScale(0.05, 0.15)
		label.Font = Enum.Font.LuckiestGuy
		label.TextScaled = true
		label.TextColor3 = WHITE
		label.TextStrokeColor3 = color
		label.TextStrokeTransparency = 0.2
		label.Text = BILLBOARD_TEXTS[(i - 1) % #BILLBOARD_TEXTS + 1]
		label.Parent = gui
		gui.Parent = holo
	end
end

--- Fabrikteil (Schornstein, Tank oder Halle) mit Fußpunkt y.
function MapBuilder:_factoryPiece(x: number, y: number, z: number)
	local theme, rng = self.Theme, self.Rng
	local roll = rng:NextNumber()
	if roll < 0.4 then
		local h = rng:NextNumber(40, 90)
		local d = rng:NextNumber(5, 8)
		local stack = self:Deco(Vector3.new(h, d, d), CFrame.new(self:W(x, y + h / 2, z)) * VERTICAL, rgb(150, 74, 56), M.Brick, { Name = "Smokestack", Shape = CYL })
		self:Deco(Vector3.new(1.2, d + 0.3, d + 0.3), CFrame.new(self:W(x, y + h * 0.86, z)) * VERTICAL, WHITE, M.SmoothPlastic, { Name = "StackBand", Shape = CYL })
		self:Deco(Vector3.new(1.2, d + 0.3, d + 0.3), CFrame.new(self:W(x, y + h * 0.94, z)) * VERTICAL, rgb(200, 40, 40), M.SmoothPlastic, { Name = "StackBand", Shape = CYL })
		self:Deco(Vector3.new(0.4, d * 0.7, d * 0.7), CFrame.new(self:W(x, y + h + 0.1, z)) * VERTICAL, theme.Accent, NEON, { Name = "StackGlow", Shape = CYL })
		local top = Instance.new("Attachment")
		top.Position = Vector3.new(h / 2, 0, 0)
		top.Parent = stack
		emitter(top, {
			Rate = 3,
			Lifetime = NumberRange.new(5, 8),
			Speed = NumberRange.new(5, 8),
			EmissionDirection = Enum.NormalId.Right,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 14) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) }),
			Color = ColorSequence.new(rgb(70, 62, 60)),
			SpreadAngle = Vector2.new(10, 10),
			Acceleration = Vector3.new(4, 2, 0),
		})
	elseif roll < 0.7 then
		local d = rng:NextNumber(12, 20)
		local h = rng:NextNumber(14, 26)
		self:Deco(Vector3.new(h, d, d), CFrame.new(self:W(x, y + h / 2, z)) * VERTICAL, rgb(140, 128, 116), M.CorrodedMetal, { Name = "Tank", Shape = CYL })
		self:Deco(Vector3.new(d, d * 0.35, d), CFrame.new(self:W(x, y + h, z)), rgb(150, 138, 126), M.Metal, { Name = "TankDome", Mesh = SPHERE })
		self:Deco(Vector3.new(0.6, h * 0.7, 0.3), CFrame.new(self:W(x, y + h * 0.45, z + d / 2 + 0.05)), theme.Accent2 or theme.Accent, NEON, { Name = "TankGauge" })
	else
		local w = rng:NextNumber(22, 40)
		local h = rng:NextNumber(14, 24)
		self:Deco(Vector3.new(w, h, 16), CFrame.new(self:W(x, y + h / 2, z)), rgb(78, 64, 58), M.CorrodedMetal, { Name = "Hall" })
		self:Deco(Vector3.new(w * 0.8, 2.2, 0.3), CFrame.new(self:W(x, y + h * 0.6, z + 8.1)), theme.Accent, NEON, { Name = "HallWindows", Transparency = 0.1 })
		self:_triangle(x, y + h, w + 1, 5, 16, z, rgb(96, 70, 58), M.CorrodedMetal, false, "HallRoof")
	end
end

function MapBuilder:_decorIndustrial()
	local theme, rng = self.Theme, self.Rng
	local terrain = theme.Terrain or {}
	local lo, hi = self:_floorRange()
	local base = self.MinY - 30
	local lava = terrain.Liquid or M.CrackedLava
	local rock = terrain.Cliff or M.Basalt
	-- Lavasee über die gesamte Länge (tödlich)
	self:Hazard(self.MinX - 120, base - 8, self.MaxX + 120, base, "Lava", { Depth = 220 })
	-- Erstarrte Schollen auf dem See
	local x, xEnd = self.MinX - 100, self.MaxX + 100
	while x < xEnd do
		self:Deco(
			Vector3.new(rng:NextNumber(6, 18), 0.8, rng:NextNumber(4, 12)),
			CFrame.new(self:W(x, base + 0.1, -rng:NextNumber(8, 90))) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 180)), 0),
			rgb(54, 40, 36),
			M.CrackedLava,
			{ Name = "LavaCrust" }
		)
		x += rng:NextNumber(20, 45)
	end
	-- Terrain: Lava jenseits der Gefahrenfläche
	self:_terrainStrip(-112, -470, base - 6.5, base - 0.5, lava)
	-- Basaltfelsen, die aus der Lava ragen, teils mit Fabrikbauten
	x, xEnd = self:_span(-70)
	while x < xEnd do
		local r = rng:NextNumber(8, 15)
		local z = -(r * 1.2 + rng:NextNumber(24, 80))
		self:TerrainBall(x, base - r * 1.1, z, r * 1.2, lava)
		self:TerrainBall(x, base + r * 0.4, z, r, rock)
		self:TerrainBall(x + rng:NextNumber(-3, 3), base + r * 1.3, z, r * 0.7, rock)
		self:TerrainBall(x + rng:NextNumber(-2, 2), base + r * 1.9, z, r * 0.42, rock)
		if rng:NextNumber() < 0.5 then
			self:_factoryPiece(x, base + r * 2.2, z)
		end
		x += rng:NextNumber(60, 120)
	end
	-- Fabrikbauten im Lavasee
	x, xEnd = self:_span(-110)
	while x < xEnd do
		self:_factoryPiece(x, base, -rng:NextNumber(70, 130))
		x += rng:NextNumber(90, 150)
	end
	-- Rohrbrücken knapp hinter der Spur mit Stützen bis in die Lava
	x, xEnd = self.MinX - 60, self.MaxX + 60
	while x < xEnd do
		local len = rng:NextNumber(40, 80)
		local py = rng:NextNumber(lo - 10, hi + 25)
		local d = rng:NextNumber(2.2, 3.4)
		local pz = -rng:NextNumber(16, 26)
		self:Deco(Vector3.new(len, d, d), CFrame.new(self:W(x + len / 2, py, pz)), rgb(124, 108, 92), M.Metal, { Name = "Pipe", Shape = CYL })
		for _, fx in { x + 2, x + len - 2 } do
			self:Deco(Vector3.new(0.8, d + 0.6, d + 0.6), CFrame.new(self:W(fx, py, pz)), rgb(90, 76, 64), M.Metal, { Name = "PipeFlange", Shape = CYL })
			self:Deco(Vector3.new(1.2, py - base, 1.2), CFrame.new(self:W(fx, (py + base) / 2, pz - d / 2 - 0.8)), self:_t("Support"), self:_t("SupportMaterial"), { Name = "PipeLeg" })
		end
		x += rng:NextNumber(90, 150)
	end
	-- Vulkane am Horizont
	x, xEnd = self:_span(-440)
	x += rng:NextNumber(0, 150)
	while x < xEnd do
		local r = rng:NextNumber(55, 80)
		local z = -rng:NextNumber(420, 460)
		self:TerrainBall(x, base - r * 0.1, z, r, rock)
		self:TerrainBall(x + rng:NextNumber(-10, 10), base + r * 0.75, z, r * 0.55, terrain.Peak or rock)
		self:TerrainBall(x, base + r * 1.15, z, r * 0.22, lava)
		local smoke = self:Deco(Vector3.new(8, 2, 8), CFrame.new(self:W(x, base + r * 1.3, z)), WHITE, nil, { Name = "VolcanoSmoke", Transparency = 1 })
		emitter(smoke, {
			Rate = 2,
			Lifetime = NumberRange.new(10, 14),
			Speed = NumberRange.new(6, 10),
			EmissionDirection = Enum.NormalId.Top,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 12), NumberSequenceKeypoint.new(1, 40) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }),
			Color = ColorSequence.new(rgb(70, 60, 58)),
			SpreadAngle = Vector2.new(8, 8),
			Acceleration = Vector3.new(3, 1, 0),
		})
		x += rng:NextNumber(240, 360)
	end
	-- Glut über der Lava
	x = self.MinX
	while x < self.MaxX do
		local holder = self:Deco(Vector3.new(120, 1, 40), CFrame.new(self:W(x + 60, base + 1, -10)), Color3.new(), nil, { Name = "EmberField", Transparency = 1 })
		emitter(holder, {
			Rate = 8,
			Lifetime = NumberRange.new(2, 4),
			Speed = NumberRange.new(4, 9),
			EmissionDirection = Enum.NormalId.Top,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) }),
			Color = ColorSequence.new(theme.Accent),
			LightEmission = 1,
			SpreadAngle = Vector2.new(20, 20),
		})
		x += 140
	end
end

--- Ruinen, Bäume und Wasserfälle auf einer Hintergrund-Insel.
function MapBuilder:_islandRuins(x: number, top: number, z: number, r: number, treeScale)
	local rng = self.Rng
	local marble = rgb(238, 232, 220)
	if rng:NextNumber() < 0.5 then
		for _ = 1, rng:NextInteger(2, 3) do
			local cx = x + rng:NextNumber(-r * 0.55, r * 0.55)
			local h = rng:NextNumber(0.35, 0.9) * r
			self:Deco(Vector3.new(h, r * 0.14, r * 0.14), CFrame.new(self:W(cx, top + h / 2, z + rng:NextNumber(-r * 0.3, r * 0.3))) * VERTICAL, marble, M.Marble, { Name = "RuinColumn", Shape = CYL })
		end
	end
	if rng:NextNumber() < 0.55 then
		self:Tree(x + rng:NextNumber(-r * 0.4, r * 0.4), top - 0.5, z, { Kind = "Round", Scale = rng:NextNumber(treeScale[1], treeScale[2]) })
	end
	if rng:NextNumber() < 0.18 then
		self:Waterfall(x + r * 0.5, top - 1, z + r * 0.75, r * 0.2, r * 2.6)
	end
end

function MapBuilder:_decorSky()
	local theme, rng = self.Theme, self.Rng
	local back = theme.Backdrop or {}
	local terrain = theme.Terrain or {}
	local lo, hi = self:_floorRange()
	local seaY = self.MinY - 58
	-- Wolkenmeer in drei Tiefen (abgeflachte Ellipsoide)
	for _, row in {
		{ Z = -45, Step = { 40, 60 }, W = { 70, 110 }, H = { 22, 32 }, Color = back.Near or WHITE },
		{ Z = -140, Step = { 60, 90 }, W = { 110, 170 }, H = { 30, 44 }, Color = back.Mid or rgb(232, 240, 252) },
		{ Z = -300, Step = { 100, 140 }, W = { 180, 260 }, H = { 40, 60 }, Color = back.Far or rgb(214, 228, 248) },
	} do
		local x, xEnd = self:_span(row.Z)
		while x < xEnd do
			local w = rng:NextNumber(row.W[1], row.W[2])
			local h = rng:NextNumber(row.H[1], row.H[2])
			self:Deco(Vector3.new(w, h, w * 0.75), CFrame.new(self:W(x, seaY + rng:NextNumber(-4, 4), row.Z + rng:NextNumber(-8, 8))), row.Color, M.SmoothPlastic, { Name = "CloudSea", Mesh = SPHERE })
			x += rng:NextNumber(row.Step[1], row.Step[2])
		end
	end
	-- Schwebende Inseln (Terrain) in drei Tiefen
	for _, layer in {
		{ Z = { -80, -55 }, R = { 9, 16 }, Step = { 70, 120 }, Trees = { 1.1, 1.6 } },
		{ Z = { -180, -130 }, R = { 18, 30 }, Step = { 110, 170 }, Trees = { 1.8, 2.6 } },
		{ Z = { -380, -300 }, R = { 38, 60 }, Step = { 180, 280 } },
	} do
		local x, xEnd = self:_span(layer.Z[1])
		x += rng:NextNumber(0, layer.Step[1])
		while x < xEnd do
			local r = rng:NextNumber(layer.R[1], layer.R[2])
			local z = rng:NextNumber(layer.Z[1], layer.Z[2])
			local top = self:Island(x, rng:NextNumber(lo - 30, hi + 70), z, r)
			if layer.Trees then
				self:_islandRuins(x, top, z, r, layer.Trees)
			end
			x += rng:NextNumber(layer.Step[1], layer.Step[2])
		end
	end
	-- Felsnadeln am Horizont, die aus den Wolken ragen
	local x, xEnd = self:_span(-460)
	while x < xEnd do
		local w = rng:NextNumber(90, 150)
		self:Mountain(x, -rng:NextNumber(450, 480), seaY - 20, (hi - seaY) + rng:NextNumber(40, 160), w, { Style = "Peak", Material = terrain.Cliff or M.Limestone, Cap = terrain.Top, CapRatio = 0.12, Depth = 36 })
		x += w * rng:NextNumber(1.6, 2.8)
	end
	-- Vögel
	for _ = 1, 10 do
		local bx = rng:NextNumber(self.MinX, self.MaxX)
		local by = hi + rng:NextNumber(10, 70)
		local bz = -rng:NextNumber(40, 120)
		local s = rng:NextNumber(1.4, 2.4)
		for _, side in { -1, 1 } do
			self:Deco(Vector3.new(s, 0.18 * s, 0.18 * s), CFrame.new(self:W(bx + side * s * 0.42, by, bz)) * CFrame.Angles(0, 0, math.rad(22 * side)), rgb(60, 66, 80), M.SmoothPlastic, { Name = "Bird" })
		end
	end
end

function MapBuilder:_decorGlacier()
	local theme, rng = self.Theme, self.Rng
	local terrain = theme.Terrain or {}
	local lo, hi = self:_floorRange()
	local base = self.MinY - 40
	local snow = terrain.Top or M.Snow
	-- Eiswasser ganz unten (tödlich)
	self:Hazard(self.MinX - 120, base - 6, self.MaxX + 120, base, "IceWater", { Depth = 200 })
	-- Eisschollen auf dem Wasser
	local x, xEnd = self.MinX - 100, self.MaxX + 100
	while x < xEnd do
		self:Deco(
			Vector3.new(rng:NextNumber(5, 14), 0.8, rng:NextNumber(4, 10)),
			CFrame.new(self:W(x, base + 0.15, -rng:NextNumber(8, 90))) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 180)), 0),
			rgb(232, 246, 255),
			M.Ice,
			{ Name = "IceFloe" }
		)
		x += rng:NextNumber(25, 50)
	end
	-- Terrain: Eisdecke hinter dem Wasser
	self:_terrainStrip(-102, -330, base - 8, base + 0.5, terrain.Cliff or M.Glacier)
	-- Nahe Schneehügel mit Tannen und Kristallen
	x, xEnd = self:_span(-60)
	while x < xEnd do
		local r = rng:NextNumber(16, 28)
		local z = -(r + rng:NextNumber(18, 46))
		local cy = base + rng:NextNumber(-8, 18)
		self:TerrainBall(x, cy, z, r, terrain.Ground or snow)
		local roll = rng:NextNumber()
		if roll < 0.5 then
			local dx = rng:NextNumber(-r * 0.3, r * 0.3)
			self:Tree(x + dx, cy + math.sqrt(r * r - dx * dx) - 1.5, z, { Kind = "Pine", Scale = rng:NextNumber(1.8, 2.8) })
		elseif roll < 0.7 then
			self:Prop("Crystal", x, cy + r - 1, z, { Scale = 2.2 })
		end
		x += rng:NextNumber(30, 55)
	end
	-- Gletscherkamm (Mitte) und hohe Gipfel am Horizont
	x, xEnd = self:_span(-200)
	while x < xEnd do
		local w = rng:NextNumber(90, 150)
		self:Mountain(x, -rng:NextNumber(175, 210), base - 10, (hi - base) + rng:NextNumber(10, 90), w, { Style = "Peak", Material = terrain.Cliff or M.Glacier, Cap = snow, Depth = 34, CapRatio = 0.35 })
		x += w * rng:NextNumber(0.5, 0.8)
	end
	x, xEnd = self:_span(-450)
	while x < xEnd do
		local w = rng:NextNumber(220, 340)
		self:Mountain(x, -rng:NextNumber(430, 470), base - 10, (hi - base) + rng:NextNumber(140, 320), w, { Style = "Peak", Material = terrain.Peak or M.Slate, Cap = snow, Depth = 30, CapRatio = 0.4 })
		x += w * rng:NextNumber(0.7, 1)
	end
	-- Schwebende Eiskristalle knapp hinter der Spur
	x = self.MinX
	while x < self.MaxX do
		local cy = rng:NextNumber(lo - 10, hi + 30)
		local cz = -rng:NextNumber(16, 40)
		local h = rng:NextNumber(5, 12)
		local tilt = CFrame.Angles(0, math.rad(45), math.rad(rng:NextNumber(-25, 25)))
		self:Deco(Vector3.new(1.4, h, 1.4), CFrame.new(self:W(x, cy, cz)) * tilt, rgb(150, 230, 255), M.Glass, { Name = "Crystal", Transparency = 0.25 })
		self:Deco(Vector3.new(0.5, h * 0.8, 0.5), CFrame.new(self:W(x, cy, cz)) * tilt, rgb(170, 240, 255), NEON, { Name = "CrystalCore", Transparency = 0.1 })
		x += rng:NextNumber(60, 110)
	end
	-- Schneefall
	x = self.MinX - 100
	while x < self.MaxX + 100 do
		local holder = self:Deco(Vector3.new(220, 1, 80), CFrame.new(self:W(x + 110, self.MaxY + 60, -20)), Color3.new(), nil, { Name = "SnowEmitter", Transparency = 1 })
		emitter(holder, {
			Rate = 30,
			Lifetime = NumberRange.new(6, 9),
			Speed = NumberRange.new(8, 12),
			EmissionDirection = Enum.NormalId.Bottom,
			Size = NumberSequence.new(0.35),
			Color = ColorSequence.new(rgb(255, 255, 255)),
			LightEmission = 0.3,
			SpreadAngle = Vector2.new(15, 15),
		})
		x += 220
	end
end

function MapBuilder:_decorJungle()
	local theme, rng = self.Theme, self.Rng
	local back = theme.Backdrop or {}
	local terrain = theme.Terrain or {}
	local lo, hi = self:_floorRange()
	local base = self.MinY - 36
	local leaf = self:_t("Leaf")
	local grass = terrain.Top or M.LeafyGrass
	-- Fluss ganz unten (tödlich)
	self:Hazard(self.MinX - 120, base - 6, self.MaxX + 120, base, "River", { Depth = 200 })
	-- Seerosen und Steine im Fluss
	local x, xEnd = self.MinX - 100, self.MaxX + 100
	while x < xEnd do
		if rng:NextNumber() < 0.6 then
			local pad = rng:NextNumber(2.5, 4.5)
			self:Deco(Vector3.new(0.2, pad, pad), CFrame.new(self:W(x, base + 0.1, -rng:NextNumber(8, 80))) * VERTICAL, rgb(78, 160, 70), M.Grass, { Name = "LilyPad", Shape = CYL })
		else
			local d = rng:NextNumber(3, 7)
			self:Deco(Vector3.new(d, d * 0.6, d * 0.8), CFrame.new(self:W(x, base, -rng:NextNumber(8, 80))) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 90)), 0), rgb(110, 112, 100), M.Rock, { Name = "RiverRock" })
		end
		x += rng:NextNumber(24, 48)
	end
	-- Terrain: Fluss setzt sich fort, Ufer
	self:_terrainStrip(-102, -170, base - 8, base - 0.6, terrain.Liquid or M.Water)
	self:_terrainStrip(-170, -240, base - 8, base + 3, terrain.Ground or M.Mud)
	-- Nahe Hügel mit Urwaldriesen
	x, xEnd = self:_span(-70)
	while x < xEnd do
		local r = rng:NextNumber(14, 26)
		local z = -(r + rng:NextNumber(26, 56))
		local cy = base + rng:NextNumber(-6, 14)
		self:TerrainBall(x, cy, z, r, grass)
		if rng:NextNumber() < 0.55 then
			self:Tree(x, cy + r - 2, z, { Kind = "Jungle", Scale = rng:NextNumber(1.4, 2), Height = rng:NextNumber(14, 26) })
		end
		x += rng:NextNumber(34, 60)
	end
	-- Urwaldriesen direkt hinter der Spur (Kronendach)
	x, xEnd = self:_span(-25)
	while x < xEnd do
		local s = rng:NextNumber(2, 2.8)
		local crownY = hi + rng:NextNumber(-10, 30)
		self:Tree(x, base, -rng:NextNumber(18, 32), { Kind = "Jungle", Scale = s, Height = crownY - base, Leaf = jitter(rng, back.Near or leaf, 0.12) })
		x += rng:NextNumber(32, 52)
	end
	-- Felswände mit Wasserfällen (Mitte)
	x, xEnd = self:_span(-170)
	local falls = 0
	while x < xEnd do
		local w = rng:NextNumber(44, 70)
		local h = (hi - base) + rng:NextNumber(-10, 50)
		local z = -rng:NextNumber(150, 185)
		self:Mountain(x, z, base - 6, h, w, { Material = terrain.Cliff or M.Rock, Cap = grass })
		if falls < 4 and rng:NextNumber() < 0.3 then
			falls += 1
			self:Waterfall(x + w * 0.1, base - 6 + h * 0.85, z + w * 0.5, rng:NextNumber(4, 7), h * 0.85)
		end
		x += w * rng:NextNumber(1.1, 1.6)
	end
	-- Kalksteinberge am Horizont
	x, xEnd = self:_span(-430)
	while x < xEnd do
		local w = rng:NextNumber(120, 200)
		local h = (hi - base) + rng:NextNumber(80, 220)
		local z = -rng:NextNumber(420, 450)
		self:Mountain(x, z, base - 10, h, w, { Style = "Peak", Material = terrain.Peak or M.Ground, Cap = grass, CapRatio = 0.55, Depth = 34 })
		x += w * rng:NextNumber(0.6, 0.95)
	end
	-- Lianen zwischen den Bäumen
	x = self.MinX - 60
	while x < self.MaxX + 60 do
		local vineLen = rng:NextNumber(20, 50)
		local vy = self.MaxY + 40 - vineLen / 2
		self:Deco(Vector3.new(vineLen, 0.5, 0.5), CFrame.new(self:W(x + 4, vy, -8)) * VERTICAL, rgb(60, 120, 50), M.Grass, { Name = "Vine", Shape = CYL })
		for _ = 1, 2 do
			local d = rng:NextNumber(1, 1.8)
			self:Deco(Vector3.new(d, d, d), CFrame.new(self:W(x + 4 + rng:NextNumber(-0.6, 0.6), vy + rng:NextNumber(-vineLen / 2, vineLen / 2), -8)), jitter(rng, leaf, 0.15), M.Grass, { Name = "VineLeaf", Shape = BALL })
		end
		x += rng:NextNumber(60, 110)
	end
	-- Glühwürmchen
	x = self.MinX
	while x < self.MaxX do
		local holder = self:Deco(Vector3.new(150, 40, 30), CFrame.new(self:W(x + 75, lo + 20, -14)), Color3.new(), nil, { Name = "Fireflies", Transparency = 1 })
		emitter(holder, {
			Rate = 4,
			Lifetime = NumberRange.new(3, 5),
			Speed = NumberRange.new(0.5, 1.5),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(1, 0) }),
			Color = ColorSequence.new(theme.Accent2 or theme.Accent),
			LightEmission = 1,
			SpreadAngle = Vector2.new(180, 180),
		})
		x += 160
	end
end

function MapBuilder:_decorHub()
	local theme, rng = self.Theme, self.Rng
	local back = theme.Backdrop or {}
	local terrain = theme.Terrain or {}
	local lights = back.Lights or { theme.Accent, theme.Accent2 }
	local _, hi = self:_floorRange()
	local base = self.MinY - 30
	-- Terrain: Platz, Bucht, ferne Hügel
	self:_terrainStrip(-24, -110, base - 6, base, terrain.Ground or M.Concrete)
	self:_terrainStrip(-110, -270, base - 10, base - 2, terrain.Liquid or M.Water)
	local x, xEnd = self:_span(-340)
	while x < xEnd do
		local w = rng:NextNumber(80, 140)
		self:Mountain(x, -rng:NextNumber(330, 360), base - 6, rng:NextNumber(40, 90), w, { Material = terrain.Cliff or M.Slate })
		x += w * 0.75
	end
	-- Nahe Türme mit Fenstern
	x, xEnd = self:_span(-60)
	while x < xEnd do
		local w = rng:NextNumber(16, 28)
		self:Building(x + w / 2, -rng:NextNumber(46, 80), base, w, (hi + rng:NextNumber(10, 110)) - base, 20, {
			Color = jitter(rng, back.Near or rgb(46, 46, 80), 0.15),
			Lights = lights,
		})
		x += w + rng:NextNumber(6, 16)
	end
	-- Ferne, helle Skyline am anderen Ufer
	x, xEnd = self:_span(-300)
	while x < xEnd do
		local w = rng:NextNumber(30, 60)
		local h = (hi - base) + rng:NextNumber(40, 200)
		self:Deco(Vector3.new(w, h, 24), CFrame.new(self:W(x + w / 2, base + h / 2, -295)), jitter(rng, back.Far or rgb(96, 84, 144), 0.08), M.SmoothPlastic, { Name = "Skyline" })
		if rng:NextNumber() < 0.4 then
			self:Deco(Vector3.new(0.8, h * 0.6, 0.3), CFrame.new(self:W(x + w / 2, base + h * 0.6, -282.8)), lights[rng:NextInteger(1, #lights)], NEON, { Name = "SkylineLight", Transparency = 0.3 })
		end
		x += w + rng:NextNumber(8, 24)
	end
	-- Holo-Ringe
	for i = 1, 6 do
		local color = if i % 2 == 0 then theme.Accent else theme.Accent2 or theme.Accent
		local pos = CFrame.new(self:W(-140 + i * 40, 60 + (i % 2) * 14, -30)) * FACING
		self:Deco(Vector3.new(0.4, 18, 18), pos, color, NEON, { Name = "HoloRing", Shape = CYL, Transparency = 0.55 })
		self:Deco(Vector3.new(0.3, 12, 12), pos * CFrame.new(-0.4, 0, 0), color, M.ForceField, { Name = "HoloRingCore", Shape = CYL, Transparency = 0.3 })
	end
	-- Lichtsäulen in den Himmel
	for i = 1, 4 do
		local lx = self.MinX + (self.MaxX - self.MinX) * (i - 0.5) / 4
		self:Deco(Vector3.new(2, 400, 2), CFrame.new(self:W(lx, base + 200, -140 - i * 20)), lights[(i - 1) % #lights + 1], NEON, { Name = "LightBeam", Transparency = 0.75 })
	end
end

--- Tribüne (Stufen mit bunten Sitzreihen, Dach, Flutlicht). z = vordere Kante.
function MapBuilder:_stand(x: number, z: number, baseY: number, width: number)
	local theme = self.Theme
	local seats = { theme.Accent, WHITE, theme.Accent2 or theme.Accent }
	for step = 0, 3 do
		local h = 3 + step * 3
		local sz = z - 2 - step * 4
		self:Deco(Vector3.new(width, h, 4), CFrame.new(self:W(x, baseY + h / 2, sz)), rgb(214, 218, 228), M.Concrete, { Name = "Stand" })
		self:Deco(Vector3.new(width - 1, 1, 0.8), CFrame.new(self:W(x, baseY + h + 0.5, sz + 1.2)), seats[step % 3 + 1], M.SmoothPlastic, { Name = "Seats" })
	end
	self:Deco(Vector3.new(width + 4, 1, 18), CFrame.new(self:W(x, baseY + 24, z - 9)), rgb(240, 242, 248), M.Metal, { Name = "StandRoof" })
	for _, side in { -1, 1 } do
		local mx = x + side * (width / 2 + 3)
		self:Deco(Vector3.new(34, 1, 1), CFrame.new(self:W(mx, baseY + 17, z - 16)) * VERTICAL, rgb(200, 204, 214), M.Metal, { Name = "FloodlightMast", Shape = CYL })
		self:Deco(Vector3.new(5, 3, 0.6), CFrame.new(self:W(mx, baseY + 35, z - 15.4)), rgb(255, 250, 230), NEON, { Name = "Floodlight" })
	end
end

function MapBuilder:_decorAcademy()
	local theme, rng = self.Theme, self.Rng
	local back = theme.Backdrop or {}
	local terrain = theme.Terrain or {}
	local _, hi = self:_floorRange()
	local base = self.MinY - 30
	local grass = terrain.Top or M.Grass
	-- Terrain: Wiese, See, Wiese, Hügel
	self:_terrainStrip(-22, -140, base - 6, base, grass)
	self:_terrainStrip(-140, -200, base - 8, base - 1, terrain.Liquid or M.Water)
	self:_terrainStrip(-200, -300, base - 6, base + 2, grass)
	local x, xEnd = self:_span(-80)
	while x < xEnd do
		local r = rng:NextNumber(14, 26)
		local z = -(r + rng:NextNumber(40, 80))
		local cy = base + rng:NextNumber(-12, 6)
		self:TerrainBall(x, cy, z, r, M.LeafyGrass)
		if rng:NextNumber() < 0.6 then
			self:Tree(x, cy + r - 1.5, z, { Kind = "Round", Scale = rng:NextNumber(1.6, 2.4) })
		end
		x += rng:NextNumber(40, 70)
	end
	x, xEnd = self:_span(-340)
	while x < xEnd do
		local w = rng:NextNumber(70, 120)
		self:Mountain(x, -rng:NextNumber(330, 360), base, rng:NextNumber(40, 90), w, { Material = M.LeafyGrass })
		x += w * 0.9
	end
	-- Tribünen und Bäume auf der Wiese
	for i = 1, 3 do
		self:_stand(self.MinX + (self.MaxX - self.MinX) * (i - 0.5) / 3, -40, base, rng:NextNumber(50, 70))
	end
	x = self.MinX - 40
	while x < self.MaxX + 40 do
		self:Tree(x, base, -rng:NextNumber(24, 34), { Kind = "Round", Scale = rng:NextNumber(1.6, 2.4) })
		x += rng:NextNumber(45, 80)
	end
	-- Fahnenreihe
	x = self.MinX
	local flip = false
	while x < self.MaxX do
		self:Banner(x, base, if flip then theme.Accent2 or theme.Accent else theme.Accent, { Height = 16, Width = 4, Z = -22, Color2 = WHITE })
		flip = not flip
		x += 90
	end
	-- Ferne, helle Skyline und Wolken
	x, xEnd = self:_span(-380)
	while x < xEnd do
		local w = rng:NextNumber(30, 70)
		local h = (hi - base) + rng:NextNumber(30, 180)
		self:Deco(Vector3.new(w, h, 30), CFrame.new(self:W(x + w / 2, base + h / 2, -385)), jitter(rng, back.Far or rgb(206, 222, 244), 0.06), M.SmoothPlastic, { Name = "Skyline" })
		x += w + rng:NextNumber(10, 40)
	end
	for _ = 1, 12 do
		self:Cloud(rng:NextNumber(self.MinX - 100, self.MaxX + 100), hi + rng:NextNumber(50, 120), -rng:NextNumber(160, 320), rng:NextNumber(2.5, 4.5), { Puffs = 4 })
	end
end

--- Erzeugt Bodenverzierung und Hintergrund passend zum Theme.
function MapBuilder:Decorate()
	if self.AutoDress ~= false then
		self:_dressPlatforms()
	end
	local kind = self.Theme.Decor
	if kind == "City" then
		self:_decorCity()
	elseif kind == "Industrial" then
		self:_decorIndustrial()
	elseif kind == "Sky" then
		self:_decorSky()
	elseif kind == "Glacier" then
		self:_decorGlacier()
	elseif kind == "Jungle" then
		self:_decorJungle()
	elseif kind == "Hub" then
		self:_decorHub()
	elseif kind == "Academy" then
		self:_decorAcademy()
	end
end

------------------------------------------------------------------------
-- Ergebnis
------------------------------------------------------------------------

--- Liefert die fertige MapInstance (Tabelle mit allen Laufzeitdaten).
--- TerrainFills: aufgezeichnete Terrain-Füllungen in Weltkoordinaten
--- ({Kind="Block"|"Wedge", CFrame, Size} | {Kind="Ball", Center, Radius} | {Kind="Cylinder", CFrame, Height, Radius}).
function MapBuilder:Result()
	local o = self.Origin
	return {
		RegionId = self.RegionId,
		MapId = self.MapId,
		Model = self.Model,
		Origin = o,
		StartX = o.X + self.StartLocalX,
		FinishX = if self.FinishLocalX then o.X + self.FinishLocalX else nil,
		KillY = o.Y + self.MinY - 20,
		Spawns = self.Spawns,
		Checkpoints = self.Checkpoints,
		TeleportNodes = self.TeleportNodes,
		PickupSpawns = self.PickupSpawns,
		Anchors = self.Anchors,
		Portals = self.Portals,
		HazardFolder = self.Folders.Hazards,
		PickupFolder = self.Folders.Pickups,
		RuntimeFolder = self.Folders.Runtime,
		TerrainFills = self.TerrainFills,
		Bounds = {
			MinX = o.X + self.MinX,
			MaxX = o.X + self.MaxX,
			MinY = o.Y + self.MinY,
			MaxY = o.Y + self.MaxY,
		},
	}
end

return MapBuilder
