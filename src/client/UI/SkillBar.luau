-- SkillBar
-- Bottom-centre bar for the summoned weapon: name, four slots (Attack, Q, E,
-- R) with icons, key hints and a draining cooldown overlay, a ready flash,
-- a shake when a press is rejected, and a hover tooltip describing the skill.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))
local GemConfig = require(ReplicatedStorage:WaitForChild("GemConfig"))
local WeaponConfig = require(ReplicatedStorage:WaitForChild("WeaponConfig"))
local Theme = require(script.Parent:WaitForChild("Theme"))

local C = Theme.Colors
local STATUS = CombatConfig.Status

local SkillBar = {}

local SLOT_SIZE = 74
local KEYS = { Basic = "LMB", Q = "Q", E = "E", R = "R" }
local GAMEPAD_KEYS = { Basic = "R2", Q = "X", E = "B", R = "R1" }
local BASIC_ICONS = { Melee = "⚔", Projectile = "✦" }

function SkillBar.Init(screen: ScreenGui, context)
	local player = Players.LocalPlayer
	local controller = context.WeaponController

	local root = Theme.new("Frame", {
		Name = "SkillBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(4 * SLOT_SIZE + 3 * 10 + 28, SLOT_SIZE + 64),
		BackgroundTransparency = 1,
		Parent = screen,
	})

	local title = Theme.label({
		Text = "",
		Font = Theme.Fonts.Title,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.5,
		TextStrokeColor3 = Color3.fromRGB(50, 25, 70),
		Size = UDim2.new(1, 0, 0, 26),
		Parent = root,
	})
	local titleGradient = Theme.shimmer(title, nil, 0.3, 0)

	local hint = Theme.label({
		Text = "",
		TextSize = 14,
		TextColor3 = C.SubText,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.6,
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 0, 18),
		Parent = root,
	})

	local bar = Theme.panel({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, SLOT_SIZE + 16),
		Parent = root,
	})
	Theme.list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center).Parent = bar

	-- Tooltip
	local tooltip = Theme.panel({
		Name = "Tooltip",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -8),
		Size = UDim2.fromOffset(300, 92),
		Visible = false,
		ZIndex = 5,
		Parent = root,
	})
	Theme.padding(10, 14).Parent = tooltip
	local tipTitle = Theme.label({ Text = "", Font = Theme.Fonts.Title, TextSize = 18, Size = UDim2.new(1, 0, 0, 22), ZIndex = 6, Parent = tooltip })
	local tipBody = Theme.label({
		Text = "",
		TextSize = 13,
		TextColor3 = C.SubText,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 1, -24),
		ZIndex = 6,
		Parent = tooltip,
	})

	type Slot = {
		Frame: Frame,
		Icon: TextLabel,
		Name: TextLabel,
		Key: TextLabel,
		Overlay: Frame,
		Timer: TextLabel,
		Stroke: UIStroke,
		Scale: UIScale,
		WasReady: boolean,
	}
	local slots: { [string]: Slot } = {}

	for order, slotName in WeaponConfig.SlotOrder do
		local frame = Theme.new("TextButton", {
			Name = slotName,
			LayoutOrder = order,
			Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE),
			BackgroundColor3 = C.PanelLight,
			AutoButtonColor = false,
			Text = "",
			ClipsDescendants = true,
			BorderSizePixel = 0,
			Parent = bar,
		}, { Theme.corner(14) })
		local fill = Theme.new("UIGradient", { Rotation = 90, Parent = frame })
		fill.Color = ColorSequence.new(Color3.fromRGB(90, 70, 140), Color3.fromRGB(40, 28, 70))
		local stroke = Theme.stroke(Color3.new(1, 1, 1), 2, 0.1)
		stroke.Parent = frame
		Theme.shimmer(stroke, nil, 0.35)
		local scale = Theme.new("UIScale", { Parent = frame })

		local icon = Theme.label({
			Text = "",
			Font = Theme.Fonts.Title,
			TextSize = 30,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, 8),
			Size = UDim2.new(1, 0, 0, 34),
			Parent = frame,
		})
		Theme.shimmer(icon, nil, 0.5, 45)
		local name = Theme.label({
			Text = "",
			Font = Theme.Fonts.Bold,
			TextSize = 10,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(2, 44),
			Size = UDim2.new(1, -4, 0, 26),
			Parent = frame,
		})
		local key = Theme.new("TextLabel", {
			Text = KEYS[slotName],
			Font = Theme.Fonts.Title,
			TextSize = 12,
			TextColor3 = Color3.fromRGB(40, 30, 60),
			BackgroundColor3 = C.Gold,
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.fromOffset(28, 16),
			ZIndex = 3,
			BorderSizePixel = 0,
			Parent = frame,
		}, { Theme.corner(5) })
		local overlay = Theme.new("Frame", {
			Name = "Cooldown",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 0),
			BackgroundColor3 = Color3.fromRGB(10, 6, 24),
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = frame,
		})
		local timer = Theme.label({
			Text = "",
			Font = Theme.Fonts.Title,
			TextSize = 24,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextStrokeTransparency = 0.3,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 4,
			Parent = frame,
		})

		slots[slotName] = {
			Frame = frame,
			Icon = icon,
			Name = name,
			Key = key,
			Overlay = overlay,
			Timer = timer,
			Stroke = stroke,
			Scale = scale,
			WasReady = true,
		}

		frame.Activated:Connect(function()
			controller.Use(slotName)
		end)
		frame.MouseEnter:Connect(function()
			local weapon = controller.GetWeapon()
			local config = weapon and WeaponConfig.GetSlot(weapon, slotName) :: any
			if not config then
				return
			end
			tipTitle.Text = `{config.Name}  ·  {config.Cooldown}s`
			tipBody.Text = config.Description or (if slotName == "Basic" then "Basic attack. Every third melee hit is a finisher." else "")
			tooltip.Visible = true
		end)
		frame.MouseLeave:Connect(function()
			tooltip.Visible = false
		end)
	end

	local function refreshWeapon()
		local weapon = controller.GetWeapon()
		if not weapon then
			title.Text = ""
			return
		end
		title.Text = weapon.DisplayName
		local h, s = weapon.Color:ToHSV()
		titleGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, weapon.Color),
			ColorSequenceKeypoint.new(0.5, Color3.fromHSV(h, s * 0.2, 1)),
			ColorSequenceKeypoint.new(1, weapon.Glow),
		})
		for slotName, slot in slots do
			local config = WeaponConfig.GetSlot(weapon, slotName) :: any
			slot.Icon.Text = if slotName == "Basic" then BASIC_ICONS[config.Kind] or "⚔" else config.Icon
			slot.Name.Text = config.Name
			slot.Icon.TextColor3 = Color3.new(1, 1, 1)
		end
	end

	local function refreshKeys()
		local gamepad = UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled
		for slotName, slot in slots do
			slot.Key.Text = if gamepad then GAMEPAD_KEYS[slotName] else KEYS[slotName]
			slot.Key.Visible = not UserInputService.TouchEnabled or UserInputService.KeyboardEnabled
		end
	end

	controller.Rejected:Connect(function(slotName, reason)
		local slot = slots[slotName]
		if slot and reason ~= "Summoning" then
			-- Wiggle (the list layout owns Position, so shake via Rotation).
			local frame = slot.Frame
			task.spawn(function()
				for i = 1, 4 do
					frame.Rotation = if i % 2 == 0 then 4 else -4
					task.wait(0.035)
				end
				frame.Rotation = 0
			end)
		end
	end)
	controller.Pressed:Connect(function(slotName)
		local slot = slots[slotName]
		if slot then
			slot.Scale.Scale = 0.9
			Theme.tween(slot.Scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end)

	RunService.RenderStepped:Connect(function()
		local t = Workspace:GetServerTimeNow()
		local character = player.Character
		local summoned = character and character:GetAttribute(STATUS.WeaponSummoned) == true
		hint.Text = if summoned
			then ""
			elseif UserInputService.TouchEnabled then "Tap Weapon to summon your light-weapon"
			else "Press F to summon your light-weapon"
		bar.BackgroundTransparency = if summoned then 0.12 else 0.4

		for slotName, slot in slots do
			local remaining = controller.ReadyAt[slotName] - t
			local duration = controller.Duration[slotName]
			local ready = remaining <= 0
			if ready then
				slot.Overlay.Size = UDim2.fromScale(1, 0)
				slot.Timer.Text = ""
				if not slot.WasReady then
					-- Ready flash
					slot.Scale.Scale = 1.12
					Theme.tween(slot.Scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
					slot.Stroke.Thickness = 5
					Theme.tween(slot.Stroke, 0.5, { Thickness = 2 })
				end
			else
				slot.Overlay.Size = UDim2.fromScale(1, math.clamp(remaining / math.max(duration, 0.05), 0, 1))
				slot.Timer.Text = if remaining >= 1 and slotName ~= "Basic" then tostring(math.ceil(remaining)) else ""
			end
			slot.WasReady = ready
			slot.Icon.TextTransparency = if summoned then 0 else 0.5
		end
	end)

	player:GetAttributeChangedSignal(GemConfig.Attributes.WeaponId):Connect(refreshWeapon)
	controller.Changed:Connect(function(slotName)
		if slotName == nil then
			refreshWeapon()
		end
	end)
	UserInputService.LastInputTypeChanged:Connect(refreshKeys)
	refreshWeapon()
	refreshKeys()
end

return SkillBar
