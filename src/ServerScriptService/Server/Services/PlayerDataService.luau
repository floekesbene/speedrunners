--[[
	PlayerDataService  (ModuleScript)
	Pfad: ServerScriptService/Server/Services/PlayerDataService

	Lädt und speichert Spielerprofile mit DataStoreService.

	- UpdateAsync mit einfachem Session-Lock (verhindert, dass zwei Server
	  gleichzeitig dasselbe Profil überschreiben).
	- Wiederholungsversuche mit exponentiellem Backoff.
	- Autosave alle Config.Data.AutosaveInterval Sekunden (nur wenn geändert).
	- Speichern beim Verlassen und beim Herunterfahren (BindToClose).
	- In Studio ohne API-Zugriff: Profile nur im Speicher (Hinweis an Spieler).
	- Profile werden nie pro Frame gespeichert.

	Öffentliche API:
		:GetProfile(player) -> table?        Live-Profil (nur serverseitig ändern!)
		:WaitForProfile(player, timeout) -> table?
		:MarkDirty(player)                   Änderungen zum Speichern vormerken
		:PushProfile(player)                 Schnappschuss an den Client senden
		:IsPersistent() -> boolean           false = Studio-Speichermodus
		:Release(player)                     Speichern + Freigeben beim Verlassen
		.ProfileLoaded (Signal: player, profile)
		.ProfileReleasing (Signal: player, profile)
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Signal = require(Shared.Signal)
local Remotes = require(Shared.Remotes)
local CosmeticDefinitions = require(Shared.CosmeticDefinitions)

local RateLimiter = require(script.Parent.Parent.Modules.RateLimiter)

local PlayerDataService = {}
PlayerDataService.ProfileLoaded = Signal.new()
PlayerDataService.ProfileReleasing = Signal.new()

local SCHEMA_VERSION = 1

local function defaultOwned()
	local owned = {}
	for _, category in CosmeticDefinitions.Categories do
		owned[category] = {}
		for _, item in CosmeticDefinitions.Items[category] do
			if item.Default then
				owned[category][item.Id] = true
			end
		end
	end
	return owned
end

local function buildTemplate()
	return {
		Version = SCHEMA_VERSION,
		Coins = Config.Economy.StartingCoins,
		TotalXP = 0,
		Level = 1,
		Stats = {
			Races = 0,
			Wins = 0,
			Top3 = 0,
			Finishes = 0,
			Eliminated = 0,
			Grapples = 0,
			PowerUps = 0,
			Distance = 0,
			FlawlessWins = 0,
			BestTimes = {},
		},
		Ranked = {
			Rating = Config.Ranked.StartRating,
			Season = Config.Ranked.Season,
			Games = 0,
			Wins = 0,
			Peak = Config.Ranked.StartRating,
		},
		Owned = defaultOwned(),
		Equipped = Util.DeepCopy(CosmeticDefinitions.DefaultEquipped),
		Quests = { Day = 0, List = {} },
		Achievements = {},
		Settings = {
			MusicVolume = 0.5,
			SfxVolume = 0.8,
			CameraShake = true,
			GamepadSensitivity = 1,
			TouchControls = true,
			AutoRequeue = true,
			ReducedEffects = false,
		},
		RecentMatches = {},
		CreatedAt = os.time(),
		LastJoin = os.time(),
	}
end

PlayerDataService.Template = buildTemplate()

--- Migration älterer Profile (Platz für zukünftige Schema-Versionen).
local function migrate(data)
	data.Version = data.Version or 1
	-- Beispiel: if data.Version < 2 then ... data.Version = 2 end
	Util.Reconcile(data, PlayerDataService.Template)
	for _, category in CosmeticDefinitions.Categories do
		if type(data.Owned[category]) ~= "table" then
			data.Owned[category] = {}
		end
		if type(data.Equipped[category]) ~= "string" then
			data.Equipped[category] = CosmeticDefinitions.DefaultEquipped[category]
		end
		for _, item in CosmeticDefinitions.Items[category] do
			if item.Default then
				data.Owned[category][item.Id] = true
			end
		end
	end
	return data
end

function PlayerDataService:Init(services)
	self.Services = services
	self.Profiles = {} -- [player] = { Data, Dirty, Key, Loaded }
	self.Persistent = true
	self.Store = nil
	self.ShuttingDown = false
	self.PushQueued = {}
	self.SettingsLimiter = RateLimiter.ForRemote("SaveSettings")
	self.GetLimiter = RateLimiter.ForRemote("GetProfile")

	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(Config.Data.StoreName)
	end)
	if ok then
		self.Store = store
		-- Studio ohne API-Zugriff erkennen
		local probeOk, probeErr = pcall(function()
			store:GetAsync("__probe")
		end)
		if not probeOk then
			local message = tostring(probeErr)
			if Config.IsStudio or message:find("403") or message:find("Studio") or message:find("API") then
				warn("[PlayerDataService] DataStore nicht verfügbar – Profile werden nur im Speicher gehalten: " .. message)
				self.Persistent = false
			end
		end
	else
		warn("[PlayerDataService] GetDataStore fehlgeschlagen: " .. tostring(store))
		self.Persistent = false
	end
end

function PlayerDataService:Start()
	Players.PlayerAdded:Connect(function(player)
		self:_load(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			self:_load(player)
		end)
	end
	Remotes.GetProfile.OnServerInvoke = function(player)
		if not self.GetLimiter:Check(player) then
			return nil
		end
		local profile = self:WaitForProfile(player, 15)
		if not profile then
			return nil
		end
		return self:_snapshot(player, profile)
	end

	Remotes.SaveSettings.OnServerEvent:Connect(function(player, settings)
		if not self.SettingsLimiter:Check(player) then
			return
		end
		self:_saveSettings(player, settings)
	end)

	task.spawn(function()
		while true do
			task.wait(Config.Data.AutosaveInterval)
			for player, entry in self.Profiles do
				if entry.Loaded and player.Parent then
					task.spawn(function()
						self:_save(player, false)
					end)
				end
			end
		end
	end)

	game:BindToClose(function()
		self.ShuttingDown = true
		local pending = 0
		for player, entry in self.Profiles do
			if entry.Loaded then
				pending += 1
				task.spawn(function()
					self:_save(player, true)
					pending -= 1
				end)
			end
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.2)
		end
	end)
end

------------------------------------------------------------------------
-- Öffentliche API
------------------------------------------------------------------------

function PlayerDataService:GetProfile(player: Player)
	local entry = self.Profiles[player]
	if entry and entry.Loaded then
		return entry.Data
	end
	return nil
end

function PlayerDataService:WaitForProfile(player: Player, timeout: number?)
	local deadline = os.clock() + (timeout or 20)
	while player.Parent and os.clock() < deadline do
		local profile = self:GetProfile(player)
		if profile then
			return profile
		end
		task.wait(0.1)
	end
	return self:GetProfile(player)
end

function PlayerDataService:MarkDirty(player: Player)
	local entry = self.Profiles[player]
	if entry then
		entry.Dirty = true
	end
end

function PlayerDataService:IsPersistent(): boolean
	return self.Persistent
end

--- Sendet einen Profil-Schnappschuss an den Client (mehrere Aufrufe werden gebündelt).
function PlayerDataService:PushProfile(player: Player)
	if self.PushQueued[player] then
		return
	end
	self.PushQueued[player] = true
	task.delay(0.15, function()
		self.PushQueued[player] = nil
		local profile = self:GetProfile(player)
		if profile and player.Parent then
			Remotes.ProfileUpdate:FireClient(player, self:_snapshot(player, profile))
		end
	end)
end

------------------------------------------------------------------------
-- Intern
------------------------------------------------------------------------

function PlayerDataService:_snapshot(_player: Player, profile)
	local snapshot = Util.DeepCopy(profile)
	snapshot.RecentMatches = nil
	snapshot._Lock = nil
	snapshot.Persistent = self.Persistent
	return snapshot
end

function PlayerDataService:_key(player: Player): string
	return Config.Data.KeyPrefix .. tostring(player.UserId)
end

function PlayerDataService:_load(player: Player)
	if self.Profiles[player] then
		return
	end
	local entry = { Data = nil, Dirty = false, Loaded = false, Key = self:_key(player) }
	self.Profiles[player] = entry

	local data
	if self.Persistent then
		data = self:_loadFromStore(player, entry.Key)
		if data == nil then
			if player.Parent then
				player:Kick("Deine Spieldaten konnten nicht geladen werden. Bitte versuche es gleich noch einmal.")
			end
			self.Profiles[player] = nil
			return
		end
	else
		data = buildTemplate()
	end

	if not player.Parent then
		-- Spieler hat während des Ladens verlassen: Lock freigeben, nichts behalten.
		if self.Persistent then
			entry.Data = data
			entry.Loaded = true
			self:_save(player, true)
		end
		self.Profiles[player] = nil
		return
	end

	data = migrate(data)
	data.LastJoin = os.time()
	entry.Data = data
	entry.Loaded = true
	entry.Dirty = true
	self.ProfileLoaded:Fire(player, data)
	self:PushProfile(player)
	if not self.Persistent then
		task.delay(4, function()
			if player.Parent then
				Remotes.GameEvent:FireClient(player, "Notify", {
					Text = "Studio-Modus: Fortschritt wird nicht gespeichert (API-Zugriff deaktiviert).",
					Kind = "Warning",
				})
			end
		end)
	end
end

function PlayerDataService:_loadFromStore(player: Player, key: string)
	local jobId = game.JobId
	for attempt = 1, Config.Data.LoadRetries do
		local locked = false
		local ok, result = pcall(function()
			return self.Store:UpdateAsync(key, function(old)
				locked = false
				local data = old
				if type(data) ~= "table" then
					data = buildTemplate()
				end
				local lock = data._Lock
				if
					type(lock) == "table"
					and lock.Job ~= jobId
					and type(lock.Time) == "number"
					and os.time() - lock.Time < Config.Data.LockTimeout
					and attempt < Config.Data.LoadRetries
				then
					locked = true
					return nil -- Update abbrechen, anderer Server hält das Profil
				end
				data._Lock = { Job = jobId, Time = os.time() }
				return data
			end)
		end)
		if ok and not locked and type(result) == "table" then
			result._Lock = nil
			return result
		end
		if not ok then
			warn(string.format("[PlayerDataService] Laden fehlgeschlagen (%s, Versuch %d): %s", player.Name, attempt, tostring(result)))
		end
		if not player.Parent then
			return nil
		end
		task.wait(math.min(2 ^ attempt, 12))
	end
	return nil
end

function PlayerDataService:_save(player: Player, release: boolean)
	local entry = self.Profiles[player]
	if not entry or not entry.Loaded or not entry.Data then
		return
	end
	if not self.Persistent then
		entry.Dirty = false
		return
	end
	if not entry.Dirty and not release then
		-- Nur den Lock auffrischen, wenn nichts geändert wurde, ist nicht nötig:
		-- der Lock gilt Config.Data.LockTimeout Sekunden.
		return
	end
	if entry.Saving then
		-- Laufende Speicherung abwarten, dann ggf. erneut speichern.
		local deadline = os.clock() + 15
		while entry.Saving and os.clock() < deadline do
			task.wait(0.1)
		end
	end
	entry.Saving = true
	entry.Dirty = false
	local data = Util.DeepCopy(entry.Data)
	local jobId = game.JobId
	if release then
		data._Lock = nil
	else
		data._Lock = { Job = jobId, Time = os.time() }
	end

	local success = false
	for attempt = 1, Config.Data.SaveRetries do
		local ok, err = pcall(function()
			self.Store:UpdateAsync(entry.Key, function(old)
				if type(old) == "table" and type(old._Lock) == "table" and old._Lock.Job ~= jobId then
					-- Ein anderer Server hat das Profil übernommen: nicht überschreiben.
					return nil
				end
				return data
			end)
		end)
		if ok then
			success = true
			break
		end
		warn(string.format("[PlayerDataService] Speichern fehlgeschlagen (%s, Versuch %d): %s", player.Name, attempt, tostring(err)))
		task.wait(math.min(2 ^ attempt, 8))
	end
	if not success then
		entry.Dirty = true
	end
	entry.Saving = false
end

--- Speichert und gibt das Profil frei. Wird von Bootstrap beim Verlassen
--- als letzter Schritt aufgerufen (nachdem alle Services aufgeräumt haben).
function PlayerDataService:Release(player: Player)
	local entry = self.Profiles[player]
	if not entry then
		return
	end
	if entry.Loaded then
		self.ProfileReleasing:Fire(player, entry.Data)
		self:_save(player, true)
	end
	self.Profiles[player] = nil
	self.PushQueued[player] = nil
end

local SETTING_RULES = {
	MusicVolume = { Type = "number", Min = 0, Max = 1 },
	SfxVolume = { Type = "number", Min = 0, Max = 1 },
	GamepadSensitivity = { Type = "number", Min = 0.3, Max = 2.5 },
	CameraShake = { Type = "boolean" },
	TouchControls = { Type = "boolean" },
	AutoRequeue = { Type = "boolean" },
	ReducedEffects = { Type = "boolean" },
}

function PlayerDataService:_saveSettings(player: Player, settings)
	local profile = self:GetProfile(player)
	if not profile or type(settings) ~= "table" then
		return
	end
	for key, rule in SETTING_RULES do
		local value = settings[key]
		if type(value) == rule.Type then
			if rule.Type == "number" then
				if value == value then -- NaN ausschließen
					profile.Settings[key] = math.clamp(value, rule.Min, rule.Max)
				end
			else
				profile.Settings[key] = value
			end
		end
	end
	self:MarkDirty(player)
	self:PushProfile(player)
end

return PlayerDataService
