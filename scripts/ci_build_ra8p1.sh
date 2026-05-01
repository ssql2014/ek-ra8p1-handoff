#!/usr/bin/env bash
# ci_build_ra8p1.sh — clean build + size delta for EK_RA8P1.
#
# Run from anywhere; CDs to ports/renesas-ra under MICROPYTHON_ROOT.
# Reports text/data/bss size and computes delta against the previous build
# if a baseline was saved (./.size-baseline-EK_RA8P1).
#
# Usage:
#   scripts/ci_build_ra8p1.sh              # build + report
#   scripts/ci_build_ra8p1.sh --baseline   # build + save current size as baseline
#   scripts/ci_build_ra8p1.sh --clean      # clean + build (slower)
#
# Exit codes:
#   0 = build succeeded
#   1 = build failed
#   2 = arguments invalid

set -euo pipefail

MICROPYTHON_ROOT="${MICROPYTHON_ROOT:-/Users/alex/micropython}"
PORT_DIR="${MICROPYTHON_ROOT}/ports/renesas-ra"
BOARD="EK_RA8P1"
BUILD_DIR="${PORT_DIR}/build-${BOARD}"
ELF="${BUILD_DIR}/firmware.elf"
BASELINE="${PORT_DIR}/.size-baseline-${BOARD}"

mode="report"
for arg in "$@"; do
    case "$arg" in
        --baseline) mode="baseline" ;;
        --clean)    mode="clean" ;;
        -h|--help)
            sed -n '2,18p' "$0"
            exit 0
            ;;
        *)
            echo "unknown arg: $arg" >&2
            exit 2
            ;;
    esac
done

cd "$PORT_DIR"

if [[ "$mode" == "clean" ]]; then
    echo "==> make clean BOARD=${BOARD}"
    make clean BOARD="${BOARD}" >/dev/null
fi

echo "==> make BOARD=${BOARD} USE_FSP_QSPI=0 -j8"
make BOARD="${BOARD}" USE_FSP_QSPI=0 -j8

if [[ ! -f "$ELF" ]]; then
    echo "BUILD FAILED — no $ELF" >&2
    exit 1
fi

# Size readout — use the toolchain's size tool, falling back to host size if missing.
if command -v arm-none-eabi-size >/dev/null; then
    SIZE=arm-none-eabi-size
else
    SIZE=$(find /Applications -name 'arm-none-eabi-size' 2>/dev/null | head -1)
    if [[ -z "$SIZE" ]]; then
        echo "warn: no arm-none-eabi-size found; using host size" >&2
        SIZE=size
    fi
fi

echo
echo "==> Section sizes"
"$SIZE" "$ELF"

# Extract dec column for delta tracking.
NEW=$("$SIZE" "$ELF" | awk 'NR==2 {print $4}')

if [[ "$mode" == "baseline" ]]; then
    echo "$NEW" > "$BASELINE"
    echo "==> baseline saved: $NEW bytes (dec)"
elif [[ -f "$BASELINE" ]]; then
    OLD=$(cat "$BASELINE")
    DELTA=$((NEW - OLD))
    echo
    if [[ "$DELTA" -gt 0 ]]; then
        echo "==> size DELTA: +${DELTA} bytes (was $OLD, now $NEW)"
    elif [[ "$DELTA" -lt 0 ]]; then
        echo "==> size DELTA: ${DELTA} bytes (was $OLD, now $NEW)"
    else
        echo "==> size unchanged: $NEW bytes"
    fi
fi

echo
echo "==> firmware artifacts:"
ls -la "${BUILD_DIR}"/firmware.{elf,bin,hex} 2>/dev/null || true
