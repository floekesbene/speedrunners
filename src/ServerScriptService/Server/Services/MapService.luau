--[[
	MapService  (ModuleScript)
	Pfad: ServerScriptService/Server/Services/MapService

	Lädt, aktiviert, setzt zurück und entlädt Maps ("Regionen").
	Regionen:
		"Lobby"                 – immer geladen (Workspace/Lobby)
		"Race"                  – aktuelle Rennstrecke (Workspace/ActiveMap)
		"Tutorial"              – Trainings-Tutorial (Workspace/Practice)
		"Practice_<MapId>"      – Trainingskopien der Rennstrecken (Workspace/Practice)

	Jede Region ist eine MapInstance (siehe MapBuilder:Result()). Beim Laden
	werden Greifhaken-Anker und Item-Boxen bei den zuständigen Services
	registriert, beim Entladen wieder entfernt. Das Hintergrund-Terrain einer
	Region (MapInstance.TerrainFills) wird beim Entladen gelöscht, indem jede
	aufgezeichnete Füllung leicht vergrößert mit Luft überschrieben wird.

	Öffentliche API:
		:GetRegion(regionId) -> MapInstance?
		:LoadRaceMap(mapId) -> MapInstance
		:UnloadRaceMap()
		:ResetRaceMap()
		:EnsurePracticeRegion(courseId) -> MapInstance?
		:PeekNextMap() -> mapId
		:AdvanceRotation() -> mapId
		:IsInHazard(region, position, previous?) -> (boolean, string?)
		:FindCheckpointIndex(region, x) -> number
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local MapDefinitions = require(Shared.MapDefinitions)

local MapBuilder = require(script.Parent.Parent.Modules.MapBuilder)

local MapService = {}

local TERRAIN_ERASE_MARGIN = 4 -- eine Voxelbreite Reserve beim Löschen

function MapService:Init(services)
	self.Services = services
	self.Regions = {}
	self.Rotation = {}
	self.RotationIndex = 0
	self.Rng = Random.new()

	self.Folders = {}
	for _, name in { "Lobby", "ActiveMap", "Practice" } do
		local folder = workspace:FindFirstChild(name)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = name
			folder.Parent = workspace
		end
		self.Folders[name] = folder
	end

	self.OverlapParams = OverlapParams.new()
	self.OverlapParams.FilterType = Enum.RaycastFilterType.Include
	self.OverlapParams.FilterDescendantsInstances = {}
end

function MapService:Start()
	self:_buildRegion("Lobby", MapDefinitions.Lobby, Config.World.LobbyOrigin, self.Folders.Lobby, "Lobby")
	self:_refillRotation()
	self:_publishNextMap()
end

------------------------------------------------------------------------
-- Aufbau
------------------------------------------------------------------------

function MapService:_buildRegion(regionId: string, definition, origin: Vector3, parent: Instance, mapId: string)
	local templateModule = ServerStorage:WaitForChild("MapTemplates"):FindFirstChild(definition.Template)
	if not templateModule then
		error("[MapService] Map-Vorlage fehlt: " .. tostring(definition.Template))
	end
	local template = require(templateModule)
	local builder = MapBuilder.new({
		Name = regionId,
		RegionId = regionId,
		MapId = mapId,
		Origin = origin,
		Theme = definition.Theme,
		Difficulty = definition.Difficulty or 2,
		Seed = definition.Seed or 1,
	})
	template(builder)
	local instance = builder:Result()
	instance.Definition = definition
	instance.Model.Parent = parent
	self.Regions[regionId] = instance

	for _, anchor in instance.Anchors do
		self.Services.GrappleService:RegisterAnchor(anchor, regionId)
	end
	self.Services.PowerUpService:RegisterRegion(instance)
	self:_rebuildOverlap()
	return instance
end

function MapService:_destroyRegion(regionId: string)
	local instance = self.Regions[regionId]
	if not instance then
		return
	end
	self.Services.GrappleService:UnregisterRegion(regionId)
	self.Services.PowerUpService:UnregisterRegion(regionId)
	self.Regions[regionId] = nil
	self:_eraseTerrain(instance)
	instance.Model:Destroy()
	self:_rebuildOverlap()
end

--- Löscht das Terrain einer Region: jede aufgezeichnete Füllung wird leicht
--- vergrößert mit Luft gefüllt (Keile über ihren umschließenden Quader).
function MapService:_eraseTerrain(instance)
	local fills = instance.TerrainFills
	if not fills or #fills == 0 then
		return
	end
	local terrain = workspace.Terrain
	local air = Enum.Material.Air
	local margin = TERRAIN_ERASE_MARGIN
	local grow = Vector3.new(margin * 2, margin * 2, margin * 2)
	for _, fill in fills do
		local ok, err = pcall(function()
			if fill.Kind == "Ball" then
				terrain:FillBall(fill.Center, fill.Radius + margin, air)
			elseif fill.Kind == "Cylinder" then
				terrain:FillCylinder(fill.CFrame, fill.Height + margin * 2, fill.Radius + margin, air)
			else
				terrain:FillBlock(fill.CFrame, fill.Size + grow, air)
			end
		end)
		if not ok then
			warn("[MapService] Terrain konnte nicht gelöscht werden: " .. tostring(err))
		end
	end
	instance.TerrainFills = {}
end

function MapService:_rebuildOverlap()
	local list = {}
	for _, instance in self.Regions do
		table.insert(list, instance.HazardFolder)
	end
	self.OverlapParams.FilterDescendantsInstances = list
end

------------------------------------------------------------------------
-- Öffentliche API
------------------------------------------------------------------------

function MapService:GetRegion(regionId: string)
	return self.Regions[regionId]
end

function MapService:GetRaceMap()
	return self.Regions.Race
end

--- Baut die Rennstrecke `mapId` in Workspace/ActiveMap (ersetzt eine vorhandene).
function MapService:LoadRaceMap(mapId: string)
	local definition = MapDefinitions.Get(mapId)
	if not definition then
		error("[MapService] Unbekannte Map: " .. tostring(mapId))
	end
	self:UnloadRaceMap()
	local instance = self:_buildRegion("Race", definition, Config.World.RaceOrigin, self.Folders.ActiveMap, mapId)
	return instance
end

function MapService:UnloadRaceMap()
	self:_destroyRegion("Race")
end

--- Setzt Laufzeitobjekte der Rennstrecke zurück (Fallen, Item-Boxen).
function MapService:ResetRaceMap()
	local instance = self.Regions.Race
	if instance then
		instance.RuntimeFolder:ClearAllChildren()
		self.Services.PowerUpService:ResetRegion("Race")
	end
end

--- Baut (falls nötig) die Trainingsregion für "Tutorial" oder eine Map-Id.
function MapService:EnsurePracticeRegion(courseId: string)
	local regionId = self.Services.PracticeService:RegionIdFor(courseId)
	if self.Regions[regionId] then
		return self.Regions[regionId]
	end
	if courseId == "Tutorial" then
		return self:_buildRegion(regionId, MapDefinitions.Tutorial, Config.World.TutorialOrigin, self.Folders.Practice, "Tutorial")
	end
	local definition = MapDefinitions.Get(courseId)
	if not definition then
		return nil
	end
	local index = table.find(MapDefinitions.Order, courseId) or 1
	local origin = Config.World.PracticeOriginStart - Vector3.new((index - 1) * Config.World.PracticeOriginSpacing, 0, 0)
	return self:_buildRegion(regionId, definition, origin, self.Folders.Practice, courseId)
end

function MapService:_refillRotation()
	self.Rotation = Util.Shuffle(table.clone(MapDefinitions.Order), self.Rng)
	self.RotationIndex = 1
end

function MapService:PeekNextMap(): string
	if self.RotationIndex < 1 or self.RotationIndex > #self.Rotation then
		self:_refillRotation()
	end
	return self.Rotation[self.RotationIndex]
end

--- Liefert die nächste Map und rückt die Rotation weiter.
function MapService:AdvanceRotation(): string
	local mapId = self:PeekNextMap()
	self.RotationIndex += 1
	if self.RotationIndex > #self.Rotation then
		local last = mapId
		self:_refillRotation()
		-- Dieselbe Map nicht zweimal hintereinander
		if self.Rotation[1] == last and #self.Rotation > 1 then
			self.Rotation[1], self.Rotation[2] = self.Rotation[2], self.Rotation[1]
		end
	end
	self:_publishNextMap()
	return mapId
end

function MapService:_publishNextMap()
	local state = ReplicatedStorage:FindFirstChild("GameState")
	if state then
		state:SetAttribute("NextMapId", self:PeekNextMap())
	end
end

local HAZARD_BOX = Vector3.new(1.6, 4.6, 1.6)

local function hazardActive(part: BasePart, now: number): boolean
	local period = part:GetAttribute("HazardPeriod")
	if not period then
		return true
	end
	local onTime = part:GetAttribute("HazardOnTime") or period / 2
	local offset = part:GetAttribute("HazardOffset") or 0
	return (now + offset) % period < onTime
end

--- Prüft, ob die Spielfigur (Root-Position) eine Gefahr der Region berührt.
--- Mit `previous` wird die Strecke seit dem letzten Tick geprüft, damit
--- schnelle Spieler dünne Barrieren nicht "überspringen".
function MapService:IsInHazard(region, position: Vector3, previous: Vector3?): (boolean, string?)
	if position.Y < region.KillY then
		return true, "Fall"
	end
	local from = previous or position
	local delta = position - from
	if delta.Magnitude > 40 then
		-- Teleport oder Respawn seit dem letzten Tick: nur aktuelle Position prüfen.
		from = position
		delta = Vector3.zero
	end
	-- Schneller Vorabtest mit einer Box um die gesamte Bewegung
	local center = (from + position) / 2
	local size = HAZARD_BOX + Vector3.new(math.abs(delta.X), math.abs(delta.Y), 0)
	local parts = workspace:GetPartBoundsInBox(CFrame.new(center), size, self.OverlapParams)
	if #parts == 0 then
		return false
	end
	local now = workspace:GetServerTimeNow()
	local candidates = {}
	for _, part in parts do
		if part:IsDescendantOf(region.HazardFolder) and hazardActive(part, now) then
			table.insert(candidates, part)
		end
	end
	if #candidates == 0 then
		return false
	end
	-- Genaue Prüfung entlang der Bewegung
	local steps = math.clamp(math.ceil(delta.Magnitude / 1.2), 1, 16)
	for i = 0, steps do
		local point = from:Lerp(position, i / steps)
		local half = HAZARD_BOX / 2
		for _, part in candidates do
			local localPoint = part.CFrame:PointToObjectSpace(point)
			local partHalf = part.Size / 2
			if
				math.abs(localPoint.X) <= partHalf.X + half.X
				and math.abs(localPoint.Y) <= partHalf.Y + half.Y
				and math.abs(localPoint.Z) <= partHalf.Z + half.Z
			then
				return true, part:GetAttribute("HazardKind")
			end
		end
	end
	return false
end

--- Index des letzten erreichten Checkpoints für eine X-Position.
function MapService:FindCheckpointIndex(region, x: number): number
	local index = 1
	for i, checkpoint in region.Checkpoints do
		if x >= checkpoint.X - 1 then
			index = i
		end
	end
	return index
end

return MapService
