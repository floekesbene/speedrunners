--[[
	Results  (ModuleScript)
	Pfad: StarterPlayer/StarterPlayerScripts/Client/UI/Screens/Results

	Ergebnisbildschirm nach jedem Rennen:
		- Schlagzeile (SIEG! / PLATZ n / „X GEWINNT“) in Display-Schrift mit
		  Farbverlauf und Info-Chips (Map, Modus, Grund des Rennendes, Dauer)
		- Siegerpodest für die Plätze 1–3 (Gold/Silber/Bronze, Krone für den
		  Sieger; die Blöcke wachsen beim Öffnen nacheinander hoch)
		- Tabelle aller Teilnehmer (Plakette, Name, Status, Zeit/Strecke, Rating)
		- Belohnungskarten: Coins und XP zählen beim Öffnen hoch, Level-Up als
		  goldenes Banner mit Glanz, dazu Rating, Bestzeit, Aufgaben und Erfolge
		- Option "Automatisch erneut anstellen"
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local MapDefinitions = require(Shared.MapDefinitions)

local UI = script.Parent.Parent
local Components = require(UI.Components)
local Theme = require(UI.Theme)

local player = Players.LocalPlayer
local new = Components.new
local rgb = Color3.fromRGB

local Results = {}
Results.__index = Results

local REASONS = {
	Finish = "Ziellinie überquert",
	LastStanding = "Letzter Überlebender",
	Timeout = "Zeit abgelaufen – der Führende gewinnt",
	NoRacers = "Keine Teilnehmer mehr im Rennen",
}

local STATUS = {
	Finished = "Im Ziel",
	Survived = "Überlebt",
	Eliminated = "Ausgeschieden",
	Left = "Verlassen",
	Racing = "Im Rennen",
}

local STATUS_ICONS = {
	Finished = Theme.Icons.Flag,
	Survived = Theme.Icons.Check,
	Eliminated = "💀",
	Left = "🚪",
	Racing = "🏃",
}

-- Plaketten-Verläufe für die Plätze 1–3 (Gold, Silber, Bronze)
local MEDALS = {
	{ rgb(255, 234, 100), rgb(255, 154, 18) },
	{ rgb(242, 246, 255), rgb(146, 158, 186) },
	{ rgb(255, 196, 140), rgb(184, 96, 38) },
}

-- Podest: Platz, horizontale Lage (Anteil), Blockhöhe
local PODIUM = {
	{ Place = 1, X = 0.5, Height = 70 },
	{ Place = 2, X = 0.19, Height = 54 },
	{ Place = 3, X = 0.81, Height = 40 },
}

local LEFT_WIDTH = 540 -- Breite von Podest und Tabelle
local TOP = 92 -- Beginn von Podest/Belohnungen unter der Kopfzeile
local FOOTER = 60

local function initial(name: string): string
	return string.upper(string.match(name, utf8.charpattern) or "?")
end

local function textWidth(text: string, perChar: number): number
	return (utf8.len(text) or #text) * perChar
end

function Results.new(ui)
	local self = setmetatable({}, Results)
	self.UI = ui
	self.Counters = {}
	local modal = Components.Modal({
		Name = "Results",
		Title = "ERGEBNIS",
		Icon = Theme.Icons.Flag,
		Accent = Theme.Colors.Gold,
		Size = UDim2.fromOffset(960, 580),
		Parent = ui.Root,
	})
	self.Modal = modal
	ui:RegisterModal("Results", modal)
	local content = modal.Content

	-- Kopf: Schlagzeile + Info-Chips
	self.Headline = Components.Heading({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 46,
		TextScaled = true,
		MaxTextSize = 46,
		Outline = 3,
		OutlineTransparency = 0,
		RichText = false,
		Size = UDim2.new(1, 0, 0, 50),
		Parent = content,
	})
	self.HeadlineGradient = Components.Gradient(Theme.Gradients.Gold, 90)
	self.HeadlineGradient.Parent = self.Headline
	self.Chips = new("Frame", {
		Name = "Chips",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 56),
		Size = UDim2.new(1, 0, 0, 26),
		Parent = content,
	}, { Components.List(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })

	self:_buildPodium(content)

	-- Tabelle aller Teilnehmer
	local list = new("ScrollingFrame", {
		Name = "Table",
		Position = UDim2.fromOffset(0, TOP + 178),
		Size = UDim2.new(0, LEFT_WIDTH, 1, -(TOP + 178 + FOOTER)),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Colors.Stroke,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = content,
	}, { Components.List(Enum.FillDirection.Vertical, 5), Components.Padding(2, 4, 2, 2) })
	self.List = list

	self:_buildRewards(content)

	-- Fußzeile
	local footer = new("Frame", {
		Name = "Footer",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 52),
		Parent = content,
	})
	local _, setToggle = Components.Toggle({
		Text = "Automatisch erneut anstellen",
		Size = UDim2.new(0.5, 0, 1, 0),
		Parent = footer,
		OnChanged = function(value)
			ui.Ctx.ClientState:SaveSettings({ AutoRequeue = value })
		end,
	})
	self.SetAutoRequeue = setToggle
	local continueButton = Components.Button({
		Text = "WEITER",
		Icon = Theme.Icons.Play,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(210, 52),
		Color = Theme.Colors.Success,
		Gradient = Theme.Gradients.Play,
		TextColor = Theme.Colors.White,
		TextSize = 22,
		Font = Theme.Fonts.Title,
		CornerRadius = 14,
		OnClick = function()
			modal.Close()
		end,
	})
	continueButton.Parent = footer
	Components.Shine(continueButton, { Interval = 4 })

	modal.OnOpen = function()
		self:_playIntro()
	end
	return self
end

-- Siegerpodest (drei feste Plätze, werden pro Rennen befüllt)
function Results:_buildPodium(content: Frame)
	local podium = new("Frame", {
		Name = "Podium",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, TOP),
		Size = UDim2.fromOffset(LEFT_WIDTH, 170),
		Parent = content,
	})
	-- Bodenlinie unter dem Podest
	Components.Divider({
		Name = "Floor",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 3),
		Colors = { Theme.Colors.Gold, Theme.Colors.Accent },
		Parent = podium,
	})
	self.Podium = podium
	self.PodiumSlots = {}
	for _, info in PODIUM do
		local place, height = info.Place, info.Height
		local medal = MEDALS[place]
		local slot = new("Frame", {
			Name = "Place" .. place,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(info.X, 0, 1, -3),
			Size = UDim2.fromOffset(160, 167),
			Parent = podium,
		})
		local block = new("Frame", {
			Name = "Block",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.new(1, -16, 0, height),
			BackgroundColor3 = Theme.Colors.White,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			Parent = slot,
		})
		Components.Corner(12).Parent = block
		Components.Gradient(medal, 90).Parent = block
		Components.Stroke(medal[2]:Lerp(Theme.Colors.Black, 0.45), 2, 0).Parent = block
		Components.Heading({
			Text = tostring(place),
			Font = Theme.Fonts.Display,
			TextSize = 34,
			TextXAlignment = Enum.TextXAlignment.Center,
			Outline = 2.5,
			OutlineColor = medal[2]:Lerp(Theme.Colors.Black, 0.6),
			OutlineTransparency = 0,
			RichText = false,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 3),
			Size = UDim2.new(1, 0, 0, 36),
			Parent = block,
		})
		local detail = Components.Label({
			Name = "Detail",
			Text = "",
			Font = Theme.Fonts.Bold,
			TextSize = 12,
			TextColor3 = Theme.Colors.TextDim,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = false,
			RichText = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -(height + 3)),
			Size = UDim2.new(1, 0, 0, 15),
			Parent = slot,
		})
		local name = Components.Heading({
			Name = "PlayerName",
			Text = "",
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Center,
			Outline = 1.5,
			RichText = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -(height + 18)),
			Size = UDim2.new(1, 0, 0, 20),
			Parent = slot,
		})
		local avatar = new("Frame", {
			Name = "Avatar",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -(height + 40)),
			Size = UDim2.fromOffset(44, 44),
			BackgroundColor3 = Theme.Colors.White,
			BorderSizePixel = 0,
			Parent = slot,
		})
		new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = avatar })
		Components.Gradient(medal, 135).Parent = avatar
		local avatarStroke = Components.Stroke(Theme.Colors.White, 3, 0.15)
		avatarStroke.Parent = avatar
		local letter = Components.Label({
			Text = "",
			Font = Theme.Fonts.Title,
			TextSize = 22,
			TextColor3 = Theme.Colors.White,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = false,
			RichText = false,
			TextStrokeTransparency = 0.3,
			TextStrokeColor3 = medal[2]:Lerp(Theme.Colors.Black, 0.6),
			Size = UDim2.fromScale(1, 1),
			Parent = avatar,
		})
		if place == 1 then
			Components.Label({
				Name = "Crown",
				Text = Theme.Icons.Ranked,
				TextSize = 24,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextWrapped = false,
				RichText = false,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 0, 8),
				Rotation = -12,
				Size = UDim2.fromOffset(40, 28),
				Parent = avatar,
			})
		end
		self.PodiumSlots[place] = {
			Slot = slot,
			Block = block,
			Height = height,
			Name = name,
			Detail = detail,
			Avatar = avatar,
			AvatarStroke = avatarStroke,
			Letter = letter,
		}
	end
end

-- Belohnungs-Karte: Coins/XP-Kacheln, Level-Up-Banner, weitere Zeilen
function Results:_buildRewards(content: Frame)
	local _, panel = Components.Card({
		Name = "Rewards",
		Position = UDim2.fromOffset(LEFT_WIDTH + 16, TOP),
		Size = UDim2.new(1, -(LEFT_WIDTH + 16), 1, -(TOP + FOOTER)),
		BackgroundColor3 = Theme.Colors.PanelDark,
		CornerRadius = 16,
		ShadowOffset = 4,
		ShadowSpread = 5,
		Parent = content,
	})
	local _, gift = Components.Icon({ Glyph = Theme.Icons.Gift, Color = Theme.Colors.Gold, Size = 32, TextSize = 17, Position = UDim2.fromOffset(12, 9), Parent = panel })
	gift.TextStrokeTransparency = 1
	Components.Heading({
		Text = "BELOHNUNGEN",
		TextSize = 19,
		Outline = 1.5,
		RichText = false,
		Position = UDim2.fromOffset(52, 11),
		Size = UDim2.new(1, -64, 0, 28),
		Parent = panel,
	})
	Components.Divider({ Position = UDim2.fromOffset(12, 48), Size = UDim2.new(1, -24, 0, 2), Colors = { Theme.Colors.Gold, Theme.Colors.Accent2 }, Parent = panel })
	local body = new("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 58),
		Size = UDim2.new(1, -24, 1, -66),
		Parent = panel,
	})
	self.RewardsBody = body

	-- Coins- und XP-Kachel
	local function tile(position: UDim2, color: Color3, caption: string)
		local frame = new("Frame", {
			Name = caption,
			Position = position,
			Size = UDim2.new(0.5, -4, 0, 74),
			BackgroundColor3 = Theme.Colors.White,
			BorderSizePixel = 0,
			Parent = body,
		})
		Components.Corner(12).Parent = frame
		Components.Gradient({ color:Lerp(Theme.Colors.Panel, 0.55), color:Lerp(Theme.Colors.PanelDark, 0.82) }, 90).Parent = frame
		Components.Stroke(color, 1.5, 0.3).Parent = frame
		local value = Components.Heading({
			Text = "+0",
			TextSize = 28,
			TextScaled = true,
			MaxTextSize = 28,
			TextColor3 = color:Lerp(Theme.Colors.White, 0.25),
			Outline = 2,
			RichText = false,
			Position = UDim2.fromOffset(52, 8),
			Size = UDim2.new(1, -58, 0, 34),
			Parent = frame,
		})
		Components.Label({
			Text = caption,
			Font = Theme.Fonts.Title,
			TextSize = 13,
			TextColor3 = Theme.Colors.TextDim,
			TextWrapped = false,
			RichText = false,
			Position = UDim2.fromOffset(53, 44),
			Size = UDim2.new(1, -58, 0, 18),
			Parent = frame,
		})
		return frame, value
	end
	local coinTile, coinValue = tile(UDim2.new(), Theme.Colors.Gold, "COINS")
	Components.CoinIcon(34, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Parent = coinTile })
	local xpTile, xpValue = tile(UDim2.new(0.5, 4, 0, 0), Theme.Colors.XP, "XP")
	Components.Icon({ Glyph = "✦", Color = Theme.Colors.XP, Size = 36, TextSize = 20, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 9, 0.5, 0), Parent = xpTile })
	self.CoinTile, self.CoinValue = coinTile, coinValue
	self.XPTile, self.XPValue = xpTile, xpValue

	-- Level-Up-Banner (gold, mit Glanz)
	local banner = new("Frame", {
		Name = "LevelUp",
		Position = UDim2.fromOffset(0, 82),
		Size = UDim2.new(1, 0, 0, 58),
		BackgroundColor3 = Theme.Colors.White,
		BorderSizePixel = 0,
		Visible = false,
		Parent = body,
	})
	Components.Corner(12).Parent = banner
	Components.Gradient(Theme.Gradients.Gold, 90).Parent = banner
	Components.Stroke(rgb(150, 80, 0), 2, 0.1).Parent = banner
	Components.Label({
		Text = "⭐",
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		RichText = false,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0),
		Size = UDim2.fromOffset(40, 40),
		Parent = banner,
	})
	Components.Heading({
		Text = "LEVEL UP!",
		Font = Theme.Fonts.Display,
		TextSize = 26,
		Outline = 2.5,
		OutlineColor = rgb(120, 56, 0),
		OutlineTransparency = 0,
		RichText = false,
		Position = UDim2.fromOffset(54, 4),
		Size = UDim2.new(1, -62, 0, 30),
		Parent = banner,
	})
	self.LevelInfo = Components.Label({
		Text = "",
		Font = Theme.Fonts.Bold,
		TextSize = 14,
		TextScaled = true,
		MaxTextSize = 14,
		TextColor3 = rgb(92, 44, 0),
		TextWrapped = false,
		Position = UDim2.fromOffset(55, 34),
		Size = UDim2.new(1, -64, 0, 18),
		Parent = banner,
	})
	Components.Shine(banner, { Interval = 3 })
	self.LevelBanner = banner

	-- Weitere Zeilen (Rating, Bestzeit, Aufgaben, Erfolge, Hinweise)
	self.Rewards = new("ScrollingFrame", {
		Name = "Lines",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 82),
		Size = UDim2.new(1, 0, 1, -82),
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = Theme.Colors.Stroke,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = body,
	}, { Components.List(Enum.FillDirection.Vertical, 6) })
	self.LineCount = 0
end

function Results:Start()
	local state = self.UI.Ctx.ClientState
	state:On("MatchResults", function(payload)
		self:Show(payload)
	end)
end

--- Zeile im Belohnungsbereich (Symbol + Text, bricht bei Bedarf um).
function Results:_rewardLine(text: string, color: Color3?, icon: string?)
	local tint = color or Theme.Colors.Text
	self.LineCount += 1
	local row = new("Frame", {
		Name = "Line",
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, -6, 0, 0),
		BackgroundColor3 = tint,
		BackgroundTransparency = 0.86,
		BorderSizePixel = 0,
		LayoutOrder = self.LineCount,
		Parent = self.Rewards,
	})
	Components.Corner(8).Parent = row
	Components.Padding(5, 8, 5, 6).Parent = row
	Components.Label({
		Text = icon or Theme.Icons.Star,
		Font = Theme.Fonts.Title,
		TextSize = 15,
		TextColor3 = tint:Lerp(Theme.Colors.White, 0.3),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		RichText = false,
		Size = UDim2.fromOffset(20, 20),
		Parent = row,
	})
	Components.Label({
		Text = text,
		Font = Theme.Fonts.Bold,
		TextSize = 14,
		TextColor3 = tint:Lerp(Theme.Colors.White, 0.3),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.fromOffset(26, 1),
		Size = UDim2.new(1, -26, 0, 18),
		Parent = row,
	})
end

-- Info-Chip in der Kopfzeile (Breite grob aus der Textlänge geschätzt)
function Results:_chip(order: number, text: string, color: Color3)
	Components.Pill({
		Text = text,
		Color = color,
		Size = UDim2.fromOffset(math.min(300, 26 + textWidth(text, 8)), 24),
		TextSize = 13,
		LayoutOrder = order,
		Parent = self.Chips,
	})
end

function Results:Show(payload)
	local participated = false
	local myResult = nil
	for _, entry in payload.Results or {} do
		if entry.UserId == player.UserId then
			participated = true
			myResult = entry
		end
	end

	local definition = MapDefinitions.Get(payload.MapId or "")
	local mapName = if definition then definition.Name else ""
	local winnerName = "—"
	for _, entry in payload.Results or {} do
		if entry.Placement == 1 then
			winnerName = entry.Name
		end
	end

	-- Schlagzeile
	local headlinePair
	if payload.WinnerUserId == player.UserId then
		self.Headline.Text = "SIEG!"
		headlinePair = Theme.Gradients.Gold
	elseif myResult then
		self.Headline.Text = string.format("PLATZ %d", myResult.Placement)
		headlinePair = if myResult.Placement <= 3 then Theme.Gradients.Accent else { Theme.Colors.White, Theme.Colors.TextDim }
	else
		self.Headline.Text = string.upper(winnerName) .. " GEWINNT"
		headlinePair = { Theme.Colors.White, rgb(200, 212, 245) }
	end
	self.HeadlineGradient.Color = ColorSequence.new(headlinePair[1], headlinePair[2])
	local stroke = self.Headline:FindFirstChild("TextStroke")
	if stroke then
		stroke.Color = headlinePair[2]:Lerp(Theme.Colors.Black, 0.7)
	end

	-- Info-Chips
	for _, child in self.Chips:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local ranked = payload.Mode == "Ranked"
	if mapName ~= "" then
		self:_chip(1, string.upper(mapName), Theme.Colors.Accent)
	end
	self:_chip(2, if ranked then Theme.Icons.Ranked .. " RANKED" else Theme.Icons.Quick .. " SCHNELLES SPIEL", if ranked then Theme.Colors.Gold else Theme.Colors.Accent2)
	if REASONS[payload.Reason] then
		self:_chip(3, REASONS[payload.Reason], Theme.Colors.PanelLight:Lerp(Theme.Colors.White, 0.3))
	end
	self:_chip(4, "⏱ " .. Util.FormatTime(payload.Duration or 0), Theme.Colors.Success)

	-- Podest
	local byPlace = {}
	for _, entry in payload.Results or {} do
		if entry.Placement and entry.Placement <= 3 and not byPlace[entry.Placement] then
			byPlace[entry.Placement] = entry
		end
	end
	for place, slot in self.PodiumSlots do
		local entry = byPlace[place]
		slot.Slot.Visible = entry ~= nil
		if entry then
			local isMe = entry.UserId == player.UserId
			slot.Name.Text = entry.Name or "?"
			slot.Name.TextColor3 = if isMe then Theme.Colors.Accent:Lerp(Theme.Colors.White, 0.3) else Theme.Colors.White
			slot.Letter.Text = initial(entry.Name or "?")
			slot.AvatarStroke.Color = if isMe then Theme.Colors.Accent else Theme.Colors.White
			slot.AvatarStroke.Thickness = if isMe then 4 else 3
			if entry.Time then
				slot.Detail.Text = Util.FormatTime(entry.Time)
			elseif entry.Progress then
				slot.Detail.Text = string.format("%d m", math.max(0, entry.Progress))
			else
				slot.Detail.Text = STATUS[entry.Status] or ""
			end
		end
	end

	-- Tabelle
	for _, child in self.List:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for index, entry in payload.Results or {} do
		self:_tableRow(index, entry)
	end

	-- Belohnungen
	for _, child in self.Rewards:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	self.LineCount = 0
	self.Counters = {}
	local rewards = payload.Rewards
	local leveled = rewards ~= nil and (rewards.LevelsGained or 0) > 0
	self.CoinTile.Visible = rewards ~= nil
	self.XPTile.Visible = rewards ~= nil
	self.LevelBanner.Visible = leveled
	local linesTop = if leveled then 148 elseif rewards then 82 else 0
	self.Rewards.Position = UDim2.fromOffset(0, linesTop)
	self.Rewards.Size = UDim2.new(1, 0, 1, -linesTop)
	if rewards then
		self.CoinValue.Text = "+" .. Util.FormatNumber(rewards.Coins or 0)
		self.XPValue.Text = "+" .. Util.FormatNumber(rewards.XP or 0)
		self.Counters = {
			{ Label = self.CoinValue, Target = rewards.Coins or 0, Tile = self.CoinTile },
			{ Label = self.XPValue, Target = rewards.XP or 0, Tile = self.XPTile },
		}
		if leveled then
			self.LevelInfo.Text = string.format("Level %d erreicht · +%s Coins Bonus", rewards.NewLevel or 0, Util.FormatNumber(rewards.LevelBonusCoins or 0))
		end
		if rewards.RatingChange then
			self:_rewardLine(
				string.format("Rating %+d → %d (%s)", rewards.RatingChange, rewards.NewRating or 0, rewards.Tier or ""),
				if rewards.RatingChange >= 0 then Theme.Colors.Success else Theme.Colors.Danger,
				if rewards.RatingChange >= 0 then Theme.Icons.Up else Theme.Icons.Down
			)
		end
		if rewards.NewBestTime then
			self:_rewardLine("Neue Bestzeit: " .. Util.FormatTime(rewards.NewBestTime), Theme.Colors.Accent, "⏱")
		end
		for _, quest in rewards.Quests or {} do
			self:_rewardLine("Aufgabe erledigt: " .. quest, Theme.Colors.Success, Theme.Icons.Check)
		end
		for _, achievement in rewards.Achievements or {} do
			self:_rewardLine("Erfolg: " .. achievement, Theme.Colors.Gold, Theme.Icons.Leaderboard)
		end
	elseif participated then
		self:_rewardLine("Keine Belohnung (Rennen verlassen).", Theme.Colors.TextDim, Theme.Icons.Info)
	else
		self:_rewardLine("Du hast zugeschaut.", Theme.Colors.TextDim, Theme.Icons.Spectate)
		self:_rewardLine("Tritt der Warteschlange bei, um in der nächsten Runde mitzufahren!", Theme.Colors.Accent, Theme.Icons.Queue)
	end

	self.SetAutoRequeue(self.UI.Ctx.ClientState:GetSetting("AutoRequeue") ~= false)

	-- Nur Teilnehmer und Zuschauer bekommen das Fenster automatisch
	local spectating = self.UI.Ctx.CameraController:GetSpectate() ~= nil
	if participated or spectating then
		task.delay(Config.Round.ReturnToLobbyDelay * 0.6, function()
			self.UI:OpenModal("Results")
		end)
		local token = {}
		self.Token = token
		task.delay(Config.Round.ResultsDuration + 4, function()
			if self.Token == token then
				self.Modal.Close()
			end
		end)
	end
end

-- Eine Tabellenzeile: Plakette, Name, Status/Zeit, Rating-Änderung
function Results:_tableRow(index: number, entry)
	local isMe = entry.UserId == player.UserId
	local place = entry.Placement or index
	local medal = MEDALS[place]
	local row = Components.Panel({
		Name = "Row",
		Size = UDim2.new(1, -8, 0, 38),
		BackgroundColor3 = if isMe then Theme.Colors.PanelLight else Theme.Colors.PanelDark,
		BackgroundTransparency = 0.08,
		StrokeColor = if isMe then Theme.Colors.Accent elseif medal then medal[2] else Theme.Colors.Stroke,
		StrokeTransparency = if isMe or medal then 0.1 else 0.5,
		CornerRadius = 10,
		LayoutOrder = index,
		Parent = self.List,
	})
	local badge = new("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0),
		Size = UDim2.fromOffset(28, 28),
		BackgroundColor3 = Theme.Colors.White,
		BorderSizePixel = 0,
		Parent = row,
	})
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = badge })
	Components.Gradient(medal or Theme.Gradients.Neutral, 90).Parent = badge
	Components.Stroke(Theme.Colors.Shadow, 1.5, 0.3).Parent = badge
	Components.Label({
		Text = tostring(place),
		Font = Theme.Fonts.Title,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		RichText = false,
		TextStrokeTransparency = 0.35,
		TextStrokeColor3 = Theme.Colors.Shadow,
		Size = UDim2.fromScale(1, 1),
		Parent = badge,
	})
	Components.Label({
		Text = entry.Name or "?",
		Font = Theme.Fonts.Title,
		TextSize = 16,
		TextColor3 = if isMe then Theme.Colors.Accent:Lerp(Theme.Colors.White, 0.25) else Theme.Colors.Text,
		RichText = false,
		Position = UDim2.fromOffset(46, 0),
		Size = UDim2.new(0.42, -46, 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
		Parent = row,
	})
	local detail = STATUS[entry.Status] or entry.Status or ""
	if entry.Time then
		detail = "Ziel " .. Util.FormatTime(entry.Time)
	elseif entry.Progress then
		detail = string.format("%s · %d m", detail, math.max(0, entry.Progress))
	end
	Components.Label({
		Text = (STATUS_ICONS[entry.Status] or "") .. "  " .. detail,
		Font = Theme.Fonts.Medium,
		TextSize = Theme.TextSize.Small - 1,
		TextColor3 = if entry.Status == "Finished" then Theme.Colors.Gold:Lerp(Theme.Colors.White, 0.4) else Theme.Colors.TextDim,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		RichText = false,
		Position = UDim2.new(0.42, 0, 0, 0),
		Size = UDim2.new(0.4, 0, 1, 0),
		Parent = row,
	})
	if entry.RatingChange then
		local positive = entry.RatingChange >= 0
		Components.Pill({
			Text = string.format("%+d", entry.RatingChange),
			Color = if positive then Theme.Colors.Success else Theme.Colors.Danger,
			Size = UDim2.fromOffset(58, 24),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			TextSize = 14,
			Parent = row,
		})
	end
end

-- Auftritt beim Öffnen: Schlagzeile hüpft, Podest wächst, Belohnungen zählen hoch
function Results:_playIntro()
	Components.Pop(self.Headline, 1.35, 0.5)
	local order = { 3, 2, 1 }
	for step, place in order do
		local slot = self.PodiumSlots[place]
		if slot and slot.Slot.Visible then
			slot.Block.Size = UDim2.new(1, -16, 0, 0)
			slot.Avatar.Visible = false
			task.delay(0.12 + step * 0.16, function()
				Components.Tween(slot.Block, 0.45, { Size = UDim2.new(1, -16, 0, slot.Height) }, Enum.EasingStyle.Back)
				slot.Avatar.Visible = true
				Components.Pop(slot.Avatar, 0.3, 0.5)
			end)
		end
	end
	for index, counter in self.Counters do
		local label = counter.Label
		local target = counter.Target
		label.Text = "+0"
		local value = new("NumberValue", { Value = 0 })
		value:GetPropertyChangedSignal("Value"):Connect(function()
			label.Text = "+" .. Util.FormatNumber(math.floor(value.Value + 0.5))
		end)
		task.delay(0.35 + index * 0.15, function()
			local tween = Components.Tween(value, 1.2, { Value = target }, Enum.EasingStyle.Quart)
			tween.Completed:Connect(function()
				label.Text = "+" .. Util.FormatNumber(target)
				value:Destroy()
				Components.Pop(counter.Tile, 1.08, 0.3)
			end)
		end)
	end
	if self.LevelBanner.Visible then
		task.delay(1.7, function()
			Components.Pop(self.LevelBanner, 1.15, 0.45)
		end)
	end
end

return Results
