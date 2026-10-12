--[[
	TopBar  (ModuleScript)
	Pfad: StarterPlayer/StarterPlayerScripts/Client/UI/Screens/TopBar

	Immer sichtbare Statusleiste oben links: Level, XP-Fortschritt,
	Coins (mit animierter Änderung) und Ranked-Stufe.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Progression = require(Shared.Progression)
local Util = require(Shared.Util)

local UI = script.Parent.Parent
local Components = require(UI.Components)
local Theme = require(UI.Theme)

local player = Players.LocalPlayer

local TopBar = {}
TopBar.__index = TopBar

function TopBar.new(ui)
	local self = setmetatable({}, TopBar)
	self.UI = ui
	self.DisplayedCoins = nil

	local frame = Components.Panel({
		Name = "TopBar",
		Position = UDim2.fromOffset(16, 64),
		Size = UDim2.fromOffset(440, 66),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.12,
		Parent = ui.Root,
	})
	self.Frame = frame

	local badge = Components.new("Frame", {
		Position = UDim2.fromOffset(8, 7),
		Size = UDim2.fromOffset(52, 52),
		BackgroundColor3 = Theme.Colors.Accent,
		BorderSizePixel = 0,
		Parent = frame,
	})
	Components.Corner(26).Parent = badge
	Components.Label({ Text = "LV", Font = Theme.Fonts.Bold, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = Theme.Colors.Background, Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 6), Parent = badge })
	self.LevelLabel = Components.Label({
		Text = "1",
		Font = Theme.Fonts.Title,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Theme.Colors.Background,
		Size = UDim2.new(1, 0, 0, 28),
		Position = UDim2.fromOffset(0, 18),
		Parent = badge,
	})

	self.NameLabel = Components.Label({
		Text = player.DisplayName,
		Position = UDim2.fromOffset(70, 8),
		Size = UDim2.fromOffset(210, 22),
		TextSize = Theme.TextSize.Body,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
		Parent = frame,
	})
	local _, setXP = Components.ProgressBar({
		Position = UDim2.fromOffset(70, 36),
		Size = UDim2.fromOffset(210, 10),
		Color = Theme.Colors.XP,
		Parent = frame,
	})
	self.SetXP = setXP
	self.XPLabel = Components.Label({
		Text = "0 / 100 XP",
		Position = UDim2.fromOffset(70, 47),
		Size = UDim2.fromOffset(210, 14),
		TextSize = Theme.TextSize.Tiny,
		Font = Theme.Fonts.Medium,
		TextColor3 = Theme.Colors.TextDim,
		Parent = frame,
	})

	local coins = Components.Panel({
		Position = UDim2.fromOffset(292, 11),
		Size = UDim2.fromOffset(138, 44),
		BackgroundColor3 = Theme.Colors.Panel,
		StrokeColor = Theme.Colors.Gold,
		CornerRadius = 22,
		Parent = frame,
	})
	local coinIcon = Components.new("Frame", {
		Position = UDim2.fromOffset(8, 10),
		Size = UDim2.fromOffset(24, 24),
		BackgroundColor3 = Theme.Colors.Gold,
		BorderSizePixel = 0,
		Parent = coins,
	})
	Components.Corner(12).Parent = coinIcon
	Components.Label({ Text = "C", Font = Theme.Fonts.Title, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = Theme.Colors.Background, Size = UDim2.fromScale(1, 1), Parent = coinIcon })
	self.CoinLabel = Components.Label({
		Text = "0",
		Position = UDim2.fromOffset(38, 0),
		Size = UDim2.new(1, -44, 1, 0),
		TextSize = Theme.TextSize.Large,
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.Gold,
		Parent = coins,
	})
	self.CoinPanel = coins

	self.TierLabel = Components.Label({
		Text = "",
		Position = UDim2.fromOffset(16, 134),
		Size = UDim2.fromOffset(440, 18),
		TextSize = Theme.TextSize.Small,
		Font = Theme.Fonts.Bold,
		Parent = ui.Root,
	})
	return self
end

function TopBar:Start()
	local state = self.UI.Ctx.ClientState
	state.ProfileChanged:Connect(function(profile)
		self:_render(profile)
	end)
	if state.Profile then
		self:_render(state.Profile)
	end
	RunService.Heartbeat:Connect(function()
		-- Im Rennen ausblenden: dort gehört der Platz Timer und Fortschrittsbalken
		local inRace = state:IsInRace() or self.UI.Ctx.CameraController:GetSpectate() ~= nil
		self.Frame.Visible = not inRace
		self.TierLabel.Visible = not inRace
	end)
end

function TopBar:_floatText(text: string, color: Color3)
	local label = Components.Label({
		Text = text,
		Font = Theme.Fonts.Title,
		TextSize = 20,
		TextColor3 = color,
		Position = UDim2.new(0, 40, 1, 2),
		Size = UDim2.fromOffset(120, 24),
		Parent = self.CoinPanel,
	})
	Components.Tween(label, 1.2, { Position = UDim2.new(0, 40, 1, 32), TextTransparency = 1 })
	task.delay(1.3, function()
		label:Destroy()
	end)
end

function TopBar:_render(profile)
	local level, into, needed = Progression.FromTotalXP(profile.TotalXP or 0)
	self.LevelLabel.Text = tostring(level)
	if needed > 0 then
		self.SetXP(into / needed, 0.4)
		self.XPLabel.Text = string.format("%s / %s XP", Util.FormatNumber(into), Util.FormatNumber(needed))
	else
		self.SetXP(1, 0.4)
		self.XPLabel.Text = "Maximales Level"
	end
	local coins = profile.Coins or 0
	if self.DisplayedCoins and coins ~= self.DisplayedCoins then
		local diff = coins - self.DisplayedCoins
		self:_floatText((if diff > 0 then "+" else "") .. Util.FormatNumber(diff), if diff > 0 then Theme.Colors.Gold else Theme.Colors.Danger)
	end
	self.DisplayedCoins = coins
	self.CoinLabel.Text = Util.FormatNumber(coins)
	local rating = profile.Ranked and profile.Ranked.Rating or 1000
	local tier = Progression.GetTier(rating)
	self.TierLabel.Text = string.format("RANG: %s · %d Punkte", string.upper(tier.Name), rating)
	self.TierLabel.TextColor3 = tier.Color
end

return TopBar
