--[[
	Stats  (ModuleScript)
	Pfad: StarterPlayer/StarterPlayerScripts/Client/UI/Screens/Stats

	Spielerstatistiken, Ranked-Saison, tägliche Aufgaben und Erfolge in drei
	Glas-Spalten (Kopf mit Symbol-Blase, Verlaufslinie und Zähler-Chip):
		STATISTIK   Kacheln (Level, Siege, Siegquote), Werte-Zeilen,
		            Ranked-Saison mit Rang-Chip, Bestzeiten je Map
		AUFGABEN    Karten mit Symbol, Belohnungs-Chips (Münze/XP) und
		            Verlaufs-Fortschrittsbalken
		ERFOLGE     Karten mit Pokal (freigeschaltet) bzw. Schloss
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Progression = require(Shared.Progression)
local MapDefinitions = require(Shared.MapDefinitions)
local QuestDefinitions = require(Shared.QuestDefinitions)

local UI = script.Parent.Parent
local Components = require(UI.Components)
local Theme = require(UI.Theme)

local new = Components.new

local Stats = {}
Stats.__index = Stats

function Stats.new(ui)
	local self = setmetatable({}, Stats)
	self.UI = ui
	local modal = Components.Modal({
		Name = "Stats",
		Title = "STATISTIK & AUFGABEN",
		Icon = Theme.Icons.Stats,
		Accent = Theme.Colors.Accent,
		Size = UDim2.fromOffset(1000, 600),
		Parent = ui.Root,
	})
	self.Modal = modal
	ui:RegisterModal("Stats", modal)

	-- Spalte: Glas-Karte mit Kopf (Symbol, Titel, Zähler-Chip) und Scrollbereich
	local function column(index: number, title: string, icon: string, color: Color3)
		local _, panel = Components.Card({
			Name = title,
			Position = UDim2.new((index - 1) / 3, (index - 1) * 4, 0, 0),
			Size = UDim2.new(1 / 3, -8, 1, -6),
			BackgroundColor3 = Theme.Colors.PanelDark,
			CornerRadius = 16,
			ShadowOffset = 4,
			ShadowSpread = 5,
			Parent = modal.Content,
		})
		local _, glyph = Components.Icon({ Glyph = icon, Color = color, Size = 32, TextSize = 17, Position = UDim2.fromOffset(12, 9), Parent = panel })
		glyph.TextStrokeTransparency = 1
		Components.Heading({
			Text = title,
			TextSize = 18,
			TextScaled = true,
			MaxTextSize = 18,
			Outline = 1.5,
			RichText = false,
			Position = UDim2.fromOffset(52, 11),
			Size = UDim2.new(1, -140, 0, 28),
			Parent = panel,
		})
		local pill, pillLabel = Components.Pill({
			Text = "",
			Color = color,
			Size = UDim2.fromOffset(70, 22),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 14),
			TextSize = 12,
			Parent = panel,
		})
		pill.Visible = false
		Components.Divider({ Position = UDim2.fromOffset(12, 48), Size = UDim2.new(1, -24, 0, 2), Colors = { color, Theme.Colors.Accent2 }, Parent = panel })
		local scroll = new("ScrollingFrame", {
			Position = UDim2.fromOffset(10, 58),
			Size = UDim2.new(1, -16, 1, -66),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 5,
			ScrollBarImageColor3 = Theme.Colors.Stroke,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			Parent = panel,
		}, { Components.List(Enum.FillDirection.Vertical, 6) })
		return scroll, pill, pillLabel
	end
	self.StatsList = column(1, "STATISTIK", Theme.Icons.Stats, Theme.Colors.Accent)
	self.QuestList, self.QuestPill, self.QuestCount = column(2, "TÄGLICHE AUFGABEN", Theme.Icons.Training, Theme.Colors.Success)
	self.AchievementList, self.AchievementPill, self.AchievementCount = column(3, "ERFOLGE", Theme.Icons.Leaderboard, Theme.Colors.Gold)

	modal.OnOpen = function()
		self:_render()
	end
	return self
end

function Stats:Start()
	self.UI.Ctx.ClientState.ProfileChanged:Connect(function()
		if self.Modal.IsOpen() then
			self:_render()
		end
	end)
end

local function clear(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- Werte-Zeile (Beschriftung links, Wert rechts; jede zweite leicht hinterlegt).
-- indent: zusätzlicher Abstand links (Platz für einen Farbpunkt)
function Stats:_statRow(order: number, label: string, value: string, color: Color3?, indent: number?)
	local row = new("Frame", {
		BackgroundColor3 = Theme.Colors.White,
		BackgroundTransparency = if order % 2 == 0 then 0.95 else 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -6, 0, 26),
		LayoutOrder = order,
		Parent = self.StatsList,
	})
	Components.Corner(6).Parent = row
	Components.Label({
		Text = label,
		Font = Theme.Fonts.Medium,
		TextColor3 = Theme.Colors.TextDim,
		TextSize = Theme.TextSize.Small - 1,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		RichText = false,
		Position = UDim2.fromOffset(8 + (indent or 0), 0),
		Size = UDim2.new(0.62, -8 - (indent or 0), 1, 0),
		Parent = row,
	})
	Components.Label({
		Text = value,
		Font = Theme.Fonts.Title,
		TextSize = 16,
		TextColor3 = color or Theme.Colors.Text,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
		RichText = false,
		Position = UDim2.fromScale(0.62, 0),
		Size = UDim2.new(0.38, -8, 1, 0),
		Parent = row,
	})
	return row
end

-- Abschnittsüberschrift mit Verlaufslinie und optionalem Chip
function Stats:_section(order: number, text: string, color: Color3, chipText: string?, chipColor: Color3?)
	local frame = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -6, 0, 36), LayoutOrder = order, Parent = self.StatsList })
	Components.Label({
		Text = text,
		Font = Theme.Fonts.Title,
		TextSize = 15,
		TextColor3 = color,
		TextWrapped = false,
		RichText = false,
		TextStrokeTransparency = 0.6,
		TextStrokeColor3 = Theme.Colors.Shadow,
		Position = UDim2.fromOffset(4, 10),
		Size = UDim2.new(1, -100, 0, 20),
		Parent = frame,
	})
	if chipText then
		Components.Pill({
			Text = chipText,
			Color = chipColor or color,
			Size = UDim2.fromOffset(96, 22),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -4, 0, 9),
			TextSize = 12,
			Parent = frame,
		})
	end
	Components.Divider({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 2), Colors = { color, color }, Parent = frame })
end

-- Drei Kacheln oben in der Statistik-Spalte
function Stats:_heroTiles(tiles)
	local frame = new("Frame", { Name = "Tiles", BackgroundTransparency = 1, Size = UDim2.new(1, -6, 0, 74), LayoutOrder = 0, Parent = self.StatsList }, {
		Components.List(Enum.FillDirection.Horizontal, 6),
	})
	for index, tile in tiles do
		local box = new("Frame", {
			Size = UDim2.new(1 / 3, -4, 1, 0),
			BackgroundColor3 = Theme.Colors.White,
			BorderSizePixel = 0,
			LayoutOrder = index,
			Parent = frame,
		})
		Components.Corner(12).Parent = box
		Components.Gradient({ tile.Color:Lerp(Theme.Colors.Panel, 0.55), tile.Color:Lerp(Theme.Colors.PanelDark, 0.85) }, 90).Parent = box
		Components.Stroke(tile.Color, 1.5, 0.35).Parent = box
		Components.Heading({
			Text = tile.Value,
			TextSize = 24,
			TextScaled = true,
			MaxTextSize = 24,
			TextColor3 = tile.Color:Lerp(Theme.Colors.White, 0.3),
			TextXAlignment = Enum.TextXAlignment.Center,
			Outline = 2,
			RichText = false,
			Position = UDim2.fromOffset(4, 10),
			Size = UDim2.new(1, -8, 0, 30),
			Parent = box,
		})
		Components.Label({
			Text = tile.Label,
			Font = Theme.Fonts.Title,
			TextSize = 11,
			TextColor3 = Theme.Colors.TextDim,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = false,
			RichText = false,
			Position = UDim2.fromOffset(2, 46),
			Size = UDim2.new(1, -4, 0, 16),
			Parent = box,
		})
	end
end

-- Kleiner Belohnungs-Chip: Münze + Zahl
local function coinChip(parent: Instance, coins: number, position: UDim2, anchor: Vector2?)
	local chip = new("Frame", {
		Name = "CoinChip",
		BackgroundTransparency = 1,
		AnchorPoint = anchor or Vector2.zero,
		Position = position,
		Size = UDim2.fromOffset(70, 18),
		Parent = parent,
	}, { Components.List(Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center) })
	Components.CoinIcon(16, { Parent = chip })
	Components.Label({
		Text = "+" .. Util.FormatNumber(coins),
		Font = Theme.Fonts.Title,
		TextSize = 14,
		TextColor3 = Theme.Colors.Gold,
		TextWrapped = false,
		RichText = false,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 18),
		Parent = chip,
	})
	return chip
end

function Stats:_render()
	local profile = self.UI.Ctx.ClientState.Profile
	if not profile then
		return
	end
	clear(self.StatsList)
	clear(self.QuestList)
	clear(self.AchievementList)

	local s = profile.Stats
	self:_heroTiles({
		{ Label = "LEVEL", Value = tostring(profile.Level), Color = Theme.Colors.Accent },
		{ Label = "SIEGE", Value = Util.FormatNumber(s.Wins), Color = Theme.Colors.Gold },
		{ Label = "SIEGQUOTE", Value = if s.Races > 0 then string.format("%d%%", math.floor(s.Wins / s.Races * 100 + 0.5)) else "–", Color = Theme.Colors.Accent2 },
	})
	local order = 0
	local function add(label, value, color)
		order += 1
		self:_statRow(order, label, value, color)
	end
	local function section(text, color, chipText, chipColor)
		order += 1
		self:_section(order, text, color, chipText, chipColor)
	end
	add("Gesamt-XP", Util.FormatNumber(profile.TotalXP), Theme.Colors.XP:Lerp(Theme.Colors.White, 0.3))
	add("Coins", Util.FormatNumber(profile.Coins), Theme.Colors.Gold)
	add("Rennen", Util.FormatNumber(s.Races))
	add("Top 3", Util.FormatNumber(s.Top3))
	add("Ziel erreicht", Util.FormatNumber(s.Finishes))
	add("Ausgeschieden", Util.FormatNumber(s.Eliminated))
	add("Greifhaken (Rennen)", Util.FormatNumber(s.Grapples))
	add("Power-ups (Rennen)", Util.FormatNumber(s.PowerUps))
	add("Strecke gesamt", Util.FormatNumber(s.Distance) .. " m")
	local ranked = profile.Ranked
	local tier = Progression.GetTier(ranked.Rating)
	section(Theme.Icons.Ranked .. " RANKED · SAISON " .. tostring(ranked.Season or Config.Ranked.Season), Theme.Colors.Gold, string.upper(tier.Name), tier.Color)
	add("Rang", tier.Name, tier.Color)
	add("Rating", tostring(ranked.Rating), tier.Color)
	add("Höchstwert", tostring(ranked.Peak))
	add("Ranked-Spiele / Siege", string.format("%d / %d", ranked.Games, ranked.Wins))
	section("⏱ BESTZEITEN", Theme.Colors.Accent)
	for _, mapId in MapDefinitions.Order do
		local definition = MapDefinitions.Maps[mapId]
		local best = s.BestTimes and s.BestTimes[mapId]
		local accent = definition.Theme and definition.Theme.Accent or Theme.Colors.Accent
		order += 1
		local row = self:_statRow(order, definition.Name, if best then Util.FormatTime(best) else "–", if best then Theme.Colors.Text else Theme.Colors.TextDim, 20)
		-- Farbpunkt der Map vor dem Namen
		local dot = new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 8, 0.5, 0),
			Size = UDim2.fromOffset(12, 12),
			BackgroundColor3 = accent,
			BorderSizePixel = 0,
			Parent = row,
		})
		new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = dot })
		Components.Stroke(Theme.Colors.White, 1.5, 0.4).Parent = dot
	end
	if profile.Persistent == false then
		add("Speichern", "Studio: aus", Theme.Colors.Warning)
	end

	-- Aufgaben
	local done, total = 0, 0
	for index, entry in profile.Quests and profile.Quests.List or {} do
		local quest = QuestDefinitions.DailyLookup[entry.Id]
		if quest then
			total += 1
			if entry.Done then
				done += 1
			end
			self:_questCard(index, quest, entry)
		end
	end
	self.QuestPill.Visible = total > 0
	self.QuestCount.Text = string.format("%d / %d", done, total)
	Components.Label({
		Text = Theme.Icons.Info .. "  Neue Aufgaben gibt es jeden Tag (UTC). Belohnungen werden automatisch gutgeschrieben.",
		Font = Theme.Fonts.Medium,
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, -6, 0, 34),
		LayoutOrder = 99,
		Parent = self.QuestList,
	})

	-- Erfolge
	local unlockedCount = 0
	for index, achievement in QuestDefinitions.Achievements do
		local unlocked = profile.Achievements and profile.Achievements[achievement.Id] == true
		if unlocked then
			unlockedCount += 1
		end
		self:_achievementCard(index, achievement, unlocked)
	end
	self.AchievementPill.Visible = true
	self.AchievementCount.Text = string.format("%d / %d", unlockedCount, #QuestDefinitions.Achievements)
end

function Stats:_questCard(index: number, quest, entry)
	local done = entry.Done == true
	local color = if done then Theme.Colors.Success else Theme.Colors.Accent
	local card = Components.Panel({
		Size = UDim2.new(1, -6, 0, 96),
		BackgroundColor3 = if done then Theme.Colors.Success:Lerp(Theme.Colors.Panel, 0.8) else Theme.Colors.Panel,
		StrokeColor = if done then Theme.Colors.Success else Theme.Colors.Stroke,
		StrokeTransparency = if done then 0.05 else 0.4,
		CornerRadius = 12,
		LayoutOrder = index,
		Parent = self.QuestList,
	})
	local _, glyph = Components.Icon({
		Glyph = if done then Theme.Icons.Check else Theme.Icons.Training,
		Color = color,
		Size = 38,
		TextSize = if done then 18 else 20,
		Position = UDim2.fromOffset(10, 10),
		Parent = card,
	})
	if not done then
		glyph.TextStrokeTransparency = 1
	end
	Components.Label({
		Text = quest.Name,
		Font = Theme.Fonts.Bold,
		TextSize = Theme.TextSize.Small,
		TextScaled = true,
		MaxTextSize = Theme.TextSize.Small,
		RichText = false,
		Position = UDim2.fromOffset(56, 8),
		Size = UDim2.new(1, -64, 0, 20),
		Parent = card,
	})
	-- Belohnungs-Chips
	local rewards = new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(56, 32),
		Size = UDim2.new(1, -64, 0, 20),
		Parent = card,
	}, { Components.List(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
	coinChip(rewards, quest.Coins, UDim2.new())
	Components.Pill({ Text = string.format("+%d XP", quest.XP), Color = Theme.Colors.XP, Size = UDim2.fromOffset(64, 20), TextSize = 12, Parent = rewards })
	local _, set = Components.ProgressBar({
		Position = UDim2.fromOffset(10, 64),
		Size = UDim2.new(1, -110, 0, 14),
		BackgroundColor = Theme.Colors.Shadow,
		BackgroundTransparency = 0.3,
		Color = color,
		Gradient = if done then Theme.Gradients.Success else Theme.Gradients.Play,
		CornerRadius = 7,
		Parent = card,
	})
	set(entry.Progress / quest.Goal)
	Components.Label({
		Text = if done then Theme.Icons.Check .. " ERLEDIGT" else string.format("%s / %s", Util.FormatNumber(entry.Progress), Util.FormatNumber(quest.Goal)),
		Font = Theme.Fonts.Title,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
		RichText = false,
		TextColor3 = if done then Theme.Colors.Success else Theme.Colors.Text,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 61),
		Size = UDim2.fromOffset(92, 20),
		Parent = card,
	})
end

function Stats:_achievementCard(index: number, achievement, unlocked: boolean)
	local card = Components.Panel({
		Size = UDim2.new(1, -6, 0, 68),
		BackgroundColor3 = if unlocked then Theme.Colors.Gold:Lerp(Theme.Colors.Panel, 0.82) else Theme.Colors.Panel,
		StrokeColor = if unlocked then Theme.Colors.Gold else Theme.Colors.Stroke,
		StrokeTransparency = if unlocked then 0.05 else 0.45,
		CornerRadius = 12,
		LayoutOrder = index,
		Parent = self.AchievementList,
	})
	local _, glyph = Components.Icon({
		Glyph = if unlocked then Theme.Icons.Leaderboard else Theme.Icons.Lock,
		Color = if unlocked then Theme.Colors.Gold else Theme.Colors.PanelLight,
		Size = 42,
		TextSize = 21,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Parent = card,
	})
	glyph.TextStrokeTransparency = 1
	glyph.TextTransparency = if unlocked then 0 else 0.35
	Components.Label({
		Text = achievement.Name,
		Font = Theme.Fonts.Bold,
		TextSize = Theme.TextSize.Small,
		TextScaled = true,
		MaxTextSize = Theme.TextSize.Small,
		TextColor3 = if unlocked then Theme.Colors.Gold:Lerp(Theme.Colors.White, 0.25) else Theme.Colors.Text,
		RichText = false,
		Position = UDim2.fromOffset(62, 8),
		Size = UDim2.new(1, -140, 0, 20),
		Parent = card,
	})
	coinChip(card, achievement.Coins, UDim2.new(1, -10, 0, 9), Vector2.new(1, 0))
	Components.Label({
		Text = achievement.Description,
		Font = Theme.Fonts.Medium,
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.Colors.TextDim,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(62, 30),
		Size = UDim2.new(1, -72, 0, 32),
		Parent = card,
	})
end

return Stats
