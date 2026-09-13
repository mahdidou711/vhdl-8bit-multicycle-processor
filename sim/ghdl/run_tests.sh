#!/usr/bin/env bash
# Self-checking GHDL regression for the original 8-bit processor RTL.
#
# Usage:  sim/ghdl/run_tests.sh [test ...]      (default: all tests)
#         KEEP_WORK=1 sim/ghdl/run_tests.sh      (keep the temporary build/log directory)
#         GHDL=/path/to/ghdl sim/ghdl/run_tests.sh
#
# All GHDL libraries, executables and logs are created in a temporary directory,
# never inside the repository.
#
# Language standard:
#   1. Strict check: every RTL and testbench file is analyzed with --std=93 -C.
#      -C (--mb-comments) is needed only because rtl/sqrt16.vhd:18 contains an
#      E-acute encoded in UTF-8 (0xC3 0x89) inside a comment; 0x89 is an ISO-8859-1 C1
#      control code, which strict VHDL-93 rejects even in comments.
#   2. Simulation build: --std=93 -frelaxed. rtl/ual_8.vhd and rtl/proc_8.vhd use
#      component instantiations without configuration or use clause; the strict
#      VHDL-93 default binding rule leaves them unbound in GHDL (-Wbinding) and the
#      ALU sub-units would be open. -frelaxed applies the VHDL-2002 default binding
#      rule (entity of the same name in the work library), which is what the
#      original tools relied on. It also accepts the comment above.
#
# Test outcomes:
#   PASS   testbench printed "TB_RESULT <name> PASS" and GHDL exited with status 0
#   FAIL   anything else
# Exit status is 0 only if there is no FAIL.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GHDL="${GHDL:-ghdl}"

STRICT_FLAGS=(--std=93 -C)
SIM_FLAGS=(--std=93 -frelaxed)

# Analysis order follows the component hierarchy
RTL_FILES=(
    rtl/addsub_8.vhd
    rtl/logic_8.vhd
    rtl/shifter_8.vhd
    rtl/mult_shift_add.vhd
    rtl/sqrt16.vhd
    rtl/ual_8.vhd
    rtl/proc_8.vhd
)
TB_FILES=(
    tb/tb_pkg.vhd
    tb/tb_addsub_8.vhd
    tb/tb_logic_8.vhd
    tb/tb_shifter_8.vhd
    tb/tb_mult_shift_add.vhd
    tb/tb_sqrt16.vhd
    tb/tb_ual_8.vhd
    tb/tb_proc_8.vhd
)

# name|top-level unit|runtime generic
TESTS=(
    "addsub_8|tb_addsub_8|"
    "logic_8|tb_logic_8|"
    "shifter_8|tb_shifter_8|"
    "mult_shift_add|tb_mult_shift_add|"
    "sqrt16|tb_sqrt16|"
    "ual_8|tb_ual_8|"
    "proc_8_program|tb_proc_8|-gRUN_TO_HALT=false"
    "proc_8_halt|tb_proc_8|-gRUN_TO_HALT=true"
)

command -v "$GHDL" >/dev/null 2>&1 || { echo "error: '$GHDL' not found" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/tp3_ghdl.XXXXXX")"
if [[ "${KEEP_WORK:-0}" == "1" ]]; then
    trap 'echo "work directory kept: $WORK"' EXIT
else
    trap 'rm -rf -- "$WORK"' EXIT
fi
mkdir -p "$WORK/strict" "$WORK/sim" "$WORK/logs"

# Test selection
SELECTED=()
if [[ $# -eq 0 ]]; then
    SELECTED=("${TESTS[@]}")
else
    for want in "$@"; do
        found=0
        for t in "${TESTS[@]}"; do
            if [[ "${t%%|*}" == "$want" ]]; then
                SELECTED+=("$t")
                found=1
            fi
        done
        if [[ $found -eq 0 ]]; then
            echo "error: unknown test '$want'" >&2
            echo "available: $(for t in "${TESTS[@]}"; do printf '%s ' "${t%%|*}"; done)" >&2
            exit 2
        fi
    done
fi

echo "GHDL      : $("$GHDL" --version | head -n 1)"
echo "Repository: $ROOT"
echo

analyze_all() {
    local dir="$1"; shift
    local f
    for f in "${RTL_FILES[@]}" "${TB_FILES[@]}"; do
        if ! (cd "$ROOT" && "$GHDL" -a "$@" --workdir="$dir" "$f") >>"$WORK/logs/analyze_$(basename "$dir").log" 2>&1; then
            cat "$WORK/logs/analyze_$(basename "$dir").log" >&2
            echo "error: analysis failed for $f with flags: $*" >&2
            exit 2
        fi
    done
}

echo "Strict VHDL-93 analysis (${STRICT_FLAGS[*]}): ${#RTL_FILES[@]} RTL + ${#TB_FILES[@]} testbench files"
analyze_all "$WORK/strict" "${STRICT_FLAGS[@]}"
echo "Simulation build        (${SIM_FLAGS[*]})"
analyze_all "$WORK/sim" "${SIM_FLAGS[@]}"
echo

n_pass=0; n_fail=0
FAILED=()

for entry in "${SELECTED[@]}"; do
    IFS='|' read -r name top generic <<<"$entry"
    log="$WORK/logs/$name.log"
    args=("$top")
    [[ -n "$generic" ]] && args+=("$generic")

    t0=$(date +%s%N)
    rc=0
    (cd "$WORK/sim" && "$GHDL" --elab-run "${SIM_FLAGS[@]}" --workdir="$WORK/sim" "${args[@]}") >"$log" 2>&1 || rc=$?
    ms=$(( ($(date +%s%N) - t0) / 1000000 ))

    result_line="$(grep -Eo "TB_RESULT [A-Za-z0-9_]+ (PASS|FAIL).*" "$log" | tail -n 1 || true)"
    counts="$(sed -E 's/^TB_RESULT [A-Za-z0-9_]+ (PASS|FAIL) ?//' <<<"$result_line")"
    passed=0
    [[ $rc -eq 0 && "$result_line" == *" PASS "* ]] && passed=1

    if [[ $passed -eq 1 ]]; then
        status="PASS "; n_pass=$((n_pass + 1)); detail="$counts"
    else
        status="FAIL "; n_fail=$((n_fail + 1)); detail="exit=$rc ${counts:-no TB_RESULT line}"
        FAILED+=("$name")
    fi

    printf '[%s] %-16s %6d ms  %s\n' "$status" "$name" "$ms" "$detail"
    if [[ "$status" != "PASS " ]]; then
        tail -n 15 "$log" | sed 's/^/          | /'
    fi
done

echo
echo "Summary: $n_pass passed, $n_fail failed"
if [[ $n_fail -ne 0 ]]; then
    echo "RESULT: FAIL (${FAILED[*]})"
    exit 1
fi
echo "RESULT: OK"
