--!strict
-- RollEngine
-- Pure roll logic (no Roblox services), so it can be simulated offline.
--
-- Roll(gems, pity, config, uniform) picks one gem:
--   * Base chance of each gem is gem.Probability.
--   * Soft pity: once a tier's dry streak passes SoftStart, its gems' weights
--     are multiplied, ramping linearly to MaxBoost at the Hard roll.
--   * Hard pity: on the Hard-th dry roll the pick is restricted to that tier's
--     gems (keeping their relative odds). The rarest triggered tier wins.
--   * Gems at or above PityExcludeOdds are never boosted or guaranteed.
-- The pick walks from the rarest gem down, so tiny probabilities keep full
-- precision even next to a ~50% common gem.

local RollEngine = {}

export type GemLike = {
	Id: string,
	Odds: number,
	Probability: number,
}

export type PityTier = {
	MinOdds: number,
	SoftStart: number,
	Hard: number,
	MaxBoost: number,
}

export type Config = {
	Pity: { PityTier },
	PityExcludeOdds: number,
}

export type RollInfo = {
	HardTier: number?, -- tier index that forced this roll, if any
	Boost: number, -- largest multiplier that applied to the rolled gem
}

-- Uniform number in [0, 1) with 64 bits of randomness, built from two 32-bit
-- draws. A single draw is not fine-grained enough for odds like 1 in 3e14.
function RollEngine.Uniform64(nextUInt32: () -> number): number
	local hi = nextUInt32()
	local lo = nextUInt32()
	-- hi/2^32 + lo/2^64 can round up to exactly 1.0; keep the result below 1.
	return math.min(hi / 4294967296 + lo / 18446744073709551616, 1 - 2 ^ -53)
end

local function tierMultiplier(tier: PityTier, dry: number): number
	if dry < tier.SoftStart then
		return 1
	end
	local span = math.max(1, tier.Hard - tier.SoftStart)
	local t = math.min(1, (dry - tier.SoftStart + 1) / span)
	return 1 + (tier.MaxBoost - 1) * t
end

local function inTier(gem: GemLike, tier: PityTier, config: Config): boolean
	return gem.Odds >= tier.MinOdds and gem.Odds < config.PityExcludeOdds
end

-- Returns the rolled gem, the updated pity counters and debug info.
-- `pity` is an array of dry-streak counters, one per config.Pity tier.
function RollEngine.Roll(gems: { GemLike }, pity: { number }, config: Config, uniform: number): (GemLike, { number }, RollInfo)
	local tiers = config.Pity

	-- Rarest tier whose guarantee triggers on this roll.
	local hardTier: number? = nil
	for i, tier in tiers do
		if (pity[i] or 0) + 1 >= tier.Hard then
			hardTier = i
		end
	end

	local weights = table.create(#gems, 0)
	local total = 0
	for index, gem in gems do
		local weight
		if hardTier then
			weight = if inTier(gem, tiers[hardTier], config) then gem.Probability else 0
		else
			local boost = 1
			for i, tier in tiers do
				if inTier(gem, tier, config) then
					boost = math.max(boost, tierMultiplier(tier, pity[i] or 0))
				end
			end
			weight = gem.Probability * boost
		end
		weights[index] = weight
		total += weight
	end

	local target = uniform * total
	local picked: GemLike? = nil
	for index = #gems, 1, -1 do
		local weight = weights[index]
		if weight > 0 then
			target -= weight
			if target < 0 then
				picked = gems[index]
				break
			end
		end
	end
	if not picked then
		-- Floating-point leftovers: fall back to the most common eligible gem.
		for index = 1, #gems do
			if weights[index] > 0 then
				picked = gems[index]
				break
			end
		end
	end
	local result = picked :: GemLike

	local boost = 1
	local newPity = table.create(#tiers, 0)
	for i, tier in tiers do
		if result.Odds >= tier.MinOdds then
			newPity[i] = 0
		else
			newPity[i] = (pity[i] or 0) + 1
		end
		if not hardTier and inTier(result, tier, config) then
			boost = math.max(boost, tierMultiplier(tier, pity[i] or 0))
		end
	end

	return result, newPity, { HardTier = hardTier, Boost = boost }
end

return RollEngine
