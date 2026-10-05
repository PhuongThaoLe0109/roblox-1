-- PuffOverlay
--   * While the local gem is puffed: a soft pastel overlay, desaturated world,
--     "PUFFED!" title, reform countdown, live Sealing/Reviving warning and a
--     Return Home button.
--   * Shows each capsule's Seal / Revive prompt only to the players who may use
--     it (enemies seal, allies revive). The server re-validates every trigger.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))
local GemConfig = require(ReplicatedStorage:WaitForChild("GemConfig"))
local Theme = require(script.Parent:WaitForChild("Theme"))

local STATUS = CombatConfig.Status
local C = Theme.Colors

local PuffOverlay = {}

function PuffOverlay.Init(screen: ScreenGui)
	local player = Players.LocalPlayer
	local remote = ReplicatedStorage:WaitForChild("GemRemotes"):WaitForChild("PuffAction") :: RemoteEvent

	----------------------------------------------------------------------------
	-- Prompt filtering
	----------------------------------------------------------------------------
	local function isAlly(ownerUserId: number): boolean
		if ownerUserId == 0 then
			return false -- training dummy
		end
		local owner = Players:GetPlayerByUserId(ownerUserId)
		local mine = player:GetAttribute(GemConfig.Attributes.Faction)
		local theirs = owner and owner:GetAttribute(GemConfig.Attributes.Faction)
		return mine ~= nil and mine == theirs and mine ~= "Neutral"
	end

	local function filter(prompt: Instance)
		if not prompt:IsA("ProximityPrompt") then
			return
		end
		local owner = prompt:GetAttribute("OwnerUserId") or 0
		if owner == player.UserId then
			prompt.Enabled = false
			return
		end
		local ally = isAlly(owner)
		local kind = prompt:GetAttribute("Kind")
		prompt.Enabled = if kind == "Seal" then not ally else ally
	end

	for _, prompt in CollectionService:GetTagged(CombatConfig.Tags.PuffPrompt) do
		filter(prompt)
	end
	CollectionService:GetInstanceAddedSignal(CombatConfig.Tags.PuffPrompt):Connect(filter)
	player:GetAttributeChangedSignal(GemConfig.Attributes.Faction):Connect(function()
		for _, prompt in CollectionService:GetTagged(CombatConfig.Tags.PuffPrompt) do
			filter(prompt)
		end
	end)

	----------------------------------------------------------------------------
	-- Overlay
	----------------------------------------------------------------------------
	local overlay = Theme.new("Frame", {
		Name = "PuffOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 30,
		Parent = screen,
	})
	local tint = Theme.new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 180, 220)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(200, 170, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 180, 220)),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(0.5, 0.85),
			NumberSequenceKeypoint.new(1, 0.35),
		}),
		Rotation = 90,
		Parent = overlay,
	})
	local _ = tint

	local title = Theme.label({
		Text = "PUFFED!",
		Font = Theme.Fonts.Title,
		TextSize = 76,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.4,
		TextStrokeColor3 = Color3.fromRGB(110, 50, 120),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.new(1, 0, 0, 86),
		ZIndex = 31,
		Parent = overlay,
	})
	Theme.shimmer(title, nil, 0.5, 0)
	local titleScale = Theme.new("UIScale", { Parent = title })

	local countdown = Theme.label({
		Text = "",
		Font = Theme.Fonts.Title,
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.5,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.3, 50),
		Size = UDim2.new(1, 0, 0, 34),
		ZIndex = 31,
		Parent = overlay,
	})
	local status = Theme.label({
		Text = "",
		Font = Theme.Fonts.Bold,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.4,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.3, 90),
		Size = UDim2.new(1, 0, 0, 28),
		ZIndex = 31,
		Parent = overlay,
	})
	local homeButton = Theme.button("⌂ Return Home", C.Lavender, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.3, 136),
		Size = UDim2.fromOffset(220, 48),
		TextSize = 20,
		ZIndex = 32,
		Parent = overlay,
	})
	homeButton.Activated:Connect(function()
		remote:FireServer("ReturnHome")
	end)

	local grey = Instance.new("ColorCorrectionEffect")
	grey.Name = "PuffDesaturate"
	grey.Saturation = 0
	grey.Enabled = false
	grey.Parent = Lighting

	local shown = false
	local function setShown(value: boolean)
		if value == shown then
			return
		end
		shown = value
		if value then
			overlay.Visible = true
			overlay.BackgroundTransparency = 0.2
			Theme.tween(overlay, 0.8, { BackgroundTransparency = 1 })
			titleScale.Scale = 0.3
			Theme.tween(titleScale, 0.6, { Scale = 1 }, Enum.EasingStyle.Back)
			grey.Enabled = true
			Theme.tween(grey, 0.6, { Saturation = -0.55 })
		else
			overlay.Visible = false
			Theme.tween(grey, 0.5, { Saturation = 0 })
			task.delay(0.5, function()
				if not shown then
					grey.Enabled = false
				end
			end)
		end
	end

	RunService.RenderStepped:Connect(function()
		local character = player.Character
		local isPuffed = character ~= nil and character:GetAttribute(STATUS.Puffed) == true
		setShown(isPuffed)
		if not isPuffed or not character then
			return
		end
		local remaining = (character:GetAttribute(STATUS.PuffedUntil) or 0) - Workspace:GetServerTimeNow()
		countdown.Text = if remaining > 0 then `Your gem reforms in {math.ceil(remaining)}…` else "Reforming…"

		local action = character:GetAttribute(STATUS.PuffAction)
		if action == "Sealing" then
			status.Text = "⚠ An enemy is sealing your gem!"
			status.TextColor3 = C.Danger
		elseif action == "Reviving" then
			status.Text = "✦ An ally is reviving you!"
			status.TextColor3 = C.Success
		else
			status.Text = ""
		end
	end)
end

return PuffOverlay
