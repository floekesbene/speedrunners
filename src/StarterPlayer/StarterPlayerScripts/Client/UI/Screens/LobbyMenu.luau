--[[
	LobbyMenu  (ModuleScript)
	Pfad: StarterPlayer/StarterPlayerScripts/Client/UI/Screens/LobbyMenu

	Hauptmenü in der Lobby (links) und Status-Karte (unten mittig):
		- Spielen-Karte: Modus-Wahl (Schnelles Spiel / Ranked), großer
		  SPIELEN-Button (beitreten bzw. Warteschlange verlassen) und
		  Warteschlangenstatus mit Füllstandsbalken
		- Kachel-Menü: Training, Shop, Inventar, Statistik & Aufgaben,
		  Bestenliste, Einstellungen
		- Status-Karte: Warteschlange mit Countdown und nächster Map,
		  laufendes Rennen + Zuschauen/Anstellen, Trainingsleiste
		  (Checkpoint, Verlassen), Bereit-Hinweis
	Mit M (Gamepad: Select) oder dem MENÜ-Button (wichtig für Touch)
	einklappbar; auf reinen Touch-Geräten startet das Menü eingeklappt.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local MapDefinitions = require(Shared.MapDefinitions)

local UI = script.Parent.Parent
local Components = require(UI.Components)
local Theme = require(UI.Theme)

local new = Components.new
local player = Players.LocalPlayer

local MENU_WIDTH = 304
local MENU_OPEN = UDim2.fromOffset(16, 150)
local MENU_CLOSED = UDim2.fromOffset(-MENU_WIDTH - 40, 150)

-- Darstellung der beiden Spielmodi
local MODES = {
	QuickPlay = {
		Label = "SCHNELLES SPIEL",
		Icon = Theme.Icons.Quick,
		Color = Theme.Colors.Accent,
		PlayColor = Theme.Colors.Success,
		PlayGradient = Theme.Gradients.Play,
		Sub = "Schnelles Spiel · ohne Wertung",
		Leave = "QUEUE VERLASSEN",
		Attribute = "QueueQuickPlay",
	},
	Ranked = {
		Label = "RANKED",
		Icon = Theme.Icons.Ranked,
		Color = Theme.Colors.Gold,
		PlayColor = Theme.Colors.Gold,
		PlayGradient = Theme.Gradients.Gold,
		Sub = "Ranked · Punkte für deinen Rang",
		Leave = "RANKED VERLASSEN",
		Attribute = "QueueRanked",
	},
}
local MODE_ORDER = { "QuickPlay", "Ranked" }

-- Kacheln des Menüs: Symbol, Beschriftung, Farbe der Symbol-Blase, Aktion
local TILES = {
	{
		Icon = Theme.Icons.Training,
		Text = "TRAINING",
		Color = Theme.Colors.Success,
		Action = function(ui)
			ui:OpenModal("Practice")
		end,
	},
	{
		Icon = Theme.Icons.Shop,
		Text = "SHOP",
		Color = Theme.Colors.Gold,
		Action = function(ui)
			ui.Screens.Catalog:Open("Shop")
		end,
	},
	{
		Icon = Theme.Icons.Inventory,
		Text = "INVENTAR",
		Color = Theme.Colors.Purple,
		Action = function(ui)
			ui.Screens.Catalog:Open("Inventory")
		end,
	},
	{
		Icon = Theme.Icons.Stats,
		Text = "STATISTIK",
		Color = Theme.Colors.Accent,
		Action = function(ui)
			ui:OpenModal("Stats")
		end,
	},
	{
		Icon = Theme.Icons.Leaderboard,
		Text = "BESTENLISTE",
		Color = Theme.Colors.Orange,
		Action = function(ui)
			ui:OpenModal("Leaderboard")
		end,
	},
	{
		Icon = Theme.Icons.Settings,
		Text = "EINSTELLUNGEN",
		Color = Theme.Colors.PanelLight,
		Action = function(ui)
			ui:OpenModal("Settings")
		end,
	},
}

local LobbyMenu = {}
LobbyMenu.__index = LobbyMenu

local function mapName(id: string?): string
	local definition = id and MapDefinitions.GetAny(id)
	return if definition then definition.Name else "—"
end

function LobbyMenu.new(ui)
	local self = setmetatable({}, LobbyMenu)
	self.UI = ui
	self.Collapsed = false
	self.SelectedMode = "QuickPlay"
	self.LastQueue = ""
	self.PlayKey = nil
	self.CardKey = nil

	local menu = new("Frame", {
		Name = "LobbyMenu",
		BackgroundTransparency = 1,
		Position = MENU_OPEN,
		Size = UDim2.fromOffset(MENU_WIDTH, 440),
		Parent = ui.Root,
	})
	self.Menu = menu

	self:_buildPlayCard(menu)
	self:_buildTiles(menu)
	Components.Label({
		Text = "M: Menü ein/aus · G: Emote",
		TextSize = Theme.TextSize.Tiny - 1,
		Font = Theme.Fonts.Medium,
		TextColor3 = Theme.Colors.TextDim,
		TextStrokeTransparency = 0.7,
		TextStrokeColor3 = Theme.Colors.Shadow,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 420),
		Size = UDim2.fromOffset(MENU_WIDTH, 18),
		Parent = menu,
	})

	self:_buildToggle(ui)
	self:_buildStatusCard(ui)
	return self
end

-- Spielen-Karte: Modus-Wahl, SPIELEN-Button, Warteschlangenstatus
function LobbyMenu:_buildPlayCard(menu: Frame)
	local _, card = Components.Card({
		Name = "PlayCard",
		Size = UDim2.fromOffset(MENU_WIDTH, 218),
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.05,
		StrokeColor = Theme.Colors.Accent:Lerp(Theme.Colors.Stroke, 0.5),
		StrokeThickness = 2,
		CornerRadius = 18,
		Parent = menu,
	})
	-- Akzent-Schimmer im oberen Bereich
	local glow = new("Frame", {
		Name = "Glow",
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(1, -4, 0, 90),
		BackgroundColor3 = Theme.Colors.Accent,
		BorderSizePixel = 0,
		Parent = card,
	})
	Components.Corner(16).Parent = glow
	Components.Gradient(Theme.Colors.Accent, 90, { 0.78, 1 }).Parent = glow

	Components.Label({
		Text = "SPIELMODUS",
		Font = Theme.Fonts.Title,
		TextSize = 13,
		TextColor3 = Theme.Colors.TextDim,
		TextWrapped = false,
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.new(1, -32, 0, 18),
		Parent = card,
	})

	-- Modus-Wahl als Segment-Schalter
	local segments = new("Frame", {
		Name = "Modes",
		Position = UDim2.fromOffset(12, 30),
		Size = UDim2.new(1, -24, 0, 44),
		BackgroundColor3 = Theme.Colors.Shadow,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Parent = card,
	})
	Components.Corner(12).Parent = segments
	Components.Stroke(Theme.Colors.Black, 1, 0.6).Parent = segments
	Components.Padding(4).Parent = segments
	self.ModeButtons = {}
	for index, mode in MODE_ORDER do
		local info = MODES[mode]
		local button = Components.Button({
			Name = mode,
			Text = info.Icon .. " " .. info.Label,
			Size = UDim2.new(0.5, -3, 1, 0),
			Position = if index == 1 then UDim2.new() else UDim2.new(0.5, 3, 0, 0),
			Color = info.Color,
			TextColor = Theme.Colors.White,
			TextSize = 15,
			TextScaled = true,
			CornerRadius = 10,
			OnClick = function()
				self:_selectMode(mode)
			end,
		})
		button.Parent = segments
		self.ModeButtons[mode] = button
	end
	self.QuickButton = self.ModeButtons.QuickPlay
	self.RankedButton = self.ModeButtons.Ranked

	-- Großer SPIELEN-Button
	local play = Components.Button({
		Name = "Play",
		Text = "",
		Position = UDim2.fromOffset(12, 84),
		Size = UDim2.new(1, -24, 0, 76),
		Color = Theme.Colors.Success,
		Gradient = Theme.Gradients.Play,
		CornerRadius = 16,
		OnClick = function()
			self:_toggleQueue(self.SelectedMode)
		end,
	})
	play.Parent = card
	self.PlayButton = play
	local bubble = new("Frame", {
		Name = "Bubble",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(50, 50),
		BackgroundColor3 = Theme.Colors.White,
		BackgroundTransparency = 0.72,
		BorderSizePixel = 0,
		Parent = play,
	})
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = bubble })
	Components.Stroke(Theme.Colors.White, 2, 0.35).Parent = bubble
	self.PlayGlyph = Components.Label({
		Text = Theme.Icons.Play,
		Font = Theme.Fonts.Title,
		TextSize = 24,
		TextColor3 = Theme.Colors.White,
		TextStrokeTransparency = 0.6,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		RichText = false,
		Size = UDim2.fromScale(1, 1),
		Parent = bubble,
	})
	self.PlayTitle = Components.Heading({
		Text = "SPIELEN",
		TextSize = 30,
		TextScaled = true,
		MaxTextSize = 30,
		Position = UDim2.fromOffset(74, 9),
		Size = UDim2.new(1, -84, 0, 34),
		Outline = 2,
		OutlineTransparency = 0.1,
		Parent = play,
	})
	self.PlaySub = Components.Label({
		Text = "",
		Font = Theme.Fonts.Bold,
		TextSize = 13,
		TextColor3 = Theme.Colors.White,
		TextStrokeTransparency = 0.65,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(75, 46),
		Size = UDim2.new(1, -86, 0, 18),
		Parent = play,
	})
	Components.Shine(play, { Interval = 4 })

	-- Warteschlangenstatus
	local status = new("Frame", {
		Name = "QueueStatus",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 168),
		Size = UDim2.new(1, -32, 0, 20),
		Parent = card,
	})
	self.QueueDot = new("Frame", {
		Name = "Dot",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(10, 10),
		BackgroundColor3 = Theme.Colors.TextDim,
		BorderSizePixel = 0,
		Parent = status,
	})
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = self.QueueDot })
	Components.Loop(self.QueueDot, 0.7, { BackgroundTransparency = 0.75 })
	self.QueueLabel = Components.Label({
		Text = "",
		Font = Theme.Fonts.Bold,
		TextSize = 14,
		TextColor3 = Theme.Colors.TextDim,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(18, 0),
		Size = UDim2.new(1, -18, 1, 0),
		Parent = status,
	})
	local bar, setBar = Components.ProgressBar({
		Name = "QueueBar",
		Position = UDim2.fromOffset(16, 196),
		Size = UDim2.new(1, -32, 0, 8),
		BackgroundColor = Theme.Colors.Shadow,
		BackgroundTransparency = 0.3,
		Color = Theme.Colors.Accent,
		Gradient = Theme.Gradients.Play,
		CornerRadius = 4,
		Parent = card,
	})
	self.QueueBar = bar
	self.SetQueueBar = setBar
end

-- Kachel-Menü (3 × 2)
function LobbyMenu:_buildTiles(menu: Frame)
	local grid = new("Frame", {
		Name = "Tiles",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 230),
		Size = UDim2.fromOffset(MENU_WIDTH, 180),
		Parent = menu,
	}, { Components.Grid(UDim2.fromOffset(96, 86), 8) })
	self.Tiles = {}
	for index, tile in TILES do
		local button = Components.IconButton({
			Name = tile.Text,
			Icon = tile.Icon,
			IconColor = tile.Color,
			IconSize = 28,
			Text = tile.Text,
			TextSize = 13,
			Color = Theme.Colors.PanelLight,
			LayoutOrder = index,
			OnClick = function()
				tile.Action(self.UI)
			end,
		})
		button.Parent = grid
		self.Tiles[tile.Text] = button
	end
end

-- Menü-Schalter (wichtig für Touch-Geräte ohne M-Taste) mit animiertem ☰/✕-Symbol
function LobbyMenu:_buildToggle(ui)
	local toggle = Components.Button({
		Name = "MenuToggle",
		Text = "SCHLIESSEN",
		Position = UDim2.fromOffset(596, 74),
		Size = UDim2.fromOffset(150, 48),
		TextSize = 16,
		CornerRadius = 14,
		ZIndex = 2,
		OnClick = function()
			self:ToggleCollapsed()
		end,
	})
	-- Beschriftung rechts neben dem Symbol
	local label = toggle:FindFirstChild("Label")
	if label then
		label.AnchorPoint = Vector2.new(0, 0.5)
		label.Position = UDim2.new(0, 38, 0.5, 0)
		label.Size = UDim2.new(1, -46, 1, 0)
	end
	toggle.Parent = ui.Root
	Components.Shadow(toggle, { Offset = 4, Spread = 4 })
	self.ToggleButton = toggle
	-- Drei Balken (☰), die sich beim Öffnen zu einem ✕ drehen
	local icon = new("Frame", {
		Name = "Hamburger",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(20, 20),
		ZIndex = 2,
		Parent = toggle,
	})
	self.MenuBars = {}
	for index = 1, 3 do
		local bar = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, (index - 2) * 6),
			Size = UDim2.fromOffset(20, 3),
			BackgroundColor3 = Theme.Colors.White,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = icon,
		})
		Components.Corner(2).Parent = bar
		self.MenuBars[index] = bar
	end
	self:_renderToggleIcon(false)
end

function LobbyMenu:_renderToggleIcon(animate: boolean)
	local time = if animate then 0.22 else 0
	local open = not self.Collapsed
	local bars = self.MenuBars
	Components.Tween(bars[1], time, {
		Position = UDim2.new(0.5, 0, 0.5, if open then 0 else -6),
		Rotation = if open then 45 else 0,
	}, Enum.EasingStyle.Back)
	Components.Tween(bars[3], time, {
		Position = UDim2.new(0.5, 0, 0.5, if open then 0 else 6),
		Rotation = if open then -45 else 0,
	}, Enum.EasingStyle.Back)
	Components.Tween(bars[2], time, { BackgroundTransparency = if open then 1 else 0 })
end

-- Status-Karte unten mittig
function LobbyMenu:_buildStatusCard(ui)
	local holder, card = Components.Card({
		Name = "StatusCard",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -20),
		Size = UDim2.fromOffset(580, 104),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.06,
		StrokeThickness = 2,
		CornerRadius = 18,
		Parent = ui.Root,
	})
	self.Card = holder
	self.CardPanel = card
	self.CardStroke = card:FindFirstChild("Border")
	self.CardTint = new("Frame", {
		Name = "Tint",
		Size = UDim2.fromScale(0.55, 1),
		BackgroundColor3 = Theme.Colors.Accent,
		BackgroundTransparency = 0.84,
		BorderSizePixel = 0,
		Parent = card,
	})
	Components.Corner(18).Parent = self.CardTint
	Components.Gradient(Theme.Colors.White, 0, { 0, 1 }).Parent = self.CardTint
	self.CardBar = new("Frame", {
		Name = "SideBar",
		Position = UDim2.fromOffset(7, 12),
		Size = UDim2.new(0, 5, 1, -24),
		BackgroundColor3 = Theme.Colors.Accent,
		BorderSizePixel = 0,
		Parent = card,
	})
	Components.Corner(3).Parent = self.CardBar
	local icon, glyph = Components.Icon({
		Glyph = Theme.Icons.Flag,
		Color = Theme.Colors.Accent,
		Size = 48,
		TextSize = 24,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 22, 0.5, 0),
		Parent = card,
	})
	glyph.TextStrokeTransparency = 1
	self.CardIcon = icon
	self.CardGlyph = glyph

	local textWidth = -(80 + 178)
	self.CardTitle = Components.Heading({
		Text = "",
		TextSize = Theme.TextSize.Large,
		TextScaled = true,
		MaxTextSize = Theme.TextSize.Large,
		TextColor3 = Theme.Colors.Accent,
		Outline = 1.5,
		OutlineTransparency = 0.2,
		Position = UDim2.fromOffset(80, 10),
		Size = UDim2.new(1, textWidth, 0, 28),
		Parent = card,
	})
	self.CardLine1 = Components.Label({
		Text = "",
		Font = Theme.Fonts.Medium,
		TextSize = 16,
		TextScaled = true,
		MaxTextSize = 16,
		Position = UDim2.fromOffset(80, 40),
		Size = UDim2.new(1, textWidth, 0, 22),
		Parent = card,
	})
	self.CardLine2 = Components.Label({
		Text = "",
		Font = Theme.Fonts.Medium,
		TextSize = Theme.TextSize.Tiny,
		TextScaled = true,
		MaxTextSize = Theme.TextSize.Tiny + 1,
		TextColor3 = Theme.Colors.TextDim,
		Position = UDim2.fromOffset(80, 63),
		Size = UDim2.new(1, textWidth, 0, 20),
		Parent = card,
	})
	local progress, setProgress = Components.ProgressBar({
		Name = "CardProgress",
		Position = UDim2.fromOffset(80, 88),
		Size = UDim2.new(1, textWidth, 0, 6),
		BackgroundColor = Theme.Colors.Shadow,
		BackgroundTransparency = 0.2,
		Color = Theme.Colors.Accent,
		Gradient = Theme.Gradients.Play,
		CornerRadius = 3,
		Parent = card,
	})
	self.CardProgress = progress
	self.SetCardProgress = setProgress

	self.CardButton = Components.Button({
		Name = "Primary",
		Text = "",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(160, 56),
		Color = Theme.Colors.Accent,
		TextColor = Theme.Colors.White,
		TextSize = Theme.TextSize.Large - 2,
		Font = Theme.Fonts.Title,
		CornerRadius = 14,
		OnClick = function()
			if self.CardAction then
				self.CardAction()
			end
		end,
	})
	self.CardButton.Parent = card
	self.CardButton2 = Components.Button({
		Name = "Secondary",
		Text = "",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 10),
		Size = UDim2.fromOffset(160, 38),
		TextSize = Theme.TextSize.Small,
		Visible = false,
		OnClick = function()
			if self.CardAction2 then
				self.CardAction2()
			end
		end,
	})
	self.CardButton2.Parent = card
end

function LobbyMenu:Start()
	-- Auf reinen Touch-Geräten startet das Menü eingeklappt (Platz für die Steuerung)
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		self:ToggleCollapsed()
	end
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.15 then
			accumulator = 0
			self:_refresh()
		end
	end)
	self:_refresh()
end

--- True, wenn das Menü gerade sichtbar und ausgeklappt ist.
function LobbyMenu:IsOpen(): boolean
	return self.Menu.Visible and not self.Collapsed
end

function LobbyMenu:ToggleCollapsed()
	self.Collapsed = not self.Collapsed
	self.ToggleButton.Text = if self.Collapsed then "MENÜ" else "SCHLIESSEN"
	self:_renderToggleIcon(true)
	Components.Tween(
		self.Menu,
		if self.Collapsed then 0.25 else 0.35,
		{ Position = if self.Collapsed then MENU_CLOSED else MENU_OPEN },
		if self.Collapsed then Enum.EasingStyle.Quad else Enum.EasingStyle.Back,
		if self.Collapsed then Enum.EasingDirection.In else Enum.EasingDirection.Out
	)
end

function LobbyMenu:_toggleQueue(mode: string)
	local queued = player:GetAttribute("Queue") or ""
	if queued == mode then
		Remotes.QueueRequest:FireServer("Leave", mode)
	else
		Remotes.QueueRequest:FireServer("Join", mode)
	end
end

function LobbyMenu:_selectMode(mode: string)
	if self.SelectedMode ~= mode then
		self.SelectedMode = mode
		Components.Pop(self.PlayButton, 1.05, 0.3)
	end
	self:_refreshPlay(player:GetAttribute("Queue") or "")
end

-- Spielen-Karte an Modus-Wahl und Warteschlange anpassen
function LobbyMenu:_refreshPlay(queue: string)
	local gameState = self.UI.Ctx.ClientState.GameState
	local selected = MODES[self.SelectedMode] or MODES.QuickPlay
	for mode, button in self.ModeButtons do
		local active = mode == self.SelectedMode
		local border = button:FindFirstChild("Border")
		button.BackgroundTransparency = if active then 0 else 1
		button.TextColor3 = if active then Theme.Colors.White else Theme.Colors.TextDim
		if border then
			border.Transparency = if active then 0.05 else 1
		end
	end

	local maxPlayers = gameState:GetAttribute("MaxPlayers") or 8
	local minPlayers = gameState:GetAttribute("MinPlayers") or 2
	local queuedHere = queue == self.SelectedMode
	local key
	if queuedHere then
		key = "Leave" .. self.SelectedMode
		self.PlayTitle.Text = selected.Leave
		self.PlayGlyph.Text = Theme.Icons.Close
		self.PlaySub.Text = "Du wartest auf das nächste Rennen …"
	else
		key = "Join" .. self.SelectedMode
		self.PlayTitle.Text = "SPIELEN"
		self.PlayGlyph.Text = Theme.Icons.Play
		self.PlaySub.Text = if queue ~= "" then "Wechselt in diese Warteschlange" else selected.Sub
	end
	if key ~= self.PlayKey then
		self.PlayKey = key
		if queuedHere then
			Components.SetButtonColor(self.PlayButton, Theme.Colors.Danger)
		else
			Components.SetButtonColor(self.PlayButton, selected.PlayColor, selected.PlayGradient)
		end
		local stroke = self.PlayTitle:FindFirstChild("TextStroke")
		if stroke then
			local _, bottom = Theme.GradientFor(if queuedHere then Theme.Colors.Danger else selected.PlayColor)
			stroke.Color = bottom:Lerp(Theme.Colors.Black, 0.55)
		end
	end

	if queue ~= "" then
		local info = MODES[queue] or MODES.QuickPlay
		local count = gameState:GetAttribute(info.Attribute) or 0
		self.QueueDot.BackgroundColor3 = Theme.Colors.Success
		self.QueueLabel.TextColor3 = Theme.Colors.Text
		self.QueueLabel.Text = string.format("%s %s · %d / %d Spieler", Theme.Icons.Queue, info.Label, count, maxPlayers)
		self.QueueBar.Visible = true
		self.SetQueueBar(count / math.max(1, maxPlayers), 0.3)
	else
		self.QueueDot.BackgroundColor3 = Theme.Colors.TextDim
		self.QueueLabel.TextColor3 = Theme.Colors.TextDim
		self.QueueLabel.Text = string.format("Nächste Map: %s · ab %d Spielern", mapName(gameState:GetAttribute("NextMapId")), minPlayers)
		self.QueueBar.Visible = false
	end
end

function LobbyMenu:_setCard(title: string, line1: string, line2: string, buttonText: string?, action, color: Color3?, icon: string?, accent: Color3?, progress: number?)
	local accentColor = accent or Theme.Colors.Accent
	self.CardTitle.Text = title
	self.CardTitle.TextColor3 = accentColor:Lerp(Theme.Colors.White, 0.2)
	self.CardLine1.Text = line1
	self.CardLine2.Text = line2
	self.CardButton.Visible = buttonText ~= nil
	self.CardButton.Text = buttonText or ""
	self.CardAction = action
	self.CardProgress.Visible = progress ~= nil
	if progress then
		self.SetCardProgress(progress, 0.3)
	end
	-- Farben/Symbol nur bei Zustandswechsel neu setzen (mit kleinem Hüpfer)
	local key = title .. "|" .. tostring(buttonText) .. "|" .. tostring(icon)
	if key ~= self.CardKey then
		self.CardKey = key
		Components.SetButtonColor(self.CardButton, color or Theme.Colors.Accent)
		Components.SetIconColor(self.CardIcon, accentColor)
		self.CardGlyph.Text = icon or Theme.Icons.Flag
		self.CardBar.BackgroundColor3 = accentColor
		self.CardTint.BackgroundColor3 = accentColor
		if self.CardStroke then
			self.CardStroke.Color = accentColor:Lerp(Theme.Colors.Stroke, 0.5)
		end
		Components.Pop(self.CardIcon, 1.2, 0.4)
	end
end

function LobbyMenu:_setSecond(text: string?, action)
	self.CardButton2.Visible = text ~= nil
	self.CardButton2.Text = text or ""
	self.CardAction2 = action
	if text then
		self.CardButton.Position = UDim2.new(1, -14, 1, -10)
		self.CardButton.AnchorPoint = Vector2.new(1, 1)
		self.CardButton.Size = UDim2.fromOffset(160, 40)
	else
		self.CardButton.Position = UDim2.new(1, -14, 0.5, 0)
		self.CardButton.AnchorPoint = Vector2.new(1, 0.5)
		self.CardButton.Size = UDim2.fromOffset(160, 56)
	end
end

function LobbyMenu:_refresh()
	local ctx = self.UI.Ctx
	local state = ctx.ClientState
	local gameState = state.GameState
	local spectating = ctx.CameraController:GetSpectate() ~= nil
	local inRace = state:IsInRace()
	local visible = not inRace and not spectating
	self.Menu.Visible = visible
	self.Card.Visible = visible
	self.ToggleButton.Visible = visible
	if not visible then
		return
	end

	local queue = player:GetAttribute("Queue") or ""
	local course = state:GetPracticeCourse()
	local phase = gameState:GetAttribute("Phase") or "Waiting"
	local nextMap = mapName(gameState:GetAttribute("NextMapId"))
	local minPlayers = gameState:GetAttribute("MinPlayers") or 2
	local maxPlayers = gameState:GetAttribute("MaxPlayers") or 8

	-- Beim Beitritt (egal über welchen Button) den passenden Modus vorwählen
	if queue ~= self.LastQueue then
		self.LastQueue = queue
		if queue ~= "" and MODES[queue] then
			self.SelectedMode = queue
		end
	end
	self:_refreshPlay(queue)

	self:_setSecond(nil)
	if course ~= "" then
		local queueInfo = if queue ~= "" then "  ·  In Warteschlange" else ""
		self:_setCard(
			"TRAINING: " .. string.upper(mapName(course)),
			"Keine Wertung, keine Belohnungen – übe in Ruhe." .. queueInfo,
			"R = zum Checkpoint  ·  Das Rennen holt dich automatisch ab.",
			"VERLASSEN",
			function()
				Remotes.PracticeRequest:FireServer("Leave")
			end,
			Theme.Colors.Danger,
			Theme.Icons.Training,
			Theme.Colors.Success
		)
		self:_setSecond("CHECKPOINT", function()
			Remotes.PracticeRequest:FireServer("Reset")
		end)
	elseif queue ~= "" then
		local info = MODES[queue] or MODES.QuickPlay
		local count = gameState:GetAttribute(info.Attribute) or 0
		local modeName = if queue == "Ranked" then "RANKED" else "SCHNELLES SPIEL"
		local line2 = "Nächste Map: " .. nextMap
		if phase == "Starting" and gameState:GetAttribute("Mode") == queue then
			local remaining = math.max(0, math.ceil((gameState:GetAttribute("PhaseEndsAt") or 0) - workspace:GetServerTimeNow()))
			line2 = string.format("Rennen startet in %d s  ·  Map: %s", remaining, nextMap)
		elseif phase ~= "Waiting" and phase ~= "Starting" then
			line2 = "Ein Rennen läuft – du bist in der nächsten Runde dabei."
		end
		self:_setCard(
			"WARTESCHLANGE · " .. modeName,
			string.format("%d / %d Spieler (mindestens %d)", count, maxPlayers, minPlayers),
			line2,
			"VERLASSEN",
			function()
				Remotes.QueueRequest:FireServer("Leave", queue)
			end,
			Theme.Colors.Danger,
			Theme.Icons.Queue,
			info.Color,
			math.clamp(count / math.max(1, minPlayers), 0, 1)
		)
	elseif (phase == "Countdown" or phase == "Racing" or phase == "Loading") and (gameState:GetAttribute("MapId") or "") ~= "" then
		local alive = gameState:GetAttribute("Alive") or 0
		local participants = gameState:GetAttribute("Participants") or 0
		self:_setCard(
			"RENNEN LÄUFT · " .. string.upper(mapName(gameState:GetAttribute("MapId"))),
			string.format("%d von %d Spielern noch im Rennen", alive, participants),
			"Stell dich an, um in der nächsten Runde dabei zu sein.",
			"ZUSCHAUEN",
			function()
				self.UI.Screens.RaceHud:StartSpectating()
			end,
			Theme.Colors.Accent2,
			Theme.Icons.Spectate,
			Theme.Colors.Accent2
		)
		self:_setSecond("ANSTELLEN", function()
			Remotes.QueueRequest:FireServer("Join", "QuickPlay")
		end)
	else
		self:_setCard(
			"BEREIT FÜR DAS NÄCHSTE RENNEN?",
			"Nächste Map: " .. nextMap,
			string.format("Mindestens %d Spieler · bis zu %d pro Rennen", minPlayers, maxPlayers),
			"SPIELEN",
			function()
				Remotes.QueueRequest:FireServer("Join", "QuickPlay")
			end,
			Theme.Colors.Success,
			Theme.Icons.Flag,
			Theme.Colors.Accent
		)
	end
end

return LobbyMenu
