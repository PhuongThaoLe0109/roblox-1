-- BeastService
-- The ultimate (G) of the rarest gems: the fighter transforms into a giant
-- crystal beast for a while. Their body is hidden inside a beast model welded
-- to the root (so everyone sees it); their strikes become the beast maul,
-- they take less damage and move at the beast's speed. Built from plain
-- Glass / Neon parts in the gem's colours, no meshes or textures.
--
-- Beasts: Prism Golem, Pyre Wyrm, Glacier Stag, Umbral Maw, Thunder Roc,
-- Dream Moth, Solar Lion, Star Koi.
--
-- The creatures themselves are sculpted and rigged in BeastModels.
-- Client contract: Model "Beast" tagged "BeastForm" (attribute Kind); every
-- bone is a Weld named after the bone, plus the "Mount" weld to the rider's
-- root. The client animates them locally (it only changes their C0).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))
local BeastModels = require(script.Parent:WaitForChild("BeastModels"))
local CombatService = require(script.Parent:WaitForChild("CombatService"))

local STATUS = CombatConfig.Status
local WHITE = Color3.new(1, 1, 1)

local BeastService = {}

--------------------------------------------------------------------------------
-- Building and transforming
--------------------------------------------------------------------------------

local function newPart(model: Model, name: string, size: Vector3, color: Color3, material: Enum.Material, transparency: number, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.Transparency = transparency
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = model
	return p
end

local function weld(part0: BasePart, part1: BasePart, c0: CFrame, name: string?)
	part1.CFrame = part0.CFrame * c0
	local w = Instance.new("Weld")
	w.Name = name or "Weld"
	w.Part0 = part0
	w.Part1 = part1
	w.C0 = c0
	w.Parent = part1
end

-- Builds a beast around `root` (nil root: built in place for offline checks).
function BeastService.Build(kind: string, color: Color3, accent: Color3, scale: number, root: BasePart?, groundOffset: number?): Model?
	local model = Instance.new("Model")
	model.Name = "Beast"
	model:SetAttribute("Kind", kind)

	local core = newPart(model, "Core", Vector3.new(0.2, 0.2, 0.2), WHITE, Enum.Material.SmoothPlastic, 1)
	model.PrimaryPart = core
	if root then
		weld(root, core, CFrame.new(0, -(groundOffset or 3), 0), "Mount")
	else
		core.CFrame = CFrame.new()
	end
	if not BeastModels.Build(kind, model, core, scale, color, accent) then
		model:Destroy()
		return nil
	end

	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 22
	light.Brightness = 2.5
	light.Shadows = false
	light.Parent = core

	CollectionService:AddTag(model, "BeastForm")
	return model
end

local hidden: { [Model]: { [Instance]: number } } = setmetatable({}, { __mode = "k" }) :: any

local function hideBody(character: Model)
	local saved = {}
	for _, d in character:GetDescendants() do
		if (d:IsA("BasePart") or d:IsA("Decal")) and d.Name ~= "HumanoidRootPart" then
			local item: any = d
			saved[d] = item.Transparency
			item.Transparency = 1
		end
	end
	hidden[character] = saved
end

local function showBody(character: Model)
	local saved = hidden[character]
	if not saved then
		return
	end
	for d, transparency in saved do
		if d.Parent then
			local item: any = d
			item.Transparency = transparency
		end
	end
	hidden[character] = nil
end

function BeastService.IsBeast(character: Model): boolean
	return character:GetAttribute(STATUS.Beast) ~= nil
end

-- Ends a transformation (time up, death or respawn).
function BeastService.Revert(character: Model)
	if not BeastService.IsBeast(character) then
		return
	end
	local beast = character:FindFirstChild("Beast")
	if beast then
		beast:Destroy()
	end
	character:SetAttribute(STATUS.Beast, nil)
	character:SetAttribute(STATUS.BeastUntil, 0)
	showBody(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		CombatService.FX("TransformEnd", { Caster = character, Position = root.Position })
	end
end

-- ctx = { Player, Character, Root, Skill, Kit }
function BeastService.Transform(ctx)
	local character: Model = ctx.Character
	if BeastService.IsBeast(character) then
		return
	end
	local skill = ctx.Skill
	local color, accent = CombatService.ColorsOf(ctx.Player)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local ground = humanoid.HipHeight + ctx.Root.Size.Y / 2
	if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		ground = 3
	end

	CombatService.FX("Transform", { Caster = character, Beast = skill.Beast, Name = skill.BeastName, Position = ctx.Root.Position, Color = color, Accent = accent, Element = ctx.Kit.Element })
	CombatService.Extend(character, STATUS.InvulnerableUntil, 0.8)
	CombatService.Extend(character, STATUS.BusyUntil, 0.8)
	task.wait(0.45)
	if humanoid.Health <= 0 or character.Parent == nil then
		return
	end

	local model = BeastService.Build(skill.Beast, color, accent, skill.Scale or 1, ctx.Root, ground)
	if not model then
		return
	end
	hideBody(character)
	model.Parent = character
	character:SetAttribute(STATUS.Beast, skill.Beast)
	character:SetAttribute(STATUS.BeastUntil, CombatService.Now() + skill.Duration)
	humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + 25)

	task.delay(skill.Duration, function()
		if character.Parent and character:GetAttribute(STATUS.Beast) == skill.Beast then
			BeastService.Revert(character)
		end
	end)
end

return BeastService
