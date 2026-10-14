--[[
	TopBar  (ModuleScript)
	Pfad: StarterPlayer/StarterPlayerScripts/Client/UI/Screens/TopBar

	Statusleiste oben links (außerhalb von Rennen sichtbar):
		- Level-Plakette mit XP-Ring (kreisförmiger Fortschritt)
		- Spielername, Ranked-Chip (Stufe + Punkte in Stufenfarbe)
		- XP-Balken mit Farbverlauf und Zahlen
		- Coin-Anzeige mit Münz-Symbol, hochzählender Animation,
		  schwebendem „+N“ und Shop-Abkürzung (+)
	Liegt unterhalb der Roblox-Topbar (y ≥ 56). Im Rennen ausgeblendet –
	dort gehört der Platz Timer und Fortschrittsbalken.
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

local new = Components.new
local player = Players.LocalPlayer

local COIN_COUNT_TIME = 0.8 -- Sekunden für das Hochzählen der Coins

local TopBar = {}
TopBar.__index = TopBar

function TopBar.new(ui)
	local self = setmetatable({}, TopBar)
	self.UI = ui
	self.DisplayedCoins = nil
	self.DisplayedLevel = nil
	self.CoinAnim = nil

	local frame = Components.Panel({
		Name = "TopBar",
		Position = UDim2.fromOffset(16, 60),
		Size = UDim2.fromOffset(392, 76),
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.08,
		StrokeColor = Theme.Colors.Stroke,
		CornerRadius = 18,
		ZIndex = 2,
		Shadow = true,
		Parent = ui.Root,
	})
	self.Frame = frame

	-- Level-Plakette mit XP-Ring
	local ring, setRing, inner = Components.Ring({
		Name = "LevelRing",
		Size = 64,
		Thickness = 5,
		Color = Theme.Colors.XP,
		TrackColor = Theme.Colors.Shadow,
		InnerColor = Theme.Colors.White,
		Position = UDim2.fromOffset(8, 6),
		ZIndex = 3,
		Parent = frame,
	})
	self.Ring = ring
	self.SetRing = setRing
	Components.Gradient(Theme.Gradients.Accent, 135).Parent = inner
	Components.Stroke(Theme.Colors.Shadow, 1.5, 0.3).Parent = inner
	Components.Label({
		Text = "LV",
		Font = Theme.Fonts.Title,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Theme.Colors.White,
		TextTransparency = 0.15,
		Size = UDim2.new(1, 0, 0, 12),
		Position = UDim2.fromOffset(0, 7),
		ZIndex = 3,
		Parent = inner,
	})
	self.LevelLabel = Components.Label({
		Text = "1",
		Font = Theme.Fonts.Title,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Theme.Colors.White,
		TextWrapped = false,
		Outline = 1.5,
		OutlineColor = Color3.fromRGB(0, 60, 130),
		Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.fromOffset(0, 17),
		ZIndex = 3,
		Parent = inner,
	})

	self.NameLabel = Components.Label({
		Text = player.DisplayName,
		Font = Theme.Fonts.Title,
		Position = UDim2.fromOffset(82, 8),
		Size = UDim2.fromOffset(176, 24),
		TextSize = 19,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
		RichText = false,
		Outline = 1.5,
		OutlineTransparency = 0.4,
		ZIndex = 3,
		Parent = frame,
	})

	-- Ranked-Chip (Stufe · Punkte)
	local tierPill, tierLabel = Components.Pill({
		Name = "Tier",
		Text = "",
		Color = Theme.Colors.Accent,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 9),
		Size = UDim2.fromOffset(118, 22),
		TextSize = 13,
		ZIndex = 3,
		Parent = frame,
	})
	self.TierPill = tierPill
	self.TierLabel = tierLabel

	local _, setXP = Components.ProgressBar({
		Name = "XPBar",
		Position = UDim2.fromOffset(82, 37),
		Size = UDim2.fromOffset(298, 14),
		BackgroundColor = Theme.Colors.Shadow,
		BackgroundTransparency = 0.2,
		Color = Theme.Colors.XP,
		Gradient = { Theme.Gradients.XP[2], Theme.Colors.Accent },
		CornerRadius = 7,
		Parent = frame,
	})
	self.SetXP = setXP
	self.XPLabel = Components.Label({
		Text = "0 / 100 XP",
		Position = UDim2.fromOffset(82, 53),
		Size = UDim2.fromOffset(298, 16),
		TextSize = Theme.TextSize.Tiny - 1,
		Font = Theme.Fonts.Bold,
		TextColor3 = Theme.Colors.TextDim,
		TextWrapped = false,
		ZIndex = 3,
		Parent = frame,
	})

	-- Coins
	local coins = Components.Panel({
		Name = "Coins",
		Position = UDim2.fromOffset(420, 72),
		Size = UDim2.fromOffset(164, 52),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.08,
		StrokeColor = Theme.Colors.Gold,
		StrokeThickness = 2,
		CornerRadius = 26,
		ZIndex = 2,
		Shadow = true,
		Parent = ui.Root,
	})
	self.CoinPanel = coins
	self.CoinIcon = Components.CoinIcon(36, { Position = UDim2.fromOffset(8, 8), ZIndex = 3, Parent = coins })
	self.CoinLabel = Components.Label({
		Text = "0",
		Position = UDim2.fromOffset(50, 0),
		Size = UDim2.new(1, -94, 1, 0),
		TextSize = 24,
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.Gold,
		TextWrapped = false,
		TextScaled = true,
		MaxTextSize = 24,
		Outline = 1.5,
		OutlineColor = Color3.fromRGB(90, 46, 0),
		OutlineTransparency = 0.2,
		ZIndex = 3,
		Parent = coins,
	})
	new("UIPadding", { PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12), Parent = self.CoinLabel })
	local shopButton = Components.Button({
		Name = "ShopShortcut",
		Text = "+",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -9, 0.5, 0),
		Size = UDim2.fromOffset(34, 34),
		Color = Theme.Colors.Success,
		TextColor = Theme.Colors.White,
		TextSize = 24,
		CornerRadius = 17,
		ZIndex = 3,
		OnClick = function()
			local catalog = ui.Screens.Catalog
			if catalog then
				catalog:Open("Shop")
			end
		end,
	})
	shopButton.Parent = coins
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
		self.CoinPanel.Visible = not inRace
		self:_stepCoins()
	end)
end

-- Coins hochzählen (nur während einer laufenden Animation, sonst nichts zu tun)
function TopBar:_stepCoins()
	local anim = self.CoinAnim
	if not anim then
		return
	end
	local t = math.clamp((os.clock() - anim.Start) / COIN_COUNT_TIME, 0, 1)
	local eased = 1 - (1 - t) ^ 3
	local value = anim.From + (anim.To - anim.From) * eased
	self.CoinLabel.Text = Util.FormatNumber(math.floor(value + 0.5))
	if t >= 1 then
		self.CoinAnim = nil
	end
end

function TopBar:_floatText(text: string, color: Color3)
	local label = Components.Label({
		Text = text,
		Font = Theme.Fonts.Title,
		TextSize = 22,
		TextColor3 = color,
		TextWrapped = false,
		Outline = 1.5,
		OutlineTransparency = 0.2,
		Position = UDim2.new(0, 46, 1, 0),
		Size = UDim2.fromOffset(120, 26),
		ZIndex = 4,
		Parent = self.CoinPanel,
	})
	local stroke = label:FindFirstChild("TextStroke")
	Components.Tween(label, 1.3, { Position = UDim2.new(0, 46, 1, 34), TextTransparency = 1 })
	if stroke then
		Components.Tween(stroke, 1.3, { Transparency = 1 })
	end
	task.delay(1.4, function()
		label:Destroy()
	end)
end

function TopBar:_render(profile)
	local level, into, needed = Progression.FromTotalXP(profile.TotalXP or 0)
	self.LevelLabel.Text = tostring(level)
	if self.DisplayedLevel and level > self.DisplayedLevel then
		Components.Pop(self.Ring, 1.3, 0.5)
	end
	self.DisplayedLevel = level
	if needed > 0 then
		self.SetXP(into / needed, 0.4)
		self.SetRing(into / needed, 0.5)
		self.XPLabel.Text = string.format("%s / %s XP  ·  nächstes Level %d", Util.FormatNumber(into), Util.FormatNumber(needed), level + 1)
	else
		self.SetXP(1, 0.4)
		self.SetRing(1, 0.5)
		self.XPLabel.Text = "Maximales Level erreicht"
	end

	local coins = profile.Coins or 0
	if self.DisplayedCoins and coins ~= self.DisplayedCoins then
		local diff = coins - self.DisplayedCoins
		self:_floatText((if diff > 0 then "+" else "") .. Util.FormatNumber(diff), if diff > 0 then Theme.Colors.Gold else Theme.Colors.Danger)
		self.CoinAnim = { From = self.DisplayedCoins, To = coins, Start = os.clock() }
		Components.Pop(self.CoinIcon, 1.25, 0.4)
	else
		self.CoinLabel.Text = Util.FormatNumber(coins)
	end
	self.DisplayedCoins = coins

	local rating = profile.Ranked and profile.Ranked.Rating or 1000
	local tier = Progression.GetTier(rating)
	self.TierLabel.Text = string.format("%s · %d", string.upper(tier.Name), rating)
	self.TierLabel.TextColor3 = tier.Color:Lerp(Theme.Colors.White, 0.35)
	self.TierPill.BackgroundColor3 = tier.Color
	local border = self.TierPill:FindFirstChild("Border")
	if border then
		border.Color = tier.Color
	end
end

return TopBar
