--[[
	ClientState  (ModuleScript)
	Pfad: StarterPlayer/StarterPlayerScripts/Client/Controllers/ClientState

	Zentrale Datenquelle des Clients:
		- Profil-Schnappschuss vom Server (nur lesend; Änderungen nur über Remotes)
		- Zugriff auf ReplicatedStorage/GameState
		- Verteilung der Server-Events (GameEvent) an beliebig viele Listener

	API:
		ClientState.Profile                   (table | nil)
		ClientState.ProfileChanged            (Signal: profile)
		ClientState:On(eventName, fn)         -> Connection
		ClientState:GetPhase() -> string
		ClientState:IsInRace() -> boolean
		ClientState:GetPracticeCourse() -> string
		ClientState:GetRegionDefinition() -> MapDefinition
		ClientState:GetSetting(key) -> any
		ClientState:SaveSettings(changes)
		ClientState.SettingsChanged           (Signal: settings)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Signal)
local Remotes = require(Shared.Remotes)
local MapDefinitions = require(Shared.MapDefinitions)

local player = Players.LocalPlayer

local ClientState = {}
ClientState.Profile = nil
ClientState.ProfileChanged = Signal.new()
ClientState.SettingsChanged = Signal.new()
ClientState.GameState = ReplicatedStorage:WaitForChild("GameState")
ClientState.Racers = ClientState.GameState:WaitForChild("Racers")

local events = {}

local DEFAULT_SETTINGS = {
	MusicVolume = 0.5,
	SfxVolume = 0.8,
	CameraShake = true,
	GamepadSensitivity = 1,
	TouchControls = true,
	AutoRequeue = true,
	ReducedEffects = false,
}

function ClientState:Init(_ctx)
	Remotes.GameEvent.OnClientEvent:Connect(function(name, payload)
		local signal = events[name]
		if signal then
			signal:Fire(payload or {})
		end
	end)
	Remotes.ProfileUpdate.OnClientEvent:Connect(function(snapshot)
		self:_setProfile(snapshot)
	end)
	task.spawn(function()
		for _ = 1, 5 do
			local ok, snapshot = pcall(function()
				return Remotes.GetProfile:InvokeServer()
			end)
			if ok and snapshot then
				if not self.Profile then
					self:_setProfile(snapshot)
				end
				return
			end
			task.wait(2)
		end
	end)
end

function ClientState:_setProfile(snapshot)
	if type(snapshot) ~= "table" then
		return
	end
	self.Profile = snapshot
	self.ProfileChanged:Fire(snapshot)
	self.SettingsChanged:Fire(self:GetSettings())
end

--- Registriert einen Listener für ein Server-Event (GameEvent).
function ClientState:On(name: string, fn: (any) -> ())
	local signal = events[name]
	if not signal then
		signal = Signal.new()
		events[name] = signal
	end
	return signal:Connect(fn)
end

function ClientState:GetPhase(): string
	return self.GameState:GetAttribute("Phase") or "Waiting"
end

function ClientState:IsInRace(): boolean
	return player:GetAttribute("InRace") == true
end

function ClientState:GetPracticeCourse(): string
	return player:GetAttribute("PracticeCourse") or ""
end

--- Map-Definition der Region, in der sich der lokale Spieler befindet.
function ClientState:GetRegionDefinition()
	if self:IsInRace() then
		local mapId = self.GameState:GetAttribute("MapId")
		local definition = mapId and MapDefinitions.Get(mapId)
		if definition then
			return definition
		end
	end
	local course = self:GetPracticeCourse()
	if course ~= "" then
		local definition = MapDefinitions.GetAny(course)
		if definition then
			return definition
		end
	end
	return MapDefinitions.Lobby
end

function ClientState:GetSettings()
	local settings = table.clone(DEFAULT_SETTINGS)
	if self.Profile and self.Profile.Settings then
		for key, value in self.Profile.Settings do
			settings[key] = value
		end
	end
	return settings
end

function ClientState:GetSetting(key: string)
	return self:GetSettings()[key]
end

local pendingSave = nil

--- Übernimmt Einstellungen lokal sofort und speichert sie gebündelt auf dem Server.
function ClientState:SaveSettings(changes)
	if self.Profile then
		self.Profile.Settings = self.Profile.Settings or {}
		for key, value in changes do
			self.Profile.Settings[key] = value
		end
	end
	self.SettingsChanged:Fire(self:GetSettings())
	if pendingSave then
		return
	end
	pendingSave = true
	task.delay(1.5, function()
		pendingSave = nil
		Remotes.SaveSettings:FireServer(self:GetSettings())
	end)
end

return ClientState
