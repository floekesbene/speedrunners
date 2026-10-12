--[[
	UIController  (ModuleScript)
	Pfad: StarterPlayer/StarterPlayerScripts/Client/UI/UIController

	Erstellt die komplette Benutzeroberfläche per Script (keine manuell
	angelegten GUI-Instanzen nötig) und verwaltet Screens und Modale.

	Struktur (zur Laufzeit in PlayerGui):
		VelocityRushUI (ScreenGui)
		└── Root (Frame, UIScale auf Referenz 1280×720)
		    ├── TopBar          Level, XP, Coins, Rang
		    ├── LobbyMenu       Hauptmenü / Lobby / Warteschlange / Training-Leiste
		    ├── RaceHud         Countdown, Timer, Platzierungen, Gefahr, Items, Cooldowns
		    ├── TouchControls   Mobile Buttons
		    ├── Notifications   Hinweise
		    └── Modale: Results, Shop/Inventar (Catalog), Stats, Leaderboard,
		                Settings, Practice

	API:
		:RegisterModal(name, modal)
		:OpenModal(name) / :CloseModals() / :AnyModalOpen()
		:Notify(text, kind)
		.Root, .Gui, .Ctx, .Screens
]]

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local Components = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local player = Players.LocalPlayer

local UIController = {}

local SCREEN_ORDER = {
	"Notifications",
	"TopBar",
	"LobbyMenu",
	"RaceHud",
	"TouchControls",
	"Results",
	"Catalog",
	"Stats",
	"Leaderboard",
	"Settings",
	"Practice",
}

function UIController:Init(ctx)
	self.Ctx = ctx
	self.Modals = {}
	self.Screens = {}

	local playerGui = player:WaitForChild("PlayerGui")
	self.Gui = Components.new("ScreenGui", {
		Name = "VelocityRushUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 5,
		Parent = playerGui,
	})
	self.Root = Components.new("Frame", {
		Name = "Root",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = self.Gui,
	})
	self.Scale = Components.new("UIScale", { Parent = self.Root })
	self:_rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		self:_rescale()
	end)

	Components.ClickCallback = function()
		local audio = ctx.AudioController
		if audio then
			audio:Play("Click")
		end
	end

	local screensFolder = script.Parent:WaitForChild("Screens")
	for _, name in SCREEN_ORDER do
		local module = require(screensFolder:WaitForChild(name))
		self.Screens[name] = module.new(self)
	end
end

function UIController:Start()
	for _, name in SCREEN_ORDER do
		local screen = self.Screens[name]
		if screen.Start then
			local ok, err = pcall(screen.Start, screen)
			if not ok then
				warn("[UIController] " .. name .. ":Start fehlgeschlagen: " .. tostring(err))
			end
		end
	end

	self.Ctx.InputController.ActionPressed:Connect(function(action)
		if action == "Menu" then
			if self:AnyModalOpen() then
				self:CloseModals()
			else
				self.Screens.LobbyMenu:ToggleCollapsed()
			end
		end
	end)

	-- Standard-Rucksack ausblenden und Reset-Button auf unseren Respawn umleiten
	task.spawn(function()
		local resetEvent = Instance.new("BindableEvent")
		resetEvent.Event:Connect(function()
			local Remotes = require(game:GetService("ReplicatedStorage").Shared.Remotes)
			Remotes.RequestRespawn:FireServer()
		end)
		for _ = 1, 20 do
			local ok = pcall(function()
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
				StarterGui:SetCore("ResetButtonCallback", resetEvent)
			end)
			if ok then
				break
			end
			task.wait(0.5)
		end
	end)
end

function UIController:_rescale()
	local viewport = workspace.CurrentCamera.ViewportSize
	local reference = Theme.ReferenceSize
	local scale = math.clamp(math.min(viewport.X / reference.X, viewport.Y / reference.Y), 0.45, 1.6)
	self.ScaleValue = scale
	self.Scale.Scale = scale
	self.Root.Size = UDim2.fromScale(1 / scale, 1 / scale)
end

--- Umrechnung Bildschirmpixel -> logische UI-Koordinaten.
function UIController:ToLogical(pixels: Vector2): Vector2
	return pixels / (self.ScaleValue or 1)
end

function UIController:RegisterModal(name: string, modal)
	self.Modals[name] = modal
end

function UIController:OpenModal(name: string)
	for otherName, modal in self.Modals do
		if otherName ~= name then
			modal.Close()
		end
	end
	local modal = self.Modals[name]
	if modal then
		modal.Open()
	end
end

function UIController:CloseModals()
	for _, modal in self.Modals do
		modal.Close()
	end
end

function UIController:AnyModalOpen(): boolean
	for _, modal in self.Modals do
		if modal.IsOpen() then
			return true
		end
	end
	return false
end

function UIController:Notify(text: string, kind: string?)
	local notifications = self.Screens.Notifications
	if notifications then
		notifications:Push(text, kind)
	end
end

return UIController
