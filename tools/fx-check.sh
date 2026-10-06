#!/usr/bin/env bash
# Static consistency between the server and the client's effects:
#   * every effect kind the server sends (CombatService.FX / Skills fx) has a
#     handler in CombatFX (Effects.<Kind>);
#   * every skill archetype in GemKits has a body motion of its own name in
#     CombatAnim (A.<Archetype>), and every motion CombatFX asks for exists;
#   * no Enum.FontWeight that Roblox doesn't have (only Thin..Heavy).
#   tools/fx-check.sh
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
kinds=$( (grep -ohE 'CombatService\.FX\("[A-Za-z]+"' src/server -r | sed -E 's/.*"([A-Za-z]+)"/\1/'; grep -ohE 'fx\(ctx, "[A-Za-z]+"' src/server -r | sed -E 's/.*"([A-Za-z]+)"/\1/') | sort -u)
for k in $kinds; do
	if ! grep -q "^function Effects\.$k(" src/client/Combat/CombatFX.luau; then
		echo "FAIL effect kind '$k' is sent by the server but CombatFX has no Effects.$k"
		fail=1
	fi
done
echo "effect kinds: $(echo $kinds | wc -w) sent, all handled"
archetypes=$(sed -n '/^GemKits.Archetypes = {/,/^}/p' src/shared/GemKits.luau | grep -oE '^	[A-Z][A-Za-z]+ = \{' | sed -E 's/^	([A-Za-z]+).*/\1/')
for a in $archetypes; do
	if ! grep -qE "^A\.$a = " src/client/Combat/CombatAnim.luau; then
		echo "FAIL archetype '$a' has no CombatAnim motion A.$a"
		fail=1
	fi
done
echo "archetypes: $(echo $archetypes | wc -w), each with its own motion"
motions=$(sed -n '/^local MOTION/,/^}/p' src/client/Combat/CombatFX.luau | grep -oE '= "[A-Za-z]+"' | sed -E 's/= "([A-Za-z]+)"/\1/'; grep -oE 'return "[A-Za-z]+"' src/client/Combat/CombatFX.luau | sed -E 's/return "([A-Za-z]+)"/\1/')
for m in $(echo "$motions" | sort -u); do
	if ! grep -qE "^A\.$m = " src/client/Combat/CombatAnim.luau; then
		echo "FAIL CombatFX plays motion '$m' but CombatAnim has no A.$m"
		fail=1
	fi
done
echo "motions asked for by CombatFX: $(echo "$motions" | sort -u | wc -l), all defined"
if grep -rnE 'FontWeight\.(Black|ExtraHeavy|UltraBold)' src; then
	echo "FAIL Enum.FontWeight only has Thin..Heavy"
	fail=1
fi
if [ "$fail" -ne 0 ]; then
	echo "FX CHECK FAILED"
	exit 1
fi
echo "FX OK"
