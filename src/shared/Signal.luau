--!strict
-- Signal
-- Lightweight, leak-safe event object for module-to-module communication.
-- Handlers run in their own thread (task.spawn), so a yielding or erroring
-- handler never blocks or breaks the code that fired the signal.

local Signal = {}
Signal.__index = Signal

local Connection = {}
Connection.__index = Connection

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal = {
	Connect: (self: Signal, handler: (...any) -> ()) -> Connection,
	Once: (self: Signal, handler: (...any) -> ()) -> Connection,
	Wait: (self: Signal) -> ...any,
	Fire: (self: Signal, ...any) -> (),
	DisconnectAll: (self: Signal) -> (),
	Destroy: (self: Signal) -> (),
}

function Connection:Disconnect()
	if not self.Connected then
		return
	end
	self.Connected = false

	local list = self._signal._connections
	local index = table.find(list, self)
	if index then
		table.remove(list, index)
	end
end

function Signal.new(): Signal
	local self = setmetatable({
		_connections = {},
	}, Signal)
	return (self :: any) :: Signal
end

function Signal:Connect(handler: (...any) -> ()): Connection
	assert(type(handler) == "function", "Signal:Connect expects a function")

	local connection = setmetatable({
		Connected = true,
		_signal = self,
		_handler = handler,
	}, Connection)

	table.insert(self._connections, connection)
	return (connection :: any) :: Connection
end

function Signal:Once(handler: (...any) -> ()): Connection
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		handler(...)
	end)
	return connection
end

function Signal:Wait(): ...any
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:Fire(...: any)
	-- Snapshot so handlers can safely disconnect themselves (or others) mid-fire.
	for _, connection in table.clone(self._connections) do
		if connection.Connected then
			task.spawn(connection._handler, ...)
		end
	end
end

function Signal:DisconnectAll()
	for _, connection in self._connections do
		connection.Connected = false
	end
	table.clear(self._connections)
end

Signal.Destroy = Signal.DisconnectAll

return Signal
