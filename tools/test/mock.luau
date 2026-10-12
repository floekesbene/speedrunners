--[[
	mock.luau – Minimale Roblox-Laufzeitumgebung für automatisierte Tests
	außerhalb von Roblox Studio (ausgeführt mit tools/luau-runner).

	Nachgebildet: Instanzbaum, Attribute, Signale, task-Scheduler mit
	simulierter Zeit, Vector3/CFrame/Color3/UDim2 & Co., Remotes (Server und
	Client im selben Prozess, getrennte Modul-Caches), DataStores im Speicher,
	Spieler und LoadCharacter.

	NICHT nachgebildet: Physik, Rendering, echte Netzwerk-Latenz.
]]

local Mock = {}
Mock.Errors = {}
Mock.Warnings = {}
Mock.UnknownReads = {}
Mock.Log = {}
Mock.Time = 0
Mock.Context = "server"

local baseEnv = getfenv and getfenv(1) or _G
local realTypeof = typeof

------------------------------------------------------------------------
-- Scheduler
------------------------------------------------------------------------

local queue = {}
local threadContext = setmetatable({}, { __mode = "k" })

local function reportError(co, err)
	local trace = debug.traceback(co, tostring(err))
	table.insert(Mock.Errors, trace)
	print("[MOCK ERROR] " .. trace)
end

local function resume(co, ...)
	if coroutine.status(co) == "dead" then
		return
	end
	local previous = Mock.Context
	Mock.Context = threadContext[co] or previous
	local ok, err = coroutine.resume(co, ...)
	Mock.Context = previous
	if not ok then
		reportError(co, err)
	end
end

local function spawnThread(fn, ...)
	local co
	if type(fn) == "thread" then
		co = fn
	else
		co = coroutine.create(fn)
		threadContext[co] = Mock.Context
	end
	resume(co, ...)
	return co
end

local task = {}
function task.spawn(fn, ...)
	return spawnThread(fn, ...)
end
function task.defer(fn, ...)
	local co = if type(fn) == "thread" then fn else coroutine.create(fn)
	threadContext[co] = threadContext[co] or Mock.Context
	table.insert(queue, { Co = co, At = Mock.Time, Args = table.pack(...) })
	return co
end
function task.delay(t, fn, ...)
	local co = if type(fn) == "thread" then fn else coroutine.create(fn)
	threadContext[co] = threadContext[co] or Mock.Context
	table.insert(queue, { Co = co, At = Mock.Time + (t or 0), Args = table.pack(...) })
	return co
end
function task.wait(t)
	local co = coroutine.running()
	local start = Mock.Time
	table.insert(queue, { Co = co, At = Mock.Time + math.max(t or 0, 1 / 60), Waiting = true, Start = start })
	coroutine.yield()
	return Mock.Time - start
end
function task.cancel(co)
	for i = #queue, 1, -1 do
		if queue[i].Co == co then
			table.remove(queue, i)
		end
	end
end
Mock.task = task

local function runDue()
	local guard = 0
	while true do
		guard += 1
		if guard > 10000 then
			error("Scheduler-Endlosschleife")
		end
		local index = nil
		for i, entry in queue do
			if entry.At <= Mock.Time + 1e-9 and (not index or entry.At < queue[index].At) then
				index = i
			end
		end
		if not index then
			break
		end
		local entry = table.remove(queue, index)
		if entry.Waiting then
			resume(entry.Co, Mock.Time - entry.Start)
		else
			resume(entry.Co, table.unpack(entry.Args, 1, entry.Args.n))
		end
	end
end

------------------------------------------------------------------------
-- Signale
------------------------------------------------------------------------

local SignalClass = {}
SignalClass.__index = SignalClass
SignalClass.__type = "RBXScriptSignal"

local function newSignal()
	return setmetatable({ Handlers = {} }, SignalClass)
end
Mock.NewSignal = newSignal

function SignalClass:Connect(fn)
	local handler = { Fn = fn, Connected = true, Context = Mock.Context }
	table.insert(self.Handlers, handler)
	local signal = self
	local conn = { Connected = true }
	function conn.Disconnect()
		handler.Connected = false
		conn.Connected = false
		local i = table.find(signal.Handlers, handler)
		if i then
			table.remove(signal.Handlers, i)
		end
	end
	conn.disconnect = conn.Disconnect
	return setmetatable(conn, { __index = function(_, k)
		if k == "Disconnect" then
			return conn.Disconnect
		end
		return nil
	end })
end
function SignalClass:Once(fn)
	local conn
	conn = self:Connect(function(...)
		conn.Disconnect()
		fn(...)
	end)
	return conn
end
function SignalClass:Wait()
	local co = coroutine.running()
	self:Once(function(...)
		task.spawn(co, ...)
	end)
	return coroutine.yield()
end
function SignalClass:Fire(...)
	for _, handler in table.clone(self.Handlers) do
		if handler.Connected then
			local co = coroutine.create(handler.Fn)
			threadContext[co] = handler.Context
			resume(co, ...)
		end
	end
end

------------------------------------------------------------------------
-- Werttypen
------------------------------------------------------------------------

local function typed(name)
	local mt = { __type = name }
	return mt
end

-- Vector3
local Vector3 = {}
local V3 = typed("Vector3")
local function v3(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3)
end
V3.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		if m == 0 then
			return v3(0, 0, 0)
		end
		return v3(v.X / m, v.Y / m, v.Z / m)
	elseif k == "x" then
		return v.X
	elseif k == "y" then
		return v.Y
	elseif k == "z" then
		return v.Z
	end
	return Vector3[k]
end
V3.__add = function(a, b)
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3.__sub = function(a, b)
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3.__mul = function(a, b)
	if type(a) == "number" then
		return v3(a * b.X, a * b.Y, a * b.Z)
	elseif type(b) == "number" then
		return v3(a.X * b, a.Y * b, a.Z * b)
	end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3.__div = function(a, b)
	if type(b) == "number" then
		return v3(a.X / b, a.Y / b, a.Z / b)
	end
	return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3.__unm = function(a)
	return v3(-a.X, -a.Y, -a.Z)
end
V3.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V3.__tostring = function(v)
	return string.format("%g, %g, %g", v.X, v.Y, v.Z)
end
function Vector3.new(x, y, z)
	return v3(x, y, z)
end
function Vector3.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function Vector3.Cross(a, b)
	return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function Vector3.Lerp(a, b, t)
	return a + (b - a) * t
end
function Vector3.Max(a, b)
	return v3(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z))
end
function Vector3.Min(a, b)
	return v3(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z))
end
function Vector3.Abs(a)
	return v3(math.abs(a.X), math.abs(a.Y), math.abs(a.Z))
end
Vector3.zero = v3(0, 0, 0)
Vector3.one = v3(1, 1, 1)
Vector3.xAxis = v3(1, 0, 0)
Vector3.yAxis = v3(0, 1, 0)
Vector3.zAxis = v3(0, 0, 1)
Mock.Vector3 = Vector3

-- Vector2
local Vector2 = {}
local V2 = typed("Vector2")
local function v2(x, y)
	return setmetatable({ X = x or 0, Y = y or 0 }, V2)
end
V2.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y)
	elseif k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y)
		return if m == 0 then v2(0, 0) else v2(v.X / m, v.Y / m)
	end
	return Vector2[k]
end
V2.__add = function(a, b)
	return v2(a.X + b.X, a.Y + b.Y)
end
V2.__sub = function(a, b)
	return v2(a.X - b.X, a.Y - b.Y)
end
V2.__mul = function(a, b)
	if type(a) == "number" then
		return v2(a * b.X, a * b.Y)
	elseif type(b) == "number" then
		return v2(a.X * b, a.Y * b)
	end
	return v2(a.X * b.X, a.Y * b.Y)
end
V2.__div = function(a, b)
	if type(b) == "number" then
		return v2(a.X / b, a.Y / b)
	end
	return v2(a.X / b.X, a.Y / b.Y)
end
V2.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
function Vector2.new(x, y)
	return v2(x, y)
end
Vector2.zero = v2(0, 0)
Vector2.one = v2(1, 1)

-- CFrame
local CFrame = {}
local CF = typed("CFrame")
local function cf(x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
	return setmetatable({
		x = x, y = y, z = z,
		r00 = r00 or 1, r01 = r01 or 0, r02 = r02 or 0,
		r10 = r10 or 0, r11 = r11 or 1, r12 = r12 or 0,
		r20 = r20 or 0, r21 = r21 or 0, r22 = r22 or 1,
	}, CF)
end
local function cfMulPoint(c, p)
	return v3(
		c.r00 * p.X + c.r01 * p.Y + c.r02 * p.Z + c.x,
		c.r10 * p.X + c.r11 * p.Y + c.r12 * p.Z + c.y,
		c.r20 * p.X + c.r21 * p.Y + c.r22 * p.Z + c.z
	)
end
local function cfMul(a, b)
	return cf(
		a.r00 * b.x + a.r01 * b.y + a.r02 * b.z + a.x,
		a.r10 * b.x + a.r11 * b.y + a.r12 * b.z + a.y,
		a.r20 * b.x + a.r21 * b.y + a.r22 * b.z + a.z,
		a.r00 * b.r00 + a.r01 * b.r10 + a.r02 * b.r20,
		a.r00 * b.r01 + a.r01 * b.r11 + a.r02 * b.r21,
		a.r00 * b.r02 + a.r01 * b.r12 + a.r02 * b.r22,
		a.r10 * b.r00 + a.r11 * b.r10 + a.r12 * b.r20,
		a.r10 * b.r01 + a.r11 * b.r11 + a.r12 * b.r21,
		a.r10 * b.r02 + a.r11 * b.r12 + a.r12 * b.r22,
		a.r20 * b.r00 + a.r21 * b.r10 + a.r22 * b.r20,
		a.r20 * b.r01 + a.r21 * b.r11 + a.r22 * b.r21,
		a.r20 * b.r02 + a.r21 * b.r12 + a.r22 * b.r22
	)
end
local function cfInverse(c)
	-- Rotation transponieren
	local r00, r01, r02 = c.r00, c.r10, c.r20
	local r10, r11, r12 = c.r01, c.r11, c.r21
	local r20, r21, r22 = c.r02, c.r12, c.r22
	local x = -(r00 * c.x + r01 * c.y + r02 * c.z)
	local y = -(r10 * c.x + r11 * c.y + r12 * c.z)
	local z = -(r20 * c.x + r21 * c.y + r22 * c.z)
	return cf(x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
end
CF.__index = function(c, k)
	if k == "Position" or k == "p" then
		return v3(c.x, c.y, c.z)
	elseif k == "X" then
		return c.x
	elseif k == "Y" then
		return c.y
	elseif k == "Z" then
		return c.z
	elseif k == "LookVector" then
		return v3(-c.r02, -c.r12, -c.r22)
	elseif k == "RightVector" then
		return v3(c.r00, c.r10, c.r20)
	elseif k == "UpVector" then
		return v3(c.r01, c.r11, c.r21)
	elseif k == "Rotation" then
		return cf(0, 0, 0, c.r00, c.r01, c.r02, c.r10, c.r11, c.r12, c.r20, c.r21, c.r22)
	end
	return CFrame[k]
end
CF.__mul = function(a, b)
	if getmetatable(b) == V3 then
		return cfMulPoint(a, b)
	end
	return cfMul(a, b)
end
CF.__add = function(a, b)
	return cf(a.x + b.X, a.y + b.Y, a.z + b.Z, a.r00, a.r01, a.r02, a.r10, a.r11, a.r12, a.r20, a.r21, a.r22)
end
CF.__sub = function(a, b)
	return cf(a.x - b.X, a.y - b.Y, a.z - b.Z, a.r00, a.r01, a.r02, a.r10, a.r11, a.r12, a.r20, a.r21, a.r22)
end
function CFrame.new(a, b, c, ...)
	if a == nil then
		return cf(0, 0, 0)
	end
	if type(a) == "table" then
		if b then
			return CFrame.lookAt(a, b)
		end
		return cf(a.X, a.Y, a.Z)
	end
	if select("#", ...) == 9 then
		return cf(a, b, c, ...)
	end
	return cf(a, b, c)
end
function CFrame.lookAt(pos, target, up)
	up = up or v3(0, 1, 0)
	local look = (target - pos).Unit
	if look.Magnitude == 0 then
		return cf(pos.X, pos.Y, pos.Z)
	end
	local right = Vector3.Cross(look, up).Unit
	if right.Magnitude == 0 then
		right = v3(1, 0, 0)
	end
	local upv = Vector3.Cross(right, look)
	-- Spalten: Right, Up, -Look
	return cf(pos.X, pos.Y, pos.Z, right.X, upv.X, -look.X, right.Y, upv.Y, -look.Y, right.Z, upv.Z, -look.Z)
end
function CFrame.Angles(rx, ry, rz)
	local cx, sx = math.cos(rx), math.sin(rx)
	local cy, sy = math.cos(ry), math.sin(ry)
	local cz, sz = math.cos(rz), math.sin(rz)
	local Rx = cf(0, 0, 0, 1, 0, 0, 0, cx, -sx, 0, sx, cx)
	local Ry = cf(0, 0, 0, cy, 0, sy, 0, 1, 0, -sy, 0, cy)
	local Rz = cf(0, 0, 0, cz, -sz, 0, sz, cz, 0, 0, 0, 1)
	return cfMul(cfMul(Rx, Ry), Rz)
end
CFrame.fromEulerAnglesXYZ = CFrame.Angles
function CFrame.Inverse(c)
	return cfInverse(c)
end
function CFrame.PointToObjectSpace(c, p)
	return cfMulPoint(cfInverse(c), p)
end
function CFrame.PointToWorldSpace(c, p)
	return cfMulPoint(c, p)
end
function CFrame.ToObjectSpace(a, b)
	return cfMul(cfInverse(a), b)
end
function CFrame.ToWorldSpace(a, b)
	return cfMul(a, b)
end
function CFrame.Lerp(a, b, t)
	local src = if t < 0.5 then a else b
	return cf(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t, src.r00, src.r01, src.r02, src.r10, src.r11, src.r12, src.r20, src.r21, src.r22)
end
function CFrame.GetComponents(c)
	return c.x, c.y, c.z, c.r00, c.r01, c.r02, c.r10, c.r11, c.r12, c.r20, c.r21, c.r22
end
CFrame.identity = cf(0, 0, 0)
Mock.CFrame = CFrame

-- Color3
local Color3 = {}
local C3 = typed("Color3")
C3.__index = Color3
C3.__eq = function(a, b)
	return a.R == b.R and a.G == b.G and a.B == b.B
end
function Color3.new(r, g, b)
	return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, C3)
end
function Color3.fromRGB(r, g, b)
	return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end
function Color3.fromHSV(h, s, v)
	return Color3.new(v, v * (1 - s), v * (1 - s * h))
end
function Color3.Lerp(a, b, t)
	return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end

-- UDim / UDim2
local UDim = {}
local UD = typed("UDim")
UD.__index = UDim
function UDim.new(s, o)
	return setmetatable({ Scale = s or 0, Offset = o or 0 }, UD)
end
local UDim2 = {}
local UD2 = typed("UDim2")
UD2.__index = UDim2
UD2.__add = function(a, b)
	return UDim2.new(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset)
end
function UDim2.new(xs, xo, ys, yo)
	return setmetatable({ X = UDim.new(xs, xo), Y = UDim.new(ys, yo), Width = UDim.new(xs, xo), Height = UDim.new(ys, yo) }, UD2)
end
function UDim2.fromScale(x, y)
	return UDim2.new(x, 0, y, 0)
end
function UDim2.fromOffset(x, y)
	return UDim2.new(0, x, 0, y)
end

local function simpleType(name, fields)
	local T = {}
	local mt = typed(name)
	mt.__index = T
	function T.new(...)
		local args = table.pack(...)
		local obj = {}
		for i, field in fields do
			obj[field] = args[i]
		end
		obj.Args = args
		return setmetatable(obj, mt)
	end
	return T
end
local NumberSequence = simpleType("NumberSequence", { "Value" })
local NumberSequenceKeypoint = simpleType("NumberSequenceKeypoint", { "Time", "Value" })
local ColorSequence = simpleType("ColorSequence", { "Value" })
local ColorSequenceKeypoint = simpleType("ColorSequenceKeypoint", { "Time", "Value" })
local NumberRange = simpleType("NumberRange", { "Min", "Max" })
local PhysicalProperties = simpleType("PhysicalProperties", { "Density", "Friction", "Elasticity" })
local TweenInfo = simpleType("TweenInfo", { "Time", "EasingStyle", "EasingDirection" })
local Rect = simpleType("Rect", { "Min", "Max" })

-- Random
local Random = {}
local RND = typed("Random")
RND.__index = Random
function Random.new(seed)
	return setmetatable({ State = (seed or 12345) % 2147483647 + 1 }, RND)
end
function Random:_next()
	self.State = (self.State * 48271) % 2147483647
	return self.State / 2147483647
end
function Random:NextNumber(a, b)
	local r = self:_next()
	if a then
		return a + (b - a) * r
	end
	return r
end
function Random:NextInteger(a, b)
	return math.floor(a + (b - a + 1) * self:_next())
end

-- Enum
local enumCache = {}
local EnumItemMT = typed("EnumItem")
EnumItemMT.__index = function(item, k)
	if k == "Value" then
		return 0
	end
	return nil
end
EnumItemMT.__tostring = function(item)
	return "Enum." .. item.EnumType .. "." .. item.Name
end
local Enum = setmetatable({}, {
	__index = function(_, enumName)
		local enumTable = enumCache[enumName]
		if not enumTable then
			local items = {}
			enumTable = setmetatable({}, {
				__index = function(_, itemName)
					if itemName == "GetEnumItems" then
						return function()
							return {}
						end
					end
					local item = items[itemName]
					if not item then
						item = setmetatable({ Name = itemName, EnumType = enumName }, EnumItemMT)
						items[itemName] = item
					end
					return item
				end,
			})
			enumCache[enumName] = enumTable
		end
		return enumTable
	end,
})

-- RaycastParams / OverlapParams
local RaycastParams = simpleType("RaycastParams", {})
local OverlapParams = simpleType("OverlapParams", {})

local function mockTypeof(value)
	if type(value) == "table" then
		local mt = getmetatable(value)
		if mt and mt.__type then
			return mt.__type
		end
		if rawget(value, "__instance") then
			return "Instance"
		end
	end
	return realTypeof(value)
end

------------------------------------------------------------------------
-- Instanzen
------------------------------------------------------------------------

local HIERARCHY = {
	Part = "BasePart",
	WedgePart = "BasePart",
	MeshPart = "BasePart",
	TrussPart = "BasePart",
	SpawnLocation = "Part",
	BasePart = "PVInstance",
	Model = "PVInstance",
	Workspace = "Model",
	WorldModel = "Model",
	PVInstance = "Instance",
	Script = "BaseScript",
	LocalScript = "Script",
	BaseScript = "LuaSourceContainer",
	ModuleScript = "LuaSourceContainer",
	Frame = "GuiObject",
	TextLabel = "GuiObject",
	TextButton = "GuiButton",
	ImageLabel = "GuiObject",
	ImageButton = "GuiButton",
	GuiButton = "GuiObject",
	ScrollingFrame = "GuiObject",
	ViewportFrame = "GuiObject",
	CanvasGroup = "GuiObject",
	TextBox = "GuiObject",
	GuiObject = "GuiBase2d",
	ScreenGui = "LayerCollector",
	BillboardGui = "LayerCollector",
	SurfaceGui = "LayerCollector",
	LayerCollector = "GuiBase2d",
	Motor6D = "JointInstance",
	Weld = "JointInstance",
	JointInstance = "Instance",
	RemoteEvent = "Instance",
	Configuration = "Instance",
	IntValue = "ValueBase",
	StringValue = "ValueBase",
	NumberValue = "ValueBase",
}

local function isA(className, target)
	local current = className
	while current do
		if current == target then
			return true
		end
		current = HIERARCHY[current]
	end
	return target == "Instance"
end

local DEFAULTS = {
	Name = nil,
	Archivable = true,
	Transparency = 0,
	Anchored = false,
	CanCollide = true,
	CanQuery = true,
	CanTouch = true,
	Massless = false,
	Size = v3(4, 1, 2),
	AssemblyLinearVelocity = v3(0, 0, 0),
	AssemblyAngularVelocity = v3(0, 0, 0),
	CollisionGroup = "Default",
	Visible = true,
	Enabled = true,
	BackgroundTransparency = 0,
	TextTransparency = 0,
	Text = "",
	Rotation = 0,
	LayoutOrder = 0,
	ZIndex = 1,
	Health = 100,
	MaxHealth = 100,
	Volume = 0.5,
	PlaybackSpeed = 1,
	Looped = false,
	Scale = 1,
	FieldOfView = 70,
	TextSize = 14,
	Value = 0,
	AbsolutePosition = v2(0, 0),
	AbsoluteSize = v2(100, 30),
	Adornee = nil,
	PrimaryPart = nil,
	Parent = nil,
	Character = nil,
	Gravity = 196.2,
}

local EVENTS = {
	ChildAdded = true, ChildRemoved = true, DescendantAdded = true, DescendantRemoving = true,
	AncestryChanged = true, Destroying = true, Changed = true, Died = true, CharacterAdded = true,
	CharacterRemoving = true, OnServerEvent = true, OnClientEvent = true, Event = true, Ended = true,
	Completed = true, Touched = true, TouchEnded = true, Activated = true, MouseButton1Click = true,
	MouseButton1Down = true, MouseButton1Up = true, MouseEnter = true, MouseLeave = true,
	InputBegan = true, InputEnded = true, InputChanged = true, PlayerAdded = true, PlayerRemoving = true,
	Heartbeat = true, PreSimulation = true, PostSimulation = true, RenderStepped = true, Stepped = true,
	LastInputTypeChanged = true, WindowFocusReleased = true, WindowFocused = true, SelectionGained = true,
	FocusLost = true, Played = true, StateChanged = true, Running = true,
}

local Methods = {}
local ClassMethods = {}

local InstanceMT = { __type = "Instance" }
local allInstances = setmetatable({}, { __mode = "k" })

local function newInstance(className)
	local obj = setmetatable({}, InstanceMT)
	rawset(obj, "__instance", true)
	rawset(obj, "_class", className)
	rawset(obj, "_props", { Name = className })
	rawset(obj, "_children", {})
	rawset(obj, "_attrs", {})
	rawset(obj, "_signals", {})
	rawset(obj, "_attrSignals", {})
	rawset(obj, "_propSignals", {})
	rawset(obj, "_tags", {})
	allInstances[obj] = true
	return obj
end

local function getSignal(obj, name)
	local signals = rawget(obj, "_signals")
	local s = signals[name]
	if not s then
		s = newSignal()
		signals[name] = s
	end
	return s
end
Mock.GetSignal = getSignal

InstanceMT.__index = function(obj, key)
	local class = rawget(obj, "_class")
	local cm = ClassMethods[class]
	if cm and cm[key] ~= nil then
		return cm[key]
	end
	if Methods[key] then
		return Methods[key]
	end
	if key == "ClassName" then
		return class
	end
	local props = rawget(obj, "_props")
	if key == "Position" and props.CFrame then
		return props.CFrame.Position
	end
	if props[key] ~= nil then
		return props[key]
	end
	if EVENTS[key] then
		return getSignal(obj, key)
	end
	for _, child in rawget(obj, "_children") do
		if rawget(child, "_props").Name == key then
			return child
		end
	end
	if key == "CFrame" and isA(class, "BasePart") then
		return CFrame.identity
	end
	if key == "Position" and isA(class, "BasePart") then
		return v3(0, 0, 0)
	end
	if DEFAULTS[key] ~= nil then
		return DEFAULTS[key]
	end
	local id = class .. "." .. tostring(key)
	Mock.UnknownReads[id] = (Mock.UnknownReads[id] or 0) + 1
	return nil
end

local function setParent(obj, parent)
	local props = rawget(obj, "_props")
	local old = props.Parent
	if old == parent then
		return
	end
	if old then
		local list = rawget(old, "_children")
		local i = table.find(list, obj)
		if i then
			table.remove(list, i)
		end
		getSignal(old, "ChildRemoved"):Fire(obj)
	end
	props.Parent = parent
	if parent then
		table.insert(rawget(parent, "_children"), obj)
		getSignal(parent, "ChildAdded"):Fire(obj)
		local ancestor = parent
		while ancestor do
			getSignal(ancestor, "DescendantAdded"):Fire(obj)
			ancestor = rawget(ancestor, "_props").Parent
		end
	end
	getSignal(obj, "AncestryChanged"):Fire(obj, parent)
end

InstanceMT.__newindex = function(obj, key, value)
	local props = rawget(obj, "_props")
	if rawget(obj, "_destroyed") and key == "Parent" and value ~= nil then
		error("The Parent property of " .. tostring(props.Name) .. " is locked (destroyed)")
	end
	if key == "Parent" then
		setParent(obj, value)
	elseif key == "Position" and isA(rawget(obj, "_class"), "BasePart") then
		local current = props.CFrame or CFrame.identity
		props.CFrame = cf(value.X, value.Y, value.Z, current.r00, current.r01, current.r02, current.r10, current.r11, current.r12, current.r20, current.r21, current.r22)
	else
		props[key] = value
	end
	local s = rawget(obj, "_propSignals")[key]
	if s then
		s:Fire()
	end
end

InstanceMT.__tostring = function(obj)
	return tostring(rawget(obj, "_props").Name)
end

function Methods.IsA(obj, className)
	return isA(rawget(obj, "_class"), className)
end
function Methods.GetChildren(obj)
	return table.clone(rawget(obj, "_children"))
end
function Methods.GetDescendants(obj)
	local result = {}
	local function walk(o)
		for _, child in rawget(o, "_children") do
			table.insert(result, child)
			walk(child)
		end
	end
	walk(obj)
	return result
end
function Methods.FindFirstChild(obj, name, recursive)
	for _, child in rawget(obj, "_children") do
		if rawget(child, "_props").Name == name then
			return child
		end
	end
	if recursive then
		for _, child in rawget(obj, "_children") do
			local found = Methods.FindFirstChild(child, name, true)
			if found then
				return found
			end
		end
	end
	return nil
end
function Methods.FindFirstChildOfClass(obj, className)
	for _, child in rawget(obj, "_children") do
		if rawget(child, "_class") == className then
			return child
		end
	end
	return nil
end
function Methods.FindFirstChildWhichIsA(obj, className)
	for _, child in rawget(obj, "_children") do
		if isA(rawget(child, "_class"), className) then
			return child
		end
	end
	return nil
end
function Methods.FindFirstAncestorOfClass(obj, className)
	local p = rawget(obj, "_props").Parent
	while p do
		if rawget(p, "_class") == className then
			return p
		end
		p = rawget(p, "_props").Parent
	end
	return nil
end
function Methods.WaitForChild(obj, name, timeout)
	local found = Methods.FindFirstChild(obj, name)
	if found then
		return found
	end
	local deadline = Mock.Time + (timeout or 10)
	while Mock.Time < deadline do
		task.wait(0.05)
		found = Methods.FindFirstChild(obj, name)
		if found then
			return found
		end
	end
	if not timeout then
		table.insert(Mock.Warnings, "Infinite yield possible on " .. tostring(obj) .. ":WaitForChild(" .. name .. ")")
	end
	return nil
end
function Methods.IsDescendantOf(obj, ancestor)
	local p = rawget(obj, "_props").Parent
	while p do
		if p == ancestor then
			return true
		end
		p = rawget(p, "_props").Parent
	end
	return false
end
function Methods.IsAncestorOf(obj, descendant)
	return Methods.IsDescendantOf(descendant, obj)
end
function Methods.Destroy(obj)
	if rawget(obj, "_destroyed") then
		return
	end
	getSignal(obj, "Destroying"):Fire()
	for _, child in table.clone(rawget(obj, "_children")) do
		Methods.Destroy(child)
	end
	setParent(obj, nil)
	rawset(obj, "_destroyed", true)
	for _, s in rawget(obj, "_signals") do
		table.clear(s.Handlers)
	end
	Mock.OnDestroy(obj)
end
function Methods.ClearAllChildren(obj)
	for _, child in table.clone(rawget(obj, "_children")) do
		Methods.Destroy(child)
	end
end
function Methods.Clone(obj)
	local map = {}
	local function copy(o)
		local c = newInstance(rawget(o, "_class"))
		map[o] = c
		for k, v in rawget(o, "_props") do
			if k ~= "Parent" then
				rawget(c, "_props")[k] = v
			end
		end
		for k, v in rawget(o, "_attrs") do
			rawget(c, "_attrs")[k] = v
		end
		for k, v in rawget(o, "_tags") do
			rawget(c, "_tags")[k] = v
		end
		for _, child in rawget(o, "_children") do
			local cc = copy(child)
			rawget(cc, "_props").Parent = c
			table.insert(rawget(c, "_children"), cc)
		end
		return c
	end
	local result = copy(obj)
	-- Referenzen (Part0/Part1/PrimaryPart/Attachment0…) umbiegen
	for original, clone in map do
		for k, v in rawget(clone, "_props") do
			if type(v) == "table" and rawget(v, "__instance") and map[v] and k ~= "Parent" then
				rawget(clone, "_props")[k] = map[v]
			end
		end
		local _ = original
	end
	return result
end
function Methods.SetAttribute(obj, name, value)
	assert(type(name) == "string", "Attributname muss string sein")
	local vt = mockTypeof(value)
	local allowed = {
		["nil"] = true, string = true, boolean = true, number = true, Vector3 = true, Vector2 = true,
		Color3 = true, UDim = true, UDim2 = true, CFrame = true, NumberSequence = true, ColorSequence = true,
		NumberRange = true, Rect = true, BrickColor = true, EnumItem = true, Font = true,
	}
	if not allowed[vt] then
		error("SetAttribute: Typ " .. vt .. " wird nicht unterstützt (" .. name .. ")")
	end
	local attrs = rawget(obj, "_attrs")
	if attrs[name] == value then
		return
	end
	attrs[name] = value
	local s = rawget(obj, "_attrSignals")[name]
	if s then
		s:Fire()
	end
end
function Methods.GetAttribute(obj, name)
	return rawget(obj, "_attrs")[name]
end
function Methods.GetAttributes(obj)
	return table.clone(rawget(obj, "_attrs"))
end
function Methods.GetAttributeChangedSignal(obj, name)
	local signals = rawget(obj, "_attrSignals")
	if not signals[name] then
		signals[name] = newSignal()
	end
	return signals[name]
end
function Methods.GetPropertyChangedSignal(obj, name)
	local signals = rawget(obj, "_propSignals")
	if not signals[name] then
		signals[name] = newSignal()
	end
	return signals[name]
end
function Methods.GetFullName(obj)
	local names = {}
	local o = obj
	while o do
		table.insert(names, 1, rawget(o, "_props").Name)
		o = rawget(o, "_props").Parent
	end
	return table.concat(names, ".")
end
function Methods.AddTag(obj, tag)
	Mock.CollectionService:AddTag(obj, tag)
end
function Methods.HasTag(obj, tag)
	return rawget(obj, "_tags")[tag] == true
end
function Methods.RemoveTag(obj, tag)
	Mock.CollectionService:RemoveTag(obj, tag)
end
function Methods.GetTags(obj)
	local list = {}
	for tag in rawget(obj, "_tags") do
		table.insert(list, tag)
	end
	return list
end

-- PVInstance
local function pivotTo(obj, target)
	local class = rawget(obj, "_class")
	if isA(class, "BasePart") then
		obj.CFrame = target
		return
	end
	local primary = obj.PrimaryPart
	local current = if primary then primary.CFrame else CFrame.identity
	local delta = cfMul(target, cfInverse(current))
	for _, d in Methods.GetDescendants(obj) do
		if isA(rawget(d, "_class"), "BasePart") then
			rawget(d, "_props").CFrame = cfMul(delta, d.CFrame)
		end
	end
end
function Methods.PivotTo(obj, target)
	pivotTo(obj, target)
end
function Methods.GetPivot(obj)
	if isA(rawget(obj, "_class"), "BasePart") then
		return obj.CFrame
	end
	local primary = obj.PrimaryPart
	return if primary then primary.CFrame else CFrame.identity
end
function Methods.SetNetworkOwner() end
function Methods.GetNetworkOwner()
	return nil
end
function Methods.Emit() end
function Methods.Play(obj)
	if rawget(obj, "_class") == "Sound" then
		task.delay(0.5, function()
			getSignal(obj, "Ended"):Fire()
		end)
	end
end
function Methods.Stop() end
function Methods.Pause() end

-- Humanoid
ClassMethods.Humanoid = {
	SetStateEnabled = function() end,
	ChangeState = function() end,
	GetState = function()
		return Enum.HumanoidStateType.Physics
	end,
	TakeDamage = function(h, amount)
		h.Health = math.max(0, h.Health - amount)
		if h.Health <= 0 then
			getSignal(h, "Died"):Fire()
		end
	end,
	LoadAnimation = function()
		error("LoadAnimation sollte nicht verwendet werden")
	end,
}

-- Camera
ClassMethods.Camera = {
	WorldToViewportPoint = function(camera, position)
		local cframe = camera.CFrame or CFrame.identity
		local relative = cframe:PointToObjectSpace(position)
		local viewport = camera.ViewportSize or v2(1280, 720)
		local depth = -relative.Z
		if depth <= 0.01 then
			return v3(viewport.X / 2 - relative.X * 50, viewport.Y / 2, depth), false
		end
		local f = (viewport.Y / 2) / math.tan(math.rad((camera.FieldOfView or 70) / 2))
		local x = viewport.X / 2 + relative.X / depth * f
		local y = viewport.Y / 2 - relative.Y / depth * f
		local onScreen = x >= 0 and x <= viewport.X and y >= 0 and y <= viewport.Y
		return v3(x, y, depth), onScreen
	end,
}

-- Remotes
ClassMethods.RemoteEvent = {
	FireServer = function(remote, ...)
		local player = Mock.CurrentClientPlayer
		assert(Mock.Context == "client", "FireServer nur vom Client")
		local args = table.pack(...)
		local previous = Mock.Context
		Mock.Context = "server"
		getSignal(remote, "OnServerEvent"):Fire(player, table.unpack(args, 1, args.n))
		Mock.Context = previous
	end,
	FireClient = function(remote, player, ...)
		assert(Mock.Context == "server", "FireClient nur vom Server: " .. tostring(remote))
		assert(player ~= nil, "FireClient ohne Spieler")
		table.insert(Mock.Log, { Remote = remote.Name, Player = player, Args = table.pack(...) })
		Mock.DeliverToClient(remote, player, ...)
	end,
	FireAllClients = function(remote, ...)
		assert(Mock.Context == "server", "FireAllClients nur vom Server")
		table.insert(Mock.Log, { Remote = remote.Name, Player = "all", Args = table.pack(...) })
		for _, player in Mock.Players:GetPlayers() do
			Mock.DeliverToClient(remote, player, ...)
		end
	end,
}
ClassMethods.RemoteFunction = {
	InvokeServer = function(remote, ...)
		local player = Mock.CurrentClientPlayer
		local handler = remote.OnServerInvoke
		assert(handler, "OnServerInvoke fehlt für " .. remote.Name)
		local previous = Mock.Context
		Mock.Context = "server"
		local result = table.pack(pcall(handler, player, ...))
		Mock.Context = previous
		if not result[1] then
			error(result[2])
		end
		return table.unpack(result, 2, result.n)
	end,
}
ClassMethods.BindableEvent = {
	Fire = function(b, ...)
		getSignal(b, "Event"):Fire(...)
	end,
}

-- Player
ClassMethods.Player = {
	Kick = function(player, message)
		table.insert(Mock.Log, { Remote = "Kick", Player = player, Args = table.pack(message) })
		print("[MOCK] Kick " .. player.Name .. ": " .. tostring(message))
		Mock.RemovePlayer(player)
	end,
	LoadCharacter = function(player)
		assert(Mock.Context == "server", "LoadCharacter nur vom Server")
		local template = Mock.StarterPlayer:FindFirstChild("StarterCharacter")
		assert(template, "StarterCharacter fehlt")
		local old = player.Character
		if old then
			old:Destroy()
		end
		task.wait(0.05)
		local character = template:Clone()
		character.Name = player.Name
		local scripts = Mock.StarterPlayer:FindFirstChild("StarterCharacterScripts")
		if scripts then
			for _, s in scripts:GetChildren() do
				s:Clone().Parent = character
			end
		end
		character.Parent = Mock.Workspace
		player.Character = character
		getSignal(player, "CharacterAdded"):Fire(character)
	end,
	GetMouse = function()
		return {}
	end,
	RequestStreamAroundAsync = function()
		task.wait(0.1)
	end,
}

-- Tween
ClassMethods.Tween = {
	Play = function(tween)
		local target = rawget(tween, "_target")
		for k, v in rawget(tween, "_goal") do
			target[k] = v
		end
		task.delay(rawget(tween, "_time") or 0, function()
			getSignal(tween, "Completed"):Fire(Enum.PlaybackState.Completed)
		end)
	end,
	Cancel = function() end,
	Pause = function() end,
}

------------------------------------------------------------------------
-- Services
------------------------------------------------------------------------

local game = newInstance("DataModel")
rawget(game, "_props").Name = "Game"
rawget(game, "_props").JobId = "mock-job-1"
rawget(game, "_props").PlaceId = 1
Mock.Game = game
local services = {}
local closeHandlers = {}

local function service(className, extra)
	local s = newInstance(className)
	rawget(s, "_props").Name = className
	setParent(s, game)
	services[className] = s
	if extra then
		ClassMethods[className] = extra
	end
	return s
end

ClassMethods.DataModel = {
	GetService = function(_, name)
		local s = services[name]
		if not s then
			error("Unbekannter Service im Mock: " .. tostring(name))
		end
		return s
	end,
	BindToClose = function(_, fn)
		table.insert(closeHandlers, fn)
	end,
	IsLoaded = function()
		return true
	end,
}
Mock.CloseHandlers = closeHandlers

-- Workspace
local workspaceObj = service("Workspace", {
	GetServerTimeNow = function()
		return 1000 + Mock.Time
	end,
	Raycast = function(_, origin, direction, params)
		return Mock.Raycast(origin, direction, params)
	end,
	GetPartBoundsInBox = function(_, cframe, size, params)
		local result = {}
		local center = cframe.Position
		local half = size / 2
		local roots = if params and params.FilterDescendantsInstances then params.FilterDescendantsInstances else {}
		for _, root in roots do
			for _, part in Methods.GetDescendants(root) do
				if isA(rawget(part, "_class"), "BasePart") and part.CanQuery ~= false then
					local p = part.Position
					local s = part.Size / 2
					if math.abs(p.X - center.X) <= s.X + half.X and math.abs(p.Y - center.Y) <= s.Y + half.Y and math.abs(p.Z - center.Z) <= s.Z + half.Z then
						table.insert(result, part)
					end
				end
			end
		end
		return result
	end,
	GetPartsInPart = function()
		return {}
	end,
})
rawget(workspaceObj, "_props").Name = "Workspace"
rawget(workspaceObj, "_props").Gravity = 196.2
local camera = newInstance("Camera")
rawget(camera, "_props").Name = "Camera"
rawget(camera, "_props").CFrame = CFrame.identity
rawget(camera, "_props").ViewportSize = v2(1280, 720)
rawget(camera, "_props").FieldOfView = 70
rawget(camera, "_props").CameraType = Enum.CameraType.Custom
setParent(camera, workspaceObj)
rawget(workspaceObj, "_props").CurrentCamera = camera
local terrain = newInstance("Terrain")
rawget(terrain, "_props").Name = "Terrain"
rawget(terrain, "_props").CFrame = CFrame.identity
setParent(terrain, workspaceObj)
rawget(workspaceObj, "_props").Terrain = terrain
Mock.Workspace = workspaceObj

function Mock.Raycast(_origin, _direction, _params)
	return nil
end

-- Players
local playersService
playersService = service("Players", {
	GetPlayers = function()
		local list = {}
		for _, child in rawget(playersService, "_children") do
			if rawget(child, "_class") == "Player" then
				table.insert(list, child)
			end
		end
		return list
	end,
	GetPlayerByUserId = function(_, userId)
		for _, child in rawget(playersService, "_children") do
			if rawget(child, "_class") == "Player" and child.UserId == userId then
				return child
			end
		end
		return nil
	end,
	GetNameFromUserIdAsync = function(_, userId)
		return "User" .. tostring(userId)
	end,
	CreateHumanoidModelFromDescription = function()
		error("nicht unterstützt")
	end,
})
rawget(playersService, "_props").CharacterAutoLoads = true
Mock.Players = setmetatable({}, { __index = function(_, k)
	local v = playersService[k]
	if type(v) == "function" then
		return function(_, ...)
			return v(playersService, ...)
		end
	end
	return v
end })
-- LocalPlayer kontextabhängig
local playersIndex = InstanceMT.__index
InstanceMT.__index = function(obj, key)
	if obj == playersService and key == "LocalPlayer" then
		if Mock.Context == "client" then
			return Mock.CurrentClientPlayer
		end
		return nil
	end
	return playersIndex(obj, key)
end

service("ReplicatedStorage")
service("ServerScriptService")
service("ServerStorage")
local starterPlayer = service("StarterPlayer")
Mock.StarterPlayer = starterPlayer
service("StarterGui", {
	SetCore = function() end,
	SetCoreGuiEnabled = function() end,
	GetCore = function()
		return nil
	end,
})
service("Lighting")
service("ChangeHistoryService", {
	SetWaypoint = function() end,
})
service("SoundService")
service("TextChatService")
service("GuiService")
service("ContextActionService", {
	BindAction = function() end,
	UnbindAction = function() end,
})
service("Debris", {
	AddItem = function(_, item, lifetime)
		task.delay(lifetime or 10, function()
			item:Destroy()
		end)
	end,
})
local guidCounter = 0
service("HttpService", {
	GenerateGUID = function()
		guidCounter += 1
		return "GUID-" .. guidCounter
	end,
	JSONEncode = function()
		return "{}"
	end,
})
service("RunService", {
	IsServer = function()
		return Mock.Context == "server"
	end,
	IsClient = function()
		return Mock.Context == "client"
	end,
	IsStudio = function()
		return Mock.IsStudio == true
	end,
	IsRunning = function()
		return true
	end,
	BindToRenderStep = function(_, _name, _priority, fn)
		local rs = services.RunService
		getSignal(rs, "RenderStepped"):Connect(fn)
	end,
	UnbindFromRenderStep = function() end,
})
service("TweenService", {
	Create = function(_, target, info, goal)
		local tween = newInstance("Tween")
		rawset(tween, "_target", target)
		rawset(tween, "_goal", goal)
		rawset(tween, "_time", info and info.Time or 0)
		return tween
	end,
})
local tagged = {}
local tagAdded = {}
local tagRemoved = {}
local collection
collection = service("CollectionService", {
	AddTag = function(_, obj, tag)
		rawget(obj, "_tags")[tag] = true
		tagged[tag] = tagged[tag] or {}
		if not table.find(tagged[tag], obj) then
			table.insert(tagged[tag], obj)
			if tagAdded[tag] then
				tagAdded[tag]:Fire(obj)
			end
		end
	end,
	RemoveTag = function(_, obj, tag)
		rawget(obj, "_tags")[tag] = nil
		local list = tagged[tag]
		local i = list and table.find(list, obj)
		if i then
			table.remove(list, i)
			if tagRemoved[tag] then
				tagRemoved[tag]:Fire(obj)
			end
		end
	end,
	GetTagged = function(_, tag)
		local result = {}
		for _, obj in tagged[tag] or {} do
			if obj.Parent ~= nil then
				table.insert(result, obj)
			end
		end
		return result
	end,
	GetInstanceAddedSignal = function(_, tag)
		tagAdded[tag] = tagAdded[tag] or newSignal()
		return tagAdded[tag]
	end,
	GetInstanceRemovedSignal = function(_, tag)
		tagRemoved[tag] = tagRemoved[tag] or newSignal()
		return tagRemoved[tag]
	end,
	HasTag = function(_, obj, tag)
		return rawget(obj, "_tags")[tag] == true
	end,
})
Mock.CollectionService = collection
function Mock.OnDestroy(obj)
	for tag in rawget(obj, "_tags") do
		collection:RemoveTag(obj, tag)
	end
end

local groups = { Default = true }
service("PhysicsService", {
	RegisterCollisionGroup = function(_, name)
		groups[name] = true
	end,
	IsCollisionGroupRegistered = function(_, name)
		return groups[name] == true
	end,
	CollisionGroupSetCollidable = function(_, a, b)
		assert(groups[a] and groups[b], "Kollisionsgruppe nicht registriert: " .. a .. "/" .. b)
	end,
})

-- DataStores
local stores = {}
Mock.Stores = stores
Mock.DataStoreFailure = false
local function deepCopy(v)
	if type(v) ~= "table" then
		return v
	end
	local c = {}
	for k, x in v do
		c[deepCopy(k)] = deepCopy(x)
	end
	return c
end
local function validateStorable(v, path)
	local t = type(v)
	if t == "table" then
		for k, x in v do
			assert(type(k) == "string" or type(k) == "number", "Ungültiger Schlüsseltyp in " .. path)
			validateStorable(x, path .. "." .. tostring(k))
		end
	elseif t ~= "string" and t ~= "number" and t ~= "boolean" and t ~= "nil" then
		error("Nicht speicherbarer Wert in DataStore bei " .. path .. ": " .. mockTypeof(v))
	end
end
service("DataStoreService", {
	GetDataStore = function(_, name)
		stores[name] = stores[name] or {}
		local data = stores[name]
		return {
			GetAsync = function(_, key)
				if Mock.DataStoreFailure then
					error("502: API Services rejected request (mock)")
				end
				task.wait(0.05)
				return deepCopy(data[key])
			end,
			SetAsync = function(_, key, value)
				validateStorable(value, name .. "/" .. key)
				data[key] = deepCopy(value)
			end,
			UpdateAsync = function(_, key, fn)
				if Mock.DataStoreFailure then
					error("502: API Services rejected request (mock)")
				end
				task.wait(0.05)
				local result = fn(deepCopy(data[key]))
				if result ~= nil then
					validateStorable(result, name .. "/" .. key)
					data[key] = deepCopy(result)
				end
				return deepCopy(result)
			end,
		}
	end,
	GetOrderedDataStore = function(_, name)
		local key = "ordered:" .. name
		stores[key] = stores[key] or {}
		local data = stores[key]
		return {
			SetAsync = function(_, k, value)
				assert(type(value) == "number", "OrderedDataStore braucht Zahlen")
				data[k] = value
			end,
			GetSortedAsync = function(_, ascending, size)
				local list = {}
				for k, value in data do
					table.insert(list, { key = k, value = value })
				end
				table.sort(list, function(a, b)
					if ascending then
						return a.value < b.value
					end
					return a.value > b.value
				end)
				while #list > size do
					table.remove(list)
				end
				return {
					GetCurrentPage = function()
						return list
					end,
					IsFinished = true,
				}
			end,
		}
	end,
})

-- UserInputService (Client)
service("UserInputService", {
	GetLastInputType = function()
		return Enum.UserInputType.Keyboard
	end,
	GetMouseLocation = function()
		return v2(0, 0)
	end,
	IsKeyDown = function()
		return false
	end,
})
rawget(services.UserInputService, "_props").TouchEnabled = false
rawget(services.UserInputService, "_props").KeyboardEnabled = true
rawget(services.UserInputService, "_props").GamepadEnabled = false

------------------------------------------------------------------------
-- Umgebung, require, Instanzbaum
------------------------------------------------------------------------

local InstanceLib = {}
function InstanceLib.new(className, parent)
	local obj = newInstance(className)
	if className == "Part" or className == "WedgePart" or className == "SpawnLocation" then
		rawget(obj, "_props").CFrame = CFrame.identity
		rawget(obj, "_props").Size = v3(4, 1, 2)
	elseif className == "Attachment" then
		rawget(obj, "_props").Position = v3(0, 0, 0)
		rawget(obj, "_props").CFrame = CFrame.identity
	elseif className == "Motor6D" or className == "Weld" then
		rawget(obj, "_props").C0 = CFrame.identity
		rawget(obj, "_props").C1 = CFrame.identity
		rawget(obj, "_props").Transform = CFrame.identity
	elseif className == "Humanoid" then
		rawget(obj, "_props").Health = 100
	end
	if parent then
		obj.Parent = parent
	end
	return obj
end
Mock.Instance = InstanceLib

local caches = { server = {}, client = {} }
local envBase = {
	game = game,
	workspace = workspaceObj,
	Instance = InstanceLib,
	Vector3 = Vector3,
	Vector2 = Vector2,
	CFrame = CFrame,
	Color3 = Color3,
	UDim = UDim,
	UDim2 = UDim2,
	NumberSequence = NumberSequence,
	NumberSequenceKeypoint = NumberSequenceKeypoint,
	ColorSequence = ColorSequence,
	ColorSequenceKeypoint = ColorSequenceKeypoint,
	NumberRange = NumberRange,
	PhysicalProperties = PhysicalProperties,
	TweenInfo = TweenInfo,
	Rect = Rect,
	Random = Random,
	RaycastParams = RaycastParams,
	OverlapParams = OverlapParams,
	Enum = Enum,
	task = task,
	typeof = mockTypeof,
	tick = function()
		return Mock.Time
	end,
	warn = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			table.insert(parts, tostring((select(i, ...))))
		end
		local text = table.concat(parts, " ")
		table.insert(Mock.Warnings, text)
		if Mock.Verbose then
			print("[WARN] " .. text)
		end
	end,
	print = function(...)
		if Mock.Verbose then
			print(...)
		end
	end,
	os = setmetatable({
		clock = function()
			return Mock.Time
		end,
	}, { __index = os }),
}

local function makeEnv(scriptInstance)
	local env = setmetatable({}, { __index = function(_, k)
		if k == "script" then
			return scriptInstance
		end
		local v = envBase[k]
		if v ~= nil then
			return v
		end
		return baseEnv[k]
	end })
	env.require = function(target)
		assert(type(target) == "table" and rawget(target, "__instance"), "require erwartet ModuleScript-Instanz")
		local cache = caches[Mock.Context]
		local entry = cache[target]
		if entry then
			if entry.Loading then
				error("Requested module was required recursively: " .. Methods.GetFullName(target))
			end
			return entry.Value
		end
		entry = { Loading = true }
		cache[target] = entry
		local source = rawget(target, "_props").Source
		assert(source, "Kein Quelltext für " .. Methods.GetFullName(target))
		local fn = __compile(__readfile(source), Methods.GetFullName(target), makeEnv(target))
		local value = fn()
		entry.Loading = false
		entry.Value = value
		return value
	end
	return env
end
Mock.MakeEnv = makeEnv

function Mock.BuildTree(tree)
	local lastRoot = nil
	local function build(node, parent)
		local obj
		if node.Class == "DataModel" then
			obj = game
		elseif services[node.Class] and parent == game then
			obj = services[node.Class]
		else
			obj = InstanceLib.new(node.Class)
			rawget(obj, "_props").Name = node.Name
			if node.Source then
				rawget(obj, "_props").Source = node.Source
			end
		end
		for k, v in node.Props or {} do
			rawget(obj, "_props")[k] = v
		end
		if obj ~= game and rawget(obj, "_props").Parent ~= parent then
			setParent(obj, parent)
		end
		if parent == nil then
			lastRoot = obj
		end
		for _, child in node.Children or {} do
			build(child, obj)
		end
	end
	build(tree, nil)
	Mock.LastBuiltRoot = lastRoot
	-- StarterPlayerScripts / StarterCharacterScripts sicherstellen
	for _, name in { "StarterPlayerScripts", "StarterCharacterScripts" } do
		if not starterPlayer:FindFirstChild(name) then
			InstanceLib.new(name, starterPlayer).Name = name
		end
	end
end

--- Startet ein Script (Server) oder LocalScript (Client) im passenden Kontext.
function Mock.RunScript(scriptInstance, context)
	local previous = Mock.Context
	Mock.Context = context
	task.spawn(function()
		local source = rawget(scriptInstance, "_props").Source
		local fn = __compile(__readfile(source), Methods.GetFullName(scriptInstance), makeEnv(scriptInstance))
		fn()
	end)
	Mock.Context = previous
end

------------------------------------------------------------------------
-- Spieler
------------------------------------------------------------------------

local clientEvents = {}
Mock.ClientPlayers = {}

function Mock.AddPlayer(userId, name, withClient)
	local player = newInstance("Player")
	local props = rawget(player, "_props")
	props.Name = name
	props.DisplayName = name
	props.UserId = userId
	local gui = InstanceLib.new("PlayerGui")
	rawget(gui, "_props").Name = "PlayerGui"
	setParent(gui, player)
	local scripts = InstanceLib.new("PlayerScripts")
	rawget(scripts, "_props").Name = "PlayerScripts"
	setParent(scripts, player)
	local previous = Mock.Context
	Mock.Context = "server"
	setParent(player, playersService)
	getSignal(playersService, "PlayerAdded"):Fire(player)
	Mock.Context = previous
	if withClient then
		Mock.ClientPlayers[player] = true
		Mock.CurrentClientPlayer = player
		for _, s in starterPlayer:FindFirstChild("StarterPlayerScripts"):GetChildren() do
			local copy = s:Clone()
			copy.Parent = scripts
		end
		for _, d in scripts:GetDescendants() do
			if rawget(d, "_class") == "LocalScript" then
				Mock.RunScript(d, "client")
			end
		end
	end
	return player
end

function Mock.RemovePlayer(player)
	local previous = Mock.Context
	Mock.Context = "server"
	getSignal(playersService, "PlayerRemoving"):Fire(player)
	Mock.Context = previous
	task.defer(function()
		if player.Character then
			player.Character:Destroy()
		end
		setParent(player, nil)
	end)
end

function Mock.DeliverToClient(remote, player, ...)
	if not Mock.ClientPlayers[player] then
		return
	end
	local args = table.pack(...)
	local previous = Mock.Context
	Mock.Context = "client"
	getSignal(remote, "OnClientEvent"):Fire(table.unpack(args, 1, args.n))
	Mock.Context = previous
end

--- Simuliert einen Client-Aufruf eines RemoteEvents (für Spieler ohne Client-Code).
function Mock.ClientFire(player, remoteName, ...)
	local remote = services.ReplicatedStorage.Remotes:FindFirstChild(remoteName)
	assert(remote, "Remote fehlt: " .. remoteName)
	local previous = Mock.Context
	Mock.Context = "server"
	getSignal(remote, "OnServerEvent"):Fire(player, ...)
	Mock.Context = previous
end

function Mock.ClientInvoke(player, remoteName, ...)
	local remote = services.ReplicatedStorage.Remotes:FindFirstChild(remoteName)
	assert(remote, "Remote fehlt: " .. remoteName)
	local previous = Mock.Context
	Mock.Context = "server"
	local handler = remote.OnServerInvoke
	local result = table.pack(handler(player, ...))
	Mock.Context = previous
	return table.unpack(result, 1, result.n)
end

------------------------------------------------------------------------
-- Simulation
------------------------------------------------------------------------

--- Simuliert `seconds` Sekunden in 60-Hz-Schritten. onStep(dt) wird pro Schritt aufgerufen.
function Mock.Run(seconds, onStep)
	local steps = math.floor(seconds * 60 + 0.5)
	local dt = 1 / 60
	for _ = 1, steps do
		Mock.Time += dt
		if onStep then
			onStep(dt)
		end
		local previous = Mock.Context
		Mock.Context = "server"
		getSignal(services.RunService, "PreSimulation"):Fire(dt)
		getSignal(services.RunService, "Stepped"):Fire(Mock.Time, dt)
		getSignal(services.RunService, "RenderStepped"):Fire(dt)
		getSignal(services.RunService, "Heartbeat"):Fire(dt)
		Mock.Context = previous
		runDue()
	end
end

Mock.Services = services
Mock.Enum = Enum
Mock.typeof = mockTypeof
return Mock
