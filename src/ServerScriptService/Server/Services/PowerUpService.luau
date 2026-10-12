--[[
	PowerUpService  (ModuleScript)
	Pfad: ServerScriptService/Server/Services/PowerUpService

	Item-Boxen, Aufsammeln, Benutzen und Effekte aller Power-ups
	(Definitionen: ReplicatedStorage/Shared/ItemDefinitions).

	Regeln:
		- Ein Spieler hält höchstens ein Item (Player-Attribut "HeldItem").
		- Aufsammeln wird serverseitig per Distanz geprüft (10 Hz).
		- Benutzung: Item wird VOR dem Effekt entfernt (kein Doppelverbrauch),
		  zusätzlich Debounce pro Spieler.
		- Effekte sind Character-Attribute mit Ablaufzeit (Server-Zeit), die der
		  Client für Bewegung und Effekte ausliest.
		- Im Training wirken offensive Items auf niemanden.
		- Rundenende: Items, Fallen und Status werden bereinigt.

	Öffentliche API:
		:RegisterRegion(mapInstance)
		:UnregisterRegion(regionId)
		:ResetRegion(regionId)
		:GiveItem(player, itemId)
		:ClearPlayer(player)
		:Tick(dt)
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Util = require(Shared.Util)
local ItemDefinitions = require(Shared.ItemDefinitions)

local RateLimiter = require(script.Parent.Parent.Modules.RateLimiter)

local PowerUpService = {}

function PowerUpService:Init(services)
	self.Services = services
	self.Boxes = {} -- { {Part, Region, Active, RespawnAt} }
	self.Traps = {} -- { {Part, Owner, Region, ExpiresAt, ArmedAt} }
	self.LastUse = {}
	self.Rng = Random.new()
	self.Limiter = RateLimiter.ForRemote("UsePowerUp")
	self.RaycastParams = RaycastParams.new()
	self.RaycastParams.FilterType = Enum.RaycastFilterType.Exclude
	self.RaycastParams.CollisionGroup = "Runner"
	pcall(function()
		self.RaycastParams.RespectCanCollide = true
	end)
end

function PowerUpService:Start()
	Remotes.UsePowerUp.OnServerEvent:Connect(function(player)
		if not self.Limiter:Check(player) then
			return
		end
		self:_use(player)
	end)
	Players.PlayerAdded:Connect(function(player)
		player:SetAttribute("HeldItem", "")
	end)
	for _, player in Players:GetPlayers() do
		player:SetAttribute("HeldItem", "")
	end
end

function PowerUpService:OnPlayerRemoving(player: Player)
	self.LastUse[player] = nil
	for i = #self.Traps, 1, -1 do
		if self.Traps[i].Owner == player then
			self.Traps[i].Part:Destroy()
			table.remove(self.Traps, i)
		end
	end
end

------------------------------------------------------------------------
-- Boxen
------------------------------------------------------------------------

local function makeBox(position: Vector3, parent: Instance, accent: Color3): BasePart
	local box = Instance.new("Part")
	box.Name = "ItemBox"
	box.Size = Vector3.new(2.6, 2.6, 2.6)
	box.CFrame = CFrame.new(position) * CFrame.Angles(math.rad(45), 0, math.rad(45))
	box.Anchored = true
	box.CanCollide = false
	box.CanQuery = false
	box.CanTouch = false
	box.CastShadow = false
	box.Material = Enum.Material.Glass
	box.Transparency = 0.3
	box.Color = accent
	box:SetAttribute("Active", true)
	box:SetAttribute("BasePosition", position)

	local core = Instance.new("Part")
	core.Name = "Core"
	core.Size = Vector3.new(1.3, 1.3, 1.3)
	core.CFrame = box.CFrame
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.CanTouch = false
	core.CastShadow = false
	core.Material = Enum.Material.Neon
	core.Color = Color3.fromRGB(255, 255, 255)
	core.Parent = box

	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromScale(3, 3)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 120
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.Text = "?"
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.3
	label.Parent = gui
	gui.Parent = box

	CollectionService:AddTag(box, "PowerUpBox")
	box.Parent = parent
	return box
end

local function setBoxActive(box: BasePart, active: boolean)
	box:SetAttribute("Active", active)
	box.Transparency = if active then 0.3 else 1
	local core = box:FindFirstChild("Core")
	if core then
		core.Transparency = if active then 0 else 1
	end
	local gui = box:FindFirstChild("Label")
	if gui then
		gui.Enabled = active
	end
end

function PowerUpService:RegisterRegion(instance)
	if instance.RegionId == "Lobby" then
		return
	end
	local accent = instance.Definition and instance.Definition.Theme.Accent or Color3.fromRGB(0, 214, 255)
	for _, position in instance.PickupSpawns do
		local part = makeBox(position, instance.PickupFolder, accent)
		table.insert(self.Boxes, { Part = part, Region = instance.RegionId, Active = true, RespawnAt = 0 })
	end
end

function PowerUpService:UnregisterRegion(regionId: string)
	for i = #self.Boxes, 1, -1 do
		if self.Boxes[i].Region == regionId then
			table.remove(self.Boxes, i)
		end
	end
	self:_clearTraps(regionId)
end

function PowerUpService:ResetRegion(regionId: string)
	for _, box in self.Boxes do
		if box.Region == regionId then
			box.Active = true
			setBoxActive(box.Part, true)
		end
	end
	self:_clearTraps(regionId)
end

function PowerUpService:_clearTraps(regionId: string?)
	for i = #self.Traps, 1, -1 do
		local trap = self.Traps[i]
		if regionId == nil or trap.Region == regionId then
			if trap.Part then
				trap.Part:Destroy()
			end
			table.remove(self.Traps, i)
		end
	end
end

------------------------------------------------------------------------
-- Items
------------------------------------------------------------------------

function PowerUpService:GiveItem(player: Player, itemId: string)
	if not ItemDefinitions.Get(itemId) then
		return
	end
	player:SetAttribute("HeldItem", itemId)
end

function PowerUpService:ClearPlayer(player: Player)
	player:SetAttribute("HeldItem", "")
	for i = #self.Traps, 1, -1 do
		if self.Traps[i].Owner == player then
			self.Traps[i].Part:Destroy()
			table.remove(self.Traps, i)
		end
	end
end

--- Darf der Spieler in seiner aktuellen Region Items sammeln/benutzen?
function PowerUpService:_canUseItems(player: Player, region: string): boolean
	local services = self.Services
	if region == "Race" then
		return services.RoundService:IsActiveRacer(player) and services.RoundService:GetPhase() == "Racing"
	end
	return region ~= "Lobby"
end

function PowerUpService:_rollItem(player: Player, region: string): string
	local bucket = "Front"
	if region == "Race" then
		local placement, alive = self.Services.RoundService:GetPlacementInfo(player)
		if placement and alive then
			if placement == 1 then
				bucket = "Leader"
			elseif placement > math.ceil(alive / 2) then
				bucket = "Back"
			end
		end
	end
	return Util.WeightedPick(ItemDefinitions.GetWeightedList(bucket), self.Rng) or "SpeedBoost"
end

function PowerUpService:Tick(_dt: number)
	local services = self.Services
	local now = os.clock()
	local serverNow = workspace:GetServerTimeNow()

	-- Boxen respawnen
	for _, box in self.Boxes do
		if not box.Active and now >= box.RespawnAt then
			box.Active = true
			setBoxActive(box.Part, true)
		end
	end

	-- Aufsammeln
	local radius = Config.PowerUps.PickupRadius
	for _, player in Players:GetPlayers() do
		local root = services.CharacterService:GetRoot(player)
		if root and player:GetAttribute("HeldItem") == "" then
			local region = services.CharacterService:GetRegion(player)
			if self:_canUseItems(player, region) then
				local position = root.Position
				for _, box in self.Boxes do
					if box.Active and box.Region == region and (box.Part.Position - position).Magnitude <= radius then
						box.Active = false
						box.RespawnAt = now + Config.PowerUps.RespawnTime
						setBoxActive(box.Part, false)
						local itemId = self:_rollItem(player, region)
						self:GiveItem(player, itemId)
						Remotes.GameEvent:FireClient(player, "ItemPickup", { ItemId = itemId, Position = box.Part.Position })
						break
					end
				end
			end
		end
	end

	-- Fallen
	for i = #self.Traps, 1, -1 do
		local trap = self.Traps[i]
		if serverNow >= trap.ExpiresAt or not trap.Part.Parent then
			trap.Part:Destroy()
			table.remove(self.Traps, i)
		elseif serverNow >= trap.ArmedAt then
			local triggered = false
			for _, player in Players:GetPlayers() do
				if player ~= trap.Owner and services.CharacterService:GetRegion(player) == trap.Region then
					local root = services.CharacterService:GetRoot(player)
					if root and (root.Position - trap.Part.Position).Magnitude <= ItemDefinitions.Items.Trap.TriggerRadius + 1.5 then
						self:_applyStatus(player, "Stunned", ItemDefinitions.Items.Trap.StunDuration)
						triggered = true
						break
					end
				end
			end
			if triggered then
				trap.Part:Destroy()
				table.remove(self.Traps, i)
			end
		end
	end
end

--- Wendet einen negativen Status an, sofern kein Schild aktiv ist.
function PowerUpService:_applyStatus(player: Player, kind: string, duration: number): boolean
	local character = player.Character
	if not character then
		return false
	end
	local now = workspace:GetServerTimeNow()
	local root = self.Services.CharacterService:GetRoot(player)
	if (character:GetAttribute("ShieldUntil") or 0) > now then
		character:SetAttribute("ShieldUntil", 0)
		Remotes.GameEvent:FireAllClients("ShieldBlocked", {
			UserId = player.UserId,
			Position = if root then root.Position else Vector3.zero,
		})
		return false
	end
	if kind == "Stunned" then
		character:SetAttribute("StunnedUntil", now + duration)
		self.Services.GrappleService:Release(player, true)
	elseif kind == "Slowed" then
		character:SetAttribute("SlowedUntil", now + duration)
	end
	Remotes.GameEvent:FireAllClients("StatusApplied", {
		UserId = player.UserId,
		Kind = kind,
		Duration = duration,
		Position = if root then root.Position else Vector3.zero,
	})
	return true
end

------------------------------------------------------------------------
-- Benutzen
------------------------------------------------------------------------

function PowerUpService:_use(player: Player)
	local itemId = player:GetAttribute("HeldItem")
	if type(itemId) ~= "string" or itemId == "" then
		return
	end
	local item = ItemDefinitions.Get(itemId)
	if not item then
		player:SetAttribute("HeldItem", "")
		return
	end
	local last = self.LastUse[player]
	if last and os.clock() - last < Config.PowerUps.UseDebounce then
		return
	end
	local services = self.Services
	local character = player.Character
	local root = services.CharacterService:GetRoot(player)
	if not character or not root or character:GetAttribute("Frozen") then
		return
	end
	local now = workspace:GetServerTimeNow()
	if (character:GetAttribute("StunnedUntil") or 0) > now then
		return
	end
	local region = services.CharacterService:GetRegion(player)
	if not self:_canUseItems(player, region) then
		return
	end

	self.LastUse[player] = os.clock()
	-- Item zuerst entfernen: schützt vor doppelter Verwendung
	player:SetAttribute("HeldItem", "")

	local handler = self["_item" .. itemId]
	local ok, consumed, extra = pcall(handler, self, player, character, root, region, item, now)
	if not ok then
		warn("[PowerUpService] Fehler bei " .. itemId .. ": " .. tostring(consumed))
		consumed = false
	end
	if consumed == false then
		-- Nicht verbraucht (z.B. kein Teleportziel): Item zurückgeben
		player:SetAttribute("HeldItem", itemId)
		if type(extra) == "string" then
			Remotes.GameEvent:FireClient(player, "Notify", { Text = extra, Kind = "Warning" })
		end
		return
	end
	local payload = { UserId = player.UserId, ItemId = itemId, Position = root.Position }
	if type(extra) == "table" then
		for key, value in extra do
			payload[key] = value
		end
	end
	Remotes.GameEvent:FireAllClients("PowerUpUsed", payload)
	services.RewardService:OnPowerUpUsed(player, region == "Race")
end

function PowerUpService:_itemSpeedBoost(_player, character, _root, _region, item, now)
	character:SetAttribute("BoostUntil", now + item.Duration)
	return true
end

function PowerUpService:_itemShield(_player, character, _root, _region, item, now)
	character:SetAttribute("ShieldUntil", now + item.Duration)
	return true
end

function PowerUpService:_itemGrappleUpgrade(_player, character, _root, _region, item, now)
	character:SetAttribute("GrappleBoostUntil", now + item.Duration)
	return true
end

function PowerUpService:_itemFreezeBurst(player, _character, root, region, item, _now)
	local hit = 0
	if region == "Race" then
		for _, other in Players:GetPlayers() do
			if other ~= player and self.Services.RoundService:IsActiveRacer(other) then
				local otherRoot = self.Services.CharacterService:GetRoot(other)
				if otherRoot and (otherRoot.Position - root.Position).Magnitude <= item.Radius then
					if self:_applyStatus(other, "Slowed", item.Duration) then
						hit += 1
					end
				end
			end
		end
	end
	return true, { Radius = item.Radius, Hits = hit }
end

function PowerUpService:_itemTeleportBeacon(player, _character, root, region, item, _now)
	local instance = self.Services.MapService:GetRegion(region)
	if not instance then
		return false, "Teleport hier nicht möglich."
	end
	local position = root.Position
	local best = nil
	for _, node in instance.TeleportNodes do
		local dx = node.X - position.X
		if dx >= item.MinDistance and dx <= item.Range and math.abs(node.Y - position.Y) <= 40 then
			if not instance.FinishX or node.X < instance.FinishX - 6 then
				if not best or node.X > best.X then
					best = node
				end
			end
		end
	end
	if not best then
		return false, "Kein sicheres Teleportziel in Reichweite."
	end
	local from = position
	self.Services.CharacterService:Teleport(player, CFrame.lookAt(best, best + Vector3.new(1, 0, 0)))
	return true, { From = from, To = best }
end

function PowerUpService:_itemTrap(player, _character, root, region, item, now)
	local instance = self.Services.MapService:GetRegion(region)
	if not instance then
		return false, "Falle hier nicht möglich."
	end
	-- Alte Falle des Spielers entfernen (max. eine pro Spieler)
	for i = #self.Traps, 1, -1 do
		if self.Traps[i].Owner == player then
			self.Traps[i].Part:Destroy()
			table.remove(self.Traps, i)
		end
	end
	self.RaycastParams.FilterDescendantsInstances = { player.Character }
	local result = workspace:Raycast(root.Position, Vector3.new(0, -14, 0), self.RaycastParams)
	local groundY = if result then result.Position.Y else root.Position.Y + Config.Character.FeetOffset
	local position = Vector3.new(root.Position.X, groundY + 0.4, 0)

	local trap = Instance.new("Part")
	trap.Name = "Trap"
	trap.Size = Vector3.new(3.2, 0.8, 3.2)
	trap.CFrame = CFrame.new(position)
	trap.Anchored = true
	trap.CanCollide = false
	trap.CanQuery = false
	trap.CanTouch = false
	trap.Material = Enum.Material.Neon
	trap.Color = item.Color
	trap:SetAttribute("Owner", player.UserId)
	for i = -1, 1 do
		local spike = Instance.new("WedgePart")
		spike.Name = "Spike"
		spike.Size = Vector3.new(0.6, 0.9, 0.6)
		spike.CFrame = CFrame.new(position + Vector3.new(i * 1, 0.85, 0))
		spike.Anchored = true
		spike.CanCollide = false
		spike.CanQuery = false
		spike.CanTouch = false
		spike.Material = Enum.Material.Metal
		spike.Color = Color3.fromRGB(60, 60, 70)
		spike.Parent = trap
	end
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(2.5, 2.5)
	gui.StudsOffset = Vector3.new(0, 2.5, 0)
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.Text = "!"
	label.TextScaled = true
	label.TextColor3 = item.Color
	label.TextStrokeTransparency = 0.2
	label.Parent = gui
	gui.Parent = trap
	trap.Parent = instance.RuntimeFolder

	table.insert(self.Traps, {
		Part = trap,
		Owner = player,
		Region = region,
		ExpiresAt = now + item.Lifetime,
		ArmedAt = now + 0.4,
	})
	return true, { TrapPosition = position }
end

return PowerUpService
