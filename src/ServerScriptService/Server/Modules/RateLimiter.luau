--[[
	RateLimiter  (ModuleScript)
	Pfad: ServerScriptService/Server/Modules/RateLimiter

	Token-Bucket pro Spieler. Begrenzt, wie oft ein Client ein Remote auslösen
	darf, ohne legitime Eingaben zu verwerfen.

	API:
		local limiter = RateLimiter.new(capacity, refillPerSecond)
		limiter:Check(player) -> boolean   (verbraucht ein Token)
		limiter:Remove(player)
		RateLimiter.ForRemote(name) -> limiter mit Werten aus Config.RateLimits
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local RateLimiter = {}
RateLimiter.__index = RateLimiter

local allLimiters = setmetatable({}, { __mode = "k" })

function RateLimiter.new(capacity: number, refillPerSecond: number)
	local self = setmetatable({
		Capacity = capacity,
		Refill = refillPerSecond,
		Buckets = {},
	}, RateLimiter)
	allLimiters[self] = true
	return self
end

function RateLimiter.ForRemote(name: string)
	local values = Config.RateLimits[name] or { 10, 5 }
	return RateLimiter.new(values[1], values[2])
end

function RateLimiter:Check(player: Player): boolean
	local now = os.clock()
	local bucket = self.Buckets[player]
	if not bucket then
		bucket = { Tokens = self.Capacity, Updated = now }
		self.Buckets[player] = bucket
	end
	bucket.Tokens = math.min(self.Capacity, bucket.Tokens + (now - bucket.Updated) * self.Refill)
	bucket.Updated = now
	if bucket.Tokens >= 1 then
		bucket.Tokens -= 1
		return true
	end
	if Config.Debug.LogRejections then
		warn(string.format("[RateLimiter] %s überschreitet das Limit", player.Name))
	end
	return false
end

function RateLimiter:Remove(player: Player)
	self.Buckets[player] = nil
end

Players.PlayerRemoving:Connect(function(player)
	for limiter in allLimiters do
		limiter:Remove(player)
	end
end)

return RateLimiter
