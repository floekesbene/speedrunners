--[[
	Settings  (ModuleScript)
	Pfad: StarterPlayer/StarterPlayerScripts/Client/UI/Screens/Settings

	Einstellungen (werden im Profil gespeichert), gruppiert in Glas-Karten mit
	Symbol-Kopf:
		Audio: Musik, Soundeffekte
		Steuerung: Gamepad-Empfindlichkeit, Touch-Buttons anzeigen
		Grafik: Kamerawackeln, reduzierte Effekte
		Spiel: Automatisch erneut anstellen
	Rechts eine Übersicht aller Tastenbelegungen mit Tastenkappen, umschaltbar
	zwischen PC, Gamepad und Touch (beim Öffnen ist das aktuelle Gerät gewählt).
]]

local UI = script.Parent.Parent
local Components = require(UI.Components)
local Theme = require(UI.Theme)

local new = Components.new
local rgb = Color3.fromRGB

local Settings = {}
Settings.__index = Settings

-- Tastenbelegung je Gerät: { Aktion, { Tasten … }, Hinweis? }
local CONTROLS = {
	Keyboard = {
		{ "Laufen", { "A", "D", "←", "→" } },
		{ "Springen", { "LEERTASTE", "W", "↑" }, "halten = höher" },
		{ "Greifhaken (halten)", { "E", "J", "MAUS L" } },
		{ "Slide · Air-Dash", { "SHIFT", "S", "↓" } },
		{ "Power-up", { "Q", "F" } },
		{ "Emote", { "G" } },
		{ "Respawn", { "R" } },
		{ "Menü", { "M" } },
	},
	Gamepad = {
		{ "Laufen", { "L-STICK", "D-PAD" } },
		{ "Springen", { "A" } },
		{ "Greifhaken", { "X", "R2" } },
		{ "Slide · Dash", { "B", "L2" } },
		{ "Power-up", { "Y", "R1" } },
		{ "Emote", { "L1" } },
		{ "Menü", { "SELECT" } },
	},
	Touch = {
		{ "Laufen", { "◀", "▶" }, "links unten" },
		{ "Springen", { "SPRUNG" } },
		{ "Greifhaken", { "HAKEN" } },
		{ "Slide · Dash", { "SLIDE" } },
		{ "Power-up", { "ITEM" } },
		{ "Menü", { "MENÜ" }, "oben" },
	},
}

-- Tastenkappe mit „Tiefe“ (dunklere Unterkante)
local function keyCap(parent: Instance, text: string, order: number)
	local width = math.max(30, 16 + 8 * (utf8.len(text) or #text))
	local cap = new("Frame", {
		Name = "Key",
		BackgroundColor3 = rgb(22, 26, 54),
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(width, 28),
		LayoutOrder = order,
		Parent = parent,
	})
	Components.Corner(7).Parent = cap
	local face = new("Frame", {
		Name = "Face",
		BackgroundColor3 = Theme.Colors.White,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -4),
		Parent = cap,
	})
	Components.Corner(7).Parent = face
	Components.Gradient({ rgb(104, 118, 190), rgb(58, 68, 128) }, 90).Parent = face
	Components.Stroke(Theme.Colors.Black, 1.5, 0.35).Parent = face
	Components.Label({
		Text = text,
		Font = Theme.Fonts.Black,
		TextSize = 12,
		TextColor3 = Theme.Colors.White,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		RichText = false,
		Size = UDim2.fromScale(1, 1),
		Parent = face,
	})
end

function Settings.new(ui)
	local self = setmetatable({}, Settings)
	self.UI = ui
	local modal = Components.Modal({
		Name = "Settings",
		Title = "EINSTELLUNGEN",
		Icon = Theme.Icons.Settings,
		Accent = Theme.Colors.Purple,
		Size = UDim2.fromOffset(900, 580),
		Parent = ui.Root,
	})
	self.Modal = modal
	ui:RegisterModal("Settings", modal)

	local left = new("ScrollingFrame", {
		Name = "Options",
		Size = UDim2.new(0.5, -8, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = Theme.Colors.Stroke,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = modal.Content,
	}, { Components.List(Enum.FillDirection.Vertical, 12) })
	Components.Padding(4, 14, 10, 4).Parent = left

	local state = ui.Ctx.ClientState
	local function save(key, value)
		state:SaveSettings({ [key] = value })
	end
	-- Abschnitts-Karte; contentHeight = Summe der Elementhöhen + Abstände
	local function section(order: number, title: string, icon: string, color: Color3, contentHeight: number)
		local _, panel = Components.Card({
			Name = title,
			Size = UDim2.new(1, 0, 0, 58 + contentHeight + 12),
			BackgroundColor3 = Theme.Colors.PanelDark,
			CornerRadius = 14,
			ShadowOffset = 3,
			ShadowSpread = 4,
			LayoutOrder = order,
			Parent = left,
		})
		local _, glyph = Components.Icon({ Glyph = icon, Color = color, Size = 30, TextSize = 16, Position = UDim2.fromOffset(12, 10), Parent = panel })
		glyph.TextStrokeTransparency = 1
		Components.Heading({
			Text = title,
			TextSize = 17,
			Outline = 1.5,
			RichText = false,
			Position = UDim2.fromOffset(50, 12),
			Size = UDim2.new(1, -62, 0, 26),
			Parent = panel,
		})
		Components.Divider({ Position = UDim2.fromOffset(12, 46), Size = UDim2.new(1, -24, 0, 2), Colors = { color, Theme.Colors.Accent }, Parent = panel })
		local body = new("Frame", {
			Name = "Body",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(14, 56),
			Size = UDim2.new(1, -28, 0, contentHeight),
			Parent = panel,
		}, { Components.List(Enum.FillDirection.Vertical, 6) })
		return body
	end

	self.Setters = {}
	local audio = section(1, "AUDIO", "🔊", Theme.Colors.Accent, 54 + 6 + 54)
	local _, setMusic = Components.Slider({ Text = "Musik", LayoutOrder = 1, Parent = audio, OnChanged = function(v)
		save("MusicVolume", v)
	end })
	local _, setSfx = Components.Slider({ Text = "Soundeffekte", LayoutOrder = 2, Parent = audio, OnChanged = function(v)
		save("SfxVolume", v)
	end })
	local controls = section(2, "STEUERUNG", "🎮", Theme.Colors.Orange, 54 + 6 + 44)
	local _, setSensitivity = Components.Slider({
		Text = "Gamepad-Empfindlichkeit",
		Min = 0.3,
		Max = 2.5,
		Step = 0.1,
		Value = 1,
		Format = function(v)
			return string.format("%.1f×", v)
		end,
		LayoutOrder = 1,
		Parent = controls,
		OnChanged = function(v)
			save("GamepadSensitivity", v)
		end,
	})
	local _, setTouch = Components.Toggle({ Text = "Touch-Buttons anzeigen", LayoutOrder = 2, Parent = controls, OnChanged = function(v)
		save("TouchControls", v)
	end })
	local graphics = section(3, "GRAFIK & KOMFORT", "✨", Theme.Colors.Accent2, 44 + 6 + 44)
	local _, setShake = Components.Toggle({ Text = "Kamerawackeln", LayoutOrder = 1, Parent = graphics, OnChanged = function(v)
		save("CameraShake", v)
	end })
	local _, setReduced = Components.Toggle({ Text = "Reduzierte Effekte (bessere Leistung)", LayoutOrder = 2, Parent = graphics, OnChanged = function(v)
		save("ReducedEffects", v)
	end })
	local gameplay = section(4, "SPIEL", Theme.Icons.Flag, Theme.Colors.Success, 44)
	local _, setRequeue = Components.Toggle({ Text = "Nach dem Rennen automatisch erneut anstellen", LayoutOrder = 1, Parent = gameplay, OnChanged = function(v)
		save("AutoRequeue", v)
	end })

	self.Apply = function(settings)
		setMusic(settings.MusicVolume or 0.5)
		setSfx(settings.SfxVolume or 0.8)
		setSensitivity(settings.GamepadSensitivity or 1)
		setTouch(settings.TouchControls ~= false)
		setShake(settings.CameraShake ~= false)
		setReduced(settings.ReducedEffects == true)
		setRequeue(settings.AutoRequeue ~= false)
	end

	self:_buildControls(modal.Content)

	modal.OnOpen = function()
		self.Apply(state:GetSettings())
		local device = ui.Ctx.InputController and ui.Ctx.InputController:GetDevice()
		self.SelectControls(if CONTROLS[device] then device else "Keyboard")
	end
	return self
end

-- Tastenübersicht rechts (Tabs PC / Gamepad / Touch)
function Settings:_buildControls(content: Frame)
	local _, panel = Components.Card({
		Name = "Controls",
		Position = UDim2.new(0.5, 8, 0, 0),
		Size = UDim2.new(0.5, -8, 1, -6),
		BackgroundColor3 = Theme.Colors.PanelDark,
		CornerRadius = 16,
		ShadowOffset = 4,
		ShadowSpread = 5,
		Parent = content,
	})
	local _, glyph = Components.Icon({ Glyph = "⌨", Color = Theme.Colors.Accent, Size = 30, TextSize = 16, Position = UDim2.fromOffset(12, 10), Parent = panel })
	glyph.TextStrokeTransparency = 1
	Components.Heading({
		Text = "TASTENBELEGUNG",
		TextSize = 17,
		Outline = 1.5,
		RichText = false,
		Position = UDim2.fromOffset(50, 12),
		Size = UDim2.new(1, -62, 0, 26),
		Parent = panel,
	})
	local pages = {}
	local _, selectTab = Components.Tabs({
		Tabs = {
			{ Name = "Keyboard", Label = "PC", Width = 100 },
			{ Name = "Gamepad", Label = "GAMEPAD", Width = 120 },
			{ Name = "Touch", Label = "TOUCH", Width = 100 },
		},
		Position = UDim2.fromOffset(14, 50),
		Size = UDim2.new(1, -28, 0, 34),
		Parent = panel,
		OnSelect = function(name)
			for pageName, page in pages do
				page.Visible = pageName == name
			end
		end,
	})
	self.SelectControls = selectTab
	for device, rows in CONTROLS do
		local page = new("Frame", {
			Name = device,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(14, 96),
			Size = UDim2.new(1, -28, 1, -104),
			Visible = false,
			Parent = panel,
		}, { Components.List(Enum.FillDirection.Vertical, 6) })
		for index, info in rows do
			local row = new("Frame", {
				BackgroundColor3 = Theme.Colors.White,
				BackgroundTransparency = if index % 2 == 0 then 0.95 else 1,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, 38),
				LayoutOrder = index,
				Parent = page,
			})
			Components.Corner(8).Parent = row
			Components.Label({
				Text = info[1],
				Font = Theme.Fonts.Bold,
				TextSize = 14,
				TextWrapped = false,
				RichText = false,
				Position = UDim2.fromOffset(8, if info[3] then 3 else 0),
				Size = UDim2.new(0.42, -8, if info[3] then 0 else 1, if info[3] then 20 else 0),
				Parent = row,
			})
			if info[3] then
				Components.Label({
					Text = info[3],
					Font = Theme.Fonts.Medium,
					TextSize = 11,
					TextColor3 = Theme.Colors.TextDim,
					TextWrapped = false,
					RichText = false,
					Position = UDim2.fromOffset(8, 21),
					Size = UDim2.new(0.42, -8, 0, 14),
					Parent = row,
				})
			end
			local keys = new("Frame", {
				Name = "Keys",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -6, 0.5, 0),
				Size = UDim2.new(0.58, -6, 0, 28),
				Parent = row,
			}, { Components.List(Enum.FillDirection.Horizontal, 5, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center) })
			for keyIndex, key in info[2] do
				keyCap(keys, key, keyIndex)
			end
		end
		pages[device] = page
	end
	selectTab("Keyboard")
end

function Settings:Start()
	self.Apply(self.UI.Ctx.ClientState:GetSettings())
end

return Settings
