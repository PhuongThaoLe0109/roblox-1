-- Toasts
-- Handles GemRemotes.Notify:
--   "Travel"  -> prism flash across the screen (zone banner shows the name)
--   "RankUp"  -> big shimmering celebration banner
--   others    -> stacked toast cards at the bottom centre

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent:WaitForChild("Theme"))

local C = Theme.Colors

local Toasts = {}

local KIND_STYLE = {
	Info = { Icon = "✦", Color = C.Lavender },
	Success = { Icon = "✓", Color = C.Success },
	Warning = { Icon = "!", Color = C.Warning },
	Capture = { Icon = "⚑", Color = C.Pink },
	RankUp = { Icon = "★", Color = C.Gold },
}

local MAX_TOASTS = 4
local TOAST_LIFETIME = 4.5

function Toasts.Init(screen: ScreenGui, context)
	local notify = ReplicatedStorage:WaitForChild("GemRemotes"):WaitForChild("Notify") :: RemoteEvent

	----------------------------------------------------------------------------
	-- Toast stack
	----------------------------------------------------------------------------
	local stack = Theme.new("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -120),
		Size = UDim2.fromOffset(460, 300),
		BackgroundTransparency = 1,
		Parent = screen,
	})
	local layout = Theme.list(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center)
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Parent = stack

	local order = 0
	local function toast(text: string, kind: string)
		local style = KIND_STYLE[kind] or KIND_STYLE.Info
		order += 1

		local card = Theme.panel({
			Size = UDim2.fromOffset(440, 48),
			LayoutOrder = order,
			BackgroundTransparency = 1,
			Parent = stack,
		})
		local scale = Theme.new("UIScale", { Scale = 0.8, Parent = card })
		local icon = Theme.new("TextLabel", {
			Text = style.Icon,
			Font = Theme.Fonts.Title,
			TextSize = 20,
			TextColor3 = Color3.fromRGB(40, 30, 60),
			BackgroundColor3 = style.Color,
			Position = UDim2.fromOffset(10, 9),
			Size = UDim2.fromOffset(30, 30),
			BorderSizePixel = 0,
			Parent = card,
		}, { Theme.round() })
		local label = Theme.label({
			Text = text,
			TextSize = 16,
			TextWrapped = true,
			TextTransparency = 1,
			Position = UDim2.fromOffset(50, 0),
			Size = UDim2.new(1, -60, 1, 0),
			Parent = card,
		})

		Theme.tween(card, 0.3, { BackgroundTransparency = 0.12 })
		Theme.tween(label, 0.3, { TextTransparency = 0 })
		Theme.tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)

		-- Trim oldest
		local children = {}
		for _, child in stack:GetChildren() do
			if child:IsA("Frame") then
				table.insert(children, child)
			end
		end
		table.sort(children, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		for i = 1, #children - MAX_TOASTS do
			children[i]:Destroy()
		end

		task.delay(TOAST_LIFETIME, function()
			if card.Parent then
				Theme.tween(card, 0.4, { BackgroundTransparency = 1 })
				Theme.tween(label, 0.4, { TextTransparency = 1 })
				Theme.tween(icon, 0.4, { BackgroundTransparency = 1, TextTransparency = 1 })
				task.wait(0.4)
				card:Destroy()
			end
		end)
	end
	context.Toast = toast

	----------------------------------------------------------------------------
	-- Travel flash
	----------------------------------------------------------------------------
	local flash = Theme.new("Frame", {
		Name = "TravelFlash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		ZIndex = 50,
		Parent = screen,
	})
	Theme.shimmer(flash, nil, 1.2, 35)

	local function travelFlash()
		flash.BackgroundTransparency = 0.05
		Theme.tween(flash, 0.9, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
	end

	----------------------------------------------------------------------------
	-- Rank-up banner
	----------------------------------------------------------------------------
	local rankBanner = Theme.new("Frame", {
		Name = "RankUp",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(640, 150),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 40,
		Parent = screen,
	})
	local rankScale = Theme.new("UIScale", { Parent = rankBanner })
	local rankTitle = Theme.label({
		Text = "RANK UP!",
		Font = Theme.Fonts.Title,
		TextSize = 72,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.4,
		TextStrokeColor3 = Color3.fromRGB(90, 40, 110),
		Size = UDim2.new(1, 0, 0, 80),
		ZIndex = 41,
		Parent = rankBanner,
	})
	Theme.shimmer(rankTitle, nil, 0.6, 0)
	local rankSub = Theme.label({
		Text = "",
		TextSize = 20,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 86),
		Size = UDim2.new(1, 0, 0, 52),
		ZIndex = 41,
		Parent = rankBanner,
	})

	-- A ring of spinning diamonds around the title.
	local diamonds = {}
	for i = 1, 10 do
		local d = Theme.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(14, 14),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			ZIndex = 40,
			Parent = rankBanner,
		}, { Theme.corner(3) })
		Theme.shimmer(d, nil, 1, 45)
		diamonds[i] = d
	end

	local rankToken = 0
	local function rankUp(text: string)
		rankToken += 1
		local token = rankToken
		rankSub.Text = text
		rankBanner.Visible = true
		rankScale.Scale = 0.3
		Theme.tween(rankScale, 0.6, { Scale = 1 }, Enum.EasingStyle.Back)
		task.spawn(function()
			local start = os.clock()
			while token == rankToken and os.clock() - start < 3.5 do
				local t = os.clock() - start
				for i, d in diamonds do
					local a = t * 1.4 + i / #diamonds * math.pi * 2
					d.Position = UDim2.new(0.5, math.cos(a) * 300, 0, 40 + math.sin(a) * 60)
					d.Rotation = 45 + t * 180
				end
				task.wait()
			end
			if token == rankToken then
				Theme.tween(rankScale, 0.3, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
				task.wait(0.3)
				if token == rankToken then
					rankBanner.Visible = false
				end
			end
		end)
	end

	notify.OnClientEvent:Connect(function(text: string, kind: string)
		if kind == "Travel" then
			travelFlash()
		elseif kind == "RankUp" then
			rankUp(text)
			toast(text, kind)
		else
			toast(text, kind)
		end
	end)
end

return Toasts
