#!/usr/bin/env bash
# flash_ra8p1.sh — flash build-EK_RA8P1/firmware.bin via J-Link OB.
#
# Requires JLinkExe on PATH (Segger J-Link Software Pack installed).
# Code-flash region 0 on RA8P1 starts at 0x02000000 — that matches the
# .text origin in ports/renesas-ra/boards/EK_RA8P1/ra8p1_ek.ld.
#
# Usage:
#   scripts/flash_ra8p1.sh                # flash and run
#   scripts/flash_ra8p1.sh --halt         # flash and halt at reset (for JTAG bring-up)

set -euo pipefail

MICROPYTHON_ROOT="${MICROPYTHON_ROOT:-/Users/alex/micropython}"
BIN="${MICROPYTHON_ROOT}/ports/renesas-ra/build-EK_RA8P1/firmware.bin"
# CRITICAL: use the core name, NOT the package code (R7KA8P1KFLCAC causes
# a 10+ minute hang on the OSPI flash region).
DEVICE="R7KA8P1KF_CPU0"
LOAD_ADDR="0x02000000"
OSPI_SCRIPT="/Users/alex/ra-fsp-examples/example_projects/ek_ra8p1/_quickstart/quickstart_ek_ra8p1_ep/e2studio/script/RA8x1_Reset_OSPI.JLinkScript"

HALT_AFTER_FLASH=0
for arg in "$@"; do
    case "$arg" in
        --halt) HALT_AFTER_FLASH=1 ;;
        *) echo "unknown arg: $arg" >&2; exit 2 ;;
    esac
done

if [[ ! -f "$BIN" ]]; then
    echo "no firmware: $BIN — build first" >&2
    exit 1
fi

JLINK="${JLINK:-/Users/alex/jlink_v938a_extract/Applications/SEGGER/JLink_V938a/JLinkExe}"
if [[ ! -x "$JLINK" ]]; then
    echo "JLinkExe not found: $JLINK — set JLINK env var or install to default path" >&2
    exit 1
fi

SCRIPT=$(mktemp)
trap 'rm -f "$SCRIPT"' EXIT

if [[ "$HALT_AFTER_FLASH" -eq 1 ]]; then
    cat > "$SCRIPT" <<EOF
loadbin ${BIN}, ${LOAD_ADDR}
r
h
qc
EOF
else
    cat > "$SCRIPT" <<EOF
loadbin ${BIN}, ${LOAD_ADDR}
r
g
qc
EOF
fi

echo "==> flashing $BIN to ${DEVICE} @ ${LOAD_ADDR}"
"$JLINK" -device "${DEVICE}" -if SWD -speed 4000 -autoconnect 1 \
    -JLinkScriptFile "${OSPI_SCRIPT}" -CommanderScript "$SCRIPT"
echo "==> done"
