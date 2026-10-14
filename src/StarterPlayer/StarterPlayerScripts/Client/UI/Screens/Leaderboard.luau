--[[
	Leaderboard  (ModuleScript)
	Pfad: StarterPlayer/StarterPlayerScripts/Client/UI/Screens/Leaderboard

	Bestenlisten: Siege (global), Rating der Saison (global) und dieser Server.
	Daten kommen gecacht vom Server (RemoteFunction "GetLeaderboard").

	Darstellung: Zeilen als Glas-Karten; die Plätze 1–3 mit Gold-/Silber-/
	Bronze-Plakette (Krone für Platz 1) und getöntem Hintergrund, jeder
	Spieler mit Initialen-Avatar (Farbe aus dem Namen), der eigene Eintrag
	mit Akzentrand und „DU“-Chip, der Wert groß rechts.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local UI = script.Parent.Parent
local Components = require(UI.Components)
local Theme = require(UI.Theme)

local player = Players.LocalPlayer
local new = Components.new
local rgb = Color3.fromRGB

local Leaderboard = {}
Leaderboard.__index = Leaderboard

-- Plaketten-Verläufe für die Plätze 1–3 (Gold, Silber, Bronze)
local MEDALS = {
	{ rgb(255, 234, 100), rgb(255, 154, 18) },
	{ rgb(242, 246, 255), rgb(146, 158, 186) },
	{ rgb(255, 196, 140), rgb(184, 96, 38) },
}

local AVATAR_COLORS = {
	Theme.Colors.Accent,
	Theme.Colors.Accent2,
	Theme.Colors.Success,
	Theme.Colors.Warning,
	Theme.Colors.Purple,
	Theme.Colors.Orange,
}

-- Stabile Avatar-Farbe aus dem Namen
local function avatarColor(name: string): Color3
	local hash = 0
	for index = 1, #name do
		hash = (hash * 31 + string.byte(name, index)) % 1000003
	end
	return AVATAR_COLORS[hash % #AVATAR_COLORS + 1]
end

local function toHex(color: Color3): string
	return "#" .. color:ToHex()
end

function Leaderboard.new(ui)
	local self = setmetatable({}, Leaderboard)
	self.UI = ui
	self.Tab = "Server"
	self.Data = nil
	local modal = Components.Modal({
		Name = "Leaderboard",
		Title = "BESTENLISTE",
		Icon = Theme.Icons.Leaderboard,
		Accent = Theme.Colors.Orange,
		Size = UDim2.fromOffset(760, 600),
		Parent = ui.Root,
	})
	self.Modal = modal
	ui:RegisterModal("Leaderboard", modal)

	local _, select = Components.Tabs({
		Tabs = {
			{ Name = "Server", Label = Theme.Icons.Players .. " DIESER SERVER", Width = 220 },
			{ Name = "Wins", Label = Theme.Icons.Leaderboard .. " SIEGE (GLOBAL)", Width = 220 },
			{ Name = "Rating", Label = Theme.Icons.Ranked .. " RATING (SAISON)", Width = 220 },
		},
		Parent = modal.Content,
		OnSelect = function(name)
			self.Tab = name
			self:_render()
		end,
	})
	self.Select = select
	self.Status = Components.Label({
		Text = "",
		TextColor3 = Theme.Colors.TextDim,
		Font = Theme.Fonts.Medium,
		TextSize = Theme.TextSize.Small,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(4, 50),
		Size = UDim2.new(1, -8, 0, 22),
		Parent = modal.Content,
	})
	Components.Divider({ Position = UDim2.fromOffset(0, 76), Size = UDim2.new(1, 0, 0, 2), Colors = { Theme.Colors.Orange, Theme.Colors.Accent2 }, Parent = modal.Content })
	self.List = new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 86),
		Size = UDim2.new(1, 0, 1, -86),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Colors.Stroke,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = modal.Content,
	}, { Components.List(Enum.FillDirection.Vertical, 6), Components.Padding(2, 4, 4, 2) })

	modal.OnOpen = function()
		self:_fetch()
		self.Select(self.Tab)
	end
	return self
end

function Leaderboard:Start() end

function Leaderboard:_fetch()
	self.Status.Text = Theme.Icons.Queue .. "  Lädt …"
	task.spawn(function()
		local ok, data = pcall(function()
			return Remotes.GetLeaderboard:InvokeServer()
		end)
		if ok and type(data) == "table" then
			self.Data = data
		end
		if self.Modal.IsOpen() then
			self:_render()
		end
	end)
end

function Leaderboard:_render()
	for _, child in self.List:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local data = self.Data
	if not data then
		self.Status.Text = Theme.Icons.Queue .. "  Bestenliste wird geladen …"
		return
	end
	local entries = data[self.Tab] or {}
	if self.Tab ~= "Server" and not data.Available then
		self.Status.Text = Theme.Icons.Warning .. "  Globale Bestenlisten benötigen DataStore-Zugriff (in Studio: API-Zugriff aktivieren)."
	elseif #entries == 0 then
		self.Status.Text = "Noch keine Einträge."
	else
		self.Status.Text = if self.Tab == "Server" then "Spieler auf diesem Server (nach Siegen)" else "Top " .. #entries
	end
	for index, entry in entries do
		self:_row(index, entry)
	end
end

function Leaderboard:_row(index: number, entry)
	local isMe = entry.UserId == player.UserId
	local rank = entry.Rank or index
	local medal = MEDALS[rank]
	local name = entry.Name or "?"
	local row = Components.Panel({
		Name = "Row",
		Size = UDim2.new(1, -10, 0, 54),
		BackgroundColor3 = if isMe then Theme.Colors.PanelLight else Theme.Colors.PanelDark,
		BackgroundTransparency = 0.06,
		StrokeColor = if isMe then Theme.Colors.Accent elseif medal then medal[2] else Theme.Colors.Stroke,
		StrokeThickness = if isMe or rank == 1 then 2 else 1.5,
		StrokeTransparency = if isMe or medal then 0.05 else 0.5,
		CornerRadius = 12,
		LayoutOrder = index,
		Parent = self.List,
	})
	if medal then
		-- Getönter Schimmer der Medaillenfarbe von links
		local tint = new("Frame", {
			Name = "Tint",
			Size = UDim2.fromScale(0.7, 1),
			BackgroundColor3 = medal[2],
			BackgroundTransparency = 0.6,
			BorderSizePixel = 0,
			Parent = row,
		})
		Components.Corner(12).Parent = tint
		Components.Gradient(Theme.Colors.White, 0, { 0.2, 1 }).Parent = tint
	end

	-- Platz-Plakette
	local badge = new("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(38, 38),
		BackgroundColor3 = Theme.Colors.White,
		BorderSizePixel = 0,
		Parent = row,
	})
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = badge })
	Components.Gradient(medal or Theme.Gradients.Neutral, 90).Parent = badge
	Components.Stroke(if medal then Theme.Colors.White else Theme.Colors.Shadow, 2, if medal then 0.25 else 0.4).Parent = badge
	Components.Label({
		Text = if medal then tostring(rank) else "#" .. tostring(rank),
		Font = Theme.Fonts.Title,
		TextSize = if medal then 20 else 14,
		TextScaled = true,
		MaxTextSize = if medal then 20 else 14,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		RichText = false,
		TextStrokeTransparency = 0.3,
		TextStrokeColor3 = if medal then medal[2]:Lerp(Theme.Colors.Black, 0.6) else Theme.Colors.Shadow,
		Position = UDim2.fromOffset(3, 3),
		Size = UDim2.new(1, -6, 1, -6),
		Parent = badge,
	})
	if rank == 1 then
		Components.Label({
			Text = Theme.Icons.Ranked,
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = false,
			RichText = false,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 0, 7),
			Rotation = -14,
			Size = UDim2.fromOffset(30, 22),
			Parent = badge,
		})
	end

	-- Initialen-Avatar
	local color = avatarColor(name)
	local _, letter = Components.Icon({
		Glyph = string.upper(string.match(name, utf8.charpattern) or "?"),
		Color = color,
		Size = 36,
		TextSize = 18,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 58, 0.5, 0),
		Parent = row,
	})
	letter.RichText = false

	-- Name (+ "DU"-Chip) und bei "Server" eine Unterzeile
	local server = self.Tab == "Server"
	local nameWidth = -104 - 230 - (if isMe then 48 else 0)
	Components.Label({
		Text = name,
		Font = Theme.Fonts.Title,
		TextSize = 18,
		TextColor3 = if isMe then Theme.Colors.Accent:Lerp(Theme.Colors.White, 0.25) else Theme.Colors.Text,
		TextStrokeTransparency = 0.6,
		TextStrokeColor3 = Theme.Colors.Shadow,
		RichText = false,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(104, if server then 6 else 0),
		Size = UDim2.new(1, nameWidth, 0, if server then 24 else 54),
		Parent = row,
	})
	if isMe then
		Components.Pill({
			Text = "DU",
			Color = Theme.Colors.Accent,
			Size = UDim2.fromOffset(40, 20),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -236, 0.5, 0),
			TextSize = 12,
			Parent = row,
		})
	end

	local value, unit
	if server then
		value, unit = Util.FormatNumber(entry.Wins or 0), "Siege"
		Components.Label({
			Text = string.format("Lv. %d  ·  %s RP", entry.Level or 1, Util.FormatNumber(entry.Rating or 0)),
			Font = Theme.Fonts.Medium,
			TextSize = 13,
			TextColor3 = Theme.Colors.TextDim,
			RichText = false,
			TextWrapped = false,
			Position = UDim2.fromOffset(104, 30),
			Size = UDim2.new(1, -104 - 230, 0, 18),
			Parent = row,
		})
	elseif self.Tab == "Wins" then
		value, unit = Util.FormatNumber(entry.Value or 0), "Siege"
	else
		value, unit = Util.FormatNumber(entry.Value or 0), "RP"
	end
	local valueColor = if medal then medal[1] else Theme.Colors.Text
	Components.Label({
		Text = string.format('<font color="%s">%s</font>  <font size="14" color="%s">%s</font>', toHex(valueColor), value, toHex(Theme.Colors.TextDim), unit),
		Font = Theme.Fonts.Title,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
		TextStrokeTransparency = 0.6,
		TextStrokeColor3 = Theme.Colors.Shadow,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 0),
		Size = UDim2.fromOffset(200, 54),
		Parent = row,
	})
end

return Leaderboard
