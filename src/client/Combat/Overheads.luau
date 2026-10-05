-- Overheads
-- A title floating over every fighter (yourself included), like a rare-aura
-- title: the gem they wear in its own gradient lettering, its rarity
-- ("1 in 250,000,000"), their name, a health bar (with Aegis shield) and
-- their kill streak, plus status tags (STUNNED, ROOTED, HEXED, SLOWED).
-- Built locally on each client; replaces Roblox's default name and health.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))
local GemCatalog = require(ReplicatedStorage:WaitForChild("GemCatalog"))
local UI = script.Parent.Parent:WaitForChild("UI")
local GemArt = require(UI:WaitForChild("GemArt"))
local Theme = require(UI:WaitForChild("Theme"))

local STATUS = CombatConfig.Status
local PA = CombatConfig.PlayerAttributes
local C = Theme.Colors

local Overheads = {}

type Overhead = {
	Gui: BillboardGui,
	Player: Player,
	Character: Model,
	Humanoid: Humanoid,
	Gem: TextLabel,
	GemGradient: UIGradient,
	Odds: TextLabel,
	Name: TextLabel,
	Fill: Frame,
	FillGradient: UIGradient,
	Shield: Frame,
	Streak: TextLabel,
	Status: TextLabel,
}

local folder: Folder
local overheads: { [Model]: Overhead } = {}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function refreshGem(o: Overhead)
	local gem = GemCatalog.Get(o.Player:GetAttribute("EquippedGem"))
	if not gem then
		o.Gem.Text = ""
		o.Odds.Text = ""
		return
	end
	o.Gem.Text = gem.Name
	o.GemGradient.Color = if GemArt.Tier(gem) >= 4 then GemArt.Rainbow else GemArt.Gradient(gem)
	o.Odds.Text = GemCatalog.FormatOdds(gem.Odds)
	o.Odds.TextColor3 = if GemArt.Tier(gem) >= 3 then C.Gold else C.SubText
	local h, s = gem.Color:ToHSV()
	o.FillGradient.Color = ColorSequence.new(gem.Color, Color3.fromHSV(h, s * 0.4, 1))
end

local function build(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local head = character:WaitForChild("Head", 10)
	if not humanoid or not humanoid:IsA("Humanoid") or not head or not head:IsA("BasePart") then
		return
	end
	local old = overheads[character]
	if old then
		old.Gui:Destroy()
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = player.Name
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(240, 104)
	gui.StudsOffset = Vector3.new(0, 3.4, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 150
	gui.ResetOnSpawn = false
	gui.Parent = folder

	local gemLabel = Theme.headline({
		Text = "",
		TextSize = 26,
		Size = UDim2.new(1, 0, 0, 32),
		Parent = gui,
	}, nil, 0.4)
	local odds = Theme.label({
		Text = "",
		FontFace = Theme.Faces.Odds,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.35,
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = gui,
	})
	local name = Theme.label({
		Text = player.DisplayName,
		FontFace = Theme.Faces.Heavy,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.4,
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.new(1, 0, 0, 18),
		Parent = gui,
	})
	local bar = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 72),
		Size = UDim2.fromOffset(150, 9),
		BackgroundColor3 = Color3.fromRGB(20, 12, 34),
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = gui,
	})
	Theme.round().Parent = bar
	Theme.new("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.6, Thickness = 1, Parent = bar })
	local fill = Theme.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = bar,
	})
	Theme.round().Parent = fill
	local fillGradient = Theme.new("UIGradient", { Parent = fill })
	local shield = Theme.new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = C.Cyan,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Parent = bar,
	})
	Theme.round().Parent = shield
	local streak = Theme.label({
		Text = "",
		FontFace = Theme.Faces.Heavy,
		TextSize = 13,
		TextColor3 = C.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 0.4,
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(0.5, 80, 0, 68),
		Size = UDim2.fromOffset(40, 16),
		Parent = gui,
	})
	local status = Theme.label({
		Text = "",
		FontFace = Theme.Faces.Odds,
		TextSize = 11,
		TextColor3 = C.Danger,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.3,
		Position = UDim2.fromOffset(0, 84),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = gui,
	})

	local o: Overhead = {
		Gui = gui,
		Player = player,
		Character = character,
		Humanoid = humanoid,
		Gem = gemLabel,
		GemGradient = gemLabel:FindFirstChildOfClass("UIGradient") :: UIGradient,
		Odds = odds,
		Name = name,
		Fill = fill,
		FillGradient = fillGradient,
		Shield = shield,
		Streak = streak,
		Status = status,
	}
	overheads[character] = o
	refreshGem(o)
	character.Destroying:Connect(function()
		gui:Destroy()
		overheads[character] = nil
	end)
end

local function watch(player: Player)
	player.CharacterAdded:Connect(function(character)
		build(player, character)
	end)
	player:GetAttributeChangedSignal("EquippedGem"):Connect(function()
		local o = player.Character and overheads[player.Character]
		if o then
			refreshGem(o)
		end
	end)
	if player.Character then
		task.spawn(build, player, player.Character)
	end
end

local function update()
	local t = now()
	for character, o in overheads do
		if character.Parent == nil then
			o.Gui:Destroy()
			overheads[character] = nil
			continue
		end
		local shattered = character:GetAttribute(STATUS.Shattered) == true
		o.Gui.Enabled = not shattered
		if shattered then
			continue
		end
		local humanoid = o.Humanoid
		local hp = math.clamp(humanoid.Health / math.max(1, humanoid.MaxHealth), 0, 1)
		o.Fill.Size = UDim2.fromScale(hp, 1)
		o.Fill.BackgroundColor3 = if hp < 0.3 then C.Danger else Color3.new(1, 1, 1)
		local shield = if (character:GetAttribute(STATUS.ShieldUntil) or 0) > t then character:GetAttribute(STATUS.ShieldHP) or 0 else 0
		o.Shield.Size = UDim2.fromScale(math.clamp(shield / math.max(1, humanoid.MaxHealth), 0, 1), 1)
		local streak = o.Player:GetAttribute(PA.Streak) or 0
		o.Streak.Text = if streak >= 2 then `✦{streak}` else ""

		local tags = {}
		if (character:GetAttribute(STATUS.StunnedUntil) or 0) > t then
			table.insert(tags, "STUNNED")
		end
		if (character:GetAttribute(STATUS.RootedUntil) or 0) > t then
			table.insert(tags, "ROOTED")
		end
		if (character:GetAttribute(STATUS.SlowedUntil) or 0) > t then
			table.insert(tags, "SLOWED")
		end
		if (character:GetAttribute(STATUS.CursedUntil) or 0) > t then
			table.insert(tags, "HEXED")
		end
		if (character:GetAttribute(STATUS.InvulnerableUntil) or 0) > t and character:GetAttribute(STATUS.SpawnProtected) then
			table.insert(tags, "PROTECTED")
		end
		if o.Player:GetAttribute(PA.InSafeZone) == true then
			tags = { "SAFE" }
		end
		o.Status.Text = table.concat(tags, " · ")
		o.Status.TextColor3 = if tags[1] == "SAFE" or tags[1] == "PROTECTED" then C.Success else C.Danger

		-- Beasts are big: lift the title above them.
		local beast = character:GetAttribute(STATUS.Beast)
		o.Gui.StudsOffset = Vector3.new(0, if beast then 15 else 3.4, 0)
	end
end

function Overheads.Start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	folder = Instance.new("Folder")
	folder.Name = "Overheads"
	folder.Parent = playerGui
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		task.spawn(watch, player)
	end
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= 0.1 then
			elapsed = 0
			update()
		end
	end)
end

return Overheads
