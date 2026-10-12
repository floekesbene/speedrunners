--[[
	Notifications  (ModuleScript)
	Pfad: StarterPlayer/StarterPlayerScripts/Client/UI/Screens/Notifications

	Kurze Hinweise oben in der Bildschirmmitte (Info, Erfolg, Warnung, Fehler)
	sowie Meldungen zu Aufgaben, Erfolgen und Level-Ups.
]]

local UI = script.Parent.Parent
local Components = require(UI.Components)
local Theme = require(UI.Theme)

local Notifications = {}
Notifications.__index = Notifications

local KIND_COLORS = {
	Info = Theme.Colors.Accent,
	Success = Theme.Colors.Success,
	Warning = Theme.Colors.Warning,
	Error = Theme.Colors.Danger,
	Reward = Theme.Colors.Gold,
}

function Notifications.new(ui)
	local self = setmetatable({}, Notifications)
	self.UI = ui
	self.Container = Components.new("Frame", {
		Name = "Notifications",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 176),
		Size = UDim2.fromOffset(560, 300),
		ZIndex = 50,
		Parent = ui.Root,
	}, { Components.List(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center) })
	self.Count = 0
	return self
end

function Notifications:Start()
	local state = self.UI.Ctx.ClientState
	state:On("Notify", function(payload)
		self:Push(payload.Text or "", payload.Kind)
	end)
	state:On("QuestCompleted", function(payload)
		self:Push(string.format("Aufgabe erledigt: %s  (+%d Coins, +%d XP)", payload.Name, payload.Coins, payload.XP), "Reward")
	end)
	state:On("AchievementUnlocked", function(payload)
		self:Push(string.format("Erfolg freigeschaltet: %s  (+%d Coins)", payload.Name, payload.Coins), "Reward")
	end)
	state:On("LevelUp", function(payload)
		self:Push(string.format("LEVEL UP! Du bist jetzt Level %d  (+%d Coins)", payload.Level, payload.Coins), "Reward")
	end)
end

function Notifications:Push(text: string, kind: string?)
	if text == "" then
		return
	end
	local color = KIND_COLORS[kind or "Info"] or Theme.Colors.Accent
	self.Count += 1
	local toast = Components.Panel({
		Name = "Toast",
		Size = UDim2.fromOffset(540, 46),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 1,
		StrokeColor = color,
		LayoutOrder = self.Count,
		ZIndex = 50,
		Parent = self.Container,
	})
	local bar = Components.new("Frame", {
		Size = UDim2.new(0, 6, 1, -12),
		Position = UDim2.fromOffset(8, 6),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = 51,
		Parent = toast,
	})
	Components.Corner(3).Parent = bar
	local label = Components.Label({
		Text = text,
		Position = UDim2.fromOffset(24, 0),
		Size = UDim2.new(1, -36, 1, 0),
		TextScaled = true,
		MaxTextSize = Theme.TextSize.Body,
		TextTransparency = 1,
		ZIndex = 51,
		Parent = toast,
	})
	Components.Tween(toast, 0.2, { BackgroundTransparency = 0.08 })
	Components.Tween(label, 0.2, { TextTransparency = 0 })

	local toasts = {}
	for _, child in self.Container:GetChildren() do
		if child.Name == "Toast" then
			table.insert(toasts, child)
		end
	end
	if #toasts > 4 then
		table.sort(toasts, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		toasts[1]:Destroy()
	end

	task.delay(3.6, function()
		if toast.Parent then
			Components.Tween(toast, 0.3, { BackgroundTransparency = 1 })
			Components.Tween(label, 0.3, { TextTransparency = 1 })
			task.wait(0.32)
			toast:Destroy()
		end
	end)
end

return Notifications
