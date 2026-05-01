#!/usr/bin/env bash
# harvest_display_merge.sh — copy display-related generated FSP outputs from
# a generated reference project into the MicroPython EK_RA8P1 board tree.
#
# Inputs:
#   $1 = path to generated project root (must contain ra_gen/ and ra_cfg/fsp_cfg/)
#        e.g. /tmp/fsp-gen/EK_RA8P1
#
# Outputs:
#   - /Users/alex/micropython/ports/renesas-ra/boards/EK_RA8P1/ra_gen/* updated
#   - /Users/alex/micropython/ports/renesas-ra/boards/EK_RA8P1/ra_cfg/fsp_cfg/* updated
#   - Pre-merge snapshot saved as boards/EK_RA8P1/ra_gen.bak-display-<ts> and
#     boards/EK_RA8P1/ra_cfg.bak-display-<ts>
#
# Preserves (NEVER overwrites these files):
#   - boards/EK_RA8P1/mpconfigboard.h (VCOM/dupterm/LED/heap-end edits)
#   - boards/EK_RA8P1/mpconfigboard.mk (USE_FSP_QSPI=0, USE_FSP_LPM=0)
#   - boards/EK_RA8P1/ra8p1_ek.ld (linker heapsplit/memfix)
#   - boards/EK_RA8P1/pins.csv (PA00-PA15 fix)
#   - boards/EK_RA8P1/board.json
#   - boards/EK_RA8P1/ra8p1_ek_conf.h
#
# Per directive #4: scope is GLCDC + SDRAM + board pin routing only on first pass.
# Avoid camera/touch/menu/images sources — those live in src/ outside the board
# tree, so this script doesn't pull them.

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: $0 <generated-project-root>" >&2
  exit 1
fi

GEN_ROOT="$1"
BOARD="/Users/alex/micropython/ports/renesas-ra/boards/EK_RA8P1"
TS=$(date -u +%Y%m%d-%H%M%S)

if [ ! -d "$GEN_ROOT/ra_gen" ] || [ ! -d "$GEN_ROOT/ra_cfg/fsp_cfg" ]; then
  echo "ERROR: $GEN_ROOT does not contain both ra_gen/ and ra_cfg/fsp_cfg/" >&2
  exit 2
fi

echo "[harvest] source = $GEN_ROOT"
echo "[harvest] target = $BOARD"
echo "[harvest] timestamp = $TS"

# 1) Snapshot current ra_gen/ and ra_cfg/fsp_cfg/
echo "[harvest] snapshotting current ra_gen and ra_cfg…"
cp -a "$BOARD/ra_gen" "$BOARD/ra_gen.bak-display-$TS"
cp -a "$BOARD/ra_cfg" "$BOARD/ra_cfg.bak-display-$TS"

# 2) Replace ra_gen/* with generated output (overwrite scope)
#    These are FSP-generated artifacts and must come from the generator,
#    not from manual reinvention.  See display-integration-plan.md merge rules.
echo "[harvest] copying ra_gen/* …"
RA_GEN_FILES=(
  hal_data.c hal_data.h
  common_data.c common_data.h
  pin_data.c
  vector_data.c vector_data.h
  bsp_pin_cfg.h
  bsp_clock_cfg.h
  bsp_api.h
  bsp_linker_info.h
)
for f in "${RA_GEN_FILES[@]}"; do
  if [ -f "$GEN_ROOT/ra_gen/$f" ]; then
    cp -f "$GEN_ROOT/ra_gen/$f" "$BOARD/ra_gen/$f"
    echo "  ✓ ra_gen/$f"
  else
    echo "  - ra_gen/$f (not generated; skipping)"
  fi
done

# Any other ra_gen files we don't already have a name for, also copy them
# (e.g., r_glcdc.h, r_dmac.h, etc.) — the generator decides what to emit.
for f in "$GEN_ROOT/ra_gen"/*; do
  bn=$(basename "$f")
  if [ ! -f "$BOARD/ra_gen/$bn" ] && [ -f "$f" ]; then
    cp -f "$f" "$BOARD/ra_gen/$bn"
    echo "  + ra_gen/$bn (new)"
  fi
done

# 3) Replace ra_cfg/fsp_cfg/* with generated output
#    bsp/* will be re-generated; non-bsp/* (r_glcdc_cfg.h, r_dmac_cfg.h,
#    r_transfer_cfg.h, r_dave2d_cfg.h, etc.) are the new display content.
echo "[harvest] copying ra_cfg/fsp_cfg/* …"
mkdir -p "$BOARD/ra_cfg/fsp_cfg"
cp -af "$GEN_ROOT/ra_cfg/fsp_cfg/." "$BOARD/ra_cfg/fsp_cfg/"
echo "  ✓ ra_cfg/fsp_cfg/ (full sync)"

# 4) Sanity report — did we get the expected display headers?
echo
echo "[harvest] post-merge display headers present:"
EXPECTED_DISPLAY_HEADERS=(
  "r_glcdc_cfg.h"
  "r_dmac_cfg.h"
  "r_transfer_cfg.h"
  "r_dave2d_cfg.h"
  "r_mipi_phy_cfg.h"
  "r_mipi_csi_cfg.h"
  "r_sdram_cfg.h"
  "r_ioport_cfg.h"
)
for h in "${EXPECTED_DISPLAY_HEADERS[@]}"; do
  found=$(find "$BOARD/ra_cfg/fsp_cfg" -name "$h" -print -quit 2>/dev/null)
  if [ -n "$found" ]; then
    echo "  ✓ $h"
  else
    echo "  ? $h (not present — verify whether expected for this config)"
  fi
done

echo
echo "[harvest] preserved (NOT touched):"
for p in mpconfigboard.h mpconfigboard.mk ra8p1_ek.ld pins.csv board.json ra8p1_ek_conf.h; do
  [ -f "$BOARD/$p" ] && echo "  ✓ $p"
done

echo
echo "[harvest] done. Snapshots:"
echo "  $BOARD/ra_gen.bak-display-$TS"
echo "  $BOARD/ra_cfg.bak-display-$TS"
echo
echo "Next: rebuild MicroPython and run C-side solid-color smoke test."
