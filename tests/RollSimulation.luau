-- Offline simulation of the roll system (run with tools/roll-sim.sh).
-- Checks: probabilities sum to 1, "1 in N" formatting, precision at the
-- rarest gems, distribution without pity, hidden pity never exceeding its hard
-- guarantee, and excluded gems never coming from a guarantee.
-- Expects GemCatalog, RollConfig and RollEngine in the table M.

local Cat, Cfg, Eng = M.GemCatalog, M.RollConfig, M.RollEngine
local gems = Cat.List
local function u32() return math.floor(math.random() * 4294967296) end
local function U() return Eng.Uniform64(u32) end

-- 1) sanity on displayed odds and probability sum
local sum = 0
for _, g in gems do sum += g.Probability end
assert(math.abs(sum - 1) < 1e-12, "probabilities sum " .. sum)
print(string.format("Quartz true chance %.2f%%  -> shown as %s", gems[1].Probability*100, Cat.FormatOdds(gems[1].Odds)))
assert(Cat.FormatOdds(300000000000000) == "1 in 300,000,000,000,000")
assert(Cat.FormatOdds(2) == "1 in 2")

-- 2) precision at the extremes
local noPity = { Pity = {}, PityExcludeOdds = Cfg.PityExcludeOdds }
local g = Eng.Roll(gems, {}, noPity, 0)
assert(g.Id == "TheFirstLight", "uniform 0 should give rarest, got " .. g.Id)
g = Eng.Roll(gems, {}, noPity, 3.0e-15)
assert(g.Id == "TheFirstLight", "3e-15 should still be The First Light, got " .. g.Id)
g = Eng.Roll(gems, {}, noPity, 3.4e-15)
assert(g.Id == "PrimordialShard", "3.4e-15 should be Primordial Shard, got " .. g.Id)
g = Eng.Roll(gems, {}, noPity, 0.9999999)
assert(g.Id == "Quartz")
assert(Eng.Uniform64(function() return 0 end) == 0)
assert(Eng.Uniform64(function() return 4294967295 end) < 1)

-- 3) distribution without pity
math.randomseed(7)
local N = tonumber(N_ROLLS) or 2000000
local counts = {}
for i = 1, N do local r = Eng.Roll(gems, {}, noPity, U()); counts[r.Id] = (counts[r.Id] or 0) + 1 end
for _, idx in {1, 2, 3, 5, 8, 11} do
  local gg = gems[idx]; local got = (counts[gg.Id] or 0) / N
  local rel = math.abs(got - gg.Probability) / gg.Probability
  print(string.format("%-10s expected %.5f got %.5f (%.1f%% off)", gg.Id, gg.Probability, got, rel*100))
  assert(rel < 0.05, gg.Id .. " distribution off")
end

-- 4) pity: dry streaks never exceed Hard, counters reset correctly
math.randomseed(11)
local pity = {0, 0, 0}
local maxDry = {0, 0, 0}
local dry = {0, 0, 0}
local hardHits = {0, 0, 0}
local T = tonumber(N_PITY_ROLLS) or 3000000
local tier1Count = 0
for i = 1, T do
  local r, newPity, info = Eng.Roll(gems, pity, Cfg, U())
  if info.HardTier then
    hardHits[info.HardTier] += 1
    local tier = Cfg.Pity[info.HardTier]
    assert(r.Odds >= tier.MinOdds and r.Odds < Cfg.PityExcludeOdds, "hard pity gave a non-tier gem")
  end
  for t, tier in Cfg.Pity do
    if r.Odds >= tier.MinOdds then dry[t] = 0 else dry[t] += 1 end
    maxDry[t] = math.max(maxDry[t], dry[t])
    assert(newPity[t] == dry[t], "counter mismatch")
  end
  if r.Odds >= 1000 then tier1Count += 1 end
  pity = newPity
end
for t, tier in Cfg.Pity do
  print(string.format("%s: longest dry streak %d (hard %d), guarantees used %d", tier.Name, maxDry[t], tier.Hard, hardHits[t]))
  assert(maxDry[t] < tier.Hard, tier.Name .. " exceeded hard pity")
end
print(string.format("With pity: a 1-in-1,000+ gem every %.0f rolls on average (no pity: %.0f)", T / tier1Count, 1 / (function() local s=0 for _,gg in gems do if gg.Odds>=1000 then s+=gg.Probability end end return s end)()))

-- 5) excluded gems never appear from a hard guarantee
local forced = {Cfg.Pity[1].Hard, Cfg.Pity[2].Hard, Cfg.Pity[3].Hard}
for i = 1, 20000 do
  local r = Eng.Roll(gems, {forced[1]-1, forced[2]-1, forced[3]-1}, Cfg, U())
  assert(r.Odds >= Cfg.Pity[3].MinOdds and r.Odds < Cfg.PityExcludeOdds)
end
print("ALL OK")
