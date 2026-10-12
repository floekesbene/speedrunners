--[[
	LobbyMenu  (ModuleScript)
	Pfad: StarterPlayer/StarterPlayerScripts/Client/UI/Screens/LobbyMenu

	Hauptmenü in der Lobby (links) und Status-Karte (unten mittig):
		- Schnelles Spiel / Ranked beitreten bzw. verlassen
		- Training, Shop, Inventar, Statistik, Bestenliste, Einstellungen
		- Warteschlangenstatus mit Countdown und nächster Map
		- laufendes Rennen anzeigen + Zuschauen
		- Trainingsleiste (Checkpoint, Verlassen)
	Mit M (Gamepad: Select) einklappbar.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local MapDefinitions = require(Shared.MapDefinitions)

local UI = script.Parent.Parent
local Components = require(UI.Components)
local Theme = require(UI.Theme)

local player = Players.LocalPlayer

local LobbyMenu = {}
LobbyMenu.__index = LobbyMenu

local function mapName(id: string?): string
	local definition = id and MapDefinitions.GetAny(id)
	return if definition then definition.Name else "—"
end

function LobbyMenu.new(ui)
	local self = setmetatable({}, LobbyMenu)
	self.UI = ui
	self.Collapsed = false

	local menu = Components.new("Frame", {
		Name = "LobbyMenu",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 160),
		Size = UDim2.fromOffset(260, 520),
		Parent = ui.Root,
	}, { Components.List(Enum.FillDirection.Vertical, 8) })
	self.Menu = menu

	local function menuButton(order: number, text: string, color: Color3?, textColor: Color3?, onClick)
		local button = Components.Button({
			Text = text,
			Size = UDim2.fromOffset(260, if order <= 2 then 58 else 46),
			Color = color or Theme.Colors.PanelLight,
			TextColor = textColor,
			TextSize = if order <= 2 then Theme.TextSize.Large else Theme.TextSize.Body,
			Font = if order <= 2 then Theme.Fonts.Title else Theme.Fonts.Bold,
			LayoutOrder = order,
			OnClick = onClick,
		})
		button.Parent = menu
		return button
	end

	self.QuickButton = menuButton(1, "SCHNELLES SPIEL", Theme.Colors.Accent, Theme.Colors.Background, function()
		self:_toggleQueue("QuickPlay")
	end)
	self.RankedButton = menuButton(2, "RANKED", Theme.Colors.Gold, Theme.Colors.Background, function()
		self:_toggleQueue("Ranked")
	end)
	menuButton(3, "TRAINING", nil, nil, function()
		ui:OpenModal("Practice")
	end)
	menuButton(4, "SHOP", nil, nil, function()
		ui.Screens.Catalog:Open("Shop")
	end)
	menuButton(5, "INVENTAR", nil, nil, function()
		ui.Screens.Catalog:Open("Inventory")
	end)
	menuButton(6, "STATISTIK & AUFGABEN", nil, nil, function()
		ui:OpenModal("Stats")
	end)
	menuButton(7, "BESTENLISTE", nil, nil, function()
		ui:OpenModal("Leaderboard")
	end)
	menuButton(8, "EINSTELLUNGEN", nil, nil, function()
		ui:OpenModal("Settings")
	end)
	Components.Label({
		Text = "M: Menü ein/aus · G: Emote",
		TextSize = Theme.TextSize.Tiny,
		Font = Theme.Fonts.Medium,
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.fromOffset(260, 18),
		LayoutOrder = 9,
		Parent = menu,
	})

	-- Menü-Schalter (wichtig für Touch-Geräte ohne M-Taste)
	self.ToggleButton = Components.Button({
		Text = "MENÜ",
		Position = UDim2.fromOffset(466, 74),
		Size = UDim2.fromOffset(100, 46),
		OnClick = function()
			self:ToggleCollapsed()
		end,
	})
	self.ToggleButton.Parent = ui.Root

	-- Status-Karte
	local card = Components.Panel({
		Name = "StatusCard",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -22),
		Size = UDim2.fromOffset(560, 104),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.1,
		Parent = ui.Root,
	})
	self.Card = card
	self.CardTitle = Components.Label({
		Text = "",
		Font = Theme.Fonts.Title,
		TextSize = Theme.TextSize.Large,
		Position = UDim2.fromOffset(18, 12),
		Size = UDim2.new(1, -200, 0, 28),
		TextColor3 = Theme.Colors.Accent,
		Parent = card,
	})
	self.CardLine1 = Components.Label({
		Text = "",
		Font = Theme.Fonts.Medium,
		TextSize = Theme.TextSize.Body,
		Position = UDim2.fromOffset(18, 44),
		Size = UDim2.new(1, -200, 0, 22),
		Parent = card,
	})
	self.CardLine2 = Components.Label({
		Text = "",
		Font = Theme.Fonts.Medium,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Colors.TextDim,
		Position = UDim2.fromOffset(18, 70),
		Size = UDim2.new(1, -200, 0, 20),
		Parent = card,
	})
	self.CardButton = Components.Button({
		Text = "",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(164, 54),
		Color = Theme.Colors.Accent,
		TextColor = Theme.Colors.Background,
		Font = Theme.Fonts.Title,
		OnClick = function()
			if self.CardAction then
				self.CardAction()
			end
		end,
	})
	self.CardButton.Parent = card
	self.CardButton2 = Components.Button({
		Text = "",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 10),
		Size = UDim2.fromOffset(164, 38),
		Visible = false,
		OnClick = function()
			if self.CardAction2 then
				self.CardAction2()
			end
		end,
	})
	self.CardButton2.Parent = card
	return self
end

function LobbyMenu:Start()
	-- Auf reinen Touch-Geräten startet das Menü eingeklappt (Platz für die Steuerung)
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		self:ToggleCollapsed()
	end
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.15 then
			accumulator = 0
			self:_refresh()
		end
	end)
	self:_refresh()
end

--- True, wenn das Menü gerade sichtbar und ausgeklappt ist.
function LobbyMenu:IsOpen(): boolean
	return self.Menu.Visible and not self.Collapsed
end

function LobbyMenu:ToggleCollapsed()
	self.Collapsed = not self.Collapsed
	self.ToggleButton.Text = if self.Collapsed then "MENÜ" else "SCHLIESSEN"
	Components.Tween(self.Menu, 0.25, {
		Position = if self.Collapsed then UDim2.fromOffset(-300, 160) else UDim2.fromOffset(16, 160),
	})
end

function LobbyMenu:_toggleQueue(mode: string)
	local queued = player:GetAttribute("Queue") or ""
	if queued == mode then
		Remotes.QueueRequest:FireServer("Leave", mode)
	else
		Remotes.QueueRequest:FireServer("Join", mode)
	end
end

function LobbyMenu:_setCard(title: string, line1: string, line2: string, buttonText: string?, action, color: Color3?)
	self.CardTitle.Text = title
	self.CardLine1.Text = line1
	self.CardLine2.Text = line2
	self.CardButton.Visible = buttonText ~= nil
	self.CardButton.Text = buttonText or ""
	Components.SetButtonColor(self.CardButton, color or Theme.Colors.Accent)
	self.CardAction = action
end

function LobbyMenu:_setSecond(text: string?, action)
	self.CardButton2.Visible = text ~= nil
	self.CardButton2.Text = text or ""
	self.CardAction2 = action
	if text then
		self.CardButton.Position = UDim2.new(1, -16, 1, -10)
		self.CardButton.AnchorPoint = Vector2.new(1, 1)
		self.CardButton.Size = UDim2.fromOffset(164, 40)
	else
		self.CardButton.Position = UDim2.new(1, -16, 0.5, 0)
		self.CardButton.AnchorPoint = Vector2.new(1, 0.5)
		self.CardButton.Size = UDim2.fromOffset(164, 54)
	end
end

function LobbyMenu:_refresh()
	local ctx = self.UI.Ctx
	local state = ctx.ClientState
	local gameState = state.GameState
	local spectating = ctx.CameraController:GetSpectate() ~= nil
	local inRace = state:IsInRace()
	local visible = not inRace and not spectating
	self.Menu.Visible = visible
	self.Card.Visible = visible
	self.ToggleButton.Visible = visible
	if not visible then
		return
	end

	local queue = player:GetAttribute("Queue") or ""
	local course = state:GetPracticeCourse()
	local phase = gameState:GetAttribute("Phase") or "Waiting"
	local nextMap = mapName(gameState:GetAttribute("NextMapId"))
	local minPlayers = gameState:GetAttribute("MinPlayers") or 2
	local maxPlayers = gameState:GetAttribute("MaxPlayers") or 8

	self.QuickButton.Text = if queue == "QuickPlay" then "QUEUE VERLASSEN" else "SCHNELLES SPIEL"
	self.RankedButton.Text = if queue == "Ranked" then "RANKED VERLASSEN" else "RANKED"

	self:_setSecond(nil)
	if course ~= "" then
		local queueInfo = if queue ~= "" then "  ·  In Warteschlange" else ""
		self:_setCard(
			"TRAINING: " .. string.upper(mapName(course)),
			"Keine Wertung, keine Belohnungen – übe in Ruhe." .. queueInfo,
			"R = zum Checkpoint  ·  Das Rennen holt dich automatisch ab.",
			"VERLASSEN",
			function()
				Remotes.PracticeRequest:FireServer("Leave")
			end,
			Theme.Colors.Danger
		)
		self:_setSecond("CHECKPOINT", function()
			Remotes.PracticeRequest:FireServer("Reset")
		end)
	elseif queue ~= "" then
		local count = gameState:GetAttribute(if queue == "Ranked" then "QueueRanked" else "QueueQuickPlay") or 0
		local modeName = if queue == "Ranked" then "RANKED" else "SCHNELLES SPIEL"
		local line2 = "Nächste Map: " .. nextMap
		if phase == "Starting" and gameState:GetAttribute("Mode") == queue then
			local remaining = math.max(0, math.ceil((gameState:GetAttribute("PhaseEndsAt") or 0) - workspace:GetServerTimeNow()))
			line2 = string.format("Rennen startet in %d s  ·  Map: %s", remaining, nextMap)
		elseif phase ~= "Waiting" and phase ~= "Starting" then
			line2 = "Ein Rennen läuft – du bist in der nächsten Runde dabei."
		end
		self:_setCard(
			"WARTESCHLANGE · " .. modeName,
			string.format("%d / %d Spieler (mindestens %d)", count, maxPlayers, minPlayers),
			line2,
			"VERLASSEN",
			function()
				Remotes.QueueRequest:FireServer("Leave", queue)
			end,
			Theme.Colors.Danger
		)
	elseif (phase == "Countdown" or phase == "Racing" or phase == "Loading") and (gameState:GetAttribute("MapId") or "") ~= "" then
		self:_setCard(
			"RENNEN LÄUFT · " .. string.upper(mapName(gameState:GetAttribute("MapId"))),
			string.format("%d von %d Spielern noch im Rennen", gameState:GetAttribute("Alive") or 0, gameState:GetAttribute("Participants") or 0),
			"Stell dich an, um in der nächsten Runde dabei zu sein.",
			"ZUSCHAUEN",
			function()
				self.UI.Screens.RaceHud:StartSpectating()
			end
		)
		self:_setSecond("ANSTELLEN", function()
			Remotes.QueueRequest:FireServer("Join", "QuickPlay")
		end)
	else
		self:_setCard(
			"BEREIT FÜR DAS NÄCHSTE RENNEN?",
			"Nächste Map: " .. nextMap,
			string.format("Mindestens %d Spieler · bis zu %d pro Rennen", minPlayers, maxPlayers),
			"SPIELEN",
			function()
				Remotes.QueueRequest:FireServer("Join", "QuickPlay")
			end
		)
	end
end

return LobbyMenu
