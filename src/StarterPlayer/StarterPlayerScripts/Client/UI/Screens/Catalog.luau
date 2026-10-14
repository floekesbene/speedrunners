--[[
	Catalog  (ModuleScript)
	Pfad: StarterPlayer/StarterPlayerScripts/Client/UI/Screens/Catalog

	Shop und Inventar in einem Fenster (zwei Modi):
		Shop:      alle Items, Kaufen (Preis, Seltenheit, Levelvoraussetzung)
		Inventar:  nur eigene Items, Ausrüsten/Ablegen
	Links: Vorschau-Bühne – Verlaufs-Hintergrund in der Seltenheitsfarbe,
	Lichtkegel, Podest (zwei Zylinder-Parts im ViewportFrame) mit RunnerRig +
	Kosmetik (Emote-/Siegesposen werden animiert), Name, Seltenheits- und
	Kategorie-Chips, Beschreibung, Aktions-Button mit klaren Zuständen
	(Kaufen / Gratis / zu wenig Coins / Level gesperrt / Ausrüsten / Ablegen /
	Ausgerüstet) und Meldungen mit Symbol.
	Rechts: Raster aller Items der gewählten Kategorie als Karten in der
	Seltenheitsfarbe (Farbfelder, Trail-Streifen oder Symbol, Preis mit
	Münze bzw. Status-Chip); legendäre Items haben einen umlaufenden Glanzrand.

	Alle Aktionen gehen über die RemoteFunction "ShopRequest" – der Server
	prüft Guthaben, Besitz und Doppelkäufe.

	API:
		:Open(mode)   mode = "Shop" | "Inventory"
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)
local RunnerRig = require(Shared.RunnerRig)
local CosmeticApplier = require(Shared.CosmeticApplier)
local CosmeticDefinitions = require(Shared.CosmeticDefinitions)

local UI = script.Parent.Parent
local Components = require(UI.Components)
local Theme = require(UI.Theme)

local new = Components.new
local rgb = Color3.fromRGB

local Catalog = {}
Catalog.__index = Catalog

local CARD_SIZE = UDim2.fromOffset(152, 164)
local PREVIEW_WIDTH = 330

-- Symbole je Kategorie (für Karten ohne Farbfelder und für die Tabs)
local CATEGORY_GLYPHS = {
	Skins = "👕",
	Trails = "💫",
	Effects = "✨",
	Emotes = "💃",
	Victory = Theme.Icons.Leaderboard,
	Colors = "🎨",
}

local MODES = {
	Shop = { Title = "SHOP", Icon = Theme.Icons.Shop, Color = Theme.Colors.Gold },
	Inventory = { Title = "INVENTAR", Icon = Theme.Icons.Inventory, Color = Theme.Colors.Purple },
}

local RAINBOW = { rgb(255, 60, 60), rgb(255, 200, 40), rgb(80, 255, 80), rgb(60, 160, 255), rgb(190, 90, 255) }

function Catalog.new(ui)
	local self = setmetatable({}, Catalog)
	self.UI = ui
	self.Mode = "Shop"
	self.Category = "Skins"
	self.Selected = nil
	self.Busy = false
	self.Cards = {}
	self.Glows = {}
	self.MessageToken = 0

	local modal = Components.Modal({
		Name = "Catalog",
		Title = "SHOP",
		Icon = Theme.Icons.Shop,
		Accent = Theme.Colors.Gold,
		Size = UDim2.fromOffset(1060, 620),
		Parent = ui.Root,
	})
	self.Modal = modal
	ui:RegisterModal("Catalog", modal)
	self.HeaderIcon = modal.Window:FindFirstChild("Icon")
	local content = modal.Content

	-- Coins-Anzeige oben rechts (neben dem Schließen-Button)
	local coins = new("Frame", {
		Name = "Coins",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -70, 0, 16),
		Size = UDim2.fromOffset(170, 38),
		BackgroundColor3 = Theme.Colors.Shadow,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ZIndex = 23,
		Parent = modal.Window,
	})
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = coins })
	Components.Stroke(Theme.Colors.Gold, 1.5, 0.3).Parent = coins
	Components.CoinIcon(26, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 7, 0.5, 0), ZIndex = 23, Parent = coins })
	self.CoinLabel = Components.Heading({
		Text = "",
		TextSize = 20,
		TextScaled = true,
		MaxTextSize = 20,
		TextColor3 = Theme.Colors.Gold:Lerp(Theme.Colors.White, 0.2),
		TextXAlignment = Enum.TextXAlignment.Right,
		Outline = 1.5,
		RichText = false,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.new(1, -50, 0, 24),
		ZIndex = 23,
		Parent = coins,
	})

	local tabs = {}
	for _, category in CosmeticDefinitions.Categories do
		table.insert(tabs, { Name = category, Label = string.upper(CosmeticDefinitions.CategoryNames[category]), Width = if category == "Victory" then 200 else 130 })
	end
	local _, selectTab = Components.Tabs({
		Tabs = tabs,
		Size = UDim2.new(1, 0, 0, 38),
		Parent = content,
		OnSelect = function(name)
			self.Category = name
			self.Selected = nil
			self:_render()
		end,
	})
	self.SelectTab = selectTab

	self:_buildPreview(content)

	-- Raster
	local grid = new("ScrollingFrame", {
		Name = "Grid",
		Position = UDim2.fromOffset(PREVIEW_WIDTH + 16, 50),
		Size = UDim2.new(1, -(PREVIEW_WIDTH + 16), 1, -50),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Colors.Stroke,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = content,
	})
	Components.Grid(CARD_SIZE, 12).Parent = grid
	Components.Padding(6).Parent = grid
	self.Grid = grid
	self.EmptyLabel = Components.Label({
		Text = Theme.Icons.Inventory .. "  Noch keine Items in dieser Kategorie. Schau im Shop vorbei!",
		Font = Theme.Fonts.Title,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Theme.Colors.TextDim,
		Position = UDim2.fromOffset(PREVIEW_WIDTH + 16, 140),
		Size = UDim2.new(1, -(PREVIEW_WIDTH + 16), 0, 50),
		Visible = false,
		Parent = content,
	})

	modal.OnClose = function()
		self:_destroyPreview()
	end
	return self
end

-- Vorschau-Panel links: Bühne mit ViewportFrame, Details, Aktion
function Catalog:_buildPreview(content: Frame)
	local _, panel = Components.Card({
		Name = "Preview",
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.new(0, PREVIEW_WIDTH, 1, -50),
		BackgroundColor3 = Theme.Colors.PanelDark,
		CornerRadius = 16,
		ShadowOffset = 4,
		ShadowSpread = 5,
		Parent = content,
	})
	self.PreviewPanel = panel

	-- Bühne: Verlaufs-Hintergrund, Lichtkegel, Bodenschein
	local stage = new("Frame", {
		Name = "Stage",
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.new(1, -20, 0, 250),
		BackgroundColor3 = Theme.Colors.White,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = panel,
	})
	Components.Corner(12).Parent = stage
	self.StageGradient = Components.Gradient({ Theme.Colors.Accent, Theme.Colors.PanelDark }, 90)
	self.StageGradient.Parent = stage
	self.StageStroke = Components.Stroke(Theme.Colors.Accent, 2, 0.35)
	self.StageStroke.Parent = stage
	for index, beam in { { X = 0.3, Rotation = 18 }, { X = 0.7, Rotation = -18 } } do
		local light = new("Frame", {
			Name = "Beam" .. index,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(beam.X, 0, 0, -40),
			Size = UDim2.new(0, 70, 1, 40),
			Rotation = beam.Rotation,
			BackgroundColor3 = Theme.Colors.White,
			BackgroundTransparency = 0.82,
			BorderSizePixel = 0,
			Parent = stage,
		})
		Components.Gradient(Theme.Colors.White, 90, { 0.2, 1 }).Parent = light
	end
	self.FloorGlow = new("Frame", {
		Name = "FloorGlow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 1, -34),
		Size = UDim2.fromOffset(230, 56),
		BackgroundColor3 = Theme.Colors.Accent,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		Parent = stage,
	})
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = self.FloorGlow })
	Components.Gradient(Theme.Colors.White, 90, { 1, 0.2, 1 }).Parent = self.FloorGlow

	local viewport = new("ViewportFrame", {
		Name = "Viewport",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Ambient = rgb(150, 156, 190),
		LightColor = rgb(255, 246, 232),
		-- Licht fällt von vorne-oben (Kameraseite) auf die Figur
		LightDirection = Vector3.new(-0.45, -1, 0.7),
		Parent = stage,
	})
	local worldModel = new("WorldModel", { Parent = viewport })
	local camera = new("Camera", { FieldOfView = 40, Parent = viewport })
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 1.8, -11.5), Vector3.new(0, 0.15, 0))
	viewport.CurrentCamera = camera
	self.Viewport = viewport
	self.WorldModel = worldModel

	-- Podest: dunkler Sockel mit leuchtendem Rand in der Seltenheitsfarbe
	local upright = CFrame.Angles(0, 0, math.rad(90))
	self.Pedestal = new("Part", {
		Name = "Pedestal",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, 5.6, 5.6),
		CFrame = CFrame.new(0, -2.97, 0) * upright,
		Color = rgb(40, 46, 86),
		Material = Enum.Material.SmoothPlastic,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = worldModel,
	})
	self.PedestalRim = new("Part", {
		Name = "PedestalRim",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.14, 6, 6),
		CFrame = CFrame.new(0, -2.82, 0) * upright,
		Color = Theme.Colors.Accent,
		Material = Enum.Material.Neon,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = worldModel,
	})

	-- Chips auf der Bühne
	local rarityPill, rarityLabel = Components.Pill({
		Text = "",
		Size = UDim2.fromOffset(112, 22),
		Position = UDim2.fromOffset(10, 10),
		TextSize = 12,
		ZIndex = 2,
		Parent = stage,
	})
	rarityPill.BackgroundTransparency = 0.45
	self.RarityPill, self.ItemRarity = rarityPill, rarityLabel
	local equippedPill = Components.Pill({
		Text = Theme.Icons.Check .. " AUSGERÜSTET",
		Color = Theme.Colors.Success,
		Size = UDim2.fromOffset(118, 22),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 10),
		TextSize = 12,
		ZIndex = 2,
		Parent = stage,
	})
	equippedPill.BackgroundTransparency = 0.45
	equippedPill.Visible = false
	self.EquippedPill = equippedPill

	-- Details
	self.ItemName = Components.Heading({
		Text = "",
		TextSize = 24,
		TextScaled = true,
		MaxTextSize = 24,
		RichText = false,
		Position = UDim2.fromOffset(14, 268),
		Size = UDim2.new(1, -28, 0, 30),
		Parent = panel,
	})
	local categoryPill, categoryLabel = Components.Pill({
		Text = "",
		Color = Theme.Colors.PanelLight:Lerp(Theme.Colors.White, 0.3),
		Size = UDim2.fromOffset(170, 22),
		Position = UDim2.fromOffset(14, 302),
		TextSize = 12,
		Parent = panel,
	})
	self.CategoryPill, self.CategoryLabel = categoryPill, categoryLabel
	self.ItemDescription = Components.Label({
		Text = "",
		Font = Theme.Fonts.Medium,
		TextSize = Theme.TextSize.Small - 1,
		TextColor3 = Theme.Colors.TextDim,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(14, 332),
		Size = UDim2.new(1, -28, 0, 62),
		Parent = panel,
	})
	self.ActionButton = Components.Button({
		Text = "",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -40),
		Size = UDim2.new(1, -28, 0, 52),
		Color = Theme.Colors.Accent,
		TextColor = Theme.Colors.White,
		TextSize = 20,
		TextScaled = true,
		Font = Theme.Fonts.Title,
		CornerRadius = 14,
		OnClick = function()
			self:_action()
		end,
	})
	self.ActionButton.Parent = panel
	self.ActionCoin = Components.CoinIcon(26, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0), Parent = self.ActionButton })
	self.ActionCoin.Visible = false
	Components.Shine(self.ActionButton, { Interval = 4.5 })
	self.Message = Components.Label({
		Text = "",
		Font = Theme.Fonts.Bold,
		TextSize = Theme.TextSize.Small - 1,
		TextScaled = true,
		MaxTextSize = Theme.TextSize.Small - 1,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.6,
		TextStrokeColor3 = Theme.Colors.Shadow,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -20, 0, 24),
		Parent = panel,
	})
end

function Catalog:Start()
	local state = self.UI.Ctx.ClientState
	state.ProfileChanged:Connect(function()
		if self.Modal.IsOpen() then
			self:_render()
		end
	end)
	RunService.RenderStepped:Connect(function()
		if self.Preview and self.Preview.Parent then
			self.Preview:PivotTo(CFrame.Angles(0, math.sin(os.clock() * 0.6) * 0.9, 0))
		end
		-- Umlaufender Glanzrand der legendären Karten (nur bei offenem Fenster)
		if #self.Glows > 0 and self.Modal.IsOpen() then
			local rotation = (os.clock() * 120) % 360
			for _, gradient in self.Glows do
				gradient.Rotation = rotation
			end
		end
	end)
end

--- Öffnet das Fenster im Modus "Shop" oder "Inventory".
function Catalog:Open(mode: string)
	self.Mode = mode
	local info = MODES[mode] or MODES.Shop
	self.Modal.Title.Text = info.Title
	if self.HeaderIcon then
		Components.SetIconColor(self.HeaderIcon, info.Color)
		local glyph = self.HeaderIcon:FindFirstChild("Glyph")
		if glyph then
			glyph.Text = info.Icon
		end
	end
	self.Selected = nil
	self.Message.Text = ""
	self.UI:OpenModal("Catalog")
	self.SelectTab(self.Category)
end

function Catalog:_profile()
	return self.UI.Ctx.ClientState.Profile
end

function Catalog:_owns(category: string, id: string): boolean
	local profile = self:_profile()
	return profile ~= nil and profile.Owned[category] ~= nil and profile.Owned[category][id] == true
end

function Catalog:_equipped(category: string): string
	local profile = self:_profile()
	return profile and profile.Equipped[category] or ""
end

function Catalog:_items()
	local list = {}
	for _, item in CosmeticDefinitions.Items[self.Category] do
		if self.Mode == "Shop" or self:_owns(self.Category, item.Id) then
			table.insert(list, item)
		end
	end
	table.sort(list, function(a, b)
		local ra = CosmeticDefinitions.Rarities[a.Rarity].Order
		local rb = CosmeticDefinitions.Rarities[b.Rarity].Order
		if ra ~= rb then
			return ra < rb
		end
		return a.Price < b.Price
	end)
	return list
end

-- Gesperrt durch Level? (nur für nicht besessene Items relevant)
function Catalog:_levelLocked(item): boolean
	local profile = self:_profile()
	return item.LevelRequired ~= nil and profile ~= nil and profile.Level < item.LevelRequired
end

------------------------------------------------------------------------
-- Karten
------------------------------------------------------------------------

-- Farbkreis mit weißem Rand und Glanzpunkt
local function colorDot(parent: Instance, size: number, color: Color3, position: UDim2, zIndex: number?)
	local dot = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = zIndex or 1,
		Parent = parent,
	})
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = dot })
	Components.Stroke(Theme.Colors.White, 2, 0.2).Parent = dot
	local shine = new("Frame", {
		Position = UDim2.fromScale(0.2, 0.14),
		Size = UDim2.fromScale(0.3, 0.2),
		Rotation = -35,
		BackgroundColor3 = Theme.Colors.White,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		ZIndex = zIndex or 1,
		Parent = dot,
	})
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = shine })
	return dot
end

-- Vorschau-Grafik einer Karte je Kategorie (Farbfelder, Trail-Streifen, Symbol)
local function buildArt(card: Instance, item, rarityColor: Color3)
	local art = new("Frame", {
		Name = "Art",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(8, 26),
		Size = UDim2.new(1, -16, 0, 52),
		Parent = card,
	})
	if item.Category == "Skins" then
		colorDot(art, 34, item.Secondary, UDim2.new(0.5, -26, 0.5, 4), 1)
		colorDot(art, 34, item.Accent, UDim2.new(0.5, 26, 0.5, 4), 1)
		colorDot(art, 46, item.Primary, UDim2.fromScale(0.5, 0.5), 2)
	elseif item.Category == "Trails" then
		local streak = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, -10, 0.5, 0),
			Size = UDim2.fromOffset(104, 16),
			BackgroundColor3 = Theme.Colors.White,
			BorderSizePixel = 0,
			Parent = art,
		})
		new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = streak })
		local colors = if item.Rainbow then RAINBOW else { item.ColorA, item.ColorB }
		Components.Gradient(colors, 0, { 1, 0.3, 0 }).Parent = streak
		colorDot(art, 30, if item.Rainbow then RAINBOW[#RAINBOW] else item.ColorB, UDim2.new(0.5, 44, 0.5, 0), 2)
	elseif item.Category == "Effects" or item.Category == "Colors" then
		local dot = colorDot(art, 48, item.Color, UDim2.fromScale(0.5, 0.5), 1)
		if item.Category == "Effects" then
			Components.Label({
				Text = CATEGORY_GLYPHS.Effects,
				TextSize = 22,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextWrapped = false,
				RichText = false,
				Size = UDim2.fromScale(1, 1),
				Parent = dot,
			})
		end
	else
		local _, glyph = Components.Icon({
			Glyph = CATEGORY_GLYPHS[item.Category] or Theme.Icons.Star,
			Color = rarityColor,
			Size = 50,
			TextSize = 26,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Parent = art,
		})
		glyph.TextStrokeTransparency = 1
	end
end

-- Status unten auf der Karte: Preis mit Münze oder Status-Chip
function Catalog:_buildCardStatus(card: Instance, item, owned: boolean, equipped: boolean)
	local holder = new("Frame", {
		Name = "Status",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -9),
		Size = UDim2.new(1, -16, 0, 24),
		Parent = card,
	}, { Components.List(Enum.FillDirection.Horizontal, 5, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
	local chipText, chipColor
	if equipped then
		chipText, chipColor = Theme.Icons.Check .. " AUSGERÜSTET", Theme.Colors.Success
	elseif owned then
		chipText, chipColor = "IM BESITZ", Theme.Colors.Accent
	elseif self:_levelLocked(item) then
		chipText, chipColor = Theme.Icons.Lock .. " LEVEL " .. tostring(item.LevelRequired), Theme.Colors.Danger
	elseif item.Price == 0 then
		chipText, chipColor = "GRATIS", Theme.Colors.Success
	end
	if chipText then
		Components.Pill({ Text = chipText, Color = chipColor, Size = UDim2.fromOffset(128, 22), TextSize = 12, Parent = holder })
		return
	end
	local profile = self:_profile()
	local affordable = profile == nil or profile.Coins >= item.Price
	Components.CoinIcon(20, { Parent = holder })
	Components.Label({
		Text = Util.FormatNumber(item.Price),
		Font = Theme.Fonts.Title,
		TextSize = 17,
		TextColor3 = if affordable then Theme.Colors.Gold:Lerp(Theme.Colors.White, 0.15) else Theme.Colors.TextDim,
		TextWrapped = false,
		RichText = false,
		TextStrokeTransparency = 0.5,
		TextStrokeColor3 = Theme.Colors.Shadow,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 22),
		Parent = holder,
	})
end

function Catalog:_buildCard(index: number, item)
	local rarity = CosmeticDefinitions.Rarities[item.Rarity]
	local owned = self:_owns(item.Category, item.Id)
	local equipped = self:_equipped(item.Category) == item.Id
	local card = Components.Button({
		Name = item.Id,
		Text = "",
		Size = CARD_SIZE,
		Color = rarity.Color:Lerp(Theme.Colors.PanelDark, 0.74),
		StrokeColor = rarity.Color,
		CornerRadius = 14,
		LayoutOrder = index,
		OnClick = function()
			self:_select(item)
		end,
	})
	card.Parent = self.Grid
	-- Schimmer der Seltenheitsfarbe im oberen Bereich
	local glow = new("Frame", {
		Name = "RarityGlow",
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(1, -4, 0, 70),
		BackgroundColor3 = rarity.Color,
		BorderSizePixel = 0,
		Parent = card,
	})
	Components.Corner(12).Parent = glow
	Components.Gradient(rarity.Color, 90, { 0.55, 1 }).Parent = glow
	Components.Label({
		Text = string.upper(rarity.Name),
		Font = Theme.Fonts.Title,
		TextSize = 11,
		TextColor3 = rarity.Color:Lerp(Theme.Colors.White, 0.45),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		RichText = false,
		TextStrokeTransparency = 0.5,
		TextStrokeColor3 = Theme.Colors.Shadow,
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.new(1, 0, 0, 14),
		Parent = card,
	})
	buildArt(card, item, rarity.Color)
	Components.Label({
		Text = item.Name,
		Font = Theme.Fonts.Title,
		TextSize = 15,
		TextScaled = true,
		MaxTextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Center,
		RichText = false,
		TextStrokeTransparency = 0.5,
		TextStrokeColor3 = Theme.Colors.Shadow,
		Position = UDim2.fromOffset(6, 86),
		Size = UDim2.new(1, -12, 0, 36),
		Parent = card,
	})
	self:_buildCardStatus(card, item, owned, equipped)
	if equipped then
		local _, check = Components.Icon({
			Name = "EquippedBadge",
			Glyph = Theme.Icons.Check,
			Color = Theme.Colors.Success,
			Size = 24,
			TextSize = 13,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -8, 0, 8),
			Parent = card,
		})
		check.TextStrokeTransparency = 0.4
	end
	local border = card:FindFirstChild("Border")
	if border and item.Rarity == "Legendary" then
		-- Umlaufender Glanz (Rotation wird in Start() animiert)
		local shimmer = Components.Gradient({ rarity.Color, Theme.Colors.White, rarity.Color, rgb(255, 120, 40), rarity.Color }, 0)
		shimmer.Parent = border
		table.insert(self.Glows, shimmer)
	elseif border and item.Rarity == "Epic" then
		Components.Gradient({ rarity.Color, Theme.Colors.Accent2, rarity.Color }, 45).Parent = border
	end
	self.Cards[item] = card
end

function Catalog:_render()
	local profile = self:_profile()
	self.CoinLabel.Text = if profile then Util.FormatNumber(profile.Coins) else ""
	for _, child in self.Grid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	self.Cards = {}
	self.Glows = {}
	local items = self:_items()
	self.EmptyLabel.Visible = #items == 0
	if not self.Selected or self.Selected.Category ~= self.Category then
		self.Selected = nil
		local equippedId = self:_equipped(self.Category)
		for _, item in items do
			if item.Id == equippedId then
				self.Selected = item
			end
		end
		self.Selected = self.Selected or items[1]
	end
	for index, item in items do
		self:_buildCard(index, item)
	end
	self:_highlightCards()
	self:_renderDetail()
end

-- Auswahl wechseln, ohne das Raster neu aufzubauen
function Catalog:_select(item)
	if self.Selected == item then
		return
	end
	self.Selected = item
	self.Message.Text = ""
	self:_highlightCards()
	local card = self.Cards[item]
	if card then
		Components.Pop(card, 1.08, 0.25)
	end
	self:_renderDetail()
end

function Catalog:_highlightCards()
	for item, card in self.Cards do
		local selected = item == self.Selected
		local border = card:FindFirstChild("Border")
		if border then
			border.Color = if selected then Theme.Colors.White else CosmeticDefinitions.Rarities[item.Rarity].Color
			border.Thickness = if selected then 3.5 else 2
		end
	end
end

------------------------------------------------------------------------
-- Details und Aktion
------------------------------------------------------------------------

-- Aktions-Button einfärben/beschriften (Grundfarbe, optional Verlaufspaar)
function Catalog:_setAction(text: string, color: Color3, gradient, showCoin: boolean)
	self.ActionButton.Text = text
	Components.SetButtonColor(self.ActionButton, color, gradient)
	self.ActionButton.TextColor3 = Theme.Colors.White
	self.ActionCoin.Visible = showCoin
end

function Catalog:_renderDetail()
	local item = self.Selected
	if not item then
		self.ItemName.Text = ""
		self.ItemRarity.Text = ""
		self.RarityPill.Visible = false
		self.CategoryPill.Visible = false
		self.EquippedPill.Visible = false
		self.ItemDescription.Text = ""
		self.ActionButton.Visible = false
		self:_destroyPreview()
		return
	end
	local rarity = CosmeticDefinitions.Rarities[item.Rarity]
	self.ItemName.Text = item.Name
	-- Seltenheit: Chip, Bühnenfarbe, Podest-Rand, Bodenschein
	self.RarityPill.Visible = true
	self.ItemRarity.Text = string.upper(rarity.Name)
	self.ItemRarity.TextColor3 = rarity.Color:Lerp(Theme.Colors.White, 0.4)
	self.RarityPill.BackgroundColor3 = rarity.Color
	local rarityBorder = self.RarityPill:FindFirstChild("Border")
	if rarityBorder then
		rarityBorder.Color = rarity.Color
	end
	self.CategoryPill.Visible = true
	self.CategoryLabel.Text = (CATEGORY_GLYPHS[item.Category] or "") .. " " .. string.upper(CosmeticDefinitions.CategoryNames[item.Category])
	self.StageGradient.Color = ColorSequence.new(rarity.Color:Lerp(Theme.Colors.Panel, 0.45), Theme.Colors.PanelDark:Lerp(Theme.Colors.Shadow, 0.4))
	self.StageStroke.Color = rarity.Color
	self.FloorGlow.BackgroundColor3 = rarity.Color
	self.PedestalRim.Color = rarity.Color

	local description = item.Description or ""
	if item.Category == "Trails" or item.Category == "Effects" then
		description ..= "\n(Trails und Partikel sind im Spiel sichtbar, nicht in der Vorschau.)"
	end
	self.ItemDescription.Text = description

	local owned = self:_owns(item.Category, item.Id)
	local equipped = self:_equipped(item.Category) == item.Id
	local profile = self:_profile()
	self.EquippedPill.Visible = equipped
	self.ActionButton.Visible = true
	if equipped then
		if CosmeticDefinitions.Unequippable[item.Category] then
			self:_setAction(Theme.Icons.Close .. "  ABLEGEN", Theme.Colors.PanelLight, nil, false)
		else
			self:_setAction(Theme.Icons.Check .. "  AUSGERÜSTET", Theme.Colors.Success, nil, false)
		end
	elseif owned then
		self:_setAction("AUSRÜSTEN", Theme.Colors.Accent, nil, false)
	elseif self:_levelLocked(item) then
		self:_setAction(Theme.Icons.Lock .. "  AB LEVEL " .. tostring(item.LevelRequired), Theme.Colors.PanelLight, nil, false)
	elseif item.Price == 0 then
		self:_setAction(Theme.Icons.Gift .. "  GRATIS HOLEN", Theme.Colors.Success, Theme.Gradients.Play, false)
	elseif profile and profile.Coins < item.Price then
		self:_setAction("ZU WENIG COINS · " .. Util.FormatNumber(item.Price), Theme.Colors.PanelLight, nil, true)
	else
		self:_setAction("KAUFEN · " .. Util.FormatNumber(item.Price), Theme.Colors.Gold, Theme.Gradients.Gold, true)
	end
	self:_updatePreview(item)
end

function Catalog:_destroyPreview()
	if self.Preview then
		self.UI.Ctx.AnimationController:UnregisterPreview(self.Preview)
		self.Preview:Destroy()
		self.Preview = nil
	end
end

function Catalog:_updatePreview(item)
	local profile = self:_profile()
	local equipped = if profile then table.clone(profile.Equipped) else table.clone(CosmeticDefinitions.DefaultEquipped)
	equipped[item.Category] = item.Id
	if not self.Preview then
		local rig = RunnerRig.Build({ ForCharacter = false })
		for _, part in rig:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = part.Name == "HumanoidRootPart"
			end
		end
		rig.Parent = self.WorldModel
		self.Preview = rig
		self.UI.Ctx.AnimationController:RegisterPreview(rig, function()
			return self.PreviewPose
		end)
	end
	CosmeticApplier.Apply(self.Preview, equipped)
	if item.Category == "Emotes" then
		self.PreviewPose = item.Id
	elseif item.Category == "Victory" then
		self.PreviewPose = "Victory"
	else
		self.PreviewPose = "Idle"
	end
end

-- Meldung unter dem Button (Symbol + Farbe, verschwindet nach 4 s)
function Catalog:_setMessage(text: string, kind: string?)
	self.MessageToken += 1
	local token = self.MessageToken
	if kind == "Success" then
		self.Message.Text = Theme.Icons.Check .. "  " .. text
		self.Message.TextColor3 = Theme.Colors.Success
	elseif kind == "Error" then
		self.Message.Text = Theme.Icons.Error .. "  " .. text
		self.Message.TextColor3 = Theme.Colors.Danger
	else
		self.Message.Text = text
		self.Message.TextColor3 = Theme.Colors.TextDim
	end
	if kind then
		Components.Pop(self.Message, 1.15, 0.3)
		task.delay(4, function()
			if self.MessageToken == token then
				self.Message.Text = ""
			end
		end)
	end
end

function Catalog:_action()
	local item = self.Selected
	if not item or self.Busy then
		return
	end
	local owned = self:_owns(item.Category, item.Id)
	local equipped = self:_equipped(item.Category) == item.Id
	local action
	if equipped then
		if not CosmeticDefinitions.Unequippable[item.Category] then
			return
		end
		action = "Unequip"
	elseif owned then
		action = "Equip"
	else
		action = "Buy"
	end
	self.Busy = true
	self:_setMessage("…", nil)
	local ok, result = pcall(function()
		return Remotes.ShopRequest:InvokeServer(action, item.Category, item.Id)
	end)
	self.Busy = false
	if not ok or type(result) ~= "table" then
		self:_setMessage("Verbindungsfehler – bitte erneut versuchen.", "Error")
		return
	end
	self:_setMessage(result.Message or "", if result.Ok then "Success" else "Error")
	if result.Ok then
		Components.Pop(self.ActionButton, 1.08, 0.3)
	end
	if result.Ok and action == "Buy" then
		-- Direkt nach dem Kauf ausrüsten (bequemer)
		pcall(function()
			Remotes.ShopRequest:InvokeServer("Equip", item.Category, item.Id)
		end)
	end
end

return Catalog
