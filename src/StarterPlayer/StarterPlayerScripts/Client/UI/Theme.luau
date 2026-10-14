--[[
	Theme  (ModuleScript)
	Pfad: StarterPlayer/StarterPlayerScripts/Client/UI/Theme

	Designsystem der Benutzeroberfläche: Farben, Verläufe, Schriften,
	Abstände und Symbole. Alle Screens verwenden ausschließlich diese Werte.

	Stil: verspielt-modernes Racing-Design – dunkle „Glas“-Panels mit leichtem
	Verlauf und hellem Rand, kräftige Verlaufs-Buttons, runde Überschriften
	(FredokaOne) mit Textkontur, klare Fließtexte (Gotham).

	Layout-Prinzip: Die gesamte UI ist für eine Referenzauflösung von
	1280 × 720 entworfen und wird über ein UIScale am Wurzel-Frame auf jede
	Bildschirmgröße (PC, Tablet, Smartphone) skaliert.

	Tabellen:
		Colors      Grundfarben (Schlüssel bleiben stabil, Werte = Stil)
		Gradients   { hell, dunkel } – Verlaufspaare je Farbname
		Fonts       Title/Display/Button (verspielt), Bold/Medium/Body/Black (Gotham)
		TextSize    Huge … Tiny
		Icons       Unicode-/Emoji-Symbole für Buttons, Karten und Hinweise
		Corner, SmallCorner, Padding, ReferenceSize
	Funktion:
		Theme.GradientFor(color) -> hell, dunkel   (bekannte Farbe -> Verlaufspaar,
		                                           sonst automatisch aufgehellt/abgedunkelt)
]]

local rgb = Color3.fromRGB

local Theme = {}

Theme.ReferenceSize = Vector2.new(1280, 720)

Theme.Colors = {
	Background = rgb(9, 11, 26),
	Panel = rgb(30, 36, 72),
	PanelLight = rgb(54, 64, 116),
	PanelDark = rgb(16, 19, 40),
	Stroke = rgb(96, 114, 196),
	Accent = rgb(0, 208, 255),
	Accent2 = rgb(255, 61, 154),
	Success = rgb(38, 222, 118),
	Warning = rgb(255, 186, 18),
	Danger = rgb(255, 64, 94),
	Text = rgb(246, 248, 255),
	TextDim = rgb(166, 178, 222),
	Gold = rgb(255, 204, 46),
	XP = rgb(152, 102, 255),
	Black = rgb(0, 0, 0),
	White = rgb(255, 255, 255),
	-- Ergänzungen des Designsystems
	Purple = rgb(160, 92, 255),
	Orange = rgb(255, 136, 36),
	Shadow = rgb(3, 4, 14),
	TextDark = rgb(14, 18, 40),
}

-- Verlaufspaare { oben/links (hell), unten/rechts (dunkel) }
Theme.Gradients = {
	Accent = { rgb(70, 234, 255), rgb(0, 128, 255) },
	Accent2 = { rgb(255, 116, 198), rgb(224, 22, 118) },
	Success = { rgb(116, 248, 140), rgb(14, 184, 96) },
	Warning = { rgb(255, 224, 76), rgb(255, 146, 0) },
	Danger = { rgb(255, 116, 122), rgb(220, 26, 70) },
	Gold = { rgb(255, 234, 100), rgb(255, 154, 18) },
	XP = { rgb(198, 136, 255), rgb(104, 66, 255) },
	Purple = { rgb(190, 124, 255), rgb(118, 56, 238) },
	Orange = { rgb(255, 186, 76), rgb(255, 92, 28) },
	Neutral = { rgb(76, 88, 152), rgb(40, 47, 94) },
	Dark = { rgb(36, 43, 84), rgb(15, 18, 38) },
	-- Sonderverläufe
	Play = { rgb(84, 255, 168), rgb(0, 176, 255) },
	Line = { rgb(0, 208, 255), rgb(255, 61, 154) },
	Sheen = { rgb(255, 255, 255), rgb(176, 182, 214) },
}

Theme.Fonts = {
	Title = Enum.Font.FredokaOne, -- runde, kräftige Überschriften und Zahlen
	Display = Enum.Font.LuckiestGuy, -- große Banner (SIEG!, Countdown)
	Button = Enum.Font.FredokaOne, -- Button-Beschriftungen
	Bold = Enum.Font.GothamBold,
	Medium = Enum.Font.GothamMedium,
	Body = Enum.Font.Gotham,
	Black = Enum.Font.GothamBlack,
}

Theme.Corner = 14
Theme.SmallCorner = 10
Theme.Padding = 12

Theme.TextSize = {
	Huge = 64,
	Title = 30,
	Large = 22,
	Body = 18,
	Small = 15,
	Tiny = 13,
}

-- Symbole (nur Unicode/Emoji, keine Bild-Assets)
Theme.Icons = {
	Play = "▶",
	Quick = "⚡",
	Ranked = "👑",
	Training = "🎯",
	Shop = "🛒",
	Inventory = "🎒",
	Stats = "📊",
	Leaderboard = "🏆",
	Settings = "⚙️",
	Close = "✕",
	Check = "✔",
	Star = "★",
	Info = "i",
	Warning = "!",
	Error = "✕",
	Reward = "★",
	Flag = "🏁",
	Queue = "⏳",
	Spectate = "👀",
	Fire = "🔥",
	Gift = "🎁",
	Players = "👥",
	Lock = "🔒",
	Medal = "🥇",
	Left = "◀",
	Right = "▶",
	Up = "▲",
	Down = "▼",
	Hook = "⚓",
}

-- Nachschlagetabelle: Grundfarbe (Hex) -> Verlaufspaar
local byHex = {}
for name, pair in Theme.Gradients do
	local color = Theme.Colors[name]
	if color then
		byHex[color:ToHex()] = pair
	end
end
byHex[Theme.Colors.PanelLight:ToHex()] = Theme.Gradients.Neutral
byHex[Theme.Colors.Panel:ToHex()] = Theme.Gradients.Dark
byHex[Theme.Colors.PanelDark:ToHex()] = Theme.Gradients.Dark

--- Liefert das Verlaufspaar (hell, dunkel) zu einer Grundfarbe.
function Theme.GradientFor(color: Color3): (Color3, Color3)
	local pair = byHex[color:ToHex()]
	if pair then
		return pair[1], pair[2]
	end
	return color:Lerp(Theme.Colors.White, 0.22), color:Lerp(Theme.Colors.Black, 0.22)
end

return Theme
