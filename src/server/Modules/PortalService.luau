-- PortalService
-- Rank-gated travel between islands.
--   * Portal surfaces are parts tagged "Portal" (see MapBuilder.buildPortal) with
--     attributes PortalKind ("Territory" | "Hub" | "Home"), TargetId,
--     TargetName and RequiredRank.
--   * Touching a portal teleports the player to the destination's "Arrival"
--     part if their rank is high enough, otherwise they get a notification.
--   * Fast travel (map panel) goes through the same validation.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GemConfig = require(ReplicatedStorage:WaitForChild("GemConfig"))
local TerritoryConfig = require(ReplicatedStorage:WaitForChild("TerritoryConfig"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))

local ATTR = GemConfig.Attributes

local PortalService = {}

local map: Instance
local lastTeleport: { [Player]: number } = {}
local lastDenied: { [Player]: number } = {}
local lastFastTravel: { [Player]: number } = {}

local TOUCH_DEBOUNCE = 1.5
local DENIED_MESSAGE_COOLDOWN = 3

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function getRank(player: Player): number
	return player:GetAttribute(ATTR.Rank) or 1
end

local function getAliveRoot(player: Player): (Model?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not (root and root:IsA("BasePart")) then
		return nil, nil
	end
	return character, root
end

local function findArrival(container: Instance?): BasePart?
	local arrival = container and container:FindFirstChild("Arrival")
	return if arrival and arrival:IsA("BasePart") then arrival else nil
end

-- Resolves a destination to (arrival part, display name) or (nil, error code).
local function resolve(player: Player, kind: string, targetId: string?): (BasePart?, string)
	if kind == "Hub" then
		return findArrival(map:FindFirstChild("Hub")), TerritoryConfig.HubName
	elseif kind == "Home" then
		local faction = player:GetAttribute(ATTR.Faction)
		local homes = map:FindFirstChild("Homes")
		local home = homes and type(faction) == "string" and homes:FindFirstChild(faction)
		if not home then
			return nil, "NoHome"
		end
		return findArrival(home), TerritoryConfig.Homes[faction].DisplayName
	elseif kind == "Territory" and type(targetId) == "string" and TerritoryConfig.ById[targetId] then
		local territories = map:FindFirstChild("Territories")
		return findArrival(territories and territories:FindFirstChild(targetId)), TerritoryConfig.ById[targetId].DisplayName
	end
	return nil, "InvalidDestination"
end

local function requiredRankFor(kind: string, targetId: string?): number
	if kind == "Territory" and type(targetId) == "string" then
		return TerritoryConfig.GetRequiredRank(targetId)
	end
	return 1
end

local function rankName(rank: number): string
	local info = GemConfig.Ranks[rank]
	return if info then info.Name else tostring(rank)
end

--------------------------------------------------------------------------------
-- Teleport
--------------------------------------------------------------------------------

function PortalService.Teleport(player: Player, arrival: BasePart, destinationName: string): boolean
	local character = getAliveRoot(player)
	if not character then
		return false
	end
	lastTeleport[player] = os.clock()
	-- Slight random offset so a group arriving together doesn't stack.
	local jitter = Vector3.new(math.random(-3, 3), 0, math.random(-3, 3))
	character:PivotTo(arrival.CFrame + Vector3.new(0, 4, 0) + jitter)
	Remotes.NotifyPlayer(player, destinationName, "Travel")
	return true
end

function PortalService.TeleportToHub(player: Player, reason: string?)
	local arrival = findArrival(map:FindFirstChild("Hub"))
	if arrival then
		PortalService.Teleport(player, arrival, TerritoryConfig.HubName)
		if reason then
			Remotes.NotifyPlayer(player, reason, "Warning")
		end
	end
end

-- Validates rank + destination, then teleports. Returns ok, errorCode.
function PortalService.TryTravel(player: Player, kind: string, targetId: string?): (boolean, string?)
	local required = requiredRankFor(kind, targetId)
	if getRank(player) < required then
		return false, "RankTooLow"
	end
	local arrival, nameOrError = resolve(player, kind, targetId)
	if not arrival then
		return false, nameOrError
	end
	if not PortalService.Teleport(player, arrival, nameOrError) then
		return false, "NotAlive"
	end
	return true
end

--------------------------------------------------------------------------------
-- Portal touch handling
--------------------------------------------------------------------------------

local function onPortalTouched(surface: BasePart, hit: BasePart)
	local character = hit:FindFirstAncestorOfClass("Model")
	local player = character and Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end

	local now = os.clock()
	if lastTeleport[player] and now - lastTeleport[player] < TOUCH_DEBOUNCE then
		return
	end

	local kind = surface:GetAttribute("PortalKind")
	local targetId = surface:GetAttribute("TargetId")
	if type(kind) ~= "string" then
		return
	end

	local ok, err = PortalService.TryTravel(player, kind, targetId)
	if ok then
		return
	end

	if not lastDenied[player] or now - lastDenied[player] > DENIED_MESSAGE_COOLDOWN then
		lastDenied[player] = now
		if err == "RankTooLow" then
			local required = requiredRankFor(kind, targetId)
			Remotes.NotifyPlayer(player, `This portal needs rank {required} ({rankName(required)}). Earn more essence!`, "Warning")
		elseif err == "NoHome" then
			Remotes.NotifyPlayer(player, "Rogue Shards have no home base. Join a faction first!", "Warning")
		end
	end
end

local function bindPortal(instance: Instance)
	if not instance:IsA("BasePart") or not instance:IsDescendantOf(map) then
		return
	end
	instance.CanTouch = true
	instance.Touched:Connect(function(hit)
		onPortalTouched(instance, hit)
	end)
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------

function PortalService.Init(mapRoot: Instance)
	map = mapRoot

	for _, portal in CollectionService:GetTagged(GemConfig.Tags.Portal) do
		bindPortal(portal)
	end
	CollectionService:GetInstanceAddedSignal(GemConfig.Tags.Portal):Connect(bindPortal)

	Players.PlayerRemoving:Connect(function(player)
		lastTeleport[player] = nil
		lastDenied[player] = nil
		lastFastTravel[player] = nil
	end)

	Remotes.RequestFastTravel.OnServerInvoke = function(player: Player, destination: unknown)
		if type(destination) ~= "string" then
			return false, "InvalidDestination"
		end
		local now = os.clock()
		local last = lastFastTravel[player]
		if last and now - last < TerritoryConfig.FastTravelCooldown then
			return false, "Cooldown", TerritoryConfig.FastTravelCooldown - (now - last)
		end

		local kind, targetId
		if destination == "Hub" or destination == "Home" then
			kind = destination
		else
			kind, targetId = "Territory", destination
		end

		local ok, err = PortalService.TryTravel(player, kind, targetId)
		if ok then
			lastFastTravel[player] = now
		end
		return ok, err
	end
end

return PortalService
