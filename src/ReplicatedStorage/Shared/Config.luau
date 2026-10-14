--[[
	Config  (ModuleScript)
	Pfad: ReplicatedStorage/Shared/Config

	Zentrale Konfiguration für Velocity Rush. Alle Balancing-Werte für Movement,
	Greifhaken, Gefahrenzone, Runden, Ökonomie, Ranked und Anti-Exploit stehen hier.
	Server und Client lesen dieselben Werte, damit Vorhersage (Client) und
	Validierung (Server) zusammenpassen.

	Einheiten: Studs, Sekunden, Studs/Sekunde.
]]

local RunService = game:GetService("RunService")

local Config = {}

Config.GameName = "Velocity Rush"
Config.Version = "1.0.0"
Config.IsStudio = RunService:IsStudio()

Config.Debug = {
	-- In Roblox Studio darf ein Rennen auch mit nur einem Spieler starten (zum Testen).
	AllowSoloRace = RunService:IsStudio(),
	-- Abgelehnte Remote-Aufrufe im Output protokollieren.
	LogRejections = RunService:IsStudio(),
}

Config.World = {
	Gravity = 200,
	PlaneZ = 0,
	TrackDepth = 10,
	LobbyOrigin = Vector3.new(-3000, 0, 0),
	RaceOrigin = Vector3.new(0, 0, 0),
	TutorialOrigin = Vector3.new(-10000, 0, 0),
	PracticeOriginStart = Vector3.new(-20000, 0, 0),
	PracticeOriginSpacing = 6000,
}

-- Geometrie der Spielfigur (muss zu Shared/RunnerRig passen).
Config.Character = {
	ColliderWidth = 1.8,
	ColliderDepth = 1.4,
	StandHeight = 5.4,
	SlideHeight = 2.2,
	FeetOffset = -2.7, -- Fußsohle relativ zur Mitte des HumanoidRootPart
}

Config.Movement = {
	MaxRunSpeed = 44,
	GroundAcceleration = 150,
	GroundDeceleration = 190,
	TurnAcceleration = 320,
	AirAcceleration = 95,
	AirTurnAcceleration = 150,
	AirDrag = 8,
	OverspeedGroundDecay = 38,
	OverspeedAirDecay = 7,
	AbsoluteMaxSpeed = 140,
	MaxFallSpeed = 130,

	JumpVelocity = 62,
	JumpCutMultiplier = 0.45,
	FallGravityMultiplier = 1.35,
	CoyoteTime = 0.1,
	JumpBuffer = 0.13,

	WallSlideMaxFall = 22,
	WallJumpVelocityX = 42,
	WallJumpVelocityY = 58,
	WallJumpLockTime = 0.16,

	SlideMinSpeed = 14,
	SlideBoost = 9,
	SlideFriction = 17,
	SlideEndSpeed = 9,
	SlideCooldown = 0.45,
	CrawlSpeed = 12,

	DashSpeed = 72,
	DashDuration = 0.16,
	DashCooldown = 1.1,

	IceAccelerationMultiplier = 0.35,
	IceDecelerationMultiplier = 0.18,

	BoostMultiplier = 1.35,
	BoostImpulse = 22,
	SlowMultiplier = 0.4,

	GroundCheckDistance = 0.3,
	StateSendInterval = 0.08,
}

Config.Grapple = {
	Range = 58,
	UpgradeRangeMultiplier = 1.6,
	UpgradeReelMultiplier = 2,
	MinRopeLength = 10,
	ReelSpeed = 8,
	RopeStiffness = 12,
	MaxCorrectionSpeed = 60,
	SwingAcceleration = 55,
	ReleaseBoost = 8,
	Cooldown = 0.3,
	UpgradeCooldown = 0.05,
	MaxAttachTime = 6,
	MaxAnchorBelow = 8, -- Anker dürfen höchstens so weit unter dem Spieler liegen
	ServerRangeTolerance = 14,
	ServerMinInterval = 0.12,
}

-- Gefahrenzone: eine Energiewand, die dem Führenden in festem Abstand folgt.
Config.HazardZone = {
	WarningStart = 10, -- ab Sekunde X nach Rennstart Warnung
	ShrinkStart = 18, -- ab Sekunde X wird die Zone gefährlich und schrumpft
	ShrinkDuration = 55,
	InitialLength = 260, -- Abstand der Wand zum Führenden zu Beginn
	FinalLength = 60, -- minimaler Abstand im Endzustand
	EliminationDelay = 1.6, -- so lange darf man hinter der Wand sein
	RecoveryRate = 2, -- Abbau der Gefahrenzeit pro Sekunde in Sicherheit
}

Config.Round = {
	MinPlayers = 2,
	MaxPlayers = 8,
	StartingCountdown = 10,
	FullLobbyCountdown = 4,
	CountdownDuration = 3.5,
	MaxRaceTime = 240,
	ResultsDuration = 9,
	RespawnFreezeTime = 0.9,
	ReturnToLobbyDelay = 1.5,
	TickRate = 10,
}

Config.Economy = {
	StartingCoins = 300,
	MaxCoins = 100_000_000,
	MaxTransaction = 1_000_000,
}

Config.Rewards = {
	ParticipationCoins = 20,
	ParticipationXP = 35,
	PlacementCoins = { 60, 35, 20 },
	PlacementXP = { 100, 60, 40 },
	FinishBonusCoins = 15,
	FinishBonusXP = 25,
	FullRewardPlayerCount = 4, -- ab so vielen Teilnehmern volle Platzierungsboni
	LevelUpCoinsPerLevel = 25,
	RecentMatchMemory = 25,
}

Config.Ranked = {
	Season = 1,
	StartRating = 1000,
	KFactor = 40,
	MinRating = 0,
	LeavePenaltyFactor = 1, -- Leaver werden wie Letztplatzierte gewertet
}

Config.PowerUps = {
	PickupRadius = 4.5,
	RespawnTime = 9,
	UseDebounce = 0.4,
}

Config.Practice = {
	RespawnFreezeTime = 0.35,
}

Config.Data = {
	StoreName = "VelocityRush_Profiles_v1",
	KeyPrefix = "Player_",
	AutosaveInterval = 90,
	LockTimeout = 360,
	LoadRetries = 5,
	SaveRetries = 4,
}

Config.Leaderboard = {
	WinsStore = "VelocityRush_Wins_v1",
	RatingStorePrefix = "VelocityRush_Rating_S",
	RefreshInterval = 120,
	Size = 25,
}

Config.AntiExploit = {
	SampleInterval = 0.25,
	Window = 1.0,
	MaxSpeed = 230, -- Studs/s über das Messfenster (legitimes Maximum ≈ 195)
	MaxZDrift = 6,
	TeleportGrace = 1.5,
	ViolationDecayPerSecond = 0.05,
	KickEnabled = true,
	KickThreshold = 12,
}

-- Token-Bucket pro Spieler und Remote: { Kapazität, Nachfüllrate pro Sekunde }
Config.RateLimits = {
	QueueRequest = { 6, 1.5 },
	PracticeRequest = { 6, 1.5 },
	MoveState = { 30, 18 },
	GrappleRequest = { 20, 10 },
	UsePowerUp = { 6, 3 },
	PlayEmote = { 3, 0.7 },
	SaveSettings = { 4, 0.5 },
	RequestRespawn = { 3, 0.5 },
	GetProfile = { 6, 1 },
	ShopRequest = { 10, 3 },
	GetLeaderboard = { 4, 0.5 },
}

-- Seitenkamera (CameraController). Glättung über "SmoothTime" (Sekunden bis
-- das Ziel weitgehend erreicht ist; kleiner = straffer).
Config.Camera = {
	Distance = 45, -- Abstand zur Spielebene (näher = größere Figuren)
	HeightOffset = 7, -- Kamera so viel höher als der Fokus (Blick leicht von oben)
	FocusHeight = 2.2, -- Fokuspunkt über der Körpermitte
	FieldOfView = 57,
	LookAheadFactor = 0.3, -- Vorausschau in Laufrichtung pro Stud/s
	MaxLookAhead = 16,
	LookAheadSmoothTime = 0.42,
	FollowSmoothTime = 0.085, -- horizontale Nachführung
	VerticalSmoothTime = 0.2,
	FallSmoothTime = 0.07, -- schnelles Nachführen beim Fallen
	VerticalDeadZone = 2.5,
	GroundRecenter = 1.6, -- Schärfe, mit der die Kamera am Boden wieder mittig wird
	FallLookDown = 0.08, -- Blick nach unten beim schnellen Fallen (pro Stud/s)
	MaxFallLookDown = 6,
	SpeedZoom = 0.18, -- zusätzlicher Abstand pro Stud/s über MaxRunSpeed
	MaxExtraDistance = 13,
	ZoomSharpness = 1.8,
	SpeedFov = 0.11, -- zusätzliches Sichtfeld pro Stud/s über MaxRunSpeed
	MaxExtraFov = 7,
	FovSharpness = 3.5,
	LeaderBias = 0.25,
	MaxLeaderBias = 18,
	SnapDistance = 120,
	SpectateBlendTime = 0.55, -- weicher Schwenk beim Wechsel des Zuschauerziels
	MaxBlendDistance = 700,
	ShakeFrequency = 17,
	ShakeDecay = 2.6,
	KickStiffness = 170, -- Feder für Kamera-Stöße (Landung)
	KickDamping = 15,
	MaxFovPunch = 10,
}

Config.Input = {
	GamepadDeadzone = 0.2,
	DefaultGamepadSensitivity = 1,
}

-- Sounds: Standardmäßig werden ausschließlich in Roblox eingebaute Sounddateien
-- (rbxasset://sounds/...) verwendet. Eigene Sound-IDs können hier eingetragen werden.
Config.Audio = {
	MusicId = "", -- z.B. "rbxassetid://123456" – leer = keine Musik
	Sounds = {
		Jump = { Id = "rbxasset://sounds/action_jump.mp3", Volume = 0.45, Pitch = 1.1 },
		WallJump = { Id = "rbxasset://sounds/action_jump.mp3", Volume = 0.45, Pitch = 1.3 },
		Land = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 0.5, Pitch = 1 },
		Slide = { Id = "rbxasset://sounds/action_falling.mp3", Volume = 0.25, Pitch = 2.2 },
		Dash = { Id = "rbxasset://sounds/action_falling.mp3", Volume = 0.35, Pitch = 2.8 },
		Grapple = { Id = "rbxasset://sounds/action_get_up.mp3", Volume = 0.55, Pitch = 1.6 },
		Pickup = { Id = "rbxasset://sounds/action_get_up.mp3", Volume = 0.6, Pitch = 2.2 },
		PowerUp = { Id = "rbxasset://sounds/action_jump.mp3", Volume = 0.6, Pitch = 0.7 },
		Boost = { Id = "rbxasset://sounds/action_falling.mp3", Volume = 0.4, Pitch = 1.8 },
		Eliminated = { Id = "rbxasset://sounds/uuhhh.mp3", Volume = 0.6, Pitch = 1 },
		Countdown = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 0.7, Pitch = 2 },
		Go = { Id = "rbxasset://sounds/action_jump.mp3", Volume = 0.8, Pitch = 1.4 },
		Warning = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 0.5, Pitch = 2.6 },
		Click = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 0.25, Pitch = 3 },
		Victory = { Id = "rbxasset://sounds/action_get_up.mp3", Volume = 0.8, Pitch = 1.2 },
		Splash = { Id = "rbxasset://sounds/impact_water.mp3", Volume = 0.5, Pitch = 1 },
	},
}

return Config
