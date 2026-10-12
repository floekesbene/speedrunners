--[[
	Signal  (ModuleScript)
	Pfad: ReplicatedStorage/Shared/Signal

	Minimale Event-Implementierung für die Kommunikation zwischen Modulen
	auf derselben Seite (Server-Server oder Client-Client).

	API:
		Signal.new() -> Signal
		signal:Connect(fn) -> Connection (mit :Disconnect())
		signal:Once(fn) -> Connection
		signal:Fire(...)
		signal:Wait() -> ...
		signal:DisconnectAll()
]]

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn: (...any) -> ())
	local handler = { Fn = fn, Connected = true }
	table.insert(self._handlers, handler)
	local signal = self
	return {
		Disconnect = function()
			if not handler.Connected then
				return
			end
			handler.Connected = false
			local index = table.find(signal._handlers, handler)
			if index then
				table.remove(signal._handlers, index)
			end
		end,
	}
end

function Signal:Once(fn: (...any) -> ())
	local connection
	connection = self:Connect(function(...)
		connection.Disconnect()
		fn(...)
	end)
	return connection
end

function Signal:Fire(...)
	for _, handler in table.clone(self._handlers) do
		if handler.Connected then
			task.spawn(handler.Fn, ...)
		end
	end
end

function Signal:Wait()
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:DisconnectAll()
	for _, handler in self._handlers do
		handler.Connected = false
	end
	table.clear(self._handlers)
end

return Signal
