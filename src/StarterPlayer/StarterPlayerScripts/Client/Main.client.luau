--[[
	Main  (LocalScript)
	Pfad: StarterPlayer/StarterPlayerScripts/Client/Main

	Einstiegspunkt des Clients. Lädt alle Controller und die UI, ruft
	:Init(ctx) und danach :Start() auf. Deaktiviert die Roblox-Standard-
	steuerung, da Velocity Rush eine eigene Bewegungslogik nutzt.
]]

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local controllers = script.Parent:WaitForChild("Controllers")
local ui = script.Parent:WaitForChild("UI")

-- Standardsteuerung (WASD/Thumbstick/Sprungbutton) abschalten
task.spawn(function()
	local ok, playerModule = pcall(function()
		return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 20))
	end)
	if ok and playerModule then
		local controls = playerModule:GetControls()
		if controls then
			controls:Disable()
		end
	end
end)

local ORDER = {
	"ClientState",
	"InputController",
	"MovementController",
	"CameraController",
	"AnimationController",
	"EffectsController",
	"AudioController",
}

local ctx = {}
for _, name in ORDER do
	ctx[name] = require(controllers:WaitForChild(name))
end
ctx.UIController = require(ui:WaitForChild("UIController"))

for _, name in ORDER do
	ctx[name]:Init(ctx)
end
ctx.UIController:Init(ctx)

for _, name in ORDER do
	if ctx[name].Start then
		ctx[name]:Start()
	end
end
ctx.UIController:Start()
