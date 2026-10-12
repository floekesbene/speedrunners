--[[
	MovementController  (ModuleScript)
	Pfad: StarterPlayer/StarterPlayerScripts/Client/Controllers/MovementController

	Eigene Side-Scrolling-Bewegungslogik (ersetzt die Roblox-Standardsteuerung).

	Architektur:
		- Die Spielfigur ist ein physikalischer Körper; nur der unsichtbare
		  "VR_Collider" kollidiert mit der Welt. Der Humanoid ist deaktiviert
		  (EvaluateStateMachine = false bzw. Zustand Physics).
		- Jeden Physik-Schritt (RunService.PreSimulation) wird die aktuelle
		  Geschwindigkeit gelesen, nach unseren Regeln verändert und
		  zurückgeschrieben. Schwerkraft und Kollisionen löst die Roblox-Engine,
		  dadurch bleiben Wände, Decken und Böden exakt.
		- Bewegung findet nur in der X/Y-Ebene statt; Z wird auf 0 gehalten.
		- Der Client besitzt seine Figur (Network Ownership) -> keine Eingabelatenz.
		  Der Server prüft Plausibilität (AntiExploitService, GrappleService).

	Mechaniken:
		Beschleunigung/Verzögerung, Momentum (Übergeschwindigkeit baut sich nur
		langsam ab), Boden-/Luftreibung, variable Sprunghöhe, Coyote-Time,
		Sprungpuffer, Wall-Slide + Wall-Jump, Slide (mit niedrigerem Kollider und
		Kriechen unter Decken), Air-Dash, Greifhaken mit Seilphysik, Boost- und
		Sprungpads, Eis.

	Signale: Jumped(kind), Landed(impactSpeed, position), SlideStarted,
	         DashStarted(dir), GrappleStarted(anchor), GrappleEnded, BoostPad(position),
	         GrappleFailed, StateChanged(state)
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Signal = require(Shared.Signal)
local Remotes = require(Shared.Remotes)

local M = Config.Movement
local G = Config.Grapple
local C = Config.Character

local player = Players.LocalPlayer

local MovementController = {}
MovementController.Jumped = Signal.new()
MovementController.Landed = Signal.new()
MovementController.SlideStarted = Signal.new()
MovementController.DashStarted = Signal.new()
MovementController.GrappleStarted = Signal.new()
MovementController.GrappleEnded = Signal.new()
MovementController.GrappleFailed = Signal.new()
MovementController.BoostPad = Signal.new()
MovementController.StateChanged = Signal.new()

local DISABLED_STATES = {
	Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.Ragdoll,
	Enum.HumanoidStateType.GettingUp,
	Enum.HumanoidStateType.Climbing,
	Enum.HumanoidStateType.Swimming,
	Enum.HumanoidStateType.Seated,
	Enum.HumanoidStateType.Jumping,
	Enum.HumanoidStateType.Freefall,
	Enum.HumanoidStateType.Running,
	Enum.HumanoidStateType.Landed,
	Enum.HumanoidStateType.Flying,
}

local function newState()
	return {
		State = "Idle",
		Facing = 1,
		Grounded = false,
		LastGroundTime = -math.huge,
		LastJumpTime = -math.huge,
		JumpBufferUntil = 0,
		JumpCutPending = false,
		MinAirVy = 0,
		Sliding = false,
		SlideStart = 0,
		SlideCooldownUntil = 0,
		DashUntil = 0,
		DashDir = 1,
		DashEntrySpeed = 0,
		DashCooldownUntil = 0,
		WasDashing = false,
		AirDashAvailable = true,
		WallSliding = false,
		WallJumpLockUntil = 0,
		LockedDir = 0,
		Grapple = nil,
		GrappleCooldownUntil = 0,
		LastPadTime = 0,
		PendingImpulse = 0,
		StreamWaitUntil = 0,
		SentState = "",
		SentFacing = 0,
		LastSent = 0,
		AlignFacing = 0,
	}
end

function MovementController:Init(ctx)
	self.Ctx = ctx
	self.Input = ctx.InputController
	self.S = newState()
	self.Velocity = Vector3.zero
	self.Target = nil
	self.Anchors = {}

	local function addAnchor(part)
		if part:IsA("BasePart") then
			self.Anchors[part] = true
		end
	end
	for _, part in CollectionService:GetTagged("GrappleAnchor") do
		addAnchor(part)
	end
	CollectionService:GetInstanceAddedSignal("GrappleAnchor"):Connect(addAnchor)
	CollectionService:GetInstanceRemovedSignal("GrappleAnchor"):Connect(function(part)
		self.Anchors[part] = nil
		local grapple = self.S.Grapple
		if grapple and grapple.Part == part then
			self:_releaseGrapple(false, true, 0, 0)
		end
	end)

	local okStreaming, streaming = pcall(function()
		return workspace.StreamingEnabled
	end)
	self.Streaming = okStreaming and streaming == true

	self.Params = RaycastParams.new()
	self.Params.FilterType = Enum.RaycastFilterType.Exclude
	self.Params.CollisionGroup = "Runner"
	pcall(function()
		self.Params.RespectCanCollide = true
	end)

	local state = ctx.ClientState
	state:On("Teleported", function()
		self:_onTeleported()
	end)
	state:On("GrappleRejected", function()
		self:_releaseGrapple(false, false, 0, 0)
	end)
	state:On("GrappleForceRelease", function()
		self:_releaseGrapple(false, false, 0, 0)
	end)

	player.CharacterAdded:Connect(function(character)
		self:_bind(character)
	end)
	if player.Character then
		task.spawn(function()
			self:_bind(player.Character)
		end)
	end
end

function MovementController:Start()
	RunService.PreSimulation:Connect(function(dt)
		local ok, err = pcall(self._step, self, dt)
		if not ok then
			warn("[MovementController] " .. tostring(err))
		end
	end)
end

------------------------------------------------------------------------
-- Charakter
------------------------------------------------------------------------

function MovementController:_bind(character: Model)
	self.Character = nil
	local root = character:WaitForChild("HumanoidRootPart", 10)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local collider = character:WaitForChild("VR_Collider", 10)
	if not root or not humanoid or not collider or player.Character ~= character then
		return
	end
	self.Root = root
	self.Humanoid = humanoid
	self.Collider = collider
	self.ColliderWeld = collider:FindFirstChild("VR_ColliderWeld")
	self.Align = root:FindFirstChild("VR_Align")
	self.S = newState()
	self.Params.FilterDescendantsInstances = { character }

	pcall(function()
		humanoid.EvaluateStateMachine = false
	end)
	for _, stateType in DISABLED_STATES do
		pcall(function()
			humanoid:SetStateEnabled(stateType, false)
		end)
	end
	pcall(function()
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end)

	character:GetAttributeChangedSignal("BoostUntil"):Connect(function()
		if (character:GetAttribute("BoostUntil") or 0) > workspace:GetServerTimeNow() then
			self.S.PendingImpulse = M.BoostImpulse
		end
	end)

	self:_setSliding(false)
	self.Character = character
end

function MovementController:_onTeleported()
	local S = self.S
	S.StreamWaitUntil = os.clock() + 3
	S.Grapple = nil
	S.DashUntil = 0
	S.JumpBufferUntil = 0
	S.WasDashing = false
	if S.Sliding then
		self:_setSliding(false)
	end
	self.GrappleEnded:Fire()
	if self.Root then
		self.Root.AssemblyLinearVelocity = Vector3.zero
	end
end

------------------------------------------------------------------------
-- Sensoren
------------------------------------------------------------------------

function MovementController:_groundCheck(position: Vector3): RaycastResult?
	local feetY = position.Y + C.FeetOffset
	local origin = feetY + 0.6
	local length = 0.6 + M.GroundCheckDistance
	local half = C.ColliderWidth / 2 - 0.15
	for _, offset in { 0, -half, half } do
		local hit = workspace:Raycast(Vector3.new(position.X + offset, origin, position.Z), Vector3.new(0, -length, 0), self.Params)
		if hit and hit.Normal.Y > 0.55 then
			return hit
		end
	end
	return nil
end

function MovementController:_wallCheck(position: Vector3): number
	local S = self.S
	local half = C.ColliderWidth / 2
	local top = if S.Sliding then C.SlideHeight else C.StandHeight
	local heights = { C.FeetOffset + 0.8, C.FeetOffset + top * 0.5, C.FeetOffset + top - 0.6 }
	for _, dir in { S.Facing, -S.Facing } do
		local hits = 0
		for _, height in heights do
			local hit = workspace:Raycast(position + Vector3.new(0, height, 0), Vector3.new(dir * (half + 0.35), 0, 0), self.Params)
			if hit and math.abs(hit.Normal.X) > 0.7 and not hit.Instance:GetAttribute("NoWallJump") then
				hits += 1
			end
		end
		if hits >= 2 then
			return dir
		end
	end
	return 0
end

function MovementController:_canStand(): boolean
	local root = self.Root
	if not root then
		return true
	end
	local base = root.Position + Vector3.new(0, C.FeetOffset + C.SlideHeight - 0.1, 0)
	local up = C.StandHeight - C.SlideHeight + 0.2
	local half = C.ColliderWidth / 2 - 0.1
	for _, offset in { -half, 0, half } do
		if workspace:Raycast(base + Vector3.new(offset, 0, 0), Vector3.new(0, up, 0), self.Params) then
			return false
		end
	end
	return true
end

------------------------------------------------------------------------
-- Zustände
------------------------------------------------------------------------

function MovementController:_setSliding(on: boolean)
	local S = self.S
	S.Sliding = on
	local collider = self.Collider
	if collider then
		local height = if on then C.SlideHeight else C.StandHeight
		local center = C.FeetOffset + height / 2
		collider.Size = Vector3.new(C.ColliderWidth, height, C.ColliderDepth)
		if self.ColliderWeld then
			self.ColliderWeld.C0 = CFrame.new(0, center, 0)
		end
	end
	if on then
		S.SlideStart = os.clock()
	else
		S.SlideCooldownUntil = os.clock() + M.SlideCooldown
	end
end

function MovementController:_findTarget(position: Vector3, boosted: boolean): BasePart?
	local range = G.Range * (if boosted then G.UpgradeRangeMultiplier else 1)
	local facing = self.S.Facing
	local candidates = {}
	for part in self.Anchors do
		if part.Parent then
			local p = part.Position
			local dx, dy = p.X - position.X, p.Y - position.Y
			if math.abs(dx) <= range and math.abs(dy) <= range and dy >= -G.MaxAnchorBelow then
				local distance = math.sqrt(dx * dx + dy * dy)
				if distance <= range and distance > 3 then
					local ahead = Util.Sign(dx) == facing or math.abs(dx) < 4
					local score = distance - (if ahead then 18 else 0) - math.clamp(dy, 0, 20) * 0.3
					table.insert(candidates, { Part = part, Score = score, Distance = distance })
				end
			end
		end
	end
	table.sort(candidates, function(a, b)
		return a.Score < b.Score
	end)
	for i = 1, math.min(4, #candidates) do
		local candidate = candidates[i]
		local direction = candidate.Part.Position - position
		local hit = workspace:Raycast(position, direction, self.Params)
		if not hit or (hit.Position - position).Magnitude >= candidate.Distance - 1.5 then
			return candidate.Part
		end
	end
	return nil
end

function MovementController:_tryGrapple(position: Vector3, boosted: boolean)
	local target = self.Target or self:_findTarget(position, boosted)
	if not target then
		self.GrappleFailed:Fire()
		return
	end
	local id = target:GetAttribute("AnchorId")
	if type(id) ~= "number" then
		return
	end
	local S = self.S
	local distance = (target.Position - position).Magnitude
	S.Grapple = {
		Part = target,
		Id = id,
		Position = target.Position,
		Length = math.max(G.MinRopeLength, distance),
		StartedAt = os.clock(),
	}
	S.JumpCutPending = false
	if S.Sliding and self:_canStand() then
		self:_setSliding(false)
	end
	Remotes.GrappleRequest:FireServer("Attach", id)
	self.GrappleStarted:Fire(target)
end

--- Löst den Haken. Gibt den Geschwindigkeitsbonus (dvx, dvy) zurück.
function MovementController:_releaseGrapple(byPlayer: boolean, notifyServer: boolean, vx: number, vy: number): (number, number)
	local S = self.S
	if not S.Grapple then
		return 0, 0
	end
	S.Grapple = nil
	local character = self.Character
	local boosted = character ~= nil and (character:GetAttribute("GrappleBoostUntil") or 0) > workspace:GetServerTimeNow()
	S.GrappleCooldownUntil = os.clock() + (if boosted then G.UpgradeCooldown else G.Cooldown)
	if notifyServer then
		Remotes.GrappleRequest:FireServer("Release")
	end
	self.GrappleEnded:Fire()
	if byPlayer then
		local speed = math.sqrt(vx * vx + vy * vy)
		if speed > 5 then
			return vx / speed * G.ReleaseBoost, vy / speed * G.ReleaseBoost
		end
	end
	return 0, 0
end

function MovementController:_setState(name: string)
	local S = self.S
	if S.State ~= name then
		S.State = name
		self.StateChanged:Fire(name)
	end
	local now = os.clock()
	if (S.SentState ~= S.State or S.SentFacing ~= S.Facing) and now - S.LastSent >= M.StateSendInterval then
		S.SentState = S.State
		S.SentFacing = S.Facing
		S.LastSent = now
		Remotes.MoveState:FireServer(S.State, S.Facing)
	end
end

function MovementController:_updateAlign()
	local S = self.S
	if self.Align and S.AlignFacing ~= S.Facing then
		S.AlignFacing = S.Facing
		self.Align.CFrame = CFrame.lookAt(Vector3.zero, Vector3.new(S.Facing, 0, 0))
	end
end

------------------------------------------------------------------------
-- Haupt-Schritt
------------------------------------------------------------------------

function MovementController:_step(rawDt: number)
	local character = self.Character
	local root = self.Root
	if not character or not root or not root.Parent or not self.Collider then
		return
	end
	local dt = math.min(rawDt, 1 / 20)
	local S = self.S
	local input = self.Input
	local now = os.clock()
	local serverNow = workspace:GetServerTimeNow()

	local frozen = character:GetAttribute("Frozen") == true
	local stunned = (character:GetAttribute("StunnedUntil") or 0) > serverNow
	local slowed = (character:GetAttribute("SlowedUntil") or 0) > serverNow
	local boosted = (character:GetAttribute("BoostUntil") or 0) > serverNow
	local grappleBoost = (character:GetAttribute("GrappleBoostUntil") or 0) > serverNow

	local velocity = root.AssemblyLinearVelocity
	local position = root.Position
	local vx, vy = velocity.X, velocity.Y

	-- Eingefroren (Countdown, Respawn, Ergebnis)
	if frozen then
		if S.Grapple then
			self:_releaseGrapple(false, true, 0, 0)
		end
		if S.Sliding and self:_canStand() then
			self:_setSliding(false)
		end
		S.DashUntil = 0
		S.PendingImpulse = 0
		input:Consume("Jump")
		input:Consume("Grapple")
		input:Consume("Slide")
		root.AssemblyLinearVelocity = Vector3.new(0, math.min(vy, 0), 0)
		root.AssemblyAngularVelocity = Vector3.zero
		S.Grounded = self:_groundCheck(position) ~= nil
		self.Velocity = Vector3.zero
		self.Target = nil
		self:_updateAlign()
		self:_setState("Frozen")
		return
	end

	local vz = math.clamp((Config.World.PlaneZ - position.Z) * 10, -40, 40)

	-- Sensoren
	local groundHit = self:_groundCheck(position)

	-- StreamingEnabled: nach Teleports schweben, bis der Boden geladen ist
	if self.Streaming and now < S.StreamWaitUntil and not groundHit then
		if not workspace:Raycast(position, Vector3.new(0, -250, 0), self.Params) then
			root.AssemblyLinearVelocity = Vector3.new(0, 0, vz)
			root.AssemblyAngularVelocity = Vector3.zero
			self.Velocity = Vector3.zero
			return
		end
	end
	local grounded = groundHit ~= nil and (now - S.LastJumpTime) > 0.12
	if grounded then
		if not S.Grounded and S.MinAirVy < -45 then
			self.Landed:Fire(-S.MinAirVy, position + Vector3.new(0, C.FeetOffset, 0))
		end
		S.LastGroundTime = now
		S.AirDashAvailable = true
		S.MinAirVy = 0
	else
		S.MinAirVy = math.min(S.MinAirVy, vy)
	end
	S.Grounded = grounded
	local wallDir = if grounded then 0 else self:_wallCheck(position)

	-- Eingaben
	local moveX = if stunned then 0 else input:GetMoveX()
	if now < S.WallJumpLockUntil and Util.Sign(moveX) == S.LockedDir then
		moveX = 0
	end
	if input:Consume("Jump") then
		S.JumpBufferUntil = now + M.JumpBuffer
	end
	local jumpHeld = input:IsHeld("Jump")
	local slidePressed = input:Consume("Slide")
	local slideHeld = input:IsHeld("Slide")
	local grapplePressed = input:Consume("Grapple")
	local grappleHeld = input:IsHeld("Grapple")
	if input:Consume("Item") and (player:GetAttribute("HeldItem") or "") ~= "" then
		Remotes.UsePowerUp:FireServer()
	end
	if input:Consume("Emote") then
		Remotes.PlayEmote:FireServer()
	end
	if input:Consume("Respawn") then
		Remotes.RequestRespawn:FireServer()
	end

	-- Blickrichtung
	if S.Grapple then
		if math.abs(vx) > 3 then
			S.Facing = Util.Sign(vx)
		end
	elseif math.abs(moveX) > 0.1 then
		S.Facing = Util.Sign(moveX)
	end

	-- Slide / Air-Dash
	if slidePressed and not stunned then
		if grounded and not S.Sliding and now >= S.SlideCooldownUntil and math.abs(vx) >= M.SlideMinSpeed then
			self:_setSliding(true)
			local dir = Util.Sign(vx)
			local speed = math.abs(vx)
			vx = dir * math.max(speed, math.min(speed + M.SlideBoost, M.MaxRunSpeed + M.SlideBoost))
			self.SlideStarted:Fire()
		elseif not grounded and not S.Grapple and S.AirDashAvailable and now >= S.DashCooldownUntil then
			S.AirDashAvailable = false
			S.DashUntil = now + M.DashDuration
			S.DashCooldownUntil = now + M.DashCooldown
			S.DashDir = S.Facing
			S.DashEntrySpeed = math.abs(vx)
			if S.Sliding and self:_canStand() then
				self:_setSliding(false)
			end
			self.DashStarted:Fire(S.DashDir)
		end
	end
	if S.Sliding and self:_canStand() then
		if not slideHeld or (not grounded and now - S.SlideStart > 0.25) then
			self:_setSliding(false)
		end
	end

	-- Greifhaken
	if grapplePressed and not stunned and not S.Grapple and (now >= S.GrappleCooldownUntil or grappleBoost) then
		self:_tryGrapple(position, grappleBoost)
	end
	if S.Grapple and (not grappleHeld or stunned or now - S.Grapple.StartedAt > G.MaxAttachTime) then
		local bx, by = self:_releaseGrapple(true, true, vx, vy)
		vx += bx
		vy += by
	end

	-- Horizontale Bewegung
	local maxSpeed = M.MaxRunSpeed * (if boosted then M.BoostMultiplier else 1) * (if slowed then M.SlowMultiplier else 1)
	local onIce = groundHit ~= nil and groundHit.Instance:GetAttribute("Ice") == true
	if S.PendingImpulse > 0 then
		vx += S.Facing * S.PendingImpulse
		S.PendingImpulse = 0
	end

	if now < S.DashUntil then
		vx = S.DashDir * M.DashSpeed * (if slowed then M.SlowMultiplier else 1)
		vy = 0
		S.WasDashing = true
	else
		if S.WasDashing then
			S.WasDashing = false
			local cap = math.max(S.DashEntrySpeed, maxSpeed + 6)
			if math.abs(vx) > cap then
				vx = Util.Sign(vx) * cap
			end
		end
		if S.Sliding then
			local friction = M.SlideFriction * (if onIce then 0.3 else 1)
			vx = Util.MoveToward(vx, 0, friction * dt)
			if not self:_canStand() then
				-- Kriechen unter niedrigen Decken
				local dir = S.Facing
				if math.abs(moveX) > 0.1 then
					dir = Util.Sign(moveX)
				elseif math.abs(vx) > 0.5 then
					dir = Util.Sign(vx)
				end
				if math.abs(vx) < M.CrawlSpeed then
					vx = dir * M.CrawlSpeed
				end
			elseif math.abs(vx) < M.SlideEndSpeed then
				self:_setSliding(false)
			end
		elseif S.Grapple then
			vx += moveX * G.SwingAcceleration * dt
		elseif grounded then
			local accelMul = if onIce then M.IceAccelerationMultiplier else 1
			local decelMul = if onIce then M.IceDecelerationMultiplier else 1
			if math.abs(moveX) > 0.05 then
				local target = moveX * maxSpeed
				if math.abs(vx) > maxSpeed and Util.Sign(vx) == Util.Sign(moveX) then
					vx = Util.MoveToward(vx, target, M.OverspeedGroundDecay * decelMul * dt)
				elseif math.abs(vx) > 0.5 and Util.Sign(vx) ~= Util.Sign(moveX) then
					vx = Util.MoveToward(vx, target, M.TurnAcceleration * accelMul * dt)
				else
					vx = Util.MoveToward(vx, target, M.GroundAcceleration * accelMul * dt)
				end
			else
				vx = Util.MoveToward(vx, 0, M.GroundDeceleration * decelMul * dt)
			end
		else
			if math.abs(moveX) > 0.05 then
				local target = moveX * maxSpeed
				if math.abs(vx) > maxSpeed and Util.Sign(vx) == Util.Sign(moveX) then
					vx = Util.MoveToward(vx, target, M.OverspeedAirDecay * dt)
				elseif math.abs(vx) > 0.5 and Util.Sign(vx) ~= Util.Sign(moveX) then
					vx = Util.MoveToward(vx, target, M.AirTurnAcceleration * dt)
				else
					vx = Util.MoveToward(vx, target, M.AirAcceleration * dt)
				end
			else
				local drag = if math.abs(vx) > maxSpeed then M.OverspeedAirDecay else M.AirDrag
				vx = Util.MoveToward(vx, 0, drag * dt)
			end
		end
	end

	-- Vertikale Bewegung
	if now >= S.DashUntil and not S.Grapple then
		if vy < 0 then
			vy -= Config.World.Gravity * (M.FallGravityMultiplier - 1) * dt
		end
		if S.JumpCutPending then
			if vy <= 0 then
				S.JumpCutPending = false
			elseif not jumpHeld then
				vy *= M.JumpCutMultiplier
				S.JumpCutPending = false
			end
		end
	end

	S.WallSliding = false
	if not grounded and wallDir ~= 0 and not S.Grapple and moveX * wallDir > 0.1 and vy < -M.WallSlideMaxFall then
		vy = -M.WallSlideMaxFall
		S.WallSliding = true
	end

	if now < S.JumpBufferUntil and not stunned then
		local canGroundJump = grounded or (now - S.LastGroundTime) <= M.CoyoteTime
		if S.Grapple then
			local bx, by = self:_releaseGrapple(true, true, vx, vy)
			vx += bx
			vy = math.max(vy + by, M.JumpVelocity * 0.6)
			S.JumpBufferUntil = 0
			S.LastJumpTime = now
			self.Jumped:Fire("GrappleJump")
		elseif canGroundJump and (not S.Sliding or self:_canStand()) then
			if S.Sliding then
				self:_setSliding(false)
			end
			vy = M.JumpVelocity * (if slowed then 0.8 else 1)
			S.JumpBufferUntil = 0
			S.LastJumpTime = now
			S.LastGroundTime = -math.huge
			S.JumpCutPending = true
			grounded = false
			self.Jumped:Fire("Jump")
		elseif not grounded and wallDir ~= 0 then
			vx = -wallDir * M.WallJumpVelocityX
			vy = M.WallJumpVelocityY
			S.Facing = -wallDir
			S.WallJumpLockUntil = now + M.WallJumpLockTime
			S.LockedDir = wallDir
			S.JumpBufferUntil = 0
			S.LastJumpTime = now
			S.JumpCutPending = true
			S.AirDashAvailable = true
			self.Jumped:Fire("WallJump")
		end
	end
	vy = math.max(vy, -M.MaxFallSpeed)

	-- Boost- und Sprungpads
	if groundHit and grounded then
		local part = groundHit.Instance
		local boost = part:GetAttribute("BoostPad")
		if type(boost) == "number" and now - S.LastPadTime > 0.25 then
			local direction = part:GetAttribute("Direction") or 1
			vx = direction * math.max(vx * direction, boost)
			S.LastPadTime = now
			self.BoostPad:Fire(position)
		end
		local jumpPower = part:GetAttribute("JumpPad")
		if type(jumpPower) == "number" and now - S.LastPadTime > 0.3 then
			if S.Sliding and self:_canStand() then
				self:_setSliding(false)
			end
			vy = jumpPower
			S.LastJumpTime = now
			S.LastGroundTime = -math.huge
			S.LastPadTime = now
			S.JumpCutPending = false
			self.Jumped:Fire("Pad")
		end
	end

	-- Seilphysik: Seil zieht sich bei Durchhang ein, hält bei Spannung die Länge
	local grapple = S.Grapple
	if grapple then
		local anchor = grapple.Position
		local dx, dy = position.X - anchor.X, position.Y - anchor.Y
		local distance = math.sqrt(dx * dx + dy * dy)
		local reel = G.ReelSpeed * (if grappleBoost then G.UpgradeReelMultiplier else 1)
		grapple.Length = math.max(G.MinRopeLength, math.min(grapple.Length, distance) - reel * dt)
		if distance > grapple.Length and distance > 0.01 then
			local nx, ny = dx / distance, dy / distance
			local radial = vx * nx + vy * ny
			if radial > 0 then
				vx -= nx * radial
				vy -= ny * radial
			end
			local correction = math.min((distance - grapple.Length) * G.RopeStiffness, G.MaxCorrectionSpeed)
			vx -= nx * correction
			vy -= ny * correction
		end
	end

	vx = math.clamp(vx, -M.AbsoluteMaxSpeed, M.AbsoluteMaxSpeed)
	root.AssemblyLinearVelocity = Vector3.new(vx, vy, vz)
	root.AssemblyAngularVelocity = Vector3.zero
	self.Velocity = Vector3.new(vx, vy, 0)
	self:_updateAlign()

	local stateName
	if stunned then
		stateName = "Stunned"
	elseif now < S.DashUntil then
		stateName = "Dash"
	elseif S.Grapple then
		stateName = "Grapple"
	elseif S.Sliding then
		stateName = "Slide"
	elseif S.WallSliding then
		stateName = "Wall"
	elseif not grounded then
		stateName = "Air"
	elseif math.abs(vx) > 2 then
		stateName = "Run"
	else
		stateName = "Idle"
	end
	self:_setState(stateName)

	self.Target = if S.Grapple then nil else self:_findTarget(position, grappleBoost)
end

------------------------------------------------------------------------
-- Öffentliche Abfragen (für Animation, Effekte, UI)
------------------------------------------------------------------------

function MovementController:GetState(): string
	return self.S.State
end

function MovementController:GetFacing(): number
	return self.S.Facing
end

function MovementController:GetGrappleAnchor(): Vector3?
	local grapple = self.S.Grapple
	return grapple and grapple.Position or nil
end

--- Restzeiten der Fähigkeiten in Sekunden (0 = bereit).
function MovementController:GetCooldowns()
	local S = self.S
	local now = os.clock()
	return {
		Grapple = math.max(0, S.GrappleCooldownUntil - now),
		GrappleMax = G.Cooldown,
		Dash = math.max(0, S.DashCooldownUntil - now),
		DashMax = M.DashCooldown,
		DashAvailable = S.AirDashAvailable,
		Slide = math.max(0, S.SlideCooldownUntil - now),
		SlideMax = M.SlideCooldown,
		Grappling = S.Grapple ~= nil,
		HasTarget = self.Target ~= nil,
	}
end

return MovementController
