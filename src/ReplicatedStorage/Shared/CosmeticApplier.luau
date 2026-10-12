--[[
	CosmeticApplier  (ModuleScript)
	Pfad: ReplicatedStorage/Shared/CosmeticApplier

	Wendet ausgerüstete Kosmetik (Skin, Farbvariante, Trail, Partikeleffekt)
	auf ein RunnerRig an. Wird vom Server für echte Spielfiguren und vom Client
	für die Shop-Vorschau verwendet.

	Alle erzeugten Objekte sind rein visuell:
		Massless = true, CanCollide = false, CanQuery = false, CanTouch = false.

	API:
		CosmeticApplier.Apply(model, equipped)   equipped = { Skins="Rookie", Trails="", ... }
		CosmeticApplier.Clear(model)
		CosmeticApplier.GetAccentColor(equipped) -> Color3
]]

local CosmeticDefinitions = require(script.Parent.CosmeticDefinitions)

local CosmeticApplier = {}

local FOLDER_NAME = "VR_Cosmetics"

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

local function resolveColor(key, skin, accent): Color3
	if typeof(key) == "Color3" then
		return key
	elseif key == "Accent" then
		return accent
	elseif key == "Visor" then
		return skin.Visor or accent
	elseif key == "Primary" then
		return skin.Primary
	elseif key == "Secondary" then
		return skin.Secondary
	elseif key == "Dark" then
		return skin.Dark
	end
	return skin.Primary
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

local function sequenceFromColors(a: Color3, b: Color3): ColorSequence
	return ColorSequence.new({ ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b) })
end

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 60)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 200, 40)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(80, 255, 80)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(60, 200, 255)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(120, 80, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 60, 200)),
})
CosmeticApplier.Rainbow = RAINBOW

local function applyTrail(model: Model, folderParts: { Instance }, trailDef)
	local torso = model:FindFirstChild("UpperTorso")
	if not torso then
		return
	end
	local top = Instance.new("Attachment")
	top.Name = "VR_TrailTop"
	top.Position = Vector3.new(0, 0.55, 0.3)
	top:SetAttribute("VR_Cosmetic", true)
	top.Parent = torso
	local bottom = Instance.new("Attachment")
	bottom.Name = "VR_TrailBottom"
	bottom.Position = Vector3.new(0, -0.55, 0.3)
	bottom:SetAttribute("VR_Cosmetic", true)
	bottom.Parent = torso

	local trail = Instance.new("Trail")
	trail.Name = "VR_Trail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = trailDef.Lifetime or 0.4
	trail.MinLength = 0.1
	trail.FaceCamera = true
	trail.LightEmission = trailDef.LightEmission or 0.5
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, trailDef.Width or 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	if trailDef.Rainbow then
		trail.Color = RAINBOW
	else
		trail.Color = sequenceFromColors(trailDef.ColorA, trailDef.ColorB)
	end
	trail:SetAttribute("VR_Cosmetic", true)
	trail.Parent = torso
	table.insert(folderParts, trail)
end

local function applyEffect(model: Model, effectDef)
	local torso = model:FindFirstChild("UpperTorso")
	if not torso then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "VR_EffectAttachment"
	attachment:SetAttribute("VR_Cosmetic", true)
	attachment.Parent = torso

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "VR_Effect"
	emitter.Rate = effectDef.Rate or 10
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.Speed = NumberRange.new(effectDef.Speed or 1, (effectDef.Speed or 1) * 1.5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.LightEmission = effectDef.LightEmission or 0.5
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, effectDef.Size or 0.3),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	if effectDef.Rainbow then
		emitter.Color = RAINBOW
	else
		emitter.Color = ColorSequence.new(effectDef.Color)
	end
	if effectDef.Rise then
		emitter.Acceleration = Vector3.new(0, effectDef.Rise, 0)
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
	local baseMaterial = skin.Material or Enum.Material.SmoothPlastic
	local materials = skin.Materials or {}

	for partName, group in GROUP_BY_PART do
		local part = model:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			part.Color = skin.Colors[group] or skin.Primary
			part.Material = materials[group] or baseMaterial
		end
	end

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	local created = {}

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
					part.Material = piece.Material or baseMaterial
					part.Transparency = piece.Transparency or 0
					part.TopSurface = Enum.SurfaceType.Smooth
					part.BottomSurface = Enum.SurfaceType.Smooth
					part.Anchored = false
					part.CanCollide = false
					part.CanQuery = false
					part.CanTouch = false
					part.Massless = true
					part.CastShadow = false
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
