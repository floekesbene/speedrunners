--[[
	InventoryService  (ModuleScript)
	Pfad: ServerScriptService/Server/Services/InventoryService

	Besitz und Ausrüstung kosmetischer Gegenstände. Jede Änderung wird
	serverseitig gegen CosmeticDefinitions validiert.

	Öffentliche API:
		:Owns(player, category, id) -> boolean
		:Grant(player, category, id) -> boolean        (nur intern, z.B. nach Kauf)
		:Equip(player, category, id) -> (boolean, string?)
		:Unequip(player, category) -> (boolean, string?)
		:GetEquipped(player) -> table
		:CountOwned(player) -> number
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local CosmeticDefinitions = require(Shared.CosmeticDefinitions)
local Util = require(Shared.Util)

local InventoryService = {}

function InventoryService:Init(services)
	self.Services = services
end

function InventoryService:Start() end

function InventoryService:Owns(player: Player, category: string, id: string): boolean
	local profile = self.Services.PlayerDataService:GetProfile(player)
	if not profile or not CosmeticDefinitions.IsCategory(category) then
		return false
	end
	local owned = profile.Owned[category]
	return owned ~= nil and owned[id] == true
end

function InventoryService:Grant(player: Player, category: string, id: string): boolean
	local data = self.Services.PlayerDataService
	local profile = data:GetProfile(player)
	if not profile or not CosmeticDefinitions.Get(category, id) then
		return false
	end
	profile.Owned[category][id] = true
	data:MarkDirty(player)
	data:PushProfile(player)
	return true
end

function InventoryService:Equip(player: Player, category: string, id: string): (boolean, string?)
	if not CosmeticDefinitions.IsCategory(category) or type(id) ~= "string" then
		return false, "Ungültige Anfrage."
	end
	if not CosmeticDefinitions.Get(category, id) then
		return false, "Dieses Item existiert nicht."
	end
	if not self:Owns(player, category, id) then
		return false, "Du besitzt dieses Item noch nicht."
	end
	local data = self.Services.PlayerDataService
	local profile = data:GetProfile(player)
	profile.Equipped[category] = id
	data:MarkDirty(player)
	data:PushProfile(player)
	self.Services.CharacterService:ApplyCosmetics(player)
	return true
end

function InventoryService:Unequip(player: Player, category: string): (boolean, string?)
	if not CosmeticDefinitions.IsCategory(category) then
		return false, "Ungültige Kategorie."
	end
	if not CosmeticDefinitions.Unequippable[category] then
		return false, "In dieser Kategorie muss immer etwas ausgerüstet sein."
	end
	local data = self.Services.PlayerDataService
	local profile = data:GetProfile(player)
	if not profile then
		return false, "Profil noch nicht geladen."
	end
	profile.Equipped[category] = ""
	data:MarkDirty(player)
	data:PushProfile(player)
	self.Services.CharacterService:ApplyCosmetics(player)
	return true
end

function InventoryService:GetEquipped(player: Player)
	local profile = self.Services.PlayerDataService:GetProfile(player)
	if not profile then
		return Util.DeepCopy(CosmeticDefinitions.DefaultEquipped)
	end
	return profile.Equipped
end

function InventoryService:CountOwned(player: Player): number
	local profile = self.Services.PlayerDataService:GetProfile(player)
	if not profile then
		return 0
	end
	local count = 0
	for _, owned in profile.Owned do
		count += Util.Count(owned)
	end
	return count
end

return InventoryService
