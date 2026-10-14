--[[
	CosmeticApplier  (ModuleScript)
	Pfad: ReplicatedStorage/Shared/CosmeticApplier

	Wendet ausgerüstete Kosmetik (Skin, Farbvariante, Trail, Partikeleffekt)
	auf ein RunnerRig an. Wird vom Server für echte Spielfiguren und vom Client
	für die Shop-Vorschau verwendet.

	Ablauf von Apply:
		1. Clear: entfernt den Ordner "VR_Cosmetics" und alles mit Attribut
		   VR_Cosmetic – erneutes Anwenden dupliziert also nie etwas.
		2. Knochen (R15-Körperteile) und die Körperhülle aus RunnerRig
		   (Ordner "VR_Body", Attribute VR_Paint/VR_Tag) werden nur umgefärbt,
		   umgestellt (Material, Glanz) und ggf. per HideBase ausgeblendet –
		   die Hülle wird nie neu erzeugt.
		3. Accessoires des Skins werden als geschweißte, rein visuelle Teile in
		   "VR_Cosmetics" gebaut (Block, Kugel, Zylinder, Keil, Ellipsoid per
		   SpecialMesh "Sphere").
		4. Trail (breites Farbband + optionaler heller Kernstreifen) und
		   Partikeleffekt am Oberkörper.

	Farbslots (Accessoires und Hülle):
		Körpergruppen  Head, Torso, Hips, Arms, Hands, Legs, Feet (skin.Colors)
		Primary, Secondary, Dark, Visor   Palette des Skins
		Accent         Akzentfarbe (Farbvariante überschreibt), festes Material
		Glow           Akzentfarbe als Neon
		Trim, Ears, Joint, Collar, Belt, Sole   Zusatzslots mit Fallback
		Color3         feste Farbe

	Alle erzeugten Objekte sind rein visuell:
		Massless = true, CanCollide = false, CanQuery = false, CanTouch = false.

	API:
		CosmeticApplier.Apply(model, equipped)   equipped = { Skins="Rookie", Trails="", ... }
		CosmeticApplier.Clear(model)
		CosmeticApplier.GetAccentColor(equipped) -> Color3
		CosmeticApplier.Rainbow                  (ColorSequence)
]]

local CosmeticDefinitions = require(script.Parent.CosmeticDefinitions)

local CosmeticApplier = {}

local FOLDER_NAME = "VR_Cosmetics"
local BODY_FOLDER = "VR_Body" -- siehe RunnerRig.BodyFolder

local GROUP_BY_PART = {
	Head = "Head",
	UpperTorso = "Torso",
	LowerTorso = "Hips",
	LeftUpperArm = "Arms",
	LeftLowerArm = "Arms",
	RightUpperArm = "Arms",
	RightLowerArm = "Arms",
	LeftHand = "Hands",
	RightHand = "Hands",
	LeftUpperLeg = "Legs",
	LeftLowerLeg = "Legs",
	RightUpperLeg = "Legs",
	RightLowerLeg = "Legs",
	LeftFoot = "Feet",
	RightFoot = "Feet",
}

-- Zusatzslots der Körperhülle fallen auf diese Slots zurück, wenn der Skin sie
-- nicht selbst definiert.
local SLOT_FALLBACK = {
	Trim = "Secondary",
	Ears = "Primary",
	Collar = "Joint",
	Joint = "Dark",
	Belt = "Dark",
	Sole = "Dark",
}

local function getSkin(equipped)
	local id = equipped and equipped.Skins or "Rookie"
	return CosmeticDefinitions.Get("Skins", id) or CosmeticDefinitions.Get("Skins", "Rookie")
end

--- Liefert die effektive Akzentfarbe (Farbvariante überschreibt Skin-Akzent).
function CosmeticApplier.GetAccentColor(equipped): Color3
	local skin = getSkin(equipped)
	if equipped and equipped.Colors and equipped.Colors ~= "" then
		local variant = CosmeticDefinitions.Get("Colors", equipped.Colors)
		if variant then
			return variant.Color
		end
	end
	return skin.Accent
end

local function resolveColor(key, skin, accent: Color3, depth: number?): Color3
	if typeof(key) == "Color3" then
		return key
	elseif key == "Accent" or key == "Glow" then
		return accent
	elseif key == "Visor" then
		return skin.Visor or accent
	elseif type(key) ~= "string" then
		return skin.Primary
	end
	local groupColor = skin.Colors and skin.Colors[key]
	if groupColor then
		return groupColor
	end
	local value = skin[key]
	if typeof(value) == "Color3" then
		return value
	end
	local fallback = SLOT_FALLBACK[key]
	if fallback and (depth or 0) < 4 then
		return resolveColor(fallback, skin, accent, (depth or 0) + 1)
	end
	return skin.Primary
end

local function resolveMaterial(key, skin): Enum.Material
	local materials = skin.Materials
	if type(key) == "string" and materials and materials[key] then
		return materials[key]
	end
	if key == "Glow" or key == "Visor" then
		return Enum.Material.Neon
	end
	if key == "Primary" or (type(key) == "string" and skin.Colors and skin.Colors[key]) then
		return skin.Material or Enum.Material.SmoothPlastic
	end
	if typeof(key) == "Color3" then
		return Enum.Material.SmoothPlastic
	end
	return skin.TrimMaterial or Enum.Material.SmoothPlastic
end

local function makeShape(shape: string): BasePart
	if shape == "Wedge" then
		return Instance.new("WedgePart")
	end
	local part = Instance.new("Part")
	if shape == "Ball" then
		part.Shape = Enum.PartType.Ball
	elseif shape == "Cylinder" then
		part.Shape = Enum.PartType.Cylinder
	else
		part.Shape = Enum.PartType.Block
		if shape == "Ellipsoid" then
			-- Eingebautes Kugel-Mesh skaliert mit der Part-Größe -> Ellipsoid
			local mesh = Instance.new("SpecialMesh")
			mesh.Name = "VR_Mesh"
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Scale = Vector3.one
			mesh.Parent = part
		end
	end
	return part
end

--- Entfernt alle von diesem Modul erzeugten Objekte.
function CosmeticApplier.Clear(model: Model)
	local folder = model:FindFirstChild(FOLDER_NAME)
	if folder then
		folder:Destroy()
	end
	for _, descendant in model:GetDescendants() do
		if descendant:GetAttribute("VR_Cosmetic") then
			descendant:Destroy()
		end
	end
end

local function sequence(...: Color3): ColorSequence
	local colors = { ... }
	if #colors == 1 then
		return ColorSequence.new(colors[1])
	end
	local keypoints = {}
	for index, color in colors do
		table.insert(keypoints, ColorSequenceKeypoint.new((index - 1) / (#colors - 1), color))
	end
	return ColorSequence.new(keypoints)
end

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 70, 90)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 190, 50)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(90, 255, 120)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(60, 200, 255)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(130, 90, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 70, 210)),
})
CosmeticApplier.Rainbow = RAINBOW

------------------------------------------------------------------------
-- Körper und Accessoires
------------------------------------------------------------------------

--- Färbt Knochen und Körperhülle passend zum Skin (Hülle bleibt bestehen).
local function paintBody(model: Model, skin, accent: Color3)
	local baseMaterial = skin.Material or Enum.Material.SmoothPlastic
	local materials = skin.Materials or {}
	for partName, group in GROUP_BY_PART do
		local part = model:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			part.Color = skin.Colors[group] or skin.Primary
			part.Material = materials[group] or baseMaterial
		end
	end

	local body = model:FindFirstChild(BODY_FOLDER)
	if not body then
		return
	end
	local hidden = {}
	for _, tag in skin.HideBase or {} do
		hidden[tag] = true
	end
	local reflectance = skin.Reflectance or 0
	for _, shell in body:GetChildren() do
		if shell:IsA("BasePart") then
			local slot = shell:GetAttribute("VR_Paint")
			if slot then
				shell.Color = resolveColor(slot, skin, accent)
				shell.Material = resolveMaterial(slot, skin)
				-- Glanz nur auf den Körpergruppen, nicht auf Leuchtteilen
				shell.Reflectance = if skin.Colors[slot] then reflectance else 0
			end
			local tag = shell:GetAttribute("VR_Tag")
			shell.Transparency = if tag and hidden[tag] then 1 else 0
		end
	end
end

local function buildAccessories(model: Model, folder: Folder, skin, accent: Color3, created: { Instance })
	for _, presetName in skin.Accessories or {} do
		local preset = CosmeticDefinitions.AccessoryPresets[presetName]
		if preset then
			for index, piece in preset do
				local attachTo = model:FindFirstChild(piece.Attach)
				if attachTo and attachTo:IsA("BasePart") then
					local part = makeShape(piece.Shape)
					part.Name = presetName .. "_" .. index
					part.Size = piece.Size
					part.Color = resolveColor(piece.Color, skin, accent)
					part.Material = piece.Material or resolveMaterial(piece.Color, skin)
					part.Transparency = piece.Transparency or 0
					part.Reflectance = piece.Reflectance or 0
					part.TopSurface = Enum.SurfaceType.Smooth
					part.BottomSurface = Enum.SurfaceType.Smooth
					part.Anchored = false
					part.CanCollide = false
					part.CanQuery = false
					part.CanTouch = false
					part.Massless = true
					part.CastShadow = piece.Shadow == true
					part.CFrame = attachTo.CFrame * piece.Offset
					part.CollisionGroup = attachTo.CollisionGroup

					local weld = Instance.new("Weld")
					weld.Part0 = attachTo
					weld.Part1 = part
					weld.C0 = piece.Offset
					weld.Parent = part

					part.Parent = folder
					table.insert(created, part)
				end
			end
		end
	end
end

------------------------------------------------------------------------
-- Trail und Partikel
------------------------------------------------------------------------

local function cosmeticAttachment(parent: Instance, name: string, position: Vector3): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Position = position
	attachment:SetAttribute("VR_Cosmetic", true)
	attachment.Parent = parent
	return attachment
end

local function makeTrail(name: string, torso: BasePart, halfHeight: number, options): Trail
	local top = cosmeticAttachment(torso, name .. "Top", Vector3.new(0, halfHeight, 0.3))
	local bottom = cosmeticAttachment(torso, name .. "Bottom", Vector3.new(0, -halfHeight, 0.3))

	local trail = Instance.new("Trail")
	trail.Name = name
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = options.Lifetime
	trail.MinLength = 0.1
	trail.FaceCamera = true
	trail.LightEmission = options.LightEmission
	trail.LightInfluence = options.LightInfluence
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, options.Width),
		NumberSequenceKeypoint.new(1, options.WidthEnd),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, options.Transparency),
		NumberSequenceKeypoint.new(0.55, options.Transparency + (1 - options.Transparency) * 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Color = options.Color
	trail:SetAttribute("VR_Cosmetic", true)
	trail.Parent = torso
	return trail
end

local function applyTrail(model: Model, created: { Instance }, trailDef)
	local torso = model:FindFirstChild("UpperTorso")
	if not torso or not torso:IsA("BasePart") then
		return
	end
	local color
	if trailDef.Rainbow then
		color = RAINBOW
	elseif trailDef.ColorMid then
		color = sequence(trailDef.ColorA, trailDef.ColorMid, trailDef.ColorB)
	else
		color = sequence(trailDef.ColorA, trailDef.ColorB)
	end
	local glowing = (trailDef.LightEmission or 0.5) > 0.3
	local lifetime = trailDef.Lifetime or 0.4

	-- Breites Farbband hinter dem Oberkörper
	table.insert(
		created,
		makeTrail("VR_Trail", torso, 0.55, {
			Lifetime = lifetime,
			LightEmission = trailDef.LightEmission or 0.5,
			LightInfluence = if glowing then 0.2 else 1,
			Width = trailDef.Width or 1,
			WidthEnd = trailDef.WidthEnd or 0,
			Transparency = trailDef.Transparency or 0.15,
			Color = color,
		})
	)

	-- Heller, schmaler Kern für einen Leuchtstreifen-Look
	if trailDef.Core then
		local edge = if trailDef.Rainbow then Color3.fromRGB(255, 255, 255) else trailDef.ColorA
		table.insert(
			created,
			makeTrail("VR_TrailCore", torso, 0.16, {
				Lifetime = lifetime * 0.6,
				LightEmission = 1,
				LightInfluence = 0,
				Width = 1,
				WidthEnd = 0.2,
				Transparency = 0.05,
				Color = sequence(trailDef.Core, edge),
			})
		)
	end
end

local function applyEffect(model: Model, effectDef)
	local torso = model:FindFirstChild("UpperTorso")
	if not torso then
		return
	end
	local attachment = cosmeticAttachment(torso, "VR_EffectAttachment", Vector3.new(0, -0.1, 0))

	local size = effectDef.Size or 0.3
	local speed = effectDef.Speed or 1
	local lifetime = effectDef.Lifetime or 1

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "VR_Effect"
	emitter.Rate = effectDef.Rate or 10
	emitter.Lifetime = NumberRange.new(lifetime * 0.6, lifetime)
	emitter.Speed = NumberRange.new(speed, speed * 1.5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.LightEmission = effectDef.LightEmission or 0.5
	emitter.LightInfluence = if (effectDef.LightEmission or 0.5) > 0.5 then 0 else 1
	emitter.Drag = effectDef.Drag or 0
	emitter.ZOffset = 0.5
	if effectDef.Twinkle then
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.15, size),
			NumberSequenceKeypoint.new(0.35, size * 0.35),
			NumberSequenceKeypoint.new(0.55, size * 0.9),
			NumberSequenceKeypoint.new(1, 0),
		})
	else
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, size * 0.4),
			NumberSequenceKeypoint.new(0.2, size),
			NumberSequenceKeypoint.new(1, 0),
		})
	end
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.7, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	if effectDef.Rainbow then
		emitter.Color = RAINBOW
	elseif effectDef.Color2 then
		emitter.Color = sequence(effectDef.Color, effectDef.Color2)
	else
		emitter.Color = ColorSequence.new(effectDef.Color)
	end
	if effectDef.Rise then
		emitter.Acceleration = Vector3.new(0, effectDef.Rise, 0)
	end
	if effectDef.Spin then
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-effectDef.Spin, effectDef.Spin)
	end
	emitter:SetAttribute("VR_Cosmetic", true)
	emitter.Parent = attachment
end

--- Wendet die komplette Kosmetik auf ein Rig an (ersetzt vorherige Kosmetik).
function CosmeticApplier.Apply(model: Model, equipped)
	CosmeticApplier.Clear(model)
	equipped = equipped or CosmeticDefinitions.DefaultEquipped

	local skin = getSkin(equipped)
	local accent = CosmeticApplier.GetAccentColor(equipped)

	paintBody(model, skin, accent)

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	local created = {}
	buildAccessories(model, folder, skin, accent, created)
	folder.Parent = model

	if equipped.Trails and equipped.Trails ~= "" then
		local trailDef = CosmeticDefinitions.Get("Trails", equipped.Trails)
		if trailDef then
			applyTrail(model, created, trailDef)
		end
	end

	if equipped.Effects and equipped.Effects ~= "" then
		local effectDef = CosmeticDefinitions.Get("Effects", equipped.Effects)
		if effectDef then
			applyEffect(model, effectDef)
		end
	end

	model:SetAttribute("AccentColor", accent)
	return created
end

return CosmeticApplier
