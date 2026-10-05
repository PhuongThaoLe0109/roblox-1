--!strict
-- RollConfig (SERVER ONLY — never move this to ReplicatedStorage)
-- Roll pacing, server announcements and the hidden pity system. Players are
-- never told about pity: the displayed odds stay the same, but long dry
-- streaks quietly raise the chance of better gems.

local RollConfig = {}

-- Minimum seconds between rolls for one player (anti-spam).
RollConfig.Cooldown = 1.5

-- Everyone in the server sees a message for gems at least this rare ("1 in N").
RollConfig.AnnounceServerOdds = 100_000
-- A full-screen banner for gems at least this rare.
RollConfig.AnnounceBannerOdds = 100_000_000
-- Pulls at least this rare are saved to the DataStore immediately.
RollConfig.SaveImmediatelyOdds = 100_000

-- Gems at least this rare are pure luck: never boosted or guaranteed by pity.
RollConfig.PityExcludeOdds = 1_000_000_000_000

export type PityTier = {
	Name: string,
	MinOdds: number, -- gems at least this rare count for the tier
	SoftStart: number, -- dry rolls before the boost starts
	Hard: number, -- this roll is guaranteed to give a tier gem
	MaxBoost: number, -- multiplier reached just before the guarantee
}

-- Ordered from the most common tier to the rarest. A tier's counter resets
-- whenever a gem of that tier (or rarer) is rolled.
RollConfig.Pity = {
	{ Name = "Tier1", MinOdds = 1_000, SoftStart = 100, Hard = 200, MaxBoost = 30 },
	{ Name = "Tier2", MinOdds = 100_000, SoftStart = 2_000, Hard = 5_000, MaxBoost = 80 },
	{ Name = "Tier3", MinOdds = 10_000_000, SoftStart = 20_000, Hard = 50_000, MaxBoost = 30 },
} :: { PityTier }

for i, tier in RollConfig.Pity do
	assert(tier.SoftStart < tier.Hard, `RollConfig: {tier.Name} SoftStart must be below Hard`)
	if i > 1 then
		assert(tier.MinOdds > RollConfig.Pity[i - 1].MinOdds, "RollConfig: pity tiers must get rarer")
	end
	table.freeze(tier)
end
table.freeze(RollConfig.Pity)
table.freeze(RollConfig)

return RollConfig
