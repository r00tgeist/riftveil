#!/usr/bin/env bash
# RIFTVEIL full verification suite. Run from anywhere:  bash tools/check_all.sh
# Needs lua5.3 and luajit (the game's runtime); luacheck optional.
#   QUICK=1  fewer fuzz seeds and a shorter soak
set -u
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FAILS=0
pass() { printf "  \033[32mPASS\033[0m  %s\n" "$1"; }
fail() { printf "  \033[31mFAIL\033[0m  %s\n" "$1"; FAILS=$((FAILS + 1)); }

SEEDS="1 2 3 4 5 6 7 8"; SOAK=200000
[ "${QUICK:-}" = 1 ] && SEEDS="1 2" && SOAK=40000

echo "1. Syntax"
luac5.3 -p riftveil.lua 2>/dev/null && pass "Lua 5.3 parse" || fail "Lua 5.3 parse"
luajit -bl riftveil.lua >/dev/null 2>&1 && pass "LuaJIT parse (the game's runtime)" || fail "LuaJIT parse"

echo "2. Static analysis"
if command -v luacheck >/dev/null; then
    out=$(luacheck riftveil.lua --std luajit --no-color --no-max-line-length \
          --globals client entity globals ui renderer plist cvar database readfile writefile panorama 2>&1 | tail -1)
    echo "$out" | grep -q "0 warnings / 0 errors" && pass "luacheck: $out" || fail "luacheck: $out"
else
    echo "  skip  luacheck not installed"
fi

echo "3. Scripted scenario (both runtimes)"
for rt in lua5.3 luajit; do
    $rt tools/sandbox_check.lua > "$TMP/s_$rt.txt" 2>&1
    grep -q "^PASS" "$TMP/s_$rt.txt" && pass "$rt: harness, coverage, unit checks" || { fail "$rt harness"; grep FAIL "$TMP/s_$rt.txt" | head -5; }
done

echo "4. Determinism: identical plist writes across runtimes"
norm() { awk -F'\t' '{v=$4; if (v ~ /^-?[0-9.e+-]+$/) v=sprintf("%.6f", v+0); if (v=="-0.000000") v="0.000000"; print $1"\t"$2"\t"$3"\t"v}' "$1"; }
for eng in on off; do
    envx=""; [ $eng = off ] && envx="RV_NO_ENGINE=1"
    for rt in lua5.3 luajit; do env $envx RV_PLIST_OUT="$TMP/p_${eng}_$rt.txt" $rt tools/sandbox_check.lua >/dev/null 2>&1; done
    if cmp -s <(norm "$TMP/p_${eng}_lua5.3.txt") <(norm "$TMP/p_${eng}_luajit.txt"); then
        pass "engine $eng: $(wc -l < "$TMP/p_${eng}_luajit.txt") writes identical"
    else fail "engine $eng: runtimes diverge"; fi
done

echo "5. Fuzz: hostile worlds, cross-runtime (seeds: $SEEDS)"
for seed in $SEEDS; do
    ok=1
    for rt in lua5.3 luajit; do
        RV_FUZZ=$seed RV_TICKS=20000 RV_PLIST_OUT="$TMP/f_$rt.txt" timeout 900 $rt tools/sandbox_check.lua > "$TMP/f_$rt.out" 2>&1
        grep -q "^PASS" "$TMP/f_$rt.out" || { ok=0; grep FAIL "$TMP/f_$rt.out" | head -3; }
    done
    cmp -s <(norm "$TMP/f_lua5.3.txt") <(norm "$TMP/f_luajit.txt") || { ok=0; echo "    runtimes diverge"; }
    [ $ok = 1 ] && pass "seed $seed: $(wc -l < "$TMP/f_luajit.txt") writes, valid, identical" || fail "seed $seed"
done

echo "6. Soak: $SOAK ticks on LuaJIT, memory must stay flat"
RV_FUZZ=99 RV_TICKS=$SOAK timeout 1800 luajit tools/sandbox_check.lua > "$TMP/soak.txt" 2>&1
line=$(grep "net heap peak" "$TMP/soak.txt" | sed 's/^ *//')
grep -q "^PASS" "$TMP/soak.txt" && pass "$line" || { fail "soak"; grep FAIL "$TMP/soak.txt" | head -3; }

echo "7. Decision engine simulation (LuaJIT)"
luajit tools/engine_sim.lua > "$TMP/sim.txt" 2>&1 && pass "$(grep 'average gain' "$TMP/sim.txt"); $(grep -o 'kept the chain.s pick in [0-9/]* random cases' "$TMP/sim.txt")" \
    || { fail "engine sim"; tail -4 "$TMP/sim.txt"; }

echo "8. Log analyzer smoke test"
printf '%s\n' '[00:00:00.000][INF][init] RIFTVEIL v7.7 loaded' \
    '[00:00:01.000][INF][hit] player=a b group=head dmg=100 meth=suppress val=-29 bt=0 st=running eng=pose:inv p=0.61' \
    '[00:00:02.000][WRN][miss] player=a b reason=? meth=hit_mem val=31 bt=0 hc=80% eng=hitmem:inv* p=0.55' > "$TMP/log.txt"
lua5.3 tools/log_report.lua "$TMP/log.txt" > "$TMP/rep.txt" 2>&1 && grep -q "Brier" "$TMP/rep.txt" \
    && pass "parses hit/miss/eng/p lines" || fail "log_report"

echo "9. Performance on LuaJIT (2v2: net update + 4 paint frames per tick)"
line=$(RV_BENCH=2 luajit tools/sandbox_check.lua 2>&1 | grep "^Bench")
us=$(echo "$line" | grep -o 'total at 4 frames/tick [0-9.]*' | grep -o '[0-9.]*$')
if [ -n "$us" ] && awk "BEGIN{exit !($us < 500)}"; then pass "$us us/tick (ceiling 500; tick budget 15625)"; else fail "bench: ${line:-no output}"; fi

echo
[ $FAILS = 0 ] && printf "\033[32mALL CHECKS PASSED\033[0m\n" || printf "\033[31m%d CHECK(S) FAILED\033[0m\n" "$FAILS"
exit $FAILS
