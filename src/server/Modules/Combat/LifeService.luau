-- LifeService
-- Spawning, dying and keeping score in the open-world brawl:
--   * Every character spawns armed with its gem's weapon, a moment of spawn
--     protection and fresh cooldowns. Changing gem re-arms you.
--   * Defeat: the body vanishes and the fighter "poofs" into their gem, which
--     cracks and shatters into pieces (drawn by every client); after
--     CombatConfig.RespawnTime they reform at the lobby spawn.
--   * Kill credit (also for falls shortly after a hit), kills, streaks, best
--     streak, a small heal for the killer, the kill feed and streak shout-outs.
--   * leaderstats (Kills, Streak) for the in-server leaderboard.
--   * Tracks who is standing in the safe zone (player attribute InSafeZone).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))
local GemCatalog = require(ReplicatedStorage:WaitForChild("GemCatalog"))

local Combat = script.Parent
local Modules = Combat.Parent
local ActionService = require(Combat:WaitForChild("ActionService"))
local BeastService = require(Combat:WaitForChild("BeastService"))
local CombatService = require(Combat:WaitForChild("CombatService"))
local MovementGuard = require(Combat:WaitForChild("MovementGuard"))
local WeaponBuilder = require(Combat:WaitForChild("WeaponBuilder"))
local PlayerData = require(Modules:WaitForChild("PlayerData"))
local Remotes = require(Modules:WaitForChild("Remotes"))

local STATUS = CombatConfig.Status
local PA = CombatConfig.PlayerAttributes

local LifeService = {}

local function resetStatus(character: Model)
	character:SetAttribute(STATUS.StunnedUntil, 0)
	character:SetAttribute(STATUS.InvulnerableUntil, 0)
	character:SetAttribute(STATUS.BusyUntil, 0)
	character:SetAttribute(STATUS.SlowUntil, 0)
	character:SetAttribute(STATUS.MoveGraceUntil, 0)
	character:SetAttribute(STATUS.Blocking, false)
	character:SetAttribute(STATUS.Guard, CombatConfig.Block.MaxGuard)
	character:SetAttribute(STATUS.Combo, 0)
	character:SetAttribute(STATUS.ShieldHP, 0)
	character:SetAttribute(STATUS.ShieldUntil, 0)
	character:SetAttribute(STATUS.Shattered, false)
end

local function arm(player: Player, character: Model)
	if character:GetAttribute(STATUS.Shattered) == true then
		return
	end
	local kit = CombatService.KitOf(player)
	local color, accent = CombatService.ColorsOf(player)
	WeaponBuilder.Build(character, kit.Melee.Weapon, color, accent)
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

-- Hide the body: the fighter has retreated into their gem.
local function vanish(character: Model)
	WeaponBuilder.Remove(character)
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			local item: any = d
			item.Transparency = 1
		end
	end
end

local function onDied(player: Player, character: Model)
	if character:GetAttribute(STATUS.Shattered) == true then
		return
	end
	BeastService.Revert(character)
	character:SetAttribute(STATUS.Shattered, true)
	character:SetAttribute(STATUS.Blocking, false)

	local root = character:FindFirstChild("HumanoidRootPart")
	local color, accent = CombatService.ColorsOf(player)
	local gem = GemCatalog.Get(player:GetAttribute("EquippedGem"))
	if root and root:IsA("BasePart") then
		CombatService.FX("Shatter", {
			Caster = character,
			Position = root.Position,
			Ground = CombatService.Ground(root.Position),
			Color = color,
			Accent = accent,
			GemName = gem and gem.Name or "Quartz",
			RespawnTime = CombatConfig.RespawnTime,
		})
	end
	vanish(character)

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
			CombatService.Heal(target, CombatConfig.KillHeal)
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
		Milestone = table.find(CombatConfig.StreakMilestones, streak) ~= nil,
		Ended = lostStreak, -- the victim's streak that just ended
	})
end

local function onCharacter(player: Player, character: Model)
	resetStatus(character)
	ActionService.Reset(player)
	MovementGuard.Reset(player)

	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid or character.Parent == nil then
		return
	end
	humanoid.MaxHealth = CombatConfig.MaxHealth
	humanoid.Health = CombatConfig.MaxHealth
	humanoid.BreakJointsOnDeath = false -- the body vanishes into the gem instead
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

	character:SetAttribute(STATUS.InvulnerableUntil, CombatService.Now() + CombatConfig.SpawnProtection)
	character:SetAttribute(STATUS.SpawnProtected, true)
	character:WaitForChild("HumanoidRootPart", 10)
	-- Hands load with the rig; give them a frame.
	task.wait()
	arm(player, character)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local color, accent = CombatService.ColorsOf(player)
		CombatService.FX("Spawn", { Caster = character, Position = root.Position, Color = color, Accent = accent })
	end

	humanoid.Died:Connect(function()
		onDied(player, character)
	end)
end

local function onPlayerAdded(player: Player)
	player:SetAttribute(PA.Streak, 0)
	player:SetAttribute(PA.InSafeZone, false)

	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local kills = Instance.new("IntValue")
	kills.Name = "Kills"
	kills.Parent = stats
	local streak = Instance.new("IntValue")
	streak.Name = "Streak"
	streak.Parent = stats
	stats.Parent = player

	-- A new gem re-arms you (and ends a transformation from the old one).
	player:GetAttributeChangedSignal("EquippedGem"):Connect(function()
		local character = player.Character
		if character then
			BeastService.Revert(character)
			arm(player, character)
			ActionService.Reset(player)
		end
	end)

	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
end

local function trackSafeZone()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local inside = root ~= nil and root:IsA("BasePart") and CombatService.InSafeZone(root.Position)
		if player:GetAttribute(PA.InSafeZone) ~= inside then
			player:SetAttribute(PA.InSafeZone, inside)
			if inside and character then
				character:SetAttribute(STATUS.Blocking, false)
			end
		end
	end
end

function LifeService.Init()
	Players.RespawnTime = CombatConfig.RespawnTime
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		CombatService.Forget(player)
	end)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= 0.2 then
			elapsed = 0
			trackSafeZone()
		end
	end)
end

return LifeService
