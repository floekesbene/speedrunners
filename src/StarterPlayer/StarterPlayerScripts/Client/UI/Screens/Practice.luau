--[[
	Practice  (ModuleScript)
	Pfad: StarterPlayer/StarterPlayerScripts/Client/UI/Screens/Practice

	Auswahl des Trainingsmodus: Bewegungs-Tutorial oder freies Training auf
	einer der Rennstrecken (ohne Gefahrenzone, ohne Belohnungen).

	Darstellung: Hinweis-Leiste oben, darunter je Strecke eine Glas-Karte mit
	Vorschaubild (Verlauf in den Theme-Farben der Map + Symbol), Name,
	Schwierigkeits-Chip mit Sternen, Beschreibung und START-Button.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local MapDefinitions = require(Shared.MapDefinitions)

local UI = script.Parent.Parent
local Components = require(UI.Components)
local Theme = require(UI.Theme)

local new = Components.new

local Practice = {}
Practice.__index = Practice

-- Symbol je Strecke (Unicode/Emoji)
local MAP_GLYPHS = {
	Tutorial = "🎓",
	NeonMetropolis = "🌃",
	MagmaWorks = "🌋",
	SkywayRuins = "☁️",
	GlacierCircuit = "🏔️",
	JungleVelocity = "🌴",
}

local DIFFICULTY = {
	{ Text = "LEICHT", Color = Theme.Colors.Success },
	{ Text = "MITTEL", Color = Theme.Colors.Warning },
	{ Text = "SCHWER", Color = Theme.Colors.Danger },
}

function Practice.new(ui)
	local self = setmetatable({}, Practice)
	self.UI = ui
	local modal = Components.Modal({
		Name = "Practice",
		Title = "TRAINING",
		Icon = Theme.Icons.Training,
		Accent = Theme.Colors.Success,
		Size = UDim2.fromOffset(900, 580),
		Parent = ui.Root,
	})
	self.Modal = modal
	ui:RegisterModal("Practice", modal)

	-- Hinweis-Leiste
	local info = new("Frame", {
		Name = "Info",
		BackgroundColor3 = Theme.Colors.Accent,
		BackgroundTransparency = 0.88,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 52),
		Parent = modal.Content,
	})
	Components.Corner(12).Parent = info
	Components.Stroke(Theme.Colors.Accent, 1.5, 0.5).Parent = info
	Components.Icon({
		Glyph = Theme.Icons.Info,
		Color = Theme.Colors.Accent,
		Size = 32,
		TextSize = 18,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Parent = info,
	})
	Components.Label({
		Text = "Übe Bewegung, Greifhaken und Abkürzungen ohne Druck. Im Training gibt es keine Gefahrenzone, keine Coins, keine XP und keine Statistiken. Startet ein Rennen, wirst du automatisch abgeholt.",
		Font = Theme.Fonts.Medium,
		TextSize = Theme.TextSize.Small - 1,
		TextScaled = true,
		MaxTextSize = Theme.TextSize.Small - 1,
		TextColor3 = Theme.Colors.Text,
		Position = UDim2.fromOffset(52, 5),
		Size = UDim2.new(1, -64, 1, -10),
		Parent = info,
	})

	local list = new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 62),
		Size = UDim2.new(1, 0, 1, -62),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Colors.Stroke,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = modal.Content,
	}, { Components.List(Enum.FillDirection.Vertical, 10), Components.Padding(4, 8, 8, 2) })

	local courses = { MapDefinitions.Tutorial }
	for _, id in MapDefinitions.Order do
		table.insert(courses, MapDefinitions.Maps[id])
	end
	for index, definition in courses do
		self:_courseCard(list, index, definition)
	end
	return self
end

function Practice:_courseCard(list: Instance, index: number, definition)
	local theme = definition.Theme or {}
	local accent = theme.Accent or Theme.Colors.Accent
	local accent2 = theme.Accent2 or Theme.Colors.Accent2
	local difficulty = math.clamp(definition.Difficulty or 1, 1, 3)
	local isTutorial = definition.Id == MapDefinitions.Tutorial.Id
	local _, card = Components.Card({
		Name = definition.Id,
		Size = UDim2.new(1, -6, 0, 96),
		BackgroundColor3 = Theme.Colors.PanelDark,
		StrokeColor = accent,
		StrokeTransparency = 0.3,
		CornerRadius = 14,
		ShadowOffset = 3,
		ShadowSpread = 4,
		LayoutOrder = index,
		Parent = list,
	})
	-- Schimmer in der Map-Farbe von links
	local tint = new("Frame", {
		Name = "Tint",
		Size = UDim2.fromScale(0.6, 1),
		BackgroundColor3 = accent,
		BackgroundTransparency = 0.7,
		BorderSizePixel = 0,
		Parent = card,
	})
	Components.Corner(14).Parent = tint
	Components.Gradient(Theme.Colors.White, 0, { 0.3, 1 }).Parent = tint

	-- Vorschaubild: Verlauf aus den Theme-Farben + Symbol
	local thumb = new("Frame", {
		Name = "Thumbnail",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(76, 76),
		BackgroundColor3 = Theme.Colors.White,
		BorderSizePixel = 0,
		Parent = card,
	})
	Components.Corner(14).Parent = thumb
	Components.Gradient({ accent, accent2:Lerp(Theme.Colors.PanelDark, 0.35) }, 135).Parent = thumb
	Components.Stroke(Theme.Colors.White, 2, 0.45).Parent = thumb
	Components.Label({
		Text = MAP_GLYPHS[definition.Id] or Theme.Icons.Flag,
		TextSize = 38,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		RichText = false,
		Size = UDim2.fromScale(1, 1),
		Parent = thumb,
	})

	Components.Heading({
		Text = definition.Name,
		TextSize = 21,
		TextScaled = true,
		MaxTextSize = 21,
		Outline = 1.5,
		RichText = false,
		Position = UDim2.fromOffset(102, 10),
		Size = UDim2.new(1, -102 - 190 - 200, 0, 28),
		Parent = card,
	})
	-- Chips: Schwierigkeit (+ Empfehlung beim Tutorial)
	local chips = new("Frame", {
		Name = "Chips",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -190, 0, 13),
		Size = UDim2.fromOffset(196, 22),
		Parent = card,
	}, { Components.List(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center) })
	local level = DIFFICULTY[difficulty]
	if isTutorial then
		Components.Pill({ Text = Theme.Icons.Star .. " EMPFOHLEN", Color = Theme.Colors.Accent, Size = UDim2.fromOffset(98, 22), TextSize = 12, LayoutOrder = 1, Parent = chips })
	end
	Components.Pill({
		Text = string.rep("★", difficulty) .. string.rep("☆", 3 - difficulty) .. " " .. level.Text,
		Color = level.Color,
		Size = UDim2.fromOffset(92, 22),
		TextSize = 12,
		LayoutOrder = 2,
		Parent = chips,
	})
	Components.Label({
		Text = definition.Description or "",
		Font = Theme.Fonts.Medium,
		TextSize = Theme.TextSize.Small - 1,
		TextColor3 = Theme.Colors.TextDim,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(102, 44),
		Size = UDim2.new(1, -102 - 190, 0, 40),
		Parent = card,
	})
	local button = Components.Button({
		Text = "STARTEN",
		Icon = Theme.Icons.Play,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(160, 52),
		Color = Theme.Colors.Success,
		Gradient = Theme.Gradients.Play,
		TextColor = Theme.Colors.White,
		TextSize = 20,
		Font = Theme.Fonts.Title,
		CornerRadius = 14,
		OnClick = function()
			Remotes.PracticeRequest:FireServer("Enter", definition.Id)
			self.Modal.Close()
		end,
	})
	button.Parent = card
	if isTutorial then
		Components.Shine(button, { Interval = 4 })
	end
end

function Practice:Start()
	self.UI.Ctx.ClientState:On("OpenScreen", function(payload)
		if payload.Screen == "Practice" then
			self.UI:OpenModal("Practice")
		end
	end)
end

return Practice
