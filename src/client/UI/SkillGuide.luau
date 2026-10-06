-- SkillGuide
-- The "how do I fight with this gem?" panel (SKILLS button or H). Shows the
-- equipped gem's whole kit: its melee weapon, every skill with its key,
-- description and cooldown, its transformation and domain (or which rarity
-- unlocks them), and the general controls. Updates when you change gem.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GemCatalog = require(ReplicatedStorage:WaitForChild("GemCatalog"))
local GemKits = require(ReplicatedStorage:WaitForChild("GemKits"))
local CombatController = require(script.Parent.Parent:WaitForChild("Combat"):WaitForChild("CombatController"))
local GemArt = require(script.Parent:WaitForChild("GemArt"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Cutscene = require(script.Parent.Parent:WaitForChild("Combat"):WaitForChild("Cutscene"))

local C = Theme.Colors
local player = Players.LocalPlayer

local SkillGuide = {}

local CONTROLS = {
	{ "M1 / tap ATTACK", "Melee combo (hold to keep swinging)" },
	{ "F (hold)", "Block hits from the front; too much breaks your guard" },
	{ "Q", "Dash, with a moment of invulnerability" },
	{ "Space ×2", "Double jump" },
	{ "B", "Flying broom: W follow the camera, Space / Ctrl up / down (not in combat)" },
	{ "R", "Roll for gems" },
	{ "I", "Inventory: try on and equip gems (not mid-fight)" },
}

local ELEMENT_TEXT = {
	Inferno = "Inferno",
	Frost = "Frost",
	Void = "Void",
	Electric = "Storm",
	Wisp = "Dream",
	Torrent = "Radiant",
	Blaze = "Prism",
	Spike = "Shard",
}

function SkillGuide.Init(screen: ScreenGui, context)
	local panel = Theme.panel({
		Name = "SkillGuide",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(820, 560),
		Visible = false,
		ZIndex = 50,
		Parent = screen,
	})
	local scale = Theme.new("UIScale", { Parent = panel })

	local icon = Theme.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(20, 14),
		Size = UDim2.fromOffset(64, 64),
		ZIndex = 51,
		Parent = panel,
	})
	local title = Theme.headline({
		Text = "",
		TextSize = 34,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(96, 14),
		Size = UDim2.new(1, -170, 0, 40),
		ZIndex = 51,
		Parent = panel,
	}, nil, 0.3)
	local titleGradient = title:FindFirstChildOfClass("UIGradient") :: UIGradient
	local subtitle = Theme.label({
		Text = "",
		FontFace = Theme.Faces.Odds,
		TextSize = 13,
		TextColor3 = C.SubText,
		Position = UDim2.fromOffset(98, 56),
		Size = UDim2.new(1, -170, 0, 20),
		ZIndex = 51,
		Parent = panel,
	})
	local close = Theme.button("✕", C.Pink, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.fromOffset(40, 40),
		TextSize = 20,
		ZIndex = 52,
		Parent = panel,
	})

	local list = Theme.new("ScrollingFrame", {
		Position = UDim2.fromOffset(16, 90),
		Size = UDim2.new(1, -32, 1, -106),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = C.Lavender,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ZIndex = 51,
		Parent = panel,
	}, { Theme.list(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center) })

	local order = 0
	local function section(text: string)
		order += 1
		Theme.label({
			Text = text,
			FontFace = Theme.Faces.Title,
			TextSize = 18,
			TextColor3 = C.Pink,
			Size = UDim2.new(1, -12, 0, 26),
			LayoutOrder = order,
			ZIndex = 52,
			Parent = list,
		})
	end

	local function row(key: string, iconText: string, name: string, description: string, extra: string, locked: boolean?, accent: Color3?)
		order += 1
		local card = Theme.new("Frame", {
			BackgroundColor3 = C.PanelLight,
			BackgroundTransparency = if locked then 0.6 else 0.25,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -12, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order,
			ZIndex = 52,
			Parent = list,
		})
		Theme.corner(10).Parent = card
		Theme.stroke(accent or Color3.new(1, 1, 1), 1.5, if locked then 0.7 else 0.4).Parent = card
		Theme.padding(10).Parent = card
		local badge = Theme.label({
			Text = key,
			FontFace = Theme.Faces.Odds,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Center,
			BackgroundColor3 = Color3.fromRGB(20, 12, 36),
			BackgroundTransparency = 0,
			Size = UDim2.fromOffset(46, 46),
			ZIndex = 53,
			Parent = card,
		})
		Theme.corner(10).Parent = badge
		Theme.label({
			Text = if locked then "🔒" else iconText,
			FontFace = Theme.Faces.Display,
			TextSize = 26,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(52, 0),
			Size = UDim2.fromOffset(40, 46),
			ZIndex = 53,
			Parent = card,
		})
		Theme.label({
			Text = name,
			FontFace = Theme.Faces.Heavy,
			TextSize = 18,
			TextColor3 = if locked then C.Muted else C.Text,
			Position = UDim2.fromOffset(100, 0),
			Size = UDim2.new(1, -230, 0, 22),
			ZIndex = 53,
			Parent = card,
		})
		Theme.label({
			Text = extra,
			FontFace = Theme.Faces.Odds,
			TextSize = 12,
			TextColor3 = C.Gold,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 2),
			Size = UDim2.fromOffset(130, 18),
			ZIndex = 53,
			Parent = card,
		})
		Theme.label({
			Text = description,
			FontFace = Theme.Faces.Body,
			TextSize = 14,
			TextColor3 = if locked then C.Muted else C.SubText,
			TextWrapped = true,
			AutomaticSize = Enum.AutomaticSize.Y,
			Position = UDim2.fromOffset(100, 24),
			Size = UDim2.new(1, -100, 0, 18),
			ZIndex = 53,
			Parent = card,
		})
	end

	-- A settings card with an ON / OFF switch on the right.
	local function toggle(name: string, description: string, get: () -> boolean, set: (boolean) -> ())
		order += 1
		local card = Theme.new("Frame", {
			BackgroundColor3 = C.PanelLight,
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -12, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order,
			ZIndex = 52,
			Parent = list,
		})
		Theme.corner(10).Parent = card
		Theme.stroke(Color3.new(1, 1, 1), 1.5, 0.4).Parent = card
		Theme.padding(10).Parent = card
		Theme.label({
			Text = name,
			FontFace = Theme.Faces.Heavy,
			TextSize = 18,
			TextColor3 = C.Text,
			Size = UDim2.new(1, -120, 0, 22),
			ZIndex = 53,
			Parent = card,
		})
		Theme.label({
			Text = description,
			FontFace = Theme.Faces.Body,
			TextSize = 14,
			TextColor3 = C.SubText,
			TextWrapped = true,
			AutomaticSize = Enum.AutomaticSize.Y,
			Position = UDim2.fromOffset(0, 24),
			Size = UDim2.new(1, -120, 0, 18),
			ZIndex = 53,
			Parent = card,
		})
		local switch = Theme.button("", C.Success, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 4),
			Size = UDim2.fromOffset(96, 38),
			TextSize = 16,
			ZIndex = 54,
			Parent = card,
		})
		local function paint()
			local on = get()
			switch.Text = if on then "ON" else "OFF"
			switch.BackgroundColor3 = if on then C.Success else C.Muted
		end
		paint()
		switch.Activated:Connect(function()
			set(not get())
			paint()
		end)
	end

	local function rebuild()
		for _, child in list:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		order = 0
		local gem = GemCatalog.Get(player:GetAttribute("EquippedGem")) or GemCatalog.List[1]
		local kit = CombatController.GetKit()
		for _, child in icon:GetChildren() do
			child:Destroy()
		end
		GemArt.Icon(gem, 64).Parent = icon
		title.Text = gem.Name
		titleGradient.Color = if GemArt.Tier(gem) >= 4 then GemArt.Rainbow else GemArt.Gradient(gem)
		subtitle.Text = `{GemCatalog.FormatOdds(gem.Odds)}  ·  {ELEMENT_TEXT[kit.Element] or kit.Element} element  ·  power ×{string.format("%.2f", kit.Power)}`

		section("Weapon")
		local melee = kit.Melee
		local damage = {}
		for i = 1, melee.Hits do
			damage[i] = tostring(GemKits.MeleeDamage(kit, melee, i))
		end
		row("M1", melee.Icon, melee.Name, `{melee.Description} Damage per hit: {table.concat(damage, " / ")}.`, `{melee.Hits}-hit combo`)

		section("Skills")
		for _, key in GemKits.SkillKeys do
			local skill = GemKits.SkillFor(kit, key)
			if skill then
				row(key, skill.Icon, skill.Name, skill.Description, `{skill.Cooldown}s cooldown`)
			else
				local need = if key == "X" then "1 in 1,000" elseif key == "C" then "1 in 100,000" else "1 in 10,000,000"
				row(key, "", "Locked", `Gems of {need} or rarer have a skill here.`, "", true)
			end
		end

		section("Transformation & Domain")
		if kit.Ultimate then
			row("G", kit.Ultimate.Icon, kit.Ultimate.Name, kit.Ultimate.Description, `{kit.Ultimate.Cooldown}s cooldown`, false, C.Gold)
		else
			row("G", "", "Transformation (locked)", "Gems of 1 in 750,000,000 or rarer transform into a giant crystal beast: Prism Golem, Pyre Wyrm, Glacier Stag, Umbral Maw, Thunder Roc, Dream Moth, Solar Lion or Star Koi.", "", true)
		end
		if kit.Domain then
			row("T", kit.Domain.Icon, kit.Domain.Name, kit.Domain.Description, `{kit.Domain.Cooldown}s cooldown`, false, C.Lavender)
		else
			row("T", "", "Domain (locked)", "Gems of 1 in 400,000,000,000 or rarer can tear open a dimension that traps everyone inside.", "", true)
		end

		section("Controls")
		for _, control in CONTROLS do
			row("", "", control[1], control[2], "")
		end

		section("Settings")
		toggle("Ultimate cutscenes", "A short cinematic when you transform (G) or open your domain (T). You can't be hit while it plays.", function()
			return Cutscene.Enabled
		end, Cutscene.SetEnabled)
	end
	CombatController.KitChanged:Connect(function()
		if panel.Visible then
			rebuild()
		end
	end)

	local open = false
	local function setOpen(value: boolean?)
		if value == nil then
			value = not open
		end
		open = value :: boolean
		if open then
			rebuild()
			panel.Visible = true
			scale.Scale = 0.85
			Theme.tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		else
			Theme.tween(scale, 0.12, { Scale = 0.9 })
			task.delay(0.12, function()
				if not open then
					panel.Visible = false
				end
			end)
		end
	end
	context.ToggleSkillGuide = setOpen
	close.Activated:Connect(function()
		setOpen(false)
	end)
	ContextActionService:BindAction("GemSkillGuide", function(_, state)
		if state == Enum.UserInputState.Begin then
			setOpen()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.H, Enum.KeyCode.ButtonSelect)
end

return SkillGuide
