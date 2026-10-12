--[[
	PracticeService  (ModuleScript)
	Pfad: ServerScriptService/Server/Services/PracticeService

	Trainingsmodus ohne Wettbewerbsdruck:
		- "Tutorial": Bewegungs-Tutorial mit erklärenden Schildern
		- jede Rennstrecke als eigene Trainingskopie (Abkürzungen testen)
	Kein Gefahrenring, keine Coins/XP, keine Statistiken, keine Bestzeiten.
	Items können getestet werden, offensive Items treffen niemanden.
	Wird ein Match gestartet, verlässt der Spieler das Training automatisch.

	Remote "PracticeRequest": ("Enter", courseId) | ("Leave") | ("Reset")

	Öffentliche API:
		:RegionIdFor(courseId) -> string
		:GetCourse(player) -> courseId?
		:Enter(player, courseId) -> (boolean, string)
		:Leave(player)
		:ForceLeave(player)        (ohne Teleport, z.B. bei Matchstart)
		:Reset(player)
		:GetRespawnCFrame(player) -> CFrame?
		:Tick(dt)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Util = require(Shared.Util)
local MapDefinitions = require(Shared.MapDefinitions)

local RateLimiter = require(script.Parent.Parent.Modules.RateLimiter)

local PracticeService = {}

function PracticeService:Init(services)
	self.Services = services
	self.Active = {} -- [player] = { Course, Checkpoint, StartedAt, LastPosition, RespawnLock, Finished }
	self.Limiter = RateLimiter.ForRemote("PracticeRequest")
end

function PracticeService:Start()
	Remotes.PracticeRequest.OnServerEvent:Connect(function(player, action, courseId)
		if not self.Limiter:Check(player) then
			return
		end
		if action == "Enter" then
			local ok, message = self:Enter(player, courseId)
			Remotes.GameEvent:FireClient(player, "Notify", { Text = message, Kind = if ok then "Success" else "Warning" })
		elseif action == "Leave" then
			if self.Active[player] then
				self:Leave(player)
			end
		elseif action == "Reset" then
			self:Reset(player)
		end
	end)
	Players.PlayerAdded:Connect(function(player)
		player:SetAttribute("PracticeCourse", "")
	end)
	for _, player in Players:GetPlayers() do
		player:SetAttribute("PracticeCourse", "")
	end
end

function PracticeService:OnPlayerRemoving(player: Player)
	self.Active[player] = nil
end

function PracticeService:RegionIdFor(courseId: string): string
	if courseId == "Tutorial" then
		return "Tutorial"
	end
	return "Practice_" .. courseId
end

function PracticeService:GetCourse(player: Player): string?
	local entry = self.Active[player]
	return entry and entry.Course or nil
end

function PracticeService:Enter(player: Player, courseId: any): (boolean, string)
	if type(courseId) ~= "string" or (courseId ~= "Tutorial" and not MapDefinitions.Get(courseId)) then
		return false, "Unbekannte Trainingsstrecke."
	end
	local services = self.Services
	if services.RoundService:IsInMatch(player) then
		return false, "Während eines Rennens nicht möglich."
	end
	if not player.Character then
		return false, "Spielfigur lädt noch."
	end
	local region = services.MapService:EnsurePracticeRegion(courseId)
	if not region then
		return false, "Strecke konnte nicht geladen werden."
	end
	self.Active[player] = {
		Course = courseId,
		Checkpoint = 1,
		StartedAt = os.clock(),
		LastPosition = nil,
		RespawnLock = false,
		Finished = false,
	}
	player:SetAttribute("PracticeCourse", courseId)
	services.PowerUpService:ClearPlayer(player)
	services.CharacterService:ClearStatus(player)
	services.CharacterService:SetFrozen(player, false)
	services.CharacterService:Teleport(player, region.Spawns[1])
	local definition = MapDefinitions.GetAny(courseId)
	return true, "Training: " .. (definition and definition.Name or courseId)
end

function PracticeService:ForceLeave(player: Player)
	if not self.Active[player] then
		return
	end
	self.Active[player] = nil
	player:SetAttribute("PracticeCourse", "")
	self.Services.PowerUpService:ClearPlayer(player)
	self.Services.CharacterService:ClearStatus(player)
end

function PracticeService:Leave(player: Player)
	self:ForceLeave(player)
	self.Services.CharacterService:SendToLobby(player)
end

function PracticeService:GetRespawnCFrame(player: Player): CFrame?
	local entry = self.Active[player]
	if not entry then
		return nil
	end
	local region = self.Services.MapService:GetRegion(self:RegionIdFor(entry.Course))
	if not region then
		return nil
	end
	local checkpoint = region.Checkpoints[entry.Checkpoint] or region.Checkpoints[1]
	return if checkpoint then checkpoint.CFrame else region.Spawns[1]
end

function PracticeService:Reset(player: Player)
	local entry = self.Active[player]
	if not entry then
		return
	end
	local cframe = self:GetRespawnCFrame(player)
	if cframe then
		if entry.Checkpoint <= 1 then
			entry.StartedAt = os.clock()
		end
		self.Services.CharacterService:Teleport(player, cframe)
		entry.LastPosition = cframe.Position
	end
end

function PracticeService:_respawn(player: Player, entry)
	if entry.RespawnLock then
		return
	end
	entry.RespawnLock = true
	local services = self.Services
	local cframe = self:GetRespawnCFrame(player)
	if cframe then
		Remotes.GameEvent:FireAllClients("RacerRespawn", { UserId = player.UserId, From = entry.LastPosition, To = cframe.Position, Reason = "Practice" })
		services.CharacterService:Teleport(player, cframe)
		services.CharacterService:SetFrozen(player, true)
		entry.LastPosition = cframe.Position
	end
	task.delay(Config.Practice.RespawnFreezeTime, function()
		entry.RespawnLock = false
		if self.Active[player] == entry then
			services.CharacterService:SetFrozen(player, false)
		end
	end)
end

function PracticeService:Tick(_dt: number)
	local services = self.Services
	for player, entry in self.Active do
		local root = services.CharacterService:GetRoot(player)
		local region = services.MapService:GetRegion(self:RegionIdFor(entry.Course))
		if root and region and not entry.Finished then
			local position = root.Position
			local previous = entry.LastPosition
			entry.LastPosition = position
			local index = services.MapService:FindCheckpointIndex(region, position.X)
			if index > entry.Checkpoint then
				entry.Checkpoint = index
			end
			if not entry.RespawnLock then
				local hit = services.MapService:IsInHazard(region, position, previous)
				if hit then
					self:_respawn(player, entry)
				elseif region.FinishX and position.X >= region.FinishX then
					entry.Finished = true
					local elapsed = os.clock() - entry.StartedAt
					Remotes.GameEvent:FireClient(player, "PracticeFinished", { CourseId = entry.Course, Time = elapsed })
					Remotes.GameEvent:FireClient(player, "Notify", {
						Text = "Strecke geschafft in " .. Util.FormatTime(elapsed) .. "! Neustart in 3 Sekunden.",
						Kind = "Success",
					})
					task.delay(3, function()
						if self.Active[player] == entry then
							entry.Finished = false
							entry.Checkpoint = 1
							entry.StartedAt = os.clock()
							services.CharacterService:Teleport(player, region.Spawns[1])
							entry.LastPosition = region.Spawns[1].Position
						end
					end)
				end
			end
		end
	end
end

return PracticeService
