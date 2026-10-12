--[[
	CameraController  (ModuleScript)
	Pfad: StarterPlayer/StarterPlayerScripts/Client/Controllers/CameraController

	Seitliche 2.5D-Kamera (Scriptable):
		- Blick entlang -Z auf die Spielebene (Z = 0), leicht von oben
		- Look-Ahead in Bewegungsrichtung (geglättet)
		- vertikale Totzone gegen Ruckeln bei Sprüngen, schnelles Nachführen beim Fallen
		- Zoom und Sichtfeld wachsen mit der Geschwindigkeit
		- im Rennen leichter Versatz Richtung Führendem, damit er sichtbar bleibt
		- Zuschauermodus (anderen Spieler verfolgen)
		- Kamerawackeln (abschaltbar in den Einstellungen)

	API:
		:Shake(intensity)
		:SetSpectate(player?)
		:GetSpectate() -> Player?
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)

local CAM = Config.Camera
local player = Players.LocalPlayer

local CameraController = {}

function CameraController:Init(ctx)
	self.Ctx = ctx
	self.ShakeAmount = 0
	self.Spectate = nil
	self.Focus = nil
	self.FocusY = 0
	self.LookAhead = 0
	self.Distance = CAM.Distance
end

function CameraController:Start()
	RunService:BindToRenderStep("VR_Camera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		self:_update(dt)
	end)
	self.Ctx.ClientState:On("Teleported", function()
		self.Focus = nil
	end)
end

function CameraController:Shake(intensity: number)
	if self.Ctx.ClientState:GetSetting("CameraShake") == false then
		return
	end
	self.ShakeAmount = math.max(self.ShakeAmount, intensity)
end

function CameraController:SetSpectate(target: Player?)
	if target == player then
		target = nil
	end
	self.Spectate = target
	self.Focus = nil
end

function CameraController:GetSpectate(): Player?
	return self.Spectate
end

function CameraController:_targetRoot(): BasePart?
	local target = self.Spectate
	if target and target.Parent and target.Character then
		local root = target.Character:FindFirstChild("HumanoidRootPart")
		if root then
			return root
		end
	end
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") or nil
end

function CameraController:_leaderBias(position: Vector3): number
	local state = self.Ctx.ClientState
	if self.Spectate or not state:IsInRace() or state:GetPhase() ~= "Racing" then
		return 0
	end
	for _, folder in state.Racers:GetChildren() do
		if folder:GetAttribute("Placement") == 1 and folder:GetAttribute("Status") == "Racing" then
			local leader = Players:GetPlayerByUserId(folder:GetAttribute("UserId") or 0)
			if leader and leader ~= player and leader.Character then
				local root = leader.Character:FindFirstChild("HumanoidRootPart")
				if root then
					local ahead = root.Position.X - position.X
					if ahead > 0 and ahead < 90 then
						return math.clamp(ahead * CAM.LeaderBias, 0, CAM.MaxLeaderBias)
					end
				end
			end
			break
		end
	end
	return 0
end

function CameraController:_update(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	local root = self:_targetRoot()
	if not root then
		return
	end
	local position = root.Position
	local velocity = root.AssemblyLinearVelocity
	local movement = self.Ctx.MovementController
	if not self.Spectate and movement.Velocity then
		velocity = movement.Velocity
	end

	if not self.Focus or math.abs(position.X - self.Focus.X) > CAM.SnapDistance or math.abs(position.Y - self.FocusY) > CAM.SnapDistance then
		self.FocusY = position.Y
		self.LookAhead = 0
		self.Focus = Vector3.new(position.X, position.Y + CAM.FocusHeight, 0)
	end

	local desiredLook = math.clamp(velocity.X * CAM.LookAheadFactor, -CAM.MaxLookAhead, CAM.MaxLookAhead)
	desiredLook += self:_leaderBias(position)
	self.LookAhead = Util.Damp(self.LookAhead, desiredLook, 3, dt)

	local dy = position.Y - self.FocusY
	if math.abs(dy) > CAM.VerticalDeadZone then
		self.FocusY = Util.Damp(self.FocusY, position.Y - Util.Sign(dy) * CAM.VerticalDeadZone, CAM.VerticalSharpness, dt)
	end
	if velocity.Y < -60 then
		self.FocusY = Util.Damp(self.FocusY, position.Y, 10, dt)
	end

	local focusX = Util.Damp(self.Focus.X, position.X + self.LookAhead, CAM.FollowSharpness, dt)
	local focus = Vector3.new(focusX, self.FocusY + CAM.FocusHeight, Config.World.PlaneZ)
	self.Focus = focus

	local speed = math.abs(velocity.X)
	local extra = math.clamp((speed - Config.Movement.MaxRunSpeed) * CAM.SpeedZoom, 0, CAM.MaxExtraDistance)
	self.Distance = Util.Damp(self.Distance, CAM.Distance + extra, 2, dt)

	local shake = Vector3.zero
	if self.ShakeAmount > 0 then
		self.ShakeAmount = math.max(0, self.ShakeAmount - dt * 2.5)
		local strength = self.ShakeAmount * self.ShakeAmount * 1.4
		shake = Vector3.new((math.random() - 0.5) * strength, (math.random() - 0.5) * strength, 0)
	end

	local cameraPosition = focus + Vector3.new(0, CAM.HeightOffset, self.Distance) + shake
	camera.CFrame = CFrame.lookAt(cameraPosition, focus + shake * 0.5)
	local targetFov = CAM.FieldOfView + math.clamp((speed - Config.Movement.MaxRunSpeed) * 0.12, 0, 10)
	camera.FieldOfView = Util.Damp(camera.FieldOfView, targetFov, 4, dt)
end

return CameraController
