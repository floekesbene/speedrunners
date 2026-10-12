--[[
	Leaderboard  (ModuleScript)
	Pfad: StarterPlayer/StarterPlayerScripts/Client/UI/Screens/Leaderboard

	Bestenlisten: Siege (global), Rating der Saison (global) und dieser Server.
	Daten kommen gecacht vom Server (RemoteFunction "GetLeaderboard").
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

local Leaderboard = {}
Leaderboard.__index = Leaderboard

function Leaderboard.new(ui)
	local self = setmetatable({}, Leaderboard)
	self.UI = ui
	self.Tab = "Server"
	self.Data = nil
	local modal = Components.Modal({ Name = "Leaderboard", Title = "BESTENLISTE", Size = UDim2.fromOffset(760, 600), Parent = ui.Root })
	self.Modal = modal
	ui:RegisterModal("Leaderboard", modal)

	local _, select = Components.Tabs({
		Tabs = {
			{ Name = "Server", Label = "DIESER SERVER", Width = 200 },
			{ Name = "Wins", Label = "SIEGE (GLOBAL)", Width = 200 },
			{ Name = "Rating", Label = "RATING (SAISON)", Width = 200 },
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
		Position = UDim2.fromOffset(0, 48),
		Size = UDim2.new(1, 0, 0, 22),
		Parent = modal.Content,
	})
	self.List = new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 76),
		Size = UDim2.new(1, 0, 1, -76),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = modal.Content,
	}, { Components.List(Enum.FillDirection.Vertical, 6) })

	modal.OnOpen = function()
		self:_fetch()
		self.Select(self.Tab)
	end
	return self
end

function Leaderboard:Start() end

function Leaderboard:_fetch()
	self.Status.Text = "Lädt …"
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
		self.Status.Text = "Bestenliste wird geladen …"
		return
	end
	local entries = data[self.Tab] or {}
	if self.Tab ~= "Server" and not data.Available then
		self.Status.Text = "Globale Bestenlisten benötigen DataStore-Zugriff (in Studio: API-Zugriff aktivieren)."
	elseif #entries == 0 then
		self.Status.Text = "Noch keine Einträge."
	else
		self.Status.Text = if self.Tab == "Server" then "Spieler auf diesem Server (nach Siegen)" else "Top " .. #entries
	end
	for index, entry in entries do
		local isMe = entry.UserId == player.UserId
		local row = Components.Panel({
			Size = UDim2.new(1, -10, 0, 44),
			BackgroundColor3 = if isMe then Theme.Colors.PanelLight else Theme.Colors.PanelDark,
			StrokeColor = if entry.Rank == 1 then Theme.Colors.Gold elseif entry.Rank <= 3 then Theme.Colors.Accent else Theme.Colors.Stroke,
			LayoutOrder = index,
			Parent = self.List,
		})
		Components.Label({
			Text = "#" .. tostring(entry.Rank),
			Font = Theme.Fonts.Title,
			TextColor3 = if entry.Rank == 1 then Theme.Colors.Gold else Theme.Colors.Text,
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.new(0, 70, 1, 0),
			Parent = row,
		})
		Components.Label({
			Text = entry.Name or "?",
			Font = Theme.Fonts.Bold,
			TextColor3 = if isMe then Theme.Colors.Accent else Theme.Colors.Text,
			Position = UDim2.fromOffset(84, 0),
			Size = UDim2.new(1, -300, 1, 0),
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextWrapped = false,
			Parent = row,
		})
		local valueText
		if self.Tab == "Server" then
			valueText = string.format("%d Siege · Lv. %d · %d RP", entry.Wins or 0, entry.Level or 1, entry.Rating or 0)
		elseif self.Tab == "Wins" then
			valueText = Util.FormatNumber(entry.Value or 0) .. " Siege"
		else
			valueText = Util.FormatNumber(entry.Value or 0) .. " RP"
		end
		Components.Label({
			Text = valueText,
			Font = Theme.Fonts.Bold,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 0),
			Size = UDim2.fromOffset(240, 44),
			Parent = row,
		})
	end
end

return Leaderboard
