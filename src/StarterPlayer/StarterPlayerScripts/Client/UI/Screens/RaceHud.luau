--[[
	RaceHud  (ModuleScript)
	Pfad: StarterPlayer/StarterPlayerScripts/Client/UI/Screens/RaceHud

	Renn-Oberfläche:
		- Countdown (3-2-1-LOS!), Renn-Timer, Map/Modus
		- Streckenfortschritt mit allen Spielern, Checkpoints und Gefahrenzone
		- Live-Platzierungen
		- Gefahrenring-Warnung (Banner, roter Bildschirmrand, Restzeit)
		- Power-up-Slot und Cooldown-Anzeigen (Haken, Dash, Slide)
		- Ereignis-Feed, Ausgeschieden-Panel, Zuschauermodus
		- Pfeile für Spieler außerhalb des Bildschirms
	Im Training werden nur Item-Slot und Cooldowns angezeigt.

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

local RaceHud = {}
RaceHud.__index = RaceHud

local KEY_HINTS = {
	Keyboard = { Grapple = "E", Dash = "SHIFT", Slide = "SHIFT", Item = "Q" },
	Gamepad = { Grapple = "X", Dash = "B", Slide = "B", Item = "Y" },
	Touch = { Grapple = "", Dash = "", Slide = "", Item = "" },
}

local STATUS_TEXT = {
	Racing = "",
	Eliminated = "RAUS",
	Left = "WEG",
	Finished = "ZIEL",
	Survived = "",
}

local REASON_TEXT = {
	Zone = "von der Gefahrenzone erwischt",
	Left = "hat das Spiel verlassen",
}

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

	local root = new("Frame", { Name = "RaceHud", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = ui.Root })
	self.Root = root

	-- Gefahren-Vignette (vier Ränder mit Farbverlauf)
	self.Vignette = {}
	local edges = {
		{ Size = UDim2.new(0, 220, 1, 0), Position = UDim2.fromScale(0, 0), Rotation = 0 },
		{ Size = UDim2.new(0, 220, 1, 0), Position = UDim2.new(1, -220, 0, 0), Rotation = 180 },
		{ Size = UDim2.new(1, 0, 0, 160), Position = UDim2.fromScale(0, 0), Rotation = 90 },
		{ Size = UDim2.new(1, 0, 0, 160), Position = UDim2.new(0, 0, 1, -160), Rotation = 270 },
	}
	for _, edge in edges do
		local frame = new("Frame", {
			Size = edge.Size,
			Position = edge.Position,
			BackgroundColor3 = Theme.Colors.Danger,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Parent = root,
		})
		new("UIGradient", {
			Rotation = edge.Rotation,
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
			Parent = frame,
		})
		table.insert(self.Vignette, frame)
	end

	-- Kopfbereich: Map, Timer, Fortschritt
	local top = new("Frame", {
		Name = "Top",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(660, 110),
		Parent = root,
	})
	self.Top = top
	self.MapLabel = Components.Label({
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = Theme.TextSize.Small,
		Font = Theme.Fonts.Bold,
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, 0, 0, 18),
		Parent = top,
	})
	self.TimerLabel = Components.Label({
		Text = "0:00.00",
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 40,
		Font = Theme.Fonts.Title,
		Position = UDim2.fromOffset(0, 18),
		Size = UDim2.new(1, 0, 0, 44),
		TextStrokeTransparency = 0.6,
		Parent = top,
	})
	local track = new("Frame", {
		Name = "Track",
		Position = UDim2.new(0, 30, 0, 74),
		Size = UDim2.new(1, -60, 0, 14),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Parent = top,
	})
	Components.Corner(7).Parent = track
	Components.Stroke(Theme.Colors.Stroke, 1.5).Parent = track
	self.Track = track
	self.ZoneFill = new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Colors.Danger,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = track,
	})
	Components.Corner(7).Parent = self.ZoneFill
	Components.Label({
		Text = "ZIEL",
		Font = Theme.Fonts.Title,
		TextSize = 12,
		TextColor3 = Theme.Colors.Gold,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(1, 6, 0.5, 0),
		Size = UDim2.fromOffset(40, 14),
		Parent = track,
	})
	self.TickHolder = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = track })
	self.DotHolder = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = track })

	self.Banner = Components.Label({
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Theme.Fonts.Title,
		TextSize = 30,
		TextColor3 = Theme.Colors.Danger,
		TextStrokeTransparency = 0.4,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 128),
		Size = UDim2.fromOffset(700, 40),
		Visible = false,
		Parent = root,
	})

	self.Countdown = Components.Label({
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Theme.Fonts.Title,
		TextSize = 140,
		TextStrokeTransparency = 0.3,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(600, 170),
		Visible = false,
		Parent = root,
	})
	self.CountdownScale = new("UIScale", { Parent = self.Countdown })

	self.DangerLabel = Components.Label({
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Theme.Fonts.Title,
		TextSize = 34,
		TextColor3 = Theme.Colors.White,
		TextStrokeColor3 = Theme.Colors.Danger,
		TextStrokeTransparency = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 96),
		Size = UDim2.fromOffset(700, 44),
		Visible = false,
		Parent = root,
	})

	-- Platzierungen
	self.Standings = Components.Panel({
		Name = "Standings",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 140),
		Size = UDim2.fromOffset(250, 40),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.2,
		Parent = root,
	})
	Components.Padding(8).Parent = self.Standings
	Components.List(Enum.FillDirection.Vertical, 4).Parent = self.Standings

	-- Item-Slot
	local slot = Components.Panel({
		Name = "ItemSlot",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -24, 1, -24),
		Size = UDim2.fromOffset(124, 124),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.1,
		CornerRadius = 18,
		Parent = root,
	})
	self.Slot = slot
	self.SlotScale = new("UIScale", { Parent = slot })
	if UserInputService.TouchEnabled then
		-- Auf Touch-Geräten liegt unten rechts der Sprungbutton
		slot.AnchorPoint = Vector2.new(1, 0)
		slot.Position = UDim2.new(1, -16, 0, 410)
		slot.Size = UDim2.fromOffset(110, 110)
	end
	self.SlotIcon = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(56, 56),
		BackgroundColor3 = Theme.Colors.PanelLight,
		BorderSizePixel = 0,
		Rotation = 45,
		Parent = slot,
	})
	Components.Corner(10).Parent = self.SlotIcon
	self.SlotName = Components.Label({
		Text = "KEIN ITEM",
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Theme.Fonts.Title,
		TextSize = 15,
		Position = UDim2.new(0, 4, 1, -44),
		Size = UDim2.new(1, -8, 0, 20),
		Parent = slot,
	})
	self.SlotKey = Components.Label({
		Text = "Q",
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Theme.Fonts.Bold,
		TextSize = 13,
		TextColor3 = Theme.Colors.TextDim,
		Position = UDim2.new(0, 4, 1, -22),
		Size = UDim2.new(1, -8, 0, 16),
		Parent = slot,
	})

	-- Fähigkeiten
	local abilities = new("Frame", {
		Name = "Abilities",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(300, 66),
		Parent = root,
	}, { Components.List(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center) })
	self.Abilities = abilities
	self.AbilityBoxes = {}
	for index, info in { { "Grapple", "HAKEN" }, { "Dash", "DASH" }, { "Slide", "SLIDE" } } do
		local box = Components.Panel({
			Size = UDim2.fromOffset(90, 62),
			BackgroundColor3 = Theme.Colors.PanelDark,
			BackgroundTransparency = 0.15,
			LayoutOrder = index,
			ClipsDescendants = true,
			Parent = abilities,
		})
		local fill = new("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 0),
			BackgroundColor3 = Theme.Colors.Black,
			BackgroundTransparency = 0.4,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = box,
		})
		local name = Components.Label({
			Text = info[2],
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = Theme.Fonts.Title,
			TextSize = 16,
			Position = UDim2.fromOffset(0, 10),
			Size = UDim2.new(1, 0, 0, 20),
			ZIndex = 2,
			Parent = box,
		})
		local key = Components.Label({
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = Theme.Fonts.Bold,
			TextSize = 12,
			TextColor3 = Theme.Colors.TextDim,
			Position = UDim2.fromOffset(0, 34),
			Size = UDim2.new(1, 0, 0, 16),
			ZIndex = 2,
			Parent = box,
		})
		self.AbilityBoxes[info[1]] = { Box = box, Fill = fill, Name = name, Key = key, Stroke = box:FindFirstChildOfClass("UIStroke") }
	end

	-- Ereignis-Feed
	self.Feed = new("Frame", {
		Name = "Feed",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.62, 0),
		Size = UDim2.fromOffset(400, 200),
		Parent = root,
	}, { Components.List(Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Bottom) })
	self.FeedCount = 0

	-- Ausgeschieden
	local eliminated = Components.Panel({
		Name = "Eliminated",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromOffset(480, 170),
		BackgroundColor3 = Theme.Colors.PanelDark,
		StrokeColor = Theme.Colors.Danger,
		Visible = false,
		Parent = root,
	})
	self.EliminatedPanel = eliminated
	Components.Label({
		Text = "AUSGESCHIEDEN",
		Font = Theme.Fonts.Title,
		TextSize = 38,
		TextColor3 = Theme.Colors.Danger,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(1, 0, 0, 44),
		Parent = eliminated,
	})
	self.EliminatedInfo = Components.Label({
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Theme.Fonts.Medium,
		Position = UDim2.fromOffset(0, 60),
		Size = UDim2.new(1, 0, 0, 24),
		Parent = eliminated,
	})
	local spectateButton = Components.Button({
		Text = "ZUSCHAUEN",
		Position = UDim2.new(0.5, -210, 1, -64),
		Size = UDim2.fromOffset(200, 48),
		Color = Theme.Colors.Accent,
		TextColor = Theme.Colors.Background,
		OnClick = function()
			self.EliminatedPanel.Visible = false
			self:StartSpectating()
		end,
	})
	spectateButton.Parent = eliminated
	local lobbyButton = Components.Button({
		Text = "ZUR LOBBY",
		Position = UDim2.new(0.5, 10, 1, -64),
		Size = UDim2.fromOffset(200, 48),
		OnClick = function()
			self.EliminatedPanel.Visible = false
		end,
	})
	lobbyButton.Parent = eliminated

	-- Zuschauermodus
	local spectate = Components.Panel({
		Name = "Spectate",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -100),
		Size = UDim2.fromOffset(520, 60),
		BackgroundColor3 = Theme.Colors.PanelDark,
		Visible = false,
		Parent = root,
	})
	self.SpectatePanel = spectate
	self.SpectateLabel = Components.Label({
		Text = "",
		Font = Theme.Fonts.Bold,
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(1, -300, 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
		Parent = spectate,
	})
	local prev = Components.Button({
		Text = "◀",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -212, 0.5, 0),
		Size = UDim2.fromOffset(48, 42),
		OnClick = function()
			self:_cycleSpectate(-1)
		end,
	})
	prev.Parent = spectate
	local nextButton = Components.Button({
		Text = "▶",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -158, 0.5, 0),
		Size = UDim2.fromOffset(48, 42),
		OnClick = function()
			self:_cycleSpectate(1)
		end,
	})
	nextButton.Parent = spectate
	local stop = Components.Button({
		Text = "BEENDEN",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(140, 42),
		Color = Theme.Colors.Danger,
		OnClick = function()
			self.Ctx.CameraController:SetSpectate(nil)
		end,
	})
	stop.Parent = spectate

	-- Pfeile für Spieler außerhalb des Bildes
	self.Indicators = {}
	for i = 1, 7 do
		local indicator = new("Frame", {
			Name = "Offscreen" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(120, 40),
			BackgroundTransparency = 1,
			Visible = false,
			Parent = root,
		})
		local arrow = Components.Label({
			Name = "Arrow",
			Text = "▶",
			Font = Theme.Fonts.Title,
			TextSize = 22,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromOffset(24, 24),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.3),
			TextStrokeTransparency = 0.3,
			Parent = indicator,
		})
		local label = Components.Label({
			Name = "Name",
			Text = "",
			TextSize = 12,
			Font = Theme.Fonts.Bold,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromScale(0, 0.55),
			Size = UDim2.new(1, 0, 0, 16),
			TextStrokeTransparency = 0.3,
			TextWrapped = false,
			Parent = indicator,
		})
		self.Indicators[i] = { Frame = indicator, Arrow = arrow, Label = label }
	end
	return self
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
			end
		else
			self:_feed(string.format("<b>%s</b> ist raus (Platz %d) – %s", payload.Name or "?", payload.Placement or 0, REASON_TEXT[payload.Reason] or "ausgeschieden"), Theme.Colors.Danger)
		end
	end)
	state:On("RacerFinished", function(payload)
		self:_feed(string.format("<b>%s</b> hat das Ziel erreicht! (%s)", payload.Name or "?", Util.FormatTime(payload.Time or 0)), Theme.Colors.Gold)
	end)
	state:On("PowerUpUsed", function(payload)
		local item = ItemDefinitions.Get(payload.ItemId)
		local who = Players:GetPlayerByUserId(payload.UserId)
		if item and who and who ~= player and item.Offensive then
			self:_feed(string.format("<b>%s</b> setzt %s ein", who.DisplayName, item.Name), item.Color)
		end
	end)
	state:On("StatusApplied", function(payload)
		if payload.UserId == player.UserId then
			self:_feed(if payload.Kind == "Slowed" then "Du wurdest eingefroren!" else "Du bist in eine Falle getappt!", Theme.Colors.Warning)
		end
	end)
	state:On("ShieldBlocked", function(payload)
		if payload.UserId == player.UserId then
			self:_feed("Dein Schild hat einen Angriff geblockt!", Theme.Colors.Accent)
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

function RaceHud:_feed(text: string, color: Color3)
	self.FeedCount += 1
	local entry = Components.Label({
		Text = text,
		TextSize = Theme.TextSize.Small,
		Font = Theme.Fonts.Medium,
		TextColor3 = color,
		TextStrokeTransparency = 0.5,
		Size = UDim2.new(1, 0, 0, 20),
		LayoutOrder = self.FeedCount,
		Parent = self.Feed,
	})
	local entries = {}
	for _, child in self.Feed:GetChildren() do
		if child:IsA("TextLabel") then
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
			Components.Tween(entry, 0.4, { TextTransparency = 1, TextStrokeTransparency = 1 })
			task.wait(0.45)
			entry:Destroy()
		end
	end)
end

function RaceHud:_clearFeed()
	for _, child in self.Feed:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
end

function RaceHud:_buildTicks()
	self.TickHolder:ClearAllChildren()
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
			new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(alpha, 0.5),
				Size = UDim2.fromOffset(2, 10),
				BackgroundColor3 = Theme.Colors.TextDim,
				BorderSizePixel = 0,
				Parent = self.TickHolder,
			})
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

function RaceHud:_rowFor(folder)
	local row = self.Rows[folder]
	if row and row.Frame.Parent then
		return row
	end
	local frame = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), Parent = self.Standings })
	local placement = Components.Label({ Text = "", Font = Theme.Fonts.Title, TextSize = 18, Size = UDim2.fromOffset(30, 26), Parent = frame })
	local name = Components.Label({
		Text = "",
		Font = Theme.Fonts.Bold,
		TextSize = 16,
		Position = UDim2.fromOffset(32, 0),
		Size = UDim2.new(1, -92, 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
		Parent = frame,
	})
	local status = Components.Label({
		Text = "",
		Font = Theme.Fonts.Bold,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(58, 26),
		Parent = frame,
	})
	row = { Frame = frame, Placement = placement, Name = name, Status = status }
	self.Rows[folder] = row
	return row
end

function RaceHud:_dotFor(folder)
	local dot = self.Dots[folder]
	if dot and dot.Parent then
		return dot
	end
	local isLocal = folder:GetAttribute("UserId") == player.UserId
	local size = if isLocal then 18 else 12
	dot = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = if isLocal then Theme.Colors.Accent else Theme.Colors.White,
		BorderSizePixel = 0,
		ZIndex = if isLocal then 6 else 5,
		Parent = self.DotHolder,
	})
	Components.Corner(size // 2).Parent = dot
	if isLocal then
		Components.Stroke(Theme.Colors.White, 2).Parent = dot
	end
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
		self.SpectateLabel.Text = "ZUSCHAUEN: " .. spectateTarget.DisplayName
	end
	if not matchActive then
		self.EliminatedPanel.Visible = false
	end

	-- Kopfbereich
	if watching then
		local definition = MapDefinitions.Get(gameState:GetAttribute("MapId") or "")
		local mode = if gameState:GetAttribute("Mode") == "Ranked" then "RANKED" else "SCHNELLES SPIEL"
		self.MapLabel.Text = string.format("%s · %s", if definition then string.upper(definition.Name) else "", mode)
		local startedAt = gameState:GetAttribute("RaceStartedAt") or 0
		if phase == "Racing" and startedAt > 0 then
			self.TimerLabel.Text = Util.FormatTime(serverNow - startedAt)
		elseif phase == "Results" and self.FinalTime then
			self.TimerLabel.Text = Util.FormatTime(self.FinalTime)
		elseif phase == "Countdown" then
			self.TimerLabel.Text = "0:00.00"
		end
		self:_updateTrack(gameState)
		self:_updateStandings()
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

function RaceHud:_updateTrack(gameState)
	local startX = gameState:GetAttribute("StartX") or 0
	local finishX = gameState:GetAttribute("FinishX") or 0
	local length = math.max(1, finishX - startX)
	if #self.TickHolder:GetChildren() == 0 and (gameState:GetAttribute("CheckpointXs") or "") ~= "" then
		self:_buildTicks()
	end
	local zoneState = gameState:GetAttribute("ZoneState") or "Inactive"
	local zoneX = gameState:GetAttribute("ZoneX") or -1e6
	local zoneAlpha = if zoneState == "Shrinking" or zoneState == "Final" then math.clamp((zoneX - startX) / length, 0, 1) else 0
	self.ZoneFill.Size = UDim2.fromScale(zoneAlpha, 1)

	local seen = {}
	for _, folder in self.Ctx.ClientState.Racers:GetChildren() do
		seen[folder] = true
		local dot = self:_dotFor(folder)
		local progress = folder:GetAttribute("Progress") or 0
		local status = folder:GetAttribute("Status")
		dot.Position = UDim2.fromScale(math.clamp(progress / length, 0, 1), 0.5)
		dot.Visible = status == "Racing" or status == "Finished" or status == "Survived"
	end
	for folder, dot in self.Dots do
		if not seen[folder] then
			dot:Destroy()
			self.Dots[folder] = nil
		end
	end
end

function RaceHud:_updateStandings()
	local folders = self.Ctx.ClientState.Racers:GetChildren()
	table.sort(folders, function(a, b)
		return (a:GetAttribute("Placement") or 99) < (b:GetAttribute("Placement") or 99)
	end)
	local seen = {}
	for index, folder in folders do
		seen[folder] = true
		local row = self:_rowFor(folder)
		row.Frame.LayoutOrder = index
		local status = folder:GetAttribute("Status") or "Racing"
		local isLocal = folder:GetAttribute("UserId") == player.UserId
		row.Placement.Text = tostring(folder:GetAttribute("Placement") or index)
		row.Name.Text = folder:GetAttribute("Name") or "?"
		row.Status.Text = STATUS_TEXT[status] or ""
		local active = status == "Racing" or status == "Finished" or status == "Survived"
		local color = if isLocal then Theme.Colors.Accent else Theme.Colors.Text
		if not active then
			color = Theme.Colors.TextDim
		end
		row.Name.TextColor3 = color
		row.Placement.TextColor3 = if folder:GetAttribute("Placement") == 1 and active then Theme.Colors.Gold else color
		row.Status.TextColor3 = if status == "Finished" then Theme.Colors.Gold else Theme.Colors.Danger
		local danger = folder:GetAttribute("DangerTime") or 0
		if danger > 0 and status == "Racing" then
			row.Status.Text = "GEFAHR"
		end
	end
	for folder, row in self.Rows do
		if not seen[folder] then
			row.Frame:Destroy()
			self.Rows[folder] = nil
		end
	end
	self.Standings.Size = UDim2.fromOffset(250, 16 + #folders * 30)
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
				self.Countdown.Text = tostring(number)
				self.Countdown.TextColor3 = Theme.Colors.White
				self.CountdownScale.Scale = 1.6
				Components.Tween(self.CountdownScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
				audio:Play("Countdown")
			end
		else
			self.Countdown.Visible = number > 3
			self.Countdown.Text = "BEREIT?"
			self.Countdown.TextColor3 = Theme.Colors.Accent
		end
		return
	end
	if phase == "Racing" and watching then
		local startedAt = gameState:GetAttribute("RaceStartedAt") or 0
		if serverNow - startedAt < 0.9 then
			if self.LastCountdown ~= 0 then
				self.LastCountdown = 0
				self.Countdown.Text = "LOS!"
				self.Countdown.TextColor3 = Theme.Colors.Success
				self.CountdownScale.Scale = 1.8
				Components.Tween(self.CountdownScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
				audio:Play("Go")
			end
			self.Countdown.Visible = true
			return
		end
	end
	self.Countdown.Visible = false
	if phase ~= "Countdown" and phase ~= "Racing" then
		self.LastCountdown = nil
	end
end

function RaceHud:_updateZone(gameState, serverNow: number, localRacing: boolean, watching: boolean)
	local zoneState = gameState:GetAttribute("ZoneState") or "Inactive"
	if zoneState ~= self.LastZoneState then
		if zoneState == "Shrinking" then
			self.BannerText = "DIE GEFAHRENZONE SCHRUMPFT!"
			self.BannerUntil = os.clock() + 2.5
			self.Ctx.AudioController:Play("Warning")
		elseif zoneState == "Final" then
			self.BannerText = "FINALE ZONE – NUR DIE SCHNELLSTEN ÜBERLEBEN!"
			self.BannerUntil = os.clock() + 2.5
			self.Ctx.AudioController:Play("Warning")
		end
		self.LastZoneState = zoneState
	end
	if watching and zoneState == "Warning" then
		local remaining = math.max(0, math.ceil((gameState:GetAttribute("ZoneShrinkAt") or 0) - serverNow))
		self.Banner.Text = string.format("GEFAHRENZONE AKTIV IN %d", remaining)
		self.Banner.TextColor3 = Theme.Colors.Warning
		self.Banner.Visible = true
	elseif watching and os.clock() < self.BannerUntil then
		self.Banner.Text = self.BannerText or ""
		self.Banner.TextColor3 = Theme.Colors.Danger
		self.Banner.Visible = true
	else
		self.Banner.Visible = false
	end

	-- Eigene Gefahr
	local intensity = 0
	local dangerText = nil
	if localRacing then
		local folder = self.Ctx.ClientState.Racers:FindFirstChild(tostring(player.UserId))
		local danger = folder and folder:GetAttribute("DangerTime") or 0
		local delay = Config.HazardZone.EliminationDelay
		if danger > 0 then
			intensity = 0.45 + 0.5 * math.clamp(danger / delay, 0, 1)
			dangerText = string.format("ZURÜCK NACH VORNE!  %.1f s", math.max(0, delay - danger))
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
	local pulse = if intensity > 0.4 then (0.85 + math.sin(os.clock() * 10) * 0.15) else 1
	for _, frame in self.Vignette do
		frame.BackgroundTransparency = 1 - intensity * pulse
	end
	self.DangerLabel.Visible = dangerText ~= nil
	if dangerText then
		self.DangerLabel.Text = dangerText
	end
end

function RaceHud:_updateControls()
	local ctx = self.Ctx
	local device = ctx.InputController:GetDevice()
	local hints = KEY_HINTS[device] or KEY_HINTS.Keyboard
	local itemId = player:GetAttribute("HeldItem") or ""
	local item = ItemDefinitions.Get(itemId)
	if item then
		self.SlotIcon.BackgroundColor3 = item.Color
		self.SlotName.Text = item.Short
		self.SlotName.TextColor3 = item.Color
		self.SlotKey.Text = if hints.Item ~= "" then "[" .. hints.Item .. "] EINSETZEN" else "EINSETZEN"
	else
		self.SlotIcon.BackgroundColor3 = Theme.Colors.PanelLight
		self.SlotName.Text = "KEIN ITEM"
		self.SlotName.TextColor3 = Theme.Colors.TextDim
		self.SlotKey.Text = "Box einsammeln"
	end

	local cooldowns = ctx.MovementController:GetCooldowns()
	local function render(key: string, remaining: number, max: number, active: boolean, ready: boolean)
		local entry = self.AbilityBoxes[key]
		entry.Fill.Size = UDim2.fromScale(1, if max > 0 then math.clamp(remaining / max, 0, 1) else 0)
		entry.Key.Text = if active then "AKTIV" else (if hints[key] ~= "" then "[" .. hints[key] .. "]" else "")
		if entry.Stroke then
			entry.Stroke.Color = if active then Theme.Colors.Accent elseif ready then Theme.Colors.Stroke else Theme.Colors.PanelDark
		end
		entry.Name.TextColor3 = if ready or active then Theme.Colors.Text else Theme.Colors.TextDim
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
