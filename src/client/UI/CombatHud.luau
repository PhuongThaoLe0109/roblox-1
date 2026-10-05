-- CombatHud
-- Everything you need mid-fight:
--   * Health bar in your gem's gradient (with Aegis shield and guard meter).
--   * Skill bar: M1 weapon, Z X C V skills, G transformation, T domain and
--     F block. Each slot shows its key, icon, name and cooldown; slots your
--     gem doesn't unlock yet show what rarity they need. Slots are buttons
--     too (touch screens: hold ATTACK / BLOCK).
--   * Combo counter, kill feed, streak shout-outs, safe-zone badge, beast and
--     domain timers, and the "SHATTERED" screen while you reform.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))
local GemCatalog = require(ReplicatedStorage:WaitForChild("GemCatalog"))
local GemKits = require(ReplicatedStorage:WaitForChild("GemKits"))
local CombatController = require(script.Parent.Parent:WaitForChild("Combat"):WaitForChild("CombatController"))
local GemArt = require(script.Parent:WaitForChild("GemArt"))
local Theme = require(script.Parent:WaitForChild("Theme"))

local C = Theme.Colors
local STATUS = CombatConfig.Status
local PA = CombatConfig.PlayerAttributes
local player = Players.LocalPlayer

local CombatHud = {}

local SLOT = 62
local LOCKED_HINT = {
	Z = "Any gem",
	X = "1 in 1,000+",
	C = "1 in 100,000+",
	V = "1 in 10M+",
	G = "1 in 750M+",
	T = "1 in 400B+",
}

local function now(): number
	return Workspace:GetServerTimeNow()
end

type Slot = {
	Key: string,
	Button: TextButton,
	Icon: TextLabel,
	Name: TextLabel,
	Shade: Frame,
	Timer: TextLabel,
	Stroke: UIStroke,
	Locked: boolean,
	Ready: boolean,
	Scale: UIScale,
}

function CombatHud.Init(screen: ScreenGui, context)
	local root = Theme.new("Frame", {
		Name = "CombatHud",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = screen,
	})

	----------------------------------------------------------------------------
	-- Skill bar
	----------------------------------------------------------------------------
	local bar = Theme.new("Frame", {
		Name = "SkillBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -40),
		Size = UDim2.fromOffset(8 * (SLOT + 8), SLOT),
		BackgroundTransparency = 1,
		Parent = root,
	}, { Theme.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center) })

	local slots: { [string]: Slot } = {}
	local function makeSlot(key: string, order: number, accent: Color3?): Slot
		local button = Theme.new("TextButton", {
			Name = key,
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = C.Panel,
			BackgroundTransparency = 0.1,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(SLOT, SLOT),
			LayoutOrder = order,
			ClipsDescendants = false,
			Parent = bar,
		})
		Theme.corner(12).Parent = button
		Theme.new("UIGradient", { Color = ColorSequence.new(C.PanelLight, C.Panel), Rotation = 90, Parent = button })
		local stroke = Theme.stroke(accent or Color3.new(1, 1, 1), 2, 0.25)
		stroke.Parent = button
		Theme.shimmer(stroke, nil, 0.25)
		local icon = Theme.label({
			Text = "",
			FontFace = Theme.Faces.Display,
			TextSize = 28,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 1, -8),
			ZIndex = 2,
			Parent = button,
		})
		Theme.shimmer(icon, nil, 0.3, 90)
		local keyBadge = Theme.label({
			Text = key,
			FontFace = Theme.Faces.Odds,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Center,
			BackgroundColor3 = Color3.fromRGB(20, 12, 36),
			BackgroundTransparency = 0.1,
			Position = UDim2.fromOffset(-6, -6),
			Size = UDim2.fromOffset(22, 18),
			ZIndex = 4,
			Parent = button,
		})
		Theme.corner(5).Parent = keyBadge
		local name = Theme.label({
			Text = "",
			FontFace = Theme.Faces.Bold,
			TextSize = 10,
			TextColor3 = C.SubText,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextStrokeTransparency = 0.5,
			TextTruncate = Enum.TextTruncate.AtEnd,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 1, 2),
			Size = UDim2.new(1, 14, 0, 14),
			Parent = button,
		})
		local shade = Theme.new("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 0),
			BackgroundColor3 = Color3.fromRGB(8, 4, 16),
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = button,
		})
		Theme.corner(12).Parent = shade
		local timer = Theme.label({
			Text = "",
			FontFace = Theme.Faces.Odds,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextStrokeTransparency = 0.3,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 4,
			Parent = button,
		})
		local scale = Theme.new("UIScale", { Parent = button })
		local slot: Slot = {
			Key = key,
			Button = button,
			Icon = icon,
			Name = name,
			Shade = shade,
			Timer = timer,
			Stroke = stroke,
			Locked = false,
			Ready = true,
			Scale = scale,
		}
		slots[key] = slot
		return slot
	end

	makeSlot("M1", 1)
	for i, key in GemKits.SkillKeys do
		makeSlot(key, i + 1)
	end
	makeSlot(GemKits.UltimateKey, 6, C.Gold)
	makeSlot(GemKits.DomainKey, 7, C.Lavender)
	makeSlot("F", 8, C.Cyan)

	local function lock(slot: Slot, locked: boolean, icon: string, name: string)
		slot.Locked = locked
		slot.Icon.Text = if locked then "🔒" else icon
		slot.Icon.TextTransparency = if locked then 0.5 else 0
		slot.Name.Text = if locked then (LOCKED_HINT[slot.Key] or "") else name
		slot.Button.BackgroundTransparency = if locked then 0.5 else 0.1
	end

	local function refreshKit()
		local kit = CombatController.GetKit()
		local style = CombatController.MeleeStyle()
		lock(slots.M1, false, style.Icon, style.Name)
		for _, key in GemKits.SkillKeys do
			local skill = GemKits.SkillFor(kit, key)
			lock(slots[key], skill == nil, if skill then skill.Icon else "", if skill then skill.Name else "")
		end
		local ultimate = kit.Ultimate
		lock(slots.G, ultimate == nil, "✦", if ultimate then ultimate.BeastName else "")
		local domain = kit.Domain
		lock(slots.T, domain == nil, "⌬", if domain then "Domain" else "")
		lock(slots.F, false, "⛉", "Block")
	end
	CombatController.KitChanged:Connect(refreshKit)
	refreshKit()

	-- Presses (mouse / touch)
	slots.M1.Button.MouseButton1Down:Connect(function()
		CombatController.SetAttackHeld(true)
	end)
	slots.M1.Button.MouseButton1Up:Connect(function()
		CombatController.SetAttackHeld(false)
	end)
	slots.M1.Button.MouseLeave:Connect(function()
		CombatController.SetAttackHeld(false)
	end)
	slots.F.Button.MouseButton1Down:Connect(function()
		CombatController.SetBlock(true)
	end)
	slots.F.Button.MouseButton1Up:Connect(function()
		CombatController.SetBlock(false)
	end)
	slots.F.Button.MouseLeave:Connect(function()
		CombatController.SetBlock(false)
	end)
	for _, key in GemKits.AllKeys do
		slots[key].Button.Activated:Connect(function()
			CombatController.UseSkill(key)
		end)
	end

	----------------------------------------------------------------------------
	-- Health, shield, guard
	----------------------------------------------------------------------------
	local health = Theme.new("Frame", {
		Name = "Health",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -40 - SLOT - 30),
		Size = UDim2.fromOffset(440, 22),
		BackgroundColor3 = Color3.fromRGB(20, 12, 34),
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = root,
	})
	Theme.round().Parent = health
	local healthStroke = Theme.stroke(Color3.new(1, 1, 1), 2, 0.2)
	healthStroke.Parent = health
	Theme.shimmer(healthStroke, nil, 0.2)
	local fill = Theme.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = health })
	Theme.round().Parent = fill
	local fillGradient = Theme.shimmer(fill, nil, 0.3, 0)
	local shieldFill = Theme.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Cyan, BackgroundTransparency = 0.2, BorderSizePixel = 0, Parent = health })
	Theme.round().Parent = shieldFill
	local healthText = Theme.label({
		Text = "",
		FontFace = Theme.Faces.Odds,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.3,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Parent = health,
	})
	local guard = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, -40 - SLOT - 4),
		Size = UDim2.fromOffset(300, 5),
		BackgroundColor3 = Color3.fromRGB(20, 12, 34),
		BorderSizePixel = 0,
		Visible = false,
		Parent = root,
	})
	Theme.round().Parent = guard
	local guardFill = Theme.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Cyan, BorderSizePixel = 0, Parent = guard })
	Theme.round().Parent = guardFill
	local guardLabel = Theme.label({
		Text = "GUARD",
		FontFace = Theme.Faces.Odds,
		TextSize = 9,
		TextColor3 = C.Cyan,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0, -6, 0.5, 0),
		Size = UDim2.fromOffset(50, 10),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = guard,
	})
	local _ = guardLabel

	-- Gem title over the health bar.
	local gemTitle = Theme.headline({
		Text = "",
		TextSize = 18,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -40 - SLOT - 54),
		Size = UDim2.fromOffset(440, 22),
		Parent = root,
	}, nil, 0.3)
	local gemTitleGradient = gemTitle:FindFirstChildOfClass("UIGradient") :: UIGradient
	local function refreshGem()
		local gem = GemCatalog.Get(player:GetAttribute("EquippedGem"))
		if gem then
			gemTitle.Text = `{gem.Name}  ·  {GemCatalog.FormatOdds(gem.Odds)}`
			gemTitleGradient.Color = if GemArt.Tier(gem) >= 4 then GemArt.Rainbow else GemArt.Gradient(gem)
			fillGradient.Color = GemArt.Gradient(gem)
		end
	end
	player:GetAttributeChangedSignal("EquippedGem"):Connect(refreshGem)
	refreshGem()

	----------------------------------------------------------------------------
	-- Skills guide button
	----------------------------------------------------------------------------
	local guideButton = Theme.button("📖 SKILLS  H", C.Lavender, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0.5, 230, 1, -40 - SLOT - 30),
		Size = UDim2.fromOffset(128, 26),
		TextSize = 13,
		Parent = root,
	})
	guideButton.Activated:Connect(function()
		if context.ToggleSkillGuide then
			context.ToggleSkillGuide()
		end
	end)

	----------------------------------------------------------------------------
	-- Combo counter (right)
	----------------------------------------------------------------------------
	local comboHolder = Theme.new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -40, 0.45, 0),
		Size = UDim2.fromOffset(200, 110),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = root,
	})
	local comboNumber = Theme.headline({
		Text = "",
		TextSize = 64,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(1, 0, 0, 70),
		Parent = comboHolder,
	}, nil, 0.6)
	Theme.label({
		Text = "HIT COMBO",
		FontFace = Theme.Faces.Odds,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextStrokeTransparency = 0.4,
		Position = UDim2.fromOffset(0, 72),
		Size = UDim2.new(1, 0, 0, 18),
		Parent = comboHolder,
	})
	local comboScale = Theme.new("UIScale", { Parent = comboHolder })
	local lastCombo = 0
	local function watchCombo(character: Model)
		character:GetAttributeChangedSignal(STATUS.Combo):Connect(function()
			local n = character:GetAttribute(STATUS.Combo) or 0
			if n >= 2 then
				comboHolder.Visible = true
				comboNumber.Text = tostring(n)
				if n > lastCombo then
					comboScale.Scale = 1.35
					Theme.tween(comboScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
				end
			else
				comboHolder.Visible = false
			end
			lastCombo = n
		end)
	end

	----------------------------------------------------------------------------
	-- Status line (safe zone, beast, domain)
	----------------------------------------------------------------------------
	local badge = Theme.label({
		Text = "",
		FontFace = Theme.Faces.Heavy,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.3,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -40 - SLOT - 80),
		Size = UDim2.fromOffset(500, 24),
		Parent = root,
	})

	----------------------------------------------------------------------------
	-- Kill feed (top right) and streak shout-outs
	----------------------------------------------------------------------------
	local feed = Theme.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 70),
		Size = UDim2.fromOffset(380, 220),
		BackgroundTransparency = 1,
		Parent = root,
	}, { Theme.list(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Right) })
	local feedOrder = 0
	local function gemColor(id: string?): Color3
		local gem = GemCatalog.Get(id)
		return if gem then gem.Color else C.Text
	end
	local killFeed = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("KillFeed") :: RemoteEvent
	killFeed.OnClientEvent:Connect(function(info)
		if type(info) ~= "table" then
			return
		end
		feedOrder += 1
		local row = Theme.panel({ Size = UDim2.fromOffset(370, 34), LayoutOrder = -feedOrder, Parent = feed })
		local text
		if info.Killer then
			text = `<font color="#{gemColor(info.KillerGem):ToHex()}">{info.KillerDisplay or info.Killer}</font>  ✦ shattered ✦  <font color="#{gemColor(info.VictimGem):ToHex()}">{info.VictimDisplay or info.Victim}</font>`
		else
			text = `<font color="#{gemColor(info.VictimGem):ToHex()}">{info.VictimDisplay or info.Victim}</font>  shattered`
		end
		Theme.label({
			Text = text,
			RichText = true,
			FontFace = Theme.Faces.Bold,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1),
			Parent = row,
		})
		task.delay(6, function()
			Theme.tween(row, 0.3, { BackgroundTransparency = 1 })
			task.wait(0.3)
			row:Destroy()
		end)
		if info.Milestone and info.Killer then
			context.Toast(`{info.KillerDisplay or info.Killer} is on a {info.Streak} kill streak!`, "Success")
		end
		if (info.Ended or 0) >= 3 and info.Killer then
			context.Toast(`{info.KillerDisplay or info.Killer} ended {info.VictimDisplay or info.Victim}'s {info.Ended} streak!`, "Info")
		end
	end)

	----------------------------------------------------------------------------
	-- Shattered screen
	----------------------------------------------------------------------------
	local death = Theme.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(12, 6, 24),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 30,
		Parent = root,
	})
	local deathTitle = Theme.headline({
		Text = "SHATTERED",
		TextSize = 84,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromOffset(900, 100),
		ZIndex = 31,
		Parent = death,
	}, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.5, C.Pink),
		ColorSequenceKeypoint.new(1, C.Lavender),
	}), 0.5)
	local deathSub = Theme.label({
		Text = "",
		FontFace = Theme.Faces.Bold,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.4,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.44),
		Size = UDim2.fromOffset(900, 26),
		ZIndex = 31,
		Parent = death,
	})
	local deathTimer = Theme.label({
		Text = "",
		FontFace = Theme.Faces.Odds,
		TextSize = 16,
		TextColor3 = C.SubText,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(600, 22),
		ZIndex = 31,
		Parent = death,
	})
	local deathScale = Theme.new("UIScale", { Parent = deathTitle })
	local lastKiller: string? = nil
	killFeed.OnClientEvent:Connect(function(info)
		if type(info) == "table" and info.Victim == player.Name then
			lastKiller = info.KillerDisplay or info.Killer
		end
	end)
	local reformAt = 0
	local function showDeath()
		death.Visible = true
		death.BackgroundTransparency = 1
		Theme.tween(death, 0.6, { BackgroundTransparency = 0.45 })
		deathScale.Scale = 1.5
		Theme.tween(deathScale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
		reformAt = os.clock() + CombatConfig.RespawnTime
		task.delay(0.1, function()
			deathSub.Text = if lastKiller then `Your gem was cracked by {lastKiller}` else "Your gem was cracked"
		end)
	end

	----------------------------------------------------------------------------
	-- Character hookup + per-frame refresh
	----------------------------------------------------------------------------
	local function onCharacter(character: Model)
		death.Visible = false
		lastKiller = nil
		lastCombo = 0
		comboHolder.Visible = false
		watchCombo(character)
		character:GetAttributeChangedSignal(STATUS.Shattered):Connect(function()
			if character:GetAttribute(STATUS.Shattered) == true then
				showDeath()
			end
		end)
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end

	CombatController.Notice:Connect(function(text, kind)
		context.Toast(text, kind)
	end)

	RunService.RenderStepped:Connect(function()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local t = now()

		-- Cooldowns
		for key, slot in slots do
			if slot.Locked then
				slot.Shade.Size = UDim2.fromScale(1, 0)
				slot.Timer.Text = ""
				continue
			end
			local left = CombatController.ReadyIn(key)
			local entry = CombatController.Cooldowns[key]
			local fraction = if entry and left > 0 then math.clamp(left / math.max(0.1, entry.Duration), 0, 1) else 0
			slot.Shade.Size = UDim2.fromScale(1, fraction)
			slot.Timer.Text = if left > 0.05 and key ~= "M1" then (if left >= 10 then string.format("%d", left) else string.format("%.1f", left)) else ""
			local ready = left <= 0.05
			if ready and not slot.Ready and key ~= "M1" then
				slot.Scale.Scale = 1.18
				Theme.tween(slot.Scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
			end
			slot.Ready = ready
		end
		if character then
			slots.F.Stroke.Transparency = if character:GetAttribute(STATUS.Blocking) == true then 0 else 0.25
		end

		-- Health
		if humanoid then
			local hp = math.clamp(humanoid.Health / math.max(1, humanoid.MaxHealth), 0, 1)
			fill.Size = UDim2.fromScale(hp, 1)
			fill.BackgroundColor3 = if hp < 0.3 then C.Danger else Color3.new(1, 1, 1)
			healthText.Text = `{math.ceil(humanoid.Health)} / {math.floor(humanoid.MaxHealth)}`
			local shield = if character and (character:GetAttribute(STATUS.ShieldUntil) or 0) > t then character:GetAttribute(STATUS.ShieldHP) or 0 else 0
			shieldFill.Size = UDim2.fromScale(math.clamp(shield / humanoid.MaxHealth, 0, 1), 1)
		end
		if character then
			local g = character:GetAttribute(STATUS.Guard) or CombatConfig.Block.MaxGuard
			guard.Visible = g < CombatConfig.Block.MaxGuard - 0.5 or character:GetAttribute(STATUS.Blocking) == true
			guardFill.Size = UDim2.fromScale(g / CombatConfig.Block.MaxGuard, 1)
			guardFill.BackgroundColor3 = if g < CombatConfig.Block.MaxGuard * 0.25 then C.Danger else C.Cyan
		end

		-- Status line
		local text, color = "", C.Text
		if player:GetAttribute(PA.InSafeZone) == true then
			text, color = "✦ SAFE ZONE ✦  no fighting on the plaza", C.Success
		elseif character and character:GetAttribute(STATUS.Beast) then
			local left = (character:GetAttribute(STATUS.BeastUntil) or 0) - t
			local kit = CombatController.GetKit()
			text, color = `{string.upper(kit.Ultimate and kit.Ultimate.BeastName or "Beast")} FORM  {math.max(0, math.ceil(left))}s`, C.Gold
		elseif character and (character:GetAttribute(STATUS.DomainUntil) or 0) > t then
			text, color = `DOMAIN OPEN  {math.ceil((character:GetAttribute(STATUS.DomainUntil) or 0) - t)}s  ·  cooldowns faster`, C.Lavender
		elseif character and (character:GetAttribute(STATUS.CursedUntil) or 0) > t then
			text, color = "HEXED: you take extra damage", C.Danger
		end
		badge.Text = text
		badge.TextColor3 = color

		-- Reform countdown
		if death.Visible then
			local left = reformAt - os.clock()
			deathTimer.Text = if left > 0 then string.format("Reforming in %.1f…", left) else "Reforming…"
		end
	end)
end

return CombatHud
