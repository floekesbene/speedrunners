--[[
	TouchControls  (ModuleScript)
	Pfad: StarterPlayer/StarterPlayerScripts/Client/UI/Screens/TouchControls

	Virtuelle Steuerung für Smartphones und Tablets (Multi-Touch):
		links:  ◀  ▶   (Bewegung)
		rechts: SPRUNG (groß), HAKEN, SLIDE, ITEM
	Die Buttons speisen den zentralen InputController (SetVirtualAxis /
	SetVirtualButton). Abschaltbar in den Einstellungen.
]]

local UserInputService = game:GetService("UserInputService")

local UI = script.Parent.Parent
local Components = require(UI.Components)
local Theme = require(UI.Theme)

local new = Components.new

local TouchControls = {}
TouchControls.__index = TouchControls

function TouchControls.new(ui)
	local self = setmetatable({}, TouchControls)
	self.UI = ui
	self.Active = {} -- [InputObject] = action
	self.AxisState = { Left = false, Right = false }

	local root = new("Frame", {
		Name = "TouchControls",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = ui.Root,
	})
	self.Root = root

	local function touchButton(action: string, text: string, size: number, position: UDim2, color: Color3)
		local button = new("TextButton", {
			Name = action,
			Text = text,
			Font = Theme.Fonts.Title,
			TextSize = if size > 120 then 22 else 16,
			TextColor3 = Theme.Colors.White,
			AutoButtonColor = false,
			BackgroundColor3 = color,
			BackgroundTransparency = 0.45,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = position,
			Size = UDim2.fromOffset(size, size),
			Parent = root,
		})
		Components.Corner(size // 2).Parent = button
		Components.Stroke(Theme.Colors.White, 2, 0.5).Parent = button
		button.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				self.Active[input] = action
				button.BackgroundTransparency = 0.15
				self:_apply()
			end
		end)
		return button
	end

	self.Buttons = {
		touchButton("Left", "◀", 120, UDim2.new(0, 110, 1, -130), Theme.Colors.PanelLight),
		touchButton("Right", "▶", 120, UDim2.new(0, 250, 1, -130), Theme.Colors.PanelLight),
		touchButton("Jump", "SPRUNG", 150, UDim2.new(1, -130, 1, -130), Theme.Colors.Accent),
		touchButton("Grapple", "HAKEN", 110, UDim2.new(1, -290, 1, -110), Theme.Colors.Accent2),
		touchButton("Slide", "SLIDE", 100, UDim2.new(1, -120, 1, -300), Theme.Colors.PanelLight),
		touchButton("Item", "ITEM", 96, UDim2.new(1, -270, 1, -260), Theme.Colors.Gold),
	}
	return self
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
		button.BackgroundTransparency = if held[button.Name] then 0.15 else 0.45
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
