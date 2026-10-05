-- Announcements
--   * "Server" announcements: a card slides in at the top for rare pulls by
--     anyone in the server (gem icon, player, gem name, odds).
--   * "Banner": a full-width rainbow ribbon with a flash for the rarest pulls.
--   * context.Toast(text, kind): small status messages (errors, hints, and
--     server notices from the Notify remote). kind: Warning / Success / Info.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GemCatalog = require(ReplicatedStorage:WaitForChild("GemCatalog"))
local GemArt = require(script.Parent:WaitForChild("GemArt"))
local Theme = require(script.Parent:WaitForChild("Theme"))

local C = Theme.Colors

local Announcements = {}

function Announcements.Init(screen: ScreenGui, context)
	local announce = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Announce") :: RemoteEvent
	local localName = Players.LocalPlayer.DisplayName

	----------------------------------------------------------------------------
	-- Server cards (top centre, stacked)
	----------------------------------------------------------------------------
	local stack = Theme.new("Frame", {
		Name = "ServerAnnouncements",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 16),
		Size = UDim2.fromOffset(520, 300),
		BackgroundTransparency = 1,
		ZIndex = 40,
		Parent = screen,
	}, { Theme.list(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center) })

	local order = 0
	local function serverCard(playerName: string, gem: GemCatalog.Gem)
		order += 1
		local tier = GemArt.Tier(gem)
		local card = Theme.panel({
			Size = UDim2.fromOffset(500, 70),
			LayoutOrder = order,
			ZIndex = 40,
			Parent = stack,
		})
		local scale = Theme.new("UIScale", { Scale = 0.6, Parent = card })
		Theme.tween(scale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
		local stroke = card:FindFirstChildOfClass("UIStroke")
		if stroke then
			local gradient = stroke:FindFirstChildOfClass("UIGradient")
			if gradient then
				gradient.Color = if tier >= 4 then GemArt.Rainbow else GemArt.Gradient(gem)
			end
		end
		local icon = GemArt.Icon(gem, 58)
		icon.Position = UDim2.fromOffset(8, 6)
		icon.ZIndex = 41
		icon.Parent = card
		Theme.label({
			Text = `{playerName} found`,
			FontFace = Theme.Faces.Bold,
			TextSize = 15,
			TextColor3 = C.SubText,
			Position = UDim2.fromOffset(76, 8),
			Size = UDim2.new(1, -90, 0, 18),
			ZIndex = 41,
			Parent = card,
		})
		Theme.headline({
			Text = gem.Name,
			TextSize = 24,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(76, 26),
			Size = UDim2.new(0.6, 0, 0, 28),
			ZIndex = 41,
			Parent = card,
		}, if tier >= 4 then GemArt.Rainbow else GemArt.Gradient(gem), 0.5)
		Theme.label({
			Text = GemCatalog.FormatOdds(gem.Odds),
			FontFace = Theme.Faces.Odds,
			TextSize = 12,
			TextColor3 = C.Gold,
			TextXAlignment = Enum.TextXAlignment.Right,
			Position = UDim2.new(0, 0, 0, 34),
			Size = UDim2.new(1, -14, 0, 18),
			ZIndex = 41,
			Parent = card,
		})
		task.delay(6, function()
			Theme.tween(scale, 0.25, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			task.wait(0.3)
			card:Destroy()
		end)
	end

	----------------------------------------------------------------------------
	-- Banner (rarest pulls)
	----------------------------------------------------------------------------
	local function banner(playerName: string, gem: GemCatalog.Gem)
		local flash = Theme.new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0,
			ZIndex = 80,
			Parent = screen,
		})
		Theme.new("UIGradient", { Color = GemArt.Rainbow, Rotation = 30, Parent = flash })
		Theme.tween(flash, 1.2, { BackgroundTransparency = 1 })

		local ribbon = Theme.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.36),
			Size = UDim2.new(1, 0, 0, 0),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.15,
			ClipsDescendants = true,
			ZIndex = 81,
			Parent = screen,
		})
		Theme.new("UIGradient", {
			Color = ColorSequence.new(Color3.fromRGB(40, 20, 70), Color3.fromRGB(90, 40, 120)),
			Rotation = 90,
			Parent = ribbon,
		})
		for _, y in { 0, 1 } do
			local edge = Theme.new("Frame", {
				AnchorPoint = Vector2.new(0, y),
				Position = UDim2.fromScale(0, y),
				Size = UDim2.new(1, 0, 0, 4),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				ZIndex = 82,
				Parent = ribbon,
			})
			Theme.shimmer(edge, GemArt.Rainbow, 0.8, 0)
		end
		Theme.tween(ribbon, 0.5, { Size = UDim2.new(1, 0, 0, 190) }, Enum.EasingStyle.Back)

		Theme.label({
			Text = `{string.upper(playerName)} HAS FOUND`,
			FontFace = Theme.Faces.Heavy,
			TextSize = 22,
			TextColor3 = C.SubText,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, 18),
			Size = UDim2.new(1, 0, 0, 26),
			ZIndex = 83,
			Parent = ribbon,
		})
		Theme.headline({
			Text = gem.Name,
			TextSize = 72,
			Position = UDim2.fromOffset(0, 46),
			Size = UDim2.new(1, 0, 0, 84),
			ZIndex = 83,
			Parent = ribbon,
		}, GemArt.Rainbow, 0.8)
		Theme.label({
			Text = GemCatalog.FormatOdds(gem.Odds),
			FontFace = Theme.Faces.Odds,
			TextSize = 22,
			TextColor3 = C.Gold,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, 136),
			Size = UDim2.new(1, 0, 0, 30),
			ZIndex = 83,
			Parent = ribbon,
		})

		task.delay(6.5, function()
			Theme.tween(ribbon, 0.4, { Size = UDim2.new(1, 0, 0, 0) })
			task.wait(0.45)
			ribbon:Destroy()
			flash:Destroy()
		end)
	end

	announce.OnClientEvent:Connect(function(kind: string, playerName: string, gemId: string)
		local gem = GemCatalog.Get(gemId)
		if not gem or type(playerName) ~= "string" then
			return
		end
		-- Your own pull already gets the full reveal; don't double up on it.
		local mine = playerName == localName
		if kind == "Banner" then
			if mine then
				task.delay(4, banner, playerName, gem)
			else
				banner(playerName, gem)
			end
		elseif kind == "Server" and not mine then
			serverCard(playerName, gem)
		end
	end)

	----------------------------------------------------------------------------
	-- Toasts (bottom centre, above the skill bar)
	----------------------------------------------------------------------------
	local toasts = Theme.new("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -250),
		Size = UDim2.fromOffset(460, 200),
		BackgroundTransparency = 1,
		ZIndex = 45,
		Parent = screen,
	})
	local layout = Theme.list(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center)
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Parent = toasts

	local toastOrder = 0
	context.Toast = function(text: string, kind: string?)
		toastOrder += 1
		local card = Theme.panel({ Size = UDim2.fromOffset(440, 40), LayoutOrder = toastOrder, ZIndex = 45, Parent = toasts })
		Theme.label({
			Text = text,
			FontFace = Theme.Faces.Bold,
			TextSize = 15,
			TextColor3 = if kind == "Warning" then C.Warning elseif kind == "Success" then C.Success elseif kind == "Info" then C.Cyan else C.Text,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 46,
			Parent = card,
		})
		task.delay(2.6, function()
			Theme.tween(card, 0.3, { BackgroundTransparency = 1 })
			task.wait(0.3)
			card:Destroy()
		end)
	end

	-- Messages from the server (founder commands and the like).
	local notify = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Notify") :: RemoteEvent
	notify.OnClientEvent:Connect(function(text: string, kind: string?)
		if type(text) == "string" then
			context.Toast(text, kind)
		end
	end)
end

return Announcements
