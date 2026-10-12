--[[
	Catalog  (ModuleScript)
	Pfad: StarterPlayer/StarterPlayerScripts/Client/UI/Screens/Catalog

	Shop und Inventar in einem Fenster (zwei Modi):
		Shop:      alle Items, Kaufen (Preis, Seltenheit, Levelvoraussetzung)
		Inventar:  nur eigene Items, Ausrüsten/Ablegen
	Links: 3D-Vorschau (ViewportFrame mit RunnerRig + Kosmetik, Emote-/Sieges-
	posen werden animiert), Beschreibung, Aktionen, Fehlermeldungen.
	Rechts: Raster aller Items der gewählten Kategorie.

	Alle Aktionen gehen über die RemoteFunction "ShopRequest" – der Server
	prüft Guthaben, Besitz und Doppelkäufe.
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

local Catalog = {}
Catalog.__index = Catalog

function Catalog.new(ui)
	local self = setmetatable({}, Catalog)
	self.UI = ui
	self.Mode = "Shop"
	self.Category = "Skins"
	self.Selected = nil
	self.Busy = false

	local modal = Components.Modal({ Name = "Catalog", Title = "SHOP", Size = UDim2.fromOffset(1060, 620), Parent = ui.Root })
	self.Modal = modal
	ui:RegisterModal("Catalog", modal)
	local content = modal.Content

	self.CoinLabel = Components.Label({
		Text = "",
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.Gold,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -70, 0, 22),
		Size = UDim2.fromOffset(260, 28),
		Parent = modal.Window,
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

	-- Vorschau
	local previewPanel = Components.Panel({
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.new(0, 330, 1, -50),
		BackgroundColor3 = Theme.Colors.PanelDark,
		Parent = content,
	})
	local viewport = new("ViewportFrame", {
		Size = UDim2.new(1, -20, 0, 250),
		Position = UDim2.fromOffset(10, 10),
		BackgroundColor3 = Theme.Colors.Background,
		BackgroundTransparency = 0.3,
		Ambient = Color3.fromRGB(170, 170, 190),
		LightColor = Color3.fromRGB(255, 255, 255),
		LightDirection = Vector3.new(-1, -1, -1),
		Parent = previewPanel,
	})
	Components.Corner(10).Parent = viewport
	local worldModel = new("WorldModel", { Parent = viewport })
	local camera = new("Camera", { FieldOfView = 40, Parent = viewport })
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 1.2, -10.5), Vector3.new(0, 0.2, 0))
	viewport.CurrentCamera = camera
	self.Viewport = viewport
	self.WorldModel = worldModel

	self.ItemName = Components.Label({
		Text = "",
		Font = Theme.Fonts.Title,
		TextSize = 24,
		Position = UDim2.fromOffset(14, 268),
		Size = UDim2.new(1, -28, 0, 28),
		Parent = previewPanel,
	})
	self.ItemRarity = Components.Label({
		Text = "",
		Font = Theme.Fonts.Bold,
		TextSize = Theme.TextSize.Small,
		Position = UDim2.fromOffset(14, 298),
		Size = UDim2.new(1, -28, 0, 18),
		Parent = previewPanel,
	})
	self.ItemDescription = Components.Label({
		Text = "",
		Font = Theme.Fonts.Medium,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Colors.TextDim,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(14, 322),
		Size = UDim2.new(1, -28, 0, 60),
		Parent = previewPanel,
	})
	self.ActionButton = Components.Button({
		Text = "",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -40),
		Size = UDim2.new(1, -28, 0, 50),
		Color = Theme.Colors.Accent,
		TextColor = Theme.Colors.Background,
		Font = Theme.Fonts.Title,
		OnClick = function()
			self:_action()
		end,
	})
	self.ActionButton.Parent = previewPanel
	self.Message = Components.Label({
		Text = "",
		Font = Theme.Fonts.Bold,
		TextSize = Theme.TextSize.Small,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -20, 0, 24),
		Parent = previewPanel,
	})

	-- Raster
	local grid = new("ScrollingFrame", {
		Position = UDim2.fromOffset(346, 50),
		Size = UDim2.new(1, -346, 1, -50),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = content,
	})
	Components.Grid(UDim2.fromOffset(152, 150), 12).Parent = grid
	Components.Padding(4).Parent = grid
	self.Grid = grid
	self.EmptyLabel = Components.Label({
		Text = "Noch keine Items in dieser Kategorie. Schau im Shop vorbei!",
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Theme.Colors.TextDim,
		Position = UDim2.fromOffset(346, 120),
		Size = UDim2.new(1, -346, 0, 40),
		Visible = false,
		Parent = content,
	})

	modal.OnClose = function()
		self:_destroyPreview()
	end
	return self
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
	end)
end

--- Öffnet das Fenster im Modus "Shop" oder "Inventory".
function Catalog:Open(mode: string)
	self.Mode = mode
	self.Modal.Title.Text = if mode == "Shop" then "SHOP" else "INVENTAR"
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

local function swatchColors(item): { Color3 }
	if item.Category == "Skins" then
		return { item.Primary, item.Secondary, item.Accent }
	elseif item.Category == "Trails" then
		if item.Rainbow then
			return { Color3.fromRGB(255, 60, 60), Color3.fromRGB(80, 255, 80), Color3.fromRGB(60, 160, 255) }
		end
		return { item.ColorA, item.ColorB }
	elseif item.Category == "Effects" or item.Category == "Colors" then
		return { item.Color }
	end
	return { CosmeticDefinitions.Rarities[item.Rarity].Color }
end

function Catalog:_render()
	local profile = self:_profile()
	self.CoinLabel.Text = if profile then Util.FormatNumber(profile.Coins) .. " Coins" else ""
	for _, child in self.Grid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
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
		local rarity = CosmeticDefinitions.Rarities[item.Rarity]
		local owned = self:_owns(item.Category, item.Id)
		local equipped = self:_equipped(item.Category) == item.Id
		local selected = self.Selected == item
		local card = Components.Button({
			Text = "",
			Size = UDim2.fromOffset(152, 150),
			Color = if selected then Theme.Colors.PanelLight else Theme.Colors.PanelDark,
			StrokeColor = if selected then Theme.Colors.Accent else rarity.Color,
			LayoutOrder = index,
			OnClick = function()
				self.Selected = item
				self.Message.Text = ""
				self:_render()
			end,
		})
		card.Parent = self.Grid
		local stripe = new("Frame", { Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = rarity.Color, BorderSizePixel = 0, Parent = card })
		Components.Corner(3).Parent = stripe
		local swatches = new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(12, 18),
			Size = UDim2.new(1, -24, 0, 50),
			Parent = card,
		}, { Components.List(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center) })
		for i, color in swatchColors(item) do
			local swatch = new("Frame", { Size = UDim2.fromOffset(40, 40), BackgroundColor3 = color, BorderSizePixel = 0, LayoutOrder = i, Parent = swatches })
			Components.Corner(20).Parent = swatch
			Components.Stroke(Theme.Colors.White, 1, 0.6).Parent = swatch
		end
		Components.Label({
			Text = item.Name,
			Font = Theme.Fonts.Bold,
			TextSize = Theme.TextSize.Small,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(6, 74),
			Size = UDim2.new(1, -12, 0, 36),
			Parent = card,
		})
		local status
		local statusColor = Theme.Colors.TextDim
		if equipped then
			status = "AUSGERÜSTET"
			statusColor = Theme.Colors.Success
		elseif owned then
			status = "IM BESITZ"
			statusColor = Theme.Colors.Accent
		elseif item.LevelRequired and profile and profile.Level < item.LevelRequired then
			status = "AB LEVEL " .. item.LevelRequired
			statusColor = Theme.Colors.Danger
		else
			status = if item.Price == 0 then "GRATIS" else Util.FormatNumber(item.Price) .. " C"
			statusColor = Theme.Colors.Gold
		end
		Components.Label({
			Text = status,
			Font = Theme.Fonts.Title,
			TextSize = Theme.TextSize.Small,
			TextColor3 = statusColor,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.new(0, 6, 1, -30),
			Size = UDim2.new(1, -12, 0, 22),
			Parent = card,
		})
	end
	self:_renderDetail()
end

function Catalog:_renderDetail()
	local item = self.Selected
	if not item then
		self.ItemName.Text = ""
		self.ItemRarity.Text = ""
		self.ItemDescription.Text = ""
		self.ActionButton.Visible = false
		self:_destroyPreview()
		return
	end
	local rarity = CosmeticDefinitions.Rarities[item.Rarity]
	self.ItemName.Text = item.Name
	self.ItemRarity.Text = string.upper(rarity.Name) .. " · " .. string.upper(CosmeticDefinitions.CategoryNames[item.Category])
	self.ItemRarity.TextColor3 = rarity.Color
	local description = item.Description or ""
	if item.Category == "Trails" or item.Category == "Effects" then
		description ..= "\n(Trails und Partikel sind im Spiel sichtbar, nicht in der Vorschau.)"
	end
	self.ItemDescription.Text = description

	local owned = self:_owns(item.Category, item.Id)
	local equipped = self:_equipped(item.Category) == item.Id
	self.ActionButton.Visible = true
	if equipped then
		if CosmeticDefinitions.Unequippable[item.Category] then
			self.ActionButton.Text = "ABLEGEN"
			Components.SetButtonColor(self.ActionButton, Theme.Colors.PanelLight)
			self.ActionButton.TextColor3 = Theme.Colors.Text
		else
			self.ActionButton.Text = "AUSGERÜSTET"
			Components.SetButtonColor(self.ActionButton, Theme.Colors.Success)
			self.ActionButton.TextColor3 = Theme.Colors.Background
		end
	elseif owned then
		self.ActionButton.Text = "AUSRÜSTEN"
		Components.SetButtonColor(self.ActionButton, Theme.Colors.Accent)
		self.ActionButton.TextColor3 = Theme.Colors.Background
	else
		self.ActionButton.Text = if item.Price == 0 then "GRATIS HOLEN" else "KAUFEN · " .. Util.FormatNumber(item.Price) .. " C"
		Components.SetButtonColor(self.ActionButton, Theme.Colors.Gold)
		self.ActionButton.TextColor3 = Theme.Colors.Background
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
	self.Message.Text = "..."
	self.Message.TextColor3 = Theme.Colors.TextDim
	local ok, result = pcall(function()
		return Remotes.ShopRequest:InvokeServer(action, item.Category, item.Id)
	end)
	self.Busy = false
	if not ok or type(result) ~= "table" then
		self.Message.Text = "Verbindungsfehler – bitte erneut versuchen."
		self.Message.TextColor3 = Theme.Colors.Danger
		return
	end
	self.Message.Text = result.Message or ""
	self.Message.TextColor3 = if result.Ok then Theme.Colors.Success else Theme.Colors.Danger
	if result.Ok and action == "Buy" then
		-- Direkt nach dem Kauf ausrüsten (bequemer)
		pcall(function()
			Remotes.ShopRequest:InvokeServer("Equip", item.Category, item.Id)
		end)
	end
end

return Catalog
