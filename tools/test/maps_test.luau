--[[
	maps_test.luau – baut alle Strecken im Mock und prüft die Spielbarkeit grob:
		- 8 Spawnpunkte, Ziellinie, Checkpoints, KillY unter der Strecke
		- jede Lücke ohne Boden (über alle Höhen) > 25 Studs (max. Sprungweite) braucht Greifhaken-Anker
		- keine Lücke > 95 Studs
		- Checkpoints liegen über festem Boden
	Aufruf: luau-runner --run tools/test/maps_test.luau <repo-root> <tree.luau>
]]

local ROOT = __args[1]
local TREE = __args[2]
local env = setmetatable({}, { __index = _G })
local Mock = __compile(__readfile(ROOT .. "/tools/test/mock.luau"), "mock", env)()
Mock.BuildTree(__compile(__readfile(TREE), "tree", env)())
Mock.Context = "server"

local Services = Mock.Services
local requireEnv = Mock.MakeEnv(Services.ServerScriptService)
local MapBuilder = requireEnv.require(Services.ServerScriptService.Server.Modules.MapBuilder)
local MapDefinitions = requireEnv.require(Services.ReplicatedStorage.Shared.MapDefinitions)
local templates = Services.ServerStorage.MapTemplates

local problems = 0
local function report(ok, text)
	if ok then
		print("  ✓ " .. text)
	else
		problems += 1
		print("  ✗ " .. text)
	end
end

local ids = table.clone(MapDefinitions.Order)
table.insert(ids, "Tutorial")
table.insert(ids, "Lobby")
for _, id in ids do
	local definition = MapDefinitions.GetAny(id)
	local builder = MapBuilder.new({
		Name = id,
		RegionId = id,
		MapId = id,
		Origin = Mock.Vector3.new(0, 0, 0),
		Theme = definition.Theme,
		Difficulty = definition.Difficulty or 2,
		Seed = definition.Seed,
	})
	requireEnv.require(templates:FindFirstChild(definition.Template))(builder)
	local map = builder:Result()
	local parts = #map.Model:GetDescendants()
	print(string.format("== %s: %d Instanzen, Länge %.0f, %d Checkpoints, %d Anker, %d Item-Spawns, %d Gefahren",
		id, parts, (map.FinishX or 0) - map.StartX, #map.Checkpoints, #map.Anchors, #map.PickupSpawns, #map.HazardFolder:GetChildren()))
	report(#map.Spawns >= 8, "mindestens 8 Spawnpunkte")
	report(parts < 6000, "Teileanzahl im Rahmen (" .. parts .. ")")
	if id ~= "Lobby" then
		report(map.FinishX ~= nil, "Ziellinie vorhanden")
		report(#map.Checkpoints >= 3, "Checkpoints vorhanden")
		-- Bodenabdeckung entlang X
		local floors = {}
		for _, part in map.Model.Geometry:GetChildren() do
			if part.Name == "Floor" or part.Name == "Ramp" then
				local p, s = part.Position, part.Size
				local halfX = if part.Name == "Ramp" then s.Z / 2 else s.X / 2
				table.insert(floors, { p.X - halfX, p.X + halfX, p.Y + s.Y / 2 })
			end
		end
		table.sort(floors, function(a, b)
			return a[1] < b[1]
		end)
		local coveredTo = map.StartX
		local gaps = {}
		for _, f in floors do
			if f[1] > coveredTo + 0.01 and coveredTo < map.FinishX then
				table.insert(gaps, { coveredTo, math.min(f[1], map.FinishX) })
			end
			coveredTo = math.max(coveredTo, f[2])
		end
		local maxGap = 0
		for _, gap in gaps do
			local width = gap[2] - gap[1]
			maxGap = math.max(maxGap, width)
			if width > 25 then
				local anchors = 0
				for _, anchor in map.Anchors do
					if anchor.Position.X > gap[1] - 15 and anchor.Position.X < gap[2] + 15 then
						anchors += 1
					end
				end
				report(anchors > 0, string.format("Lücke %.0f–%.0f (%.0f Studs) hat %d Anker", gap[1], gap[2], width, anchors))
			end
			if width > 95 then
				report(false, string.format("Lücke %.0f–%.0f zu breit", gap[1], gap[2]))
			end
		end
		print(string.format("  · größte Lücke: %.1f Studs, %d Lücken gesamt", maxGap, #gaps))
		-- Checkpoints über Boden
		for i, checkpoint in map.Checkpoints do
			local x = checkpoint.CFrame.Position.X
			local y = checkpoint.CFrame.Position.Y
			local supported = false
			for _, f in floors do
				if x >= f[1] and x <= f[2] and math.abs((y - 3) - f[3]) < 1.5 then
					supported = true
				end
			end
			report(supported, "Checkpoint " .. i .. " steht auf Boden")
		end
		report(map.KillY < map.Bounds.MinY, "KillY unterhalb der Strecke")
	end
end
print(string.format("\n%d Problem(e), %d Laufzeitfehler", problems, #Mock.Errors))
if problems > 0 or #Mock.Errors > 0 then
	error("Map-Prüfung fehlgeschlagen")
end
