--[[
	Install  (ModuleScript) – nur in der Import-Datei VelocityRush_Import.rbxm enthalten

	Verteilt alle Teile von Velocity Rush in die richtigen Roblox-Services und
	setzt die nötigen Einstellungen. Ausführen in Roblox Studio über die
	Befehlsleiste (Ansicht → Befehlsleiste):

		require(workspace.VelocityRush_Import.Install)()

	Danach kann das Modell gelöscht werden (geschieht automatisch).
]]

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")
local StarterPlayer = game:GetService("StarterPlayer")

return function()
	local root = script.Parent
	local hinweise = {}

	pcall(function()
		ChangeHistoryService:SetWaypoint("Vor Velocity Rush Installation")
	end)

	local function move(folderName: string, target: Instance)
		local folder = root:FindFirstChild(folderName)
		if not folder then
			return
		end
		for _, child in folder:GetChildren() do
			local existing = target:FindFirstChild(child.Name)
			if existing then
				existing:Destroy()
				table.insert(hinweise, string.format("Vorhandenes %s.%s wurde ersetzt.", target.Name, child.Name))
			end
			child.Parent = target
		end
	end

	move("ReplicatedStorage", ReplicatedStorage)
	move("ServerScriptService", ServerScriptService)
	move("ServerStorage", ServerStorage)
	move("StarterPlayerScripts", StarterPlayer:FindFirstChildOfClass("StarterPlayerScripts"))
	move("StarterCharacterScripts", StarterPlayer:FindFirstChildOfClass("StarterCharacterScripts"))

	-- Server-Einstiegspunkt erst jetzt aktivieren (war im Import-Modell deaktiviert)
	local bootstrap = ServerScriptService:FindFirstChild("Server") and ServerScriptService.Server:FindFirstChild("Bootstrap")
	if bootstrap then
		bootstrap.Disabled = false
	end

	-- Einstellungen
	Players.CharacterAutoLoads = false
	StarterPlayer.LoadCharacterAppearance = false
	StarterPlayer.EnableMouseLockOption = false
	StarterGui.ResetPlayerGuiOnSpawn = false
	workspace.Gravity = 200
	pcall(function()
		Lighting.Technology = Enum.Technology.Future
	end)
	local streamingOk = pcall(function()
		workspace.StreamingEnabled = false
	end)
	if not streamingOk then
		table.insert(hinweise, "Bitte im Explorer 'Workspace' auswählen und im Eigenschaften-Fenster 'StreamingEnabled' ausschalten.")
	end

	-- Standard-Baseplate und SpawnLocation stören die Strecken (die Rennstrecke liegt am Ursprung)
	for _, name in { "Baseplate", "SpawnLocation" } do
		local object = workspace:FindFirstChild(name)
		if object then
			object:Destroy()
			table.insert(hinweise, "Workspace." .. name .. " wurde entfernt (liegt im Bereich der Rennstrecke).")
		end
	end

	pcall(function()
		ChangeHistoryService:SetWaypoint("Velocity Rush installiert")
	end)
	root:Destroy()

	print("======================================================")
	print(" Velocity Rush wurde installiert!")
	print(" Jetzt oben auf 'Play' drücken (allein testen) oder")
	print(" Test -> Clients und Server -> 2-3 Spieler -> Start.")
	for _, hinweis in hinweise do
		print(" Hinweis: " .. hinweis)
	end
	print("======================================================")
end
