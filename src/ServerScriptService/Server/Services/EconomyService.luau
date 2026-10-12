--[[
	EconomyService  (ModuleScript)
	Pfad: ServerScriptService/Server/Services/EconomyService

	Alle Coin- und XP-Transaktionen laufen ausschließlich hier über den Server.
	Clients können Guthaben weder setzen noch direkt verändern.

	Öffentliche API:
		:GetCoins(player) -> number
		:AddCoins(player, amount, reason) -> boolean
		:TrySpend(player, amount, reason) -> (boolean, string?)
		:AddXP(player, amount, reason) -> { LevelsGained, NewLevel, BonusCoins }
		:UpdateLeaderstats(player)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Progression = require(Shared.Progression)
local Remotes = require(Shared.Remotes)

local EconomyService = {}

local function validAmount(amount: any): boolean
	return type(amount) == "number"
		and amount == amount
		and amount >= 0
		and amount <= Config.Economy.MaxTransaction
		and math.floor(amount) == amount
end

function EconomyService:Init(services)
	self.Services = services
	self.Log = {} -- [player] = { {Time, Kind, Amount, Reason}, ... } (letzte 30)
end

function EconomyService:Start()
	self.Services.PlayerDataService.ProfileLoaded:Connect(function(player)
		self:UpdateLeaderstats(player)
	end)
end

function EconomyService:OnPlayerRemoving(player: Player)
	self.Log[player] = nil
end

function EconomyService:_log(player: Player, kind: string, amount: number, reason: string?)
	local log = self.Log[player]
	if not log then
		log = {}
		self.Log[player] = log
	end
	table.insert(log, { Time = os.time(), Kind = kind, Amount = amount, Reason = reason or "?" })
	if #log > 30 then
		table.remove(log, 1)
	end
end

function EconomyService:GetCoins(player: Player): number
	local profile = self.Services.PlayerDataService:GetProfile(player)
	return profile and profile.Coins or 0
end

function EconomyService:AddCoins(player: Player, amount: number, reason: string?): boolean
	if not validAmount(amount) then
		warn("[EconomyService] Ungültiger Betrag: " .. tostring(amount))
		return false
	end
	local data = self.Services.PlayerDataService
	local profile = data:GetProfile(player)
	if not profile then
		return false
	end
	profile.Coins = math.min(Config.Economy.MaxCoins, profile.Coins + amount)
	self:_log(player, "Add", amount, reason)
	data:MarkDirty(player)
	data:PushProfile(player)
	return true
end

function EconomyService:TrySpend(player: Player, amount: number, reason: string?): (boolean, string?)
	if not validAmount(amount) then
		return false, "Ungültiger Preis."
	end
	local data = self.Services.PlayerDataService
	local profile = data:GetProfile(player)
	if not profile then
		return false, "Profil noch nicht geladen."
	end
	if profile.Coins < amount then
		return false, string.format("Nicht genug Coins – dir fehlen %d.", amount - profile.Coins)
	end
	profile.Coins -= amount
	self:_log(player, "Spend", amount, reason)
	data:MarkDirty(player)
	data:PushProfile(player)
	return true
end

function EconomyService:AddXP(player: Player, amount: number, reason: string?)
	local result = { LevelsGained = 0, NewLevel = 1, BonusCoins = 0 }
	if not validAmount(amount) then
		return result
	end
	local data = self.Services.PlayerDataService
	local profile = data:GetProfile(player)
	if not profile then
		return result
	end
	local oldLevel = profile.Level
	profile.TotalXP += amount
	local newLevel = Progression.FromTotalXP(profile.TotalXP)
	profile.Level = newLevel
	result.NewLevel = newLevel
	if newLevel > oldLevel then
		result.LevelsGained = newLevel - oldLevel
		local bonus = 0
		for level = oldLevel + 1, newLevel do
			bonus += level * Config.Rewards.LevelUpCoinsPerLevel
		end
		result.BonusCoins = bonus
		profile.Coins = math.min(Config.Economy.MaxCoins, profile.Coins + bonus)
		self:_log(player, "LevelUp", bonus, "Level " .. newLevel)
		Remotes.GameEvent:FireClient(player, "LevelUp", { Level = newLevel, Coins = bonus })
		self:UpdateLeaderstats(player)
		local rewards = self.Services.RewardService
		if rewards then
			rewards:CheckAchievements(player)
		end
	end
	self:_log(player, "XP", amount, reason)
	data:MarkDirty(player)
	data:PushProfile(player)
	return result
end

--- Pflegt die Spielerliste (leaderstats: Level, Siege).
function EconomyService:UpdateLeaderstats(player: Player)
	local profile = self.Services.PlayerDataService:GetProfile(player)
	if not profile then
		return
	end
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		local level = Instance.new("IntValue")
		level.Name = "Level"
		level.Parent = stats
		local wins = Instance.new("IntValue")
		wins.Name = "Siege"
		wins.Parent = stats
		stats.Parent = player
	end
	stats.Level.Value = profile.Level
	stats.Siege.Value = profile.Stats.Wins
	player:SetAttribute("Level", profile.Level)
	player:SetAttribute("Rating", profile.Ranked.Rating)
	player:SetAttribute("Tier", Progression.GetTier(profile.Ranked.Rating).Name)
end

return EconomyService
