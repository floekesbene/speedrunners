--[[
	Components  (ModuleScript)
	Pfad: StarterPlayer/StarterPlayerScripts/Client/UI/Components

	Wiederverwendbare UI-Bausteine im einheitlichen Stil (siehe Theme):
		new(className, props, children)  generischer Instanz-Builder
		Corner, Stroke, Padding, List, Grid
		Label, Button, Panel, ProgressBar, Toggle, Slider, Tabs, Modal
		Tween(instance, time, props)
]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)

local Components = {}

-- Wird vom UIController gesetzt, um Klick-Sounds abzuspielen.
Components.ClickCallback = nil

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
		if key ~= "MaxTextSize" then
			label[key] = value
		end
	end
	if props.TextScaled and props.MaxTextSize then
		new("UITextSizeConstraint", { MaxTextSize = props.MaxTextSize, Parent = label })
	end
	return label
end

--- Panel (Frame mit Ecken und Rand).
function Components.Panel(props)
	local frame = new("Frame", {
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
	})
	for key, value in props do
		if key ~= "NoStroke" and key ~= "StrokeColor" and key ~= "CornerRadius" then
			frame[key] = value
		end
	end
	Components.Corner(props.CornerRadius).Parent = frame
	if not props.NoStroke then
		Components.Stroke(props.StrokeColor).Parent = frame
	end
	return frame
end

--- Button mit Hover-/Klick-Animation. props.OnClick, props.Color, props.TextColor, props.Icon
function Components.Button(props)
	local color = props.Color or Theme.Colors.PanelLight
	local button = new("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Font = props.Font or Theme.Fonts.Bold,
		Text = props.Text or "",
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
	})
	if props.TextScaled then
		button.TextScaled = true
		new("UITextSizeConstraint", { MaxTextSize = props.TextSize or Theme.TextSize.Body, Parent = button })
		Components.Padding(4, 10).Parent = button
	end
	Components.Corner(props.CornerRadius or Theme.SmallCorner).Parent = button
	local stroke = Components.Stroke(props.StrokeColor or Theme.Colors.Stroke, 1.5, if props.NoStroke then 1 else 0)
	stroke.Parent = button
	local scale = new("UIScale", { Parent = button })

	local base = color
	button:SetAttribute("BaseColor", base)
	local function baseColor()
		return button:GetAttribute("BaseColor") or base
	end
	button.MouseEnter:Connect(function()
		local c = baseColor()
		Components.Tween(button, 0.12, { BackgroundColor3 = c:Lerp(Color3.new(1, 1, 1), 0.12) })
		Components.Tween(scale, 0.12, { Scale = 1.03 })
	end)
	button.MouseLeave:Connect(function()
		Components.Tween(button, 0.12, { BackgroundColor3 = baseColor() })
		Components.Tween(scale, 0.12, { Scale = 1 })
	end)
	button.MouseButton1Down:Connect(function()
		Components.Tween(scale, 0.06, { Scale = 0.96 })
	end)
	button.MouseButton1Up:Connect(function()
		Components.Tween(scale, 0.1, { Scale = 1 })
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

--- Ändert die Grundfarbe eines Buttons (inkl. Hover-Basis).
function Components.SetButtonColor(button: TextButton, color: Color3)
	button:SetAttribute("BaseColor", color)
	button.BackgroundColor3 = color
end

--- Fortschrittsbalken. Rückgabe: frame, setProgress(alpha, tweenTime?)
function Components.ProgressBar(props)
	local frame = new("Frame", {
		BackgroundColor3 = props.BackgroundColor or Theme.Colors.PanelDark,
		BorderSizePixel = 0,
		Size = props.Size or UDim2.fromOffset(200, 10),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		Name = props.Name or "ProgressBar",
		Parent = props.Parent,
	})
	Components.Corner(props.CornerRadius or 6).Parent = frame
	local fill = new("Frame", {
		Name = "Fill",
		BackgroundColor3 = props.Color or Theme.Colors.Accent,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Parent = frame,
	})
	Components.Corner(props.CornerRadius or 6).Parent = fill
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
		Size = UDim2.fromOffset(64, 30),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BorderSizePixel = 0,
		Parent = frame,
	})
	Components.Corner(15).Parent = track
	Components.Stroke().Parent = track
	local knob = new("Frame", {
		Size = UDim2.fromOffset(24, 24),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 3, 0.5, 0),
		BackgroundColor3 = Theme.Colors.TextDim,
		BorderSizePixel = 0,
		Parent = track,
	})
	Components.Corner(12).Parent = knob
	local function render(animate: boolean)
		local time = if animate then 0.15 else 0
		Components.Tween(knob, time, {
			Position = if value then UDim2.new(1, -27, 0.5, 0) else UDim2.new(0, 3, 0.5, 0),
			BackgroundColor3 = if value then Theme.Colors.White else Theme.Colors.TextDim,
		})
		Components.Tween(track, time, { BackgroundColor3 = if value then Theme.Colors.Accent else Theme.Colors.PanelDark })
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
	local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Theme.Colors.Accent, BorderSizePixel = 0, Parent = bar })
	Components.Corner(6).Parent = fill
	local knob = new("Frame", {
		Size = UDim2.fromOffset(22, 22),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		BackgroundColor3 = Theme.Colors.White,
		BorderSizePixel = 0,
		Parent = bar,
	})
	Components.Corner(11).Parent = knob

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
	local function select(name: string)
		for tabName, button in buttons do
			local active = tabName == name
			Components.SetButtonColor(button, if active then Theme.Colors.Accent else Theme.Colors.PanelLight)
			button.TextColor3 = if active then Theme.Colors.Background else Theme.Colors.Text
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
				select(tab.Name)
			end,
		})
		button.Parent = frame
		buttons[tab.Name] = button
	end
	return frame, select
end

--- Modales Fenster mit Titel und Schließen-Button.
--- Rückgabe-Objekt: { Root, Window, Content, Title, Open(), Close(), IsOpen(), OnClose (Callback-Feld) }
function Components.Modal(props)
	local modal = {}
	local root = new("Frame", {
		Name = props.Name or "Modal",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Black,
		BackgroundTransparency = 0.45,
		Visible = false,
		ZIndex = 20,
		Parent = props.Parent,
	})
	-- Fängt Klicks hinter dem Fenster ab
	new("TextButton", {
		Text = "",
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
		ZIndex = 21,
		Parent = root,
	})
	local scale = new("UIScale", { Parent = window })
	local title = Components.Label({
		Text = props.Title or "",
		Font = Theme.Fonts.Title,
		TextSize = Theme.TextSize.Title,
		Position = UDim2.fromOffset(24, 16),
		Size = UDim2.new(1, -100, 0, 36),
		ZIndex = 22,
		Parent = window,
	})
	local close = Components.Button({
		Text = "✕",
		Size = UDim2.fromOffset(44, 44),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 12),
		Color = Theme.Colors.PanelLight,
		TextSize = 20,
		ZIndex = 22,
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
		ZIndex = 21,
		Parent = window,
	})

	modal.Root = root
	modal.Window = window
	modal.Content = content
	modal.Title = title
	modal.CloseButton = close
	function modal.IsOpen()
		return root.Visible
	end
	function modal.Open()
		if root.Visible then
			return
		end
		root.Visible = true
		scale.Scale = 0.9
		window.BackgroundTransparency = 0.3
		Components.Tween(scale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
		Components.Tween(window, 0.18, { BackgroundTransparency = 0.05 })
		if modal.OnOpen then
			modal.OnOpen()
		end
	end
	function modal.Close()
		if not root.Visible then
			return
		end
		root.Visible = false
		if modal.OnClose then
			modal.OnClose()
		end
	end
	return modal
end

return Components
