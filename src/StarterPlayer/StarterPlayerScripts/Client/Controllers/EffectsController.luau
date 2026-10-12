--[[
	EffectsController  (ModuleScript)
	Pfad: StarterPlayer/StarterPlayerScripts/Client/Controllers/EffectsController

	Alle visuellen Effekte – komplett ohne externe Assets (Parts, Beams,
	ParticleEmitter mit Standardtextur, Explosion, TweenService):

		- Beleuchtung/Atmosphäre je Region (Lobby, Strecke, Training)
		- Greifhaken-Seile aller Spieler + Zielmarkierung für den eigenen Haken
		- Gefahrenwand (Gefahrenring) mit Tönung der Gefahrenzone
		- rotierende Item-Boxen, blinkende Zeit-Barrieren
		- Status: Schild, Freeze, Betäubung, Boost
		- Einmal-Effekte: Landen, Pads, Pickup, Power-ups, Ausscheiden,
		  Respawn, Siegesanimationen (Konfetti, Feuerwerk, Blitz, Goldregen)

	"Reduzierte Effekte" in den Einstellungen verringert Partikelmengen.
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

local player = Players.LocalPlayer
local rgb = Color3.fromRGB

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
	part.Color = props.Color or Color3.new(1, 1, 1)
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

function EffectsController:_reduced(): boolean
	return self.Ctx.ClientState:GetSetting("ReducedEffects") == true
end

--- Partikelstoß an einer Weltposition.
function EffectsController:Burst(position: Vector3, color, count: number, options)
	options = options or {}
	if self:_reduced() then
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
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, options.Size or 0.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	if typeof(color) == "ColorSequence" then
		emitter.Color = color
	else
		emitter.Color = ColorSequence.new(color)
	end
	emitter.LightEmission = options.LightEmission or 0.8
	emitter.Acceleration = options.Acceleration or Vector3.zero
	emitter.Drag = options.Drag or 2
	emitter.EmissionDirection = options.Direction or Enum.NormalId.Top
	emitter.Parent = attachment
	emitter:Emit(count)
	Debris:AddItem(attachment, (options.LifeMax or 0.9) + 0.5)
end

--- Sich ausdehnender Ring (z.B. Freeze Burst).
function EffectsController:Ring(position: Vector3, color: Color3, radius: number, duration: number)
	local ring = fxPart({
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 2, 2),
		CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(90), 0),
		Color = color,
		Transparency = 0.2,
		Parent = self.Folder,
	})
	local tween = TweenService:Create(ring, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.4, radius * 2, radius * 2),
		Transparency = 1,
	})
	tween:Play()
	Debris:AddItem(ring, duration + 0.1)
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
	self.CurrentTheme = nil

	self.Atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	self.Atmosphere.Parent = Lighting
	self.Bloom = Instance.new("BloomEffect")
	self.Bloom.Name = "VR_Bloom"
	self.Bloom.Parent = Lighting
	self.Color = Instance.new("ColorCorrectionEffect")
	self.Color.Name = "VR_Color"
	self.Color.Parent = Lighting

	-- Zielmarkierung für den Greifhaken
	local marker = Instance.new("BillboardGui")
	marker.Name = "VR_GrappleTarget"
	marker.Size = UDim2.fromOffset(46, 46)
	marker.AlwaysOnTop = true
	marker.LightInfluence = 0
	marker.Enabled = false
	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(1, 1)
	ring.BackgroundTransparency = 1
	ring.Parent = marker
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = rgb(255, 255, 255)
	stroke.Parent = ring
	marker.Parent = player:WaitForChild("PlayerGui")
	self.Marker = marker
	self.MarkerRing = ring

	-- Gefahrenwand
	self.ZoneWall = fxPart({
		Name = "DangerWall",
		Size = Vector3.new(3, 1400, 180),
		Color = rgb(255, 40, 70),
		Transparency = 1,
		Parent = self.Folder,
	})
	self.ZoneTint = fxPart({
		Name = "DangerTint",
		Size = Vector3.new(4000, 1400, 0.2),
		Color = rgb(255, 30, 60),
		Material = Enum.Material.SmoothPlastic,
		Transparency = 1,
		Parent = self.Folder,
	})
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
	refreshTheme()

	-- Bewegungs-Effekte (lokal)
	movement.Landed:Connect(function(impact, position)
		self:Burst(position, rgb(210, 210, 220), math.clamp(math.floor(impact / 8), 4, 16), {
			SpeedMin = 4,
			SpeedMax = 10,
			Size = 0.8,
			LightEmission = 0,
			Spread = Vector2.new(70, 10),
		})
		if impact > 90 then
			camera:Shake(0.6)
		end
	end)
	movement.Jumped:Connect(function(kind)
		local root = self:_localRoot()
		if root and (kind == "WallJump" or kind == "Pad") then
			self:Burst(root.Position, if kind == "Pad" then rgb(80, 255, 140) else rgb(230, 230, 255), 10, { SpeedMax = 12 })
		end
	end)
	movement.BoostPad:Connect(function(position)
		self:Burst(position, rgb(255, 180, 40), 8, { SpeedMax = 14 })
		camera:Shake(0.3)
	end)
	movement.DashStarted:Connect(function()
		local root = self:_localRoot()
		if root then
			self:Burst(root.Position, rgb(200, 230, 255), 10, { SpeedMax = 18, Size = 0.5 })
		end
	end)

	-- Server-Events
	state:On("ItemPickup", function(payload)
		local item = ItemDefinitions.Get(payload.ItemId)
		self:Burst(payload.Position, if item then item.Color else rgb(255, 255, 255), 18, { SpeedMax = 18 })
	end)
	state:On("PowerUpUsed", function(payload)
		self:_onPowerUp(payload)
	end)
	state:On("ShieldBlocked", function(payload)
		self:Burst(payload.Position, rgb(120, 210, 255), 24, { SpeedMin = 10, SpeedMax = 22 })
	end)
	state:On("StatusApplied", function(payload)
		local color = if payload.Kind == "Slowed" then rgb(170, 230, 255) else rgb(255, 230, 80)
		self:Burst(payload.Position, color, 14)
		if payload.UserId == player.UserId then
			camera:Shake(0.5)
		end
	end)
	state:On("RacerEliminated", function(payload)
		if payload.Position then
			local explosion = Instance.new("Explosion")
			explosion.BlastPressure = 0
			explosion.BlastRadius = 6
			explosion.DestroyJointPercent = 0
			explosion.ExplosionType = Enum.ExplosionType.NoCraters
			explosion.Position = payload.Position
			explosion.Parent = self.Folder
			self:Burst(payload.Position, rgb(255, 60, 80), 30, { SpeedMin = 12, SpeedMax = 30, Size = 0.9 })
			if payload.UserId == player.UserId then
				camera:Shake(1.2)
			end
		end
	end)
	state:On("RacerRespawn", function(payload)
		if payload.From then
			self:Burst(payload.From, rgb(240, 240, 255), 16, { Size = 1, LightEmission = 0.2 })
		end
		if payload.To then
			self:Burst(payload.To, rgb(120, 220, 255), 12)
		end
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

------------------------------------------------------------------------
-- Beleuchtung
------------------------------------------------------------------------

function EffectsController:_applyTheme(definition)
	if not definition or self.CurrentTheme == definition.Id then
		return
	end
	self.CurrentTheme = definition.Id
	local light = definition.Theme.Lighting
	local info = TweenInfo.new(1.2, Enum.EasingStyle.Sine)
	TweenService:Create(Lighting, info, {
		ClockTime = light.ClockTime,
		Brightness = light.Brightness,
		Ambient = light.Ambient,
		OutdoorAmbient = light.OutdoorAmbient,
		FogColor = light.FogColor,
		FogStart = light.FogStart,
		FogEnd = light.FogEnd,
	}):Play()
	TweenService:Create(self.Atmosphere, info, {
		Density = light.AtmosphereDensity,
		Color = light.AtmosphereColor,
		Decay = light.AtmosphereDecay,
		Haze = light.Haze,
		Glare = light.Glare,
	}):Play()
	TweenService:Create(self.Color, info, {
		TintColor = light.Tint,
		Saturation = light.Saturation,
		Contrast = light.Contrast,
	}):Play()
	TweenService:Create(self.Bloom, info, {
		Intensity = light.BloomIntensity,
		Size = light.BloomSize,
		Threshold = light.BloomThreshold,
	}):Play()
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
		self:Burst(payload.Position, item.Color, 30, { SpeedMin = 20, SpeedMax = 40 })
	elseif payload.ItemId == "TeleportBeacon" then
		if payload.From then
			self:Burst(payload.From, item.Color, 24, { SpeedMax = 20 })
		end
		if payload.To then
			self:Burst(payload.To, item.Color, 24, { SpeedMax = 20 })
			self:Ring(payload.To, item.Color, 8, 0.4)
		end
	elseif payload.ItemId == "Trap" and payload.TrapPosition then
		self:Burst(payload.TrapPosition, item.Color, 14)
	else
		self:Burst(payload.Position, item.Color, 20, { SpeedMax = 20 })
	end
	if isLocal then
		camera:Shake(0.35)
	end
end

function EffectsController:_victory(kind: string, root: BasePart)
	local origin = root.Position
	if kind == "Fireworks" then
		for i = 1, 5 do
			task.delay(i * 0.35, function()
				local start = origin + Vector3.new(math.random(-14, 14), 0, -6)
				local color = Color3.fromHSV(math.random(), 0.8, 1)
				local rocket = fxPart({ Name = "Rocket", Shape = Enum.PartType.Ball, Size = Vector3.new(0.8, 0.8, 0.8), CFrame = CFrame.new(start), Color = color, Parent = self.Folder })
				local tween = TweenService:Create(rocket, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(start + Vector3.new(0, 30, 0)) })
				tween:Play()
				tween.Completed:Once(function()
					self:Burst(rocket.Position, color, 40, { SpeedMin = 14, SpeedMax = 28, LifeMax = 1.4, Acceleration = Vector3.new(0, -12, 0) })
					rocket:Destroy()
				end)
			end)
		end
	elseif kind == "Lightning" then
		for bolt = 1, 2 do
			task.delay((bolt - 1) * 0.3, function()
				local top = origin + Vector3.new(math.random(-4, 4), 70, -2)
				local previous = top
				for step = 1, 7 do
					local nextPoint = top:Lerp(origin, step / 7) + Vector3.new(math.random(-3, 3), 0, 0)
					if step == 7 then
						nextPoint = origin
					end
					local length = (nextPoint - previous).Magnitude
					local segment = fxPart({
						Name = "Bolt",
						Size = Vector3.new(0.5, 0.5, length),
						CFrame = CFrame.lookAt((previous + nextPoint) / 2, nextPoint),
						Color = rgb(200, 230, 255),
						Parent = self.Folder,
					})
					TweenService:Create(segment, TweenInfo.new(0.45), { Transparency = 1 }):Play()
					Debris:AddItem(segment, 0.5)
					previous = nextPoint
				end
				self:Burst(origin, rgb(200, 230, 255), 30, { SpeedMin = 16, SpeedMax = 30 })
			end)
		end
	elseif kind == "GoldenRain" then
		local holder = fxPart({ Name = "GoldRain", Size = Vector3.new(30, 1, 10), CFrame = CFrame.new(origin + Vector3.new(0, 26, 0)), Transparency = 1, Parent = self.Folder })
		local emitter = Instance.new("ParticleEmitter")
		emitter.Rate = if self:_reduced() then 20 else 60
		emitter.Lifetime = NumberRange.new(1.5, 2.2)
		emitter.Speed = NumberRange.new(8, 14)
		emitter.EmissionDirection = Enum.NormalId.Bottom
		emitter.Color = ColorSequence.new(rgb(255, 210, 60))
		emitter.LightEmission = 1
		emitter.Size = NumberSequence.new(0.5)
		emitter.Parent = holder
		task.delay(3, function()
			emitter.Enabled = false
		end)
		Debris:AddItem(holder, 6)
	else
		-- Konfetti (Standard)
		for i = 1, 4 do
			task.delay(i * 0.25, function()
				self:Burst(origin + Vector3.new(math.random(-8, 8), 12, 0), CosmeticApplier.Rainbow, 40, {
					SpeedMin = 10,
					SpeedMax = 24,
					LifeMin = 1,
					LifeMax = 2,
					Acceleration = Vector3.new(0, -18, 0),
					Size = 0.5,
				})
			end)
		end
	end
end

------------------------------------------------------------------------
-- Pro-Frame-Aktualisierung
------------------------------------------------------------------------

function EffectsController:_rope(character: Model)
	local rope = self.Ropes[character]
	if rope and rope.Beam.Parent then
		return rope
	end
	local hand = character:FindFirstChild("RightHand")
	local grip = hand and hand:FindFirstChild("VR_GrappleGrip")
	if not grip then
		return nil
	end
	local anchor = Instance.new("Attachment")
	anchor.Name = "VR_RopeAnchor"
	anchor.Parent = workspace.Terrain
	local beam = Instance.new("Beam")
	beam.Name = "VR_Rope"
	beam.Attachment0 = grip
	beam.Attachment1 = anchor
	beam.Width0 = 0.3
	beam.Width1 = 0.2
	beam.FaceCamera = true
	beam.Segments = 1
	beam.LightEmission = 0.6
	beam.Enabled = false
	beam.Parent = self.Folder
	rope = { Beam = beam, Anchor = anchor }
	self.Ropes[character] = rope
	return rope
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
	local boostHolder = fxPart({ Name = "Boost", Size = Vector3.new(1, 1, 1), Transparency = 1, Parent = self.Folder })
	local boost = Instance.new("ParticleEmitter")
	boost.Enabled = false
	boost.Rate = 40
	boost.Lifetime = NumberRange.new(0.2, 0.4)
	boost.Speed = NumberRange.new(4, 8)
	boost.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
	boost.Color = ColorSequence.new(rgb(255, 220, 80), rgb(255, 80, 20))
	boost.LightEmission = 1
	boost.SpreadAngle = Vector2.new(25, 25)
	boost.Parent = boostHolder
	fx = { Shield = shield, Ice = ice, Stars = stars, BoostHolder = boostHolder, Boost = boost }
	self.Status[character] = fx
	return fx
end

function EffectsController:_cleanupCharacters(alive)
	for character, rope in self.Ropes do
		if not alive[character] then
			rope.Beam:Destroy()
			rope.Anchor:Destroy()
			self.Ropes[character] = nil
		end
	end
	for character, fx in self.Status do
		if not alive[character] then
			fx.Shield:Destroy()
			fx.Ice:Destroy()
			fx.BoostHolder:Destroy()
			for _, star in fx.Stars do
				star:Destroy()
			end
			self.Status[character] = nil
		end
	end
end

function EffectsController:_update(dt: number)
	local t = os.clock()
	local serverNow = workspace:GetServerTimeNow()
	local movement = self.Ctx.MovementController
	local currentCamera = workspace.CurrentCamera
	local cameraPosition = if currentCamera then currentCamera.CFrame.Position else Vector3.zero
	local alive = {}

	-- Spielfiguren: Seile und Status
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if character and root and character.Parent then
			alive[character] = true
			local near = (root.Position - cameraPosition).Magnitude < 400

			local rope = self:_rope(character)
			if rope then
				local anchorPosition = nil
				if other == player then
					anchorPosition = movement:GetGrappleAnchor()
				elseif character:GetAttribute("Grappling") then
					anchorPosition = character:GetAttribute("GrappleTarget")
				end
				if anchorPosition and near then
					rope.Anchor.Position = anchorPosition
					local boosted = (character:GetAttribute("GrappleBoostUntil") or 0) > serverNow
					local color = if boosted then rgb(200, 120, 255) else (character:GetAttribute("AccentColor") or rgb(230, 240, 255))
					rope.Beam.Color = ColorSequence.new(color)
					rope.Beam.Width0 = if boosted then 0.45 else 0.3
					rope.Beam.Enabled = true
				else
					rope.Beam.Enabled = false
				end
			end

			local fx = self:_statusFx(character)
			local position = root.Position
			local shielded = (character:GetAttribute("ShieldUntil") or 0) > serverNow
			local slowed = (character:GetAttribute("SlowedUntil") or 0) > serverNow
			local stunned = (character:GetAttribute("StunnedUntil") or 0) > serverNow
			local boosted = (character:GetAttribute("BoostUntil") or 0) > serverNow
			fx.Shield.Transparency = if shielded and near then 0.35 else 1
			fx.Shield.CFrame = CFrame.new(position)
			fx.Ice.Transparency = if slowed and near then 0.45 else 1
			fx.Ice.CFrame = CFrame.new(position)
			for i, star in fx.Stars do
				local angle = t * 6 + i * (math.pi * 2 / 3)
				star.Transparency = if stunned and near then 0 else 1
				star.CFrame = CFrame.new(position + Vector3.new(math.cos(angle) * 1.4, 3.6, math.sin(angle) * 1.4))
			end
			local facing = character:GetAttribute("Facing") or 1
			if other == player then
				facing = movement:GetFacing()
			end
			fx.BoostHolder.CFrame = CFrame.new(position - Vector3.new(facing * 1.2, 0, 0))
			fx.Boost.EmissionDirection = if facing > 0 then Enum.NormalId.Left else Enum.NormalId.Right
			fx.Boost.Enabled = boosted and near
		end
	end
	self:_cleanupCharacters(alive)

	-- Zielmarkierung
	local target = movement.Target
	local frozen = player.Character and player.Character:GetAttribute("Frozen")
	if target and not frozen then
		self.Marker.Adornee = target
		self.Marker.Enabled = true
		local pulse = 1 + math.sin(t * 8) * 0.12
		self.MarkerRing.Size = UDim2.fromScale(pulse, pulse)
		local cooldowns = movement:GetCooldowns()
		self.MarkerRing.UIStroke.Color = if cooldowns.Grapple > 0 then rgb(150, 150, 160) else rgb(255, 255, 255)
	else
		self.Marker.Enabled = false
	end

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

	self:_updateZone(dt)
end

function EffectsController:_updateZone(dt: number)
	local state = self.Ctx.ClientState
	local gameState = state.GameState
	local zoneState = gameState:GetAttribute("ZoneState") or "Inactive"
	local watching = state:IsInRace() or self.Ctx.CameraController:GetSpectate() ~= nil
	local active = watching and (zoneState == "Shrinking" or zoneState == "Final" or zoneState == "Warning")
	if not active then
		self.ZoneWall.Transparency = 1
		self.ZoneTint.Transparency = 1
		self.ZoneVisualX = nil
		return
	end
	local targetX = gameState:GetAttribute("ZoneX") or -1e6
	if zoneState == "Warning" then
		targetX = (gameState:GetAttribute("StartX") or 0) - 20
	end
	if not self.ZoneVisualX or math.abs(targetX - self.ZoneVisualX) > 200 then
		self.ZoneVisualX = targetX
	else
		self.ZoneVisualX = Util.Damp(self.ZoneVisualX, targetX, 8, dt)
	end
	local x = self.ZoneVisualX
	local cameraY = if workspace.CurrentCamera then workspace.CurrentCamera.CFrame.Position.Y else 0
	local pulse = 0.5 + math.sin(os.clock() * 6) * 0.1
	self.ZoneWall.CFrame = CFrame.new(x, cameraY, -40)
	self.ZoneWall.Transparency = if zoneState == "Warning" then 0.75 else pulse
	self.ZoneTint.CFrame = CFrame.new(x - 2002, cameraY, Config.World.TrackDepth / 2 + 3)
	self.ZoneTint.Transparency = if zoneState == "Warning" then 1 else 0.86
end

return EffectsController
