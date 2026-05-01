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
DEVICE="R7KA8P1KFLCAC"
LOAD_ADDR="0x02000000"

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

if ! command -v JLinkExe >/dev/null; then
    echo "JLinkExe not found on PATH — install J-Link Software Pack" >&2
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
JLinkExe -device "${DEVICE}" -if SWD -speed 4000 -autoconnect 1 -CommanderScript "$SCRIPT"
echo "==> done"
