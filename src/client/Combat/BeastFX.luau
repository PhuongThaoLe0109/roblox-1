-- BeastFX
-- Brings the crystal beasts (BeastService) to life on every client: wings
-- beat, tails sway, heads look around, arms and fins swing. Only the C0 of
-- the beast's joint welds is changed, locally, so it costs no network.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local BeastFX = {}

type Joint = { Weld: Weld, Base: CFrame, Name: string }
type Beast = { Model: Model, Joints: { Joint }, Phase: number }

local beasts: { [Model]: Beast } = {}

local JOINTS = { WingL = true, WingR = true, Tail = true, Head = true, ArmL = true, ArmR = true, FinL = true, FinR = true }

local function track(model: Instance)
	if not model:IsA("Model") or beasts[model] then
		return
	end
	local joints = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Weld") and JOINTS[d.Name] then
			table.insert(joints, { Weld = d, Base = d.C0, Name = d.Name })
		end
	end
	beasts[model] = { Model = model, Joints = joints, Phase = math.random() * 10 }
end

local function pose(name: string, t: number): CFrame
	if name == "WingL" or name == "WingR" then
		local side = if name == "WingL" then 1 else -1
		return CFrame.Angles(0, 0, side * math.sin(t * 5) * 0.45)
	elseif name == "FinL" or name == "FinR" then
		local side = if name == "FinL" then 1 else -1
		return CFrame.Angles(0, side * math.sin(t * 4) * 0.4, 0)
	elseif name == "Tail" then
		return CFrame.Angles(math.sin(t * 1.7) * 0.12, math.sin(t * 2.4) * 0.35, 0)
	elseif name == "Head" then
		return CFrame.Angles(math.sin(t * 1.3) * 0.08, math.sin(t * 0.7) * 0.25, 0)
	elseif name == "ArmL" or name == "ArmR" then
		local side = if name == "ArmL" then 1 else -1
		return CFrame.Angles(math.sin(t * 1.6 + side) * 0.15, 0, side * 0.05)
	end
	return CFrame.identity
end

function BeastFX.Start()
	CollectionService:GetInstanceAddedSignal("BeastForm"):Connect(function(model)
		task.defer(track, model)
	end)
	CollectionService:GetInstanceRemovedSignal("BeastForm"):Connect(function(model)
		beasts[model :: Model] = nil
	end)
	for _, model in CollectionService:GetTagged("BeastForm") do
		track(model)
	end
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		for model, beast in beasts do
			if model.Parent == nil then
				beasts[model] = nil
				continue
			end
			for _, joint in beast.Joints do
				joint.Weld.C0 = joint.Base * pose(joint.Name, t + beast.Phase)
			end
		end
	end)
end

return BeastFX
