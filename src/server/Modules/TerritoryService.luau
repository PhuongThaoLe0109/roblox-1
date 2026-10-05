-- TerritoryService
-- King-of-the-hill capture for the 12 islands, essence income, and location
-- tracking.
--
-- Each tick (TerritoryConfig.TickInterval):
--   * Every player's location is resolved; Player.CurrentIsland and
--     Player.CaptureTerritory attributes are kept up to date for the UI.
--   * Players standing on an island above their rank (e.g. they swam there)
--     are sent back to the hub; enemies on a faction home are bounced too.
--   * Capture state advances per island:
--       - one faction on the pad: progress drains the previous holder's claim
--         to 0 (neutralising the island), then fills toward 100 for itself.
--       - several factions on the pad: contested, frozen.
--       - nobody: owned islands regenerate to 100, unowned decay to 0.
--
-- Replicated per island (attributes on Map.Territories.<Id>):
--   Owner ("" when unowned), Capturer, Progress (0-100), Contested (bool)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GemConfig = require(ReplicatedStorage:WaitForChild("GemConfig"))
local Signal = require(ReplicatedStorage:WaitForChild("Signal"))
local TerritoryConfig = require(ReplicatedStorage:WaitForChild("TerritoryConfig"))
local GemDataManager = require(script.Parent:WaitForChild("GemDataManager"))
local PortalService = require(script.Parent:WaitForChild("PortalService"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))

local ATTR = GemConfig.Attributes
local NEUTRAL_COLOR = Color3.fromRGB(235, 235, 245)

local TerritoryService = {}

TerritoryService.Captured = Signal.new() -- (territoryId, factionId, players)
TerritoryService.Neutralized = Signal.new() -- (territoryId, previousOwner)

type State = {
	Id: string,
	Info: any,
	Model: Instance,
	Pad: BasePart,
	Beacon: BasePart?,
	Owner: string?,
	Capturer: string?,
	Progress: number,
	Contested: boolean,
	ReplicatedProgress: number,
}

local states: { [string]: State } = {}
local initialized = false

--------------------------------------------------------------------------------
-- Visuals & replication
--------------------------------------------------------------------------------

local function factionColor(factionId: string?): Color3
	local faction = factionId and GemConfig.Factions[factionId]
	return if faction then faction.Color else NEUTRAL_COLOR
end

local function updateVisuals(state: State)
	local color = factionColor(state.Owner)
	state.Pad.Color = color

	local beacon = state.Beacon
	if beacon then
		beacon.Color = color
		local light = beacon:FindFirstChildOfClass("PointLight")
		if light then
			light.Color = color
		end
		local sparkles = beacon:FindFirstChildOfClass("ParticleEmitter")
		if sparkles then
			sparkles.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, color),
				ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
				ColorSequenceKeypoint.new(1, color),
			})
		end
		local tag = beacon:FindFirstChild("NameTag")
		local label = tag and tag:FindFirstChild("Label")
		if label and label:IsA("TextLabel") then
			label.TextColor3 = if state.Owner then color else Color3.new(1, 1, 1)
		end
	end
end

local function replicate(state: State, force: boolean?)
	local model = state.Model
	model:SetAttribute("Owner", state.Owner or "")
	model:SetAttribute("Capturer", state.Capturer or "")
	model:SetAttribute("Contested", state.Contested)
	-- Progress changes every tick; only replicate meaningful steps.
	if force or math.abs(state.Progress - state.ReplicatedProgress) >= 0.5 or state.Progress == 0 or state.Progress == 100 then
		state.ReplicatedProgress = state.Progress
		model:SetAttribute("Progress", math.floor(state.Progress * 10 + 0.5) / 10)
	end
end

--------------------------------------------------------------------------------
-- Capture rules
--------------------------------------------------------------------------------

local function setOwner(state: State, newOwner: string?, capturers: { Player }?)
	local previous = state.Owner
	if previous == newOwner then
		return
	end
	state.Owner = newOwner
	updateVisuals(state)

	local name = state.Info.DisplayName
	if newOwner then
		local factionName = GemConfig.Factions[newOwner].DisplayName
		Remotes.NotifyAll(`{name} was captured by the {factionName}!`, "Capture")
		for _, player in capturers or {} do
			GemDataManager.AddEssence(player, TerritoryConfig.CaptureReward, "Capture")
			GemDataManager.IncrementStat(player, "TerritoriesCaptured")
		end
		TerritoryService.Captured:Fire(state.Id, newOwner, capturers or {})
	else
		Remotes.NotifyAll(`{name} has been neutralised!`, "Info")
		TerritoryService.Neutralized:Fire(state.Id, previous)
	end
end

local function stepTerritory(state: State, present: { [string]: { Player } }, dt: number)
	local factions = {}
	for factionId in present do
		table.insert(factions, factionId)
	end

	state.Contested = #factions > 1
	if state.Contested then
		return
	end

	if #factions == 1 then
		local faction = factions[1]
		local players = present[faction]
		local rate = 100 / TerritoryConfig.CaptureTime * math.min(#players, TerritoryConfig.MaxCaptureMultiplier) * dt

		if state.Capturer == nil or state.Capturer == faction then
			state.Capturer = faction
			state.Progress = math.min(100, state.Progress + rate)
			if state.Progress >= 100 and state.Owner ~= faction then
				setOwner(state, faction, players)
			end
		else
			state.Progress = math.max(0, state.Progress - rate)
			if state.Progress <= 0 then
				state.Capturer = faction
				if state.Owner and state.Owner ~= faction then
					setOwner(state, nil)
				end
			end
		end
		return
	end

	-- Nobody on the pad: drift back toward the owner's full hold (or to empty).
	local drift = TerritoryConfig.RegenPerSecond * dt
	if state.Owner then
		if state.Capturer == state.Owner then
			state.Progress = math.min(100, state.Progress + drift)
		else
			state.Progress = math.max(0, state.Progress - drift)
			if state.Progress <= 0 then
				state.Capturer = state.Owner
			end
		end
	else
		state.Progress = math.max(0, state.Progress - drift)
		if state.Progress <= 0 then
			state.Capturer = nil
		end
	end
end

--------------------------------------------------------------------------------
-- Tick
--------------------------------------------------------------------------------

local function isCapturing(state: State, root: BasePart): boolean
	local padPos = state.Pad.Position
	local offset = root.Position - padPos
	local horizontal = Vector3.new(offset.X, 0, offset.Z).Magnitude
	return horizontal <= TerritoryConfig.CaptureRadius and offset.Y > -3 and offset.Y < TerritoryConfig.CaptureHeight
end

local function tick(dt: number)
	local presence: { [string]: { [string]: { Player } } } = {}

	for _, player in Players:GetPlayers() do
		if not GemDataManager.IsLoaded(player) then
			continue
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not humanoid or humanoid.Health <= 0 or not (root and root:IsA("BasePart")) then
			continue
		end

		local location = TerritoryConfig.GetLocationAt(root.Position) or ""
		local faction = player:GetAttribute(ATTR.Faction)
		local rank = player:GetAttribute(ATTR.Rank) or 1

		-- Anti-bypass: islands above your rank and enemy homes bounce you to the hub.
		if TerritoryConfig.ById[location] and rank < TerritoryConfig.GetRequiredRank(location) then
			PortalService.TeleportToHub(player, "You need a higher rank to visit that island.")
			continue
		elseif location == "Home" then
			local homeFaction = TerritoryConfig.GetHomeAt(root.Position)
			if homeFaction and homeFaction ~= faction then
				PortalService.TeleportToHub(player, "That is an enemy home base!")
				continue
			end
		end

		if player:GetAttribute(ATTR.CurrentIsland) ~= location then
			player:SetAttribute(ATTR.CurrentIsland, location)
		end

		local capturing = ""
		local state = states[location]
		-- Rogues and puffed gems can't capture.
		if state and faction ~= "Neutral" and type(faction) == "string" and not character:GetAttribute("Puffed") then
			if isCapturing(state, root) then
				capturing = location
				presence[location] = presence[location] or {}
				local list = presence[location][faction] or {}
				presence[location][faction] = list
				table.insert(list, player)
			end
		end
		if player:GetAttribute(ATTR.CaptureTerritory) ~= capturing then
			player:SetAttribute(ATTR.CaptureTerritory, capturing)
		end
	end

	for id, state in states do
		stepTerritory(state, presence[id] or {}, dt)
		replicate(state)
	end
end

local function incomeLoop()
	while true do
		task.wait(TerritoryConfig.IncomeInterval)
		local owned: { [string]: number } = {}
		for _, state in states do
			if state.Owner then
				owned[state.Owner] = (owned[state.Owner] or 0) + 1
			end
		end
		for _, player in Players:GetPlayers() do
			if GemDataManager.IsLoaded(player) then
				local faction = player:GetAttribute(ATTR.Faction)
				local amount = TerritoryConfig.BaseIncome + (owned[faction] or 0) * TerritoryConfig.IncomePerTerritory
				GemDataManager.AddEssence(player, amount, "Income")
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------

function TerritoryService.GetOwner(territoryId: string): string?
	local state = states[territoryId]
	return state and state.Owner
end

function TerritoryService.GetOwnedCount(factionId: string): number
	local total = 0
	for _, state in states do
		if state.Owner == factionId then
			total += 1
		end
	end
	return total
end

function TerritoryService.Init(map: Instance)
	if initialized then
		return
	end
	initialized = true

	local folder = map:WaitForChild("Territories", 10)
	assert(folder, "TerritoryService: Workspace.Map.Territories is missing")

	for _, info in TerritoryConfig.Territories do
		local model = folder:FindFirstChild(info.Id)
		local pad = model and model:FindFirstChild("CapturePoint")
		if not (model and pad and pad:IsA("BasePart")) then
			warn(`[TerritoryService] {info.Id} has no CapturePoint; skipping`)
			continue
		end
		local beacon = model:FindFirstChild("Beacon")

		local state: State = {
			Id = info.Id,
			Info = info,
			Model = model,
			Pad = pad,
			Beacon = if beacon and beacon:IsA("BasePart") then beacon else nil,
			Owner = info.InitialOwner,
			Capturer = info.InitialOwner,
			Progress = if info.InitialOwner then 100 else 0,
			Contested = false,
			ReplicatedProgress = -1,
		}
		states[info.Id] = state
		updateVisuals(state)
		replicate(state, true)
	end

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= TerritoryConfig.TickInterval then
			local step = accumulator
			accumulator = 0
			tick(step)
		end
	end)

	task.spawn(incomeLoop)

	GemDataManager.RankChanged:Connect(function(player, newRank, oldRank)
		if newRank > oldRank then
			local rank = GemConfig.Ranks[newRank]
			local unlocked = TerritoryConfig.Territories[newRank]
			local text = `Rank up! You are now {rank.Name}.`
			if unlocked then
				text ..= ` {unlocked.DisplayName} is unlocked!`
			end
			Remotes.NotifyPlayer(player, text, "RankUp")
		end
	end)
end

return TerritoryService
