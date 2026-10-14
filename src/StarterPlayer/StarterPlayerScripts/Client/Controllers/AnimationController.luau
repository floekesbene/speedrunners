--[[
	AnimationController  (ModuleScript)
	Pfad: StarterPlayer/StarterPlayerScripts/Client/Controllers/AnimationController

	Prozedurale Animationen ohne externe Animations-Assets. Jeder Client
	animiert ALLE Spielfiguren selbst, indem er Motor6D.Transform in
	RunService.PreSimulation setzt (offiziell empfohlener Zeitpunkt).

	Datenquellen:
		Lokale Figur: MovementController (sofort, ohne Latenz)
		Andere Figuren: Character-Attribut "MoveState" (vom Server repliziert)
		                und die (geglättete) replizierte Geschwindigkeit des Root-Parts
	Posen:
		Idle     Atmen, Gewichtsverlagerung, gelegentliches Umschauen
		Run      Laufzyklus mit Gegenbewegung von Armen/Beinen, Kniehub,
		         Vorlage abhängig von Tempo und Beschleunigung, Hüft-/Schulterdrehung,
		         stabilisierter Kopf
		Air      stufenlos zwischen Steigen (angezogene Beine) und Fallen
		         (Beine strecken sich zum Boden, Arme rudern bei hohem Tempo)
		Slide, Wall (Hand und Fuß an der Wand), Grapple (Arm greift Richtung
		Anker, Körper hängt am Seil, Beine pendeln), Dash (Superhelden-Pose),
		Stunned (taumeln), Frozen (Startpose), Emotes und Siegesjubel.
	Zusätzliche Schichten (werden nach dem Überblenden aufaddiert):
		- Landungs-Federung (Einknicken, erkannt über Zustand + Fallgeschwindigkeit,
		  funktioniert damit auch für andere Spieler)
		- Salto nach Wall-Jumps, Greifhaken-Absprüngen und Sprungpads
		- weiche Drehung beim Richtungswechsel (nur lokale Figur)
	Übergänge werden pro Gelenk mit posenabhängiger Schärfe weich überblendet.

	Das Standard-"Animate"-Script wird durch StarterCharacterScripts/Animate
	(leer) ersetzt, damit keine Roblox-Animationen dazwischenfunken.

	API:
		:RegisterPreview(model, getPose)   Vorschau-Rigs (Shop) mitanimieren
		:UnregisterPreview(model)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local RunnerRig = require(Shared.RunnerRig)
local CosmeticDefinitions = require(Shared.CosmeticDefinitions)

local player = Players.LocalPlayer

local TAU = math.pi * 2
local MAX_RUN = Config.Movement.MaxRunSpeed
local ANIMATE_DISTANCE = 320
local FLIP_TIME = 0.46
local TURN_TIME = 0.16

local AnimationController = {}

local function A(x: number, y: number?, z: number?): CFrame
	return CFrame.Angles(x, y or 0, z or 0)
end

local clamp = math.clamp

-- Überblend-Schärfe je Pose (höher = schnellerer Übergang)
local BLEND = {
	Idle = 9,
	Run = 18,
	Air = 11,
	Slide = 22,
	Wall = 16,
	Grapple = 15,
	Dash = 30,
	Stunned = 14,
	Frozen = 10,
	Emote = 12,
	Victory = 12,
}

local AIRBORNE = { Air = true, Grapple = true, Dash = true, Wall = true }
local GROUNDED = { Run = true, Idle = true, Slide = true }

------------------------------------------------------------------------
-- Posen. Jede Pose bekommt einen Kontext c:
--   T (Zeit), Seed (pro Figur), Speed (|vx|), Forward (vx in Blickrichtung),
--   Vy, Phase (Laufzyklus), Accel (Tempoänderung), Reach (Armwinkel zum Anker)
-- Vorzeichen (lokaler Raum der Figur, vorne = -Z):
--   Hüfte/Schulter +X = Glied nach vorn, Knie -X = beugen, Ellbogen +X = beugen,
--   Root -X = Oberkörper nach vorn neigen, Fußgelenk +X = Zehen hoch.
------------------------------------------------------------------------

local POSES = {}

function POSES.Idle(c)
	local t = c.T + c.Seed
	local breath = math.sin(t * 2.1)
	local sway = math.sin(t * 0.8)
	local look = math.noise(t * 0.3, c.Seed) * 1.3
	local nod = math.noise(t * 0.26, c.Seed + 17.3) * 0.5
	return {
		Root = CFrame.new(sway * 0.035, -0.04 + breath * 0.015, 0) * A(0.015 * breath, sway * 0.04, sway * 0.025),
		Waist = A(-0.02 - breath * 0.03, look * 0.12, -sway * 0.03),
		Neck = A(0.03 + nod * 0.25 + breath * 0.015, look * 0.5, 0),
		LeftShoulder = A(0.04 + breath * 0.025, 0, -0.1 - breath * 0.03),
		RightShoulder = A(0.04 + breath * 0.025, 0, 0.1 + breath * 0.03),
		LeftElbow = A(0.2 + breath * 0.04),
		RightElbow = A(0.2 + breath * 0.04),
		LeftWrist = A(0.08),
		RightWrist = A(0.08),
		LeftHip = A(0.03, 0.08, -0.05),
		RightHip = A(-0.03, -0.08, 0.05),
		LeftKnee = A(-0.07),
		RightKnee = A(-0.05),
		LeftAnkle = A(0.04, 0, 0.05),
		RightAnkle = A(0.02, 0, -0.05),
	}
end

function POSES.Run(c)
	local k = clamp(c.Speed / MAX_RUN, 0.25, 1.35)
	local p = c.Phase
	local s, co = math.sin(p), math.cos(p)
	-- Vorlage: wächst mit dem Tempo, beim Beschleunigen mehr, beim Bremsen weniger
	local lean = 0.1 + 0.2 * k + clamp(c.Accel * 0.0016, -0.18, 0.22)
	local hipSwing = 0.5 + 0.42 * k
	local lift = 0.45 + 0.95 * k
	local armSwing = 0.45 + 0.55 * k
	local elbow = 0.55 + 0.75 * k
	-- zwei Schritte pro Zyklus: tief beim Aufsetzen, hoch in der Flugphase
	local bob = (math.abs(co) * 0.24 - 0.12) * k - 0.05 * k
	local hipYaw = -s * 0.1 * k
	local chestYaw = s * 0.22 * k
	-- Kniehub kurz nach dem Abdruck (Bein schwingt nach vorn)
	local kneeL = math.max(0, math.cos(p + 0.5))
	local kneeR = math.max(0, -math.cos(p + 0.5))
	local ankleL = if s > 0 then 0.22 * s * k else 0.4 * s * k
	local ankleR = if s < 0 then -0.22 * s * k else -0.4 * s * k
	return {
		Root = CFrame.new(0, bob, 0) * A(-lean, hipYaw, co * 0.035 * k),
		Waist = A(-0.05 * k + math.abs(co) * 0.04 * k, chestYaw, 0),
		-- Kopf stabilisieren: Neigung und Drehung des Körpers ausgleichen
		Neck = A(lean * 0.8 + 0.04, -(hipYaw + chestYaw) * 0.85, 0),
		LeftHip = A(lean * 0.85 + 0.1 * k + s * hipSwing),
		RightHip = A(lean * 0.85 + 0.1 * k - s * hipSwing),
		LeftKnee = A(-(0.22 * k + lift * kneeL)),
		RightKnee = A(-(0.22 * k + lift * kneeR)),
		LeftAnkle = A(ankleL),
		RightAnkle = A(ankleR),
		LeftShoulder = A(-s * armSwing + lean * 0.25, 0, -0.12 - 0.04 * k),
		RightShoulder = A(s * armSwing + lean * 0.25, 0, 0.12 + 0.04 * k),
		LeftElbow = A(elbow + 0.3 * math.max(0, -s) * k),
		RightElbow = A(elbow + 0.3 * math.max(0, s) * k),
		LeftWrist = A(0.1),
		RightWrist = A(0.1),
	}
end

function POSES.Air(c)
	local rise = clamp(c.Vy / 45, -1, 1)
	local up = math.max(0, rise)
	local down = math.max(0, -rise)
	local fwd = clamp(c.Forward / MAX_RUN, -0.6, 1.4)
	local flail = math.sin(c.T * 10) * down * down
	return {
		Root = A(-0.1 * fwd - 0.08 * up + 0.06 * down),
		Waist = A(-0.1 * up + 0.04 * down),
		Neck = A(0.1 * up - 0.18 * down + 0.08 * fwd),
		LeftHip = A(0.25 + 0.75 * up + 0.15 * down + 0.1 * fwd),
		LeftKnee = A(-(0.3 + 1.1 * up + 0.15 * down)),
		LeftAnkle = A(-0.15 * up + 0.2 * down),
		RightHip = A(-0.05 - 0.3 * up + 0.2 * down),
		RightKnee = A(-(0.35 + 0.55 * up + 0.3 * down)),
		RightAnkle = A(-0.3 * up + 0.15 * down),
		LeftShoulder = A(0.55 * up + 1.35 * down + flail * 0.35, 0, -0.3 - 0.35 * down),
		RightShoulder = A(-0.45 * up + 1.75 * down - flail * 0.35, 0, 0.3 + 0.35 * down),
		LeftElbow = A(0.35 + 0.5 * up + 0.15 * down),
		RightElbow = A(0.35 + 0.4 * up + 0.15 * down),
		LeftWrist = A(0.1),
		RightWrist = A(0.1),
	}
end

function POSES.Slide(c)
	local jitter = math.sin(c.T * 37) * 0.025 * clamp(c.Speed / MAX_RUN, 0, 1)
	return {
		Root = CFrame.new(0, -1.65, 0.3) * A(1.15 + jitter),
		Waist = A(-0.3),
		Neck = A(-0.55 + jitter),
		LeftHip = A(0.18),
		LeftKnee = A(-0.12),
		LeftAnkle = A(0.35),
		RightHip = A(0.7),
		RightKnee = A(-1.5),
		RightAnkle = A(0.2),
		LeftShoulder = A(-0.55, 0, -0.7),
		LeftElbow = A(0.15),
		LeftWrist = A(-0.3),
		RightShoulder = A(0.85, 0, 0.35),
		RightElbow = A(0.95),
	}
end

function POSES.Wall(c)
	local rub = math.sin(c.T * 21) * 0.035
	return {
		-- Rücken von der Wand weg, Blick über die Schulter in Sprungrichtung
		Root = CFrame.new(0, 0, 0.3) * A(0.16 + rub * 0.5),
		Waist = A(0.04, 0.22, 0),
		Neck = A(-0.12, 0.65, 0),
		LeftShoulder = A(1.6 + rub, 0, -0.2),
		LeftElbow = A(0.45),
		RightShoulder = A(1.05 - rub, 0, 0.5),
		RightElbow = A(0.85),
		LeftHip = A(0.8),
		LeftKnee = A(-1.05),
		LeftAnkle = A(0.5),
		RightHip = A(0.3),
		RightKnee = A(-0.55),
		RightAnkle = A(0.2),
	}
end

function POSES.Grapple(c)
	local reach = c.Reach -- Armwinkel um X (pi = senkrecht nach oben)
	local swing = clamp(c.Forward / 60, -1, 1)
	local hang = clamp((reach - math.pi) * 0.3, -0.5, 0.5)
	local rootPitch = hang - 0.12 * swing
	local waistPitch = -0.05
	local dangle = math.sin(c.T * 3) * 0.08
	return {
		Root = A(rootPitch),
		Waist = A(waistPitch, 0.18, 0),
		Neck = A(-0.25 - hang * 0.5, -0.1, 0),
		RightShoulder = A(reach - rootPitch - waistPitch, 0, 0.12),
		RightElbow = A(0.06),
		RightWrist = A(-0.1),
		LeftShoulder = A(0.35 - 0.45 * swing, 0, -0.75),
		LeftElbow = A(0.65),
		LeftHip = A(0.45 - 0.45 * swing + dangle),
		LeftKnee = A(-0.75 - 0.25 * math.max(0, swing)),
		LeftAnkle = A(-0.2),
		RightHip = A(0.1 - 0.6 * swing - dangle),
		RightKnee = A(-0.35 - 0.3 * math.max(0, -swing)),
		RightAnkle = A(-0.25),
	}
end

function POSES.Dash(_c)
	return {
		Root = CFrame.new(0, 0.25, 0) * A(-1.2),
		Waist = A(0.12),
		Neck = A(0.85),
		RightShoulder = A(2.85, 0, 0.12),
		RightElbow = A(0.1),
		LeftShoulder = A(-0.35, 0, -0.3),
		LeftElbow = A(0.3),
		LeftHip = A(0.05),
		LeftKnee = A(-0.15),
		LeftAnkle = A(-0.5),
		RightHip = A(0.3),
		RightKnee = A(-0.9),
		RightAnkle = A(-0.4),
	}
end

function POSES.Stunned(c)
	local t = c.T
	local wob = t * 5.5
	return {
		Root = CFrame.new(math.sin(t * 38) * 0.04, -0.35, 0) * A(0.1 + math.sin(wob) * 0.07, 0, math.cos(wob) * 0.09),
		Waist = A(0.12, 0, math.sin(wob + 1) * 0.1),
		Neck = A(0.22 + math.sin(wob) * 0.18, math.cos(wob) * 0.35, math.sin(wob) * 0.18),
		LeftShoulder = A(-0.1, 0, -0.28 - math.sin(t * 3) * 0.1),
		RightShoulder = A(-0.1, 0, 0.28 + math.sin(t * 3 + 1) * 0.1),
		LeftElbow = A(0.35),
		RightElbow = A(0.35),
		LeftHip = A(0.35, 0, -0.06),
		RightHip = A(0.3, 0, 0.06),
		LeftKnee = A(-0.6),
		RightKnee = A(-0.55),
		LeftAnkle = A(0.25),
		RightAnkle = A(0.25),
	}
end

function POSES.Frozen(c)
	-- Startpose ("auf die Plätze") mit leichtem Atmen
	local breath = math.sin((c.T + c.Seed) * 2.6) * 0.02
	return {
		Root = CFrame.new(0, -0.5 + breath, 0) * A(-0.38 + breath),
		Waist = A(-0.05),
		Neck = A(0.3),
		LeftHip = A(0.75),
		LeftKnee = A(-1.05),
		LeftAnkle = A(0.3),
		RightHip = A(-0.15),
		RightKnee = A(-0.55),
		RightAnkle = A(-0.1),
		LeftShoulder = A(-0.55, 0, -0.1),
		LeftElbow = A(0.75),
		RightShoulder = A(0.7, 0, 0.1),
		RightElbow = A(0.7),
	}
end

local EMOTES = {}

function EMOTES.Wave(t)
	local wave = math.sin(t * 9)
	return {
		Root = A(0, 0, math.sin(t * 2) * 0.03),
		Waist = A(0, -0.15, 0.05),
		Neck = A(-0.05, -0.25, wave * 0.04),
		RightShoulder = A(0.2, 0, 2.6 + wave * 0.3),
		RightElbow = A(0, 0, 0.3 + wave * 0.15),
		LeftShoulder = A(0, 0, -0.12),
		LeftElbow = A(0.2),
	}
end

function EMOTES.Dance(t)
	local s = math.sin(t * 6)
	return {
		Root = CFrame.new(0, math.abs(s) * 0.3, 0) * A(0, math.sin(t * 3) * 0.4, 0),
		Waist = A(0, 0, s * 0.15),
		Neck = A(0, 0, -s * 0.12),
		LeftShoulder = A(0, 0, -(1.2 + s * 0.8)),
		RightShoulder = A(0, 0, 1.2 - s * 0.8),
		LeftElbow = A(0.4),
		RightElbow = A(0.4),
		LeftHip = A(math.max(0, s) * 0.5),
		RightHip = A(math.max(0, -s) * 0.5),
		LeftKnee = A(-math.max(0, s) * 0.8),
		RightKnee = A(-math.max(0, -s) * 0.8),
	}
end

function EMOTES.Flex(t)
	local pump = math.sin(t * 5) * 0.1
	return {
		Root = CFrame.new(0, -0.2, 0),
		Waist = A(-0.05 - pump * 0.3),
		Neck = A(-0.12),
		LeftShoulder = A(0, 0, -1.5 - pump),
		RightShoulder = A(0, 0, 1.5 + pump),
		LeftElbow = A(0, 0, -1.64),
		RightElbow = A(0, 0, 1.64),
		LeftHip = A(0, 0, -0.15),
		RightHip = A(0, 0, 0.15),
		LeftKnee = A(-0.2),
		RightKnee = A(-0.2),
	}
end

function EMOTES.Spin(t)
	return {
		Root = CFrame.new(0, math.abs(math.sin(t * 5)) * 0.2, 0) * A(0, (t * 10) % TAU, 0),
		LeftShoulder = A(0, 0, -1.4),
		RightShoulder = A(0, 0, 1.4),
		LeftHip = A(0, 0, -0.1),
		RightHip = A(0.4, 0, 0.1),
		RightKnee = A(-0.9),
	}
end

function EMOTES.Salute(t)
	return {
		Root = A(0.03),
		RightShoulder = A(2.1, 0, 0.6),
		RightElbow = A(2.0),
		Neck = A(-0.05 + math.sin(t * 2) * 0.02),
		LeftShoulder = A(0, 0, -0.05),
	}
end

local function victoryPose(t)
	local hop = math.abs(math.sin(t * 5))
	local pump = math.sin(t * 10) * 0.22
	return {
		Root = CFrame.new(0, hop * 0.75, 0) * A(-0.05 + hop * 0.05, math.sin(t * 1.6) * 0.35, 0),
		Waist = A(0.08, 0, math.sin(t * 5) * 0.06),
		Neck = A(-0.3),
		LeftShoulder = A(0.15, 0, -2.6 - pump),
		RightShoulder = A(0.15, 0, 2.6 + pump),
		LeftElbow = A(0.25 + pump),
		RightElbow = A(0.25 - pump),
		LeftHip = A(0.45 * hop, 0, -0.08),
		RightHip = A(0.3 * hop, 0, 0.08),
		LeftKnee = A(-0.85 * hop - 0.05),
		RightKnee = A(-0.6 * hop - 0.05),
	}
end

local function emoteDuration(id: string): number
	local def = CosmeticDefinitions.Get("Emotes", id)
	return def and def.Duration or 2.5
end

--- Landungs-Kurve: schnelles Einknicken, danach weiches Abklingen (0..1).
local function dipCurve(age: number): number
	if age < 0.05 then
		return age / 0.05
	end
	return math.exp(-(age - 0.05) * 9)
end

local function easeInOut(t: number): number
	return t * t * (3 - 2 * t)
end

------------------------------------------------------------------------
-- Controller
------------------------------------------------------------------------

function AnimationController:Init(ctx)
	self.Ctx = ctx
	self.Rigs = setmetatable({}, { __mode = "k" })
	self.Previews = {}
end

function AnimationController:Start()
	RunService.PreSimulation:Connect(function(dt)
		local ok, err = pcall(self._step, self, dt)
		if not ok then
			warn("[AnimationController] " .. tostring(err))
		end
	end)
end

function AnimationController:RegisterPreview(model: Model, getPose: () -> string?)
	self.Previews[model] = getPose
end

function AnimationController:UnregisterPreview(model: Model)
	self.Previews[model] = nil
	self.Rigs[model] = nil
end

function AnimationController:_rig(model: Model)
	local rig = self.Rigs[model]
	if rig and rig.Motors.Root and rig.Motors.Root.Parent then
		return rig
	end
	local motors = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Motor6D") then
			motors[descendant.Name] = descendant
		end
	end
	if not motors.Root then
		return nil
	end
	rig = {
		Motors = motors,
		Current = {},
		Phase = 0,
		Seed = math.random() * 100,
		State = "Idle",
		Velocity = Vector3.zero,
		PrevSpeed = 0,
		Accel = 0,
		MinVy = 0,
		LandAt = -math.huge,
		LandAmount = 0,
		FlipAt = -math.huge,
		TurnAt = -math.huge,
		TurnFrom = 0,
		LookSign = 0,
		Ctx = {},
	}
	self.Rigs[model] = rig
	return rig
end

--- Überblendet zur Zielpose und addiert die Zusatzschichten (Landung, Salto, Drehung).
function AnimationController:_apply(rig, pose, dt: number, rate: number, t: number)
	local alpha = 1 - math.exp(-rate * dt)

	local dip = 0
	local landAge = t - rig.LandAt
	if landAge < 0.6 then
		dip = dipCurve(landAge) * rig.LandAmount
	end
	local flip, tuck = 0, 0
	local flipAge = t - rig.FlipAt
	if flipAge < FLIP_TIME then
		local u = flipAge / FLIP_TIME
		flip = easeInOut(u) * TAU
		tuck = math.sin(u * math.pi)
	end
	local turn = 0
	local turnAge = t - rig.TurnAt
	if turnAge < TURN_TIME then
		local u = turnAge / TURN_TIME
		turn = rig.TurnFrom * (1 - u) * (1 - u)
	end
	local layered = dip > 0.001 or flip > 0 or turn ~= 0

	for _, name in RunnerRig.Joints do
		local motor = rig.Motors[name]
		if motor then
			local target = pose[name] or CFrame.identity
			local current = (rig.Current[name] or CFrame.identity):Lerp(target, alpha)
			rig.Current[name] = current
			if layered then
				if name == "Root" then
					current = CFrame.new(0, -0.55 * dip, 0) * A(-flip, turn, 0) * current * A(-0.2 * dip)
				elseif name == "LeftHip" or name == "RightHip" then
					current *= A(0.45 * dip + 0.9 * tuck)
				elseif name == "LeftKnee" or name == "RightKnee" then
					current *= A(-(0.85 * dip + 1.4 * tuck))
				elseif name == "LeftAnkle" or name == "RightAnkle" then
					current *= A(0.35 * dip)
				elseif name == "LeftShoulder" or name == "RightShoulder" then
					current *= A(0.25 * dip + 0.8 * tuck)
				elseif name == "LeftElbow" or name == "RightElbow" then
					current *= A(0.6 * tuck)
				elseif name == "Neck" then
					current *= A(0.1 * dip)
				end
			end
			motor.Transform = current
		end
	end
end

--- Erkennt Zustandswechsel (Landung, Salto-Auslöser) und Richtungswechsel.
function AnimationController:_track(rig, state: string, velocity: Vector3, root: BasePart, t: number, isLocal: boolean)
	local previous = rig.State
	if AIRBORNE[state] then
		rig.MinVy = math.min(rig.MinVy, velocity.Y)
	end
	if state ~= previous then
		if AIRBORNE[previous] and GROUNDED[state] then
			local impact = -rig.MinVy
			if impact > 12 then
				rig.LandAt = t
				rig.LandAmount = clamp((impact - 10) / 110, 0.15, 1)
			end
		end
		if state == "Air" then
			local vy = velocity.Y
			if
				(previous == "Wall" and vy > 25)
				or (previous == "Grapple" and vy > 30)
				or (GROUNDED[previous] and vy > Config.Movement.JumpVelocity * 1.25)
			then
				rig.FlipAt = t
			end
		elseif rig.FlipAt > t - FLIP_TIME then
			-- Salto abbrechen, sobald die Figur nicht mehr in der Luft ist. Der aktuelle
			-- Drehwinkel wird in die Root-Pose übernommen, damit die Figur sich weich
			-- aufrichtet statt zu springen.
			local flip = easeInOut(math.clamp((t - rig.FlipAt) / FLIP_TIME, 0, 1)) * TAU
			rig.Current.Root = A(-flip) * (rig.Current.Root or CFrame.identity)
			rig.FlipAt = -math.huge
		end
		if not AIRBORNE[state] then
			rig.MinVy = 0
		end
		rig.State = state
	end

	-- Weiche Drehung nur lokal: die eigene Figur wird von AlignOrientation hart gedreht,
	-- andere Figuren interpoliert Roblox bereits selbst.
	if isLocal then
		local lookX = root.CFrame.LookVector.X
		local sign = if lookX >= 0 then 1 else -1
		if rig.LookSign ~= 0 and sign ~= rig.LookSign and math.abs(lookX) > 0.5 then
			rig.TurnAt = t
			rig.TurnFrom = -sign * math.pi
		end
		if math.abs(lookX) > 0.5 then
			rig.LookSign = sign
		end
	end
end

function AnimationController:_reach(character: Model, root: BasePart, isLocal: boolean): number
	local anchor
	if isLocal then
		anchor = self.Ctx.MovementController:GetGrappleAnchor()
	elseif character:GetAttribute("Grappling") then
		anchor = character:GetAttribute("GrappleTarget")
	end
	if typeof(anchor) ~= "Vector3" then
		return 2.7
	end
	local facing = if root.CFrame.LookVector.X >= 0 then 1 else -1
	local d = anchor - (root.Position + Vector3.new(0, 1.5, 0))
	local reach = math.atan2(d.X * facing, -d.Y)
	if reach < 0 then
		reach += TAU
	end
	return reach
end

function AnimationController:_poseFor(character: Model, state: string, velocity: Vector3, rig, t: number, dt: number, facing: number, reach: number)
	local serverNow = workspace:GetServerTimeNow()
	local speed = math.abs(velocity.X)
	if state == "Run" then
		rig.Phase = (rig.Phase + dt * (4 + math.min(speed, 80) * 0.32)) % (TAU * 64)
	end
	local rawAccel = clamp((speed - rig.PrevSpeed) / math.max(dt, 1 / 240), -400, 400)
	rig.Accel += (rawAccel - rig.Accel) * (1 - math.exp(-8 * dt))
	rig.PrevSpeed = speed

	local victory = character:GetAttribute("Victory")
	if type(victory) == "string" and victory ~= "" then
		return victoryPose(t), BLEND.Victory
	end
	local emote = character:GetAttribute("Emote")
	if type(emote) == "string" and emote ~= "" and (state == "Idle" or state == "Frozen") then
		local startedAt = character:GetAttribute("EmoteAt") or 0
		local fn = EMOTES[emote]
		if fn and serverNow - startedAt < emoteDuration(emote) then
			return fn(serverNow - startedAt), BLEND.Emote
		end
	end
	if (character:GetAttribute("StunnedUntil") or 0) > serverNow then
		state = "Stunned"
	end
	if state == "Run" and speed < 2 then
		state = "Idle"
	end
	local fn = POSES[state] or POSES.Idle

	local c = rig.Ctx
	c.T = t
	c.Seed = rig.Seed
	c.Speed = speed
	c.Forward = velocity.X * facing
	c.Vy = velocity.Y
	c.Phase = rig.Phase
	c.Accel = rig.Accel
	c.Reach = reach
	return fn(c), BLEND[state] or 12
end

function AnimationController:_step(dt: number)
	local camera = workspace.CurrentCamera
	local cameraPosition = if camera then camera.CFrame.Position else Vector3.zero
	local t = os.clock()
	local movement = self.Ctx.MovementController

	for _, other in Players:GetPlayers() do
		local character = other.Character
		if character and character.Parent then
			local root = character:FindFirstChild("HumanoidRootPart")
			if root and (root.Position - cameraPosition).Magnitude < ANIMATE_DISTANCE then
				local rig = self:_rig(character)
				if rig then
					local isLocal = other == player
					local state, velocity, facing
					if isLocal then
						state = movement:GetState()
						velocity = movement.Velocity or root.AssemblyLinearVelocity
						facing = movement:GetFacing()
					else
						state = character:GetAttribute("MoveState") or "Idle"
						facing = character:GetAttribute("Facing") or 1
						if character:GetAttribute("Frozen") then
							state = "Frozen"
						end
						-- Replizierte Geschwindigkeit glätten (Netzwerk-Rauschen)
						rig.Velocity = rig.Velocity:Lerp(root.AssemblyLinearVelocity, 1 - math.exp(-14 * dt))
						velocity = rig.Velocity
					end
					self:_track(rig, state, velocity, root, t, isLocal)
					local reach = if state == "Grapple" then self:_reach(character, root, isLocal) else 2.7
					local pose, rate = self:_poseFor(character, state, velocity, rig, t, dt, facing, reach)
					self:_apply(rig, pose, dt, rate, t)
				end
			end
		end
	end

	for model, getPose in self.Previews do
		if model.Parent then
			local rig = self:_rig(model)
			if rig then
				local mode = getPose() or "Idle"
				local pose
				if EMOTES[mode] then
					pose = EMOTES[mode](t)
				elseif mode == "Victory" then
					pose = victoryPose(t)
				else
					local c = rig.Ctx
					c.T = t
					c.Seed = rig.Seed
					c.Speed = 30
					c.Forward = 30
					c.Vy = 0
					c.Phase = t * 12
					c.Accel = 0
					c.Reach = 2.7
					pose = (POSES[mode] or POSES.Idle)(c)
				end
				self:_apply(rig, pose, dt, 12, t)
			end
		else
			self.Previews[model] = nil
		end
	end
end

return AnimationController
