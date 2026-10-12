--[[
	HazardRingService  (ModuleScript)
	Pfad: ServerScriptService/Server/Services/HazardRingService

	Der "Gefahrenring" ist für das Side-Scrolling angepasst: eine Energiewand,
	die dem Führenden in einem festen Abstand folgt. Der Abstand ("Zonenlänge")
	schrumpft über die Zeit. Wer zu lange hinter der Wand ist, scheidet aus.

	Phasen (Zeit seit Rennstart, siehe Config.HazardZone):
		Safe       0 .. WarningStart         Wand inaktiv
		Warning    WarningStart .. ShrinkStart  Ankündigung, noch harmlos
		Shrinking  ShrinkStart .. +ShrinkDuration  Länge InitialLength -> FinalLength
		Final      danach                    Länge = FinalLength

	Fairness:
		- Die Wand bewegt sich nur vorwärts (nie zurück) und nie näher als
		  FinalLength an den Führenden heran -> der Führende ist nie in Gefahr.
		- Ausscheiden erst nach EliminationDelay Sekunden ununterbrochen hinter
		  der Wand; die Gefahrenzeit baut sich in Sicherheit wieder ab.
		- Serverautoritativ: nur der Server berechnet Position und Ausscheiden.

	Repliziert über ReplicatedStorage/GameState (Attribute):
		ZoneState, ZoneX, ZoneLength, ZoneWarnAt, ZoneShrinkAt
	und pro Rennfahrer DangerTime im Racer-Ordner.

	Öffentliche API:
		:Reset()
		:Begin(match)
		:Update(match, dt) -> { racer, ... }   (auszuscheidende Rennfahrer)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local HazardRingService = {}

function HazardRingService:Init(services)
	self.Services = services
	self.ZoneX = -math.huge
	self.Active = false
end

function HazardRingService:Start()
	self:Reset()
end

local function gameState()
	return ReplicatedStorage:FindFirstChild("GameState")
end

function HazardRingService:Reset()
	self.Active = false
	self.ZoneX = -math.huge
	local state = gameState()
	if state then
		state:SetAttribute("ZoneState", "Inactive")
		state:SetAttribute("ZoneX", -1e6)
		state:SetAttribute("ZoneLength", 0)
		state:SetAttribute("ZoneWarnAt", 0)
		state:SetAttribute("ZoneShrinkAt", 0)
	end
end

function HazardRingService:Begin(match)
	local zone = Config.HazardZone
	self.Active = true
	self.ZoneX = match.Map.StartX - 100
	local state = gameState()
	if state then
		state:SetAttribute("ZoneState", "Safe")
		state:SetAttribute("ZoneX", self.ZoneX)
		state:SetAttribute("ZoneLength", zone.InitialLength)
		state:SetAttribute("ZoneWarnAt", match.StartedAt + zone.WarningStart)
		state:SetAttribute("ZoneShrinkAt", match.StartedAt + zone.ShrinkStart)
	end
end

--- Aktualisiert die Wand und liefert alle Rennfahrer, die ausscheiden.
function HazardRingService:Update(match, dt: number)
	local eliminated = {}
	if not self.Active then
		return eliminated
	end
	local zone = Config.HazardZone
	local state = gameState()
	local elapsed = workspace:GetServerTimeNow() - match.StartedAt

	local phase
	local length
	if elapsed < zone.WarningStart then
		phase = "Safe"
		length = zone.InitialLength
	elseif elapsed < zone.ShrinkStart then
		phase = "Warning"
		length = zone.InitialLength
	else
		local t = math.clamp((elapsed - zone.ShrinkStart) / zone.ShrinkDuration, 0, 1)
		length = zone.InitialLength + (zone.FinalLength - zone.InitialLength) * t
		phase = if t >= 1 then "Final" else "Shrinking"
	end

	-- Führenden bestimmen (nur aktive Rennfahrer mit Spielfigur)
	local leaderX = nil
	for _, racer in match.RacerList do
		if racer.Status == "Racing" and racer.LastPosition then
			if not leaderX or racer.LastPosition.X > leaderX then
				leaderX = racer.LastPosition.X
			end
		end
	end

	if phase == "Shrinking" or phase == "Final" then
		if leaderX then
			local candidate = leaderX - length
			if match.Map.FinishX then
				candidate = math.min(candidate, match.Map.FinishX - 10)
			end
			self.ZoneX = math.max(self.ZoneX, candidate)
		end
		for _, racer in match.RacerList do
			if racer.Status == "Racing" then
				local position = racer.LastPosition
				if position and position.X < self.ZoneX then
					racer.DangerTime += dt
				else
					racer.DangerTime = math.max(0, racer.DangerTime - dt * zone.RecoveryRate)
				end
				if racer.DangerTime >= zone.EliminationDelay then
					table.insert(eliminated, racer)
				end
			end
		end
	end

	if state then
		state:SetAttribute("ZoneState", phase)
		state:SetAttribute("ZoneLength", math.floor(length))
		if phase == "Shrinking" or phase == "Final" then
			state:SetAttribute("ZoneX", math.floor(self.ZoneX * 10) / 10)
		end
	end
	return eliminated
end

return HazardRingService
