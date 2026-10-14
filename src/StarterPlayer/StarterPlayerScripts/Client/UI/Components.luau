--[[
	Components  (ModuleScript)
	Pfad: StarterPlayer/StarterPlayerScripts/Client/UI/Components

	Wiederverwendbare UI-Bausteine im einheitlichen Stil (siehe Theme).
	Alles wird aus Frames, UIGradient, UIStroke, UICorner und Unicode-Symbolen
	gebaut – keine Bild-Assets.

	Grundbausteine (API stabil):
		new(className, props, children)        generischer Instanz-Builder
		Tween(instance, time, props, style?, direction?) -> Tween
		Corner(radius?)                        UICorner (Pixel)
		Stroke(color?, thickness?, transparency?)  Rand-UIStroke (Border)
		Padding(top, right?, bottom?, left?), List(dir?, pad?, hAlign?, vAlign?), Grid(cellSize, pad?)
		Label(props)                           TextLabel; Zusatz-Props: MaxTextSize (mit TextScaled),
		                                       Outline (true|Dicke), OutlineColor, OutlineTransparency,
		                                       TextGradient ({hell, dunkel}, vertikal)
		Panel(props)                           Glas-Panel (Verlauf + heller Rand); Zusatz-Props:
		                                       NoStroke, StrokeColor, StrokeThickness, StrokeTransparency,
		                                       CornerRadius, NoGradient, Shadow (true|Shadow-Props;
		                                       nur wenn der Parent KEIN UIListLayout/UIGridLayout hat)
		Button(props) -> TextButton            Verlaufs-Button mit Hover-/Klick-Animation.
		                                       Props: Text, OnClick, Color, TextColor, TextSize, TextScaled,
		                                       Font, Size, Position, AnchorPoint, LayoutOrder, Name,
		                                       Visible, ZIndex, CornerRadius, StrokeColor, NoStroke, Icon
		                                       (Symbol vor dem Text), Gradient ({hell, dunkel} statt
		                                       des automatischen Verlaufs, z. B. Theme.Gradients.Play)
		                                       Text, TextColor3, TextSize, Font usw. weiterhin direkt am
		                                       Button setzen – sie werden auf das Kind "Label" gespiegelt
		                                       (der eigene Button-Text bleibt unsichtbar, weil ein
		                                       UIGradient sonst auch die Schrift einfärbt). Für Ein-/
		                                       Ausblenden des Textes button.Label.TextTransparency nutzen.
		SetButtonColor(button, color, gradient?)  Grundfarbe wechseln (Verlauf, Rand, Kontur)
		ProgressBar(props) -> frame, set(alpha, tweenTime?), fill
		                                       Zusatz-Props: Gradient (true | {links, rechts}) für einen
		                                       waagrechten Farbverlauf, BackgroundTransparency
		Toggle(props) -> frame, setValue(bool)
		Slider(props) -> frame, setValue(number)
		Tabs(props) -> frame, select(name)
		Modal(props) -> { Root, Window, Content, Title, CloseButton, Open(), Close(), IsOpen(),
		                  OnOpen, OnClose (Callback-Felder) }
		                                       Zusatz-Props: Icon (Symbol vor dem Titel), Accent (Farbe
		                                       der Kopfzeile). Geometrie unverändert: Titel y 16–52,
		                                       Content ab y 68, Schließen-Button oben rechts 44×44.

	Neue Bausteine für alle Screens:
		Gradient(colors, rotation?, transparency?) -> UIGradient
		    colors: Color3 | {c1, c2, …} | ColorSequence; transparency: Zahl | {t1, t2, …} | NumberSequence
		GradientColors(color) -> hell, dunkel   (Verlaufspaar zu einer Farbe, siehe Theme.GradientFor)
		TextStroke(thickness?, color?, transparency?) -> UIStroke (Contextual = Textkontur)
		Shadow(target, props?) -> Frame         weicher Schlagschatten als Geschwister-Frame hinter
		                                        target (folgt Position/Größe/Sichtbarkeit). Props:
		                                        Offset (6), Spread (6), Strength (1), CornerRadius.
		                                        Nicht in Containern mit UIListLayout – dafür Card nutzen.
		Card(props) -> holder, panel            Panel mit Schatten in einem transparenten Halter;
		                                        funktioniert auch in Listen/Grids. Panel-Props +
		                                        ShadowOffset, ShadowSpread, ShadowStrength.
		Heading(props) -> TextLabel             große FredokaOne-Überschrift mit Kontur (Label-Props)
		Icon(props) -> frame, glyphLabel        runde Symbol-Blase. Props: Glyph, Color, Size (Zahl, 40),
		                                        TextSize, Position, AnchorPoint, LayoutOrder, ZIndex, Parent
		SetIconColor(icon, color)               Symbol-Blase umfärben
		IconButton(props) -> TextButton         Kachel-Button: großes Symbol + Beschriftung darunter.
		                                        Props wie Button + Icon, IconSize, IconColor (Symbol in
		                                        farbiger Blase); Kinder "Glyph"/"IconBubble", "Caption"
		Pill(props) -> frame, label             kleine Plakette/Chip. Props: Text, Color, TextColor,
		                                        Size, Position, AnchorPoint, LayoutOrder, TextSize, Parent
		Divider(props) -> Frame                 dünne Verlaufslinie (Props: Size, Position, Colors, Parent)
		CoinIcon(size, props?) -> Frame         Münze aus Kreisen (props: Position, AnchorPoint, Parent)
		Ring(props) -> frame, set(alpha), inner kreisförmige Fortschrittsanzeige. Props: Size (Zahl),
		                                        Thickness, Color, TrackColor, InnerColor, Position,
		                                        AnchorPoint, ZIndex, Parent; Inhalte in `inner` legen.
		Pop(guiObject, amount?, time?)          kurzer „Hüpfer“ (UIScale) – z. B. bei Wertänderungen
		Loop(instance, time, props, style?) -> Tween   endlos hin und her (Pulsieren, Schweben)
		Shine(target, props?) -> Frame          wandernder Glanzstreifen über einem Button/Panel
		                                        (Props: Interval (4.5), CornerRadius, Transparency)

	Callbacks (vom UIController gesetzt): ClickCallback(), HoverCallback()
]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)

local Components = {}

-- Wird vom UIController gesetzt, um Klick-/Hover-Sounds abzuspielen.
Components.ClickCallback = nil
Components.HoverCallback = nil

-- Helligkeits-Multiplikator für Buttons (Verlauf × Hintergrundfarbe)
local BUTTON_REST = Color3.fromRGB(232, 232, 236)
local BUTTON_HOVER = Color3.fromRGB(255, 255, 255)
local BUTTON_PRESS = Color3.fromRGB(196, 196, 204)

function Components.new(className: string, props, children)
	local instance = Instance.new(className)
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				instance[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local new = Components.new

function Components.Tween(instance: Instance, time: number, props, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local tween = TweenService:Create(instance, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	tween:Play()
	return tween
end

--- Endlos hin und her laufender Tween (z. B. Pulsieren). Rückgabe: Tween (mit :Cancel() stoppbar).
function Components.Loop(instance: Instance, time: number, props, style: Enum.EasingStyle?)
	local info = TweenInfo.new(time, style or Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	local tween = TweenService:Create(instance, info, props)
	tween:Play()
	return tween
end

function Components.Corner(radius: number?)
	return new("UICorner", { CornerRadius = UDim.new(0, radius or Theme.Corner) })
end

function Components.Stroke(color: Color3?, thickness: number?, transparency: number?)
	return new("UIStroke", {
		Color = color or Theme.Colors.Stroke,
		Thickness = thickness or 1.5,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

--- Kontur um Text (UIStroke im Contextual-Modus).
function Components.TextStroke(thickness: number?, color: Color3?, transparency: number?)
	return new("UIStroke", {
		Name = "TextStroke",
		Color = color or Theme.Colors.Shadow,
		Thickness = thickness or 2,
		Transparency = transparency or 0.2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
	})
end

local function toColorSequence(colors)
	if typeof(colors) == "ColorSequence" then
		return colors
	elseif typeof(colors) == "Color3" then
		return ColorSequence.new(colors)
	elseif #colors == 1 then
		return ColorSequence.new(colors[1])
	elseif #colors == 2 then
		return ColorSequence.new(colors[1], colors[2])
	end
	local keypoints = {}
	for index, color in colors do
		table.insert(keypoints, ColorSequenceKeypoint.new((index - 1) / (#colors - 1), color))
	end
	return ColorSequence.new(keypoints)
end

local function toNumberSequence(values)
	if typeof(values) == "NumberSequence" then
		return values
	elseif type(values) == "number" then
		return NumberSequence.new(values)
	elseif #values == 1 then
		return NumberSequence.new(values[1])
	end
	local keypoints = {}
	for index, value in values do
		table.insert(keypoints, NumberSequenceKeypoint.new((index - 1) / (#values - 1), value))
	end
	return NumberSequence.new(keypoints)
end

--- UIGradient. colors: Color3 | {Color3, …} | ColorSequence; rotation in Grad (90 = von oben nach unten).
function Components.Gradient(colors, rotation: number?, transparency)
	local gradient = new("UIGradient", {
		Color = toColorSequence(colors),
		Rotation = rotation or 0,
	})
	if transparency ~= nil then
		gradient.Transparency = toNumberSequence(transparency)
	end
	return gradient
end

--- Verlaufspaar (hell, dunkel) zu einer Grundfarbe.
function Components.GradientColors(color: Color3): (Color3, Color3)
	return Theme.GradientFor(color)
end

function Components.Padding(top: number, right: number?, bottom: number?, left: number?)
	return new("UIPadding", {
		PaddingTop = UDim.new(0, top),
		PaddingRight = UDim.new(0, right or top),
		PaddingBottom = UDim.new(0, bottom or top),
		PaddingLeft = UDim.new(0, left or right or top),
	})
end

function Components.List(direction: Enum.FillDirection?, padding: number?, horizontal: Enum.HorizontalAlignment?, vertical: Enum.VerticalAlignment?)
	return new("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or 8),
		HorizontalAlignment = horizontal or Enum.HorizontalAlignment.Left,
		VerticalAlignment = vertical or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

function Components.Grid(cellSize: UDim2, padding: number?)
	return new("UIGridLayout", {
		CellSize = cellSize,
		CellPadding = UDim2.fromOffset(padding or 10, padding or 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

local LABEL_EXTRA = { MaxTextSize = true, Outline = true, OutlineColor = true, OutlineTransparency = true, TextGradient = true }

--- Textlabel. props werden direkt übernommen; Standard: transparent, Theme-Schrift.
function Components.Label(props)
	local label = new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Bold,
		TextColor3 = Theme.Colors.Text,
		TextSize = Theme.TextSize.Body,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		RichText = true,
		Size = UDim2.new(1, 0, 0, 24),
	})
	for key, value in props do
		if not LABEL_EXTRA[key] then
			label[key] = value
		end
	end
	if props.TextScaled and props.MaxTextSize then
		new("UITextSizeConstraint", { MaxTextSize = props.MaxTextSize, Parent = label })
	end
	if props.Outline then
		Components.TextStroke(if type(props.Outline) == "number" then props.Outline else 2, props.OutlineColor, props.OutlineTransparency).Parent = label
	end
	if props.TextGradient then
		Components.Gradient(props.TextGradient, 90).Parent = label
	end
	return label
end

--- Große Überschrift (FredokaOne, weiß, mit Kontur). Nimmt alle Label-Props.
function Components.Heading(props)
	local merged = {
		Font = Theme.Fonts.Title,
		TextSize = Theme.TextSize.Title,
		TextColor3 = Theme.Colors.White,
		TextWrapped = false,
		Outline = 2,
		Size = UDim2.new(1, 0, 0, 36),
	}
	for key, value in props do
		merged[key] = value
	end
	return Components.Label(merged)
end

-- Schattenschichten (äußere weiche + innere dichtere) in einen Container legen
local function addShadowLayers(parent: Instance, radius: number, offset: number, spread: number, zIndex: number, strength: number)
	for _, layer in { { spread, 0.82 }, { math.max(1, spread * 0.35), 0.62 } } do
		local grow = layer[1]
		local frame = new("Frame", {
			Name = "ShadowLayer",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, offset),
			Size = UDim2.new(1, grow * 2, 1, grow * 2),
			BackgroundColor3 = Theme.Colors.Shadow,
			BackgroundTransparency = 1 - (1 - layer[2]) * strength,
			BorderSizePixel = 0,
			ZIndex = zIndex,
			Parent = parent,
		})
		Components.Corner(radius + grow).Parent = frame
	end
end

--- Weicher Schlagschatten hinter `target` (als Geschwister-Frame im selben Parent).
--- Folgt Position, Größe, AnchorPoint und Sichtbarkeit automatisch (ereignisbasiert).
function Components.Shadow(target: GuiObject, props)
	props = props or {}
	local corner = target:FindFirstChildOfClass("UICorner")
	local radius = props.CornerRadius or (if corner then corner.CornerRadius.Offset else Theme.Corner)
	local zIndex = math.max(0, (target.ZIndex or 1) - 1)
	local holder = new("Frame", {
		Name = (target.Name or "") .. "Shadow",
		BackgroundTransparency = 1,
		ZIndex = zIndex,
	})
	addShadowLayers(holder, radius, props.Offset or 6, props.Spread or 6, zIndex, props.Strength or 1)
	local function sync()
		holder.AnchorPoint = target.AnchorPoint
		holder.Position = target.Position
		holder.Size = target.Size
		holder.Visible = target.Visible
	end
	for _, property in { "AnchorPoint", "Position", "Size", "Visible" } do
		target:GetPropertyChangedSignal(property):Connect(sync)
	end
	target.AncestryChanged:Connect(function()
		if holder.Parent ~= target.Parent then
			holder.Parent = target.Parent
		end
	end)
	target.Destroying:Connect(function()
		holder:Destroy()
	end)
	sync()
	holder.Parent = target.Parent
	return holder
end

local PANEL_EXTRA = {
	NoStroke = true,
	StrokeColor = true,
	StrokeThickness = true,
	StrokeTransparency = true,
	CornerRadius = true,
	NoGradient = true,
	Shadow = true,
}

--- Panel im Glas-Stil: halbtransparenter Hintergrund mit Verlauf (oben heller),
--- runde Ecken und ein Rand, der oben heller „glänzt“.
function Components.Panel(props)
	local frame = new("Frame", {
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.06,
		BorderSizePixel = 0,
	})
	for key, value in props do
		if not PANEL_EXTRA[key] then
			frame[key] = value
		end
	end
	Components.Corner(props.CornerRadius).Parent = frame
	if not props.NoGradient then
		local sheen = Components.Gradient(Theme.Gradients.Sheen, 90)
		sheen.Name = "Sheen"
		sheen.Parent = frame
	end
	if not props.NoStroke then
		local stroke = Components.Stroke(props.StrokeColor, props.StrokeThickness or 1.5, props.StrokeTransparency or 0.1)
		stroke.Name = "Border"
		Components.Gradient({ Theme.Colors.White, Color3.fromRGB(120, 126, 164) }, 90).Parent = stroke
		stroke.Parent = frame
	end
	if props.Shadow and frame.Parent then
		Components.Shadow(frame, if type(props.Shadow) == "table" then props.Shadow else nil)
	end
	return frame
end

local CARD_HOLDER = {
	Name = true,
	Size = true,
	Position = true,
	AnchorPoint = true,
	LayoutOrder = true,
	Visible = true,
	Parent = true,
	ZIndex = true,
	ShadowOffset = true,
	ShadowSpread = true,
	ShadowStrength = true,
	Shadow = true,
}

--- Panel mit Schatten in einem transparenten Halter (auch in Listen/Grids nutzbar).
--- Rückgabe: holder (Position/Größe/LayoutOrder), panel (Inhalte hier hinein)
function Components.Card(props)
	local zIndex = props.ZIndex or 1
	local holder = new("Frame", {
		Name = props.Name or "Card",
		BackgroundTransparency = 1,
		Size = props.Size or UDim2.fromOffset(200, 100),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		Visible = if props.Visible == nil then true else props.Visible,
		ZIndex = zIndex,
	})
	addShadowLayers(holder, props.CornerRadius or Theme.Corner, props.ShadowOffset or 6, props.ShadowSpread or 6, zIndex, props.ShadowStrength or 1)
	local panelProps = {}
	for key, value in props do
		if not CARD_HOLDER[key] then
			panelProps[key] = value
		end
	end
	panelProps.Name = "Panel"
	panelProps.Size = UDim2.fromScale(1, 1)
	panelProps.ZIndex = zIndex + 1
	local panel = Components.Panel(panelProps)
	panel.Parent = holder
	holder.Parent = props.Parent
	return holder, panel
end

local function isLight(color: Color3): boolean
	return color.R * 0.299 + color.G * 0.587 + color.B * 0.114 > 0.55
end

-- Verlauf, Rand und Textkontur eines Buttons an seine Grundfarbe anpassen
-- (gradient = optionales eigenes Verlaufspaar {hell, dunkel})
local function paintButton(button: GuiButton, color: Color3, gradient)
	local top, bottom = Theme.GradientFor(color)
	if gradient then
		top, bottom = gradient[1], gradient[2]
	end
	local fill = button:FindFirstChild("Fill")
	if fill then
		fill.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, top:Lerp(Theme.Colors.White, 0.1)),
			ColorSequenceKeypoint.new(0.45, top),
			ColorSequenceKeypoint.new(1, bottom),
		})
	else
		button.BackgroundColor3 = color
	end
	local border = button:FindFirstChild("Border")
	if border and not button:GetAttribute("CustomStroke") then
		border.Color = bottom:Lerp(Theme.Colors.Black, 0.45)
	end
	local label = button:FindFirstChild("Label")
	if label then
		label.TextStrokeColor3 = bottom:Lerp(Theme.Colors.Black, 0.6)
	end
end

-- Helle Schrift bekommt eine dunkle Kontur, dunkle Schrift keine
local function updateTextStroke(button: GuiButton, label: TextLabel)
	label.TextStrokeTransparency = if isLight(button.TextColor3 or Theme.Colors.White) then 0.55 else 1
end

-- Text-Eigenschaften, die vom Button auf sein Kind "Label" gespiegelt werden.
-- Hintergrund: Ein UIGradient färbt auch den eigenen Text eines TextButtons ein
-- (weiße Schrift auf Cyan-Verlauf würde cyan). Deshalb ist der eigene Text des
-- Buttons unsichtbar (TextTransparency = 1) und ein Kind-Label zeigt ihn an.
local MIRRORED_TEXT = {
	"Text",
	"TextColor3",
	"TextSize",
	"Font",
	"TextScaled",
	"TextWrapped",
	"RichText",
	"TextXAlignment",
	"TextYAlignment",
	"TextTruncate",
}

--- Verlaufs-Button mit Hover-/Klick-Animation.
--- props.OnClick, props.Color, props.TextColor, props.Icon (Symbol vor dem Text) u. a. (siehe Kopf)
function Components.Button(props)
	local color = props.Color or Theme.Colors.PanelLight
	local text = props.Text or ""
	if props.Icon then
		text = props.Icon .. "  " .. text
	end
	local button = new("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = BUTTON_REST,
		BorderSizePixel = 0,
		Font = props.Font or Theme.Fonts.Button,
		Text = text,
		TextColor3 = props.TextColor or Theme.Colors.Text,
		TextSize = props.TextSize or Theme.TextSize.Body,
		Size = props.Size or UDim2.fromOffset(200, 48),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		Name = props.Name or "Button",
		Selectable = true,
		Visible = if props.Visible == nil then true else props.Visible,
		ZIndex = props.ZIndex or 1,
		TextTransparency = 1, -- sichtbarer Text liegt im Kind "Label"
	})
	local label = new("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = if props.TextScaled then UDim2.new(1, -20, 1, -8) else UDim2.new(1, -12, 1, 0),
		TextStrokeTransparency = 1,
		ZIndex = props.ZIndex or 1,
		Parent = button,
	})
	if props.TextScaled then
		button.TextScaled = true
		new("UITextSizeConstraint", { MaxTextSize = props.TextSize or Theme.TextSize.Body, Parent = label })
	end
	for _, property in MIRRORED_TEXT do
		label[property] = button[property]
		button:GetPropertyChangedSignal(property):Connect(function()
			label[property] = button[property]
			if property == "TextColor3" then
				updateTextStroke(button, label)
			end
		end)
	end
	Components.Corner(props.CornerRadius or Theme.SmallCorner).Parent = button
	local fill = Components.Gradient(Theme.Colors.White, 90)
	fill.Name = "Fill"
	fill.Parent = button
	local stroke = Components.Stroke(props.StrokeColor or Theme.Colors.Black, 2, if props.NoStroke then 1 else 0.05)
	stroke.Name = "Border"
	stroke.Parent = button
	if props.StrokeColor then
		button:SetAttribute("CustomStroke", true)
	end
	local scale = new("UIScale", { Parent = button })

	button:SetAttribute("BaseColor", color)
	paintButton(button, color, props.Gradient)
	updateTextStroke(button, label)

	local hovering = false
	local function rest()
		hovering = false
		Components.Tween(button, 0.12, { BackgroundColor3 = BUTTON_REST })
		Components.Tween(scale, 0.15, { Scale = 1 })
	end
	button.MouseEnter:Connect(function()
		hovering = true
		Components.Tween(button, 0.12, { BackgroundColor3 = BUTTON_HOVER })
		Components.Tween(scale, 0.18, { Scale = 1.05 }, Enum.EasingStyle.Back)
		if Components.HoverCallback then
			Components.HoverCallback()
		end
	end)
	button.MouseLeave:Connect(rest)
	button.MouseButton1Down:Connect(function()
		Components.Tween(button, 0.06, { BackgroundColor3 = BUTTON_PRESS })
		Components.Tween(scale, 0.06, { Scale = 0.94 })
	end)
	button.MouseButton1Up:Connect(function()
		Components.Tween(button, 0.1, { BackgroundColor3 = if hovering then BUTTON_HOVER else BUTTON_REST })
		Components.Tween(scale, 0.22, { Scale = if hovering then 1.05 else 1 }, Enum.EasingStyle.Back)
	end)
	-- Touch: kein MouseLeave – nach dem Loslassen in den Ruhezustand
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			rest()
		end
	end)
	button.Activated:Connect(function()
		if Components.ClickCallback then
			Components.ClickCallback()
		end
		if props.OnClick then
			props.OnClick()
		end
	end)
	return button
end

--- Ändert die Grundfarbe eines Buttons (Verlauf, Rand, Textkontur).
--- gradient (optional): eigenes Verlaufspaar {hell, dunkel}, z. B. Theme.Gradients.Play
function Components.SetButtonColor(button: TextButton, color: Color3, gradient)
	button:SetAttribute("BaseColor", color)
	paintButton(button, color, gradient)
end

--- Kachel-Button: großes Symbol oben, Beschriftung darunter.
--- Props wie Button + Icon (Symbol), IconSize, IconColor (Symbol in farbiger Blase).
--- Kinder: "Glyph" (bzw. "IconBubble" mit "Glyph"), "Caption".
function Components.IconButton(props)
	local buttonProps = {}
	for key, value in props do
		if key ~= "Icon" and key ~= "IconSize" and key ~= "IconColor" and key ~= "Text" then
			buttonProps[key] = value
		end
	end
	buttonProps.Text = ""
	buttonProps.Size = props.Size or UDim2.fromOffset(96, 84)
	buttonProps.CornerRadius = props.CornerRadius or Theme.Corner
	local button = Components.Button(buttonProps)
	local iconSize = props.IconSize or 30
	if props.IconColor then
		local bubbleSize = math.floor(iconSize * 1.45)
		local _, bubbleGlyph = Components.Icon({
			Name = "IconBubble",
			Glyph = props.Icon or "",
			Color = props.IconColor,
			Size = bubbleSize,
			TextSize = math.floor(iconSize * 0.8),
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 8),
			ZIndex = button.ZIndex,
			Parent = button,
		})
		bubbleGlyph.TextStrokeTransparency = 1 -- Emoji ohne Kontur
	else
		Components.Label({
			Name = "Glyph",
			Text = props.Icon or "",
			Font = Theme.Fonts.Title,
			TextSize = iconSize,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextWrapped = false,
			RichText = false,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 8),
			Size = UDim2.new(1, -8, 0.55, -6),
			ZIndex = button.ZIndex,
			Parent = button,
		})
	end
	Components.Label({
		Name = "Caption",
		Text = props.Text or "",
		Font = Theme.Fonts.Button,
		TextSize = props.TextSize or 14,
		TextScaled = true,
		MaxTextSize = props.TextSize or 14,
		TextColor3 = props.TextColor or Theme.Colors.Text,
		TextStrokeTransparency = 0.6,
		TextStrokeColor3 = Theme.Colors.Shadow,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -10, 0, 18),
		ZIndex = button.ZIndex,
		Parent = button,
	})
	return button
end

--- Runde Symbol-Blase mit Farbverlauf. Rückgabe: frame, glyphLabel
function Components.Icon(props)
	local size = props.Size or 40
	local color = props.Color or Theme.Colors.Accent
	local top, bottom = Theme.GradientFor(color)
	local frame = new("Frame", {
		Name = props.Name or "Icon",
		BackgroundColor3 = Theme.Colors.White,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(size, size),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
	})
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = frame })
	Components.Gradient({ top, bottom }, 90).Parent = frame
	Components.Stroke(Theme.Colors.White, 2, 0.55).Parent = frame
	local glyph = Components.Label({
		Name = "Glyph",
		Text = props.Glyph or "",
		Font = Theme.Fonts.Title,
		TextSize = props.TextSize or math.floor(size * 0.55),
		TextColor3 = Theme.Colors.White,
		TextStrokeTransparency = 0.5,
		TextStrokeColor3 = bottom:Lerp(Theme.Colors.Black, 0.6),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = false,
		RichText = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = props.ZIndex or 1,
		Parent = frame,
	})
	frame.Parent = props.Parent
	return frame, glyph
end

--- Färbt eine mit Components.Icon erzeugte Symbol-Blase um.
function Components.SetIconColor(icon: Frame, color: Color3)
	local top, bottom = Theme.GradientFor(color)
	local gradient = icon:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Color = ColorSequence.new(top, bottom)
	end
	local glyph = icon:FindFirstChild("Glyph")
	if glyph then
		glyph.TextStrokeColor3 = bottom:Lerp(Theme.Colors.Black, 0.6)
	end
end

--- Kleine Plakette (Chip). Rückgabe: frame, label
function Components.Pill(props)
	local color = props.Color or Theme.Colors.Accent
	local frame = new("Frame", {
		Name = props.Name or "Pill",
		BackgroundColor3 = color,
		BackgroundTransparency = props.BackgroundTransparency or 0.78,
		BorderSizePixel = 0,
		Size = props.Size or UDim2.fromOffset(96, 24),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
	})
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = frame })
	local stroke = Components.Stroke(color, 1.5, 0.2)
	stroke.Name = "Border"
	stroke.Parent = frame
	local label = Components.Label({
		Name = "Label",
		Text = props.Text or "",
		Font = Theme.Fonts.Title,
		TextSize = props.TextSize or 14,
		TextScaled = true,
		MaxTextSize = props.TextSize or 14,
		TextColor3 = props.TextColor or color:Lerp(Theme.Colors.White, 0.35),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -14, 1, -6),
		ZIndex = props.ZIndex or 1,
		Parent = frame,
	})
	frame.Parent = props.Parent
	return frame, label
end

--- Dünne Verlaufslinie (Standard: Akzent -> Akzent 2, an den Enden ausblendend).
function Components.Divider(props)
	props = props or {}
	local line = new("Frame", {
		Name = props.Name or "Divider",
		BackgroundColor3 = Theme.Colors.White,
		BorderSizePixel = 0,
		Size = props.Size or UDim2.new(1, 0, 0, 2),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
	})
	Components.Corner(2).Parent = line
	Components.Gradient(props.Colors or Theme.Gradients.Line, 0, { 0.7, 0, 0, 0.7 }).Parent = line
	line.Parent = props.Parent
	return line
end

--- Münz-Symbol aus Kreisen (ohne Bild-Asset).
function Components.CoinIcon(size: number?, props)
	props = props or {}
	local px = size or 28
	local coin = new("Frame", {
		Name = props.Name or "Coin",
		BackgroundColor3 = Theme.Colors.White,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(px, px),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		ZIndex = props.ZIndex or 1,
	})
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = coin })
	Components.Gradient(Theme.Gradients.Gold, 135).Parent = coin
	Components.Stroke(Color3.fromRGB(176, 92, 0), math.max(1, px / 14), 0).Parent = coin
	local inner = new("Frame", {
		Name = "Inner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.62, 0.62),
		BackgroundColor3 = Theme.Colors.White,
		BorderSizePixel = 0,
		ZIndex = props.ZIndex or 1,
		Parent = coin,
	})
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = inner })
	Components.Gradient({ Color3.fromRGB(255, 176, 30), Color3.fromRGB(255, 226, 92) }, 135).Parent = inner
	Components.Stroke(Color3.fromRGB(214, 120, 0), math.max(1, px / 20), 0.25).Parent = inner
	-- Glanzpunkt
	local shine = new("Frame", {
		Name = "Shine",
		Position = UDim2.fromScale(0.2, 0.14),
		Size = UDim2.fromScale(0.26, 0.16),
		Rotation = -35,
		BackgroundColor3 = Theme.Colors.White,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		ZIndex = props.ZIndex or 1,
		Parent = coin,
	})
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = shine })
	coin.Parent = props.Parent
	return coin
end

--- Kreisförmige Fortschrittsanzeige aus zwei geclippten Halbkreisen.
--- Rückgabe: frame, set(alpha, tweenTime?), inner (Innenfläche für Inhalte)
function Components.Ring(props)
	local size = props.Size or 64
	local thickness = props.Thickness or 6
	local color = props.Color or Theme.Colors.Accent
	local zIndex = props.ZIndex or 1
	local frame = new("Frame", {
		Name = props.Name or "Ring",
		BackgroundColor3 = props.TrackColor or Theme.Colors.PanelDark,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(size, size),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		ZIndex = zIndex,
	})
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = frame })
	local transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(0.501, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	-- Jede Hälfte zeigt eine volle Scheibe, deren Verlauf halb deckend/halb
	-- transparent ist; die Drehung des Verlaufs bestimmt den sichtbaren Bogen.
	local gradients = {}
	for index = 1, 2 do
		-- index 1 = rechte Hälfte (0–50 %), index 2 = linke Hälfte (50–100 %)
		local isRight = index == 1
		local clip = new("Frame", {
			Name = if isRight then "RightHalf" else "LeftHalf",
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			Position = UDim2.fromScale(if isRight then 0.5 else 0, 0),
			Size = UDim2.fromScale(0.5, 1),
			ZIndex = zIndex,
			Parent = frame,
		})
		local disc = new("Frame", {
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(if isRight then -1 else 0, 0),
			Size = UDim2.fromScale(2, 1),
			ZIndex = zIndex,
			Parent = clip,
		})
		new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = disc })
		local gradient = new("UIGradient", { Transparency = transparency, Rotation = if isRight then 0 else 180, Parent = disc })
		gradients[index] = gradient
	end
	local inner = new("Frame", {
		Name = "Inner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -thickness * 2, 1, -thickness * 2),
		BackgroundColor3 = props.InnerColor or Theme.Colors.PanelDark,
		BorderSizePixel = 0,
		ZIndex = zIndex,
		Parent = frame,
	})
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = inner })
	local current = 0
	local function apply(alpha: number)
		gradients[1].Rotation = math.clamp(alpha, 0, 0.5) * 360
		gradients[2].Rotation = 180 + math.clamp(alpha - 0.5, 0, 0.5) * 360
	end
	local function set(alpha: number, tweenTime: number?)
		alpha = math.clamp(alpha, 0, 1)
		if tweenTime and tweenTime > 0 then
			local from = current
			local value = new("NumberValue", { Value = 0 })
			value:GetPropertyChangedSignal("Value"):Connect(function()
				apply(from + (alpha - from) * value.Value)
			end)
			local tween = Components.Tween(value, tweenTime, { Value = 1 })
			tween.Completed:Connect(function()
				apply(alpha)
				value:Destroy()
			end)
		else
			apply(alpha)
		end
		current = alpha
	end
	apply(0)
	frame.Parent = props.Parent
	return frame, set, inner
end

--- Kurzer „Hüpfer“ über das (vorhandene oder neue) UIScale des Objekts.
function Components.Pop(guiObject: GuiObject, amount: number?, time: number?)
	local scale = guiObject:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = new("UIScale", { Parent = guiObject })
	end
	scale.Scale = amount or 1.15
	Components.Tween(scale, time or 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
end

--- Wandernder Glanzstreifen (läuft alle paar Sekunden über das Objekt).
function Components.Shine(target: GuiObject, props)
	props = props or {}
	local corner = target:FindFirstChildOfClass("UICorner")
	local shine = new("Frame", {
		Name = "Shine",
		BackgroundColor3 = Theme.Colors.White,
		BackgroundTransparency = props.Transparency or 0.55,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = target.ZIndex,
		Parent = target,
	})
	new("UICorner", { CornerRadius = props.CornerRadius and UDim.new(0, props.CornerRadius) or (if corner then corner.CornerRadius else UDim.new(0, Theme.SmallCorner)), Parent = shine })
	local gradient = new("UIGradient", {
		Rotation = 20,
		Offset = Vector2.new(-1.2, 0),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.42, 1),
			NumberSequenceKeypoint.new(0.5, 0.2),
			NumberSequenceKeypoint.new(0.58, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = shine,
	})
	-- Offset läuft weit über den sichtbaren Bereich hinaus -> kurzer Glanz, dann Pause
	local interval = props.Interval or 4.5
	local info = TweenInfo.new(interval, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1)
	TweenService:Create(gradient, info, { Offset = Vector2.new(1.2 + interval * 0.9, 0) }):Play()
	return shine
end

--- Fortschrittsbalken. Rückgabe: frame, setProgress(alpha, tweenTime?), fill
function Components.ProgressBar(props)
	local frame = new("Frame", {
		BackgroundColor3 = props.BackgroundColor or Theme.Colors.PanelDark,
		BackgroundTransparency = props.BackgroundTransparency or 0,
		BorderSizePixel = 0,
		Size = props.Size or UDim2.fromOffset(200, 10),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		Name = props.Name or "ProgressBar",
		Parent = props.Parent,
	})
	Components.Corner(props.CornerRadius or 6).Parent = frame
	local track = Components.Stroke(Theme.Colors.Black, 1, 0.55)
	track.Name = "Border"
	track.Parent = frame
	local fill = new("Frame", {
		Name = "Fill",
		BackgroundColor3 = props.Color or Theme.Colors.Accent,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Parent = frame,
	})
	Components.Corner(props.CornerRadius or 6).Parent = fill
	if props.Gradient then
		-- Waagrechter Farbverlauf (Füllfarbe wird dann über den Verlauf bestimmt)
		local pair = if type(props.Gradient) == "table" then props.Gradient else { Theme.GradientFor(props.Color or Theme.Colors.Accent) }
		fill.BackgroundColor3 = Theme.Colors.White
		Components.Gradient(pair, 0).Parent = fill
	else
		-- Glanz: oben hell, unten etwas dunkler (multipliziert mit der Füllfarbe)
		Components.Gradient({ Theme.Colors.White, Color3.fromRGB(255, 255, 255), Color3.fromRGB(178, 182, 200) }, 90).Parent = fill
	end
	local function set(alpha: number, tweenTime: number?)
		local target = UDim2.fromScale(math.clamp(alpha, 0, 1), 1)
		if tweenTime and tweenTime > 0 then
			Components.Tween(fill, tweenTime, { Size = target })
		else
			fill.Size = target
		end
	end
	return frame, set, fill
end

--- Schalter. Rückgabe: frame, setValue(boolean)
function Components.Toggle(props)
	local value = props.Value == true
	local frame = new("Frame", {
		BackgroundTransparency = 1,
		Size = props.Size or UDim2.new(1, 0, 0, 44),
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	})
	Components.Label({ Text = props.Text, Size = UDim2.new(1, -90, 1, 0), Font = Theme.Fonts.Medium, Parent = frame })
	local track = new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(64, 32),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BorderSizePixel = 0,
		Parent = frame,
	})
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = track })
	Components.Gradient({ Theme.Colors.White, Color3.fromRGB(190, 196, 220) }, 90).Parent = track
	local trackStroke = Components.Stroke(Theme.Colors.Stroke, 1.5, 0.2)
	trackStroke.Parent = track
	local knob = new("Frame", {
		Size = UDim2.fromOffset(26, 26),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 3, 0.5, 0),
		BackgroundColor3 = Theme.Colors.TextDim,
		BorderSizePixel = 0,
		Parent = track,
	})
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = knob })
	Components.Stroke(Theme.Colors.Shadow, 1.5, 0.6).Parent = knob
	local mark = Components.Label({
		Text = Theme.Icons.Check,
		Font = Theme.Fonts.Title,
		TextSize = 14,
		TextColor3 = Theme.Colors.Accent,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		RichText = false,
		Size = UDim2.fromScale(1, 1),
		TextTransparency = 1,
		Parent = knob,
	})
	local function render(animate: boolean)
		local time = if animate then 0.18 else 0
		Components.Tween(knob, time, {
			Position = if value then UDim2.new(1, -29, 0.5, 0) else UDim2.new(0, 3, 0.5, 0),
			BackgroundColor3 = if value then Theme.Colors.White else Theme.Colors.TextDim,
		}, Enum.EasingStyle.Back)
		Components.Tween(mark, time, { TextTransparency = if value then 0 else 1 })
		Components.Tween(track, time, { BackgroundColor3 = if value then Theme.Colors.Accent else Theme.Colors.PanelDark })
		trackStroke.Color = if value then Theme.Colors.Accent:Lerp(Theme.Colors.White, 0.3) else Theme.Colors.Stroke
	end
	track.Activated:Connect(function()
		value = not value
		render(true)
		if Components.ClickCallback then
			Components.ClickCallback()
		end
		if props.OnChanged then
			props.OnChanged(value)
		end
	end)
	render(false)
	return frame, function(newValue: boolean)
		value = newValue
		render(false)
	end
end

--- Schieberegler. Rückgabe: frame, setValue(number)
function Components.Slider(props)
	local min, max = props.Min or 0, props.Max or 1
	local value = props.Value or min
	local frame = new("Frame", {
		BackgroundTransparency = 1,
		Size = props.Size or UDim2.new(1, 0, 0, 54),
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	})
	local label = Components.Label({ Text = props.Text, Size = UDim2.new(1, 0, 0, 22), Font = Theme.Fonts.Medium, Parent = frame })
	local bar = new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		Position = UDim2.new(0, 0, 0, 30),
		Size = UDim2.new(1, -8, 0, 12),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BorderSizePixel = 0,
		Parent = frame,
	})
	Components.Corner(6).Parent = bar
	Components.Stroke(Theme.Colors.Black, 1, 0.55).Parent = bar
	local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Theme.Colors.White, BorderSizePixel = 0, Parent = bar })
	Components.Corner(6).Parent = fill
	Components.Gradient(Theme.Gradients.Accent, 0).Parent = fill
	local knob = new("Frame", {
		Size = UDim2.fromOffset(24, 24),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		BackgroundColor3 = Theme.Colors.White,
		BorderSizePixel = 0,
		Parent = bar,
	})
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = knob })
	Components.Stroke(Theme.Colors.Accent, 3, 0).Parent = knob

	local function render()
		local alpha = (value - min) / (max - min)
		fill.Size = UDim2.fromScale(alpha, 1)
		knob.Position = UDim2.fromScale(alpha, 0.5)
		label.Text = string.format("%s: <b>%s</b>", props.Text, if props.Format then props.Format(value) else string.format("%d%%", math.floor(alpha * 100 + 0.5)))
	end
	local dragging = false
	local function setFromX(x: number)
		local alpha = math.clamp((x - bar.AbsolutePosition.X) / math.max(1, bar.AbsoluteSize.X), 0, 1)
		local newValue = min + (max - min) * alpha
		if props.Step then
			newValue = math.floor(newValue / props.Step + 0.5) * props.Step
		end
		if newValue ~= value then
			value = newValue
			render()
			if props.OnChanged then
				props.OnChanged(value)
			end
		end
	end
	bar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	render()
	return frame, function(newValue: number)
		value = math.clamp(newValue, min, max)
		render()
	end
end

--- Tab-Leiste. onSelect(name). Rückgabe: frame, select(name)
function Components.Tabs(props)
	local frame = new("Frame", {
		BackgroundTransparency = 1,
		Size = props.Size or UDim2.new(1, 0, 0, 40),
		Position = props.Position or UDim2.new(),
		Parent = props.Parent,
	}, { Components.List(Enum.FillDirection.Horizontal, 6) })
	local buttons = {}
	local function selectTab(name: string)
		for tabName, button in buttons do
			local active = tabName == name
			Components.SetButtonColor(button, if active then Theme.Colors.Accent else Theme.Colors.PanelLight)
			button.TextColor3 = if active then Theme.Colors.White else Theme.Colors.TextDim
		end
		if props.OnSelect then
			props.OnSelect(name)
		end
	end
	for index, tab in props.Tabs do
		local button = Components.Button({
			Text = tab.Label,
			Size = UDim2.new(0, tab.Width or 130, 1, 0),
			TextSize = Theme.TextSize.Small,
			LayoutOrder = index,
			OnClick = function()
				selectTab(tab.Name)
			end,
		})
		button.Parent = frame
		buttons[tab.Name] = button
	end
	return frame, selectTab
end

--- Modales Fenster mit Kopfzeile, Titel und Schließen-Button.
--- Rückgabe-Objekt: { Root, Window, Content, Title, CloseButton, Open(), Close(), IsOpen(),
---                    OnOpen / OnClose (Callback-Felder) }
function Components.Modal(props)
	local modal = {}
	local accent = props.Accent or Theme.Colors.Accent
	local isOpen = false
	local token = 0
	local root = new("Frame", {
		Name = props.Name or "Modal",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Shadow,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 20,
		Parent = props.Parent,
	})
	-- Fängt Klicks hinter dem Fenster ab
	new("TextButton", {
		Name = "Blocker",
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 20,
		Parent = root,
	})
	local window = Components.Panel({
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = props.Size or UDim2.fromOffset(900, 560),
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.03,
		StrokeColor = accent:Lerp(Theme.Colors.Stroke, 0.45),
		StrokeThickness = 2,
		CornerRadius = Theme.Corner + 4,
		ZIndex = 22,
		Parent = root,
	})
	local shadow = Components.Shadow(window, { Offset = 10, Spread = 14, Strength = 1.2 })
	local scale = new("UIScale", { Parent = window })
	local shadowScale = new("UIScale", { Parent = shadow })

	-- Kopfzeile: weich auslaufender Akzent-Schimmer + Verlaufslinie
	local header = new("Frame", {
		Name = "Header",
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(1, -4, 0, 62),
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		ZIndex = 22,
		Parent = window,
	})
	Components.Corner(Theme.Corner + 2).Parent = header
	Components.Gradient(accent, 90, { 0.72, 1 }).Parent = header
	Components.Divider({
		Name = "HeaderLine",
		Position = UDim2.fromOffset(24, 60),
		Size = UDim2.new(1, -48, 0, 3),
		ZIndex = 22,
		Parent = window,
	})

	local titleX = 24
	if props.Icon then
		Components.Icon({ Glyph = props.Icon, Color = accent, Size = 38, Position = UDim2.fromOffset(20, 15), ZIndex = 23, Parent = window })
		titleX = 68
	end
	local title = Components.Heading({
		Text = props.Title or "",
		TextSize = Theme.TextSize.Title,
		Position = UDim2.fromOffset(titleX, 16),
		Size = UDim2.new(1, -76 - titleX, 0, 36),
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 23,
		Parent = window,
	})
	local close = Components.Button({
		Name = "Close",
		Text = Theme.Icons.Close,
		Size = UDim2.fromOffset(44, 44),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 12),
		Color = Theme.Colors.Danger,
		TextColor = Theme.Colors.White,
		TextSize = 22,
		CornerRadius = 22,
		ZIndex = 23,
		OnClick = function()
			modal.Close()
		end,
	})
	close.Parent = window
	local content = new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(24, 68),
		Size = UDim2.new(1, -48, 1, -88),
		ZIndex = 22,
		Parent = window,
	})

	modal.Root = root
	modal.Window = window
	modal.Content = content
	modal.Title = title
	modal.CloseButton = close
	function modal.IsOpen()
		return isOpen
	end
	function modal.Open()
		if isOpen then
			return
		end
		isOpen = true
		token += 1
		root.Visible = true
		root.BackgroundTransparency = 1
		scale.Scale = 0.86
		shadowScale.Scale = 0.86
		Components.Tween(root, 0.2, { BackgroundTransparency = 0.35 })
		Components.Tween(scale, 0.32, { Scale = 1 }, Enum.EasingStyle.Back)
		Components.Tween(shadowScale, 0.32, { Scale = 1 }, Enum.EasingStyle.Back)
		if modal.OnOpen then
			modal.OnOpen()
		end
	end
	function modal.Close()
		if not isOpen then
			return
		end
		isOpen = false
		token += 1
		local myToken = token
		Components.Tween(root, 0.14, { BackgroundTransparency = 1 })
		Components.Tween(scale, 0.14, { Scale = 0.9 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Components.Tween(shadowScale, 0.14, { Scale = 0.9 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.15, function()
			if token == myToken then
				root.Visible = false
			end
		end)
		if modal.OnClose then
			modal.OnClose()
		end
	end
	return modal
end

return Components
