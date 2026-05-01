# EK-RA8P1 MicroPython port — handoff doc + tooling

Companion repo to **[ssql2014/micropython @ ek-ra8p1-port](https://github.com/ssql2014/micropython/tree/ek-ra8p1-port)**.

The MicroPython port itself lives in the fork branch above. This repo holds
the things that live *outside* the source tree:

| Path | Purpose |
|---|---|
| `melissa-spec-porting-plan.md` | Master append-only plan + status log of the porting work, against the original Melissa spec. The single source of truth for what's done / blocked / why. |
| `progress.md` | Earlier-session progress notes (pre-merge into the master plan). |
| `ra8p1-gtioc-pin-table.txt` | 110-entry GPT GTIOC pin table extracted from FSP-generated `ra_cfg.txt`, paste-ready for `ra/ra_gpt.c`. |
| `scripts/rtt_terminal.py` | Interactive REPL terminal that drives SEGGER RTT over SWD. The primary way to talk to the running MicroPython REPL on EK-RA8P1 (the on-board J-Link OB CDC bridge does not deliver bytes — see board README). |
| `scripts/ci_build_ra8p1.sh` | Clean build + size-delta tracker (saves a baseline at `ports/renesas-ra/.size-baseline-EK_RA8P1`). |
| `scripts/flash_ra8p1.sh` | JLinkExe wrapper — flash `firmware.bin` to `0x02000000`, optionally `--halt` for JTAG bring-up. |
| `scripts/install_fsp_v640.sh` | Repeatable install of FSP 6.4.0 + e²studio on a fresh macOS host. |
| `scripts/headless_codegen.py` | Spike at headless FSP code generation (parked — e²studio CLI mode has limitations; doc'd for future). |
| `scripts/display_smoke.c` | C-side GLCDC smoke-test source kept for reference. |
| `scripts/harvest_display_merge.sh` | Helper from the early display bring-up phase (kept for posterity). |
| `originals/` | Historical handoff notes from earlier porting sessions (pre this milestone). |

## Quick start (after cloning the MicroPython fork)

```sh
# Build:
cd ~/micropython/ports/renesas-ra
make BOARD=EK_RA8P1 USE_FSP_QSPI=0 -j8

# Flash:
~/ek-ra8p1-handoff/scripts/flash_ra8p1.sh

# Drive the REPL via SWD (J-Link OB CDC is dead on this board):
python3 ~/ek-ra8p1-handoff/scripts/rtt_terminal.py
```

Prerequisites: J-Link Software Pack on PATH (`JLinkExe`), `pip3 install --break-system-packages pylink-square`, FSP 6.4.0 installed.

## Project status

See `melissa-spec-porting-plan.md` for the full status table. As of the
handoff push: REPL fully working over RTT, six peripherals validated
(`Pin`, `PWM`, `UART`, `I2C` × 3 channels, `SPI`, `RTC`, `ra8p1_display`).
Remaining work is mostly FSP-regen-blocked (ADC, DAC, CANFD) or
hardware-loop-blocked (visual blink confirm, SPI loopback).

## Known not-software issues

1. **J-Link OB CDC VCOM is dead on this board** — confirmed against stock
   Renesas factory firmware. REPL works via SEGGER RTT instead.
2. **External 24 MHz crystal does not stabilize** — `MOSCSF` never goes to
   1, so PLLs are sourced from HOCO instead of MAIN_OSC. Multipliers
   recomputed to keep clock topology unchanged.

Both are documented in detail in the porting plan and the board README.
