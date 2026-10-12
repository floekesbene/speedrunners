--[[
	InputController  (ModuleScript)
	Pfad: StarterPlayer/StarterPlayerScripts/Client/Controllers/InputController

	Zentrale Verwaltung ALLER Eingaben (Tastatur, Maus, Gamepad, Touch).
	Andere Module fragen nur abstrakte Aktionen ab:

		Left/Right (Achse), Jump, Grapple, Slide, Item, Emote, Respawn, Menu

	Belegung:
		PC:       A/D oder ←/→ bewegen · Leertaste/W/↑ springen
		          E / J / linke Maustaste Greifhaken (halten)
		          Shift / S / ↓ / K Slide (Boden, halten) bzw. Air-Dash (Luft)
		          Q / F / L Power-up · G Emote · R Respawn · M Menü
		Gamepad:  Linker Stick / D-Pad bewegen · A springen · X oder R2 Haken
		          B oder L2 Slide/Dash · Y oder R1 Power-up · L1 Emote · Select Menü
		Touch:    Virtuelle Buttons (UI/Screens/TouchControls)

	API:
		:GetMoveX() -> number (-1..1)
		:IsHeld(action) -> boolean
		:Consume(action) -> boolean     (Druck seit max. 0,25 s, wird verbraucht)
		:SetVirtualAxis(x)              (Touch)
		:SetVirtualButton(action, down) (Touch)
		:GetDevice() -> "Keyboard" | "Gamepad" | "Touch"
		.ActionPressed / .ActionReleased (Signal: action)
		.DeviceChanged (Signal: device)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Signal)
local Config = require(Shared.Config)

local InputController = {}
InputController.ActionPressed = Signal.new()
InputController.ActionReleased = Signal.new()
InputController.DeviceChanged = Signal.new()

local K = Enum.KeyCode

local KEYMAP = {
	[K.A] = "Left",
	[K.Left] = "Left",
	[K.D] = "Right",
	[K.Right] = "Right",
	[K.Space] = "Jump",
	[K.W] = "Jump",
	[K.Up] = "Jump",
	[K.E] = "Grapple",
	[K.J] = "Grapple",
	[K.LeftShift] = "Slide",
	[K.S] = "Slide",
	[K.Down] = "Slide",
	[K.K] = "Slide",
	[K.Q] = "Item",
	[K.F] = "Item",
	[K.L] = "Item",
	[K.G] = "Emote",
	[K.R] = "Respawn",
	[K.M] = "Menu",
	-- Gamepad
	[K.ButtonA] = "Jump",
	[K.ButtonX] = "Grapple",
	[K.ButtonR2] = "Grapple",
	[K.ButtonB] = "Slide",
	[K.ButtonL2] = "Slide",
	[K.ButtonY] = "Item",
	[K.ButtonR1] = "Item",
	[K.ButtonL1] = "Emote",
	[K.DPadLeft] = "Left",
	[K.DPadRight] = "Right",
	[K.ButtonSelect] = "Menu",
}

local PRESS_WINDOW = 0.25

function InputController:Init(ctx)
	self.Ctx = ctx
	self.Held = {} -- [action] = { [source] = true }
	self.Pressed = {} -- [action] = os.clock()
	self.Virtual = {}
	self.VirtualAxis = 0
	self.StickX = 0
	self.Device = "Keyboard"
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		self.Device = "Touch"
	end
end

function InputController:_press(action: string, source: any)
	local held = self.Held[action]
	if not held then
		held = {}
		self.Held[action] = held
	end
	local wasHeld = next(held) ~= nil or self.Virtual[action] == true
	held[source] = true
	if not wasHeld then
		self.Pressed[action] = os.clock()
		self.ActionPressed:Fire(action)
	end
end

function InputController:_release(action: string, source: any)
	local held = self.Held[action]
	if not held or not held[source] then
		return
	end
	held[source] = nil
	if next(held) == nil and not self.Virtual[action] then
		self.ActionReleased:Fire(action)
	end
end

function InputController:_setDevice(device: string)
	if self.Device ~= device then
		self.Device = device
		self.DeviceChanged:Fire(device)
	end
end

function InputController:Start()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		local action = KEYMAP[input.KeyCode]
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			action = "Grapple"
		end
		if action then
			self:_press(action, input.KeyCode.Name .. input.UserInputType.Name)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		local action = KEYMAP[input.KeyCode]
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			action = "Grapple"
		end
		if action then
			self:_release(action, input.KeyCode.Name .. input.UserInputType.Name)
		end
		if input.KeyCode == K.Thumbstick1 then
			self.StickX = 0
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if input.KeyCode == K.Thumbstick1 then
			self.StickX = input.Position.X
		end
	end)

	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		local name = inputType.Name
		if name:find("Gamepad") then
			self:_setDevice("Gamepad")
		elseif inputType == Enum.UserInputType.Touch then
			self:_setDevice("Touch")
		elseif name:find("Mouse") or inputType == Enum.UserInputType.Keyboard then
			self:_setDevice("Keyboard")
		end
	end)

	-- Fenster verliert den Fokus: alle Tasten loslassen
	UserInputService.WindowFocusReleased:Connect(function()
		for action, held in self.Held do
			for source in held do
				self:_release(action, source)
			end
		end
		self.StickX = 0
	end)
end

function InputController:GetDevice(): string
	return self.Device
end

function InputController:IsHeld(action: string): boolean
	local held = self.Held[action]
	return (held ~= nil and next(held) ~= nil) or self.Virtual[action] == true
end

function InputController:Consume(action: string): boolean
	local pressed = self.Pressed[action]
	if pressed and os.clock() - pressed <= PRESS_WINDOW then
		self.Pressed[action] = nil
		return true
	end
	return false
end

function InputController:GetMoveX(): number
	local keyboard = (if self:IsHeld("Right") then 1 else 0) - (if self:IsHeld("Left") then 1 else 0)
	local deadzone = Config.Input.GamepadDeadzone
	local stick = 0
	if math.abs(self.StickX) > deadzone then
		local sensitivity = Config.Input.DefaultGamepadSensitivity
		local state = self.Ctx and self.Ctx.ClientState
		if state then
			sensitivity = state:GetSetting("GamepadSensitivity") or sensitivity
		end
		local magnitude = (math.abs(self.StickX) - deadzone) / (1 - deadzone)
		stick = math.sign(self.StickX) * math.clamp(magnitude * sensitivity, 0, 1)
	end
	local best = keyboard
	if math.abs(stick) > math.abs(best) then
		best = stick
	end
	if math.abs(self.VirtualAxis) > math.abs(best) then
		best = self.VirtualAxis
	end
	return best
end

function InputController:SetVirtualAxis(x: number)
	self.VirtualAxis = math.clamp(x, -1, 1)
end

function InputController:SetVirtualButton(action: string, down: boolean)
	local wasHeld = self:IsHeld(action)
	self.Virtual[action] = down or nil
	if down and not wasHeld then
		self.Pressed[action] = os.clock()
		self.ActionPressed:Fire(action)
	elseif not down and wasHeld and not self:IsHeld(action) then
		self.ActionReleased:Fire(action)
	end
end

-- Lokaler Spieler wird für zukünftige Erweiterungen bereitgehalten
InputController.Player = Players.LocalPlayer

return InputController
