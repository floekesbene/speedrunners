--[[
	Notifications  (ModuleScript)
	Pfad: StarterPlayer/StarterPlayerScripts/Client/UI/Screens/Notifications

	Kurze Hinweise („Toasts“) oben in der Bildschirmmitte (Info, Erfolg,
	Warnung, Fehler, Belohnung) sowie Meldungen zu Aufgaben, Erfolgen und
	Level-Ups. Jeder Toast hat ein Symbol, einen farbigen Seitenbalken und
	einen Schatten; er gleitet von oben herein und wieder hinaus.
	Höchstens 4 Toasts gleichzeitig, Anzeigedauer 3,6 s.

	API: :Push(text, kind)   kind = "Info" | "Success" | "Warning" | "Error" | "Reward"
]]

local UI = script.Parent.Parent
local Components = require(UI.Components)
local Theme = require(UI.Theme)

local new = Components.new

local TOAST_WIDTH = 540
local TOAST_HEIGHT = 52
local LIFETIME = 3.6
local MAX_TOASTS = 4

local Notifications = {}
Notifications.__index = Notifications

local KINDS = {
	Info = { Color = Theme.Colors.Accent, Icon = Theme.Icons.Info },
	Success = { Color = Theme.Colors.Success, Icon = Theme.Icons.Check },
	Warning = { Color = Theme.Colors.Warning, Icon = Theme.Icons.Warning },
	Error = { Color = Theme.Colors.Danger, Icon = Theme.Icons.Error },
	Reward = { Color = Theme.Colors.Gold, Icon = Theme.Icons.Reward },
}

function Notifications.new(ui)
	local self = setmetatable({}, Notifications)
	self.UI = ui
	self.Container = new("Frame", {
		Name = "Notifications",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 176),
		Size = UDim2.fromOffset(TOAST_WIDTH + 30, 300),
		ZIndex = 50,
		Parent = ui.Root,
	}, { Components.List(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center) })
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

-- Baut einen Toast; Rückgabe: holder (Listeneintrag), body (gleitender Inhalt), fades
-- fades = { { Instanz, Eigenschaft, sichtbarer Wert } } für Ein-/Ausblenden
local function buildToast(text: string, kind)
	local fades = {}
	local function fade(instance: Instance, property: string, value: number)
		table.insert(fades, { instance, property, value })
	end

	local holder = new("Frame", {
		Name = "Toast",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(TOAST_WIDTH, TOAST_HEIGHT),
		ZIndex = 50,
	})
	-- Inhalt gleitet innerhalb des Halters (die Liste selbst bleibt ruhig)
	local body = new("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 50,
		Parent = holder,
	})
	for _, layer in { { 8, 0.8 }, { 3, 0.62 } } do
		local shadow = new("Frame", {
			Name = "ShadowLayer",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 5),
			Size = UDim2.new(1, layer[1] * 2, 1, layer[1] * 2),
			BackgroundColor3 = Theme.Colors.Shadow,
			BorderSizePixel = 0,
			ZIndex = 50,
			Parent = body,
		})
		Components.Corner(Theme.Corner + layer[1]).Parent = shadow
		fade(shadow, "BackgroundTransparency", layer[2])
	end

	local panel = Components.Panel({
		Name = "Panel",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.PanelDark,
		StrokeColor = kind.Color,
		StrokeThickness = 2,
		ZIndex = 51,
		Parent = body,
	})
	fade(panel, "BackgroundTransparency", 0.06)
	local border = panel:FindFirstChild("Border")
	if border then
		fade(border, "Transparency", 0.15)
	end
	-- Farbiger Schimmer von links
	local tint = new("Frame", {
		Name = "Tint",
		Size = UDim2.fromScale(0.6, 1),
		BackgroundColor3 = kind.Color,
		BorderSizePixel = 0,
		ZIndex = 51,
		Parent = panel,
	})
	Components.Corner(Theme.Corner).Parent = tint
	Components.Gradient(kind.Color, 0, { 0, 1 }).Parent = tint
	fade(tint, "BackgroundTransparency", 0.82)
	-- Seitenbalken
	local bar = new("Frame", {
		Name = "SideBar",
		Position = UDim2.fromOffset(6, 7),
		Size = UDim2.new(0, 5, 1, -14),
		BackgroundColor3 = kind.Color,
		BorderSizePixel = 0,
		ZIndex = 52,
		Parent = panel,
	})
	Components.Corner(3).Parent = bar
	fade(bar, "BackgroundTransparency", 0)

	local icon, glyph = Components.Icon({
		Glyph = kind.Icon,
		Color = kind.Color,
		Size = 34,
		TextSize = 18,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 20, 0.5, 0),
		ZIndex = 52,
		Parent = panel,
	})
	fade(icon, "BackgroundTransparency", 0)
	fade(glyph, "TextTransparency", 0)
	fade(glyph, "TextStrokeTransparency", 0.5)
	local iconStroke = icon:FindFirstChildOfClass("UIStroke")
	if iconStroke then
		fade(iconStroke, "Transparency", 0.55)
	end

	local label = Components.Label({
		Text = text,
		Font = Theme.Fonts.Bold,
		Position = UDim2.fromOffset(66, 0),
		Size = UDim2.new(1, -80, 1, 0),
		TextScaled = true,
		MaxTextSize = Theme.TextSize.Body,
		TextColor3 = Theme.Colors.Text,
		ZIndex = 52,
		Parent = panel,
	})
	new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), Parent = label })
	fade(label, "TextTransparency", 0)
	return holder, body, fades
end

local function setFaded(fades, alpha: number, time: number)
	-- alpha 0 = sichtbar, 1 = ausgeblendet
	for _, entry in fades do
		local instance, property, visible = entry[1], entry[2], entry[3]
		local value = visible + (1 - visible) * alpha
		if time > 0 then
			Components.Tween(instance, time, { [property] = value })
		else
			instance[property] = value
		end
	end
end

function Notifications:Push(text: string, kind: string?)
	if text == "" then
		return
	end
	local style = KINDS[kind or "Info"] or KINDS.Info
	self.Count += 1
	local holder, body, fades = buildToast(text, style)
	holder.LayoutOrder = self.Count
	setFaded(fades, 1, 0)
	body.Position = UDim2.fromOffset(0, -18)
	holder.Parent = self.Container

	-- Hereingleiten + Aufblenden
	setFaded(fades, 0, 0.22)
	Components.Tween(body, 0.35, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Back)
	if kind == "Reward" then
		Components.Pop(body, 1.08, 0.4)
	end

	local toasts = {}
	for _, child in self.Container:GetChildren() do
		if child.Name == "Toast" then
			table.insert(toasts, child)
		end
	end
	if #toasts > MAX_TOASTS then
		table.sort(toasts, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		toasts[1]:Destroy()
	end

	task.delay(LIFETIME, function()
		if holder.Parent then
			-- Hinausgleiten nach rechts + Ausblenden
			setFaded(fades, 1, 0.3)
			Components.Tween(body, 0.3, { Position = UDim2.fromOffset(40, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.wait(0.32)
			holder:Destroy()
		end
	end)
end

return Notifications
