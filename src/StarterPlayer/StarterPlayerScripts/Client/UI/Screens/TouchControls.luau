--[[
	TouchControls  (ModuleScript)
	Pfad: StarterPlayer/StarterPlayerScripts/Client/UI/Screens/TouchControls

	Virtuelle Steuerung für Smartphones und Tablets (Multi-Touch):
		links:  ◀  ▶   (Bewegung)
		rechts: SPRUNG (groß), HAKEN, SLIDE, ITEM – im Bogen um den Daumen
	Runde Verlaufs-Buttons mit Symbol + Beschriftung; beim Drücken werden
	sie kleiner und kräftiger. Die rechte Gruppe lässt den Item-Slot des
	RaceHud (rechts, y 410–520 auf Touch-Geräten) frei.
	Die Buttons speisen den zentralen InputController (SetVirtualAxis /
	SetVirtualButton). Abschaltbar in den Einstellungen.
]]

local UserInputService = game:GetService("UserInputService")

local UI = script.Parent.Parent
local Components = require(UI.Components)
local Theme = require(UI.Theme)

local new = Components.new

local IDLE_TRANSPARENCY = 0.35
local PRESSED_TRANSPARENCY = 0.05

local TouchControls = {}
TouchControls.__index = TouchControls

function TouchControls.new(ui)
	local self = setmetatable({}, TouchControls)
	self.UI = ui
	self.Active = {} -- [InputObject] = action
	self.AxisState = { Left = false, Right = false }
	self.Pressed = {} -- [action] = true, wenn optisch gedrückt
	self.Visuals = {} -- [action] = { Scale, Stroke, Glyph }

	local root = new("Frame", {
		Name = "TouchControls",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = ui.Root,
	})
	self.Root = root

	local function touchButton(action: string, glyph: string, caption: string?, size: number, position: UDim2, color: Color3)
		local top, bottom = Theme.GradientFor(color)
		local button = new("TextButton", {
			Name = action,
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Theme.Colors.White,
			BackgroundTransparency = IDLE_TRANSPARENCY,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = position,
			Size = UDim2.fromOffset(size, size),
			Parent = root,
		})
		new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = button })
		Components.Gradient({ top, bottom }, 90).Parent = button
		local stroke = Components.Stroke(Theme.Colors.White, 3, 0.45)
		stroke.Parent = button
		local scale = new("UIScale", { Parent = button })
		-- Innerer Glanzring
		local ring = new("Frame", {
			Name = "InnerRing",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -14, 1, -14),
			BackgroundTransparency = 1,
			Parent = button,
		})
		new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = ring })
		Components.Stroke(Theme.Colors.White, 1.5, 0.8).Parent = ring

		local glyphLabel = Components.Label({
			Name = "Glyph",
			Text = glyph,
			Font = Theme.Fonts.Title,
			TextSize = math.floor(size * (if caption then 0.34 else 0.42)),
			TextColor3 = Theme.Colors.White,
			TextStrokeTransparency = 0.45,
			TextStrokeColor3 = bottom:Lerp(Theme.Colors.Black, 0.6),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextWrapped = false,
			RichText = false,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, if caption then 0.42 else 0.5),
			Size = UDim2.fromScale(0.8, 0.5),
			Parent = button,
		})
		if caption then
			Components.Label({
				Name = "Caption",
				Text = caption,
				Font = Theme.Fonts.Title,
				TextSize = if size > 120 then 17 else 13,
				TextColor3 = Theme.Colors.White,
				TextStrokeTransparency = 0.4,
				TextStrokeColor3 = bottom:Lerp(Theme.Colors.Black, 0.6),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextWrapped = false,
				RichText = false,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0.66),
				Size = UDim2.new(1, -16, 0, 18),
				Parent = button,
			})
		end
		self.Visuals[action] = { Scale = scale, Stroke = stroke, Glyph = glyphLabel }

		button.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				self.Active[input] = action
				self:_apply()
			end
		end)
		return button
	end

	-- Positionen relativ zu den unteren Ecken (logische Referenzpixel)
	self.Buttons = {
		touchButton("Left", Theme.Icons.Left, nil, 120, UDim2.new(0, 110, 1, -130), Theme.Colors.PanelLight),
		touchButton("Right", Theme.Icons.Right, nil, 120, UDim2.new(0, 250, 1, -130), Theme.Colors.PanelLight),
		touchButton("Jump", Theme.Icons.Up, "SPRUNG", 150, UDim2.new(1, -130, 1, -130), Theme.Colors.Accent),
		touchButton("Grapple", Theme.Icons.Hook, "HAKEN", 110, UDim2.new(1, -295, 1, -105), Theme.Colors.Accent2),
		touchButton("Slide", Theme.Icons.Down, "SLIDE", 100, UDim2.new(1, -185, 1, -305), Theme.Colors.Purple),
		touchButton("Item", Theme.Icons.Star, "ITEM", 96, UDim2.new(1, -305, 1, -255), Theme.Colors.Gold),
	}
	return self
end

-- Optischer Zustand eines Buttons (nur bei Änderung tweenen)
function TouchControls:_setPressed(button: TextButton, pressed: boolean)
	local action = button.Name
	if (self.Pressed[action] == true) == pressed then
		return
	end
	self.Pressed[action] = pressed or nil
	local visual = self.Visuals[action]
	Components.Tween(button, 0.08, { BackgroundTransparency = if pressed then PRESSED_TRANSPARENCY else IDLE_TRANSPARENCY })
	if visual then
		Components.Tween(visual.Scale, if pressed then 0.07 else 0.2, { Scale = if pressed then 0.88 else 1 }, if pressed then Enum.EasingStyle.Quad else Enum.EasingStyle.Back)
		Components.Tween(visual.Stroke, 0.08, { Transparency = if pressed then 0 else 0.45 })
	end
end

function TouchControls:_apply()
	local input = self.UI.Ctx.InputController
	local held = {}
	for _, action in self.Active do
		held[action] = true
	end
	local axis = (if held.Right then 1 else 0) - (if held.Left then 1 else 0)
	input:SetVirtualAxis(axis)
	for _, action in { "Jump", "Grapple", "Slide", "Item" } do
		input:SetVirtualButton(action, held[action] == true)
	end
	for _, button in self.Buttons do
		self:_setPressed(button, held[button.Name] == true)
	end
end

function TouchControls:Start()
	UserInputService.InputEnded:Connect(function(input)
		if self.Active[input] then
			self.Active[input] = nil
			self:_apply()
		end
	end)
	local state = self.UI.Ctx.ClientState
	local function refresh()
		local enabled = UserInputService.TouchEnabled and state:GetSetting("TouchControls") ~= false
		local lobbyMenu = self.UI.Screens.LobbyMenu
		local menuOpen = lobbyMenu ~= nil and lobbyMenu:IsOpen()
		self.Root.Visible = enabled and not menuOpen and not self.UI:AnyModalOpen()
		if not self.Root.Visible and next(self.Active) then
			table.clear(self.Active)
			self:_apply()
		end
	end
	state.SettingsChanged:Connect(refresh)
	game:GetService("RunService").Heartbeat:Connect(refresh)
	refresh()
end

return TouchControls
