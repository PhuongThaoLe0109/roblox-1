-- ClientData
-- Local mirror of the player's public data (inventory, equipped gem, roll
-- count), kept in sync from the server's InventorySync events. UI modules read
-- from here and listen to Changed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage:WaitForChild("Signal"))

local ClientData = {}

ClientData.Loaded = false
ClientData.Inventory = {} :: { [string]: number }
ClientData.Equipped = ""
ClientData.Rolls = 0
ClientData.Changed = Signal.new() -- (kind: "Full" | "Gem" | "Equipped", gemId?)

local started = false

function ClientData.Count(gemId: string): number
	return ClientData.Inventory[gemId] or 0
end

function ClientData.UniqueOwned(): number
	local total = 0
	for _, count in ClientData.Inventory do
		if count > 0 then
			total += 1
		end
	end
	return total
end

local function applySnapshot(snapshot: any)
	if type(snapshot) ~= "table" then
		return
	end
	ClientData.Inventory = if type(snapshot.Inventory) == "table" then snapshot.Inventory else {}
	ClientData.Equipped = if type(snapshot.Equipped) == "string" then snapshot.Equipped else ""
	ClientData.Rolls = if type(snapshot.Rolls) == "number" then snapshot.Rolls else 0
	ClientData.Loaded = true
	ClientData.Changed:Fire("Full")
end

function ClientData.Start()
	if started then
		return
	end
	started = true
	local player = Players.LocalPlayer
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local sync = remotes:WaitForChild("InventorySync") :: RemoteEvent
	local getProfile = remotes:WaitForChild("GetProfile") :: RemoteFunction

	sync.OnClientEvent:Connect(function(kind: string, a: any, b: any)
		if kind == "Full" then
			applySnapshot(a)
		elseif kind == "Gem" and type(a) == "string" and type(b) == "number" then
			ClientData.Inventory[a] = b
			ClientData.Changed:Fire("Gem", a)
		elseif kind == "Equipped" and type(a) == "string" then
			ClientData.Equipped = a
			ClientData.Changed:Fire("Equipped", a)
		end
	end)

	player:GetAttributeChangedSignal("TotalRolls"):Connect(function()
		ClientData.Rolls = player:GetAttribute("TotalRolls") or ClientData.Rolls
	end)

	-- The "Full" event may have fired before we connected; ask explicitly.
	task.spawn(function()
		while not player:GetAttribute("DataLoaded") do
			player:GetAttributeChangedSignal("DataLoaded"):Wait()
		end
		if not ClientData.Loaded then
			applySnapshot(getProfile:InvokeServer())
		end
	end)
end

return ClientData
