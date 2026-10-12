--[[
	AnimationController  (ModuleScript)
	Pfad: StarterPlayer/StarterPlayerScripts/Client/Controllers/AnimationController

	Prozedurale Animationen ohne externe Animations-Assets. Jeder Client
	animiert ALLE Spielfiguren selbst, indem er Motor6D.Transform in
	RunService.PreSimulation setzt (offiziell empfohlener Zeitpunkt).

	Datenquellen:
		Lokale Figur: MovementController (sofort, ohne Latenz)
		Andere Figuren: Character-Attribut "MoveState" (vom Server repliziert)
		                und die replizierte Geschwindigkeit des Root-Parts
	Posen: Idle, Run, Air, Slide, Wall, Grapple, Dash, Stunned, Frozen (Startpose),
	       Emotes (Wave, Dance, Flex, Spin, Salute) und Siegesjubel.
	Übergänge werden pro Gelenk weich überblendet.

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
local RunnerRig = require(Shared.RunnerRig)
local CosmeticDefinitions = require(Shared.CosmeticDefinitions)

local player = Players.LocalPlayer

local AnimationController = {}

local function A(x: number, y: number?, z: number?): CFrame
	return CFrame.Angles(x, y or 0, z or 0)
end

local POSES = {}

function POSES.Idle(t, _speed, _vy)
	local b = math.sin(t * 2.2) * 0.03
	return {
		Root = CFrame.new(0, b * 0.5, 0),
		Waist = A(b),
		LeftShoulder = A(0, 0, -0.08),
		RightShoulder = A(0, 0, 0.08),
		LeftElbow = A(0.15),
		RightElbow = A(0.15),
	}
end

function POSES.Run(_t, speed, _vy, phase)
	local k = math.clamp(speed / 44, 0.25, 1.3)
	local s, c = math.sin(phase), math.cos(phase)
	return {
		Root = CFrame.new(0, math.abs(c) * 0.18 * k - 0.05, 0) * A(-0.22 * k),
		Waist = A(-0.05 * k, s * 0.12 * k, 0),
		Neck = A(0.15 * k),
		LeftHip = A(s * 0.95 * k),
		RightHip = A(-s * 0.95 * k),
		LeftKnee = A(-(0.25 + 0.9 * math.max(0, c)) * k),
		RightKnee = A(-(0.25 + 0.9 * math.max(0, -c)) * k),
		LeftAnkle = A(0.2 * s * k),
		RightAnkle = A(-0.2 * s * k),
		LeftShoulder = A(-s * 0.9 * k, 0, -0.1),
		RightShoulder = A(s * 0.9 * k, 0, 0.1),
		LeftElbow = A(0.5 + 0.4 * k),
		RightElbow = A(0.5 + 0.4 * k),
	}
end

function POSES.Air(_t, _speed, vy)
	local rising = vy > 0
	return {
		Root = A(if rising then -0.12 else 0.06),
		LeftHip = A(0.7),
		LeftKnee = A(-1.0),
		RightHip = A(-0.35),
		RightKnee = A(-0.5),
		LeftShoulder = A(0.4, 0, -0.5),
		RightShoulder = A(-0.3, 0, 0.6),
		LeftElbow = A(0.6),
		RightElbow = A(0.5),
	}
end

function POSES.Slide()
	return {
		Root = CFrame.new(0, -1.65, 0.3) * A(1.15),
		Waist = A(-0.25),
		Neck = A(-0.55),
		LeftHip = A(0.15),
		LeftKnee = A(-0.2),
		RightHip = A(0.55),
		RightKnee = A(-1.3),
		LeftShoulder = A(-0.6, 0, -0.5),
		RightShoulder = A(-0.9, 0, 0.4),
		LeftElbow = A(0.4),
		RightElbow = A(0.3),
	}
end

function POSES.Wall()
	return {
		Root = A(0.1),
		LeftShoulder = A(1.6, 0, -0.2),
		RightShoulder = A(1.3, 0, 0.2),
		LeftElbow = A(0.3),
		RightElbow = A(0.5),
		LeftHip = A(0.5),
		LeftKnee = A(-0.8),
		RightHip = A(0.1),
		RightKnee = A(-0.4),
	}
end

function POSES.Grapple(_t, speed, _vy, _phase, signedSpeed)
	local tilt = math.clamp((signedSpeed or speed) / 80, -0.4, 0.6)
	return {
		Root = A(-tilt),
		RightShoulder = A(2.7, 0, 0.15),
		RightElbow = A(0.1),
		LeftShoulder = A(0.2, 0, -0.5),
		LeftElbow = A(0.6),
		LeftHip = A(0.45),
		LeftKnee = A(-0.7),
		RightHip = A(0.2),
		RightKnee = A(-0.4),
	}
end

function POSES.Dash()
	return {
		Root = A(-0.65),
		LeftShoulder = A(-1.0, 0, -0.3),
		RightShoulder = A(-1.0, 0, 0.3),
		LeftHip = A(-0.3),
		RightHip = A(0.4),
		RightKnee = A(-0.9),
	}
end

function POSES.Stunned(t)
	local shake = math.sin(t * 40) * 0.06
	return {
		Root = CFrame.new(shake, -0.2, 0) * A(0.15),
		Neck = A(0.3, math.sin(t * 6) * 0.4, 0),
		LeftShoulder = A(0, 0, -0.4),
		RightShoulder = A(0, 0, 0.4),
		LeftKnee = A(-0.4),
		RightKnee = A(-0.4),
	}
end

function POSES.Frozen()
	-- Startpose ("auf die Plätze")
	return {
		Root = CFrame.new(0, -0.45, 0) * A(-0.35),
		LeftHip = A(0.7),
		LeftKnee = A(-1.0),
		RightHip = A(-0.2),
		RightKnee = A(-0.5),
		LeftShoulder = A(-0.5, 0, -0.1),
		RightShoulder = A(0.6, 0, 0.1),
		LeftElbow = A(0.6),
		RightElbow = A(0.6),
	}
end

local EMOTES = {}

function EMOTES.Wave(t)
	return {
		RightShoulder = A(0.2, 0, 2.6 + math.sin(t * 9) * 0.3),
		RightElbow = A(0, 0, 0.3),
		LeftShoulder = A(0, 0, -0.1),
	}
end

function EMOTES.Dance(t)
	local s = math.sin(t * 6)
	return {
		Root = CFrame.new(0, math.abs(s) * 0.3, 0) * A(0, math.sin(t * 3) * 0.4, 0),
		Waist = A(0, 0, s * 0.15),
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
		LeftShoulder = A(0, 0, -1.5 - pump),
		RightShoulder = A(0, 0, 1.5 + pump),
		LeftElbow = A(0, 0, -1.64),
		RightElbow = A(0, 0, 1.64),
		LeftHip = A(0, 0, -0.15),
		RightHip = A(0, 0, 0.15),
	}
end

function EMOTES.Spin(t)
	return {
		Root = A(0, (t * 10) % (math.pi * 2), 0),
		LeftShoulder = A(0, 0, -1.4),
		RightShoulder = A(0, 0, 1.4),
	}
end

function EMOTES.Salute()
	return {
		RightShoulder = A(2.1, 0, 0.6),
		RightElbow = A(2.0),
		Neck = A(-0.05),
	}
end

local function victoryPose(t)
	return {
		Root = CFrame.new(0, math.abs(math.sin(t * 5)) * 0.6, 0),
		LeftShoulder = A(0, 0, -2.8),
		RightShoulder = A(0, 0, 2.8),
		LeftElbow = A(0.3),
		RightElbow = A(0.3),
		Neck = A(-0.25),
	}
end

local function emoteDuration(id: string): number
	local def = CosmeticDefinitions.Get("Emotes", id)
	return def and def.Duration or 2.5
end

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
	rig = { Motors = motors, Current = {}, Phase = 0 }
	self.Rigs[model] = rig
	return rig
end

function AnimationController:_apply(rig, pose, dt: number)
	local alpha = 1 - math.exp(-16 * dt)
	for _, name in RunnerRig.Joints do
		local motor = rig.Motors[name]
		if motor then
			local target = pose[name] or CFrame.identity
			local current = (rig.Current[name] or CFrame.identity):Lerp(target, alpha)
			rig.Current[name] = current
			motor.Transform = current
		end
	end
end

function AnimationController:_poseFor(character: Model, state: string, velocity: Vector3, rig, t: number, dt: number, facing: number)
	local serverNow = workspace:GetServerTimeNow()
	local speed = math.abs(velocity.X)
	rig.Phase += dt * (2 + speed * 0.38)

	local victory = character:GetAttribute("Victory")
	if type(victory) == "string" and victory ~= "" then
		return victoryPose(t)
	end
	local emote = character:GetAttribute("Emote")
	if type(emote) == "string" and emote ~= "" and (state == "Idle" or state == "Frozen") then
		local startedAt = character:GetAttribute("EmoteAt") or 0
		local fn = EMOTES[emote]
		if fn and serverNow - startedAt < emoteDuration(emote) then
			return fn(serverNow - startedAt)
		end
	end
	if (character:GetAttribute("StunnedUntil") or 0) > serverNow then
		return POSES.Stunned(t)
	end
	local fn = POSES[state] or POSES.Idle
	if state == "Run" and speed < 2 then
		fn = POSES.Idle
	end
	return fn(t, speed, velocity.Y, rig.Phase, velocity.X * facing)
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
			if root and (root.Position - cameraPosition).Magnitude < 320 then
				local rig = self:_rig(character)
				if rig then
					local state, velocity, facing
					if other == player then
						state = movement:GetState()
						velocity = movement.Velocity or root.AssemblyLinearVelocity
						facing = movement:GetFacing()
					else
						state = character:GetAttribute("MoveState") or "Idle"
						velocity = root.AssemblyLinearVelocity
						facing = character:GetAttribute("Facing") or 1
						if character:GetAttribute("Frozen") then
							state = "Frozen"
						end
					end
					self:_apply(rig, self:_poseFor(character, state, velocity, rig, t, dt, facing), dt)
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
					pose = (POSES[mode] or POSES.Idle)(t, 30, 0, t * 12, 30)
				end
				self:_apply(rig, pose, dt)
			end
		else
			self.Previews[model] = nil
		end
	end
end

return AnimationController
