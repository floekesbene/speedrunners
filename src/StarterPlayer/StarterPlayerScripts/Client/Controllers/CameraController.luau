--[[
	CameraController  (ModuleScript)
	Pfad: StarterPlayer/StarterPlayerScripts/Client/Controllers/CameraController

	Seitliche 2.5D-Kamera (Scriptable):
		- Blick entlang -Z auf die Spielebene (Z = 0), leicht von oben
		- nah an der Figur (Config.Camera.Distance), damit Läufer gut erkennbar sind
		- kritisch gedämpfte Federn (SmoothDamp) statt hartem Nachziehen:
		  weiche, ruckelfreie Verfolgung ohne Überschwingen
		- Look-Ahead in Bewegungsrichtung (geglättet)
		- vertikale Totzone gegen Ruckeln bei Sprüngen, langsames Zentrieren am
		  Boden, schnelles Nachführen und leichter Blick nach unten beim Fallen
		- Zoom und Sichtfeld wachsen sanft mit der Geschwindigkeit
		- im Rennen leichter Versatz Richtung Führendem, damit er sichtbar bleibt
		- Zuschauermodus (anderen Spieler verfolgen) mit weichem Kameraschwenk
		- Kamerawackeln mit Rauschfunktion (organisch statt Zufallszittern),
		  Kamera-Stöße (Feder, z.B. bei Landungen) und Sichtfeld-Impulse
		  (Dash/Boost) – alles abschaltbar über die Einstellung "CameraShake"

	API:
		:Shake(intensity)
		:Kick(impulse: Vector3)        Stoß in die Kamerafeder (Studs/s)
		:PunchFov(amount)              kurzzeitig größeres Sichtfeld (Grad)
		:SetSpectate(player?)
		:GetSpectate() -> Player?
		:GetFocusDistance() -> number  aktueller Abstand Kamera → Fokuspunkt
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

--- Kritisch gedämpfte Feder (wie Unity SmoothDamp). Gibt (Wert, Geschwindigkeit) zurück.
local function smoothDamp(current: number, target: number, velocity: number, smoothTime: number, dt: number): (number, number)
	local omega = 2 / math.max(smoothTime, 0.0001)
	local x = omega * dt
	local decay = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
	local change = current - target
	local temp = (velocity + omega * change) * dt
	return target + (change + temp) * decay, (velocity - omega * temp) * decay
end

local function easeInOut(t: number): number
	return t * t * (3 - 2 * t)
end

function CameraController:Init(ctx)
	self.Ctx = ctx
	self.ShakeAmount = 0
	self.Spectate = nil
	self.Focus = nil
	self.FocusX = 0
	self.FocusXVel = 0
	self.FocusY = 0
	self.FocusYVel = 0
	self.AnchorY = 0
	self.LookAhead = 0
	self.LookAheadVel = 0
	self.LookDown = 0
	self.Distance = CAM.Distance
	self.Fov = CAM.FieldOfView
	self.FovPunch = 0
	self.KickOffset = Vector3.zero
	self.KickVelocity = Vector3.zero
	self.Blend = nil
	self.LastCFrame = nil
end

function CameraController:Start()
	RunService:BindToRenderStep("VR_Camera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		local ok, err = pcall(self._update, self, dt)
		if not ok then
			warn("[CameraController] " .. tostring(err))
		end
	end)
	self.Ctx.ClientState:On("Teleported", function()
		self.Focus = nil
		self.Blend = nil
	end)
end

function CameraController:_motionAllowed(): boolean
	return self.Ctx.ClientState:GetSetting("CameraShake") ~= false
end

function CameraController:Shake(intensity: number)
	if not self:_motionAllowed() then
		return
	end
	self.ShakeAmount = math.max(self.ShakeAmount, intensity)
end

--- Stößt die Kamerafeder an (z.B. nach unten bei einer harten Landung).
function CameraController:Kick(impulse: Vector3)
	if not self:_motionAllowed() then
		return
	end
	self.KickVelocity += impulse
end

--- Kurzer Sichtfeld-Impuls (z.B. Dash, Boost-Pad).
function CameraController:PunchFov(amount: number)
	if not self:_motionAllowed() then
		return
	end
	self.FovPunch = math.clamp(self.FovPunch + amount, -CAM.MaxFovPunch, CAM.MaxFovPunch)
end

function CameraController:SetSpectate(target: Player?)
	if target == player then
		target = nil
	end
	if target == self.Spectate then
		return
	end
	self.Spectate = target
	self.Focus = nil
	-- Weicher Schwenk vom bisherigen Bild zum neuen Ziel
	if self.LastCFrame then
		self.Blend = { From = self.LastCFrame, Start = os.clock() }
	end
end

function CameraController:GetSpectate(): Player?
	return self.Spectate
end

function CameraController:GetFocusDistance(): number
	return math.sqrt(self.Distance * self.Distance + CAM.HeightOffset * CAM.HeightOffset)
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

function CameraController:_update(rawDt: number)
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
	-- Große Bildzeit-Sprünge (Ruckler) nicht in die Federn übernehmen
	local dt = math.min(rawDt, 1 / 20)
	local position = root.Position
	local velocity = root.AssemblyLinearVelocity
	local movement = self.Ctx.MovementController
	if not self.Spectate and movement.Velocity then
		velocity = movement.Velocity
	end

	if
		not self.Focus
		or math.abs(position.X - self.FocusX) > CAM.SnapDistance
		or math.abs(position.Y - self.FocusY) > CAM.SnapDistance
	then
		self.Focus = true
		self.FocusX = position.X
		self.FocusXVel = 0
		self.FocusY = position.Y
		self.FocusYVel = 0
		self.AnchorY = position.Y
		self.LookAhead = 0
		self.LookAheadVel = 0
		self.LookDown = 0
	end

	-- Horizontal: Vorausschau + Führenden-Versatz, beides weich gefedert
	local desiredLook = math.clamp(velocity.X * CAM.LookAheadFactor, -CAM.MaxLookAhead, CAM.MaxLookAhead)
	desiredLook += self:_leaderBias(position)
	self.LookAhead, self.LookAheadVel = smoothDamp(self.LookAhead, desiredLook, self.LookAheadVel, CAM.LookAheadSmoothTime, dt)
	self.FocusX, self.FocusXVel = smoothDamp(self.FocusX, position.X + self.LookAhead, self.FocusXVel, CAM.FollowSmoothTime, dt)

	-- Vertikal: Totzone, am Boden langsam zentrieren, beim Fallen schnell folgen
	local dy = position.Y - self.AnchorY
	if math.abs(dy) > CAM.VerticalDeadZone then
		self.AnchorY = position.Y - Util.Sign(dy) * CAM.VerticalDeadZone
	end
	if math.abs(velocity.Y) < 2 then
		self.AnchorY = Util.Damp(self.AnchorY, position.Y, CAM.GroundRecenter, dt)
	end
	local falling = velocity.Y < -60
	if falling then
		self.AnchorY = position.Y
	end
	local verticalTime = if falling then CAM.FallSmoothTime else CAM.VerticalSmoothTime
	self.FocusY, self.FocusYVel = smoothDamp(self.FocusY, self.AnchorY, self.FocusYVel, verticalTime, dt)
	local lookDown = math.clamp((-velocity.Y - 40) * CAM.FallLookDown, 0, CAM.MaxFallLookDown)
	self.LookDown = Util.Damp(self.LookDown, lookDown, 4, dt)

	-- Tempo: sanfter Zoom und Sichtfeld
	local speed = math.abs(velocity.X)
	local over = math.max(0, speed - Config.Movement.MaxRunSpeed)
	self.Distance = Util.Damp(self.Distance, CAM.Distance + math.min(over * CAM.SpeedZoom, CAM.MaxExtraDistance), CAM.ZoomSharpness, dt)
	self.Fov = Util.Damp(self.Fov, CAM.FieldOfView + math.min(over * CAM.SpeedFov, CAM.MaxExtraFov), CAM.FovSharpness, dt)
	self.FovPunch = Util.Damp(self.FovPunch, 0, 5, dt)

	-- Kamera-Stöße: gedämpfte Feder
	local accel = -self.KickOffset * CAM.KickStiffness - self.KickVelocity * CAM.KickDamping
	self.KickVelocity += accel * dt
	self.KickOffset += self.KickVelocity * dt
	if self.KickOffset.Magnitude > 4 then
		self.KickOffset = self.KickOffset.Unit * 4
	end

	-- Wackeln über Rauschfunktion (weich statt zufälligem Zittern)
	local shake = Vector3.zero
	local roll = 0
	if self.ShakeAmount > 0 then
		self.ShakeAmount = math.max(0, self.ShakeAmount - dt * CAM.ShakeDecay)
		local strength = self.ShakeAmount * self.ShakeAmount * 2.4
		local n = os.clock() * CAM.ShakeFrequency
		shake = Vector3.new(math.noise(n, 0.31), math.noise(n, 7.13), 0) * strength
		roll = math.noise(n, 13.7) * strength * 0.025
	end

	local focus = Vector3.new(self.FocusX, self.FocusY + CAM.FocusHeight - self.LookDown, Config.World.PlaneZ)
	local cameraPosition = focus + Vector3.new(0, CAM.HeightOffset, self.Distance) + shake + self.KickOffset
	local cframe = CFrame.lookAt(cameraPosition, focus + shake * 0.5 + self.KickOffset * 0.7)
	if roll ~= 0 then
		cframe *= CFrame.Angles(0, 0, roll)
	end

	-- Zuschauer-Schwenk
	local blend = self.Blend
	if blend then
		local alpha = (os.clock() - blend.Start) / CAM.SpectateBlendTime
		if alpha >= 1 or (blend.From.Position - cframe.Position).Magnitude > CAM.MaxBlendDistance then
			self.Blend = nil
		else
			cframe = blend.From:Lerp(cframe, easeInOut(math.clamp(alpha, 0, 1)))
		end
	end

	camera.CFrame = cframe
	camera.FieldOfView = math.clamp(self.Fov + self.FovPunch, 30, 100)
	self.LastCFrame = cframe
end

return CameraController
