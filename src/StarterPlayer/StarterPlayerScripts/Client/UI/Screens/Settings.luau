--[[
	Settings  (ModuleScript)
	Pfad: StarterPlayer/StarterPlayerScripts/Client/UI/Screens/Settings

	Einstellungen (werden im Profil gespeichert):
		Audio: Musik, Soundeffekte
		Steuerung: Gamepad-Empfindlichkeit, Touch-Buttons anzeigen
		Grafik: Kamerawackeln, reduzierte Effekte
		Spiel: Automatisch erneut anstellen
	Dazu eine Übersicht aller Tastenbelegungen.
]]

local UI = script.Parent.Parent
local Components = require(UI.Components)
local Theme = require(UI.Theme)

local new = Components.new

local Settings = {}
Settings.__index = Settings

local CONTROLS_TEXT = table.concat({
	"<b>PC</b>",
	"A / D oder ← / →: laufen",
	"Leertaste / W / ↑: springen (halten = höher)",
	"E / J / linke Maustaste: Greifhaken (halten)",
	"Shift / S / ↓: Slide (Boden) · Air-Dash (Luft)",
	"Q / F: Power-up · G: Emote · R: Respawn · M: Menü",
	"",
	"<b>Gamepad</b>",
	"Linker Stick / D-Pad: laufen · A: springen",
	"X oder R2: Greifhaken · B oder L2: Slide/Dash",
	"Y oder R1: Power-up · L1: Emote · Select: Menü",
	"",
	"<b>Touch</b>",
	"◀ ▶ links: laufen · rechts: SPRUNG, HAKEN, SLIDE, ITEM",
}, "\n")

function Settings.new(ui)
	local self = setmetatable({}, Settings)
	self.UI = ui
	local modal = Components.Modal({ Name = "Settings", Title = "EINSTELLUNGEN", Size = UDim2.fromOffset(900, 580), Parent = ui.Root })
	self.Modal = modal
	ui:RegisterModal("Settings", modal)

	local left = new("ScrollingFrame", {
		Size = UDim2.new(0.5, -10, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = modal.Content,
	}, { Components.List(Enum.FillDirection.Vertical, 10) })
	Components.Padding(4, 12, 4, 4).Parent = left

	local state = ui.Ctx.ClientState
	local function save(key, value)
		state:SaveSettings({ [key] = value })
	end
	local function header(order, text)
		Components.Label({ Text = text, Font = Theme.Fonts.Title, TextColor3 = Theme.Colors.Accent, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = order, Parent = left })
	end

	self.Setters = {}
	header(1, "AUDIO")
	local _, setMusic = Components.Slider({ Text = "Musik", LayoutOrder = 2, Parent = left, OnChanged = function(v)
		save("MusicVolume", v)
	end })
	local _, setSfx = Components.Slider({ Text = "Soundeffekte", LayoutOrder = 3, Parent = left, OnChanged = function(v)
		save("SfxVolume", v)
	end })
	header(4, "STEUERUNG")
	local _, setSensitivity = Components.Slider({
		Text = "Gamepad-Empfindlichkeit",
		Min = 0.3,
		Max = 2.5,
		Step = 0.1,
		Value = 1,
		Format = function(v)
			return string.format("%.1f×", v)
		end,
		LayoutOrder = 5,
		Parent = left,
		OnChanged = function(v)
			save("GamepadSensitivity", v)
		end,
	})
	local _, setTouch = Components.Toggle({ Text = "Touch-Buttons anzeigen", LayoutOrder = 6, Parent = left, OnChanged = function(v)
		save("TouchControls", v)
	end })
	header(7, "GRAFIK & KOMFORT")
	local _, setShake = Components.Toggle({ Text = "Kamerawackeln", LayoutOrder = 8, Parent = left, OnChanged = function(v)
		save("CameraShake", v)
	end })
	local _, setReduced = Components.Toggle({ Text = "Reduzierte Effekte (bessere Leistung)", LayoutOrder = 9, Parent = left, OnChanged = function(v)
		save("ReducedEffects", v)
	end })
	header(10, "SPIEL")
	local _, setRequeue = Components.Toggle({ Text = "Nach dem Rennen automatisch erneut anstellen", LayoutOrder = 11, Parent = left, OnChanged = function(v)
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

	local right = Components.Panel({
		Position = UDim2.new(0.5, 10, 0, 0),
		Size = UDim2.new(0.5, -10, 1, 0),
		BackgroundColor3 = Theme.Colors.PanelDark,
		Parent = modal.Content,
	})
	Components.Label({ Text = "STEUERUNG", Font = Theme.Fonts.Title, TextColor3 = Theme.Colors.Accent, Position = UDim2.fromOffset(16, 12), Size = UDim2.new(1, -32, 0, 24), Parent = right })
	Components.Label({
		Text = CONTROLS_TEXT,
		Font = Theme.Fonts.Medium,
		TextSize = Theme.TextSize.Small,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(16, 44),
		Size = UDim2.new(1, -32, 1, -56),
		Parent = right,
	})

	modal.OnOpen = function()
		self.Apply(state:GetSettings())
	end
	return self
end

function Settings:Start()
	self.Apply(self.UI.Ctx.ClientState:GetSettings())
end

return Settings
