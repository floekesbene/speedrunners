--[[
	CharacterService  (ModuleScript)
	Pfad: ServerScriptService/Server/Services/CharacterService

	Verwaltet Spielfiguren:
		- legt beim Start StarterPlayer/StarterCharacter (RunnerRig) an
		- spawnt Spieler manuell (Players.CharacterAutoLoads = false)
		- setzt Spawn-/Respawnposition je nach Region (Lobby, Rennen, Training)
		- Teleports mit Anti-Exploit-Toleranz und Client-Benachrichtigung
		- Kosmetik und Namensschilder
		- Movement-Status (MoveState) aus Client-Meldungen übernehmen
		- Lobby-Portale und Absturzschutz in der Lobby

	Öffentliche API:
		:Spawn(player)
		:Teleport(player, cframe) -> boolean
		:SendToLobby(player)
		:GetRoot(player) -> BasePart?
		:GetRegion(player) -> string ("Lobby" | "Race" | Practice-RegionId)
		:GetSpawnCFrame(player) -> CFrame
		:SetFrozen(player, frozen)
		:ClearStatus(player)
		:ApplyCosmetics(player)
		.CharacterReady (Signal: player, character)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Signal = require(Shared.Signal)
local Remotes = require(Shared.Remotes)
local RunnerRig = require(Shared.RunnerRig)
local CosmeticApplier = require(Shared.CosmeticApplier)
local CosmeticDefinitions = require(Shared.CosmeticDefinitions)
local Progression = require(Shared.Progression)

local RateLimiter = require(script.Parent.Parent.Modules.RateLimiter)

local CharacterService = {}
CharacterService.CharacterReady = Signal.new()

local VALID_STATES = {
	Idle = true,
	Run = true,
	Air = true,
	Slide = true,
	Wall = true,
	Grapple = true,
	Dash = true,
	Frozen = true,
	Stunned = true,
}

local STATUS_ATTRIBUTES = { "StunnedUntil", "SlowedUntil", "BoostUntil", "GrappleBoostUntil", "ShieldUntil" }

function CharacterService:Init(services)
	self.Services = services
	self.Spawning = {}
	self.PortalState = {} -- [player] = { Portal, Since, Fired }
	self.MoveLimiter = RateLimiter.ForRemote("MoveState")
	self.EmoteLimiter = RateLimiter.ForRemote("PlayEmote")
	self.RespawnLimiter = RateLimiter.ForRemote("RequestRespawn")

	Players.CharacterAutoLoads = false
	pcall(function()
		StarterPlayer.LoadCharacterAppearance = false
	end)

	local existing = StarterPlayer:FindFirstChild("StarterCharacter")
	if existing then
		existing:Destroy()
	end
	local rig = RunnerRig.Build({ ForCharacter = true })
	rig.Name = "StarterCharacter"
	rig.Parent = StarterPlayer
end

function CharacterService:Start()
	local data = self.Services.PlayerDataService

	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			self:_setupCharacter(player, character)
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end

	data.ProfileLoaded:Connect(function(player)
		self:Spawn(player)
	end)
	for _, player in Players:GetPlayers() do
		if data:GetProfile(player) and not player.Character then
			self:Spawn(player)
		end
	end

	Remotes.MoveState.OnServerEvent:Connect(function(player, state, facing)
		if not self.MoveLimiter:Check(player) then
			return
		end
		if type(state) ~= "string" or not VALID_STATES[state] then
			return
		end
		if facing ~= 1 and facing ~= -1 then
			facing = 1
		end
		local character = player.Character
		if character then
			character:SetAttribute("MoveState", state)
			character:SetAttribute("Facing", facing)
		end
	end)

	Remotes.PlayEmote.OnServerEvent:Connect(function(player)
		if not self.EmoteLimiter:Check(player) then
			return
		end
		self:_playEmote(player)
	end)

	Remotes.RequestRespawn.OnServerEvent:Connect(function(player)
		if not self.RespawnLimiter:Check(player) then
			return
		end
		local services = self.Services
		if services.RoundService:IsActiveRacer(player) then
			services.RoundService:RespawnRacer(player, "Manual")
		elseif services.PracticeService:GetCourse(player) then
			services.PracticeService:Reset(player)
		else
			self:SendToLobby(player)
		end
	end)
end

function CharacterService:OnPlayerRemoving(player: Player)
	self.Spawning[player] = nil
	self.PortalState[player] = nil
end

------------------------------------------------------------------------
-- Spawnen
------------------------------------------------------------------------

function CharacterService:Spawn(player: Player)
	if self.Spawning[player] or not player.Parent then
		return
	end
	self.Spawning[player] = true
	task.spawn(function()
		local ok, err = pcall(function()
			player:LoadCharacter()
		end)
		if not ok then
			warn("[CharacterService] LoadCharacter fehlgeschlagen: " .. tostring(err))
		end
		self.Spawning[player] = nil
	end)
end

function CharacterService:_setupCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not root then
		return
	end
	character:SetAttribute("MoveState", "Idle")
	character:SetAttribute("Facing", 1)
	character:SetAttribute("Frozen", false)
	character:SetAttribute("Grappling", false)
	character:SetAttribute("Emote", "")
	character:SetAttribute("Victory", "")
	for _, name in STATUS_ATTRIBUTES do
		character:SetAttribute(name, 0)
	end

	self:ApplyCosmetics(player)
	self:_nameTag(player, character)

	humanoid.Died:Connect(function()
		task.wait(1)
		if player.Parent and player.Character == character then
			self:Spawn(player)
		end
	end)

	local cframe = self:GetSpawnCFrame(player)
	self.Services.AntiExploitService:GrantGrace(player, 2.5)
	character:PivotTo(cframe)
	self.CharacterReady:Fire(player, character)
end

function CharacterService:_nameTag(player: Player, character: Model)
	local head = character:FindFirstChild("Head")
	if not head then
		return
	end
	local old = head:FindFirstChild("VR_NameTag")
	if old then
		old:Destroy()
	end
	local profile = self.Services.PlayerDataService:GetProfile(player)
	local gui = Instance.new("BillboardGui")
	gui.Name = "VR_NameTag"
	gui.Size = UDim2.fromOffset(160, 40)
	gui.StudsOffset = Vector3.new(0, 2.4, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 140
	gui.LightInfluence = 0
	gui.PlayerToHideFrom = player
	gui.ResetOnSpawn = false

	local name = Instance.new("TextLabel")
	name.Name = "PlayerName"
	name.BackgroundTransparency = 1
	name.Size = UDim2.fromScale(1, 0.6)
	name.Font = Enum.Font.GothamBlack
	name.TextScaled = true
	name.TextColor3 = Color3.fromRGB(255, 255, 255)
	name.TextStrokeTransparency = 0.4
	name.Text = player.DisplayName
	name.Parent = gui

	local info = Instance.new("TextLabel")
	info.Name = "Info"
	info.BackgroundTransparency = 1
	info.Position = UDim2.fromScale(0, 0.6)
	info.Size = UDim2.fromScale(1, 0.4)
	info.Font = Enum.Font.GothamBold
	info.TextScaled = true
	info.TextStrokeTransparency = 0.5
	if profile then
		local tier = Progression.GetTier(profile.Ranked.Rating)
		info.Text = string.format("Lv. %d · %s", profile.Level, tier.Name)
		info.TextColor3 = tier.Color
	else
		info.Text = ""
	end
	info.Parent = gui
	gui.Parent = head
end

------------------------------------------------------------------------
-- Positionen und Teleports
------------------------------------------------------------------------

function CharacterService:GetRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

function CharacterService:GetRegion(player: Player): string
	local services = self.Services
	if services.RoundService:IsActiveRacer(player) then
		return "Race"
	end
	local course = services.PracticeService:GetCourse(player)
	if course then
		return services.PracticeService:RegionIdFor(course)
	end
	return "Lobby"
end

function CharacterService:GetLobbySpawn(): CFrame
	local lobby = self.Services.MapService:GetRegion("Lobby")
	if lobby and #lobby.Spawns > 0 then
		return lobby.Spawns[math.random(1, #lobby.Spawns)]
	end
	return CFrame.new(Config.World.LobbyOrigin + Vector3.new(0, 5, 0))
end

function CharacterService:GetSpawnCFrame(player: Player): CFrame
	local services = self.Services
	local cframe = services.RoundService:GetRespawnCFrame(player)
	if cframe then
		return cframe
	end
	cframe = services.PracticeService:GetRespawnCFrame(player)
	if cframe then
		return cframe
	end
	return self:GetLobbySpawn()
end

--- Teleportiert die Spielfigur. Löst den Greifhaken und informiert den Client.
function CharacterService:Teleport(player: Player, cframe: CFrame): boolean
	local character = player.Character
	local root = self:GetRoot(player)
	if not character or not root then
		return false
	end
	self.Services.AntiExploitService:GrantGrace(player, Config.AntiExploit.TeleportGrace)
	self.Services.GrappleService:Release(player, true)
	character:SetAttribute("Emote", "")
	character:PivotTo(cframe)
	root.AssemblyLinearVelocity = Vector3.zero
	Remotes.GameEvent:FireClient(player, "Teleported", { Position = cframe.Position })
	return true
end

function CharacterService:SendToLobby(player: Player)
	if not self:Teleport(player, self:GetLobbySpawn()) then
		self:Spawn(player)
	end
end

function CharacterService:SetFrozen(player: Player, frozen: boolean)
	local character = player.Character
	if character then
		character:SetAttribute("Frozen", frozen)
	end
end

--- Setzt alle Power-up-Statuswerte zurück (z.B. nach Rundenende).
function CharacterService:ClearStatus(player: Player)
	local character = player.Character
	if not character then
		return
	end
	for _, name in STATUS_ATTRIBUTES do
		character:SetAttribute(name, 0)
	end
	character:SetAttribute("Victory", "")
	character:SetAttribute("Emote", "")
end

function CharacterService:ApplyCosmetics(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local equipped = self.Services.InventoryService:GetEquipped(player)
	CosmeticApplier.Apply(character, equipped)
	-- Kosmetik darf nie kollidieren (Sicherheitsnetz)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name ~= "VR_Collider" then
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = descendant.Name ~= "HumanoidRootPart"
			descendant.CollisionGroup = "RunnerBody"
		end
	end
end

function CharacterService:_playEmote(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local services = self.Services
	if services.RoundService:IsActiveRacer(player) and services.RoundService:GetPhase() == "Racing" then
		return
	end
	local equipped = services.InventoryService:GetEquipped(player)
	local emoteId = equipped.Emotes
	if not CosmeticDefinitions.Get("Emotes", emoteId) or not services.InventoryService:Owns(player, "Emotes", emoteId) then
		return
	end
	character:SetAttribute("Emote", emoteId)
	character:SetAttribute("EmoteAt", workspace:GetServerTimeNow())
end

------------------------------------------------------------------------
-- Tick (10 Hz, von Bootstrap aufgerufen)
------------------------------------------------------------------------

function CharacterService:Tick(_dt: number)
	local services = self.Services
	local lobby = services.MapService:GetRegion("Lobby")
	for _, player in Players:GetPlayers() do
		local profileLoaded = services.PlayerDataService:GetProfile(player) ~= nil
		local character = player.Character
		local root = self:GetRoot(player)
		if profileLoaded and (not character or not root or not character.Parent) then
			self:Spawn(player)
		elseif root and lobby and player:GetAttribute("InRace") ~= true and self:GetRegion(player) == "Lobby" then
			-- (Spieler mit InRace = true stehen noch auf der Strecke: Siegerehrung bzw.
			-- kurze Pause nach dem Ausscheiden – RoundService holt sie selbst zurück.)
			local position = root.Position
			if position.Y < lobby.KillY or math.abs(position.X - Config.World.LobbyOrigin.X) > 1500 then
				self:SendToLobby(player)
			else
				self:_checkPortals(player, lobby, position)
			end
		end
	end
end

function CharacterService:_checkPortals(player: Player, lobby, position: Vector3)
	local inside = nil
	for _, portal in lobby.Portals do
		if position.X >= portal.MinX and position.X <= portal.MaxX and position.Y >= portal.MinY and position.Y <= portal.MaxY then
			inside = portal
			break
		end
	end
	local state = self.PortalState[player]
	if not inside then
		self.PortalState[player] = nil
		return
	end
	if not state or state.Portal ~= inside then
		self.PortalState[player] = { Portal = inside, Since = os.clock(), Fired = false }
		return
	end
	if state.Fired or os.clock() - state.Since < 0.8 then
		return
	end
	state.Fired = true
	local services = self.Services
	if inside.Action == "QuickPlay" or inside.Action == "Ranked" then
		local ok, message = services.MatchmakingService:Join(player, inside.Action)
		Remotes.GameEvent:FireClient(player, "Notify", {
			Text = if ok then "Warteschlange beigetreten." else message,
			Kind = if ok then "Success" else "Warning",
		})
	elseif inside.Action == "Practice" then
		Remotes.GameEvent:FireClient(player, "OpenScreen", { Screen = "Practice" })
	end
end

return CharacterService
