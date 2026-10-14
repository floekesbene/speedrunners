--[[
	RunnerRig  (ModuleScript)
	Pfad: ReplicatedStorage/Shared/RunnerRig

	Baut die einheitliche Spielfigur ("Runner") komplett aus Parts und Motor6Ds.
	Alle Spieler haben dadurch identische Proportionen und Hitboxen – Avatare
	und Skins können keinen Vorteil verschaffen.

	Der Server legt beim Start ein Exemplar als StarterPlayer/StarterCharacter ab
	(siehe CharacterService). Der Client nutzt dieselbe Funktion für die
	Skin-Vorschau im Shop.

	Aufbau:
		Skelett   Die 15 Körperteile mit R15-Namen sind unsichtbare "Knochen",
		          verbunden über 15 Motor6D-Gelenke (AnimationController setzt
		          deren Transform). Namen und Gelenkpositionen sind fest.
		Hülle     Sichtbar ist eine stilisierte Figur aus Standardformen
		          (Kugelhelm mit Ohrkapseln, abgerundeter Brustkorb mit
		          V-Silhouette, Brustplatte und Emblem, Gürtel mit Schnalle,
		          zylindrische Arme/Beine mit Kugelgelenken, Handschuhe mit
		          Stulpen, Stiefel mit runder Kappe, Sohle und Zierstreifen).
		          Jedes Hüllenteil ist per Weld an seinen Knochen geschweißt und
		          folgt so der prozeduralen Animation. Die Teile liegen im Ordner
		          "VR_Body" und tragen die Attribute
		              VR_Paint  Farbslot (Körpergruppe Head/Torso/Hips/Arms/Hands/
		                        Legs/Feet oder Trim/Ears/Joint/Collar/Belt/Sole/
		                        Glow/Visor)
		              VR_Tag    optionale Gruppe, die ein Skin per HideBase
		                        ausblenden kann (Ears, Plate, Emblem, Back, Belt,
		                        Stripes)
		          CosmeticApplier färbt sie passend zum Skin ein.
		Blickrichtung des Rigs ist lokal -Z, Rücken +Z, rechte Seite +X. Die
		Spielkamera sieht die Figur im Profil (entlang X), der Shop von vorn –
		deshalb haben Seiten (Ohrkapseln, Streifen, Stiefel) eigene Details.

	Kollision:
		Nur der unsichtbare Part "VR_Collider" kollidiert mit der Welt
		(CollisionGroup "Runner"). Knochen und Hülle sind Massless,
		CanCollide/CanQuery/CanTouch = false und (als Spielfigur) in der Gruppe
		"RunnerBody". So bleibt die Hitbox exakt definiert.

	API:
		RunnerRig.Build({ ForCharacter = boolean }) -> Model
		RunnerRig.Joints     (Liste der Gelenknamen)
		RunnerRig.PartNames  (Liste der Körperteil-/Knochennamen)
		RunnerRig.BodyFolder (Name des Hüllen-Ordners, "VR_Body")
]]

local Config = require(script.Parent.Config)

local RunnerRig = {}

RunnerRig.BodyFolder = "VR_Body"

-- Mittelpunkte der Körperteile relativ zur Mitte des HumanoidRootPart (Ruhepose).
local PARTS = {
	{ Name = "LowerTorso", Size = Vector3.new(1.9, 0.6, 1.0), Center = Vector3.new(0, 0, 0) },
	{ Name = "UpperTorso", Size = Vector3.new(2.0, 1.4, 1.0), Center = Vector3.new(0, 1.0, 0) },
	{ Name = "Head", Size = Vector3.new(1.3, 1.3, 1.3), Center = Vector3.new(0, 2.325, 0) },
	{ Name = "LeftUpperArm", Size = Vector3.new(0.7, 1.1, 0.7), Center = Vector3.new(-1.4, 1.15, 0) },
	{ Name = "LeftLowerArm", Size = Vector3.new(0.6, 0.9, 0.6), Center = Vector3.new(-1.4, 0.15, 0) },
	{ Name = "LeftHand", Size = Vector3.new(0.62, 0.35, 0.62), Center = Vector3.new(-1.4, -0.475, 0) },
	{ Name = "RightUpperArm", Size = Vector3.new(0.7, 1.1, 0.7), Center = Vector3.new(1.4, 1.15, 0) },
	{ Name = "RightLowerArm", Size = Vector3.new(0.6, 0.9, 0.6), Center = Vector3.new(1.4, 0.15, 0) },
	{ Name = "RightHand", Size = Vector3.new(0.62, 0.35, 0.62), Center = Vector3.new(1.4, -0.475, 0) },
	{ Name = "LeftUpperLeg", Size = Vector3.new(0.78, 1.1, 0.78), Center = Vector3.new(-0.5, -0.85, 0) },
	{ Name = "LeftLowerLeg", Size = Vector3.new(0.7, 0.95, 0.7), Center = Vector3.new(-0.5, -1.875, 0) },
	{ Name = "LeftFoot", Size = Vector3.new(0.8, 0.35, 1.1), Center = Vector3.new(-0.5, -2.525, -0.1) },
	{ Name = "RightUpperLeg", Size = Vector3.new(0.78, 1.1, 0.78), Center = Vector3.new(0.5, -0.85, 0) },
	{ Name = "RightLowerLeg", Size = Vector3.new(0.7, 0.95, 0.7), Center = Vector3.new(0.5, -1.875, 0) },
	{ Name = "RightFoot", Size = Vector3.new(0.8, 0.35, 1.1), Center = Vector3.new(0.5, -2.525, -0.1) },
}

-- Gelenke: Name, Part0 (Elternteil), Part1 (Kind), Gelenkposition (Ruhepose)
local JOINTS = {
	{ Name = "Root", Part0 = "HumanoidRootPart", Part1 = "LowerTorso", At = Vector3.new(0, 0, 0) },
	{ Name = "Waist", Part0 = "LowerTorso", Part1 = "UpperTorso", At = Vector3.new(0, 0.3, 0) },
	{ Name = "Neck", Part0 = "UpperTorso", Part1 = "Head", At = Vector3.new(0, 1.7, 0) },
	{ Name = "LeftShoulder", Part0 = "UpperTorso", Part1 = "LeftUpperArm", At = Vector3.new(-1.4, 1.55, 0) },
	{ Name = "LeftElbow", Part0 = "LeftUpperArm", Part1 = "LeftLowerArm", At = Vector3.new(-1.4, 0.6, 0) },
	{ Name = "LeftWrist", Part0 = "LeftLowerArm", Part1 = "LeftHand", At = Vector3.new(-1.4, -0.3, 0) },
	{ Name = "RightShoulder", Part0 = "UpperTorso", Part1 = "RightUpperArm", At = Vector3.new(1.4, 1.55, 0) },
	{ Name = "RightElbow", Part0 = "RightUpperArm", Part1 = "RightLowerArm", At = Vector3.new(1.4, 0.6, 0) },
	{ Name = "RightWrist", Part0 = "RightLowerArm", Part1 = "RightHand", At = Vector3.new(1.4, -0.3, 0) },
	{ Name = "LeftHip", Part0 = "LowerTorso", Part1 = "LeftUpperLeg", At = Vector3.new(-0.5, -0.35, 0) },
	{ Name = "LeftKnee", Part0 = "LeftUpperLeg", Part1 = "LeftLowerLeg", At = Vector3.new(-0.5, -1.4, 0) },
	{ Name = "LeftAnkle", Part0 = "LeftLowerLeg", Part1 = "LeftFoot", At = Vector3.new(-0.5, -2.35, 0) },
	{ Name = "RightHip", Part0 = "LowerTorso", Part1 = "RightUpperLeg", At = Vector3.new(0.5, -0.35, 0) },
	{ Name = "RightKnee", Part0 = "RightUpperLeg", Part1 = "RightLowerLeg", At = Vector3.new(0.5, -1.4, 0) },
	{ Name = "RightAnkle", Part0 = "RightLowerLeg", Part1 = "RightFoot", At = Vector3.new(0.5, -2.35, 0) },
}

RunnerRig.Joints = {}
for _, joint in JOINTS do
	table.insert(RunnerRig.Joints, joint.Name)
end

RunnerRig.PartNames = {}
for _, info in PARTS do
	table.insert(RunnerRig.PartNames, info.Name)
end

------------------------------------------------------------------------
-- Sichtbare Hülle
------------------------------------------------------------------------

local rad = math.rad
local V = Vector3.new
local CF = CFrame.new
local CYL_Y = CFrame.Angles(0, 0, rad(90)) -- Zylinderachse senkrecht (Y)
local CYL_Z = CFrame.Angles(0, rad(90), 0) -- Zylinderachse nach vorn (Z)

-- Startfarben (= Rookie-Skin), bis CosmeticApplier den echten Skin setzt.
local DEFAULT_PAINT = {
	Head = Color3.fromRGB(242, 245, 252),
	Torso = Color3.fromRGB(36, 120, 255),
	Hips = Color3.fromRGB(28, 36, 62),
	Arms = Color3.fromRGB(36, 120, 255),
	Hands = Color3.fromRGB(242, 245, 252),
	Legs = Color3.fromRGB(34, 46, 82),
	Feet = Color3.fromRGB(242, 245, 252),
	Trim = Color3.fromRGB(242, 245, 252),
	Ears = Color3.fromRGB(36, 120, 255),
	Joint = Color3.fromRGB(22, 26, 40),
	Collar = Color3.fromRGB(22, 26, 40),
	Belt = Color3.fromRGB(22, 26, 40),
	Sole = Color3.fromRGB(255, 186, 40),
	Glow = Color3.fromRGB(0, 214, 255),
	Visor = Color3.fromRGB(70, 230, 255),
}
local GLOW_PAINT = { Glow = true, Visor = true }
local FALLBACK_COLOR = Color3.fromRGB(200, 205, 215)

-- Hüllenteile: Bone = Knochen, Shape = Block|Ball|Cylinder, Size, Offset
-- (relativ zur Knochenmitte), Paint = Farbslot, Tag = per Skin ausblendbar,
-- Shadow = wirft Schatten (nur die großen Volumen).
local SHELLS = {
	-- Kopf: Kugelhelm, eine durchgehende Walze bildet beide Ohrkapseln (Kopfhörer-Look)
	{ Name = "Helmet", Bone = "Head", Shape = "Ball", Size = V(1.36, 1.36, 1.36), Offset = CF(0, 0.02, 0), Paint = "Head", Shadow = true },
	{ Name = "EarCaps", Bone = "Head", Shape = "Cylinder", Size = V(1.52, 0.52, 0.52), Offset = CF(0, -0.04, 0.08), Paint = "Ears", Tag = "Ears" },

	-- Oberkörper: Walze (im Profil runde Brust/Schultern) + schmalere Taille
	{ Name = "Chest", Bone = "UpperTorso", Shape = "Cylinder", Size = V(1.96, 1.24, 1.24), Offset = CF(0, 0.1, 0), Paint = "Torso", Shadow = true },
	{ Name = "Waist", Bone = "UpperTorso", Shape = "Block", Size = V(1.5, 0.9, 1.06), Offset = CF(0, -0.27, 0), Paint = "Torso", Shadow = true },
	{ Name = "Collar", Bone = "UpperTorso", Shape = "Cylinder", Size = V(0.24, 0.98, 0.98), Offset = CF(0, 0.7, 0) * CYL_Y, Paint = "Collar" },
	{ Name = "ChestPlate", Bone = "UpperTorso", Shape = "Block", Size = V(1.2, 0.62, 0.14), Offset = CF(0, 0.05, -0.58), Paint = "Trim", Tag = "Plate" },
	{ Name = "Emblem", Bone = "UpperTorso", Shape = "Cylinder", Size = V(0.06, 0.36, 0.36), Offset = CF(0, 0.07, -0.66) * CYL_Z, Paint = "Glow", Tag = "Emblem" },
	{ Name = "BackPlate", Bone = "UpperTorso", Shape = "Block", Size = V(1.1, 0.8, 0.22), Offset = CF(0, 0, 0.6), Paint = "Trim", Tag = "Back" },

	-- Hüfte mit rundem Sitz, Gürtel, Schnalle und seitlichen Gürtellichtern
	{ Name = "Hips", Bone = "LowerTorso", Shape = "Block", Size = V(1.5, 0.5, 1.04), Offset = CF(0, 0.02, 0), Paint = "Hips", Shadow = true },
	{ Name = "Seat", Bone = "LowerTorso", Shape = "Cylinder", Size = V(1.46, 0.96, 0.96), Offset = CF(0, -0.12, 0), Paint = "Hips", Shadow = true },
	{ Name = "Belt", Bone = "LowerTorso", Shape = "Block", Size = V(1.6, 0.2, 1.12), Offset = CF(0, 0.22, 0), Paint = "Belt" },
	{ Name = "Buckle", Bone = "LowerTorso", Shape = "Block", Size = V(0.42, 0.26, 0.08), Offset = CF(0, 0.22, -0.59), Paint = "Glow", Tag = "Belt" },
	{ Name = "BeltLights", Bone = "LowerTorso", Shape = "Cylinder", Size = V(1.66, 0.13, 0.13), Offset = CF(0, 0.22, 0.18), Paint = "Glow", Tag = "Belt" },
}

-- Arme und Beine sind symmetrisch (Offsets liegen mittig im Knochen).
for _, side in { "Left", "Right" } do
	local limbShells = {
		-- Arm: Schulterkugel, Ärmel mit Leuchtstreifen, Ellbogen, Unterarm, Stulpe, Handschuh
		{ Name = "Shoulder", Bone = "UpperArm", Shape = "Ball", Size = V(0.76, 0.76, 0.76), Offset = CF(0, 0.26, 0), Paint = "Arms", Shadow = true },
		{ Name = "Sleeve", Bone = "UpperArm", Shape = "Cylinder", Size = V(0.9, 0.58, 0.58), Offset = CF(0, -0.15, 0) * CYL_Y, Paint = "Arms", Shadow = true },
		{ Name = "ArmStripe", Bone = "UpperArm", Shape = "Block", Size = V(0.62, 0.62, 0.1), Offset = CF(0, -0.12, 0), Paint = "Glow", Tag = "Stripes" },
		{ Name = "Elbow", Bone = "LowerArm", Shape = "Ball", Size = V(0.56, 0.56, 0.56), Offset = CF(0, 0.45, 0), Paint = "Joint" },
		{ Name = "Forearm", Bone = "LowerArm", Shape = "Cylinder", Size = V(0.62, 0.52, 0.52), Offset = CF(0, 0.12, 0) * CYL_Y, Paint = "Arms", Shadow = true },
		{ Name = "Cuff", Bone = "LowerArm", Shape = "Cylinder", Size = V(0.3, 0.64, 0.64), Offset = CF(0, -0.3, 0) * CYL_Y, Paint = "Hands" },
		{ Name = "Glove", Bone = "Hand", Shape = "Ball", Size = V(0.62, 0.62, 0.62), Offset = CF(0, -0.07, 0), Paint = "Hands", Shadow = true },
		-- Bein: Oberschenkel mit Streifen, Knie, Schienbein, Stiefelschaft
		{ Name = "Thigh", Bone = "UpperLeg", Shape = "Cylinder", Size = V(1.05, 0.74, 0.74), Offset = CF(0, 0.02, 0) * CYL_Y, Paint = "Legs", Shadow = true },
		{ Name = "LegStripe", Bone = "UpperLeg", Shape = "Block", Size = V(0.78, 0.8, 0.12), Offset = CF(0, 0, 0), Paint = "Glow", Tag = "Stripes" },
		{ Name = "Knee", Bone = "LowerLeg", Shape = "Ball", Size = V(0.66, 0.66, 0.66), Offset = CF(0, 0.475, 0), Paint = "Joint" },
		{ Name = "Shin", Bone = "LowerLeg", Shape = "Cylinder", Size = V(0.62, 0.64, 0.64), Offset = CF(0, 0.17, 0) * CYL_Y, Paint = "Legs", Shadow = true },
		{ Name = "BootShaft", Bone = "LowerLeg", Shape = "Cylinder", Size = V(0.5, 0.74, 0.74), Offset = CF(0, -0.27, 0) * CYL_Y, Paint = "Feet", Shadow = true },
		-- Fuß: Stiefel mit runder Kappe, Sohle bis exakt Fußsohlenhöhe (-2.7), Seitenstreifen
		{ Name = "Boot", Bone = "Foot", Shape = "Block", Size = V(0.76, 0.34, 0.9), Offset = CF(0, 0.03, 0.1), Paint = "Feet", Shadow = true },
		{ Name = "Toe", Bone = "Foot", Shape = "Cylinder", Size = V(0.76, 0.34, 0.34), Offset = CF(0, 0, -0.4), Paint = "Feet" },
		{ Name = "Sole", Bone = "Foot", Shape = "Block", Size = V(0.82, 0.12, 1.16), Offset = CF(0, -0.115, -0.03), Paint = "Sole" },
		{ Name = "BootStripe", Bone = "Foot", Shape = "Block", Size = V(0.8, 0.08, 0.6), Offset = CF(0, 0.06, 0.08) * CFrame.Angles(rad(-14), 0, 0), Paint = "Glow", Tag = "Stripes" },
	}
	for _, shell in limbShells do
		shell.Name = side .. shell.Name
		shell.Bone = side .. shell.Bone
		table.insert(SHELLS, shell)
	end
end

local function makePart(name: string, size: Vector3, center: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = CFrame.new(center)
	part.Color = FALLBACK_COLOR
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.CastShadow = false
	return part
end

--- Erstellt ein sichtbares Hüllenteil und schweißt es an seinen Knochen.
local function makeShell(info, bone: BasePart, folder: Folder, forCharacter: boolean)
	local part = Instance.new("Part")
	part.Name = info.Name
	-- Form zuerst setzen: Ball erzwingt sonst eine gleichseitige Größe.
	if info.Shape == "Ball" then
		part.Shape = Enum.PartType.Ball
	elseif info.Shape == "Cylinder" then
		part.Shape = Enum.PartType.Cylinder
	else
		part.Shape = Enum.PartType.Block
	end
	part.Size = info.Size
	part.CFrame = bone.CFrame * info.Offset
	part.Color = DEFAULT_PAINT[info.Paint] or FALLBACK_COLOR
	part.Material = if GLOW_PAINT[info.Paint] then Enum.Material.Neon else Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.CastShadow = info.Shadow == true
	if forCharacter then
		part.CollisionGroup = "RunnerBody"
	end
	part:SetAttribute("VR_Paint", info.Paint)
	if info.Tag then
		part:SetAttribute("VR_Tag", info.Tag)
	end

	local weld = Instance.new("Weld")
	weld.Name = "VR_ShellWeld"
	weld.Part0 = bone
	weld.Part1 = part
	weld.C0 = info.Offset
	weld.Parent = part

	part.Parent = folder
	return part
end

--- Erstellt das Rig. Mit ForCharacter=true inklusive Humanoid, Kollider und Ausrichtung.
function RunnerRig.Build(options: { ForCharacter: boolean? }?): Model
	local forCharacter = options ~= nil and options.ForCharacter == true
	local model = Instance.new("Model")
	model.Name = "Runner"

	local parts = {}

	local root = makePart("HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.zero)
	root.Transparency = 1
	root.Massless = false
	root.Parent = model
	parts.HumanoidRootPart = root

	-- Knochen: unsichtbar, tragen Gelenke, Attachments und das Namensschild
	for _, info in PARTS do
		local part = makePart(info.Name, info.Size, info.Center)
		part.Transparency = 1
		part.Parent = model
		parts[info.Name] = part
	end

	for _, joint in JOINTS do
		local part0 = parts[joint.Part0]
		local part1 = parts[joint.Part1]
		local motor = Instance.new("Motor6D")
		motor.Name = joint.Name
		motor.Part0 = part0
		motor.Part1 = part1
		-- Ruhepose: alle Teile achsparallel, daher reichen Positionen.
		motor.C0 = CFrame.new(joint.At - part0.Position)
		motor.C1 = CFrame.new(joint.At - part1.Position)
		motor.Parent = part1
	end

	-- Sichtbare Hülle (nur Welds, keine Motor6Ds – die Animation findet Gelenke per Name)
	local body = Instance.new("Folder")
	body.Name = RunnerRig.BodyFolder
	for _, info in SHELLS do
		local bone = parts[info.Bone]
		if bone then
			makeShell(info, bone, body, forCharacter)
		end
	end
	body.Parent = model

	-- Befestigungspunkte für Seil, Trails und Effekte
	local grip = Instance.new("Attachment")
	grip.Name = "VR_GrappleGrip"
	grip.Position = Vector3.new(0, -0.15, 0)
	grip.Parent = parts.RightHand

	if forCharacter then
		for _, part in parts do
			part.CollisionGroup = "RunnerBody"
		end

		local character = Config.Character
		local centerOffset = character.FeetOffset + character.StandHeight / 2
		local collider = Instance.new("Part")
		collider.Name = "VR_Collider"
		collider.Size = Vector3.new(character.ColliderWidth, character.StandHeight, character.ColliderDepth)
		collider.CFrame = CFrame.new(0, centerOffset, 0)
		collider.Transparency = 1
		collider.CanCollide = true
		collider.CanTouch = false
		collider.CanQuery = false
		collider.CastShadow = false
		collider.Massless = false
		collider.CollisionGroup = "Runner"
		collider.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0, 0, 100, 100)
		collider.Parent = model

		local weld = Instance.new("Weld")
		weld.Name = "VR_ColliderWeld"
		weld.Part0 = root
		weld.Part1 = collider
		weld.C0 = CFrame.new(0, centerOffset, 0)
		weld.Parent = collider

		local alignAttachment = Instance.new("Attachment")
		alignAttachment.Name = "VR_AlignAttachment"
		alignAttachment.Parent = root

		local align = Instance.new("AlignOrientation")
		align.Name = "VR_Align"
		align.Mode = Enum.OrientationAlignmentMode.OneAttachment
		align.Attachment0 = alignAttachment
		align.RigidityEnabled = true
		align.CFrame = CFrame.lookAt(Vector3.zero, Vector3.new(1, 0, 0))
		align.Parent = root

		local humanoid = Instance.new("Humanoid")
		humanoid.RigType = Enum.HumanoidRigType.R15
		humanoid.HipHeight = 1.7
		humanoid.AutomaticScalingEnabled = false
		humanoid.BreakJointsOnDeath = false
		humanoid.RequiresNeck = false
		humanoid.AutoRotate = false
		humanoid.WalkSpeed = 0
		humanoid.UseJumpPower = true
		humanoid.JumpPower = 0
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		pcall(function()
			-- Neuere API: schaltet die Humanoid-Zustandsmaschine komplett ab.
			humanoid.EvaluateStateMachine = false
		end)
		humanoid.Parent = model

		-- Rückenpunkt für Trails/Effekte (wird von CosmeticApplier genutzt)
		local back = Instance.new("Attachment")
		back.Name = "VR_BackAttachment"
		back.Position = Vector3.new(0, 0, 0.5)
		back.Parent = parts.UpperTorso
	end

	model.PrimaryPart = root
	return model
end

return RunnerRig
