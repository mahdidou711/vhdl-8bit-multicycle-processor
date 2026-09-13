#!/usr/bin/env bash
# Synthesis-oriented GHDL validation for the DE1 FPGA wrapper.
#
# This does not invoke Quartus and makes no claim about Quartus compilation.
# It only proves, with GHDL, that:
#   1. the 7 RTL files and the wrapper analyze together under the same
#      relaxed binding rule the project's simulation build uses;
#   2. proc8_de1_top elaborates cleanly;
#   3. `ghdl synth` (the GHDL synthesis pass) accepts the design.
#
# Usage:  sim/ghdl/check_fpga.sh
#         GHDL=/path/to/ghdl sim/ghdl/check_fpga.sh
#
# All GHDL libraries and logs are created in a temporary directory, never
# inside the repository.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GHDL="${GHDL:-ghdl}"

# Same standard/binding flags as sim/ghdl/run_tests.sh's simulation build:
# --std=93 -frelaxed, needed for the component instantiations without
# configuration or use clause in rtl/ual_8.vhd and rtl/proc_8.vhd.
FLAGS=(--std=93 -frelaxed)

RTL_FILES=(
    rtl/addsub_8.vhd
    rtl/logic_8.vhd
    rtl/shifter_8.vhd
    rtl/mult_shift_add.vhd
    rtl/sqrt16.vhd
    rtl/ual_8.vhd
    rtl/proc_8.vhd
)
WRAPPER_FILE="fpga/de1/proc8_de1_top.vhd"
TOP_UNIT="proc8_de1_top"

command -v "$GHDL" >/dev/null 2>&1 || { echo "error: '$GHDL' not found" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/tp3_fpga_check.XXXXXX")"
if [[ "${KEEP_WORK:-0}" == "1" ]]; then
    trap 'echo "work directory kept: $WORK"' EXIT
else
    trap 'rm -rf -- "$WORK"' EXIT
fi

echo "GHDL      : $("$GHDL" --version | head -n 1)"
echo "Repository: $ROOT"
echo

echo "Analysis (${FLAGS[*]}): ${#RTL_FILES[@]} RTL files + $WRAPPER_FILE"
for f in "${RTL_FILES[@]}" "$WRAPPER_FILE"; do
    if ! (cd "$ROOT" && "$GHDL" -a "${FLAGS[@]}" --workdir="$WORK" "$f") >"$WORK/analyze.log" 2>&1; then
        cat "$WORK/analyze.log" >&2
        echo "error: analysis failed for $f" >&2
        exit 1
    fi
done
echo "  ok"

echo "Elaboration: $TOP_UNIT"
if ! (cd "$ROOT" && "$GHDL" -e "${FLAGS[@]}" --workdir="$WORK" -o "$WORK/$TOP_UNIT" "$TOP_UNIT") >"$WORK/elab.log" 2>&1; then
    cat "$WORK/elab.log" >&2
    echo "error: elaboration failed for $TOP_UNIT" >&2
    exit 1
fi
echo "  ok"

echo "Synthesis (ghdl synth): $TOP_UNIT"
if ! (cd "$ROOT" && "$GHDL" --synth "${FLAGS[@]}" --workdir="$WORK" "$TOP_UNIT") >"$WORK/synth.out" 2>"$WORK/synth.log"; then
    cat "$WORK/synth.log" >&2
    echo "error: ghdl synth failed for $TOP_UNIT" >&2
    exit 1
fi
echo "  ok"

echo
echo "RESULT: OK (GHDL analysis, elaboration and synthesis-oriented check passed; Quartus compilation not performed)"
