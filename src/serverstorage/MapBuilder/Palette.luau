-- Palette
-- One place for every colour of the world: a moonlit teal sea, dark violet
-- stratified rock with pale lavender rims, pale temple stone and cyan light.

local rgb = Color3.fromRGB

return table.freeze({
	-- Rock
	Rock = rgb(40, 33, 62),
	RockLight = rgb(58, 48, 88),
	Rim = rgb(196, 178, 236),
	StreakBlue = rgb(150, 200, 255),
	StreakPink = rgb(255, 190, 230),

	-- Temple
	Stone = rgb(214, 208, 240),
	StoneShade = rgb(172, 166, 218),
	StoneDeep = rgb(132, 124, 186),
	Trim = rgb(240, 238, 255),

	-- Light
	Channel = rgb(120, 236, 255),
	ChannelGlow = rgb(70, 165, 225),
	Beam = rgb(160, 245, 255),
	PodGlass = rgb(120, 220, 232),
	PodCore = rgb(175, 255, 240),

	-- Water
	Sea = rgb(34, 108, 118),
	Ripple = rgb(130, 236, 222),

	-- Accents
	Pink = rgb(255, 172, 214),
	Gold = rgb(255, 218, 150),
	Lavender = rgb(196, 166, 255),
	Teal = rgb(112, 232, 222),
	Pearl = rgb(242, 240, 255),

	-- Distance
	Mountain = rgb(38, 58, 84),
	MountainCap = rgb(150, 160, 210),
})
