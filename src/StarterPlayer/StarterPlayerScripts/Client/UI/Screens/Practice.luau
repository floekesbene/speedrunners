--[[
	Practice  (ModuleScript)
	Pfad: StarterPlayer/StarterPlayerScripts/Client/UI/Screens/Practice

	Auswahl des Trainingsmodus: Bewegungs-Tutorial oder freies Training auf
	einer der Rennstrecken (ohne Gefahrenzone, ohne Belohnungen).
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

function Practice.new(ui)
	local self = setmetatable({}, Practice)
	self.UI = ui
	local modal = Components.Modal({ Name = "Practice", Title = "TRAINING", Size = UDim2.fromOffset(900, 580), Parent = ui.Root })
	self.Modal = modal
	ui:RegisterModal("Practice", modal)

	Components.Label({
		Text = "Übe Bewegung, Greifhaken und Abkürzungen ohne Druck. Im Training gibt es keine Gefahrenzone, keine Coins, keine XP und keine Statistiken. Startet ein Rennen, wirst du automatisch abgeholt.",
		Font = Theme.Fonts.Medium,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, 0, 0, 40),
		Parent = modal.Content,
	})
	local list = new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.new(1, 0, 1, -50),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = modal.Content,
	}, { Components.List(Enum.FillDirection.Vertical, 8) })

	local courses = { MapDefinitions.Tutorial }
	for _, id in MapDefinitions.Order do
		table.insert(courses, MapDefinitions.Maps[id])
	end
	for index, definition in courses do
		local row = Components.Panel({
			Size = UDim2.new(1, -10, 0, 74),
			BackgroundColor3 = Theme.Colors.PanelDark,
			StrokeColor = definition.Theme.Accent,
			LayoutOrder = index,
			Parent = list,
		})
		local swatch = new("Frame", { Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(50, 50), BackgroundColor3 = definition.Theme.Accent, BorderSizePixel = 0, Parent = row })
		Components.Corner(10).Parent = swatch
		Components.Label({
			Text = definition.Name .. "  " .. string.rep("★", definition.Difficulty or 1) .. string.rep("☆", 3 - (definition.Difficulty or 1)),
			Font = Theme.Fonts.Title,
			Position = UDim2.fromOffset(76, 10),
			Size = UDim2.new(1, -260, 0, 26),
			Parent = row,
		})
		Components.Label({
			Text = definition.Description or "",
			Font = Theme.Fonts.Medium,
			TextSize = Theme.TextSize.Small,
			TextColor3 = Theme.Colors.TextDim,
			Position = UDim2.fromOffset(76, 38),
			Size = UDim2.new(1, -260, 0, 30),
			Parent = row,
		})
		local button = Components.Button({
			Text = "STARTEN",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(160, 46),
			Color = Theme.Colors.Success,
			TextColor = Theme.Colors.Background,
			Font = Theme.Fonts.Title,
			OnClick = function()
				Remotes.PracticeRequest:FireServer("Enter", definition.Id)
				modal.Close()
			end,
		})
		button.Parent = row
	end
	return self
end

function Practice:Start()
	self.UI.Ctx.ClientState:On("OpenScreen", function(payload)
		if payload.Screen == "Practice" then
			self.UI:OpenModal("Practice")
		end
	end)
end

return Practice
