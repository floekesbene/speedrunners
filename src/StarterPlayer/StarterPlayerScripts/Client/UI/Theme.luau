--[[
	Theme  (ModuleScript)
	Pfad: StarterPlayer/StarterPlayerScripts/Client/UI/Theme

	Designsystem der Benutzeroberfläche: Farben, Schriften, Abstände.
	Alle Screens verwenden ausschließlich diese Werte.

	Layout-Prinzip: Die gesamte UI ist für eine Referenzauflösung von
	1280 × 720 entworfen und wird über ein UIScale am Wurzel-Frame auf jede
	Bildschirmgröße (PC, Tablet, Smartphone) skaliert.
]]

local rgb = Color3.fromRGB

local Theme = {}

Theme.ReferenceSize = Vector2.new(1280, 720)

Theme.Colors = {
	Background = rgb(10, 12, 22),
	Panel = rgb(20, 24, 42),
	PanelLight = rgb(32, 38, 64),
	PanelDark = rgb(14, 17, 30),
	Stroke = rgb(62, 72, 115),
	Accent = rgb(0, 214, 255),
	Accent2 = rgb(255, 64, 129),
	Success = rgb(60, 220, 120),
	Warning = rgb(255, 196, 0),
	Danger = rgb(255, 70, 90),
	Text = rgb(240, 244, 255),
	TextDim = rgb(150, 160, 195),
	Gold = rgb(255, 200, 60),
	XP = rgb(130, 100, 255),
	Black = rgb(0, 0, 0),
	White = rgb(255, 255, 255),
}

Theme.Fonts = {
	Title = Enum.Font.GothamBlack,
	Bold = Enum.Font.GothamBold,
	Medium = Enum.Font.GothamMedium,
	Body = Enum.Font.Gotham,
}

Theme.Corner = 12
Theme.SmallCorner = 8
Theme.Padding = 12

Theme.TextSize = {
	Huge = 64,
	Title = 30,
	Large = 22,
	Body = 18,
	Small = 15,
	Tiny = 13,
}

return Theme
