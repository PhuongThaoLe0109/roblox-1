-- LobbyHud
-- The rolling side of the screen: title lettering, roll count + equipped
-- aura, the ROLL button with its cooldown bar, Auto / Fast toggles and the
-- Inventory button (bottom left). There is no PLAY button: the whole world is
-- the battlefield, so you fight with your gem as soon as you spawn.
--   R / ButtonX   roll
--   I / ButtonY   inventory (handled by Inventory)
-- Auto roll keeps rolling and stops by itself after a rare result so the
-- player doesn't miss it.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GemCatalog = require(ReplicatedStorage:WaitForChild("GemCatalog"))
local ClientData = require(script.Parent.Parent:WaitForChild("ClientData"))
local GemArt = require(script.Parent:WaitForChild("GemArt"))
local RollReveal = require(script.Parent:WaitForChild("RollReveal"))
local Theme = require(script.Parent:WaitForChild("Theme"))

local C = Theme.Colors

local LobbyHud = {}

local ROLL_COOLDOWN = 1.5 -- mirrors the server; the server is authoritative
local AUTO_STOP_TIER = 3 -- auto roll pauses on "1 in 100,000" or rarer

function LobbyHud.Init(screen: ScreenGui, context)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local rollRemote = remotes:WaitForChild("RequestRoll") :: RemoteFunction

	local root = Theme.new("Frame", {
		Name = "LobbyHud",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = screen,
	})

	----------------------------------------------------------------------------
	-- Title + stats (top left)
	----------------------------------------------------------------------------
	Theme.headline({
		Text = Theme.GameTitle,
		TextSize = 44,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(28, 18),
		Size = UDim2.fromOffset(520, 54),
		Parent = root,
	}, nil, 0.2)
	local stats = Theme.label({
		Text = "",
		FontFace = Theme.Faces.Bold,
		TextSize = 17,
		TextColor3 = C.SubText,
		TextStrokeTransparency = 0.6,
		Position = UDim2.fromOffset(30, 72),
		Size = UDim2.fromOffset(520, 22),
		Parent = root,
	})
	local auraLine = Theme.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(28, 98),
		Size = UDim2.fromOffset(520, 40),
		Parent = root,
	})
	local auraIconHolder = Theme.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(40, 40), Parent = auraLine })
	local auraName = Theme.headline({
		Text = "",
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(46, 2),
		Size = UDim2.fromOffset(460, 36),
		Parent = auraLine,
	})
	local auraGradient = auraName:FindFirstChildOfClass("UIGradient") :: UIGradient

	local function refreshStats()
		stats.Text = `Rolls  {Theme.formatNumber(ClientData.Rolls)}   ·   Collection  {ClientData.UniqueOwned()}/{#GemCatalog.List}`
		for _, child in auraIconHolder:GetChildren() do
			child:Destroy()
		end
		local gem = GemCatalog.Get(ClientData.Equipped)
		if gem then
			GemArt.Icon(gem, 40).Parent = auraIconHolder
			auraName.Text = gem.Name
			auraGradient.Color = if GemArt.Tier(gem) >= 4 then GemArt.Rainbow else GemArt.Gradient(gem)
		else
			auraName.Text = "No aura yet — roll!"
			auraGradient.Color = Theme.Prism
		end
	end
	ClientData.Changed:Connect(refreshStats)
	refreshStats()

	----------------------------------------------------------------------------
	-- Roll cluster (bottom left, above Inventory)
	----------------------------------------------------------------------------
	local cluster = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 28, 1, -100),
		Size = UDim2.fromOffset(340, 92),
		BackgroundTransparency = 1,
		Parent = root,
	})

	local rollButton = Theme.button("ROLL", C.Pink, {
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(210, 72),
		FontFace = Theme.Faces.Display,
		TextSize = 38,
		Parent = cluster,
	})
	local rollStroke = Theme.new("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Color = Color3.fromRGB(90, 30, 90),
		Thickness = 2.5,
		Transparency = 0.2,
		Parent = rollButton,
	})
	local _ = rollStroke
	local _, setCooldown = Theme.progressBar({
		Position = UDim2.fromOffset(0, 80),
		Size = UDim2.fromOffset(210, 8),
		Parent = cluster,
	})
	setCooldown(1, C.Pink)

	local function toggle(text: string, y: number): (TextButton, (boolean) -> ())
		local button = Theme.button(text, C.Lavender, {
			Position = UDim2.fromOffset(222, y),
			Size = UDim2.fromOffset(112, 34),
			TextSize = 15,
			Parent = cluster,
		})
		local function set(on: boolean)
			button.Text = `{text}  {if on then "ON" else "OFF"}`
			button.BackgroundColor3 = if on then C.Success else C.Lavender
		end
		set(false)
		return button, set
	end
	local autoButton, setAuto = toggle("Auto", 0)
	local fastButton, setFast = toggle("Fast", 40)

	----------------------------------------------------------------------------
	-- Menu (bottom left)
	----------------------------------------------------------------------------
	local inventoryButton = Theme.button("✦ Inventory", C.Cyan, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 28, 1, -28),
		Size = UDim2.fromOffset(200, 60),
		TextSize = 22,
		Parent = root,
	})
	----------------------------------------------------------------------------
	-- Behaviour
	----------------------------------------------------------------------------
	local autoOn, fastOn = false, false
	local rolling = false
	local readyAt = 0

	local function startCooldown(seconds: number)
		readyAt = os.clock() + seconds
		setCooldown(0)
		task.spawn(function()
			while os.clock() < readyAt do
				setCooldown(1 - (readyAt - os.clock()) / ROLL_COOLDOWN)
				task.wait(0.05)
			end
			setCooldown(1)
		end)
	end

	local function rollOnce(): boolean
		if rolling or RollReveal.IsBusy() then
			return false
		end
		if os.clock() < readyAt then
			return false
		end
		rolling = true
		startCooldown(ROLL_COOLDOWN)
		local ok, gemIdOrReason, countOrWait = rollRemote:InvokeServer()
		if ok then
			local gem = GemCatalog.Get(gemIdOrReason)
			RollReveal.Play(gemIdOrReason, countOrWait, fastOn)
			rolling = false
			if autoOn and gem and GemArt.Tier(gem) >= AUTO_STOP_TIER then
				autoOn = false
				setAuto(false)
				context.Toast(`Auto roll paused: you found {gem.Name}!`)
			end
			return true
		end
		rolling = false
		if gemIdOrReason == "Cooldown" and type(countOrWait) == "number" then
			startCooldown(countOrWait)
		elseif gemIdOrReason == "NotLoaded" then
			context.Toast("Still loading your data…", "Warning")
		end
		return false
	end

	rollButton.Activated:Connect(rollOnce)
	autoButton.Activated:Connect(function()
		autoOn = not autoOn
		setAuto(autoOn)
		if autoOn then
			task.spawn(function()
				while autoOn and root.Parent do
					if not rollOnce() then
						task.wait(0.1)
					end
					task.wait()
				end
			end)
		end
	end)
	fastButton.Activated:Connect(function()
		fastOn = not fastOn
		setFast(fastOn)
	end)
	inventoryButton.Activated:Connect(function()
		context.ToggleInventory()
	end)
	ContextActionService:BindAction("GemRoll", function(_, state)
		if state == Enum.UserInputState.Begin and root.Visible then
			task.spawn(rollOnce)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.R, Enum.KeyCode.ButtonX)

	context.SetLobbyVisible = function(visible: boolean)
		root.Visible = visible
		if not visible then
			autoOn = false
			setAuto(false)
		end
	end
end

return LobbyHud
