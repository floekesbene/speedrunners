--[[
	RaceHud  (ModuleScript)
	Pfad: StarterPlayer/StarterPlayerScripts/Client/UI/Screens/RaceHud

	Renn-Oberfläche im Stil des Designsystems (Theme/Components):
		- Countdown 3-2-1-LOS! in großer Display-Schrift mit dicker Kontur,
		  Farbverlauf je Zahl, Dreh-/Skalier-Pop und Schockwellen-Ring
		- Kopfbereich: Map/Modus-Chip, eigene Platzierung als Plakette,
		  Renn-Timer (Glas-Karte mit Kontur), Streckenfortschritt (Verlauf,
		  Checkpoint-Rauten, pulsierende Gefahrenzone mit Kante, Spielerpunkte –
		  eigener Punkt hervorgehoben, Führender golden)
		- Live-Platzierungen mit Gold-/Silber-/Bronze-Plaketten und Status-Chips
		- Gefahrenzone: Banner-Band, roter Bildschirmrand (Vignette + leichte
		  Tönung) und Warnkarte mit Restzeit-Balken
		- Power-up-Slot (leuchtender, pulsierender Ring + Symbol je Item,
		  Tastenkappe) und Cooldown-Ringe für Haken, Dash und Slide
		- Ereignis-Feed mit Symbolen (gleitet ein und blendet aus),
		  Ausgeschieden-Karte, Zuschauerleiste
		- Pfeile für Spieler außerhalb des Bildschirms
	Im Training werden nur Item-Slot und Cooldowns angezeigt.

	Pro Frame werden nur vorhandene Objekte aktualisiert (Farben/Texte nur
	bei Zustandswechsel), neue Instanzen entstehen nur bei Ereignissen.

	API:
		:StartSpectating()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local MapDefinitions = require(Shared.MapDefinitions)
local ItemDefinitions = require(Shared.ItemDefinitions)

local UI = script.Parent.Parent
local Components = require(UI.Components)
local Theme = require(UI.Theme)

local player = Players.LocalPlayer
local new = Components.new
local rgb = Color3.fromRGB

local RaceHud = {}
RaceHud.__index = RaceHud

local KEY_HINTS = {
	Keyboard = { Grapple = "E", Dash = "SHIFT", Slide = "SHIFT", Item = "Q" },
	Gamepad = { Grapple = "X", Dash = "B", Slide = "B", Item = "Y" },
	Touch = { Grapple = "", Dash = "", Slide = "", Item = "" },
}

-- Status-Chips in der Platzierungsliste
local STATUS_CHIPS = {
	Eliminated = { Text = "RAUS", Color = Theme.Colors.Danger },
	Left = { Text = "WEG", Color = Theme.Colors.TextDim },
	Finished = { Text = "ZIEL", Color = Theme.Colors.Gold },
}

local REASON_TEXT = {
	Zone = "von der Gefahrenzone erwischt",
	Left = "hat das Spiel verlassen",
}

-- Symbole der Power-ups (Unicode/Emoji, keine Bild-Assets)
local ITEM_GLYPHS = {
	SpeedBoost = "⚡",
	Shield = "🛡️",
	FreezeBurst = "❄️",
	GrappleUpgrade = Theme.Icons.Hook,
	TeleportBeacon = "🌀",
	Trap = "💣",
}

-- Fähigkeiten: Schlüssel, Beschriftung, Symbol, Farbe des Cooldown-Rings
local ABILITIES = {
	{ Key = "Grapple", Label = "HAKEN", Glyph = Theme.Icons.Hook, Color = Theme.Colors.Accent },
	{ Key = "Dash", Label = "DASH", Glyph = "💨", Color = Theme.Colors.Orange },
	{ Key = "Slide", Label = "SLIDE", Glyph = "🏂", Color = Theme.Colors.Purple },
}

-- Plaketten-Verläufe für die Plätze 1–3 (Gold, Silber, Bronze)
local MEDALS = {
	{ rgb(255, 234, 100), rgb(255, 154, 18) },
	{ rgb(242, 246, 255), rgb(146, 158, 186) },
	{ rgb(255, 196, 140), rgb(184, 96, 38) },
}

-- Countdown-Farben: 3 rot, 2 orange, 1 gelb, LOS! grün-cyan, BEREIT? cyan
local COUNTDOWN_STYLE = {
	[3] = Theme.Gradients.Danger,
	[2] = Theme.Gradients.Orange,
	[1] = Theme.Gradients.Warning,
	[0] = Theme.Gradients.Play,
	[4] = Theme.Gradients.Accent,
}

local function pairSequence(pair)
	return ColorSequence.new(pair[1], pair[2])
end

-- Kleine Tastenkappe (z. B. "E", "SHIFT"); Rückgabe: frame, label
local function keyCap(props)
	local cap = new("Frame", {
		Name = "KeyCap",
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		Position = props.Position or UDim2.new(),
		Size = UDim2.fromOffset(22, 20),
		BackgroundColor3 = Theme.Colors.White,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 3,
		Parent = props.Parent,
	})
	Components.Corner(6).Parent = cap
	Components.Gradient({ rgb(92, 104, 170), rgb(38, 44, 90) }, 90).Parent = cap
	Components.Stroke(Theme.Colors.Black, 1.5, 0.25).Parent = cap
	local label = Components.Label({
		Name = "Key",
		Text = "",
		Font = Theme.Fonts.Black,
		TextSize = 11,
		TextColor3 = Theme.Colors.White,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		RichText = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Parent = cap,
	})
	return cap, label
end

-- Tastenkappe beschriften (leerer Text = ausblenden, z. B. auf Touch-Geräten)
local function setKeyCap(cap: Frame, label: TextLabel, text: string)
	cap.Visible = text ~= ""
	if label.Text ~= text then
		label.Text = text
		cap.Size = UDim2.fromOffset(math.max(22, 10 + 8 * (utf8.len(text) or #text)), 20)
	end
end

function RaceHud.new(ui)
	local self = setmetatable({}, RaceHud)
	self.UI = ui
	self.Ctx = ui.Ctx
	self.LastCountdown = nil
	self.LastZoneState = "Inactive"
	self.BannerUntil = 0
	self.FinalTime = nil
	self.Rows = {}
	self.Dots = {}
	self.Ticks = {}
	self.LastItem = nil

	local root = new("Frame", { Name = "RaceHud", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = ui.Root })
	self.Root = root

	self:_buildDanger(root)
	self:_buildTop(root)
	self:_buildCountdown(root)
	self:_buildStandings(root)
	self:_buildItemSlot(root)
	self:_buildAbilities(root)

	-- Ereignis-Feed (links; auf Touch-Geräten höher, über den Lauf-Buttons)
	self.Feed = new("Frame", {
		Name = "Feed",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = if UserInputService.TouchEnabled then UDim2.new(0, 16, 0.5, -30) else UDim2.new(0, 16, 0.62, 0),
		Size = UDim2.fromOffset(420, 230),
		Parent = root,
	}, { Components.List(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Bottom) })
	self.FeedCount = 0

	self:_buildEliminated(root)
	self:_buildSpectate(root)
	self:_buildIndicators(root)
	return self
end

------------------------------------------------------------------------
-- Aufbau
------------------------------------------------------------------------

-- Gefahren-Vignette, Tönung, Banner-Band und Warnkarte
function RaceHud:_buildDanger(root: Frame)
	-- Vier Ränder mit Farbverlauf (dunkelrot am Rand -> transparent zur Mitte)
	self.Vignette = {}
	local edges = {
		{ Size = UDim2.new(0, 300, 1, 0), Position = UDim2.fromScale(0, 0), Rotation = 0 },
		{ Size = UDim2.new(0, 300, 1, 0), Position = UDim2.new(1, -300, 0, 0), Rotation = 180 },
		{ Size = UDim2.new(1, 0, 0, 210), Position = UDim2.fromScale(0, 0), Rotation = 90 },
		{ Size = UDim2.new(1, 0, 0, 210), Position = UDim2.new(0, 0, 1, -210), Rotation = 270 },
	}
	for _, edge in edges do
		local frame = new("Frame", {
			Name = "Vignette",
			Size = edge.Size,
			Position = edge.Position,
			BackgroundColor3 = Theme.Colors.White,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Parent = root,
		})
		new("UIGradient", {
			Rotation = edge.Rotation,
			Color = ColorSequence.new(rgb(140, 0, 26), Theme.Colors.Danger),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.45, 0.6),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = frame,
		})
		table.insert(self.Vignette, frame)
	end
	-- Sehr leichte rote Tönung des ganzen Bildes bei akuter Gefahr
	self.DangerTint = new("Frame", {
		Name = "DangerTint",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Danger,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = root,
	})

	-- Banner-Band (Zonen-Meldungen)
	local banner = new("Frame", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 142),
		Size = UDim2.fromOffset(760, 50),
		BackgroundColor3 = Theme.Colors.White,
		BorderSizePixel = 0,
		Visible = false,
		Parent = root,
	})
	self.Banner = banner
	self.BannerGradient = Components.Gradient({ Theme.Colors.Danger, Theme.Colors.Danger }, 0, { 1, 0.12, 0.12, 1 })
	self.BannerGradient.Parent = banner
	for _, y in { 0, 1 } do
		Components.Divider({
			Name = "Edge",
			AnchorPoint = Vector2.new(0, y),
			Position = UDim2.fromScale(0, y),
			Size = UDim2.new(1, 0, 0, 2),
			Colors = { Theme.Colors.White, Theme.Colors.White },
			Parent = banner,
		})
	end
	self.BannerLabel = Components.Heading({
		Name = "Text",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 30,
		TextScaled = true,
		MaxTextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Center,
		Outline = 2.5,
		OutlineTransparency = 0,
		RichText = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -60, 1, -10),
		Parent = banner,
	})

	-- Warnkarte "ZURÜCK NACH VORNE!" mit Restzeit-Balken
	local card = new("Frame", {
		Name = "DangerCard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 112),
		Size = UDim2.fromOffset(470, 74),
		BackgroundColor3 = Theme.Colors.White,
		BorderSizePixel = 0,
		Visible = false,
		Parent = root,
	})
	Components.Corner(18).Parent = card
	Components.Gradient(Theme.Gradients.Danger, 90).Parent = card
	Components.Stroke(Theme.Colors.White, 2.5, 0.2).Parent = card
	self.DangerPanel = card
	self.DangerScale = new("UIScale", { Parent = card })
	local _, warnGlyph = Components.Icon({
		Glyph = Theme.Icons.Warning,
		Color = Theme.Colors.Warning,
		Size = 50,
		TextSize = 30,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Parent = card,
	})
	warnGlyph.TextStrokeTransparency = 0.3
	local darkRed = rgb(86, 0, 20)
	self.DangerLabel = Components.Heading({
		Text = "ZURÜCK NACH VORNE!",
		Font = Theme.Fonts.Display,
		TextSize = 28,
		TextScaled = true,
		MaxTextSize = 28,
		Outline = 2.5,
		OutlineColor = darkRed,
		OutlineTransparency = 0,
		RichText = false,
		Position = UDim2.fromOffset(74, 8),
		Size = UDim2.new(1, -176, 0, 32),
		Parent = card,
	})
	self.DangerTime = Components.Heading({
		Text = "",
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Right,
		Outline = 2.5,
		OutlineColor = darkRed,
		OutlineTransparency = 0,
		RichText = false,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 6),
		Size = UDim2.fromOffset(96, 36),
		Parent = card,
	})
	local _, setBar = Components.ProgressBar({
		Name = "DangerBar",
		Position = UDim2.fromOffset(74, 50),
		Size = UDim2.new(1, -92, 0, 10),
		BackgroundColor = darkRed,
		BackgroundTransparency = 0.25,
		Color = Theme.Colors.White,
		CornerRadius = 5,
		Parent = card,
	})
	self.SetDangerBar = setBar
end

-- Kopfbereich: Modus-Chip, Platz-Plakette, Timer, Streckenfortschritt
function RaceHud:_buildTop(root: Frame)
	local top = new("Frame", {
		Name = "Top",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(680, 126),
		Parent = root,
	})
	self.Top = top

	local modePill, modeLabel = Components.Pill({
		Name = "Mode",
		Text = "",
		Color = Theme.Colors.Accent,
		Size = UDim2.fromOffset(380, 24),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		TextSize = 13,
		Parent = top,
	})
	modePill.BackgroundColor3 = Theme.Colors.PanelDark
	modePill.BackgroundTransparency = 0.2
	modeLabel.TextStrokeTransparency = 0.6
	modeLabel.TextStrokeColor3 = Theme.Colors.Shadow
	self.ModePill = modePill
	self.MapLabel = modeLabel

	-- Timer als Glas-Karte
	local _, timerPanel = Components.Card({
		Name = "TimerCard",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 30),
		Size = UDim2.fromOffset(236, 58),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.12,
		CornerRadius = 16,
		ShadowOffset = 4,
		ShadowSpread = 5,
		Parent = top,
	})
	self.TimerLabel = Components.Heading({
		Text = "0:00.00",
		TextSize = 40,
		TextXAlignment = Enum.TextXAlignment.Center,
		Outline = 2.5,
		OutlineTransparency = 0,
		RichText = false,
		Size = UDim2.fromScale(1, 1),
		Parent = timerPanel,
	})
	self.TimerGradient = Components.Gradient({ Theme.Colors.White, rgb(178, 228, 255) }, 90)
	self.TimerGradient.Parent = self.TimerLabel
	self.TimerStyle = "Race"

	-- Eigene Platzierung (bzw. die des beobachteten Spielers)
	local badge = new("Frame", {
		Name = "PlaceBadge",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(0.5, -130, 0, 31),
		Size = UDim2.fromOffset(56, 56),
		BackgroundColor3 = Theme.Colors.White,
		BorderSizePixel = 0,
		Visible = false,
		Parent = top,
	})
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = badge })
	self.PlaceGradient = Components.Gradient(Theme.Gradients.Neutral, 90)
	self.PlaceGradient.Parent = badge
	Components.Stroke(Theme.Colors.White, 2.5, 0.15).Parent = badge
	self.PlaceBadge = badge
	self.PlaceLabel = Components.Heading({
		Text = "",
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Center,
		Outline = 2,
		RichText = false,
		Position = UDim2.fromOffset(0, 4),
		Size = UDim2.new(1, 0, 0, 30),
		Parent = badge,
	})
	self.PlaceOf = Components.Label({
		Text = "",
		Font = Theme.Fonts.Title,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		RichText = false,
		TextStrokeTransparency = 0.4,
		TextStrokeColor3 = Theme.Colors.Shadow,
		Position = UDim2.fromOffset(0, 33),
		Size = UDim2.new(1, 0, 0, 14),
		Parent = badge,
	})
	self.LastPlace = nil

	-- Streckenfortschritt
	local track = new("Frame", {
		Name = "Track",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 102),
		Size = UDim2.fromOffset(560, 14),
		BackgroundColor3 = Theme.Colors.Shadow,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Parent = top,
	})
	Components.Corner(7).Parent = track
	Components.Stroke(Theme.Colors.White, 1.5, 0.55).Parent = track
	self.Track = track
	self.ProgressFill = new("Frame", {
		Name = "Progress",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Colors.White,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Parent = track,
	})
	Components.Corner(7).Parent = self.ProgressFill
	Components.Gradient({ Theme.Gradients.Accent[2], Theme.Gradients.Accent[1] }, 0).Parent = self.ProgressFill
	self.ZoneFill = new("Frame", {
		Name = "Zone",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Colors.White,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = track,
	})
	Components.Corner(7).Parent = self.ZoneFill
	Components.Gradient({ rgb(110, 0, 22), Theme.Colors.Danger }, 0).Parent = self.ZoneFill
	self.ZoneEdge = new("Frame", {
		Name = "ZoneEdge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(6, 24),
		BackgroundColor3 = rgb(255, 214, 214),
		BorderSizePixel = 0,
		ZIndex = 3,
		Visible = false,
		Parent = track,
	})
	Components.Corner(3).Parent = self.ZoneEdge
	self.ZoneEdgeStroke = Components.Stroke(Theme.Colors.Danger, 3, 0.1)
	self.ZoneEdgeStroke.Parent = self.ZoneEdge
	Components.Icon({
		Name = "Start",
		Glyph = Theme.Icons.Play,
		Color = Theme.Colors.Success,
		Size = 24,
		TextSize = 11,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0, -8, 0.5, 0),
		Parent = track,
	})
	local _, finishGlyph = Components.Icon({
		Name = "Finish",
		Glyph = Theme.Icons.Flag,
		Color = Theme.Colors.Gold,
		Size = 32,
		TextSize = 17,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(1, 8, 0.5, 0),
		Parent = track,
	})
	finishGlyph.TextStrokeTransparency = 1
	self.TickHolder = new("Frame", { Name = "Ticks", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = track })
	self.DotHolder = new("Frame", { Name = "Dots", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = track })
end

-- Countdown mit Schockwellen-Ring
function RaceHud:_buildCountdown(root: Frame)
	self.Shock = new("Frame", {
		Name = "Shockwave",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(140, 140),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = root,
	})
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = self.Shock })
	self.ShockStroke = Components.Stroke(Theme.Colors.White, 8, 1)
	self.ShockStroke.Parent = self.Shock

	self.Countdown = Components.Label({
		Name = "Countdown",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 160,
		TextColor3 = Theme.Colors.White,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		RichText = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(900, 220),
		Visible = false,
		Parent = root,
	})
	self.CountdownStroke = Components.TextStroke(6, Theme.Colors.Shadow, 0)
	self.CountdownStroke.Parent = self.Countdown
	self.CountdownGradient = Components.Gradient(Theme.Gradients.Accent, 90)
	self.CountdownGradient.Parent = self.Countdown
	self.CountdownScale = new("UIScale", { Parent = self.Countdown })
end

-- Platzierungen (rechts)
function RaceHud:_buildStandings(root: Frame)
	local holder, panel = Components.Card({
		Name = "Standings",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 150),
		Size = UDim2.fromOffset(264, 82),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.12,
		CornerRadius = 16,
		ShadowOffset = 4,
		ShadowSpread = 5,
		Parent = root,
	})
	self.Standings = holder
	Components.Label({
		Text = Theme.Icons.Flag .. "  PLATZIERUNG",
		Font = Theme.Fonts.Title,
		TextSize = 14,
		TextColor3 = Theme.Colors.TextDim,
		TextWrapped = false,
		RichText = false,
		Position = UDim2.fromOffset(14, 9),
		Size = UDim2.new(1, -100, 0, 18),
		Parent = panel,
	})
	self.AliveLabel = Components.Label({
		Text = "",
		Font = Theme.Fonts.Title,
		TextSize = 13,
		TextColor3 = Theme.Colors.Text,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
		RichText = false,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 9),
		Size = UDim2.fromOffset(80, 18),
		Parent = panel,
	})
	Components.Divider({ Position = UDim2.fromOffset(12, 32), Size = UDim2.new(1, -24, 0, 2), Parent = panel })
	self.StandingsList = new("Frame", {
		Name = "Rows",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(8, 40),
		Size = UDim2.new(1, -16, 1, -46),
		Parent = panel,
	}, { Components.List(Enum.FillDirection.Vertical, 4) })
end

-- Power-up-Slot (unten rechts, auf Touch-Geräten rechts oberhalb der Buttons)
function RaceHud:_buildItemSlot(root: Frame)
	local touch = UserInputService.TouchEnabled
	local size = if touch then 110 else 124
	local slot, panel = Components.Card({
		Name = "ItemSlot",
		AnchorPoint = if touch then Vector2.new(1, 0) else Vector2.new(1, 1),
		-- Auf Touch-Geräten liegt unten rechts der Sprungbutton
		Position = if touch then UDim2.new(1, -16, 0, 410) else UDim2.new(1, -24, 1, -24),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.1,
		CornerRadius = 22,
		ShadowOffset = 5,
		Parent = root,
	})
	self.Slot = slot
	self.SlotScale = new("UIScale", { Parent = slot })
	self.SlotStroke = panel:FindFirstChild("Border")

	-- Pulsierender Leuchtring hinter dem Symbol
	local glowSize = math.floor(size * 0.6)
	local glow = new("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(glowSize, glowSize),
		BackgroundColor3 = Theme.Colors.White,
		BackgroundTransparency = 0.72,
		BorderSizePixel = 0,
		Visible = false,
		Parent = panel,
	})
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = glow })
	self.SlotGlowStroke = Components.Stroke(Theme.Colors.White, 4, 0.2)
	self.SlotGlowStroke.Parent = glow
	Components.Loop(new("UIScale", { Parent = glow }), 0.7, { Scale = 1.14 })
	self.SlotGlow = glow

	local icon, glyph = Components.Icon({
		Name = "ItemIcon",
		Glyph = "?",
		Color = Theme.Colors.PanelLight,
		Size = 54,
		TextSize = 28,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Parent = panel,
	})
	self.SlotIcon = icon
	self.SlotGlyph = glyph
	self.SlotName = Components.Heading({
		Text = "KEIN ITEM",
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Center,
		Outline = 1.5,
		RichText = false,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -22),
		Size = UDim2.new(1, -8, 0, 18),
		Parent = panel,
	})
	self.SlotKey = Components.Label({
		Text = "",
		Font = Theme.Fonts.Bold,
		TextSize = 11,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		RichText = false,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -7),
		Size = UDim2.new(1, -8, 0, 14),
		Parent = panel,
	})
	self.SlotKeyCap, self.SlotKeyLabel = keyCap({ Position = UDim2.fromOffset(8, 8), Parent = panel })
end

-- Fähigkeiten mit Cooldown-Ringen (unten mittig)
function RaceHud:_buildAbilities(root: Frame)
	local abilities = new("Frame", {
		Name = "Abilities",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(330, 100),
		Parent = root,
	}, { Components.List(Enum.FillDirection.Horizontal, 12, Enum.HorizontalAlignment.Center) })
	self.Abilities = abilities
	self.AbilityBoxes = {}
	for index, info in ABILITIES do
		local holder, box = Components.Card({
			Name = info.Key,
			Size = UDim2.fromOffset(96, 96),
			BackgroundColor3 = Theme.Colors.PanelDark,
			BackgroundTransparency = 0.12,
			CornerRadius = 16,
			ShadowOffset = 4,
			ShadowSpread = 4,
			LayoutOrder = index,
			Parent = abilities,
		})
		local ring, setRing, inner = Components.Ring({
			Size = 54,
			Thickness = 5,
			Color = info.Color,
			TrackColor = Theme.Colors.Shadow,
			InnerColor = rgb(22, 26, 56),
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 6),
			Parent = box,
		})
		local glyph = Components.Label({
			Name = "Glyph",
			Text = info.Glyph,
			Font = Theme.Fonts.Title,
			TextSize = 24,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = false,
			RichText = false,
			Size = UDim2.fromScale(1, 1),
			Parent = inner,
		})
		local timer = Components.Heading({
			Name = "Timer",
			Text = "",
			TextSize = 17,
			TextXAlignment = Enum.TextXAlignment.Center,
			Outline = 1.5,
			RichText = false,
			Size = UDim2.fromScale(1, 1),
			Visible = false,
			Parent = inner,
		})
		local name = Components.Heading({
			Text = info.Label,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Center,
			Outline = 1.5,
			RichText = false,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -4),
			Size = UDim2.new(1, -8, 0, 18),
			Parent = box,
		})
		-- Tastenkappe sitzt auf der Unterkante des Rings
		local cap, capLabel = keyCap({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 60), Parent = box })
		local discs = {}
		for _, half in { "RightHalf", "LeftHalf" } do
			local clip = ring:FindFirstChild(half)
			local disc = clip and clip:FindFirstChildOfClass("Frame")
			if disc then
				table.insert(discs, disc)
			end
		end
		self.AbilityBoxes[info.Key] = {
			Holder = holder,
			Box = box,
			Ring = ring,
			SetRing = setRing,
			Discs = discs,
			Glyph = glyph,
			Timer = timer,
			Name = name,
			Label = info.Label,
			Color = info.Color,
			Cap = cap,
			CapLabel = capLabel,
			Stroke = box:FindFirstChild("Border"),
			State = nil,
		}
	end
end

-- Ausgeschieden-Karte
function RaceHud:_buildEliminated(root: Frame)
	local holder, panel = Components.Card({
		Name = "Eliminated",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(500, 214),
		BackgroundColor3 = Theme.Colors.PanelDark,
		StrokeColor = Theme.Colors.Danger,
		StrokeThickness = 2.5,
		CornerRadius = 20,
		ShadowOffset = 8,
		ShadowSpread = 10,
		Visible = false,
		Parent = root,
	})
	self.EliminatedPanel = holder
	local glow = new("Frame", {
		Name = "Glow",
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(1, -4, 0, 96),
		BackgroundColor3 = Theme.Colors.Danger,
		BorderSizePixel = 0,
		Parent = panel,
	})
	Components.Corner(18).Parent = glow
	Components.Gradient(Theme.Colors.Danger, 90, { 0.6, 1 }).Parent = glow
	local _, skull = Components.Icon({
		Glyph = "💀",
		Color = Theme.Colors.Danger,
		Size = 64,
		TextSize = 34,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 0),
		ZIndex = 3,
		Parent = panel,
	})
	skull.TextStrokeTransparency = 1
	Components.Heading({
		Text = "AUSGESCHIEDEN",
		Font = Theme.Fonts.Display,
		TextSize = 42,
		TextXAlignment = Enum.TextXAlignment.Center,
		Outline = 3,
		OutlineColor = rgb(70, 0, 16),
		OutlineTransparency = 0,
		TextGradient = Theme.Gradients.Danger,
		RichText = false,
		Position = UDim2.fromOffset(0, 38),
		Size = UDim2.new(1, 0, 0, 48),
		Parent = panel,
	})
	self.EliminatedInfo = Components.Label({
		Text = "",
		Font = Theme.Fonts.Medium,
		TextSize = 17,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(20, 90),
		Size = UDim2.new(1, -40, 0, 24),
		Parent = panel,
	})
	local spectateButton = Components.Button({
		Text = "ZUSCHAUEN",
		Icon = Theme.Icons.Spectate,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(0.5, -8, 1, -18),
		Size = UDim2.fromOffset(210, 52),
		Color = Theme.Colors.Accent,
		TextColor = Theme.Colors.White,
		TextSize = 19,
		CornerRadius = 14,
		OnClick = function()
			self.EliminatedPanel.Visible = false
			self:StartSpectating()
		end,
	})
	spectateButton.Parent = panel
	local lobbyButton = Components.Button({
		Text = "ZUR LOBBY",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0.5, 8, 1, -18),
		Size = UDim2.fromOffset(210, 52),
		TextColor = Theme.Colors.White,
		TextSize = 19,
		CornerRadius = 14,
		OnClick = function()
			self.EliminatedPanel.Visible = false
		end,
	})
	lobbyButton.Parent = panel
end

-- Zuschauerleiste (unten mittig)
function RaceHud:_buildSpectate(root: Frame)
	local holder, panel = Components.Card({
		Name = "Spectate",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -22),
		Size = UDim2.fromOffset(620, 76),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.08,
		StrokeColor = Theme.Colors.Accent2,
		StrokeThickness = 2,
		CornerRadius = 18,
		Visible = false,
		Parent = root,
	})
	self.SpectatePanel = holder
	local _, eye = Components.Icon({
		Glyph = Theme.Icons.Spectate,
		Color = Theme.Colors.Accent2,
		Size = 50,
		TextSize = 26,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
		Parent = panel,
	})
	eye.TextStrokeTransparency = 1
	Components.Label({
		Text = "DU SCHAUST ZU",
		Font = Theme.Fonts.Title,
		TextSize = 12,
		TextColor3 = Theme.Colors.TextDim,
		TextWrapped = false,
		RichText = false,
		Position = UDim2.fromOffset(78, 12),
		Size = UDim2.fromOffset(110, 16),
		Parent = panel,
	})
	local placePill, placeLabel = Components.Pill({
		Text = "",
		Color = Theme.Colors.Accent2,
		Size = UDim2.fromOffset(78, 18),
		Position = UDim2.fromOffset(188, 11),
		TextSize = 11,
		Parent = panel,
	})
	self.SpectatePlacePill = placePill
	self.SpectatePlace = placeLabel
	self.SpectateLabel = Components.Heading({
		Text = "",
		TextSize = 24,
		RichText = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(78, 30),
		Size = UDim2.new(1, -78 - 290, 0, 32),
		Parent = panel,
	})
	local prev = Components.Button({
		Text = Theme.Icons.Left,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -218, 0.5, 0),
		Size = UDim2.fromOffset(46, 46),
		TextColor = Theme.Colors.White,
		CornerRadius = 23,
		OnClick = function()
			self:_cycleSpectate(-1)
		end,
	})
	prev.Parent = panel
	local nextButton = Components.Button({
		Text = Theme.Icons.Right,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -164, 0.5, 0),
		Size = UDim2.fromOffset(46, 46),
		TextColor = Theme.Colors.White,
		CornerRadius = 23,
		OnClick = function()
			self:_cycleSpectate(1)
		end,
	})
	nextButton.Parent = panel
	local stop = Components.Button({
		Text = "BEENDEN",
		Icon = Theme.Icons.Close,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(140, 46),
		Color = Theme.Colors.Danger,
		TextColor = Theme.Colors.White,
		CornerRadius = 14,
		OnClick = function()
			self.Ctx.CameraController:SetSpectate(nil)
		end,
	})
	stop.Parent = panel
end

-- Pfeile für Spieler außerhalb des Bildes
function RaceHud:_buildIndicators(root: Frame)
	self.Indicators = {}
	for i = 1, 7 do
		local indicator = new("Frame", {
			Name = "Offscreen" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(130, 56),
			BackgroundTransparency = 1,
			Visible = false,
			Parent = root,
		})
		local bubble = new("Frame", {
			Name = "Bubble",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromOffset(32, 32),
			BackgroundColor3 = Theme.Colors.PanelDark,
			BackgroundTransparency = 0.1,
			BorderSizePixel = 0,
			Parent = indicator,
		})
		new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = bubble })
		Components.Stroke(Theme.Colors.Accent2, 2, 0.1).Parent = bubble
		local arrow = Components.Label({
			Name = "Arrow",
			Text = Theme.Icons.Right,
			Font = Theme.Fonts.Title,
			TextSize = 15,
			TextColor3 = Theme.Colors.Accent2:Lerp(Theme.Colors.White, 0.35),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = false,
			RichText = false,
			Size = UDim2.fromScale(1, 1),
			Parent = bubble,
		})
		local tag = new("Frame", {
			Name = "Tag",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 36),
			Size = UDim2.fromOffset(126, 18),
			BackgroundColor3 = Theme.Colors.Shadow,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			Parent = indicator,
		})
		Components.Corner(9).Parent = tag
		local label = Components.Label({
			Name = "Name",
			Text = "",
			TextSize = 11,
			Font = Theme.Fonts.Bold,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = false,
			RichText = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(4, 0),
			Size = UDim2.new(1, -8, 1, 0),
			Parent = tag,
		})
		self.Indicators[i] = { Frame = indicator, Arrow = arrow, Label = label }
	end
end

------------------------------------------------------------------------
-- Ereignisse
------------------------------------------------------------------------

function RaceHud:Start()
	local state = self.Ctx.ClientState
	state:On("RacerEliminated", function(payload)
		if payload.UserId == player.UserId then
			if payload.Reason ~= "Left" then
				self.EliminatedInfo.Text = string.format("Platz %d · %s", payload.Placement or 0, REASON_TEXT[payload.Reason] or "")
				self.EliminatedPanel.Visible = true
				Components.Pop(self.EliminatedPanel, 0.75, 0.45)
			end
		else
			self:_feed(
				string.format("<b>%s</b> ist raus (Platz %d) – %s", payload.Name or "?", payload.Placement or 0, REASON_TEXT[payload.Reason] or "ausgeschieden"),
				Theme.Colors.Danger,
				"💀"
			)
		end
	end)
	state:On("RacerFinished", function(payload)
		self:_feed(string.format("<b>%s</b> hat das Ziel erreicht! (%s)", payload.Name or "?", Util.FormatTime(payload.Time or 0)), Theme.Colors.Gold, Theme.Icons.Flag)
	end)
	state:On("PowerUpUsed", function(payload)
		local item = ItemDefinitions.Get(payload.ItemId)
		local who = Players:GetPlayerByUserId(payload.UserId)
		if item and who and who ~= player and item.Offensive then
			self:_feed(string.format("<b>%s</b> setzt %s ein", who.DisplayName, item.Name), item.Color, ITEM_GLYPHS[item.Id])
		end
	end)
	state:On("StatusApplied", function(payload)
		if payload.UserId == player.UserId then
			local slowed = payload.Kind == "Slowed"
			self:_feed(if slowed then "Du wurdest eingefroren!" else "Du bist in eine Falle getappt!", Theme.Colors.Warning, if slowed then "❄️" else "💣")
		end
	end)
	state:On("ShieldBlocked", function(payload)
		if payload.UserId == player.UserId then
			self:_feed("Dein Schild hat einen Angriff geblockt!", Theme.Colors.Accent, "🛡️")
		end
	end)
	state:On("ItemPickup", function()
		self.SlotScale.Scale = 1.25
		Components.Tween(self.SlotScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	state:On("MatchStarted", function()
		self.EliminatedPanel.Visible = false
		self.FinalTime = nil
		self:_clearFeed()
		self:_buildTicks()
	end)
	state:On("MatchResults", function(payload)
		self.EliminatedPanel.Visible = false
		self.FinalTime = payload.Duration
	end)

	RunService.RenderStepped:Connect(function(dt)
		local ok, err = pcall(self._update, self, dt)
		if not ok then
			warn("[RaceHud] " .. tostring(err))
		end
	end)
end

--- Neuer Eintrag im Ereignis-Feed (gleitet ein, blendet nach 6 s aus).
function RaceHud:_feed(text: string, color: Color3, icon: string?)
	self.FeedCount += 1
	local entry = new("Frame", {
		Name = "FeedEntry",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = self.FeedCount,
		Parent = self.Feed,
	})
	local bubble = new("Frame", {
		Name = "Bubble",
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.fromOffset(-24, 0),
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = entry,
	})
	Components.Corner(10).Parent = bubble
	local stroke = Components.Stroke(color, 1.5, 1)
	stroke.Parent = bubble
	Components.Padding(0, 12, 0, 6).Parent = bubble
	Components.List(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center).Parent = bubble
	local bar = new("Frame", {
		Name = "Bar",
		Size = UDim2.fromOffset(4, 18),
		BackgroundColor3 = color,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = 1,
		Parent = bubble,
	})
	Components.Corner(2).Parent = bar
	local glyph = Components.Label({
		Text = icon or Theme.Icons.Info,
		Font = Theme.Fonts.Title,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		RichText = false,
		TextTransparency = 1,
		Size = UDim2.fromOffset(20, 20),
		LayoutOrder = 2,
		Parent = bubble,
	})
	local label = Components.Label({
		Text = text,
		Font = Theme.Fonts.Medium,
		TextSize = 14,
		TextColor3 = color:Lerp(Theme.Colors.White, 0.55),
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 0, 20),
		LayoutOrder = 3,
		Parent = bubble,
	})
	new("UISizeConstraint", { MaxSize = Vector2.new(360, 20), Parent = label })

	-- Einblenden (von links hereingleiten)
	Components.Tween(bubble, 0.3, { Position = UDim2.new(), BackgroundTransparency = 0.15 }, Enum.EasingStyle.Back)
	Components.Tween(stroke, 0.3, { Transparency = 0.35 })
	Components.Tween(bar, 0.3, { BackgroundTransparency = 0 })
	Components.Tween(glyph, 0.3, { TextTransparency = 0 })
	Components.Tween(label, 0.3, { TextTransparency = 0 })

	local entries = {}
	for _, child in self.Feed:GetChildren() do
		if child.Name == "FeedEntry" then
			table.insert(entries, child)
		end
	end
	if #entries > 6 then
		table.sort(entries, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		entries[1]:Destroy()
	end
	task.delay(6, function()
		if entry.Parent then
			Components.Tween(bubble, 0.4, { BackgroundTransparency = 1, Position = UDim2.fromOffset(-16, 0) })
			Components.Tween(stroke, 0.4, { Transparency = 1 })
			Components.Tween(bar, 0.4, { BackgroundTransparency = 1 })
			Components.Tween(glyph, 0.4, { TextTransparency = 1 })
			Components.Tween(label, 0.4, { TextTransparency = 1 })
			task.wait(0.45)
			entry:Destroy()
		end
	end)
end

function RaceHud:_clearFeed()
	for _, child in self.Feed:GetChildren() do
		if child.Name == "FeedEntry" then
			child:Destroy()
		end
	end
end

-- Checkpoint-Rauten auf der Fortschrittsleiste
function RaceHud:_buildTicks()
	self.TickHolder:ClearAllChildren()
	self.Ticks = {}
	local gameState = self.Ctx.ClientState.GameState
	local startX = gameState:GetAttribute("StartX") or 0
	local finishX = gameState:GetAttribute("FinishX") or 0
	local list = gameState:GetAttribute("CheckpointXs") or ""
	if finishX <= startX then
		return
	end
	for value in string.gmatch(list, "[^,]+") do
		local x = tonumber(value)
		if x then
			local alpha = math.clamp((x - startX) / (finishX - startX), 0, 1)
			local tick = new("Frame", {
				Name = "Checkpoint",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(alpha, 0.5),
				Size = UDim2.fromOffset(10, 10),
				Rotation = 45,
				BackgroundColor3 = Theme.Colors.TextDim,
				BorderSizePixel = 0,
				Parent = self.TickHolder,
			})
			Components.Corner(2).Parent = tick
			Components.Stroke(Theme.Colors.Shadow, 1.5, 0.1).Parent = tick
			table.insert(self.Ticks, { Frame = tick, Alpha = alpha, Passed = nil })
		end
	end
end

------------------------------------------------------------------------
-- Zuschauen
------------------------------------------------------------------------

function RaceHud:_aliveRacers()
	local list = {}
	for _, folder in self.Ctx.ClientState.Racers:GetChildren() do
		if folder:GetAttribute("Status") == "Racing" then
			local other = Players:GetPlayerByUserId(folder:GetAttribute("UserId") or 0)
			if other and other ~= player then
				table.insert(list, { Player = other, Placement = folder:GetAttribute("Placement") or 99 })
			end
		end
	end
	table.sort(list, function(a, b)
		return a.Placement < b.Placement
	end)
	return list
end

function RaceHud:StartSpectating()
	local alive = self:_aliveRacers()
	if #alive > 0 then
		self.Ctx.CameraController:SetSpectate(alive[1].Player)
	else
		self.UI:Notify("Gerade gibt es niemanden zum Zuschauen.", "Info")
	end
end

function RaceHud:_cycleSpectate(direction: number)
	local alive = self:_aliveRacers()
	if #alive == 0 then
		return
	end
	local current = self.Ctx.CameraController:GetSpectate()
	local index = 0
	for i, entry in alive do
		if entry.Player == current then
			index = i
		end
	end
	index = ((index - 1 + direction) % #alive) + 1
	self.Ctx.CameraController:SetSpectate(alive[index].Player)
end

------------------------------------------------------------------------
-- Pro Frame
------------------------------------------------------------------------

-- Verlaufspaar einer Platzierung (Gold/Silber/Bronze, sonst neutral)
local function placeGradient(placement: number?, active: boolean)
	if active and placement and MEDALS[placement] then
		return MEDALS[placement]
	end
	return Theme.Gradients.Neutral
end

function RaceHud:_rowFor(folder)
	local row = self.Rows[folder]
	if row and row.Frame.Parent then
		return row
	end
	local isLocal = folder:GetAttribute("UserId") == player.UserId
	local frame = new("Frame", { Name = "Row", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28), Parent = self.StandingsList })
	if isLocal then
		-- Eigene Zeile: Akzent-Schimmer von links
		local highlight = new("Frame", {
			Name = "Highlight",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Theme.Colors.Accent,
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
			Parent = frame,
		})
		Components.Corner(8).Parent = highlight
		Components.Gradient(Theme.Colors.White, 0, { 0.1, 1 }).Parent = highlight
	end
	local badge = new("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 2, 0.5, 0),
		Size = UDim2.fromOffset(24, 24),
		BackgroundColor3 = Theme.Colors.White,
		BorderSizePixel = 0,
		Parent = frame,
	})
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = badge })
	local badgeGradient = Components.Gradient(Theme.Gradients.Neutral, 90)
	badgeGradient.Parent = badge
	Components.Stroke(Theme.Colors.Shadow, 1.5, 0.3).Parent = badge
	local placement = Components.Label({
		Text = "",
		Font = Theme.Fonts.Title,
		TextSize = 14,
		TextColor3 = Theme.Colors.White,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		RichText = false,
		TextStrokeTransparency = 0.35,
		TextStrokeColor3 = Theme.Colors.Shadow,
		Size = UDim2.fromScale(1, 1),
		Parent = badge,
	})
	local name = Components.Label({
		Text = "",
		Font = Theme.Fonts.Bold,
		TextSize = 15,
		RichText = false,
		TextStrokeTransparency = 0.7,
		TextStrokeColor3 = Theme.Colors.Shadow,
		Position = UDim2.fromOffset(34, 0),
		Size = UDim2.new(1, -96, 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
		Parent = frame,
	})
	local chip, chipLabel = Components.Pill({
		Text = "",
		Color = Theme.Colors.Danger,
		Size = UDim2.fromOffset(58, 20),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -2, 0.5, 0),
		TextSize = 11,
		Parent = frame,
	})
	chip.Visible = false
	row = {
		Frame = frame,
		Badge = badge,
		BadgeGradient = badgeGradient,
		Placement = placement,
		Name = name,
		Chip = chip,
		ChipLabel = chipLabel,
		IsLocal = isLocal,
		LastPlacement = nil,
		LastStyle = nil,
		LastChip = nil,
	}
	self.Rows[folder] = row
	return row
end

-- Status-Chip einer Zeile setzen (nur bei Änderung)
local function setChip(row, text: string?, color: Color3?)
	if row.LastChip == text then
		return
	end
	row.LastChip = text
	row.Chip.Visible = text ~= nil
	if text and color then
		row.ChipLabel.Text = text
		row.ChipLabel.TextColor3 = color:Lerp(Theme.Colors.White, 0.35)
		row.Chip.BackgroundColor3 = color
		row.Chip.BackgroundTransparency = 0.78
		local border = row.Chip:FindFirstChild("Border")
		if border then
			border.Color = color
		end
	end
end

function RaceHud:_dotFor(folder)
	local dot = self.Dots[folder]
	if dot and dot.Frame.Parent then
		return dot
	end
	local isLocal = folder:GetAttribute("UserId") == player.UserId
	local size = if isLocal then 20 else 12
	local frame = new("Frame", {
		Name = if isLocal then "LocalDot" else "Dot",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Theme.Colors.White,
		BorderSizePixel = 0,
		ZIndex = if isLocal then 7 else 6,
		Parent = self.DotHolder,
	})
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = frame })
	Components.Stroke(if isLocal then Theme.Colors.White else Theme.Colors.Shadow, if isLocal then 2.5 else 2, 0).Parent = frame
	if isLocal then
		Components.Gradient(Theme.Gradients.Accent, 90).Parent = frame
		-- Markierung über dem eigenen Punkt
		Components.Label({
			Text = Theme.Icons.Down,
			Font = Theme.Fonts.Title,
			TextSize = 12,
			TextColor3 = Theme.Colors.Accent,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = false,
			RichText = false,
			Outline = 1.5,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 0, -3),
			Size = UDim2.fromOffset(16, 12),
			ZIndex = 7,
			Parent = frame,
		})
	end
	dot = { Frame = frame, IsLocal = isLocal, Leader = nil }
	self.Dots[folder] = dot
	return dot
end

function RaceHud:_update(_dt: number)
	local ctx = self.Ctx
	local state = ctx.ClientState
	local gameState = state.GameState
	local serverNow = workspace:GetServerTimeNow()
	local phase = gameState:GetAttribute("Phase") or "Waiting"
	local inRace = state:IsInRace()
	local spectateTarget = ctx.CameraController:GetSpectate()
	local practice = state:GetPracticeCourse() ~= ""
	local matchActive = phase == "Countdown" or phase == "Racing" or phase == "Results"

	-- Zuschauen beenden, wenn das Rennen vorbei ist oder das Ziel weg ist
	if spectateTarget and (not matchActive or not spectateTarget.Parent or inRace) then
		ctx.CameraController:SetSpectate(nil)
		spectateTarget = nil
	end
	local watching = (inRace or spectateTarget ~= nil) and matchActive

	self.Top.Visible = watching
	self.Standings.Visible = watching
	self.SpectatePanel.Visible = spectateTarget ~= nil
	if spectateTarget then
		self:_updateSpectate(spectateTarget)
	end
	if not matchActive then
		self.EliminatedPanel.Visible = false
	end

	-- Kopfbereich
	if watching then
		local definition = MapDefinitions.Get(gameState:GetAttribute("MapId") or "")
		local ranked = gameState:GetAttribute("Mode") == "Ranked"
		local modeText = string.format("%s  %s · %s", Theme.Icons.Flag, if definition then string.upper(definition.Name) else "", if ranked then "RANKED" else "SCHNELLES SPIEL")
		if self.MapLabel.Text ~= modeText then
			self.MapLabel.Text = modeText
			local color = if ranked then Theme.Colors.Gold else Theme.Colors.Accent
			self.MapLabel.TextColor3 = color:Lerp(Theme.Colors.White, 0.35)
			local border = self.ModePill:FindFirstChild("Border")
			if border then
				border.Color = color
			end
		end
		local startedAt = gameState:GetAttribute("RaceStartedAt") or 0
		if phase == "Racing" and startedAt > 0 then
			self.TimerLabel.Text = Util.FormatTime(serverNow - startedAt)
		elseif phase == "Results" and self.FinalTime then
			self.TimerLabel.Text = Util.FormatTime(self.FinalTime)
		elseif phase == "Countdown" then
			self.TimerLabel.Text = "0:00.00"
		end
		-- Endzeit golden, sonst weiß-cyan
		local timerStyle = if phase == "Results" then "Final" else "Race"
		if timerStyle ~= self.TimerStyle then
			self.TimerStyle = timerStyle
			self.TimerGradient.Color = if timerStyle == "Final" then pairSequence(Theme.Gradients.Gold) else ColorSequence.new(Theme.Colors.White, rgb(178, 228, 255))
			Components.Pop(self.TimerLabel, 1.2, 0.35)
		end
		self:_updateTrack(gameState, spectateTarget)
		self:_updateStandings(spectateTarget)
	end

	-- Countdown
	self:_updateCountdown(phase, gameState, serverNow, watching)

	-- Gefahrenzone
	self:_updateZone(gameState, serverNow, inRace and phase == "Racing", watching)

	-- Item und Fähigkeiten
	local showControls = (inRace and phase ~= "Results") or practice
	self.Slot.Visible = showControls
	self.Abilities.Visible = showControls
	if showControls then
		self:_updateControls()
	end

	self:_updateIndicators(watching)
end

function RaceHud:_updateSpectate(target: Player)
	if self.SpectateLabel.Text ~= target.DisplayName then
		self.SpectateLabel.Text = target.DisplayName
	end
	local folder = self.Ctx.ClientState.Racers:FindFirstChild(tostring(target.UserId))
	local placement = folder and folder:GetAttribute("Placement")
	self.SpectatePlacePill.Visible = placement ~= nil
	if placement then
		local text = "PLATZ " .. tostring(placement)
		if self.SpectatePlace.Text ~= text then
			self.SpectatePlace.Text = text
		end
	end
end

function RaceHud:_updateTrack(gameState, spectateTarget: Player?)
	local startX = gameState:GetAttribute("StartX") or 0
	local finishX = gameState:GetAttribute("FinishX") or 0
	local length = math.max(1, finishX - startX)
	if #self.Ticks == 0 and (gameState:GetAttribute("CheckpointXs") or "") ~= "" then
		self:_buildTicks()
	end
	local zoneState = gameState:GetAttribute("ZoneState") or "Inactive"
	local zoneX = gameState:GetAttribute("ZoneX") or -1e6
	local zoneAlpha = if zoneState == "Shrinking" or zoneState == "Final" then math.clamp((zoneX - startX) / length, 0, 1) else 0
	self.ZoneFill.Size = UDim2.fromScale(zoneAlpha, 1)
	self.ZoneEdge.Visible = zoneAlpha > 0
	if zoneAlpha > 0 then
		-- Zone pulsiert leicht, die Kante glüht
		local pulse = 0.5 + 0.5 * math.sin(os.clock() * 6)
		self.ZoneFill.BackgroundTransparency = 0.05 + 0.2 * pulse
		self.ZoneEdge.Position = UDim2.fromScale(zoneAlpha, 0.5)
		self.ZoneEdgeStroke.Transparency = 0.6 * pulse
	end

	local focusId = if spectateTarget then spectateTarget.UserId else player.UserId
	local focusAlpha = nil
	local seen = {}
	for _, folder in self.Ctx.ClientState.Racers:GetChildren() do
		seen[folder] = true
		local dot = self:_dotFor(folder)
		local progress = folder:GetAttribute("Progress") or 0
		local status = folder:GetAttribute("Status")
		local alpha = math.clamp(progress / length, 0, 1)
		dot.Frame.Position = UDim2.fromScale(alpha, 0.5)
		dot.Frame.Visible = status == "Racing" or status == "Finished" or status == "Survived"
		if folder:GetAttribute("UserId") == focusId then
			focusAlpha = alpha
		end
		if not dot.IsLocal then
			local leader = folder:GetAttribute("Placement") == 1
			if leader ~= dot.Leader then
				dot.Leader = leader
				dot.Frame.BackgroundColor3 = if leader then Theme.Colors.Gold else Theme.Colors.White
			end
		end
	end
	for folder, dot in self.Dots do
		if not seen[folder] then
			dot.Frame:Destroy()
			self.Dots[folder] = nil
		end
	end

	-- Fortschritt des eigenen (bzw. beobachteten) Spielers + erreichte Checkpoints
	self.ProgressFill.Visible = focusAlpha ~= nil
	local reached = focusAlpha or 0
	self.ProgressFill.Size = UDim2.fromScale(reached, 1)
	for _, tick in self.Ticks do
		local passed = reached >= tick.Alpha
		if passed ~= tick.Passed then
			tick.Passed = passed
			tick.Frame.BackgroundColor3 = if passed then Theme.Colors.Accent else Theme.Colors.TextDim
			if passed then
				Components.Pop(tick.Frame, 1.8, 0.35)
			end
		end
	end
end

function RaceHud:_updateStandings(spectateTarget: Player?)
	local folders = self.Ctx.ClientState.Racers:GetChildren()
	table.sort(folders, function(a, b)
		return (a:GetAttribute("Placement") or 99) < (b:GetAttribute("Placement") or 99)
	end)
	local focusId = if spectateTarget then spectateTarget.UserId else player.UserId
	local focusPlacement = nil
	local alive = 0
	local pulse = 0.5 + 0.5 * math.sin(os.clock() * 12)
	local seen = {}
	for index, folder in folders do
		seen[folder] = true
		local row = self:_rowFor(folder)
		row.Frame.LayoutOrder = index
		local status = folder:GetAttribute("Status") or "Racing"
		local placement = folder:GetAttribute("Placement") or index
		local active = status == "Racing" or status == "Finished" or status == "Survived"
		if status == "Racing" then
			alive += 1
		end
		if folder:GetAttribute("UserId") == focusId then
			focusPlacement = placement
		end

		local name = folder:GetAttribute("Name") or "?"
		if row.Name.Text ~= name then
			row.Name.Text = name
		end
		local style = tostring(placement) .. (if active then "+" else "-")
		if style ~= row.LastStyle then
			row.LastStyle = style
			row.Placement.Text = tostring(placement)
			row.BadgeGradient.Color = pairSequence(placeGradient(placement, active))
			local color = if row.IsLocal then Theme.Colors.Accent:Lerp(Theme.Colors.White, 0.25) else Theme.Colors.Text
			row.Name.TextColor3 = if active then color else Theme.Colors.TextDim
			-- Überholt? Plakette hüpft
			if row.LastPlacement and active and placement < row.LastPlacement then
				Components.Pop(row.Badge, 1.35, 0.35)
			end
			row.LastPlacement = placement
		end

		local danger = folder:GetAttribute("DangerTime") or 0
		if danger > 0 and status == "Racing" then
			setChip(row, "GEFAHR", Theme.Colors.Danger)
			row.Chip.BackgroundTransparency = 0.25 + 0.5 * pulse
		else
			local chip = STATUS_CHIPS[status]
			setChip(row, chip and chip.Text, chip and chip.Color)
		end
	end
	for folder, row in self.Rows do
		if not seen[folder] then
			row.Frame:Destroy()
			self.Rows[folder] = nil
		end
	end
	self.Standings.Size = UDim2.fromOffset(264, 50 + #folders * 32)
	local aliveText = string.format("%s %d/%d", Theme.Icons.Players, alive, #folders)
	if self.AliveLabel.Text ~= aliveText then
		self.AliveLabel.Text = aliveText
	end

	-- Platz-Plakette neben dem Timer
	self.PlaceBadge.Visible = focusPlacement ~= nil
	if focusPlacement and focusPlacement ~= self.LastPlace then
		local improved = self.LastPlace ~= nil and focusPlacement < self.LastPlace
		self.LastPlace = focusPlacement
		self.PlaceLabel.Text = tostring(focusPlacement)
		self.PlaceGradient.Color = pairSequence(placeGradient(focusPlacement, true))
		if improved then
			Components.Pop(self.PlaceBadge, 1.3, 0.4)
		end
	end
	local ofText = "VON " .. tostring(#folders)
	if self.PlaceOf.Text ~= ofText then
		self.PlaceOf.Text = ofText
	end
end

-- Countdown-Zahl/-Wort mit Pop, Drehung und Schockwelle anzeigen
function RaceHud:_popCountdown(text: string, style: number, scale: number)
	local pair = COUNTDOWN_STYLE[style] or Theme.Gradients.Accent
	local countdown = self.Countdown
	countdown.Text = text
	countdown.TextSize = if style >= 1 and style <= 3 then 160 else 120
	countdown.TextTransparency = 0
	countdown.Rotation = -14
	self.CountdownStroke.Transparency = 0
	self.CountdownGradient.Color = pairSequence(pair)
	self.CountdownScale.Scale = scale
	Components.Tween(self.CountdownScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
	Components.Tween(countdown, 0.45, { Rotation = 0 }, Enum.EasingStyle.Back)
	local shock = self.Shock
	shock.Size = UDim2.fromOffset(140, 140)
	shock.Visible = true
	self.ShockStroke.Color = pair[1]
	self.ShockStroke.Transparency = 0.1
	Components.Tween(shock, 0.6, { Size = UDim2.fromOffset(580, 580) }, Enum.EasingStyle.Quart)
	Components.Tween(self.ShockStroke, 0.6, { Transparency = 1 })
end

function RaceHud:_updateCountdown(phase: string, gameState, serverNow: number, watching: boolean)
	local audio = self.Ctx.AudioController
	if phase == "Countdown" and watching then
		local remaining = (gameState:GetAttribute("PhaseEndsAt") or 0) - serverNow
		local number = math.ceil(remaining)
		if number >= 1 and number <= 3 then
			self.Countdown.Visible = true
			if self.LastCountdown ~= number then
				self.LastCountdown = number
				self:_popCountdown(tostring(number), number, 2.2)
				audio:Play("Countdown")
			end
		else
			self.Countdown.Visible = number > 3
			self.Shock.Visible = false
			if number > 3 and self.LastCountdown ~= 4 then
				self.LastCountdown = 4
				self:_popCountdown("BEREIT?", 4, 1.4)
			end
		end
		return
	end
	if phase == "Racing" and watching then
		local startedAt = gameState:GetAttribute("RaceStartedAt") or 0
		local elapsed = serverNow - startedAt
		if elapsed < 0.9 then
			if self.LastCountdown ~= 0 then
				self.LastCountdown = 0
				self:_popCountdown("LOS!", 0, 2.4)
				audio:Play("Go")
			end
			-- Zum Ende hin ausblenden
			local fade = math.clamp((elapsed - 0.55) / 0.35, 0, 1)
			self.Countdown.TextTransparency = fade
			self.CountdownStroke.Transparency = fade
			self.Countdown.Visible = true
			return
		end
	end
	self.Countdown.Visible = false
	self.Shock.Visible = false
	if phase ~= "Countdown" and phase ~= "Racing" then
		self.LastCountdown = nil
	end
end

-- Banner-Band setzen (nil = ausblenden); pair = Verlaufspaar der Farbe
function RaceHud:_setBanner(text: string?, pair)
	if not text then
		self.Banner.Visible = false
		self.BannerPair = nil
		return
	end
	local changed = self.BannerLabel.Text ~= text
	if changed then
		self.BannerLabel.Text = text
	end
	if not self.Banner.Visible or self.BannerPair ~= pair then
		self.BannerPair = pair
		self.BannerGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, pair[2]),
			ColorSequenceKeypoint.new(0.5, pair[1]),
			ColorSequenceKeypoint.new(1, pair[2]),
		})
		local stroke = self.BannerLabel:FindFirstChild("TextStroke")
		if stroke then
			stroke.Color = pair[2]:Lerp(Theme.Colors.Black, 0.65)
		end
		self.Banner.Visible = true
		Components.Pop(self.Banner, 1.25, 0.4)
	elseif changed then
		Components.Pop(self.Banner, 1.06, 0.2)
	end
end

function RaceHud:_updateZone(gameState, serverNow: number, localRacing: boolean, watching: boolean)
	local zoneState = gameState:GetAttribute("ZoneState") or "Inactive"
	if zoneState ~= self.LastZoneState then
		if zoneState == "Shrinking" then
			self.BannerText = "⚠  DIE GEFAHRENZONE SCHRUMPFT!  ⚠"
			self.BannerUntil = os.clock() + 2.5
			self.Ctx.AudioController:Play("Warning")
		elseif zoneState == "Final" then
			self.BannerText = "⚠  FINALE ZONE – NUR DIE SCHNELLSTEN ÜBERLEBEN!  ⚠"
			self.BannerUntil = os.clock() + 2.5
			self.Ctx.AudioController:Play("Warning")
		end
		self.LastZoneState = zoneState
	end
	if watching and zoneState == "Warning" then
		local remaining = math.max(0, math.ceil((gameState:GetAttribute("ZoneShrinkAt") or 0) - serverNow))
		self:_setBanner(string.format("GEFAHRENZONE AKTIV IN %d", remaining), Theme.Gradients.Warning)
	elseif watching and os.clock() < self.BannerUntil then
		self:_setBanner(self.BannerText or "", Theme.Gradients.Danger)
	else
		self:_setBanner(nil)
	end

	-- Eigene Gefahr
	local intensity = 0
	local remainingDanger = nil
	local delay = Config.HazardZone.EliminationDelay
	if localRacing then
		local folder = self.Ctx.ClientState.Racers:FindFirstChild(tostring(player.UserId))
		local danger = folder and folder:GetAttribute("DangerTime") or 0
		if danger > 0 then
			intensity = 0.45 + 0.5 * math.clamp(danger / delay, 0, 1)
			remainingDanger = math.max(0, delay - danger)
		elseif zoneState == "Shrinking" or zoneState == "Final" then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root then
				local gap = root.Position.X - (gameState:GetAttribute("ZoneX") or -1e6)
				if gap < 30 then
					intensity = 0.35 * (1 - math.clamp(gap / 30, 0, 1))
				end
			end
		end
	end
	local clock = os.clock()
	local pulse = if intensity > 0.4 then (0.85 + math.sin(clock * 10) * 0.15) else 1
	for _, frame in self.Vignette do
		frame.BackgroundTransparency = 1 - intensity * pulse
	end
	self.DangerTint.BackgroundTransparency = 1 - math.max(0, intensity - 0.4) * 0.22 * pulse

	-- Warnkarte mit Restzeit
	self.DangerPanel.Visible = remainingDanger ~= nil
	if remainingDanger then
		local text = string.format("%.1f s", remainingDanger)
		if self.DangerTime.Text ~= text then
			self.DangerTime.Text = text
		end
		self.SetDangerBar(remainingDanger / math.max(0.01, delay))
		self.DangerScale.Scale = 1 + 0.035 * math.sin(clock * 12)
	end
end

function RaceHud:_updateControls()
	local ctx = self.Ctx
	local device = ctx.InputController:GetDevice()
	local hints = KEY_HINTS[device] or KEY_HINTS.Keyboard
	local itemId = player:GetAttribute("HeldItem") or ""
	local item = ItemDefinitions.Get(itemId)
	setKeyCap(self.SlotKeyCap, self.SlotKeyLabel, if item then hints.Item else "")
	if itemId ~= self.LastItem then
		self.LastItem = itemId
		if item then
			Components.SetIconColor(self.SlotIcon, item.Color)
			self.SlotGlyph.Text = ITEM_GLYPHS[item.Id] or Theme.Icons.Star
			self.SlotGlyph.TextStrokeTransparency = 1
			self.SlotGlyph.TextTransparency = 0
			self.SlotName.Text = item.Short
			self.SlotName.TextColor3 = item.Color:Lerp(Theme.Colors.White, 0.35)
			self.SlotKey.Text = "EINSETZEN"
			self.SlotKey.TextColor3 = Theme.Colors.Text
			self.SlotGlow.Visible = true
			self.SlotGlow.BackgroundColor3 = item.Color
			self.SlotGlowStroke.Color = item.Color
			if self.SlotStroke then
				self.SlotStroke.Color = item.Color
			end
			Components.Pop(self.SlotIcon, 1.4, 0.4)
		else
			Components.SetIconColor(self.SlotIcon, Theme.Colors.PanelLight)
			self.SlotGlyph.Text = "?"
			self.SlotGlyph.TextStrokeTransparency = 0.5
			self.SlotGlyph.TextTransparency = 0.45
			self.SlotName.Text = "KEIN ITEM"
			self.SlotName.TextColor3 = Theme.Colors.TextDim
			self.SlotKey.Text = "Box einsammeln"
			self.SlotKey.TextColor3 = Theme.Colors.TextDim
			self.SlotGlow.Visible = false
			if self.SlotStroke then
				self.SlotStroke.Color = Theme.Colors.Stroke
			end
		end
	end

	local cooldowns = ctx.MovementController:GetCooldowns()
	local clock = os.clock()
	local function render(key: string, remaining: number, max: number, active: boolean, ready: boolean)
		local entry = self.AbilityBoxes[key]
		setKeyCap(entry.Cap, entry.CapLabel, hints[key] or "")
		local cooling = remaining > 0 and max > 0
		entry.SetRing(if cooling then 1 - math.clamp(remaining / max, 0, 1) else 1)
		if cooling then
			local text = string.format("%.1f", remaining)
			if entry.Timer.Text ~= text then
				entry.Timer.Text = text
			end
		end
		local state = if active then "Active" elseif cooling then "Cooling" elseif ready then "Ready" else "Blocked"
		if state ~= entry.State then
			local previous = entry.State
			entry.State = state
			local ringColor = if state == "Cooling" then Theme.Colors.Stroke elseif state == "Blocked" then Theme.Colors.PanelLight else entry.Color
			for _, disc in entry.Discs do
				disc.BackgroundColor3 = ringColor
			end
			entry.Glyph.Visible = not cooling
			entry.Timer.Visible = cooling
			entry.Glyph.TextTransparency = if state == "Blocked" then 0.55 else 0
			entry.Name.Text = if state == "Active" then "AKTIV" else entry.Label
			entry.Name.TextColor3 = if state == "Active"
				then entry.Color:Lerp(Theme.Colors.White, 0.3)
				elseif state == "Ready" then Theme.Colors.Text
				else Theme.Colors.TextDim
			if entry.Stroke then
				entry.Stroke.Color = if state == "Active" or state == "Ready" then entry.Color:Lerp(Theme.Colors.Stroke, 0.3) else Theme.Colors.Stroke
				entry.Stroke.Thickness = if state == "Active" then 3 else 1.5
				entry.Stroke.Transparency = 0.1
			end
			-- Wieder bereit: Ring hüpft kurz
			if (state == "Ready" or state == "Active") and previous == "Cooling" then
				Components.Pop(entry.Ring, 1.2, 0.3)
			end
		end
		if state == "Active" and entry.Stroke then
			entry.Stroke.Transparency = 0.1 + 0.35 * (0.5 + 0.5 * math.sin(clock * 14))
		end
	end
	render("Grapple", cooldowns.Grapple, cooldowns.GrappleMax, cooldowns.Grappling, cooldowns.Grapple <= 0 and cooldowns.HasTarget)
	render("Dash", cooldowns.Dash, cooldowns.DashMax, false, cooldowns.Dash <= 0 and cooldowns.DashAvailable)
	render("Slide", cooldowns.Slide, cooldowns.SlideMax, ctx.MovementController:GetState() == "Slide", cooldowns.Slide <= 0)
end

function RaceHud:_updateIndicators(watching: boolean)
	local camera = workspace.CurrentCamera
	local index = 0
	if watching and camera then
		local viewport = camera.ViewportSize
		local focusPlayer = self.Ctx.CameraController:GetSpectate() or player
		for _, folder in self.Ctx.ClientState.Racers:GetChildren() do
			if folder:GetAttribute("Status") == "Racing" then
				local other = Players:GetPlayerByUserId(folder:GetAttribute("UserId") or 0)
				local character = other and other ~= focusPlayer and other.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root and index < #self.Indicators then
					local screen, onScreen = camera:WorldToViewportPoint(root.Position)
					local inside = onScreen and screen.X > 0 and screen.X < viewport.X and screen.Y > 0 and screen.Y < viewport.Y
					if not inside then
						index += 1
						local indicator = self.Indicators[index]
						local margin = 70
						local x = math.clamp(screen.X, margin, viewport.X - margin)
						local y = math.clamp(screen.Y, margin, viewport.Y - margin)
						if not onScreen then
							-- Hinter der Kamera: horizontal spiegeln
							x = viewport.X - x
						end
						local logical = self.UI:ToLogical(Vector2.new(x, y))
						indicator.Frame.Position = UDim2.fromOffset(logical.X, logical.Y)
						indicator.Frame.Visible = true
						local center = viewport / 2
						local direction = Vector2.new(screen.X, screen.Y) - center
						indicator.Arrow.Rotation = math.deg(math.atan2(direction.Y, direction.X))
						local focusCharacter = focusPlayer.Character
						local focusRoot = focusCharacter and focusCharacter:FindFirstChild("HumanoidRootPart")
						local distance = if focusRoot then math.floor(math.abs(root.Position.X - focusRoot.Position.X)) else 0
						indicator.Label.Text = string.format("%s · %dm", other.DisplayName, distance)
					end
				end
			end
		end
	end
	for i = index + 1, #self.Indicators do
		self.Indicators[i].Frame.Visible = false
	end
end

return RaceHud
