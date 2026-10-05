-- AdminService
-- Founder chat commands. Only the accounts listed in FOUNDERS can use them;
-- everyone else's "?admin" is ignored.
--
--   ?admin   adds one of every gem you don't own yet to your inventory
--
-- Works with the new TextChatService (as a TextChatCommand, so the command is
-- not shown in chat) and with legacy chat (Player.Chatted).

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))

local AdminService = {}

-- Founder usernames (case-insensitive). Add user ids to FOUNDER_IDS to keep
-- access even if a username changes.
local FOUNDERS = { "swarovski_i" }
local FOUNDER_IDS: { number } = {}

local COMMAND = "?admin"

local function isFounder(player: Player): boolean
	if table.find(FOUNDER_IDS, player.UserId) then
		return true
	end
	local name = player.Name:lower()
	for _, founder in FOUNDERS do
		if founder:lower() == name then
			return true
		end
	end
	return false
end

local lastUse: { [Player]: number } = {}

local function runAdmin(player: Player)
	if not isFounder(player) then
		return
	end
	if os.clock() - (lastUse[player] or 0) < 2 then
		return -- the same message can arrive through both chat systems
	end
	lastUse[player] = os.clock()
	if not PlayerData.IsLoaded(player) then
		Remotes.Notify:FireClient(player, "Your data is still loading. Try ?admin again in a moment.", "Warning")
		return
	end
	local added = PlayerData.GrantAll(player)
	PlayerData.SaveNow(player)
	Remotes.Notify:FireClient(player, if added > 0 then `Founder access: {added} new gems added. Your collection is complete!` else "Founder access: you already own every gem.", "Success")
end

local function isCommand(message: string): boolean
	return message:lower():match("^%s*(%S+)") == COMMAND
end

function AdminService.Init()
	-- New chat: a command that never reaches the chat window.
	pcall(function()
		local commands = TextChatService:FindFirstChild("TextChatCommands") or TextChatService
		local command = Instance.new("TextChatCommand")
		command.Name = "FounderAdmin"
		command.PrimaryAlias = COMMAND
		command.Parent = commands
		command.Triggered:Connect(function(source: TextSource)
			local player = Players:GetPlayerByUserId(source.UserId)
			if player then
				runAdmin(player)
			end
		end)
	end)

	-- Legacy chat.
	local function watch(player: Player)
		player.Chatted:Connect(function(message)
			if isCommand(message) then
				runAdmin(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastUse[player] = nil
	end)
end

return AdminService
