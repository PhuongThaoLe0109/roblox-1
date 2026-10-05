-- Auras
-- Draws every player's aura locally, from the gem they wear (the
-- "EquippedGem" player attribute). Auras are client-only: smooth at any frame
-- rate, no network cost, and the server stays authoritative over who owns what.
--
--   * One recipe per gem (Recipes) built from shared layers (Layers).
--   * All part moves of a frame go out in a single Workspace:BulkMoveTo.
--   * Auras far from the camera are unparented until they come back in range.
--   * Auras.SetPreview(gemId?) lets the Inventory "try on" a gem on your own
--     character before equipping it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GemCatalog = require(ReplicatedStorage:WaitForChild("GemCatalog"))
local Layers = require(script.Parent:WaitForChild("Layers"))
local Recipes = require(script.Parent:WaitForChild("Recipes"))

local localPlayer = Players.LocalPlayer

local Auras = {}

local CULL_DISTANCE = 260

type Aura = {
	GemId: string,
	Model: Model,
	Root: BasePart,
	Updates: { Layers.Update },
	Started: number,
	Visible: boolean,
}

local folder: Folder
local auras: { [Player]: Aura } = {}
local preview: string? = nil

local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}
local function place(p: BasePart, cf: CFrame)
	local n = #moveParts + 1
	moveParts[n] = p
	moveFrames[n] = cf
end

local function tierOf(odds: number): number
	if odds < 1_000 then
		return 1
	elseif odds < 100_000 then
		return 2
	elseif odds < 10_000_000 then
		return 3
	elseif odds < 1_000_000_000 then
		return 4
	end
	return 5
end

-- Builds an aura model for a gem around `root`. Returns nil for unknown gems.
function Auras.Build(gemId: string, root: BasePart, parent: Instance, groundOffset: number?): Aura?
	local gem = GemCatalog.Get(gemId)
	local recipe = Recipes.Get(gemId)
	if not gem or not recipe then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "Aura_" .. gem.Id
	local ctx: Layers.Context = {
		Parent = model,
		Color = gem.Color,
		Accent = gem.Accent,
		Seed = gem.Index,
		Ground = -(groundOffset or 3),
		Place = place,
		Rng = Random.new(gem.Index * 7919 + 17),
	}
	local tier = tierOf(gem.Odds)
	local updates: { Layers.Update } = {
		Layers.Glow(ctx, { Range = 6 + tier * 3, Brightness = 0.5 + tier * 0.3 }),
	}
	for _, spec in recipe do
		local layer = (Layers :: any)[spec.Kind]
		if layer then
			local ok, update = pcall(layer, ctx, spec)
			if ok then
				table.insert(updates, update)
			else
				warn(`[Auras] {gem.Id} {spec.Kind}: {update}`)
			end
		end
	end
	model.Parent = parent
	return {
		GemId = gem.Id,
		Model = model,
		Root = root,
		Updates = updates,
		Started = os.clock() - math.random() * 10,
		Visible = true,
	}
end

local function groundOffset(character: Model, root: BasePart): number
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hip = humanoid and humanoid.HipHeight or 0
	if hip <= 0.1 then
		return 3 -- R6 rigs report no hip height
	end
	return hip + root.Size.Y / 2
end

local function clear(player: Player)
	local aura = auras[player]
	if aura then
		aura.Model:Destroy()
		auras[player] = nil
	end
end

local function refresh(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local gemId = if player == localPlayer and preview then preview else player:GetAttribute("EquippedGem")
	if not character or not (root and root:IsA("BasePart")) or not humanoid or humanoid.Health <= 0 or type(gemId) ~= "string" then
		clear(player)
		return
	end
	local current = auras[player]
	if current and current.GemId == gemId and current.Root == root then
		return
	end
	clear(player)
	local aura = Auras.Build(gemId, root, folder, groundOffset(character, root))
	if aura then
		auras[player] = aura
	end
end

local function watch(player: Player)
	player:GetAttributeChangedSignal("EquippedGem"):Connect(function()
		refresh(player)
	end)
	local function onCharacter(character: Model)
		clear(player)
		local humanoid = character:WaitForChild("Humanoid", 10)
		character:WaitForChild("HumanoidRootPart", 10)
		if humanoid and humanoid:IsA("Humanoid") then
			humanoid.Died:Connect(function()
				clear(player)
			end)
		end
		refresh(player)
	end
	player.CharacterAdded:Connect(onCharacter)
	player.CharacterRemoving:Connect(function()
		clear(player)
	end)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

-- Try a gem on your own character (nil = back to the equipped gem).
function Auras.SetPreview(gemId: string?)
	if preview == gemId then
		return
	end
	preview = gemId
	refresh(localPlayer)
end

local function step()
	local camera = Workspace.CurrentCamera
	local eye = camera and camera.CFrame.Position or Vector3.zero
	local now = os.clock()
	table.clear(moveParts)
	table.clear(moveFrames)
	for player, aura in auras do
		local root = aura.Root
		if root.Parent == nil then
			clear(player)
			continue
		end
		local near = (root.Position - eye).Magnitude < CULL_DISTANCE
		if near ~= aura.Visible then
			aura.Visible = near
			aura.Model.Parent = if near then folder else nil
		end
		if near then
			local t = now - aura.Started
			local cf = root.CFrame
			for _, update in aura.Updates do
				update(t, cf)
			end
		end
	end
	if #moveParts > 0 then
		Workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function Auras.Start()
	folder = Instance.new("Folder")
	folder.Name = "Auras"
	folder.Parent = Workspace

	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(clear)
	for _, player in Players:GetPlayers() do
		task.spawn(watch, player)
	end
	RunService.RenderStepped:Connect(function()
		local ok, err = pcall(step)
		if not ok then
			warn("[Auras] " .. tostring(err))
		end
	end)
end

return Auras
