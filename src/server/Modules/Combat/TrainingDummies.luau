-- TrainingDummies
-- Crystal training dummies on the hub so skills can be tested solo.
-- Tagged CombatDummy: always hittable (even in the safe hub), regenerate when
-- left alone, drift back to their post after knockbacks, respawn after defeat.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))

local TrainingDummies = {}

local MAX_HEALTH = 400
local REGEN_DELAY = 3
local POSTS = {
	Vector3.new(-24, 0, 62),
	Vector3.new(0, 0, 68),
	Vector3.new(24, 0, 62),
}
local BODY_COLOR = Color3.fromRGB(215, 195, 245)

local function buildDummy(index: number, post: Vector3, parent: Instance)
	local description = Instance.new("HumanoidDescription")
	for _, field in { "HeadColor", "TorsoColor", "LeftArmColor", "RightArmColor", "LeftLegColor", "RightLegColor" } do
		(description :: any)[field] = BODY_COLOR
	end

	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		warn(`[TrainingDummies] Could not create dummy: {model}`)
		return
	end

	model.Name = "TrainingCrystal" .. index
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayName = "Training Crystal"
	humanoid.MaxHealth = MAX_HEALTH
	humanoid.Health = MAX_HEALTH
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.BreakJointsOnDeath = false
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOn
	humanoid.NameDisplayDistance = 60

	-- Facing the hub centre.
	model:PivotTo(CFrame.lookAt(post + Vector3.new(0, 3.2, 0), Vector3.new(0, 3.2, 0)))
	CollectionService:AddTag(model, CombatConfig.Tags.Dummy)
	model.Parent = parent

	local lastHit = os.clock()
	local lastHealth = humanoid.Health
	humanoid.HealthChanged:Connect(function(health)
		if health < lastHealth then
			lastHit = os.clock()
		end
		lastHealth = health
	end)

	humanoid.Died:Connect(function()
		task.delay(2.5, function()
			model:Destroy()
			buildDummy(index, post, parent)
		end)
	end)

	task.spawn(function()
		while model.Parent and humanoid.Health > 0 do
			task.wait(1)
			if os.clock() - lastHit > REGEN_DELAY then
				humanoid.Health = MAX_HEALTH
				local root = model:FindFirstChild("HumanoidRootPart")
				if root and (root.Position - post).Magnitude > 12 then
					model:PivotTo(CFrame.lookAt(post + Vector3.new(0, 3.2, 0), Vector3.new(0, 3.2, 0)))
				end
			end
		end
	end)
end

function TrainingDummies.Init(map: Instance)
	local hub = map:FindFirstChild("Hub")
	if not hub then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "TrainingDummies"
	folder.Parent = hub
	for index, post in POSTS do
		task.spawn(buildDummy, index, post, folder)
	end
end

return TrainingDummies
