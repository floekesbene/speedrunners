--[[
	GrappleService  (ModuleScript)
	Pfad: ServerScriptService/Server/Services/GrappleService

	Serverseitige Validierung des Greifhakens. Der Client simuliert das
	Schwingen sofort (Vorhersage, keine spürbare Latenz) und meldet das Ziel.
	Der Server prüft:
		- Anker existiert und gehört zur Region, in der sich der Spieler befindet
		- Distanz ≤ Reichweite (+ Upgrade) + Latenztoleranz
		- Spieler ist nicht eingefroren/betäubt
		- Mindestabstand zwischen zwei Ankoppelungen (Spam-Schutz)
	Bei Ablehnung erhält der Client "GrappleRejected" und löst sofort.
	Gültige Seile werden über Character-Attribute (Grappling, GrappleTarget)
	an alle Clients repliziert, damit jeder das Seil sieht.

	Öffentliche API:
		:RegisterAnchor(part, regionId) -> anchorId
		:UnregisterRegion(regionId)
		:Release(player, notifyClient)
		:IsGrappling(player) -> boolean
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local RateLimiter = require(script.Parent.Parent.Modules.RateLimiter)

local GrappleService = {}

function GrappleService:Init(services)
	self.Services = services
	self.Anchors = {} -- [id] = { Part, Region }
	self.NextId = 1
	self.Active = {} -- [player] = { AnchorId, Since }
	self.LastAttach = {}
	self.Limiter = RateLimiter.ForRemote("GrappleRequest")
end

function GrappleService:Start()
	Remotes.GrappleRequest.OnServerEvent:Connect(function(player, action, anchorId)
		if not self.Limiter:Check(player) then
			return
		end
		if action == "Release" then
			self:Release(player, false)
		elseif action == "Attach" then
			local ok, reason = self:_attach(player, anchorId)
			if not ok then
				if Config.Debug.LogRejections then
					warn(string.format("[GrappleService] %s abgelehnt: %s", player.Name, tostring(reason)))
				end
				Remotes.GameEvent:FireClient(player, "GrappleRejected", { Reason = reason })
			end
		end
	end)
end

function GrappleService:OnPlayerRemoving(player: Player)
	self.Active[player] = nil
	self.LastAttach[player] = nil
end

function GrappleService:RegisterAnchor(part: BasePart, regionId: string): number
	local id = self.NextId
	self.NextId += 1
	part:SetAttribute("AnchorId", id)
	part:SetAttribute("RegionId", regionId)
	CollectionService:AddTag(part, "GrappleAnchor")
	self.Anchors[id] = { Part = part, Region = regionId }
	return id
end

function GrappleService:UnregisterRegion(regionId: string)
	for id, anchor in self.Anchors do
		if anchor.Region == regionId then
			self.Anchors[id] = nil
			for player, active in self.Active do
				if active.AnchorId == id then
					self:Release(player, true)
				end
			end
		end
	end
end

function GrappleService:IsGrappling(player: Player): boolean
	return self.Active[player] ~= nil
end

function GrappleService:_attach(player: Player, anchorId: any): (boolean, string?)
	if type(anchorId) ~= "number" or anchorId ~= anchorId then
		return false, "InvalidId"
	end
	local anchor = self.Anchors[anchorId]
	if not anchor or not anchor.Part.Parent then
		return false, "UnknownAnchor"
	end
	local character = player.Character
	local root = self.Services.CharacterService:GetRoot(player)
	if not character or not root then
		return false, "NoCharacter"
	end
	if character:GetAttribute("Frozen") then
		return false, "Frozen"
	end
	local now = workspace:GetServerTimeNow()
	if (character:GetAttribute("StunnedUntil") or 0) > now then
		return false, "Stunned"
	end
	local region = self.Services.CharacterService:GetRegion(player)
	if anchor.Region ~= region then
		return false, "WrongRegion"
	end
	local last = self.LastAttach[player]
	if last and os.clock() - last < Config.Grapple.ServerMinInterval then
		return false, "TooFast"
	end
	local range = Config.Grapple.Range
	if (character:GetAttribute("GrappleBoostUntil") or 0) > now then
		range *= Config.Grapple.UpgradeRangeMultiplier
	end
	local distance = (root.Position - anchor.Part.Position).Magnitude
	if distance > range + Config.Grapple.ServerRangeTolerance then
		return false, "OutOfRange"
	end

	self.LastAttach[player] = os.clock()
	self.Active[player] = { AnchorId = anchorId, Since = os.clock() }
	character:SetAttribute("GrappleTarget", anchor.Part.Position)
	character:SetAttribute("Grappling", true)

	local inRace = region == "Race"
	self.Services.RewardService:OnGrapple(player, inRace)
	return true
end

--- Löst den Greifhaken. notifyClient=true erzwingt das Lösen auch auf dem Client.
function GrappleService:Release(player: Player, notifyClient: boolean?)
	local wasActive = self.Active[player] ~= nil
	self.Active[player] = nil
	local character = player.Character
	if character then
		character:SetAttribute("Grappling", false)
	end
	if notifyClient and (wasActive or character) and player.Parent then
		Remotes.GameEvent:FireClient(player, "GrappleForceRelease", {})
	end
end

return GrappleService
