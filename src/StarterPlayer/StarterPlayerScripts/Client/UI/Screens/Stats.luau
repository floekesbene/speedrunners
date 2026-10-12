--[[
	Stats  (ModuleScript)
	Pfad: StarterPlayer/StarterPlayerScripts/Client/UI/Screens/Stats

	Spielerstatistiken, Ranked-Saison, tägliche Aufgaben und Erfolge.
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
	local modal = Components.Modal({ Name = "Stats", Title = "STATISTIK & AUFGABEN", Size = UDim2.fromOffset(1000, 600), Parent = ui.Root })
	self.Modal = modal
	ui:RegisterModal("Stats", modal)

	local function column(x: number, width: number, title: string)
		local panel = Components.Panel({
			Position = UDim2.new(x, if x > 0 then 8 else 0, 0, 0),
			Size = UDim2.new(width, -8, 1, 0),
			BackgroundColor3 = Theme.Colors.PanelDark,
			Parent = modal.Content,
		})
		Components.Label({ Text = title, Font = Theme.Fonts.Title, TextColor3 = Theme.Colors.Accent, Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 24), Parent = panel })
		local scroll = new("ScrollingFrame", {
			Position = UDim2.fromOffset(10, 42),
			Size = UDim2.new(1, -20, 1, -52),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 5,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			Parent = panel,
		}, { Components.List(Enum.FillDirection.Vertical, 6) })
		return scroll
	end
	self.StatsList = column(0, 0.33, "STATISTIK")
	self.QuestList = column(0.33, 0.34, "TÄGLICHE AUFGABEN")
	self.AchievementList = column(0.67, 0.33, "ERFOLGE")

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

function Stats:_statRow(order: number, label: string, value: string, color: Color3?)
	local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = order, Parent = self.StatsList })
	Components.Label({ Text = label, Font = Theme.Fonts.Medium, TextColor3 = Theme.Colors.TextDim, TextSize = Theme.TextSize.Small, Size = UDim2.new(0.62, 0, 1, 0), Parent = row })
	Components.Label({
		Text = value,
		Font = Theme.Fonts.Bold,
		TextSize = Theme.TextSize.Small,
		TextColor3 = color or Theme.Colors.Text,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.fromScale(0.62, 0),
		Size = UDim2.new(0.38, 0, 1, 0),
		Parent = row,
	})
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
	local order = 0
	local function add(label, value, color)
		order += 1
		self:_statRow(order, label, value, color)
	end
	add("Level", tostring(profile.Level), Theme.Colors.Accent)
	add("Gesamt-XP", Util.FormatNumber(profile.TotalXP))
	add("Coins", Util.FormatNumber(profile.Coins), Theme.Colors.Gold)
	add("Rennen", Util.FormatNumber(s.Races))
	add("Siege", Util.FormatNumber(s.Wins), Theme.Colors.Gold)
	add("Siegquote", if s.Races > 0 then string.format("%d%%", math.floor(s.Wins / s.Races * 100 + 0.5)) else "–")
	add("Top 3", Util.FormatNumber(s.Top3))
	add("Ziel erreicht", Util.FormatNumber(s.Finishes))
	add("Ausgeschieden", Util.FormatNumber(s.Eliminated))
	add("Greifhaken (Rennen)", Util.FormatNumber(s.Grapples))
	add("Power-ups (Rennen)", Util.FormatNumber(s.PowerUps))
	add("Strecke gesamt", Util.FormatNumber(s.Distance) .. " m")
	local ranked = profile.Ranked
	local tier = Progression.GetTier(ranked.Rating)
	add("—— RANKED SAISON " .. tostring(ranked.Season or Config.Ranked.Season), "", Theme.Colors.TextDim)
	add("Rang", tier.Name, tier.Color)
	add("Rating", tostring(ranked.Rating), tier.Color)
	add("Höchstwert", tostring(ranked.Peak))
	add("Ranked-Spiele / Siege", string.format("%d / %d", ranked.Games, ranked.Wins))
	add("—— BESTZEITEN", "", Theme.Colors.TextDim)
	for _, mapId in MapDefinitions.Order do
		local best = s.BestTimes and s.BestTimes[mapId]
		add(MapDefinitions.Maps[mapId].Name, if best then Util.FormatTime(best) else "–")
	end
	if profile.Persistent == false then
		add("Speichern", "Studio: aus", Theme.Colors.Warning)
	end

	-- Aufgaben
	for index, entry in profile.Quests and profile.Quests.List or {} do
		local quest = QuestDefinitions.DailyLookup[entry.Id]
		if quest then
			local card = Components.Panel({
				Size = UDim2.new(1, -6, 0, 86),
				BackgroundColor3 = Theme.Colors.Panel,
				StrokeColor = if entry.Done then Theme.Colors.Success else Theme.Colors.Stroke,
				LayoutOrder = index,
				Parent = self.QuestList,
			})
			Components.Label({ Text = quest.Name, Font = Theme.Fonts.Bold, TextSize = Theme.TextSize.Small, Position = UDim2.fromOffset(10, 8), Size = UDim2.new(1, -20, 0, 20), Parent = card })
			Components.Label({
				Text = string.format("Belohnung: %d Coins · %d XP", quest.Coins, quest.XP),
				Font = Theme.Fonts.Medium,
				TextSize = Theme.TextSize.Tiny,
				TextColor3 = Theme.Colors.Gold,
				Position = UDim2.fromOffset(10, 30),
				Size = UDim2.new(1, -20, 0, 16),
				Parent = card,
			})
			local _, set = Components.ProgressBar({
				Position = UDim2.fromOffset(10, 56),
				Size = UDim2.new(1, -110, 0, 12),
				Color = if entry.Done then Theme.Colors.Success else Theme.Colors.Accent,
				Parent = card,
			})
			set(entry.Progress / quest.Goal)
			Components.Label({
				Text = if entry.Done then "ERLEDIGT" else string.format("%s / %s", Util.FormatNumber(entry.Progress), Util.FormatNumber(quest.Goal)),
				Font = Theme.Fonts.Bold,
				TextSize = Theme.TextSize.Tiny,
				TextXAlignment = Enum.TextXAlignment.Right,
				TextColor3 = if entry.Done then Theme.Colors.Success else Theme.Colors.Text,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -10, 0, 52),
				Size = UDim2.fromOffset(90, 20),
				Parent = card,
			})
		end
	end
	Components.Label({
		Text = "Neue Aufgaben gibt es jeden Tag (UTC). Belohnungen werden automatisch gutgeschrieben.",
		Font = Theme.Fonts.Medium,
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, -6, 0, 34),
		LayoutOrder = 99,
		Parent = self.QuestList,
	})

	-- Erfolge
	for index, achievement in QuestDefinitions.Achievements do
		local unlocked = profile.Achievements and profile.Achievements[achievement.Id] == true
		local card = Components.Panel({
			Size = UDim2.new(1, -6, 0, 58),
			BackgroundColor3 = if unlocked then Theme.Colors.PanelLight else Theme.Colors.Panel,
			StrokeColor = if unlocked then Theme.Colors.Gold else Theme.Colors.Stroke,
			LayoutOrder = index,
			Parent = self.AchievementList,
		})
		Components.Label({
			Text = (if unlocked then "★ " else "☆ ") .. achievement.Name,
			Font = Theme.Fonts.Bold,
			TextSize = Theme.TextSize.Small,
			TextColor3 = if unlocked then Theme.Colors.Gold else Theme.Colors.Text,
			Position = UDim2.fromOffset(10, 6),
			Size = UDim2.new(1, -20, 0, 20),
			Parent = card,
		})
		Components.Label({
			Text = string.format("%s (+%d Coins)", achievement.Description, achievement.Coins),
			Font = Theme.Fonts.Medium,
			TextSize = Theme.TextSize.Tiny,
			TextColor3 = Theme.Colors.TextDim,
			Position = UDim2.fromOffset(10, 28),
			Size = UDim2.new(1, -20, 0, 24),
			Parent = card,
		})
	end
end

return Stats
