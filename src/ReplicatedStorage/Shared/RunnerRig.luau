--[[
	RunnerRig  (ModuleScript)
	Pfad: ReplicatedStorage/Shared/RunnerRig

	Baut die einheitliche Spielfigur ("Runner") komplett aus Parts und Motor6Ds.
	Alle Spieler haben dadurch identische Proportionen und Hitboxen – Avatare
	und Skins können keinen Vorteil verschaffen.

	Der Server legt beim Start ein Exemplar als StarterPlayer/StarterCharacter ab
	(siehe CharacterService). Der Client nutzt dieselbe Funktion für die
	Skin-Vorschau im Shop.

	Kollision:
		Nur der unsichtbare Part "VR_Collider" kollidiert mit der Welt
		(CollisionGroup "Runner"). Alle Körperteile sind in "RunnerBody" und
		kollidieren mit nichts. So bleibt die Hitbox exakt definiert.

	API:
		RunnerRig.Build({ ForCharacter = boolean }) -> Model
		RunnerRig.Joints  (Liste der Gelenknamen)
]]

local Config = require(script.Parent.Config)

local RunnerRig = {}

-- Mittelpunkte der Körperteile relativ zur Mitte des HumanoidRootPart (Ruhepose).
local PARTS = {
	{ Name = "LowerTorso", Size = Vector3.new(1.9, 0.6, 1.0), Center = Vector3.new(0, 0, 0) },
	{ Name = "UpperTorso", Size = Vector3.new(2.0, 1.4, 1.0), Center = Vector3.new(0, 1.0, 0) },
	{ Name = "Head", Size = Vector3.new(1.25, 1.25, 1.25), Center = Vector3.new(0, 2.325, 0) },
	{ Name = "LeftUpperArm", Size = Vector3.new(0.8, 1.1, 0.8), Center = Vector3.new(-1.4, 1.15, 0) },
	{ Name = "LeftLowerArm", Size = Vector3.new(0.75, 0.9, 0.75), Center = Vector3.new(-1.4, 0.15, 0) },
	{ Name = "LeftHand", Size = Vector3.new(0.75, 0.35, 0.75), Center = Vector3.new(-1.4, -0.475, 0) },
	{ Name = "RightUpperArm", Size = Vector3.new(0.8, 1.1, 0.8), Center = Vector3.new(1.4, 1.15, 0) },
	{ Name = "RightLowerArm", Size = Vector3.new(0.75, 0.9, 0.75), Center = Vector3.new(1.4, 0.15, 0) },
	{ Name = "RightHand", Size = Vector3.new(0.75, 0.35, 0.75), Center = Vector3.new(1.4, -0.475, 0) },
	{ Name = "LeftUpperLeg", Size = Vector3.new(0.85, 1.1, 0.85), Center = Vector3.new(-0.5, -0.85, 0) },
	{ Name = "LeftLowerLeg", Size = Vector3.new(0.8, 0.95, 0.8), Center = Vector3.new(-0.5, -1.875, 0) },
	{ Name = "LeftFoot", Size = Vector3.new(0.85, 0.35, 1.1), Center = Vector3.new(-0.5, -2.525, -0.1) },
	{ Name = "RightUpperLeg", Size = Vector3.new(0.85, 1.1, 0.85), Center = Vector3.new(0.5, -0.85, 0) },
	{ Name = "RightLowerLeg", Size = Vector3.new(0.8, 0.95, 0.8), Center = Vector3.new(0.5, -1.875, 0) },
	{ Name = "RightFoot", Size = Vector3.new(0.85, 0.35, 1.1), Center = Vector3.new(0.5, -2.525, -0.1) },
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

local DEFAULT_COLOR = Color3.fromRGB(200, 205, 215)

local function makePart(name: string, size: Vector3, center: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = CFrame.new(center)
	part.Color = DEFAULT_COLOR
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.CastShadow = true
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
	root.CastShadow = false
	root.Parent = model
	parts.HumanoidRootPart = root

	for _, info in PARTS do
		local part = makePart(info.Name, info.Size, info.Center)
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
