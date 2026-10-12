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
		Start(len)                 Startbereich mit 8 Spawnpunkten
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
		Finish(len)                Ziellinie
		Decorate()                 Hintergrund passend zum Theme

	Freie Bausteine: Box, Ground, RampPart, Anchor, Hazard, BoostPad, JumpPad,
	Checkpoint, SpawnPoint, PickupSpot, Sign, Portal.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local MapBuilder = {}
MapBuilder.__index = MapBuilder

local DEPTH = Config.World.TrackDepth
local ROOT_HEIGHT = -Config.Character.FeetOffset + 0.3
local GRAVITY = Config.World.Gravity
local NEON = Enum.Material.Neon
local rgb = Color3.fromRGB

local HAZARD_STYLE = {
	Lava = { Color = rgb(255, 90, 20), Material = NEON, Transparency = 0 },
	Laser = { Color = rgb(255, 40, 90), Material = NEON, Transparency = 0.25 },
	Flame = { Color = rgb(255, 120, 20), Material = NEON, Transparency = 0.15 },
	Arcane = { Color = rgb(170, 90, 255), Material = NEON, Transparency = 0.3 },
	Void = { Color = rgb(120, 80, 220), Material = NEON, Transparency = 0.7 },
	Icicle = { Color = rgb(170, 230, 255), Material = Enum.Material.Glass, Transparency = 0.15 },
	IceWater = { Color = rgb(60, 140, 210), Material = Enum.Material.Glass, Transparency = 0.25 },
	River = { Color = rgb(50, 120, 160), Material = Enum.Material.Glass, Transparency = 0.25 },
	Thorns = { Color = rgb(110, 30, 50), Material = Enum.Material.Slate, Transparency = 0 },
	Spikes = { Color = rgb(150, 150, 165), Material = Enum.Material.Metal, Transparency = 0 },
}

local TEETH_KINDS = { Thorns = true, Spikes = true, Icicle = true }

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
	self.CheckpointSpacing = 200
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
function MapBuilder:Deco(size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, extra)
	local props = {
		Name = extra and extra.Name or "Deco",
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		Transparency = extra and extra.Transparency or 0,
		Shape = extra and extra.Shape or nil,
		Wedge = extra and extra.Wedge or nil,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
		Parent = self.Folders.Decor,
	}
	return self:Part(props)
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

--- Plattform mit Oberkante y. opts: Thickness, Ice, TopColor, TopMaterial
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
		top.Material = Enum.Material.Ice
		top.Color = rgb(190, 230, 255)
	end
	if theme.EdgeGlow and (x2 - x1) >= 4 then
		self:Deco(
			Vector3.new(x2 - x1, 0.22, 0.22),
			CFrame.new(self:W((x1 + x2) / 2, y - 0.12, DEPTH / 2 + 0.12)),
			theme.Accent,
			NEON,
			{ Name = "EdgeGlow" }
		)
	end
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
end

--- Greifhaken-Anker an lokaler Position.
function MapBuilder:Anchor(x: number, y: number)
	local theme = self.Theme
	local position = self:W(x, y, 0)
	local part = self:Part({
		Name = "GrappleAnchor",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.8, 1.8, 1.8),
		CFrame = CFrame.new(position),
		Color = theme.Anchor or theme.Accent,
		Material = NEON,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
		Parent = self.Folders.Anchors,
	})
	self:Deco(
		Vector3.new(0.25, 3.4, 3.4),
		CFrame.new(position) * CFrame.Angles(0, math.rad(90), 0),
		theme.Anchor or theme.Accent,
		NEON,
		{ Name = "AnchorRing", Shape = Enum.PartType.Cylinder, Transparency = 0.45 }
	)
	table.insert(self.Anchors, part)
	return part
end

--- Zacken-Dekoration (Dornen/Stacheln/Eiszapfen) entlang einer Kante.
function MapBuilder:_teeth(x1: number, x2: number, y: number, height: number, color: Color3, material, pointDown: boolean?)
	local width = x2 - x1
	local count = math.clamp(math.floor(width / 2.5), 1, 24)
	local toothWidth = width / count
	for i = 0, count - 1 do
		local cx = x1 + toothWidth * (i + 0.5)
		local half = toothWidth / 2
		local yCenter = if pointDown then y - height / 2 else y + height / 2
		-- Zwei Keile Rücken an Rücken ergeben ein Dreieck in der Seitenansicht.
		local flip = if pointDown then CFrame.Angles(0, 0, math.rad(180)) else CFrame.new()
		self:Deco(
			Vector3.new(DEPTH * 0.8, height, half),
			CFrame.new(self:W(cx - half / 2, yCenter, 0)) * flip * CFrame.Angles(0, math.rad(if pointDown then -90 else 90), 0),
			color,
			material,
			{ Name = "Tooth", Wedge = true }
		)
		self:Deco(
			Vector3.new(DEPTH * 0.8, height, half),
			CFrame.new(self:W(cx + half / 2, yCenter, 0)) * flip * CFrame.Angles(0, math.rad(if pointDown then 90 else -90), 0),
			color,
			material,
			{ Name = "Tooth", Wedge = true }
		)
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
		Color = rgb(255, 170, 0),
		Material = NEON,
		Depth = DEPTH - 1,
		Parent = self.Folders.Pads,
		Track = false,
	})
	pad:SetAttribute("BoostPad", power or 80)
	-- Pfeile (">") an der Vorderkante
	local count = math.clamp(math.floor((x2 - x1) / 6), 1, 8)
	for i = 1, count do
		local cx = x1 + (x2 - x1) * i / (count + 1)
		for _, sign in { 1, -1 } do
			self:Deco(
				Vector3.new(1.6, 0.3, 0.2),
				CFrame.new(self:W(cx, y + 0.9 + sign * 0.45, DEPTH / 2 - 0.2)) * CFrame.Angles(0, 0, math.rad(-35 * sign)),
				rgb(255, 220, 120),
				NEON,
				{ Name = "BoostArrow" }
			)
		end
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
	self:Deco(Vector3.new(4, 0.25, 0.25), CFrame.new(self:W(x, y + 1.2, DEPTH / 2 - 0.5)), rgb(160, 255, 190), NEON, { Name = "JumpPadGlow", Transparency = 0.3 })
	return pad
end

--- Spawnpunkt (Root-Position über dem Boden y, Blick nach +X).
function MapBuilder:SpawnPoint(x: number, y: number, z: number?)
	local position = self:W(x, y + ROOT_HEIGHT, z or 0)
	table.insert(self.Spawns, CFrame.lookAt(position, position + Vector3.new(1, 0, 0)))
end

--- Checkpoint für Respawns (inkl. Fahne).
function MapBuilder:Checkpoint(x: number?, y: number?)
	local cx = x or self.X
	local cy = y or self.Y
	local position = self:W(cx, cy + ROOT_HEIGHT, 0)
	table.insert(self.Checkpoints, {
		X = position.X,
		CFrame = CFrame.lookAt(position, position + Vector3.new(1, 0, 0)),
	})
	self.LastCheckpointX = cx
	local z = -DEPTH / 2 + 0.4
	self:Deco(Vector3.new(0.35, 9, 0.35), CFrame.new(self:W(cx, cy + 4.5, z)), rgb(230, 230, 240), Enum.Material.Metal, { Name = "CheckpointPole" })
	self:Deco(Vector3.new(3, 2.2, 0.15), CFrame.new(self:W(cx + 1.6, cy + 7.8, z)), self.Theme.Accent, NEON, { Name = "CheckpointFlag" })
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
function MapBuilder:Sign(x: number, y: number, title: string, text: string?, opts)
	opts = opts or {}
	local holder = self:Deco(Vector3.new(0.2, 0.2, 0.2), CFrame.new(self:W(x, y, -2)), Color3.new(), nil, { Name = "Sign", Transparency = 1 })
	local gui = Instance.new("BillboardGui")
	gui.Name = "SignGui"
	gui.Size = UDim2.new(opts.Width or 26, 0, opts.Height or (if text and text ~= "" then 7 else 4), 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 260
	gui.Adornee = holder

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = rgb(14, 17, 30)
	frame.BackgroundTransparency = opts.Transparent and 1 or 0.2
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.12, 0)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = opts.Color or self.Theme.Accent
	stroke.Thickness = 3
	stroke.Transparency = opts.Transparent and 1 or 0
	stroke.Parent = frame

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = if text and text ~= "" then UDim2.fromScale(0.94, 0.48) else UDim2.fromScale(0.94, 0.86)
	titleLabel.Position = UDim2.fromScale(0.03, 0.06)
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = opts.Color or self.Theme.Accent
	titleLabel.Text = title
	titleLabel.Parent = frame

	if text and text ~= "" then
		local body = Instance.new("TextLabel")
		body.BackgroundTransparency = 1
		body.Size = UDim2.fromScale(0.94, 0.38)
		body.Position = UDim2.fromScale(0.03, 0.56)
		body.Font = Enum.Font.GothamBold
		body.TextScaled = true
		body.TextColor3 = rgb(235, 240, 255)
		body.Text = text
		body.Parent = frame
	end
	gui.Parent = holder
	return holder
end

--- Portal in der Lobby (Stehenbleiben löst eine Aktion aus).
function MapBuilder:Portal(x: number, y: number, action: string, label: string, color: Color3)
	local z = -3
	self:Deco(Vector3.new(1, 13, 2), CFrame.new(self:W(x - 5.5, y + 6.5, z)), color, NEON, { Name = "PortalPost" })
	self:Deco(Vector3.new(1, 13, 2), CFrame.new(self:W(x + 5.5, y + 6.5, z)), color, NEON, { Name = "PortalPost" })
	self:Deco(Vector3.new(12, 1, 2), CFrame.new(self:W(x, y + 13.5, z)), color, NEON, { Name = "PortalTop" })
	self:Deco(Vector3.new(10, 12.5, 0.4), CFrame.new(self:W(x, y + 6.5, z - 0.5)), color, NEON, { Name = "PortalField", Transparency = 0.78 })
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

------------------------------------------------------------------------
-- Cursor-Bausteine
------------------------------------------------------------------------

--- Startbereich: Rückwand, Boden, 8 Spawnpunkte (gleiche X-Position, gestaffelte Tiefe), Startlinie.
function MapBuilder:Start(length: number?)
	local len = length or 60
	local theme = self.Theme
	self:Box(-48, self.Y - self.Thickness, -40, self.Y + 70, { Name = "StartWall", Color = theme.Wall, Material = theme.GroundMaterial })
	self:Ground(-40, len, self.Y)
	for i = 0, 7 do
		self:SpawnPoint(22, self.Y, -3.5 + i)
	end
	self:Checkpoint(22, self.Y)
	self.StartLocalX = 34
	self:Deco(Vector3.new(0.6, 0.12, DEPTH), CFrame.new(self:W(34, self.Y + 0.07, 0)), rgb(255, 255, 255), NEON, { Name = "StartLine" })
	self:Sign(34, self.Y + 16, "START", nil, { Width = 12, Height = 4 })
	self:_node(10, self.Y)
	self.X = len
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
	self:Box(x1 + 4, ceilingBottom, x1 + 4 + length, y + 15.6, { Name = "TunnelCeiling", Color = theme.Wall, Material = theme.GroundMaterial })
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
end

--- Schacht für Wall-Jumps. Rechts wartet die höhere Ebene.
function MapBuilder:WallClimb(height: number, width: number?, opts)
	opts = opts or {}
	local theme = self.Theme
	local shaft = width or 14
	local x0, y0 = self.X, self.Y
	local wallX = x0 + 4 + shaft
	self:Ground(x0, wallX, y0)
	-- Hängende linke Wand (unten offen, damit man hineinläuft)
	self:Box(x0 + 2, y0 + 7, x0 + 4, y0 + height + 12, { Name = "ClimbWall", Color = theme.Wall, Material = theme.GroundMaterial })
	-- Rechte Wand = Block bis zur oberen Ebene
	self:Box(wallX, y0 - self.Thickness, wallX + 8, y0 + height - 1, { Name = "ClimbBlock", Color = theme.Wall, Material = theme.GroundMaterial })
	self:Ground(wallX, wallX + 8, y0 + height, { Thickness = 1 })
	if opts.Anchor ~= false then
		self:Anchor(x0 + 4 + shaft * 0.5, y0 + height + 12)
	end
	self.X = wallX + 8
	self.Y = y0 + height
	self:_node(wallX + 4, self.Y)
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
	self:Deco(Vector3.new(2.6, 1.4, DEPTH), CFrame.new(self:W(bx, self.Y + 16.7, 0)), theme.Wall, Enum.Material.Metal, { Name = "BarrierEmitter" })
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

--- Ziellinie mit Auslaufzone und Endwand.
function MapBuilder:Finish(length: number?)
	local len = length or 70
	local theme = self.Theme
	local x0 = self.X
	self:Ground(x0, x0 + len, self.Y)
	local fx = x0 + 14
	self.FinishLocalX = fx
	-- Schachbrett-Banner hinter der Spur
	local z = -DEPTH / 2 - 0.4
	for row = 0, 9 do
		for col = 0, 1 do
			local white = (row + col) % 2 == 0
			self:Deco(
				Vector3.new(2, 2, 0.4),
				CFrame.new(self:W(fx - 1 + col * 2, self.Y + 1 + row * 2, z)),
				if white then rgb(245, 245, 245) else rgb(20, 20, 24),
				Enum.Material.SmoothPlastic,
				{ Name = "FinishBanner" }
			)
		end
	end
	self:Deco(Vector3.new(0.8, 0.14, DEPTH), CFrame.new(self:W(fx, self.Y + 0.08, 0)), rgb(255, 255, 255), NEON, { Name = "FinishLine" })
	self:Sign(fx, self.Y + 26, "ZIEL", nil, { Width = 12, Height = 4, Color = rgb(255, 220, 80) })
	self:Box(x0 + len, self.Y - self.Thickness, x0 + len + 8, self.Y + 70, { Name = "EndWall", Color = theme.Wall, Material = theme.GroundMaterial })
	self.X = x0 + len
end

------------------------------------------------------------------------
-- Dekoration
------------------------------------------------------------------------

local function emitter(parent: Instance, props)
	local e = Instance.new("ParticleEmitter")
	for key, value in props do
		e[key] = value
	end
	e.Parent = parent
	return e
end

function MapBuilder:_decorCity()
	local theme, rng = self.Theme, self.Rng
	local base = self.MinY - 40
	local x = self.MinX - 80
	while x < self.MaxX + 80 do
		local w = rng:NextNumber(16, 34)
		local h = rng:NextNumber(70, 200)
		local d = rng:NextNumber(14, 30)
		local front = -rng:NextNumber(26, 70)
		local zc = front - d / 2
		local shade = rng:NextInteger(16, 30)
		self:Deco(Vector3.new(w, h, d), CFrame.new(self:W(x + w / 2, base + h / 2, zc)), rgb(shade, shade, shade + 16), Enum.Material.SmoothPlastic, { Name = "Building" })
		for _ = 1, rng:NextInteger(1, 3) do
			local sy = base + rng:NextNumber(0.35, 0.95) * h
			local color = if rng:NextNumber() < 0.5 then theme.Accent else theme.Accent2
			self:Deco(Vector3.new(w * 0.8, 0.5, 0.2), CFrame.new(self:W(x + w / 2, sy, front + 0.1)), color, NEON, { Name = "Window" })
		end
		x += w + rng:NextNumber(3, 12)
	end
	x = self.MinX - 200
	while x < self.MaxX + 200 do
		local w = rng:NextNumber(40, 70)
		local h = rng:NextNumber(140, 320)
		self:Deco(Vector3.new(w, h, 30), CFrame.new(self:W(x + w / 2, base + h / 2, -160)), rgb(14, 12, 28), Enum.Material.SmoothPlastic, { Name = "FarBuilding" })
		if rng:NextNumber() < 0.6 then
			self:Deco(Vector3.new(w * 0.6, 1, 0.3), CFrame.new(self:W(x + w / 2, base + h * 0.8, -144.8)), theme.Accent2, NEON, { Name = "FarSign", Transparency = 0.2 })
		end
		x += w + rng:NextNumber(5, 25)
	end
end

function MapBuilder:_decorIndustrial()
	local theme, rng = self.Theme, self.Rng
	local base = self.MinY - 30
	-- Lavasee über die gesamte Länge (tödlich)
	self:Hazard(self.MinX - 120, base - 8, self.MaxX + 120, base, "Lava", { Depth = 220 })
	local x = self.MinX - 60
	while x < self.MaxX + 60 do
		-- Schornstein mit Rauch
		local h = rng:NextNumber(60, 140)
		local z = -rng:NextNumber(40, 90)
		local stack = self:Deco(Vector3.new(h, 8, 8), CFrame.new(self:W(x, base + h / 2, z)) * CFrame.Angles(0, 0, math.rad(90)), rgb(70, 60, 55), Enum.Material.Metal, { Name = "Smokestack", Shape = Enum.PartType.Cylinder })
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
			Color = ColorSequence.new(rgb(60, 55, 55)),
			SpreadAngle = Vector2.new(10, 10),
			Acceleration = Vector3.new(4, 2, 0),
		})
		-- Rohrleitung
		local pipeY = base + rng:NextNumber(30, 90)
		local pipeLen = rng:NextNumber(40, 90)
		self:Deco(Vector3.new(pipeLen, 3, 3), CFrame.new(self:W(x + pipeLen / 2, pipeY, -14 - rng:NextNumber(0, 8))), rgb(110, 95, 80), Enum.Material.Metal, { Name = "Pipe", Shape = Enum.PartType.Cylinder })
		x += rng:NextNumber(70, 130)
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

function MapBuilder:_decorSky()
	local rng = self.Rng
	-- Wolkenmeer unter der Strecke
	local cloudY = self.MinY - 50
	local x = self.MinX - 200
	while x < self.MaxX + 200 do
		self:Deco(Vector3.new(160, 8, 200), CFrame.new(self:W(x + 80, cloudY + rng:NextNumber(-3, 3), -60)), rgb(250, 252, 255), Enum.Material.SmoothPlastic, { Name = "CloudSea", Transparency = 0.15 })
		x += 150
	end
	-- Wolkenhaufen und schwebende Inseln
	x = self.MinX - 80
	while x < self.MaxX + 80 do
		local cy = rng:NextNumber(self.MinY - 10, self.MaxY + 70)
		local cz = -rng:NextNumber(40, 160)
		for i = 1, rng:NextInteger(3, 5) do
			local r = rng:NextNumber(8, 18)
			self:Deco(Vector3.new(r, r, r), CFrame.new(self:W(x + i * r * 0.6, cy + rng:NextNumber(-3, 3), cz)), rgb(255, 255, 255), Enum.Material.SmoothPlastic, { Name = "Cloud", Shape = Enum.PartType.Ball, Transparency = 0.1 })
		end
		if rng:NextNumber() < 0.45 then
			local iy = rng:NextNumber(self.MinY, self.MaxY + 40)
			local iz = -rng:NextNumber(30, 90)
			local w = rng:NextNumber(14, 30)
			self:Deco(Vector3.new(w, 6, w * 0.6), CFrame.new(self:W(x, iy, iz)), self.Theme.Ground, Enum.Material.Cobblestone, { Name = "Island" })
			self:Deco(Vector3.new(w, 1, w * 0.6), CFrame.new(self:W(x, iy + 3.5, iz)), self.Theme.Top, Enum.Material.Grass, { Name = "IslandTop" })
			self:Deco(Vector3.new(w * 0.6, 8, w * 0.4), CFrame.new(self:W(x, iy - 6, iz)), self.Theme.Ground, Enum.Material.Cobblestone, { Name = "IslandRoot", Wedge = false })
			if rng:NextNumber() < 0.6 then
				local ph = rng:NextNumber(10, 24)
				self:Deco(Vector3.new(ph, 2.4, 2.4), CFrame.new(self:W(x + w * 0.25, iy + 4 + ph / 2, iz)) * CFrame.Angles(0, 0, math.rad(90)), self.Theme.Wall, Enum.Material.Marble, { Name = "RuinPillar", Shape = Enum.PartType.Cylinder })
			end
		end
		x += rng:NextNumber(50, 90)
	end
end

function MapBuilder:_decorGlacier()
	local rng = self.Rng
	local base = self.MinY - 40
	-- Berggipfel (zwei Keile ergeben einen Gipfel)
	local x = self.MinX - 150
	while x < self.MaxX + 150 do
		local w = rng:NextNumber(80, 160)
		local h = rng:NextNumber(120, 260)
		local z = -rng:NextNumber(120, 200)
		local color = rgb(225, 235, 248)
		self:Deco(Vector3.new(30, h, w / 2), CFrame.new(self:W(x - w / 4, base + h / 2, z)) * CFrame.Angles(0, math.rad(90), 0), color, Enum.Material.Snow, { Name = "Peak", Wedge = true })
		self:Deco(Vector3.new(30, h, w / 2), CFrame.new(self:W(x + w / 4, base + h / 2, z)) * CFrame.Angles(0, math.rad(-90), 0), color, Enum.Material.Snow, { Name = "Peak", Wedge = true })
		x += w * rng:NextNumber(0.6, 1)
	end
	-- Eiskristalle
	x = self.MinX
	while x < self.MaxX do
		local cy = rng:NextNumber(self.MinY - 20, self.MaxY + 30)
		self:Deco(Vector3.new(1.5, rng:NextNumber(6, 14), 1.5), CFrame.new(self:W(x, cy, -rng:NextNumber(16, 50))) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-25, 25))), rgb(150, 230, 255), NEON, { Name = "Crystal", Transparency = 0.2 })
		x += rng:NextNumber(30, 60)
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
	-- Eiswasser ganz unten
	self:Hazard(self.MinX - 120, base - 6, self.MaxX + 120, base, "IceWater", { Depth = 200 })
end

function MapBuilder:_decorJungle()
	local theme, rng = self.Theme, self.Rng
	local base = self.MinY - 36
	local x = self.MinX - 60
	while x < self.MaxX + 60 do
		local z = -rng:NextNumber(14, 70)
		local h = rng:NextNumber(60, 140)
		local trunkY = base + h / 2
		self:Deco(Vector3.new(h, 4, 4), CFrame.new(self:W(x, trunkY, z)) * CFrame.Angles(0, 0, math.rad(90)), rgb(90, 65, 40), Enum.Material.Wood, { Name = "Trunk", Shape = Enum.PartType.Cylinder })
		for _ = 1, rng:NextInteger(2, 4) do
			local r = rng:NextNumber(14, 26)
			local leaf = rgb(rng:NextInteger(40, 80), rng:NextInteger(110, 160), rng:NextInteger(40, 70))
			self:Deco(Vector3.new(r, r * 0.7, r), CFrame.new(self:W(x + rng:NextNumber(-8, 8), base + h + rng:NextNumber(-6, 6), z)), leaf, Enum.Material.Grass, { Name = "Leaves", Shape = Enum.PartType.Ball })
		end
		if rng:NextNumber() < 0.5 then
			local vineLen = rng:NextNumber(20, 50)
			self:Deco(Vector3.new(vineLen, 0.5, 0.5), CFrame.new(self:W(x + 4, self.MaxY + 40 - vineLen / 2, -8)) * CFrame.Angles(0, 0, math.rad(90)), rgb(60, 120, 50), Enum.Material.Grass, { Name = "Vine", Shape = Enum.PartType.Cylinder })
		end
		x += rng:NextNumber(30, 60)
	end
	-- Glühwürmchen
	x = self.MinX
	while x < self.MaxX do
		local holder = self:Deco(Vector3.new(150, 40, 30), CFrame.new(self:W(x + 75, self.MinY + 20, -14)), Color3.new(), nil, { Name = "Fireflies", Transparency = 1 })
		emitter(holder, {
			Rate = 4,
			Lifetime = NumberRange.new(3, 5),
			Speed = NumberRange.new(0.5, 1.5),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(1, 0) }),
			Color = ColorSequence.new(theme.Accent2),
			LightEmission = 1,
			SpreadAngle = Vector2.new(180, 180),
		})
		x += 160
	end
	-- Fluss ganz unten
	self:Hazard(self.MinX - 120, base - 6, self.MaxX + 120, base, "River", { Depth = 200 })
end

function MapBuilder:_decorHub()
	local theme, rng = self.Theme, self.Rng
	for i = 1, 14 do
		local x = self.MinX + (self.MaxX - self.MinX) * (i - 0.5) / 14
		local h = rng:NextNumber(60, 160)
		local z = -rng:NextNumber(40, 90)
		self:Deco(Vector3.new(rng:NextNumber(16, 28), h, 20), CFrame.new(self:W(x, -30 + h / 2, z)), rgb(22, 24, 40), Enum.Material.SmoothPlastic, { Name = "Tower" })
		self:Deco(Vector3.new(14, 0.5, 0.2), CFrame.new(self:W(x, -30 + h * 0.8, z + 10.1)), if i % 2 == 0 then theme.Accent else theme.Accent2, NEON, { Name = "TowerLight" })
	end
	for i = 1, 6 do
		self:Deco(Vector3.new(0.4, 18, 18), CFrame.new(self:W(-140 + i * 40, 60 + (i % 2) * 14, -30)) * CFrame.Angles(0, math.rad(90), 0), if i % 2 == 0 then theme.Accent else theme.Accent2, NEON, { Name = "HoloRing", Shape = Enum.PartType.Cylinder, Transparency = 0.5 })
	end
end

--- Erzeugt die Hintergrund-Dekoration passend zum Theme.
function MapBuilder:Decorate()
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
	end
end

------------------------------------------------------------------------
-- Ergebnis
------------------------------------------------------------------------

--- Liefert die fertige MapInstance (Tabelle mit allen Laufzeitdaten).
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
		Bounds = {
			MinX = o.X + self.MinX,
			MaxX = o.X + self.MaxX,
			MinY = o.Y + self.MinY,
			MaxY = o.Y + self.MaxY,
		},
	}
end

return MapBuilder
