--[[
	EffectsController  (ModuleScript)
	Pfad: StarterPlayer/StarterPlayerScripts/Client/Controllers/EffectsController

	Alle visuellen Effekte – komplett ohne externe Assets (Parts, Beams, Trails,
	ParticleEmitter mit Standardtextur, PointLight, Highlight, Explosion,
	Lighting-Effekte, Sky mit Standardtexturen, TweenService):

		Beleuchtung je Region (Lobby, Strecke, Training) aus Theme.Lighting:
			Lighting, Atmosphere, Sky (nur Sterne/Sonne/Mond), Bloom,
			ColorCorrection, SunRays, Tiefenunschärfe (nur der Hintergrund wird
			leicht weich, Spielebene und Läufer bleiben scharf). Fehlende Felder
			bekommen Standardwerte (LIGHT_DEFAULTS), Wechsel werden getweent.
			Zusätzlich ein weiches Licht an der verfolgten Figur (v.a. nachts).
		Bewegung:
			Speed-Lines und Rand-Vignette bei hohem Tempo (Bildschirm, gepoolt),
			Laufstaub an den Füßen (Farbe aus dem Theme), Slide-Staub und -Funken,
			Wall-Slide-Funken, Lande-Schockwelle + Staub + Kamerastoß,
			Sprung-/Wall-Jump-/Pad-Effekte, Dash-Nachbilder (gepoolte Geister),
			Boost-Aura (Flammen, Glut, Licht)
		Greifhaken: leuchtendes Seil mit Glow, Ausschuss-Animation und
			Nachschwingen, Funken am Anker; Zielmarkierung (Lock-on-Animation,
			rotierender Ring, Highlight am Anker, Farbe zeigt Abklingzeit)
		Rennen: Checkpoint-Blitz (Lichtsäule, Ring, Bildschirmblitz),
			Gefahrenwand (geschichtete Neon-Ebenen, wandernde Pulse, Glut,
			getönte Zone), Ausscheiden (Explosion, Trümmer, Rauch),
			Respawn-Lichtsäule, Siegesanimationen (Konfetti, Feuerwerk, Blitz,
			Goldregen) mit Siegerlicht
		Sonstiges: rotierende Item-Boxen, blinkende Zeit-Barrieren,
			Status (Schild, Freeze, Betäubung)

	"Reduzierte Effekte" in den Einstellungen schaltet Tiefenunschärfe und
	Sonnenstrahlen ab und verringert Partikelmengen, Speed-Lines und Nachbilder.

	API (auch für andere Module):
		:Burst(position, color, count, options?)
		:Ring(position, color, radius, duration, options?)   options.Flat = am Boden
		:Flash(position, color, size, duration)
		:ScreenFlash(color, strength, duration)
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local ItemDefinitions = require(Shared.ItemDefinitions)
local CosmeticApplier = require(Shared.CosmeticApplier)
local RunnerRig = require(Shared.RunnerRig)

local player = Players.LocalPlayer
local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local FEET = Config.Character.FeetOffset
local MAX_RUN = Config.Movement.MaxRunSpeed

local NEAR_DISTANCE = 400
local SPEED_LINES = 14
local SPEED_LINES_REDUCED = 6
local GHOST_SETS = 10
local GHOST_LIFE = 0.32
local ROPE_SHOOT_TIME = 0.09
local DANGER = rgb(255, 40, 70)
local GREY = rgb(150, 150, 160)
local BOOST_PURPLE = rgb(200, 120, 255)

-- Standardwerte für Theme.Lighting. Fehlende oder falsch typisierte Felder
-- einer Map werden hiermit ergänzt.
local LIGHT_DEFAULTS = {
	ClockTime = 14,
	Brightness = 2.2,
	Ambient = rgb(105, 105, 120),
	OutdoorAmbient = rgb(140, 140, 155),
	FogColor = rgb(190, 210, 240),
	FogStart = 400,
	FogEnd = 3000,
	ColorShiftTop = rgb(0, 0, 0),
	ColorShiftBottom = rgb(0, 0, 0),
	GeographicLatitude = 41.7,
	ExposureCompensation = 0.1,
	EnvironmentDiffuseScale = 1,
	EnvironmentSpecularScale = 1,
	ShadowSoftness = 0.2,
	AtmosphereDensity = 0.25,
	AtmosphereOffset = 0.2,
	AtmosphereColor = rgb(200, 220, 255),
	AtmosphereDecay = rgb(130, 160, 220),
	Haze = 0.8,
	Glare = 0.2,
	Tint = rgb(255, 255, 255),
	Saturation = 0.15,
	Contrast = 0.08,
	ColorBrightness = 0.02,
	BloomIntensity = 0.6,
	BloomSize = 24,
	BloomThreshold = 1.1,
	SunRaysIntensity = 0.05,
	SunRaysSpread = 0.5,
	DofFarIntensity = 0.12,
	DofInFocusRadius = 30,
	StarCount = 3000,
	CelestialBodiesShown = true,
	SunAngularSize = 18,
	MoonAngularSize = 11,
	PlayerLight = -1, -- Helligkeit des Figurenlichts (-1 = automatisch nach Uhrzeit)
}

local EffectsController = {}

------------------------------------------------------------------------
-- Hilfen
------------------------------------------------------------------------

local function fxPart(props): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = props.Material or Enum.Material.Neon
	part.Color = props.Color or WHITE
	part.Size = props.Size or Vector3.one
	part.Transparency = props.Transparency or 0
	if props.Shape then
		part.Shape = props.Shape
	end
	part.CFrame = props.CFrame or CFrame.new()
	part.Name = props.Name or "FX"
	part.Parent = props.Parent
	return part
end

local function worldAttachment(name: string): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Parent = workspace.Terrain
	return attachment
end

local function sequence(...): NumberSequence
	local points = { ... }
	local keypoints = {}
	for i = 1, #points, 2 do
		table.insert(keypoints, NumberSequenceKeypoint.new(points[i], points[i + 1]))
	end
	return NumberSequence.new(keypoints)
end

local function circle(parent: Instance, size: number, color: Color3, transparency: number, zIndex: number): Frame
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(size, size)
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency
	frame.BorderSizePixel = 0
	frame.ZIndex = zIndex
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame
	frame.Parent = parent
	return frame
end

local function easeOut(t: number): number
	return 1 - (1 - t) * (1 - t)
end

function EffectsController:_reduced(): boolean
	return self.Ctx.ClientState:GetSetting("ReducedEffects") == true
end

function EffectsController:_tween(instance: Instance, info: TweenInfo?, goal)
	if info then
		TweenService:Create(instance, info, goal):Play()
	else
		for key, value in goal do
			(instance :: any)[key] = value
		end
	end
end

------------------------------------------------------------------------
-- Öffentliche Einmal-Effekte
------------------------------------------------------------------------

--- Partikelstoß an einer Weltposition.
--- options: LifeMin, LifeMax, SpeedMin, SpeedMax, Spread (Vector2), Size, SizeEnd,
---          Transparency0, LightEmission, LightInfluence, Acceleration, Drag,
---          Direction (NormalId), Spin (Grad/s)
function EffectsController:Burst(position: Vector3, color, count: number, options)
	options = options or {}
	if self.Reduced then
		count = math.ceil(count * 0.35)
	end
	local attachment = Instance.new("Attachment")
	attachment.Position = position
	attachment.Parent = workspace.Terrain
	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	emitter.Lifetime = NumberRange.new(options.LifeMin or 0.4, options.LifeMax or 0.9)
	emitter.Speed = NumberRange.new(options.SpeedMin or 6, options.SpeedMax or 16)
	emitter.SpreadAngle = options.Spread or Vector2.new(180, 180)
	emitter.Size = sequence(0, options.Size or 0.6, 1, options.SizeEnd or 0)
	emitter.Transparency = sequence(0, options.Transparency0 or 0, 1, 1)
	if typeof(color) == "ColorSequence" then
		emitter.Color = color
	else
		emitter.Color = ColorSequence.new(color)
	end
	local lightEmission = options.LightEmission or 0.8
	emitter.LightEmission = lightEmission
	emitter.LightInfluence = options.LightInfluence or (if lightEmission > 0.5 then 0 else 1)
	emitter.Acceleration = options.Acceleration or Vector3.zero
	emitter.Drag = options.Drag or 2
	emitter.EmissionDirection = options.Direction or Enum.NormalId.Top
	if options.Spin then
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-options.Spin, options.Spin)
	end
	emitter.Parent = attachment
	emitter:Emit(count)
	Debris:AddItem(attachment, (options.LifeMax or 0.9) + 0.5)
end

--- Sich ausdehnender Ring. Standard: Scheibe zur Kamera; options.Flat = flach am Boden.
--- options: Flat, Transparency (Start), Thickness, Material
function EffectsController:Ring(position: Vector3, color: Color3, radius: number, duration: number, options)
	options = options or {}
	local thickness = options.Thickness or (if options.Flat then 0.15 else 0.4)
	local orientation = if options.Flat then CFrame.Angles(0, 0, math.rad(90)) else CFrame.Angles(0, math.rad(90), 0)
	local ring = fxPart({
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(thickness, 2, 2),
		CFrame = CFrame.new(position) * orientation,
		Color = color,
		Material = options.Material,
		Transparency = options.Transparency or 0.2,
		Parent = self.Folder,
	})
	local tween = TweenService:Create(ring, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(thickness, radius * 2, radius * 2),
		Transparency = 1,
	})
	tween:Play()
	Debris:AddItem(ring, duration + 0.1)
end

--- Aufblitzende, wachsende Leuchtkugel.
function EffectsController:Flash(position: Vector3, color: Color3, size: number, duration: number)
	local ball = fxPart({
		Name = "Flash",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * math.max(0.5, size * 0.25),
		CFrame = CFrame.new(position),
		Color = color,
		Transparency = 0.05,
		Parent = self.Folder,
	})
	TweenService:Create(ball, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * size,
		Transparency = 1,
	}):Play()
	Debris:AddItem(ball, duration + 0.1)
end

--- Kurzer farbiger Bildschirmblitz (0 < strength <= 1).
function EffectsController:ScreenFlash(color: Color3, strength: number, duration: number)
	local frame = self.FlashFrame
	if not frame then
		return
	end
	if self.Reduced then
		strength *= 0.5
	end
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = 1 - math.clamp(strength, 0, 1)
	TweenService:Create(frame, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()
end

------------------------------------------------------------------------
-- Init / Start
------------------------------------------------------------------------

function EffectsController:Init(ctx)
	self.Ctx = ctx
	self.Folder = Instance.new("Folder")
	self.Folder.Name = "VR_ClientFX"
	self.Folder.Parent = workspace
	self.Ropes = {}
	self.Status = {}
	self.ZoneVisualX = nil
	self.ZoneVisible = false
	self.CurrentTheme = nil
	self.Light = LIGHT_DEFAULTS
	self.LightApplied = false
	self.ClockTime = nil
	self.Accent = rgb(0, 214, 255)
	self.DustColor = rgb(225, 220, 210)
	self.ThemeVersion = 0
	self.Reduced = false
	self.SpeedIntensity = 0
	self.LineDirection = 1
	self.LinesActive = 0
	self.GhostPool = {}
	self.GhostCursor = 0
	self.LastAfterimage = 0
	self.DofDistance = 0
	self.MarkerTarget = nil
	self.MarkerLockAt = 0
	self.MarkerColor = nil

	self:_initLighting()
	self:_initMarker()
	self:_initZone()
	self:_initScreen()
end

function EffectsController:_initLighting()
	self.Atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	self.Atmosphere.Parent = Lighting
	-- Himmel: vorhandenen Sky nutzen, sonst einen mit Standardtexturen anlegen
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if not sky then
		sky = Instance.new("Sky")
		sky.Name = "VR_Sky"
		sky.Parent = Lighting
	end
	self.Sky = sky
	self.Bloom = Instance.new("BloomEffect")
	self.Bloom.Name = "VR_Bloom"
	self.Bloom.Parent = Lighting
	self.Color = Instance.new("ColorCorrectionEffect")
	self.Color.Name = "VR_Color"
	self.Color.Parent = Lighting
	self.SunRays = Instance.new("SunRaysEffect")
	self.SunRays.Name = "VR_SunRays"
	self.SunRays.Parent = Lighting
	-- Tiefenunschärfe: nur der weit entfernte Hintergrund wird weich
	self.Dof = Instance.new("DepthOfFieldEffect")
	self.Dof.Name = "VR_DepthOfField"
	self.Dof.NearIntensity = 0
	self.Dof.FocusDistance = 50
	self.Dof.InFocusRadius = 30
	self.Dof.FarIntensity = 0.1
	self.Dof.Parent = Lighting

	-- Weiches Licht an der verfolgten Figur
	self.PlayerLightAttachment = worldAttachment("VR_PlayerLight")
	local light = Instance.new("PointLight")
	light.Range = 16
	light.Brightness = 0.5
	light.Shadows = false
	light.Color = rgb(255, 245, 230)
	light.Parent = self.PlayerLightAttachment
	self.PlayerLight = light
end

function EffectsController:_initMarker()
	local marker = Instance.new("BillboardGui")
	marker.Name = "VR_GrappleTarget"
	marker.Size = UDim2.fromOffset(76, 76)
	marker.AlwaysOnTop = true
	marker.LightInfluence = 0
	marker.ResetOnSpawn = false
	marker.Enabled = false
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = marker
	local scale = Instance.new("UIScale")
	scale.Parent = root

	local glow = circle(root, 0.95, self.Accent, 0.82, 1)
	glow.Name = "Glow"
	local ring = circle(root, 0.6, WHITE, 1, 2)
	ring.Name = "Ring"
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = WHITE
	stroke.Parent = ring
	local gradient = Instance.new("UIGradient")
	gradient.Transparency = sequence(0, 0, 0.5, 0.55, 1, 0)
	gradient.Parent = stroke
	local dot = circle(root, 0.16, WHITE, 0, 3)
	dot.Name = "Dot"

	-- Vier Fadenkreuz-Striche, die sich langsam drehen
	local reticle = Instance.new("Frame")
	reticle.Name = "Reticle"
	reticle.AnchorPoint = Vector2.new(0.5, 0.5)
	reticle.Position = UDim2.fromScale(0.5, 0.5)
	reticle.Size = UDim2.fromScale(1, 1)
	reticle.BackgroundTransparency = 1
	reticle.ZIndex = 4
	reticle.Parent = root
	local ticks = {}
	for _, info in {
		{ UDim2.fromScale(0.5, 0.06), UDim2.fromScale(0.06, 0.2) },
		{ UDim2.fromScale(0.5, 0.94), UDim2.fromScale(0.06, 0.2) },
		{ UDim2.fromScale(0.06, 0.5), UDim2.fromScale(0.2, 0.06) },
		{ UDim2.fromScale(0.94, 0.5), UDim2.fromScale(0.2, 0.06) },
	} do
		local tick = Instance.new("Frame")
		tick.AnchorPoint = Vector2.new(0.5, 0.5)
		tick.Position = info[1]
		tick.Size = info[2]
		tick.BackgroundColor3 = WHITE
		tick.BorderSizePixel = 0
		tick.ZIndex = 4
		tick.Parent = reticle
		table.insert(ticks, tick)
	end

	marker.Parent = player:WaitForChild("PlayerGui")
	self.Marker = marker
	self.MarkerParts = {
		Scale = scale,
		Glow = glow,
		Stroke = stroke,
		Gradient = gradient,
		Dot = dot,
		Reticle = reticle,
		Ticks = ticks,
	}

	local highlight = Instance.new("Highlight")
	highlight.Name = "VR_TargetHighlight"
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillTransparency = 0.6
	highlight.OutlineTransparency = 0.1
	highlight.OutlineColor = WHITE
	highlight.Enabled = false
	highlight.Parent = self.Folder
	self.Highlight = highlight
end

function EffectsController:_initZone()
	local zone = { Glows = {}, Pulses = {} }
	-- Seitlich sichtbare Energiewand (YZ-Ebene) – wirkt durch die Perspektive räumlich
	zone.Sheet = fxPart({ Name = "DangerSheet", Size = Vector3.new(0.5, 400, 64), Color = DANGER, Transparency = 1, Parent = self.Folder })
	-- Helle Kante vor der Strecke + weicher Verlauf aus überlagerten Streifen
	zone.Line = fxPart({ Name = "DangerLine", Size = Vector3.new(0.9, 400, 0.2), Color = rgb(255, 175, 190), Transparency = 1, Parent = self.Folder })
	for i, info in { { 2.5, 0.72 }, { 5, 0.8 }, { 9, 0.87 }, { 15, 0.92 } } do
		zone.Glows[i] = {
			Part = fxPart({ Name = "DangerGlow", Size = Vector3.new(info[1], 400, 0.2), Color = DANGER, Transparency = 1, Parent = self.Folder }),
			Width = info[1],
			Base = info[2],
		}
	end
	-- Getönte Zone vorn und hinten (Teile höchstens 2048 Studs groß)
	zone.Tint = fxPart({
		Name = "DangerTint",
		Size = Vector3.new(2000, 400, 0.2),
		Color = rgb(255, 30, 60),
		Material = Enum.Material.SmoothPlastic,
		Transparency = 1,
		Parent = self.Folder,
	})
	zone.Back = fxPart({
		Name = "DangerBack",
		Size = Vector3.new(2000, 400, 0.5),
		Color = rgb(150, 10, 40),
		Material = Enum.Material.SmoothPlastic,
		Transparency = 1,
		Parent = self.Folder,
	})
	-- Wandernde Energiepulse entlang der Kante
	for i = 1, 3 do
		zone.Pulses[i] = fxPart({ Name = "DangerPulse", Size = Vector3.new(1.5, 7, 0.2), Color = WHITE, Transparency = 1, Parent = self.Folder })
	end
	-- Glut, die in die Gefahrenzone treibt
	zone.EmberSource = fxPart({ Name = "DangerEmbers", Size = Vector3.new(1, 70, 4), Transparency = 1, Parent = self.Folder })
	local embers = Instance.new("ParticleEmitter")
	embers.Enabled = false
	embers.Rate = 30
	embers.Lifetime = NumberRange.new(1, 1.8)
	embers.Speed = NumberRange.new(3, 9)
	embers.SpreadAngle = Vector2.new(25, 60)
	embers.EmissionDirection = Enum.NormalId.Left
	embers.Size = sequence(0, 0.45, 1, 0)
	embers.Color = ColorSequence.new(rgb(255, 200, 120), DANGER)
	embers.LightEmission = 1
	embers.LightInfluence = 0
	embers.Acceleration = Vector3.new(0, 6, 0)
	embers.Drag = 0.5
	embers.Parent = zone.EmberSource
	zone.Embers = embers
	self.Zone = zone
end

function EffectsController:_initScreen()
	local gui = Instance.new("ScreenGui")
	gui.Name = "VR_ScreenFX"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 1 -- unter der Spiel-UI
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Rand-Vignette bei hohem Tempo
	self.Vignette = {}
	for _, side in { 0, 1 } do
		local edge = Instance.new("Frame")
		edge.Name = "SpeedVignette"
		edge.AnchorPoint = Vector2.new(side, 0)
		edge.Position = UDim2.fromScale(side, 0)
		edge.Size = UDim2.fromScale(0.24, 1)
		edge.BackgroundColor3 = rgb(10, 12, 28)
		edge.BackgroundTransparency = 1
		edge.BorderSizePixel = 0
		local gradient = Instance.new("UIGradient")
		gradient.Transparency = sequence(0, 0, 1, 1)
		gradient.Rotation = if side == 0 then 0 else 180
		gradient.Parent = edge
		edge.Parent = gui
		table.insert(self.Vignette, edge)
	end

	-- Speed-Lines (gepoolt)
	local lines = Instance.new("Frame")
	lines.Name = "SpeedLines"
	lines.Size = UDim2.fromScale(1, 1)
	lines.BackgroundTransparency = 1
	lines.Visible = false
	lines.Parent = gui
	self.LinesFrame = lines
	self.SpeedLines = {}
	for i = 1, SPEED_LINES do
		local frame = Instance.new("Frame")
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.BackgroundColor3 = WHITE
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		local gradient = Instance.new("UIGradient")
		gradient.Transparency = sequence(0, 1, 0.55, 0.25, 0.85, 0, 1, 1)
		gradient.Parent = frame
		frame.Parent = lines
		local line = { Frame = frame, Gradient = gradient, X = 0, Y = 0, Speed = 1, Alpha = 1 }
		self:_resetLine(line, i / SPEED_LINES)
		self.SpeedLines[i] = line
	end

	-- Bildschirmblitz
	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = WHITE
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = 5
	flash.Parent = gui
	self.FlashFrame = flash

	gui.Parent = player:WaitForChild("PlayerGui")
	self.ScreenGui = gui
end

--- Setzt eine Speed-Line an eine neue Startposition (start = 0..1 über den Bildschirm verteilt).
function EffectsController:_resetLine(line, start: number?)
	local band = math.random()
	-- Nur obere und untere Bildbereiche, damit die Mitte frei bleibt
	line.Y = if band < 0.5 then 0.05 + band * 0.62 else 0.95 - (band - 0.5) * 0.62
	local length = 0.07 + math.random() * 0.16
	line.Speed = 1.1 + math.random() * 1.3
	line.Alpha = 0.35 + math.random() * 0.45
	if start then
		line.X = start * 1.4 - 0.2
	else
		line.X = if self.LineDirection > 0 then 1.15 + math.random() * 0.25 else -0.15 - math.random() * 0.25
	end
	line.Frame.Size = UDim2.new(length, 0, 0, if math.random() < 0.3 then 3 else 2)
end

function EffectsController:Start()
	local state = self.Ctx.ClientState
	local movement = self.Ctx.MovementController
	local camera = self.Ctx.CameraController

	-- Beleuchtung je Region
	local function refreshTheme()
		self:_applyTheme(state:GetRegionDefinition())
	end
	player:GetAttributeChangedSignal("InRace"):Connect(refreshTheme)
	player:GetAttributeChangedSignal("PracticeCourse"):Connect(refreshTheme)
	state.GameState:GetAttributeChangedSignal("MapId"):Connect(refreshTheme)
	state.SettingsChanged:Connect(function()
		self:_applyQuality()
	end)
	refreshTheme()
	self:_applyQuality()

	-- Bewegungs-Effekte (lokal)
	movement.Landed:Connect(function(impact, position)
		self:_landFx(impact, position)
	end)
	movement.Jumped:Connect(function(kind)
		self:_jumpFx(kind)
	end)
	movement.SlideStarted:Connect(function()
		local root = self:_localRoot()
		if root then
			local facing = movement:GetFacing()
			self:Burst(root.Position + Vector3.new(facing * 0.8, FEET + 0.3, 0), self.DustColor, 8, {
				SpeedMin = 6,
				SpeedMax = 12,
				Size = 0.9,
				SizeEnd = 2,
				Transparency0 = 0.3,
				LightEmission = 0,
				Spread = Vector2.new(20, 20),
				Direction = if facing > 0 then Enum.NormalId.Right else Enum.NormalId.Left,
				Drag = 5,
				Acceleration = Vector3.new(0, 6, 0),
			})
		end
	end)
	movement.BoostPad:Connect(function(position)
		self:Burst(position, ColorSequence.new(rgb(255, 230, 120), rgb(255, 120, 30)), 14, { SpeedMin = 8, SpeedMax = 20 })
		self:Ring(position + Vector3.new(0, FEET + 0.3, 0), rgb(255, 180, 40), 7, 0.35, { Flat = true, Transparency = 0.15 })
		camera:Shake(0.3)
		camera:PunchFov(5)
	end)
	movement.DashStarted:Connect(function()
		local root = self:_localRoot()
		if root then
			self:Burst(root.Position, rgb(200, 230, 255), 12, { SpeedMin = 8, SpeedMax = 20, Size = 0.5 })
			self:Ring(root.Position, self:_accentOf(player.Character), 4.5, 0.22, { Transparency = 0.35 })
		end
		camera:PunchFov(6)
	end)
	movement.GrappleStarted:Connect(function()
		camera:PunchFov(1.5)
	end)

	-- Server-Events
	state:On("ItemPickup", function(payload)
		local item = ItemDefinitions.Get(payload.ItemId)
		local color = if item then item.Color else WHITE
		self:Burst(payload.Position, ColorSequence.new(WHITE, color), 20, { SpeedMax = 20, Spin = 180 })
		self:Ring(payload.Position, color, 5, 0.3)
		self:Flash(payload.Position, color, 4, 0.25)
	end)
	state:On("PowerUpUsed", function(payload)
		self:_onPowerUp(payload)
	end)
	state:On("ShieldBlocked", function(payload)
		local blue = rgb(120, 210, 255)
		self:Burst(payload.Position, ColorSequence.new(WHITE, blue), 24, { SpeedMin = 10, SpeedMax = 22 })
		self:Ring(payload.Position, blue, 7, 0.35)
		self:Flash(payload.Position, blue, 8, 0.25)
	end)
	state:On("StatusApplied", function(payload)
		local color = if payload.Kind == "Slowed" then rgb(170, 230, 255) else rgb(255, 230, 80)
		self:Burst(payload.Position, color, 14)
		self:Ring(payload.Position, color, 4, 0.3)
		if payload.UserId == player.UserId then
			camera:Shake(0.5)
			self:ScreenFlash(color, 0.25, 0.35)
		end
	end)
	state:On("RacerEliminated", function(payload)
		if payload.Position then
			self:_eliminationFx(payload.Position, payload.UserId == player.UserId)
		end
	end)
	state:On("RacerRespawn", function(payload)
		self:_respawnFx(payload)
	end)
	state:On("MatchResults", function(payload)
		local winner = Players:GetPlayerByUserId(payload.WinnerUserId or 0)
		if winner and winner.Character then
			local root = winner.Character:FindFirstChild("HumanoidRootPart")
			if root then
				self:_victory(winner.Character:GetAttribute("Victory") or "Default", root)
			end
		end
	end)

	self:_watchCheckpoints()

	RunService.RenderStepped:Connect(function(dt)
		local ok, err = pcall(self._update, self, dt)
		if not ok then
			warn("[EffectsController] " .. tostring(err))
		end
	end)
end

function EffectsController:_localRoot(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") or nil
end

function EffectsController:_accentOf(character: Model?): Color3
	local accent = character and character:GetAttribute("AccentColor")
	if typeof(accent) == "Color3" then
		return accent
	end
	return rgb(230, 240, 255)
end

------------------------------------------------------------------------
-- Beleuchtung
------------------------------------------------------------------------

function EffectsController:_applyTheme(definition)
	if not definition or self.CurrentTheme == definition.Id then
		return
	end
	self.CurrentTheme = definition.Id
	local theme = definition.Theme or {}
	local source = theme.Lighting or {}
	local light = {}
	for key, default in LIGHT_DEFAULTS do
		local value = source[key]
		if value == nil or typeof(value) ~= typeof(default) then
			value = default
		end
		light[key] = value
	end
	self.Light = light
	-- Erster Aufruf ohne Tween, damit das Spiel direkt im richtigen Look startet
	local info = if self.LightApplied then TweenInfo.new(1.2, Enum.EasingStyle.Sine) else nil
	self.LightApplied = true

	-- Uhrzeit: über Mitternacht nicht tweenen (sonst kurz Tageslicht)
	if info and self.ClockTime and math.abs(light.ClockTime - self.ClockTime) <= 12 then
		TweenService:Create(Lighting, info, { ClockTime = light.ClockTime }):Play()
	else
		Lighting.ClockTime = light.ClockTime
	end
	self.ClockTime = light.ClockTime

	self:_tween(Lighting, info, {
		Brightness = light.Brightness,
		Ambient = light.Ambient,
		OutdoorAmbient = light.OutdoorAmbient,
		FogColor = light.FogColor,
		FogStart = light.FogStart,
		FogEnd = light.FogEnd,
		ColorShift_Top = light.ColorShiftTop,
		ColorShift_Bottom = light.ColorShiftBottom,
		GeographicLatitude = light.GeographicLatitude,
		ExposureCompensation = math.clamp(light.ExposureCompensation, -3, 3),
		EnvironmentDiffuseScale = math.clamp(light.EnvironmentDiffuseScale, 0, 1),
		EnvironmentSpecularScale = math.clamp(light.EnvironmentSpecularScale, 0, 1),
		ShadowSoftness = math.clamp(light.ShadowSoftness, 0, 1),
	})
	self:_tween(self.Atmosphere, info, {
		Density = light.AtmosphereDensity,
		Offset = light.AtmosphereOffset,
		Color = light.AtmosphereColor,
		Decay = light.AtmosphereDecay,
		Haze = light.Haze,
		Glare = light.Glare,
	})
	self:_tween(self.Color, info, {
		TintColor = light.Tint,
		Saturation = light.Saturation,
		Contrast = light.Contrast,
		Brightness = light.ColorBrightness,
	})
	self:_tween(self.Bloom, info, {
		Intensity = light.BloomIntensity,
		Size = math.clamp(light.BloomSize, 0, 56),
		Threshold = light.BloomThreshold,
	})
	self:_tween(self.SunRays, info, {
		Intensity = light.SunRaysIntensity,
		Spread = light.SunRaysSpread,
	})
	self:_tween(self.Dof, info, {
		FarIntensity = math.clamp(light.DofFarIntensity, 0, 1),
		InFocusRadius = math.clamp(light.DofInFocusRadius, 0, 50),
	})
	self.Sky.StarCount = math.clamp(math.floor(light.StarCount), 0, 5000)
	self.Sky.CelestialBodiesShown = light.CelestialBodiesShown
	self:_tween(self.Sky, info, {
		SunAngularSize = math.clamp(light.SunAngularSize, 0, 60),
		MoonAngularSize = math.clamp(light.MoonAngularSize, 0, 60),
	})

	-- Figurenlicht: nachts kräftiger, tagsüber nur ein leichter Aufheller
	local night = light.ClockTime < 6.3 or light.ClockTime > 17.7
	local brightness = if light.PlayerLight >= 0 then light.PlayerLight elseif night then 1.4 else 0.45
	self:_tween(self.PlayerLight, info, { Brightness = brightness })

	-- Theme-Farben für Staub und Effekte
	if typeof(theme.Top) == "Color3" then
		self.DustColor = theme.Top:Lerp(rgb(235, 230, 220), 0.55)
	end
	if typeof(theme.Accent) == "Color3" then
		self.Accent = theme.Accent
	end
	self.MarkerColor = nil -- Markerfarben beim nächsten Frame neu setzen
	self.ThemeVersion += 1
	self:_applyQuality()
end

--- Qualitätsabhängige Effekte (Einstellung "Reduzierte Effekte").
function EffectsController:_applyQuality()
	local reduced = self:_reduced()
	self.Reduced = reduced
	local light = self.Light
	self.SunRays.Enabled = not reduced and light.SunRaysIntensity > 0
	self.Dof.Enabled = not reduced and light.DofFarIntensity > 0
end

------------------------------------------------------------------------
-- Bewegung (lokal)
------------------------------------------------------------------------

function EffectsController:_landFx(impact: number, position: Vector3)
	local camera = self.Ctx.CameraController
	local strength = math.clamp((impact - 45) / 80, 0, 1)
	local count = math.floor(5 + strength * 9)
	for _, direction in { Enum.NormalId.Left, Enum.NormalId.Right } do
		self:Burst(position + Vector3.new(0, 0.3, 0), self.DustColor, count, {
			SpeedMin = 6,
			SpeedMax = 10 + strength * 14,
			LifeMin = 0.35,
			LifeMax = 0.75,
			Size = 1 + strength,
			SizeEnd = 2.2,
			Transparency0 = 0.3,
			LightEmission = 0,
			Spread = Vector2.new(12, 12),
			Direction = direction,
			Drag = 5,
			Acceleration = Vector3.new(0, 4, 0),
		})
	end
	self:Ring(position + Vector3.new(0, 0.15, 0), self.DustColor:Lerp(WHITE, 0.5), 4 + strength * 8, 0.35, { Flat = true, Transparency = 0.3 })
	if strength > 0.4 then
		self:Ring(position + Vector3.new(0, 1.2, 0), WHITE, 3 + strength * 5, 0.25, { Transparency = 0.6 })
	end
	camera:Kick(Vector3.new(0, -(4 + strength * 14), 0))
	if impact > 90 then
		camera:Shake(0.6)
	end
end

function EffectsController:_jumpFx(kind: string)
	local root = self:_localRoot()
	if not root then
		return
	end
	local movement = self.Ctx.MovementController
	local position = root.Position
	local feet = position + Vector3.new(0, FEET + 0.3, 0)
	if kind == "Jump" then
		self:Burst(feet, self.DustColor, 5, {
			SpeedMin = 3,
			SpeedMax = 7,
			Size = 0.8,
			SizeEnd = 1.6,
			Transparency0 = 0.35,
			LightEmission = 0,
			Spread = Vector2.new(70, 10),
			Drag = 4,
			LifeMax = 0.6,
		})
	elseif kind == "WallJump" then
		-- Nach dem Wall-Jump schaut die Figur von der Wand weg
		local wallSide = position + Vector3.new(-movement:GetFacing() * 1.1, -0.5, 0)
		self:Burst(wallSide, ColorSequence.new(rgb(255, 240, 170), rgb(255, 140, 40)), 12, {
			SpeedMin = 8,
			SpeedMax = 18,
			Size = 0.35,
			LifeMax = 0.5,
			Acceleration = Vector3.new(0, -60, 0),
			LightEmission = 1,
		})
		self:Burst(wallSide, self.DustColor, 5, { SpeedMin = 2, SpeedMax = 5, Size = 0.9, SizeEnd = 1.8, Transparency0 = 0.35, LightEmission = 0 })
		self:Ring(wallSide, WHITE, 3.5, 0.22, { Transparency = 0.45 })
	elseif kind == "Pad" then
		local green = rgb(80, 255, 140)
		self:Burst(feet, green, 14, { SpeedMax = 16 })
		self:Ring(feet, green, 6, 0.35, { Flat = true, Transparency = 0.15 })
		self.Ctx.CameraController:PunchFov(4)
	elseif kind == "GrappleJump" then
		self:Burst(position, self:_accentOf(player.Character), 10, { SpeedMax = 14, Size = 0.5 })
	end
end

------------------------------------------------------------------------
-- Rennen: Checkpoints, Ausscheiden, Respawn
------------------------------------------------------------------------

function EffectsController:_watchCheckpoints()
	local state = self.Ctx.ClientState
	local function watch(folder: Instance)
		if folder.Name ~= tostring(player.UserId) then
			return
		end
		local last = folder:GetAttribute("Checkpoint") or 1
		folder:GetAttributeChangedSignal("Checkpoint"):Connect(function()
			local index = folder:GetAttribute("Checkpoint") or 1
			if index > last then
				self:_checkpointFx(index)
			end
			last = index
		end)
	end
	for _, folder in state.Racers:GetChildren() do
		watch(folder)
	end
	state.Racers.ChildAdded:Connect(watch)
end

function EffectsController:_checkpointFx(index: number)
	local root = self:_localRoot()
	if not root then
		return
	end
	local position = root.Position
	local x = position.X
	local list = string.split(self.Ctx.ClientState.GameState:GetAttribute("CheckpointXs") or "", ",")
	local checkpointX = tonumber(list[index])
	if checkpointX and math.abs(checkpointX - x) < 80 then
		x = checkpointX
	end
	local color = self.Accent:Lerp(WHITE, 0.15)
	-- Lichtsäule knapp hinter der Strecke
	local pillar = fxPart({ Name = "CheckpointPillar", Size = Vector3.new(2.5, 90, 0.4), CFrame = CFrame.new(x, position.Y + 30, -6.5), Color = color, Transparency = 0.25, Parent = self.Folder })
	TweenService:Create(pillar, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(10, 90, 0.4),
		Transparency = 1,
	}):Play()
	Debris:AddItem(pillar, 0.7)
	local core = fxPart({ Name = "CheckpointCore", Size = Vector3.new(0.8, 90, 0.4), CFrame = CFrame.new(x, position.Y + 30, -6.3), Color = WHITE, Parent = self.Folder })
	TweenService:Create(core, TweenInfo.new(0.45), { Transparency = 1 }):Play()
	Debris:AddItem(core, 0.5)
	self:Ring(position, color, 7, 0.4, { Transparency = 0.35 })
	self:Burst(position + Vector3.new(0, 1, 0), ColorSequence.new(WHITE, color), 22, {
		SpeedMin = 10,
		SpeedMax = 24,
		LifeMax = 0.8,
		Acceleration = Vector3.new(0, -20, 0),
		Size = 0.5,
		Spin = 200,
	})
	self:ScreenFlash(color, 0.2, 0.35)
	self.Ctx.CameraController:PunchFov(2.5)
end

function EffectsController:_eliminationFx(position: Vector3, isLocal: boolean)
	local camera = self.Ctx.CameraController
	local explosion = Instance.new("Explosion")
	explosion.BlastPressure = 0
	explosion.BlastRadius = 6
	explosion.DestroyJointPercent = 0
	explosion.ExplosionType = Enum.ExplosionType.NoCraters
	explosion.Position = position
	explosion.Parent = self.Folder
	self:Flash(position, rgb(255, 230, 200), 11, 0.3)
	self:Ring(position, rgb(255, 70, 90), 14, 0.45, { Transparency = 0.3 })
	self:Burst(position, ColorSequence.new({
		ColorSequenceKeypoint.new(0, rgb(255, 245, 180)),
		ColorSequenceKeypoint.new(0.4, rgb(255, 140, 40)),
		ColorSequenceKeypoint.new(1, rgb(255, 40, 70)),
	}), 36, { SpeedMin = 15, SpeedMax = 40, Size = 0.9, LifeMax = 1, Acceleration = Vector3.new(0, -40, 0), Drag = 1.5 })
	self:Burst(position, rgb(60, 55, 65), 12, {
		SpeedMin = 3,
		SpeedMax = 9,
		LifeMin = 0.8,
		LifeMax = 1.5,
		Size = 2.4,
		SizeEnd = 4.5,
		Transparency0 = 0.35,
		LightEmission = 0,
		Drag = 3,
		Acceleration = Vector3.new(0, 5, 0),
		Spin = 60,
	})
	-- Trümmer: lokale, nicht kollidierende Physik-Teile
	local pieces = if self.Reduced then 3 else 8
	for _ = 1, pieces do
		local size = 0.5 + math.random() * 0.6
		local piece = fxPart({
			Name = "Debris",
			Size = Vector3.one * size,
			CFrame = CFrame.new(position) * CFrame.Angles(math.random() * 6, math.random() * 6, 0),
			Color = if math.random() < 0.5 then rgb(255, 70, 90) else rgb(60, 60, 70),
			Material = if math.random() < 0.4 then Enum.Material.Neon else Enum.Material.SmoothPlastic,
			Parent = self.Folder,
		})
		piece.Anchored = false
		piece.Massless = true
		piece.AssemblyLinearVelocity = Vector3.new((math.random() - 0.5) * 60, 25 + math.random() * 35, (math.random() - 0.5) * 6)
		piece.AssemblyAngularVelocity = Vector3.new(math.random() * 20 - 10, math.random() * 20 - 10, math.random() * 20 - 10)
		TweenService:Create(piece, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
		Debris:AddItem(piece, 1.2)
	end
	if isLocal then
		camera:Shake(1.2)
		self:ScreenFlash(DANGER, 0.45, 0.6)
	elseif self:_nearCamera(position, 120) then
		camera:Shake(0.35)
	end
end

function EffectsController:_respawnFx(payload)
	if payload.From then
		self:Burst(payload.From, rgb(240, 240, 255), 16, { Size = 1, SizeEnd = 1.8, LightEmission = 0.2, Transparency0 = 0.2 })
		self:Flash(payload.From, WHITE, 5, 0.25)
	end
	if payload.To then
		local cyan = rgb(120, 220, 255)
		local pillar = fxPart({ Name = "RespawnBeam", Size = Vector3.new(3.2, 30, 0.3), CFrame = CFrame.new(payload.To + Vector3.new(0, 11, -2.5)), Color = cyan, Transparency = 0.25, Parent = self.Folder })
		TweenService:Create(pillar, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = Vector3.new(0.2, 30, 0.3),
			Transparency = 1,
		}):Play()
		Debris:AddItem(pillar, 0.6)
		self:Ring(payload.To, cyan, 6, 0.35, { Transparency = 0.35 })
		self:Ring(payload.To + Vector3.new(0, FEET + 0.2, 0), cyan, 5, 0.4, { Flat = true })
		self:Burst(payload.To, ColorSequence.new(WHITE, cyan), 16, { Spin = 180 })
		if payload.UserId == player.UserId then
			self:ScreenFlash(WHITE, 0.25, 0.35)
		end
	end
end

function EffectsController:_nearCamera(position: Vector3, distance: number): boolean
	local currentCamera = workspace.CurrentCamera
	return currentCamera ~= nil and (currentCamera.CFrame.Position - position).Magnitude < distance
end

------------------------------------------------------------------------
-- Power-ups und Sieg
------------------------------------------------------------------------

function EffectsController:_onPowerUp(payload)
	local item = ItemDefinitions.Get(payload.ItemId)
	if not item then
		return
	end
	local camera = self.Ctx.CameraController
	local isLocal = payload.UserId == player.UserId
	if payload.ItemId == "FreezeBurst" then
		self:Ring(payload.Position, item.Color, item.Radius, 0.6)
		self:Ring(payload.Position, WHITE, item.Radius * 0.6, 0.4, { Transparency = 0.5 })
		self:Burst(payload.Position, ColorSequence.new(WHITE, item.Color), 30, { SpeedMin = 20, SpeedMax = 40, Spin = 120 })
	elseif payload.ItemId == "TeleportBeacon" then
		if payload.From then
			self:Burst(payload.From, item.Color, 24, { SpeedMax = 20 })
			self:Flash(payload.From, item.Color, 6, 0.3)
		end
		if payload.To then
			self:Burst(payload.To, item.Color, 24, { SpeedMax = 20 })
			self:Ring(payload.To, item.Color, 8, 0.4)
		end
	elseif payload.ItemId == "Trap" and payload.TrapPosition then
		self:Burst(payload.TrapPosition, item.Color, 14)
	else
		self:Burst(payload.Position, item.Color, 20, { SpeedMax = 20 })
		self:Ring(payload.Position, item.Color, 5, 0.3, { Transparency = 0.4 })
	end
	if isLocal then
		camera:Shake(0.35)
	end
end

function EffectsController:_victory(kind: string, root: BasePart)
	local origin = root.Position
	local reduced = self.Reduced
	local gold = rgb(255, 215, 90)

	-- Gemeinsam: Siegerlicht hinter der Figur, Bodenringe, goldene Funken
	local beam = fxPart({
		Name = "VictoryBeam",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(140, 6, 6),
		CFrame = CFrame.new(origin + Vector3.new(0, 60, -5)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = rgb(255, 235, 160),
		Transparency = 0.55,
		Parent = self.Folder,
	})
	TweenService:Create(beam, TweenInfo.new(3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = Vector3.new(140, 1.5, 1.5),
		Transparency = 1,
	}):Play()
	Debris:AddItem(beam, 3.1)
	for i = 0, 2 do
		task.delay(i * 0.35, function()
			self:Ring(origin + Vector3.new(0, FEET + 0.2, 0), gold, 9 + i * 3, 0.6, { Flat = true, Transparency = 0.2 })
		end)
	end
	self:Burst(origin, ColorSequence.new(WHITE, gold), 26, { SpeedMin = 10, SpeedMax = 24, Spin = 200, LifeMax = 1.2, Acceleration = Vector3.new(0, -10, 0) })

	if kind == "Fireworks" then
		for i = 1, (if reduced then 3 else 6) do
			task.delay(i * 0.3, function()
				local start = origin + Vector3.new(math.random(-16, 16), 0, -8)
				local color = Color3.fromHSV(math.random(), 0.75, 1)
				local rocket = fxPart({ Name = "Rocket", Shape = Enum.PartType.Ball, Size = Vector3.new(0.9, 0.9, 0.9), CFrame = CFrame.new(start), Color = color, Parent = self.Folder })
				local a0 = Instance.new("Attachment")
				a0.Position = Vector3.new(0, 0.35, 0)
				a0.Parent = rocket
				local a1 = Instance.new("Attachment")
				a1.Position = Vector3.new(0, -0.35, 0)
				a1.Parent = rocket
				local trail = Instance.new("Trail")
				trail.Attachment0 = a0
				trail.Attachment1 = a1
				trail.Color = ColorSequence.new(WHITE, color)
				trail.LightEmission = 1
				trail.Lifetime = 0.35
				trail.FaceCamera = true
				trail.Transparency = sequence(0, 0, 1, 1)
				trail.Parent = rocket
				local peak = start + Vector3.new(math.random(-4, 4), 28 + math.random() * 10, 0)
				local tween = TweenService:Create(rocket, TweenInfo.new(0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(peak) })
				tween:Play()
				tween.Completed:Once(function()
					local burstAt = rocket.Position
					self:Flash(burstAt, color, 7, 0.3)
					self:Burst(burstAt, ColorSequence.new(WHITE, color), 50, {
						SpeedMin = 16,
						SpeedMax = 32,
						LifeMin = 0.9,
						LifeMax = 1.6,
						Acceleration = Vector3.new(0, -14, 0),
						Drag = 1.5,
						Size = 0.7,
					})
					task.delay(0.18, function()
						self:Burst(burstAt, Color3.fromHSV(math.random(), 0.6, 1), 24, { SpeedMin = 5, SpeedMax = 12, Size = 0.4, LifeMax = 1.2, Spin = 300 })
					end)
					rocket:Destroy()
				end)
			end)
		end
	elseif kind == "Lightning" then
		for bolt = 1, 3 do
			task.delay((bolt - 1) * 0.25, function()
				local top = origin + Vector3.new(math.random(-6, 6), 70, -2)
				local previous = top
				for step = 1, 8 do
					local nextPoint = top:Lerp(origin, step / 8) + Vector3.new(math.random(-30, 30) / 10, 0, 0)
					if step == 8 then
						nextPoint = origin
					end
					local length = (nextPoint - previous).Magnitude
					local cframe = CFrame.lookAt((previous + nextPoint) / 2, nextPoint)
					local segment = fxPart({ Name = "Bolt", Size = Vector3.new(0.35, 0.35, length), CFrame = cframe, Color = rgb(225, 240, 255), Parent = self.Folder })
					local glow = fxPart({ Name = "BoltGlow", Size = Vector3.new(1.4, 1.4, length), CFrame = cframe, Color = rgb(120, 180, 255), Transparency = 0.6, Parent = self.Folder })
					TweenService:Create(segment, TweenInfo.new(0.4), { Transparency = 1 }):Play()
					TweenService:Create(glow, TweenInfo.new(0.3), { Transparency = 1 }):Play()
					Debris:AddItem(segment, 0.5)
					Debris:AddItem(glow, 0.5)
					previous = nextPoint
				end
				self:Flash(origin, rgb(200, 230, 255), 9, 0.3)
				self:Ring(origin + Vector3.new(0, FEET + 0.2, 0), rgb(160, 210, 255), 12, 0.4, { Flat = true })
				self:Burst(origin, rgb(200, 230, 255), 30, { SpeedMin = 16, SpeedMax = 30 })
				if self:_nearCamera(origin, 150) then
					self:ScreenFlash(rgb(220, 235, 255), 0.3, 0.25)
				end
			end)
		end
	elseif kind == "GoldenRain" then
		local holder = fxPart({ Name = "GoldRain", Size = Vector3.new(30, 1, 10), CFrame = CFrame.new(origin + Vector3.new(0, 26, 0)), Transparency = 1, Parent = self.Folder })
		local emitter = Instance.new("ParticleEmitter")
		emitter.Rate = if reduced then 20 else 60
		emitter.Lifetime = NumberRange.new(1.5, 2.2)
		emitter.Speed = NumberRange.new(8, 14)
		emitter.EmissionDirection = Enum.NormalId.Bottom
		emitter.Color = ColorSequence.new(rgb(255, 235, 140), rgb(255, 190, 40))
		emitter.LightEmission = 1
		emitter.Size = sequence(0, 0.6, 1, 0.2)
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-200, 200)
		emitter.Parent = holder
		task.delay(3, function()
			emitter.Enabled = false
		end)
		Debris:AddItem(holder, 6)
		-- Fallende, sich drehende Münzen
		for i = 1, (if reduced then 6 else 14) do
			task.delay(i * 0.12, function()
				local start = origin + Vector3.new(math.random(-12, 12), 24 + math.random() * 6, -1 - math.random() * 2)
				local coin = fxPart({
					Name = "Coin",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(0.25, 1.4, 1.4),
					CFrame = CFrame.new(start),
					Color = rgb(255, 205, 60),
					Parent = self.Folder,
				})
				TweenService:Create(coin, TweenInfo.new(1.8, Enum.EasingStyle.Linear), {
					Position = start - Vector3.new(0, 26, 0),
					Orientation = Vector3.new(0, 900, 0),
				}):Play()
				task.delay(1.4, function()
					TweenService:Create(coin, TweenInfo.new(0.4), { Transparency = 1 }):Play()
				end)
				Debris:AddItem(coin, 1.9)
			end)
		end
	else
		-- Konfetti (Standard)
		for i = 1, (if reduced then 2 else 5) do
			task.delay(i * 0.22, function()
				self:Burst(origin + Vector3.new(math.random(-8, 8), 12, 0), CosmeticApplier.Rainbow, 40, {
					SpeedMin = 10,
					SpeedMax = 24,
					LifeMin = 1,
					LifeMax = 2,
					Acceleration = Vector3.new(0, -18, 0),
					Size = 0.5,
					Spin = 360,
				})
			end)
		end
		self:Ring(origin, WHITE, 8, 0.4, { Transparency = 0.4 })
	end
end

------------------------------------------------------------------------
-- Pro-Figur-Effekte
------------------------------------------------------------------------

function EffectsController:_rope(character: Model)
	local rope = self.Ropes[character]
	if rope and rope.Beam.Parent and rope.Hand.Parent then
		return rope
	end
	if rope then
		rope.Beam:Destroy()
		rope.Glow:Destroy()
		rope.Anchor:Destroy()
		self.Ropes[character] = nil
	end
	local hand = character:FindFirstChild("RightHand")
	local grip = hand and hand:FindFirstChild("VR_GrappleGrip")
	if not grip then
		return nil
	end
	local anchor = worldAttachment("VR_RopeAnchor")
	local function beam(name: string, width0: number, width1: number, transparency: number): Beam
		local b = Instance.new("Beam")
		b.Name = name
		b.Attachment0 = grip
		b.Attachment1 = anchor
		b.Width0 = width0
		b.Width1 = width1
		b.FaceCamera = true
		b.Segments = 12
		b.LightEmission = 1
		b.LightInfluence = 0
		b.Transparency = NumberSequence.new(transparency)
		b.Enabled = false
		b.Parent = self.Folder
		return b
	end
	rope = {
		Beam = beam("VR_Rope", 0.32, 0.22, 0.05),
		Glow = beam("VR_RopeGlow", 1.1, 0.8, 0.78),
		Anchor = anchor,
		Hand = hand,
		Active = false,
		AttachedAt = 0,
		Boosted = nil,
		Color = nil,
	}
	self.Ropes[character] = rope
	return rope
end

function EffectsController:_updateRope(rope, character: Model, anchorPosition: Vector3?, t: number, serverNow: number)
	if not anchorPosition then
		if rope.Active then
			rope.Active = false
			rope.Beam.Enabled = false
			rope.Glow.Enabled = false
		end
		return
	end
	local boosted = (character:GetAttribute("GrappleBoostUntil") or 0) > serverNow
	local color = if boosted then BOOST_PURPLE else self:_accentOf(character)
	if not rope.Active then
		rope.Active = true
		rope.AttachedAt = t
		rope.Beam.Enabled = true
		rope.Glow.Enabled = true
		-- Funken am Anker, sobald der Haken trifft
		task.delay(ROPE_SHOOT_TIME, function()
			self:Burst(anchorPosition, ColorSequence.new(WHITE, color), 8, { SpeedMin = 6, SpeedMax = 14, Size = 0.35, LifeMax = 0.4 })
			self:Ring(anchorPosition, color, 2.6, 0.22, { Transparency = 0.3 })
		end)
	end
	if rope.Color ~= color or rope.Boosted ~= boosted then
		rope.Color = color
		rope.Boosted = boosted
		rope.Beam.Color = ColorSequence.new(color:Lerp(WHITE, 0.35), color)
		rope.Glow.Color = ColorSequence.new(color)
		rope.Beam.Width0 = if boosted then 0.45 else 0.32
		rope.Glow.Width0 = if boosted then 1.6 else 1.1
	end
	-- Ausschuss: Seilspitze fliegt von der Hand zum Anker
	local age = t - rope.AttachedAt
	local handPosition = rope.Hand.Position
	local tip = handPosition:Lerp(anchorPosition, easeOut(math.clamp(age / ROPE_SHOOT_TIME, 0, 1)))
	local direction = anchorPosition - handPosition
	local length = direction.Magnitude
	local up = if length > 0.01 then direction / length else Vector3.yAxis
	-- X-Achse des Ankers steht senkrecht zum Seil (für das Nachschwingen)
	rope.Anchor.CFrame = CFrame.lookAt(tip, tip - Vector3.zAxis, up)
	local wobble = 0
	if age < 0.55 then
		wobble = math.sin(age * 38) * math.exp(-age * 7) * math.min(length * 0.12, 3)
	end
	rope.Beam.CurveSize1 = wobble
	rope.Glow.CurveSize1 = wobble
end

function EffectsController:_statusFx(character: Model)
	local fx = self.Status[character]
	if fx and fx.Shield.Parent then
		return fx
	end
	local shield = fxPart({ Name = "Shield", Shape = Enum.PartType.Ball, Size = Vector3.new(7.5, 7.5, 7.5), Material = Enum.Material.ForceField, Color = rgb(90, 200, 255), Transparency = 1, Parent = self.Folder })
	local ice = fxPart({ Name = "Ice", Size = Vector3.new(3.4, 6.2, 3), Material = Enum.Material.Glass, Color = rgb(170, 230, 255), Transparency = 1, Parent = self.Folder })
	local stars = {}
	for i = 1, 3 do
		stars[i] = fxPart({ Name = "Star", Shape = Enum.PartType.Ball, Size = Vector3.new(0.5, 0.5, 0.5), Color = rgb(255, 230, 80), Transparency = 1, Parent = self.Folder })
	end

	-- Laufstaub an den Füßen
	local dustAttachment = worldAttachment("VR_Dust")
	local dust = Instance.new("ParticleEmitter")
	dust.Enabled = false
	dust.Rate = 0
	dust.Lifetime = NumberRange.new(0.35, 0.7)
	dust.Speed = NumberRange.new(1.5, 4)
	dust.SpreadAngle = Vector2.new(35, 35)
	dust.Size = sequence(0, 0.5, 1, 1.8)
	dust.Transparency = sequence(0, 0.35, 1, 1)
	dust.LightEmission = 0
	dust.LightInfluence = 1
	dust.Drag = 3
	dust.Rotation = NumberRange.new(0, 360)
	dust.RotSpeed = NumberRange.new(-60, 60)
	dust.Color = ColorSequence.new(self.DustColor)
	dust.Parent = dustAttachment

	-- Funken (Wall-Slide, schneller Slide)
	local sparkAttachment = worldAttachment("VR_Sparks")
	local sparks = Instance.new("ParticleEmitter")
	sparks.Enabled = false
	sparks.Rate = 0
	sparks.Lifetime = NumberRange.new(0.2, 0.45)
	sparks.Speed = NumberRange.new(6, 14)
	sparks.SpreadAngle = Vector2.new(55, 55)
	sparks.Size = sequence(0, 0.32, 1, 0)
	sparks.Color = ColorSequence.new(rgb(255, 240, 170), rgb(255, 140, 40))
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.Acceleration = Vector3.new(0, -70, 0)
	sparks.Drag = 1
	sparks.Parent = sparkAttachment

	-- Boost: Flammen nach hinten, Glut-Aura und Licht
	local boostAttachment = worldAttachment("VR_Boost")
	local flames = Instance.new("ParticleEmitter")
	flames.Enabled = false
	flames.Rate = 45
	flames.Lifetime = NumberRange.new(0.2, 0.4)
	flames.Speed = NumberRange.new(5, 9)
	flames.Size = sequence(0, 1, 1, 0)
	flames.Color = ColorSequence.new(rgb(255, 230, 90), rgb(255, 80, 20))
	flames.LightEmission = 1
	flames.LightInfluence = 0
	flames.SpreadAngle = Vector2.new(25, 25)
	flames.Parent = boostAttachment
	local aura = Instance.new("ParticleEmitter")
	aura.Enabled = false
	aura.Rate = 28
	aura.Lifetime = NumberRange.new(0.35, 0.6)
	aura.Speed = NumberRange.new(1, 3)
	aura.SpreadAngle = Vector2.new(180, 180)
	aura.Size = sequence(0, 0.9, 1, 0)
	aura.Transparency = sequence(0, 0.2, 1, 1)
	aura.Color = ColorSequence.new(rgb(255, 240, 150), rgb(255, 120, 30))
	aura.LightEmission = 1
	aura.LightInfluence = 0
	aura.Acceleration = Vector3.new(0, 14, 0)
	aura.Parent = boostAttachment
	local boostLight = Instance.new("PointLight")
	boostLight.Enabled = false
	boostLight.Brightness = 2.2
	boostLight.Range = 12
	boostLight.Color = rgb(255, 170, 60)
	boostLight.Shadows = false
	boostLight.Parent = boostAttachment

	fx = {
		Shield = shield,
		Ice = ice,
		Stars = stars,
		DustAttachment = dustAttachment,
		Dust = dust,
		SparkAttachment = sparkAttachment,
		Sparks = sparks,
		BoostAttachment = boostAttachment,
		Flames = flames,
		Aura = aura,
		BoostLight = boostLight,
		DustRate = 0,
		SparkRate = 0,
		DustFacing = 0,
		DustVersion = -1,
		State = "Idle",
		ShieldOn = false,
		IceOn = false,
		StarsOn = false,
		BoostOn = false,
		BoostFacing = 0,
	}
	self.Status[character] = fx
	return fx
end

function EffectsController:_cleanupCharacters(alive)
	for character, rope in self.Ropes do
		if not alive[character] then
			rope.Beam:Destroy()
			rope.Glow:Destroy()
			rope.Anchor:Destroy()
			self.Ropes[character] = nil
		end
	end
	for character, fx in self.Status do
		if not alive[character] then
			fx.Shield:Destroy()
			fx.Ice:Destroy()
			fx.DustAttachment:Destroy()
			fx.SparkAttachment:Destroy()
			fx.BoostAttachment:Destroy()
			for _, star in fx.Stars do
				star:Destroy()
			end
			self.Status[character] = nil
		end
	end
end

--- Holt einen Satz Geister-Teile aus dem Pool (ältester wird wiederverwendet).
function EffectsController:_ghostSet()
	self.GhostCursor = self.GhostCursor % GHOST_SETS + 1
	local set = self.GhostPool[self.GhostCursor]
	if not set then
		set = {}
		for _, name in RunnerRig.PartNames do
			set[name] = fxPart({ Name = "Ghost", Transparency = 1, Parent = self.Folder })
		end
		self.GhostPool[self.GhostCursor] = set
	end
	return set
end

--- Nachbild der Figur an ihrer aktuellen Pose.
function EffectsController:_spawnGhost(character: Model, color: Color3, startTransparency: number)
	if not character.Parent then
		return
	end
	local set = self:_ghostSet()
	local info = TweenInfo.new(GHOST_LIFE, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for name, part in set do
		local source = character:FindFirstChild(name)
		if source and source:IsA("BasePart") then
			part.Size = source.Size
			part.CFrame = source.CFrame
			part.Color = color
			part.Transparency = startTransparency
			TweenService:Create(part, info, { Transparency = 1 }):Play()
		else
			part.Transparency = 1
		end
	end
end

function EffectsController:_dashGhosts(character: Model)
	local color = self:_accentOf(character):Lerp(WHITE, 0.3)
	local count = if self.Reduced then 1 else 3
	for i = 0, count - 1 do
		task.delay(i * 0.045, function()
			self:_spawnGhost(character, color, 0.45 + i * 0.1)
		end)
	end
end

------------------------------------------------------------------------
-- Pro-Frame-Aktualisierung
------------------------------------------------------------------------

function EffectsController:_updateCharacter(other: Player, character: Model, root: BasePart, near: boolean, t: number, serverNow: number)
	local movement = self.Ctx.MovementController
	local isLocal = other == player
	local position = root.Position
	local state, velocity, facing
	if isLocal then
		state = movement:GetState()
		velocity = movement.Velocity or root.AssemblyLinearVelocity
		facing = movement:GetFacing()
	else
		state = character:GetAttribute("MoveState") or "Idle"
		velocity = root.AssemblyLinearVelocity
		facing = character:GetAttribute("Facing") or 1
	end
	local speed = math.abs(velocity.X)

	-- Greifhaken-Seil
	local rope = self:_rope(character)
	if rope then
		local anchorPosition = nil
		if near then
			if isLocal then
				anchorPosition = movement:GetGrappleAnchor()
			elseif character:GetAttribute("Grappling") then
				anchorPosition = character:GetAttribute("GrappleTarget")
			end
		end
		self:_updateRope(rope, character, if typeof(anchorPosition) == "Vector3" then anchorPosition else nil, t, serverNow)
	end

	local fx = self:_statusFx(character)

	-- Zustandswechsel: Dash-Nachbilder
	if state ~= fx.State then
		if state == "Dash" and near then
			self:_dashGhosts(character)
		end
		fx.State = state
	end
	-- Nachbilder bei extremem Tempo (nur eigene Figur)
	if isLocal and speed > 95 and t - self.LastAfterimage > (if self.Reduced then 0.3 else 0.11) then
		self.LastAfterimage = t
		self:_spawnGhost(character, self:_accentOf(character):Lerp(WHITE, 0.4), 0.72)
	end

	-- Laufstaub / Slide-Staub
	local dustRate = 0
	if near then
		if state == "Run" and speed > 16 then
			dustRate = 6 + speed * 0.3
		elseif state == "Slide" and speed > 6 then
			dustRate = 26 + speed * 0.4
		end
		if self.Reduced then
			dustRate *= 0.4
		end
		dustRate = math.floor(dustRate)
	end
	if dustRate ~= fx.DustRate then
		fx.DustRate = dustRate
		fx.Dust.Rate = dustRate
		fx.Dust.Enabled = dustRate > 0
	end
	if dustRate > 0 then
		fx.DustAttachment.Position = position + Vector3.new(0, FEET + 0.25, 0)
		if fx.DustFacing ~= facing then
			fx.DustFacing = facing
			fx.Dust.Acceleration = Vector3.new(-facing * 9, 3.5, 0)
		end
		if fx.DustVersion ~= self.ThemeVersion then
			fx.DustVersion = self.ThemeVersion
			fx.Dust.Color = ColorSequence.new(self.DustColor)
		end
	end

	-- Funken: Wand (Wand liegt in Blickrichtung) oder schneller Slide
	local sparkRate = 0
	if near then
		if state == "Wall" then
			sparkRate = 45
		elseif state == "Slide" and speed > 28 then
			sparkRate = 18
		end
		if self.Reduced then
			sparkRate = math.floor(sparkRate * 0.4)
		end
	end
	if sparkRate ~= fx.SparkRate then
		fx.SparkRate = sparkRate
		fx.Sparks.Rate = sparkRate
		fx.Sparks.Enabled = sparkRate > 0
	end
	if sparkRate > 0 then
		if state == "Wall" then
			fx.SparkAttachment.Position = position + Vector3.new(facing * 1.05, -0.4, 0)
		else
			fx.SparkAttachment.Position = position + Vector3.new(facing * 1.3, FEET + 0.2, 0)
		end
	end

	-- Status-Effekte
	local shielded = near and (character:GetAttribute("ShieldUntil") or 0) > serverNow
	local slowed = near and (character:GetAttribute("SlowedUntil") or 0) > serverNow
	local stunned = near and (character:GetAttribute("StunnedUntil") or 0) > serverNow
	local boosted = near and (character:GetAttribute("BoostUntil") or 0) > serverNow
	if shielded then
		local pulse = 7.5 + math.sin(t * 4) * 0.25
		fx.Shield.Size = Vector3.new(pulse, pulse, pulse)
		fx.Shield.CFrame = CFrame.new(position)
		fx.Shield.Transparency = 0.35
		fx.ShieldOn = true
	elseif fx.ShieldOn then
		fx.ShieldOn = false
		fx.Shield.Transparency = 1
	end
	if slowed then
		fx.Ice.CFrame = CFrame.new(position)
		fx.Ice.Transparency = 0.45
		fx.IceOn = true
	elseif fx.IceOn then
		fx.IceOn = false
		fx.Ice.Transparency = 1
	end
	if stunned then
		for i, star in fx.Stars do
			local angle = t * 6 + i * (math.pi * 2 / 3)
			star.Transparency = 0
			star.CFrame = CFrame.new(position + Vector3.new(math.cos(angle) * 1.4, 3.6, math.sin(angle) * 1.4))
		end
		fx.StarsOn = true
	elseif fx.StarsOn then
		fx.StarsOn = false
		for _, star in fx.Stars do
			star.Transparency = 1
		end
	end
	if boosted ~= fx.BoostOn then
		fx.BoostOn = boosted
		fx.Flames.Enabled = boosted
		fx.Aura.Enabled = boosted and not self.Reduced
		fx.BoostLight.Enabled = boosted
	end
	if boosted then
		fx.BoostAttachment.Position = position - Vector3.new(facing * 0.6, 0, 0)
		if fx.BoostFacing ~= facing then
			fx.BoostFacing = facing
			fx.Flames.EmissionDirection = if facing > 0 then Enum.NormalId.Left else Enum.NormalId.Right
		end
	end
end

function EffectsController:_updateMarker(t: number)
	local movement = self.Ctx.MovementController
	local target = movement.Target
	local frozen = player.Character and player.Character:GetAttribute("Frozen")
	if not target or frozen or not target.Parent then
		if self.Marker.Enabled then
			self.Marker.Enabled = false
			self.Highlight.Enabled = false
		end
		self.MarkerTarget = nil
		return
	end
	local parts = self.MarkerParts
	if self.MarkerTarget ~= target then
		self.MarkerTarget = target
		self.MarkerLockAt = t
		self.Marker.Adornee = target
		self.Highlight.Adornee = target
	end
	self.Marker.Enabled = true
	self.Highlight.Enabled = true

	local cooldowns = movement:GetCooldowns()
	local ready = cooldowns.Grapple <= 0
	local character = player.Character
	local boosted = character ~= nil and (character:GetAttribute("GrappleBoostUntil") or 0) > workspace:GetServerTimeNow()
	local base = target.Color
	if typeof(base) ~= "Color3" then
		base = self.Accent
	end
	local color = if not ready then GREY elseif boosted then BOOST_PURPLE else base:Lerp(WHITE, 0.25)
	if self.MarkerColor ~= color then
		self.MarkerColor = color
		parts.Gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, WHITE),
			ColorSequenceKeypoint.new(0.5, color),
			ColorSequenceKeypoint.new(1, WHITE),
		})
		parts.Glow.BackgroundColor3 = color
		parts.Dot.BackgroundColor3 = color:Lerp(WHITE, 0.5)
		for _, tick in parts.Ticks do
			tick.BackgroundColor3 = color
		end
		self.Highlight.FillColor = color
	end

	-- Lock-on: Marker schnappt beim Zielwechsel von groß auf normal
	local lock = math.clamp((t - self.MarkerLockAt) / 0.18, 0, 1)
	local pulse = if ready then math.sin(t * 7) * 0.05 else 0
	parts.Scale.Scale = 1 + (1 - easeOut(lock)) * 0.9 + pulse
	parts.Gradient.Rotation = (t * 240) % 360
	parts.Reticle.Rotation = 45 + (if ready then (t * 70) % 90 else 0)
	parts.Glow.BackgroundTransparency = if ready then 0.8 + math.sin(t * 7) * 0.06 else 0.9
	self.Highlight.FillTransparency = if ready then 0.55 + math.sin(t * 6) * 0.12 else 0.8
end

function EffectsController:_cameraTarget(): (BasePart?, Vector3)
	local spectate = self.Ctx.CameraController:GetSpectate()
	if spectate and spectate.Character then
		local root = spectate.Character:FindFirstChild("HumanoidRootPart")
		if root then
			return root, root.AssemblyLinearVelocity
		end
	end
	local root = self:_localRoot()
	if not root then
		return nil, Vector3.zero
	end
	return root, self.Ctx.MovementController.Velocity or root.AssemblyLinearVelocity
end

function EffectsController:_updateSpeedLines(dt: number, root: BasePart?, velocity: Vector3)
	local target = 0
	if root then
		target = math.clamp((math.abs(velocity.X) - (MAX_RUN + 6)) / 50, 0, 1)
		local spectating = self.Ctx.CameraController:GetSpectate() ~= nil
		if not spectating and self.Ctx.MovementController:GetState() == "Dash" then
			target = math.max(target, 0.85)
		end
		local character = root.Parent
		if character and (character:GetAttribute("BoostUntil") or 0) > workspace:GetServerTimeNow() then
			target = math.max(target, 0.45)
		end
		if math.abs(velocity.X) > 3 then
			self.LineDirection = Util.Sign(velocity.X)
		end
	end
	self.SpeedIntensity = Util.Damp(self.SpeedIntensity, target, if target > self.SpeedIntensity then 10 else 4, dt)
	local intensity = self.SpeedIntensity
	if intensity < 0.02 then
		if self.LinesFrame.Visible then
			self.LinesFrame.Visible = false
			for _, edge in self.Vignette do
				edge.BackgroundTransparency = 1
			end
		end
		return
	end
	self.LinesFrame.Visible = true
	for _, edge in self.Vignette do
		edge.BackgroundTransparency = 1 - intensity * 0.35
	end
	local direction = self.LineDirection
	local active = if self.Reduced then SPEED_LINES_REDUCED else SPEED_LINES
	if active ~= self.LinesActive then
		self.LinesActive = active
		for i, line in self.SpeedLines do
			line.Frame.Visible = i <= active
		end
	end
	local rotation = if direction > 0 then 180 else 0
	for i = 1, active do
		local line = self.SpeedLines[i]
		line.X -= direction * line.Speed * (0.6 + intensity * 1.6) * dt
		if line.X < -0.4 or line.X > 1.4 then
			self:_resetLine(line)
		end
		line.Frame.Position = UDim2.fromScale(line.X, line.Y)
		line.Frame.BackgroundTransparency = 1 - intensity * line.Alpha
		line.Gradient.Rotation = rotation
	end
end

function EffectsController:_update(dt: number)
	local t = os.clock()
	local serverNow = workspace:GetServerTimeNow()
	local currentCamera = workspace.CurrentCamera
	local cameraPosition = if currentCamera then currentCamera.CFrame.Position else Vector3.zero
	local alive = {}

	-- Spielfiguren: Seile, Staub, Funken, Status
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if character and root and character.Parent then
			alive[character] = true
			local near = (root.Position - cameraPosition).Magnitude < NEAR_DISTANCE
			self:_updateCharacter(other, character, root, near, t, serverNow)
		end
	end
	self:_cleanupCharacters(alive)

	self:_updateMarker(t)

	-- Item-Boxen drehen
	for _, box in CollectionService:GetTagged("PowerUpBox") do
		local base = box:GetAttribute("BasePosition")
		if typeof(base) == "Vector3" and (base - cameraPosition).Magnitude < 250 then
			local cframe = CFrame.new(base + Vector3.new(0, math.sin(t * 2 + base.X) * 0.4, 0)) * CFrame.Angles(t * 1.2, t * 1.7, math.rad(45))
			box.CFrame = cframe
			local core = box:FindFirstChild("Core")
			if core then
				core.CFrame = cframe
			end
		end
	end

	-- Zeitgesteuerte Gefahren
	for _, hazard in CollectionService:GetTagged("TimedHazard") do
		if (hazard.Position - cameraPosition).Magnitude < 300 then
			local period = hazard:GetAttribute("HazardPeriod") or 2
			local onTime = hazard:GetAttribute("HazardOnTime") or 1
			local offset = hazard:GetAttribute("HazardOffset") or 0
			local phase = (serverNow + offset) % period
			if phase < onTime then
				hazard.Transparency = 0.1
			elseif period - phase < 0.45 then
				hazard.Transparency = if math.floor(t * 12) % 2 == 0 then 0.35 else 0.85
			else
				hazard.Transparency = 0.9
			end
		end
	end

	self:_updateZone(dt, t)

	-- Kamera-Ziel: Speed-Lines, Figurenlicht, Tiefenunschärfe
	local targetRoot, targetVelocity = self:_cameraTarget()
	self:_updateSpeedLines(dt, targetRoot, targetVelocity)
	if targetRoot then
		self.PlayerLightAttachment.Position = targetRoot.Position + Vector3.new(0, 2.5, 5)
	end
	local focusDistance = self.Ctx.CameraController:GetFocusDistance()
	if math.abs(focusDistance - self.DofDistance) > 0.3 then
		self.DofDistance = focusDistance
		self.Dof.FocusDistance = math.clamp(focusDistance, 0, 200)
	end
end

------------------------------------------------------------------------
-- Gefahrenwand
------------------------------------------------------------------------

function EffectsController:_hideZone()
	local zone = self.Zone
	zone.Sheet.Transparency = 1
	zone.Line.Transparency = 1
	zone.Tint.Transparency = 1
	zone.Back.Transparency = 1
	for _, glow in zone.Glows do
		glow.Part.Transparency = 1
	end
	for _, pulse in zone.Pulses do
		pulse.Transparency = 1
	end
	zone.Embers.Enabled = false
	self.ZoneVisible = false
end

function EffectsController:_updateZone(dt: number, t: number)
	local state = self.Ctx.ClientState
	local gameState = state.GameState
	local zoneState = gameState:GetAttribute("ZoneState") or "Inactive"
	local watching = state:IsInRace() or self.Ctx.CameraController:GetSpectate() ~= nil
	local active = watching and (zoneState == "Shrinking" or zoneState == "Final" or zoneState == "Warning")
	if not active then
		if self.ZoneVisible then
			self:_hideZone()
		end
		self.ZoneVisualX = nil
		return
	end
	local targetX = gameState:GetAttribute("ZoneX") or -1e6
	local warning = zoneState == "Warning"
	if warning then
		targetX = (gameState:GetAttribute("StartX") or 0) - 20
	end
	if not self.ZoneVisualX or math.abs(targetX - self.ZoneVisualX) > 200 then
		self.ZoneVisualX = targetX
	else
		self.ZoneVisualX = Util.Damp(self.ZoneVisualX, targetX, 8, dt)
	end
	local x = self.ZoneVisualX
	local y = if workspace.CurrentCamera then workspace.CurrentCamera.CFrame.Position.Y else 0
	local zone = self.Zone
	local pulse = 0.5 + 0.5 * math.sin(t * 5)
	-- Warnphase: gleiche Wand, nur deutlich schwächer
	local strength = if warning then 0.35 else 1
	local function alpha(base: number): number
		return 1 - (1 - base) * strength
	end

	zone.Sheet.CFrame = CFrame.new(x, y, -24)
	zone.Sheet.Transparency = alpha(0.62 - pulse * 0.1)
	zone.Line.CFrame = CFrame.new(x, y, 8.6)
	-- Kante bleibt durchscheinend, damit Läufer direkt an der Wand sichtbar bleiben
	zone.Line.Transparency = alpha(0.3 + pulse * 0.15)
	for _, glow in zone.Glows do
		glow.Part.CFrame = CFrame.new(x - glow.Width / 2, y, 8.5)
		glow.Part.Transparency = alpha(glow.Base - pulse * 0.05)
	end
	for i, bar in zone.Pulses do
		local cycle = (t * 0.9 + i / 3) % 1
		bar.CFrame = CFrame.new(x, y - 35 + cycle * 70, 8.75)
		bar.Transparency = alpha(0.3 + cycle * 0.68)
	end
	if warning then
		zone.Tint.Transparency = 1
		zone.Back.Transparency = 1
		zone.Embers.Enabled = false
	else
		zone.Tint.CFrame = CFrame.new(x - 1000.5, y, 8.3)
		zone.Tint.Transparency = 0.87
		zone.Back.CFrame = CFrame.new(x - 1000, y, -60)
		zone.Back.Transparency = 0.72
		zone.EmberSource.CFrame = CFrame.new(x - 0.5, y, 2)
		zone.Embers.Enabled = not self.Reduced
	end
	self.ZoneVisible = true
end

return EffectsController
