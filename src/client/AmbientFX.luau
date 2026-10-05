-- AmbientFX
-- Client-side decorative motion, so it is perfectly smooth and costs nothing
-- on the network:
--   * "Spin"  tagged parts rotate slowly around world Y and bob a little.
--   * "Float" tagged parts bob up and down.
--   * Portal surfaces pulse their transparency and drift toward white.
-- Works with StreamingEnabled: parts are picked up as they stream in.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GemConfig = require(ReplicatedStorage:WaitForChild("GemConfig"))

local AmbientFX = {}

type Entry = { Part: BasePart, Base: CFrame, Phase: number, Speed: number, Amplitude: number }

local spinners: { [BasePart]: Entry } = {}
local floaters: { [BasePart]: Entry } = {}
local portals: { [BasePart]: { Color: Color3, Phase: number } } = {}

local function track(list: { [BasePart]: Entry }, speed: number, amplitude: number)
	return function(instance: Instance)
		if instance:IsA("BasePart") and not list[instance] then
			list[instance] = {
				Part = instance,
				Base = instance.CFrame,
				Phase = math.random() * math.pi * 2,
				Speed = speed * (0.8 + math.random() * 0.4),
				Amplitude = amplitude * (0.7 + math.random() * 0.6),
			}
		end
	end
end

local function untrack(list: { [any]: any })
	return function(instance: Instance)
		list[instance] = nil
	end
end

local function bind(tag: string, onAdded: (Instance) -> (), onRemoved: (Instance) -> ())
	for _, instance in CollectionService:GetTagged(tag) do
		onAdded(instance)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(onAdded)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(onRemoved)
end

function AmbientFX.Start()
	bind("Spin", track(spinners, 0.6, 1.2), untrack(spinners))
	bind("Float", track(floaters, 0.9, 1.6), untrack(floaters))
	bind(GemConfig.Tags.Portal, function(instance)
		if instance:IsA("BasePart") then
			portals[instance] = { Color = instance.Color, Phase = math.random() * 6 }
		end
	end, untrack(portals))

	RunService.RenderStepped:Connect(function()
		local t = os.clock()

		for part, entry in spinners do
			if part.Parent then
				local bob = math.sin(t * entry.Speed * 1.5 + entry.Phase) * entry.Amplitude
				local rotation = CFrame.Angles(0, t * entry.Speed + entry.Phase, 0)
				-- Rotate around world Y at the original position, keeping the part's own tilt.
				part.CFrame = CFrame.new(entry.Base.Position + Vector3.new(0, bob, 0)) * rotation * entry.Base.Rotation
			end
		end

		for part, entry in floaters do
			if part.Parent then
				local bob = math.sin(t * entry.Speed + entry.Phase) * entry.Amplitude
				part.CFrame = entry.Base + Vector3.new(0, bob, 0)
			end
		end

		for part, data in portals do
			if part.Parent then
				local pulse = (math.sin(t * 2.2 + data.Phase) + 1) / 2
				part.Transparency = 0.25 + pulse * 0.25
				part.Color = data.Color:Lerp(Color3.new(1, 1, 1), pulse * 0.45)
			end
		end
	end)
end

return AmbientFX
