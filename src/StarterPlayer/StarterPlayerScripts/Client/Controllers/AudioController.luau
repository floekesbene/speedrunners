--[[
	AudioController  (ModuleScript)
	Pfad: StarterPlayer/StarterPlayerScripts/Client/Controllers/AudioController

	Spielt Soundeffekte und optionale Musik. Standardmäßig werden nur in Roblox
	eingebaute Sounddateien (rbxasset://sounds/...) genutzt, siehe Config.Audio.
	Fehlt ein Sound, läuft das Spiel normal weiter (rein optional).

	Lautstärken kommen aus den Spieler-Einstellungen (SfxVolume, MusicVolume).

	API:
		:Play(name, options?)   options: { Volume, Pitch, Position }
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local player = Players.LocalPlayer

local AudioController = {}

function AudioController:Init(ctx)
	self.Ctx = ctx
	self.Templates = {}
	self.LastPlayed = {}

	self.SfxGroup = Instance.new("SoundGroup")
	self.SfxGroup.Name = "VR_SFX"
	self.SfxGroup.Parent = SoundService
	self.MusicGroup = Instance.new("SoundGroup")
	self.MusicGroup.Name = "VR_Music"
	self.MusicGroup.Parent = SoundService

	for name, def in Config.Audio.Sounds do
		local sound = Instance.new("Sound")
		sound.Name = "VR_" .. name
		sound.SoundId = def.Id
		sound.Volume = def.Volume or 0.5
		sound.PlaybackSpeed = def.Pitch or 1
		sound.SoundGroup = self.SfxGroup
		sound.Parent = SoundService
		self.Templates[name] = sound
	end

	if Config.Audio.MusicId ~= "" then
		local music = Instance.new("Sound")
		music.Name = "VR_MusicTrack"
		music.SoundId = Config.Audio.MusicId
		music.Looped = true
		music.Volume = 0.4
		music.SoundGroup = self.MusicGroup
		music.Parent = SoundService
		self.Music = music
	end
end

function AudioController:Start()
	local state = self.Ctx.ClientState
	local function applyVolumes(settings)
		self.SfxGroup.Volume = settings.SfxVolume or 0.8
		self.MusicGroup.Volume = settings.MusicVolume or 0.5
	end
	applyVolumes(state:GetSettings())
	state.SettingsChanged:Connect(applyVolumes)
	if self.Music then
		self.Music:Play()
	end

	local movement = self.Ctx.MovementController
	movement.Jumped:Connect(function(kind)
		if kind == "WallJump" then
			self:Play("WallJump")
		elseif kind == "Pad" then
			self:Play("Boost", { Pitch = 1.2 })
		else
			self:Play("Jump")
		end
	end)
	movement.Landed:Connect(function(impact)
		self:Play("Land", { Volume = math.clamp(impact / 120, 0.2, 0.7) })
	end)
	movement.SlideStarted:Connect(function()
		self:Play("Slide")
	end)
	movement.DashStarted:Connect(function()
		self:Play("Dash")
	end)
	movement.GrappleStarted:Connect(function()
		self:Play("Grapple")
	end)
	movement.BoostPad:Connect(function()
		self:Play("Boost")
	end)

	state:On("ItemPickup", function()
		self:Play("Pickup")
	end)
	state:On("PowerUpUsed", function(payload)
		if payload.UserId == player.UserId then
			self:Play("PowerUp")
		end
	end)
	state:On("RacerEliminated", function(payload)
		self:Play("Eliminated", { Volume = if payload.UserId == player.UserId then 0.8 else 0.35 })
	end)
	state:On("RacerRespawn", function(payload)
		if payload.UserId == player.UserId then
			self:Play("Splash", { Pitch = 1.4 })
		end
	end)
	state:On("MatchResults", function(payload)
		if payload.WinnerUserId == player.UserId then
			self:Play("Victory")
		end
	end)
end

function AudioController:Play(name: string, options)
	local template = self.Templates[name]
	if not template then
		return
	end
	-- Gleichen Sound nicht öfter als alle 50 ms starten
	local now = os.clock()
	if self.LastPlayed[name] and now - self.LastPlayed[name] < 0.05 then
		return
	end
	self.LastPlayed[name] = now
	local sound = template:Clone()
	if options then
		if options.Volume then
			sound.Volume = options.Volume
		end
		if options.Pitch then
			sound.PlaybackSpeed = options.Pitch
		end
	end
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(6, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

return AudioController
