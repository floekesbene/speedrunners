--[[
	Results  (ModuleScript)
	Pfad: StarterPlayer/StarterPlayerScripts/Client/UI/Screens/Results

	Ergebnisbildschirm nach jedem Rennen:
		- Sieger / eigene Platzierung, Grund des Rennendes
		- Tabelle aller Teilnehmer (Platz, Name, Status, Zeit/Strecke, Rating)
		- eigene Belohnungen: Coins, XP, Level-Up, Rating, Aufgaben, Erfolge, Bestzeit
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

function Results.new(ui)
	local self = setmetatable({}, Results)
	self.UI = ui
	local modal = Components.Modal({ Name = "Results", Title = "ERGEBNIS", Size = UDim2.fromOffset(960, 580), Parent = ui.Root })
	self.Modal = modal
	ui:RegisterModal("Results", modal)
	local content = modal.Content

	self.Headline = Components.Label({
		Text = "",
		Font = Theme.Fonts.Title,
		TextSize = 44,
		Size = UDim2.new(1, 0, 0, 50),
		Parent = content,
	})
	self.Subline = Components.Label({
		Text = "",
		Font = Theme.Fonts.Medium,
		TextColor3 = Theme.Colors.TextDim,
		Position = UDim2.fromOffset(0, 52),
		Size = UDim2.new(1, 0, 0, 22),
		Parent = content,
	})

	local list = new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 86),
		Size = UDim2.new(0.6, -10, 1, -150),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = content,
	}, { Components.List(Enum.FillDirection.Vertical, 6) })
	self.List = list

	local rewards = Components.Panel({
		Position = UDim2.new(0.6, 10, 0, 86),
		Size = UDim2.new(0.4, -10, 1, -150),
		BackgroundColor3 = Theme.Colors.PanelDark,
		Parent = content,
	})
	Components.Padding(14).Parent = rewards
	Components.List(Enum.FillDirection.Vertical, 6).Parent = rewards
	self.Rewards = rewards

	local footer = new("Frame", {
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
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(200, 50),
		Color = Theme.Colors.Accent,
		TextColor = Theme.Colors.Background,
		Font = Theme.Fonts.Title,
		OnClick = function()
			modal.Close()
		end,
	})
	continueButton.Parent = footer
	return self
end

function Results:Start()
	local state = self.UI.Ctx.ClientState
	state:On("MatchResults", function(payload)
		self:Show(payload)
	end)
end

function Results:_rewardLine(text: string, color: Color3?)
	Components.Label({
		Text = text,
		Font = Theme.Fonts.Bold,
		TextSize = Theme.TextSize.Body,
		TextColor3 = color or Theme.Colors.Text,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = self.Rewards,
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

	if payload.WinnerUserId == player.UserId then
		self.Headline.Text = "SIEG!"
		self.Headline.TextColor3 = Theme.Colors.Gold
	elseif myResult then
		self.Headline.Text = string.format("PLATZ %d", myResult.Placement)
		self.Headline.TextColor3 = if myResult.Placement <= 3 then Theme.Colors.Accent else Theme.Colors.Text
	else
		self.Headline.Text = winnerName .. " GEWINNT"
		self.Headline.TextColor3 = Theme.Colors.Text
	end
	self.Subline.Text = string.format("%s · %s · %s · Dauer %s", mapName, if payload.Mode == "Ranked" then "Ranked" else "Schnelles Spiel", REASONS[payload.Reason] or "", Util.FormatTime(payload.Duration or 0))

	for _, child in self.List:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for index, entry in payload.Results or {} do
		local isMe = entry.UserId == player.UserId
		local row = Components.Panel({
			Size = UDim2.new(1, -10, 0, 42),
			BackgroundColor3 = if isMe then Theme.Colors.PanelLight else Theme.Colors.PanelDark,
			StrokeColor = if entry.Placement == 1 then Theme.Colors.Gold else Theme.Colors.Stroke,
			LayoutOrder = index,
			Parent = self.List,
		})
		Components.Label({
			Text = tostring(entry.Placement),
			Font = Theme.Fonts.Title,
			TextSize = 22,
			TextColor3 = if entry.Placement == 1 then Theme.Colors.Gold else Theme.Colors.Text,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(0, 44, 1, 0),
			Parent = row,
		})
		Components.Label({
			Text = entry.Name,
			Font = Theme.Fonts.Bold,
			TextColor3 = if isMe then Theme.Colors.Accent else Theme.Colors.Text,
			Position = UDim2.fromOffset(48, 0),
			Size = UDim2.new(0.42, -48, 1, 0),
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextWrapped = false,
			Parent = row,
		})
		local detail = STATUS[entry.Status] or entry.Status
		if entry.Time then
			detail = "Ziel " .. Util.FormatTime(entry.Time)
		elseif entry.Progress then
			detail = string.format("%s · %d m", detail, math.max(0, entry.Progress))
		end
		Components.Label({
			Text = detail,
			Font = Theme.Fonts.Medium,
			TextSize = Theme.TextSize.Small,
			TextColor3 = Theme.Colors.TextDim,
			Position = UDim2.new(0.42, 0, 0, 0),
			Size = UDim2.new(0.4, 0, 1, 0),
			Parent = row,
		})
		if entry.RatingChange then
			Components.Label({
				Text = string.format("%+d", entry.RatingChange),
				Font = Theme.Fonts.Title,
				TextSize = Theme.TextSize.Body,
				TextColor3 = if entry.RatingChange >= 0 then Theme.Colors.Success else Theme.Colors.Danger,
				TextXAlignment = Enum.TextXAlignment.Right,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -12, 0, 0),
				Size = UDim2.new(0.16, 0, 1, 0),
				Parent = row,
			})
		end
	end

	for _, child in self.Rewards:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local rewards = payload.Rewards
	if rewards then
		self:_rewardLine("BELOHNUNGEN", Theme.Colors.TextDim)
		self:_rewardLine(string.format("+%s Coins", Util.FormatNumber(rewards.Coins or 0)), Theme.Colors.Gold)
		self:_rewardLine(string.format("+%s XP", Util.FormatNumber(rewards.XP or 0)), Theme.Colors.XP)
		if (rewards.LevelsGained or 0) > 0 then
			self:_rewardLine(string.format("LEVEL UP! Level %d (+%s Coins)", rewards.NewLevel, Util.FormatNumber(rewards.LevelBonusCoins or 0)), Theme.Colors.Success)
		end
		if rewards.RatingChange then
			self:_rewardLine(string.format("Rating %+d → %d (%s)", rewards.RatingChange, rewards.NewRating or 0, rewards.Tier or ""), if rewards.RatingChange >= 0 then Theme.Colors.Success else Theme.Colors.Danger)
		end
		if rewards.NewBestTime then
			self:_rewardLine("Neue Bestzeit: " .. Util.FormatTime(rewards.NewBestTime), Theme.Colors.Accent)
		end
		for _, quest in rewards.Quests or {} do
			self:_rewardLine("Aufgabe erledigt: " .. quest, Theme.Colors.Success)
		end
		for _, achievement in rewards.Achievements or {} do
			self:_rewardLine("Erfolg: " .. achievement, Theme.Colors.Gold)
		end
	elseif participated then
		self:_rewardLine("Keine Belohnung (Rennen verlassen).", Theme.Colors.TextDim)
	else
		self:_rewardLine("Du hast zugeschaut.", Theme.Colors.TextDim)
		self:_rewardLine("Tritt der Warteschlange bei, um in der nächsten Runde mitzufahren!", Theme.Colors.TextDim)
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

return Results
