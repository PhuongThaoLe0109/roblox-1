-- MapFX
-- Client-side animation for the world's decoration (smooth and free of
-- network cost). Works with StreamingEnabled: tagged objects are picked up as
-- they stream in.
--   MapSpin   Model or part: slow rotation + gentle bob
--             (attributes SpinSpeed, FloatHeight)
--   MapFloat  part: drifting bob and slow tumble
--   MapPulse  neon part: breathing transparency
--   MapRise   Model: rises along the light pillar and loops
--             (attributes RiseHeight, RiseSpeed)

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local MapFX = {}

type Entry = { Instance: Instance, Base: CFrame, Phase: number, Speed: number, Amp: number, Extra: number }

local spinning: { [Instance]: Entry } = {}
local floating: { [Instance]: Entry } = {}
local pulsing: { [Instance]: Entry } = {}
local rising: { [Instance]: Entry } = {}

local function pivotOf(instance: Instance): CFrame?
	if instance:IsA("Model") then
		return instance:GetPivot()
	elseif instance:IsA("BasePart") then
		return instance.CFrame
	end
	return nil
end

local function setPivot(instance: Instance, cf: CFrame)
	if instance:IsA("Model") then
		instance:PivotTo(cf)
	elseif instance:IsA("BasePart") then
		instance.CFrame = cf
	end
end

local function bind(tag: string, list: { [Instance]: Entry }, make: (Instance) -> Entry?)
	local function add(instance: Instance)
		if not list[instance] then
			local entry = make(instance)
			if entry then
				list[instance] = entry
			end
		end
	end
	for _, instance in CollectionService:GetTagged(tag) do
		add(instance)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance)
		list[instance] = nil
	end)
end

function MapFX.Start()
	bind("MapSpin", spinning, function(instance)
		local base = pivotOf(instance)
		return base and {
			Instance = instance,
			Base = base,
			Phase = math.random() * math.pi * 2,
			Speed = instance:GetAttribute("SpinSpeed") or 0.6,
			Amp = instance:GetAttribute("FloatHeight") or 1,
			Extra = 0,
		}
	end)
	bind("MapFloat", floating, function(instance)
		local base = pivotOf(instance)
		return base and {
			Instance = instance,
			Base = base,
			Phase = math.random() * math.pi * 2,
			Speed = 0.5 + math.random() * 0.7,
			Amp = 0.6 + math.random() * 1.6,
			Extra = math.random() * 0.6,
		}
	end)
	bind("MapPulse", pulsing, function(instance)
		if not instance:IsA("BasePart") then
			return nil
		end
		return {
			Instance = instance,
			Base = instance.CFrame,
			Phase = math.random() * math.pi * 2,
			Speed = 1.2 + math.random() * 0.8,
			Amp = instance.Transparency,
			Extra = 0,
		}
	end)
	bind("MapRise", rising, function(instance)
		local base = pivotOf(instance)
		return base and {
			Instance = instance,
			Base = base,
			Phase = math.random(),
			Speed = instance:GetAttribute("RiseSpeed") or 8,
			Amp = instance:GetAttribute("RiseHeight") or 120,
			Extra = 0,
		}
	end)

	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		for instance, e in spinning do
			if instance.Parent then
				local bob = math.sin(t * 1.3 + e.Phase) * e.Amp
				-- Rotate around world Y at the original position, keep the tilt.
				setPivot(instance, CFrame.new(e.Base.Position + Vector3.new(0, bob, 0)) * CFrame.Angles(0, t * e.Speed + e.Phase, 0) * e.Base.Rotation)
			end
		end
		for instance, e in floating do
			if instance.Parent then
				local bob = math.sin(t * e.Speed + e.Phase) * e.Amp
				setPivot(instance, e.Base * CFrame.new(0, bob, 0) * CFrame.Angles(0, t * e.Extra, 0))
			end
		end
		for instance, e in pulsing do
			if instance.Parent then
				local wave = (math.sin(t * e.Speed + e.Phase) + 1) / 2
				;(instance :: BasePart).Transparency = math.clamp(e.Amp + (wave - 0.5) * 0.35, 0, 0.95)
			end
		end
		for instance, e in rising do
			if instance.Parent then
				local progress = ((t * e.Speed / e.Amp) + e.Phase) % 1
				setPivot(instance, e.Base + Vector3.new(0, progress * e.Amp, 0))
			end
		end
	end)
end

return MapFX
