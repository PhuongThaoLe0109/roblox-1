-- MatchService
-- The lobby <-> arena loop:
--   * RequestPlay moves a living lobby player onto an arena spawn (the one
--     furthest from other fighters), arms the Crystal Blade in their gem's
--     colours and grants a moment of spawn protection.
--   * Defeat in the arena credits the killer (kills, streaks, best streak,
--     a small heal), posts to the kill feed, and the player respawns in the
--     lobby after CombatConfig.ReturnToLobbyDelay.
--   * Falling below the arena's KillY is a defeat; lobby players who slip
--     into the temple are sent back to the lobby.
--   * leaderstats (Kills, Streak) give the in-server leaderboard.
--
-- Reads the map only through its contract: Map.Arena (attributes Center,
-- Radius, KillY + ArenaSpawn parts) and Map.Lobby.LobbySpawn. It never edits
-- Workspace.Map.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))

local Combat = script.Parent
local Modules = Combat.Parent
local ActionService = require(Combat:WaitForChild("ActionService"))
local BladeBuilder = require(Combat:WaitForChild("BladeBuilder"))
local CombatService = require(Combat:WaitForChild("CombatService"))
local MovementGuard = require(Combat:WaitForChild("MovementGuard"))
local PlayerData = require(Modules:WaitForChild("PlayerData"))
local Remotes = require(Modules:WaitForChild("Remotes"))

local STATUS = CombatConfig.Status
local PA = CombatConfig.PlayerAttributes

local PLAY_COOLDOWN = 1
local BOUNDS_INTERVAL = 0.25

local MatchService = {}

local playCooldown = Remotes.CreateCooldown(PLAY_COOLDOWN)
local joining: { [Player]: boolean } = {}

--------------------------------------------------------------------------------
-- Map contract
--------------------------------------------------------------------------------

local function arena(): Instance?
	local map = Workspace:FindFirstChild("Map")
	return map and map:FindFirstChild("Arena")
end

local function lobbySpawn(): BasePart?
	local map = Workspace:FindFirstChild("Map")
	local lobby = map and map:FindFirstChild("Lobby")
	local spawn = lobby and lobby:FindFirstChild("LobbySpawn", true)
	return if spawn and spawn:IsA("BasePart") then spawn else nil
end

local function spawnPoints(folder: Instance): { BasePart }
	local list = {}
	for _, part in CollectionService:GetTagged("ArenaSpawn") do
		if part:IsA("BasePart") and part:IsDescendantOf(folder) then
			table.insert(list, part)
		end
	end
	return list
end

-- The spawn whose nearest fighter is furthest away (random among near-ties).
local function pickSpawn(folder: Instance, exclude: Player): BasePart?
	local points = spawnPoints(folder)
	if #points == 0 then
		return nil
	end
	local fighters = {}
	for _, player in Players:GetPlayers() do
		local target = player ~= exclude and CombatService.ToTarget(player)
		if target then
			table.insert(fighters, target.Root.Position)
		end
	end
	local best, bestScore = nil, -math.huge
	for _, point in points do
		local nearest = 1e6
		for _, position in fighters do
			nearest = math.min(nearest, (position - point.Position).Magnitude)
		end
		local score = math.min(nearest, 400) + math.random() * 25
		if score > bestScore then
			best, bestScore = point, score
		end
	end
	return best
end

--------------------------------------------------------------------------------
-- Characters
--------------------------------------------------------------------------------

local function resetStatus(character: Model)
	character:SetAttribute(STATUS.StunnedUntil, 0)
	character:SetAttribute(STATUS.InvulnerableUntil, 0)
	character:SetAttribute(STATUS.BusyUntil, 0)
	character:SetAttribute(STATUS.MoveGraceUntil, 0)
	character:SetAttribute(STATUS.Blocking, false)
	character:SetAttribute(STATUS.Guard, CombatConfig.Block.MaxGuard)
	character:SetAttribute(STATUS.Combo, 0)
	character:SetAttribute(STATUS.SpawnProtected, false)
end

local function setStreak(player: Player, streak: number)
	player:SetAttribute(PA.Streak, streak)
	local stats = player:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild("Streak")
	if value and value:IsA("IntValue") then
		value.Value = streak
	end
end

local function addKill(player: Player)
	local stats = player:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild("Kills")
	if value and value:IsA("IntValue") then
		value.Value += 1
	end
end

local function onDied(player: Player, character: Model)
	if player:GetAttribute(PA.InArena) ~= true then
		return
	end
	player:SetAttribute(PA.InArena, false)
	character:SetAttribute(STATUS.Blocking, false)

	local root = character:FindFirstChild("HumanoidRootPart")
	local color, accent = CombatService.ColorsOf(player)
	if root and root:IsA("BasePart") then
		CombatService.FX("Defeat", { Caster = character, Position = root.Position, Color = color, Accent = accent })
	end

	local killer = CombatService.RecentAttacker(player, CombatConfig.KillCreditWindow)
	CombatService.Forget(player)

	PlayerData.IncrementStat(player, "Deaths")
	local lostStreak = player:GetAttribute(PA.Streak) or 0
	setStreak(player, 0)

	local streak = 0
	if killer and killer ~= player then
		PlayerData.IncrementStat(killer, "Kills")
		addKill(killer)
		streak = (killer:GetAttribute(PA.Streak) or 0) + 1
		setStreak(killer, streak)
		PlayerData.SetBestStreak(killer, streak)
		local target = CombatService.ToTarget(killer)
		if target then
			target.Humanoid.Health = math.min(target.Humanoid.MaxHealth, target.Humanoid.Health + CombatConfig.KillHeal)
		end
	end

	Remotes.KillFeed:FireAllClients({
		Killer = killer and killer.Name or nil,
		KillerDisplay = killer and killer.DisplayName or nil,
		KillerGem = killer and killer:GetAttribute("EquippedGem") or nil,
		Victim = player.Name,
		VictimDisplay = player.DisplayName,
		VictimGem = player:GetAttribute("EquippedGem"),
		Streak = streak,
		Ended = lostStreak, -- the victim's streak that just ended
	})
end

local function onCharacter(player: Player, character: Model)
	player:SetAttribute(PA.InArena, false)
	MovementGuard.Reset(player)
	resetStatus(character)

	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid or character.Parent == nil then
		return
	end
	humanoid.MaxHealth = CombatConfig.MaxHealth
	humanoid.Health = CombatConfig.MaxHealth
	humanoid.WalkSpeed = CombatConfig.WalkSpeed
	humanoid.UseJumpPower = false
	humanoid.JumpHeight = 7.2
	-- Overheads replace the default name / health display.
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff

	-- No passive regeneration: remove Roblox's default "Health" script.
	local function stripRegen(child: Instance)
		if child.Name == "Health" and child:IsA("Script") then
			child:Destroy()
		end
	end
	for _, child in character:GetChildren() do
		stripRegen(child)
	end
	character.ChildAdded:Connect(stripRegen)

	humanoid.Died:Connect(function()
		onDied(player, character)
	end)
end

local function onPlayerAdded(player: Player)
	player:SetAttribute(PA.InArena, false)
	player:SetAttribute(PA.Streak, 0)

	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local kills = Instance.new("IntValue")
	kills.Name = "Kills"
	kills.Parent = stats
	local streak = Instance.new("IntValue")
	streak.Name = "Streak"
	streak.Parent = stats
	stats.Parent = player

	-- Re-colour the blade if the equipped gem changes mid-fight.
	player:GetAttributeChangedSignal("EquippedGem"):Connect(function()
		local target = CombatService.ToTarget(player)
		if target then
			local color, accent = CombatService.ColorsOf(player)
			BladeBuilder.Build(target.Character, color, accent)
		end
	end)

	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
end

--------------------------------------------------------------------------------
-- Play
--------------------------------------------------------------------------------

local enterArena

local function onPlay(player: Player): (boolean, string?)
	if joining[player] then
		return false, "Busy"
	end
	joining[player] = true
	local ok, okOrError, reason = pcall(enterArena, player)
	joining[player] = nil
	if not ok then
		warn("[MatchService] entering the arena failed: " .. tostring(okOrError))
		return false, "NotReady"
	end
	return okOrError, reason
end

function enterArena(player: Player): (boolean, string?)
	if not PlayerData.IsLoaded(player) then
		return false, "NotLoaded"
	end
	if player:GetAttribute(PA.InArena) == true then
		return false, "AlreadyInArena"
	end
	if playCooldown(player) > 0 then
		return false, "Busy"
	end
	local folder = arena()
	if not folder then
		warn("[MatchService] Workspace.Map.Arena is missing; the arena can't open.")
		return false, "ArenaClosed"
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or humanoid.Health <= 0 or not (root and root:IsA("BasePart")) then
		return false, "NotReady"
	end
	local spawn = pickSpawn(folder, player)
	if not spawn then
		warn("[MatchService] Map.Arena has no ArenaSpawn parts.")
		return false, "ArenaClosed"
	end

	local destination = spawn.CFrame + Vector3.new(0, 3.5, 0)
	pcall(function()
		player:RequestStreamAroundAsync(destination.Position, 4)
	end)
	if character.Parent == nil or humanoid.Health <= 0 then
		return false, "NotReady"
	end

	resetStatus(character)
	ActionService.Reset(player)
	MovementGuard.Reset(player)
	character:PivotTo(destination)
	root.AssemblyLinearVelocity = Vector3.zero
	humanoid.Health = humanoid.MaxHealth
	character:SetAttribute(STATUS.InvulnerableUntil, CombatService.Now() + CombatConfig.SpawnProtection)
	character:SetAttribute(STATUS.SpawnProtected, true)

	local color, accent = CombatService.ColorsOf(player)
	BladeBuilder.Build(character, color, accent)
	player:SetAttribute(PA.InArena, true)
	CombatService.FX("Spawn", { Caster = character, Position = destination.Position, Color = color, Accent = accent })
	return true
end

--------------------------------------------------------------------------------
-- Bounds
--------------------------------------------------------------------------------

local function checkBounds()
	local folder = arena()
	if not folder then
		return
	end
	local center = folder:GetAttribute("Center")
	local radius = folder:GetAttribute("Radius")
	local killY = folder:GetAttribute("KillY")
	if typeof(center) ~= "Vector3" or type(radius) ~= "number" or type(killY) ~= "number" then
		return
	end

	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
			local position = root.Position
			local flat = Vector3.new(position.X - center.X, 0, position.Z - center.Z)
			if player:GetAttribute(PA.InArena) == true then
				if position.Y < killY then
					humanoid.Health = 0
				end
			elseif flat.Magnitude < radius and position.Z < center.Z + 26 and position.Y > killY then
				-- A lobby player got into the temple: back to the lobby.
				local spawn = lobbySpawn()
				if spawn then
					(character :: Model):PivotTo(spawn.CFrame + Vector3.new(0, 4, 0))
				end
			end
		end
	end
end

function MatchService.Init()
	Players.RespawnTime = CombatConfig.ReturnToLobbyDelay
	Remotes.RequestPlay.OnServerInvoke = onPlay

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		CombatService.Forget(player)
		joining[player] = nil
	end)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= BOUNDS_INTERVAL then
			elapsed = 0
			checkBounds()
		end
	end)
end

return MatchService
