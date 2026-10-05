#!/usr/bin/env bash
# Runs tests/RollSimulation.luau against the real GemCatalog / RollConfig /
# RollEngine sources using the standalone Luau CLI (https://github.com/luau-lang/luau).
#   tools/roll-sim.sh [path/to/luau] [rolls] [pity-rolls]
set -euo pipefail
cd "$(dirname "$0")/.."
LUAU="${1:-luau}"
ROLLS="${2:-300000}"
PITY_ROLLS="${3:-600000}"
OUT="$(mktemp)"
{
	echo 'local C3 = {}; C3.__index = C3'
	echo 'Color3 = { fromRGB = function(r, g, b) return setmetatable({ R = r, G = g, B = b }, C3) end }'
	echo "local M = {}"
	echo "local N_ROLLS, N_PITY_ROLLS = $ROLLS, $PITY_ROLLS"
	for path in src/shared/GemCatalog src/server/Modules/RollConfig src/server/Modules/RollEngine; do
		name="$(basename "$path")"
		echo "do"
		grep -v '^--!strict' "$path.luau" | sed "s/^return $name\$/M.$name = $name/"
		echo "end"
	done
	cat tests/RollSimulation.luau
} > "$OUT"
"$LUAU" "$OUT"
