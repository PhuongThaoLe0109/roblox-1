-- PortalLabels
-- Floating labels over every portal, personalised to the local player's rank:
-- destination name plus "Unlocked" or the rank still required.
-- Billboards live in PlayerGui (local), adorned to the portal surfaces.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GemConfig = require(ReplicatedStorage:WaitForChild("GemConfig"))
local Theme = require(script.Parent:WaitForChild("Theme"))

local ATTR = GemConfig.Attributes
local C = Theme.Colors

local PortalLabels = {}

function PortalLabels.Init(_screen: ScreenGui)
	local player = Players.LocalPlayer
	local folder = Instance.new("Folder")
	folder.Name = "PortalLabels"
	folder.Parent = player:WaitForChild("PlayerGui")

	local labels: { [BasePart]: { Gui: BillboardGui, Status: TextLabel } } = {}

	local function update(surface: BasePart)
		local entry = labels[surface]
		if not entry then
			return
		end
		local required = surface:GetAttribute("RequiredRank") or 1
		local rank = player:GetAttribute(ATTR.Rank) or 1
		if rank >= required then
			entry.Status.Text = "✓ Step through"
			entry.Status.TextColor3 = C.Success
		else
			local info = GemConfig.Ranks[required]
			entry.Status.Text = `🔒 Rank {required} · {info and info.Name or "?"}`
			entry.Status.TextColor3 = C.Danger
		end
	end

	local function add(instance: Instance)
		if not instance:IsA("BasePart") or labels[instance] then
			return
		end
		local gui = Theme.new("BillboardGui", {
			Name = "PortalLabel",
			Adornee = instance,
			Size = UDim2.fromOffset(240, 64),
			StudsOffsetWorldSpace = Vector3.new(0, 15, 0),
			MaxDistance = 220,
			LightInfluence = 0,
			AlwaysOnTop = false,
			Parent = folder,
		})
		local name = Theme.label({
			Text = instance:GetAttribute("TargetName") or "Portal",
			Font = Theme.Fonts.Title,
			TextSize = 26,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextStrokeTransparency = 0.3,
			TextStrokeColor3 = Color3.fromRGB(60, 30, 80),
			Size = UDim2.new(1, 0, 0, 32),
			Parent = gui,
		})
		Theme.shimmer(name, nil, 0.35, 0)
		local status = Theme.label({
			Text = "",
			Font = Theme.Fonts.Bold,
			TextSize = 17,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextStrokeTransparency = 0.4,
			Position = UDim2.fromOffset(0, 34),
			Size = UDim2.new(1, 0, 0, 22),
			Parent = gui,
		})
		labels[instance] = { Gui = gui, Status = status }
		update(instance)
	end

	local function remove(instance: Instance)
		local entry = labels[instance :: BasePart]
		if entry then
			entry.Gui:Destroy()
			labels[instance :: BasePart] = nil
		end
	end

	for _, instance in CollectionService:GetTagged(GemConfig.Tags.Portal) do
		add(instance)
	end
	CollectionService:GetInstanceAddedSignal(GemConfig.Tags.Portal):Connect(add)
	CollectionService:GetInstanceRemovedSignal(GemConfig.Tags.Portal):Connect(remove)

	player:GetAttributeChangedSignal(ATTR.Rank):Connect(function()
		for surface in labels do
			update(surface)
		end
	end)
end

return PortalLabels
