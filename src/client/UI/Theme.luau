-- Theme
-- Shared look & feel for every UI module: pastel crystal palette, fonts,
-- an instance factory, and animated "shimmer" gradients (one render loop
-- drives every shimmer so there are no per-element connections to leak).

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Theme = {}

Theme.GameTitle = "Universal Gems"

local rgb = Color3.fromRGB

Theme.Colors = {
	Panel = rgb(30, 22, 52),
	PanelLight = rgb(54, 40, 88),
	PanelGlass = rgb(46, 34, 80),
	Stroke = rgb(255, 190, 235),
	Text = rgb(255, 255, 255),
	SubText = rgb(210, 200, 235),
	Muted = rgb(150, 140, 175),
	Pink = rgb(255, 150, 205),
	Lavender = rgb(190, 160, 255),
	Cyan = rgb(130, 225, 255),
	Gold = rgb(255, 215, 120),
	Success = rgb(140, 240, 190),
	Warning = rgb(255, 200, 120),
	Danger = rgb(255, 120, 140),
}

Theme.Fonts = {
	Title = Enum.Font.FredokaOne,
	Body = Enum.Font.GothamMedium,
	Bold = Enum.Font.GothamBold,
}

-- Typography. Roblox font families (no custom assets needed):
--   Display  Merriweather Heavy Italic: gem names, big reveals
--   Title    Merriweather Bold: panel titles
--   Odds     Michroma: "1 in N" lines
--   Heavy    Nunito Heavy: buttons, numbers
--   Bold     Nunito Bold, Body Nunito SemiBold: everything else
local MERRIWEATHER = "rbxasset://fonts/families/Merriweather.json"
local NUNITO = "rbxasset://fonts/families/Nunito.json"
Theme.Faces = {
	Display = Font.new(MERRIWEATHER, Enum.FontWeight.Heavy, Enum.FontStyle.Italic),
	Title = Font.new(MERRIWEATHER, Enum.FontWeight.Bold),
	Odds = Font.new("rbxasset://fonts/families/Michroma.json"),
	Heavy = Font.new(NUNITO, Enum.FontWeight.Heavy),
	Bold = Font.new(NUNITO, Enum.FontWeight.Bold),
	Body = Font.new(NUNITO, Enum.FontWeight.SemiBold),
}

-- Legacy Enum.Font values passed by callers map onto the new faces.
local FACE_FOR_FONT = {
	[Theme.Fonts.Title] = Theme.Faces.Heavy,
	[Theme.Fonts.Bold] = Theme.Faces.Bold,
	[Theme.Fonts.Body] = Theme.Faces.Body,
}

local function applyFace(props: { [string]: any })
	if props.Font ~= nil then
		props.FontFace = props.FontFace or FACE_FOR_FONT[props.Font] or Theme.Faces.Body
		props.Font = nil
	end
end

-- Pastel "crystal light" sequence used for shimmering strokes and fills.
Theme.Prism = ColorSequence.new({
	ColorSequenceKeypoint.new(0, rgb(255, 160, 210)),
	ColorSequenceKeypoint.new(0.25, rgb(200, 170, 255)),
	ColorSequenceKeypoint.new(0.5, rgb(140, 225, 255)),
	ColorSequenceKeypoint.new(0.75, rgb(255, 240, 200)),
	ColorSequenceKeypoint.new(1, rgb(255, 160, 210)),
})

--------------------------------------------------------------------------------
-- Factory
--------------------------------------------------------------------------------

-- Theme.new("Frame", { Size = ... }, { child1, child2 })
function Theme.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className)
	local parent = nil
	for key, value in props or {} do
		if key == "Parent" then
			parent = value
		else
			(instance :: any)[key] = value
		end
	end
	for _, child in children or {} do
		child.Parent = instance
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function Theme.corner(radius: number?): UICorner
	return Theme.new("UICorner", { CornerRadius = UDim.new(0, radius or 12) })
end

function Theme.round(): UICorner
	return Theme.new("UICorner", { CornerRadius = UDim.new(1, 0) })
end

function Theme.padding(all: number, horizontal: number?): UIPadding
	local h = horizontal or all
	return Theme.new("UIPadding", {
		PaddingTop = UDim.new(0, all),
		PaddingBottom = UDim.new(0, all),
		PaddingLeft = UDim.new(0, h),
		PaddingRight = UDim.new(0, h),
	})
end

function Theme.stroke(color: Color3?, thickness: number?, transparency: number?): UIStroke
	return Theme.new("UIStroke", {
		Color = color or Theme.Colors.Stroke,
		Thickness = thickness or 1.5,
		Transparency = transparency or 0.2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Theme.list(direction: Enum.FillDirection?, spacing: number?, align: Enum.HorizontalAlignment?): UIListLayout
	return Theme.new("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, spacing or 6),
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

function Theme.label(props: { [string]: any }): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		TextColor3 = Theme.Colors.Text,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 20),
	}
	for key, value in props do
		defaults[key] = value
	end
	if props.FontFace then
		defaults.Font = nil
	end
	applyFace(defaults)
	return Theme.new("TextLabel", defaults)
end

-- Premium lettering: display face, shimmering gradient fill and a soft dark
-- outline so it reads on any background. `sequence` defaults to Theme.Prism.
function Theme.headline(props: { [string]: any }, sequence: ColorSequence?, speed: number?): TextLabel
	local defaults = {
		FontFace = Theme.Faces.Display,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
	}
	for key, value in props do
		defaults[key] = value
	end
	local label = Theme.label(defaults)
	Theme.shimmer(label, sequence, speed or 0.35, 0)
	Theme.new("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Color = Color3.fromRGB(45, 20, 70),
		Thickness = math.max(1.5, (label.TextSize or 20) / 18),
		Transparency = 0.25,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = label,
	})
	return label
end

--------------------------------------------------------------------------------
-- Shimmer gradients
--------------------------------------------------------------------------------

local shimmers: { [UIGradient]: { Speed: number, Phase: number } } = setmetatable({}, { __mode = "k" }) :: any

-- Adds a UIGradient whose highlight sweeps continuously across the parent.
-- Works on GuiObjects and on UIStrokes.
function Theme.shimmer(parent: Instance, sequence: ColorSequence?, speed: number?, rotation: number?): UIGradient
	local gradient = Theme.new("UIGradient", {
		Color = sequence or Theme.Prism,
		Rotation = rotation or 20,
		Parent = parent,
	})
	shimmers[gradient] = { Speed = speed or 0.25, Phase = math.random() }
	return gradient
end

RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for gradient, data in shimmers do
		if gradient.Parent then
			-- Offset slides -1..1 so the colour bands sweep across and wrap.
			local x = ((t * data.Speed + data.Phase) % 1) * 2 - 1
			gradient.Offset = Vector2.new(x, 0)
		end
	end
end)

--------------------------------------------------------------------------------
-- Composite widgets
--------------------------------------------------------------------------------

-- Dark glassy panel with a shimmering prism border.
function Theme.panel(props: { [string]: any }): Frame
	local defaults = {
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
	}
	for key, value in props do
		defaults[key] = value
	end
	local frame = Theme.new("Frame", defaults)
	Theme.corner(14).Parent = frame
	local stroke = Theme.stroke(Color3.new(1, 1, 1), 2, 0.1)
	stroke.Parent = frame
	Theme.shimmer(stroke, nil, 0.18)
	Theme.new("UIGradient", {
		Color = ColorSequence.new(Theme.Colors.PanelLight, Theme.Colors.Panel),
		Rotation = 90,
		Parent = frame,
	})
	return frame
end

function Theme.tween(instance: Instance, seconds: number, goals: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(seconds, style or Enum.EasingStyle.Quint, direction or Enum.EasingDirection.Out),
		goals
	)
	tween:Play()
	return tween
end

-- Rounded button with a gradient fill, shimmer and a springy hover/press.
function Theme.button(text: string, color: Color3?, props: { [string]: any }?): TextButton
	local base = color or Theme.Colors.Pink
	local defaults = {
		Text = text,
		Font = Theme.Fonts.Title,
		TextSize = 18,
		TextColor3 = Theme.Colors.Text,
		BackgroundColor3 = base,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(140, 40),
	}
	for key, value in props or {} do
		defaults[key] = value
	end
	if props and props.FontFace then
		defaults.Font = nil
	end
	applyFace(defaults)
	local button = Theme.new("TextButton", defaults)
	Theme.corner(12).Parent = button
	local h, s, v = base:ToHSV()
	Theme.new("UIGradient", {
		Color = ColorSequence.new(Color3.fromHSV(h, s * 0.6, math.min(1, v * 1.15)), Color3.fromHSV(h, math.min(1, s * 1.1), v * 0.8)),
		Rotation = 90,
		Parent = button,
	})
	local stroke = Theme.stroke(Color3.new(1, 1, 1), 1.5, 0.35)
	stroke.Parent = button
	Theme.shimmer(stroke, nil, 0.4)
	Theme.new("UITextSizeConstraint", { MaxTextSize = defaults.TextSize, Parent = button })

	local scale = Theme.new("UIScale", { Parent = button })
	button.MouseEnter:Connect(function()
		Theme.tween(scale, 0.18, { Scale = 1.06 }, Enum.EasingStyle.Back)
	end)
	button.MouseLeave:Connect(function()
		Theme.tween(scale, 0.18, { Scale = 1 })
	end)
	button.MouseButton1Down:Connect(function()
		Theme.tween(scale, 0.08, { Scale = 0.94 })
	end)
	button.MouseButton1Up:Connect(function()
		Theme.tween(scale, 0.2, { Scale = 1.04 }, Enum.EasingStyle.Back)
	end)
	return button
end

-- Horizontal progress bar; returns (container, setFn(alpha, color?)).
function Theme.progressBar(props: { [string]: any }): (Frame, (number, Color3?) -> ())
	local defaults = {
		BackgroundColor3 = Color3.fromRGB(20, 14, 36),
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 10),
		ClipsDescendants = true,
	}
	for key, value in props do
		defaults[key] = value
	end
	local bar = Theme.new("Frame", defaults)
	Theme.round().Parent = bar
	local fill = Theme.new("Frame", {
		Name = "Fill",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Parent = bar,
	})
	Theme.round().Parent = fill
	local gradient = Theme.shimmer(fill, nil, 0.35, 0)

	local function set(alpha: number, color: Color3?)
		Theme.tween(fill, 0.35, { Size = UDim2.fromScale(math.clamp(alpha, 0, 1), 1) })
		if color then
			local h, s, v = color:ToHSV()
			gradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, color),
				ColorSequenceKeypoint.new(0.5, Color3.fromHSV(h, s * 0.35, 1)),
				ColorSequenceKeypoint.new(1, color),
			})
			local _ = v
		end
	end
	return bar, set
end

function Theme.formatNumber(n: number): string
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^,", ""))
end

function Theme.formatDuration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = seconds // 3600
	local m = (seconds % 3600) // 60
	if h > 0 then
		return `{h}h {m}m`
	end
	return `{m}m {seconds % 60}s`
end

return Theme
