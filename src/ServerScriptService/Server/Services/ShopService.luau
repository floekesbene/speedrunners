--[[
	ShopService  (ModuleScript)
	Pfad: ServerScriptService/Server/Services/ShopService

	Verarbeitet Shop-Anfragen (RemoteFunction "ShopRequest"):
		("Buy", category, itemId)     -> kaufen (Coins prüfen, doppelte Käufe verhindern)
		("Equip", category, itemId)   -> ausrüsten (Besitz prüfen)
		("Unequip", category)         -> ablegen

	Rückgabe immer: { Ok = boolean, Message = string }

	Sicherheit:
		- Preis/Level kommen ausschließlich aus CosmeticDefinitions (Server).
		- Kauf läuft ohne Yield zwischen Prüfung und Abbuchung (atomar).
		- Pro Spieler Sperre gegen parallele Anfragen + Rate-Limit.
		- Kein Pay-to-Win: nur Kosmetik, nur Coins aus dem Spiel.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local CosmeticDefinitions = require(Shared.CosmeticDefinitions)
local Remotes = require(Shared.Remotes)

local RateLimiter = require(script.Parent.Parent.Modules.RateLimiter)

local ShopService = {}

function ShopService:Init(services)
	self.Services = services
	self.Busy = {}
	self.Limiter = RateLimiter.ForRemote("ShopRequest")
end

function ShopService:Start()
	Remotes.ShopRequest.OnServerInvoke = function(player, action, category, itemId)
		if not self.Limiter:Check(player) then
			return { Ok = false, Message = "Zu viele Anfragen – bitte kurz warten." }
		end
		if self.Busy[player] then
			return { Ok = false, Message = "Vorherige Anfrage läuft noch." }
		end
		self.Busy[player] = true
		local ok, result = pcall(function()
			return self:_handle(player, action, category, itemId)
		end)
		self.Busy[player] = nil
		if not ok then
			warn("[ShopService] Fehler: " .. tostring(result))
			return { Ok = false, Message = "Interner Fehler. Bitte erneut versuchen." }
		end
		return result
	end
end

function ShopService:OnPlayerRemoving(player: Player)
	self.Busy[player] = nil
end

function ShopService:_handle(player: Player, action: any, category: any, itemId: any)
	if type(action) ~= "string" or not CosmeticDefinitions.IsCategory(category) then
		return { Ok = false, Message = "Ungültige Anfrage." }
	end
	local inventory = self.Services.InventoryService
	if action == "Buy" then
		return self:_buy(player, category, itemId)
	elseif action == "Equip" then
		local ok, message = inventory:Equip(player, category, itemId)
		return { Ok = ok, Message = message or "Ausgerüstet." }
	elseif action == "Unequip" then
		local ok, message = inventory:Unequip(player, category)
		return { Ok = ok, Message = message or "Abgelegt." }
	end
	return { Ok = false, Message = "Unbekannte Aktion." }
end

function ShopService:_buy(player: Player, category: string, itemId: any)
	if type(itemId) ~= "string" then
		return { Ok = false, Message = "Ungültiges Item." }
	end
	local item = CosmeticDefinitions.Get(category, itemId)
	if not item then
		return { Ok = false, Message = "Dieses Item existiert nicht." }
	end
	local services = self.Services
	local profile = services.PlayerDataService:GetProfile(player)
	if not profile then
		return { Ok = false, Message = "Profil wird noch geladen." }
	end
	if services.InventoryService:Owns(player, category, itemId) then
		return { Ok = false, Message = "Du besitzt dieses Item bereits." }
	end
	if item.LevelRequired and profile.Level < item.LevelRequired then
		return { Ok = false, Message = string.format("Benötigt Level %d.", item.LevelRequired) }
	end
	local price = item.Price or 0
	-- Prüfung + Abbuchung + Gutschrift ohne Yield (atomar im Server-Thread)
	local ok, err = services.EconomyService:TrySpend(player, price, "Shop:" .. category .. ":" .. itemId)
	if not ok then
		return { Ok = false, Message = err or "Kauf fehlgeschlagen." }
	end
	services.InventoryService:Grant(player, category, itemId)
	services.RewardService:CheckAchievements(player)
	return { Ok = true, Message = string.format("%s gekauft!", item.Name) }
end

return ShopService
