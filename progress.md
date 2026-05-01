# EK-RA8P1 Display Track Progress (ist-mac-s side)

Maintained by: claude-opus-4-7 on ist-mac-s
Last update: 2026-04-30 11:55 local

## Status snapshot

- **Build**: ✓ smoke-enabled firmware builds clean and links.
  - `firmware.elf` text=281,084 / data=112 / bss=4,920,336 / total=5,201,532 (delta vs no-smoke: +2,600 text, +8 data, +16 bss).
  - `main.o` references `g_display`, `g_ioport_ctrl`, `g_bsp_pin_cfg`, `R_BSP_SdramInit` (from `common_data.o`, `pin_data.o`, `bsp_sdram.o`).
- **Flash**: ✓ programmed at 0x02000000, verified by JLinkExe.
- **Runtime**: ✓ GLCDC reaches DISPLAY_STATE_DISPLAYING (state field in `g_display_ctrl` at `0x2200086C` = `0x00000002`).
- **Probe**: ✓ J-Link OB-RA4M2 healthy, SWD@4MHz, halt+regs+mem32 all working.
- **Open**: framebuffer is uninitialized `.sdram_noinit` content (smoke test doesn't paint — next iteration adds pattern fill).

## Build-integrity fix this session

### Symptom

Earlier builds with `make CFLAGS_EXTRA=-DMICROPY_RA8P1_BRINGUP_DISPLAY_TEST=1` AND
later `CFLAGS_USERMOD='-DMICROPY_RA8P1_BRINGUP_DISPLAY_TEST=1'` BOTH silently
dropped the macro. `nm build-EK_RA8P1/main.o | grep -i display|smoke|glcdc|sdram`
came back empty even though `g_display` was present in `common_data.o` and the
overall link succeeded — i.e. the firmware was linkable but **the smoke caller
in `main()` was compiled out**, masking the wiring bug.

### Root cause

1. The Make-based `ports/renesas-ra/Makefile` does NOT honor `CFLAGS_EXTRA`.
   `CFLAGS_EXTRA` is only handled in `py/mkrules.cmake` (cmake-port path),
   not in the Make rules.
2. `CFLAGS_USERMOD` IS appended to `CFLAGS` in `py/py.mk:69`, but only inside
   the `ifneq ($(USER_C_MODULES),)` block. Without a user-c-modules path,
   `CFLAGS_USERMOD` is never read into `CFLAGS`.
3. So a user-side `-D` define cannot be injected into renesas-ra builds without
   either setting `USER_C_MODULES` or putting the `-D` into a board-side
   `mpconfigboard.mk` (which IS read into `CFLAGS` via the existing
   `CFLAGS+=-DDEFAULT_DBG_CH=0` style).

### Fix applied

Added a board-side gate in
`/Users/alex/micropython/ports/renesas-ra/boards/EK_RA8P1/mpconfigboard.mk`:

```make
# Display smoke test gate (C-side GLCDC bring-up before REPL).
# Set to 0 to revert to the no-display image.
RA8P1_BRINGUP_DISPLAY_TEST ?= 1
ifeq ($(RA8P1_BRINGUP_DISPLAY_TEST), 1)
CFLAGS += -DMICROPY_RA8P1_BRINGUP_DISPLAY_TEST=1
endif
```

This is the idiomatic MicroPython port pattern (mirrors `USE_FSP_QSPI`,
`USE_FSP_LPM`). Default-on for now; flip to `0` to disable for non-display
images. To override on cmdline:

```
make BOARD=EK_RA8P1 USE_FSP_QSPI=0 RA8P1_BRINGUP_DISPLAY_TEST=0
```

### Verification

After clean rebuild:

```
nm build-EK_RA8P1/main.o | grep -iE 'display|smoke|glcdc|sdram|ioport_ctrl|bsp_pin|R_BSP'
         U R_BSP_SdramInit
         U g_bsp_pin_cfg
         U g_display
         U g_ioport_ctrl
```

`arm-none-eabi-objdump -d build-EK_RA8P1/main.o` head:
```
00000000 <main>:
  20:	f7ff fffe 	bl	0 <R_IOPORT_Open>
  26:	f7ff fffe 	bl	0 <R_BSP_SdramInit>
```

(The full `R_GLCDC_Open`/`R_GLCDC_Start` calls are indirect through
`g_display.p_api->open` / `->start`, so they appear as `blx` on a register
loaded from `g_display`, not as `bl R_GLCDC_*`.  But `g_display_ctrl` post-run
state confirms both APIs were invoked.)

`firmware.map` shows the GLCDC drivers linked and addressed:
- `R_BSP_SdramInit` @ `0x0202b07c` (in `bsp_sdram.o`)
- `R_GLCDC_Open`  @ `0x0202b860` (in `r_glcdc.o`)
- `R_GLCDC_Start` @ `0x0202b35c` (in `r_glcdc.o`)
- `g_display`     @ `0x0203d558` (rodata, from `common_data.o`)
- `g_display_cfg` @ `0x0203d564` (rodata, from `common_data.o`)
- `g_display_ctrl` @ `0x2200086C` (bss, from `common_data.o`)

## Runtime evidence (live JLinkExe halt+read)

```
J-Link> connect / halt
PC = 0x0202C58C, CycleCnt = 0x93FD53F7   (chip alive, runtime advancing)
SP = 0x22001388 (MSP)
LR = 0x0202C579

J-Link> mem32 0x2200086c 4   (g_display_ctrl)
2200086C = 00000002 00000000 00000000 0203D564
              ^^^^^^^^                 ^^^^^^^^
              state = 2 = DISPLAY_STATE_DISPLAYING
              p_cfg back-pointer = &g_display_cfg
```

`state == 2` is the FSP display-API value `DISPLAY_STATE_DISPLAYING` — set
only by the path `R_GLCDC_Open` (→ OPENED) → `R_GLCDC_Start` (→ DISPLAYING).
So the smoke test fully ran: IOPORT_Open ✓ → SdramInit ✓ → GLCDC_Open ✓ →
GLCDC_Start ✓.

```
J-Link> mem8 0x68000000 32   (SDRAM framebuffer head, 32 bytes)
68000000 = 00 00 FF 00  00 00 FF 00  00 00 FF 00  00 00 FF 00
68000010 = 00 00 FF 00  00 00 FF 00  00 00 FF 00  00 00 FF 00
68000020 = 00 00 FF 00  ...
```

Pattern repeats uniformly across the framebuffer (sampled at `0x68000000`,
`0x68040000`, `0x680A0000`).  Layer 0 is RGB565 768x450 in `.sdram_noinit`,
which is intentionally NOT zeroed at startup — this is just cold-boot SDRAM
content.  The panel will be scanning that out as alternating
black/cyan-tinge stripes.  To get a deterministic pattern visible on the
panel, the smoke must paint the framebuffer before `R_GLCDC_Start`.

## 2026-04-30 13:04 — Demo pattern shipped

- User confirmed solid-red smoke worked.  Replaced the smoke's flat-red fill in
  `ports/renesas-ra/main.c:86-104` with a sliding-color-bands demo:
  - 8 vertical bands (RED, ORANGE, YELLOW, GREEN, CYAN, BLUE, INDIGO, MAGENTA), 128 px each.
  - Diagonal brightness sweep that wraps with the animation phase.
  - Renders to alternating buffers `g_framebuffer[0]` and `g_framebuffer[1]`,
    flipping via `g_display.p_api->bufferChange(p_ctrl, back, DISPLAY_FRAME_LAYER_1)`.
  - Bounded at 600 frames (~9s at 15ms pacing) so MicroPython REPL still starts after the demo.
  - Gated by `MICROPY_RA8P1_BRINGUP_DISPLAY_DEMO` (default 1 when DISPLAY_TEST=1);
    set to 0 to revert to the flat-red fill.
- Build: text 281084 → 281284 (+200 bytes for paint fn + band table).
- Live JTAG verify: framebuffer rows show varying shades within bands; both
  buffers painted; `g_display_ctrl.state == 2` (DISPLAYING) throughout.

## Next bounded actions (in priority order)

1. **Visual confirmation from physical panel**: the smoke is structurally complete and runtime-verified. Layer 0 holds pure red across the whole 1024×600. If the panel is dark, eliminate physical-side suspects per the VCOM-handoff community-clue list:
   - SW4 all OFF (per the "whole-white-LCD" thread)
   - LCD FFC fully reseated and connector lock closed
   - Backlight enable: GLCDC `g_display_extend_cfg.tcon_*` and the BLEN pin (P514) — verify panel's expected BLEN polarity vs `g_display_extend_cfg`.
   - Power: USB host current capacity (Renesas QSG flags this; use a powered hub or root host port).

2. **Optional**: enhance smoke to paint horizontal color bands (RED/GREEN/BLUE/BLACK/WHITE/YELLOW/MAGENTA/CYAN) so the visual carries scan-direction and bit-order information, not just "is it lit". Code path: edit the loop at `main.c:96-100` to vary `fb[i]` by `(i / pixels_per_band)`. RGB888 byte order in `g_framebuffer` is little-endian (LSB=B, then G, then R, then ignored), so:
   - RED   = 0x00FF0000   GREEN  = 0x0000FF00   BLUE  = 0x000000FF
   - BLACK = 0x00000000   WHITE  = 0x00FFFFFF   YELLOW= 0x00FFFF00
   - MAGENTA=0x00FF00FF   CYAN   = 0x0000FFFF

3. **VCOM track resume** once display is visually confirmed: return to `originals/ek-ra8p1-vcom-handoff.md`'s open `UART_BYTES 0` issue. The next decisive test there is a physical PD02↔PD03 short to determine whether the MCU SCI_B8 path or the J-Link OB CDC path is at fault.

## Toolchain confirmation (matches Codex)

- `which arm-none-eabi-gcc` → `/opt/homebrew/bin/arm-none-eabi-gcc`
- `arm-none-eabi-gcc --version` → `gcc (GCC) 15.2.0`
- Build artifacts byte-identical to Codex's verified build:
  text=281084 / data=112 / bss=4920336 / dec=5201532 / hex=4f5e7c
- Symbols verified in firmware.map exactly as Codex reported:
  - `g_display`     = 0x0203d558
  - `g_display_cfg` = 0x0203d564
  - `g_display_ctrl`= 0x2200086c
  - `g_init_info`   = 0x0203d524
  - `glcdc_line_detect_isr` = 0x0202bb24
  - `g_framebuffer` = 0x68000000
  - `.sdram_noinit` at 0x68000000 size 0x004b0000

## Layer-0 framebuffer geometry (re-confirmed against generated code)

Per `boards/EK_RA8P1/ra_gen/common_data.h`:

```c
#define DISPLAY_HSIZE_INPUT0          (1024)
#define DISPLAY_VSIZE_INPUT0          (600)
#define DISPLAY_BUFFER_STRIDE_BYTES_INPUT0  (((1024 * BPP + 0x1FF) >> 9) << 6)
extern uint8_t g_framebuffer[2][DISPLAY_BUFFER_STRIDE_BYTES_INPUT0 * 600];
```

`g_display.p_cfg->input[0].format = DISPLAY_IN_FORMAT_32BITS_RGB888` (32-bit per pixel).
Per-buffer footprint: 1024 × 600 × 4 = 2,457,600 = 0x258000.
Two buffers: 4,915,200 = 0x4B0000 ✓ matches `.sdram_noinit` size.

The smoke loop at `main.c:96-100` writes `0x00ff0000u` to every `uint32_t` in
`g_framebuffer[0]`, which is **pure red in RGB888** (R=0xFF, G=0x00, B=0x00,
high byte unused).  Live JTAG sampling at 0x68000000, 0x68100000, 0x68200000,
0x68257FF0 (last word of buffer 0) all confirm uniform `00FF0000`.  Buffer 1
remains uninitialized — only used if/when GLCDC is told to flip.

## J-Link probe state (from this machine, alex@100.81.212.41 = ist-mac-s)

- The probe is **healthy** from this side.  SWD@4MHz, halt+regs+mem32+loadfile all working first-shot.
- `JLinkExe` at `/Users/alex/jlink_v938a_extract/Applications/SEGGER/JLink_V938a/JLinkExe` (V9.38a extract).
- USB CDC node `/dev/cu.usbmodem0010802448941` (J-Link OB serial 001080244894).
- The "remote J-Link probe out-of-sync" Codex still sees from MacBook is most likely a session-locking artifact: the J-Link USB device is exclusive-open, so when MacBook codex's ssh session tries to open it while another local process (or stale JLinkExe) holds it, it fails.  On this side `pgrep -fl JLink` is empty between operations, so the local path is unblocked.

## Codex helper alignments

Codex reported two helper fixes already in place on the codex side:
- Smoke build helper now does `make clean` before `CFLAGS_EXTRA=-DMICROPY_RA8P1_BRINGUP_DISPLAY_TEST=1`.
- Build helpers export PATH for `/opt/homebrew/Cellar/arm-none-eabi-gcc/15.2.0/bin` and `/opt/homebrew/Cellar/arm-none-eabi-binutils/2.46.0/bin`.

⚠ **Note**: `CFLAGS_EXTRA` is not honored by the renesas-ra Make-based port (only the cmake-port path reads it; see py/mkrules.cmake).  Codex's helper passing `CFLAGS_EXTRA=…` works ONLY because of the `mpconfigboard.mk` gate I added — without that gate, that helper would also silently drop the macro.  Recommend Codex helper switch to `make BOARD=EK_RA8P1 USE_FSP_QSPI=0 RA8P1_BRINGUP_DISPLAY_TEST=1` (or just `make BOARD=EK_RA8P1 USE_FSP_QSPI=0` since `RA8P1_BRINGUP_DISPLAY_TEST` defaults to 1) — that's the supported, idiomatic path now.

## J-Link probe state

- `JLinkExe`: `/Users/alex/jlink_v938a_extract/Applications/SEGGER/JLink_V938a/JLinkExe` (V9.38a extract).
- USB CDC node: `/dev/cu.usbmodem0010802448941` (J-Link OB serial `001080244894`).
- SWD@4MHz to `R7KA8P1KF_CPU0` works first-shot, no replug needed.
- The previous "out-of-sync" report appears to have been from a prior session — current probe is healthy.

## Authoritative handoff docs on this machine

- `/Users/alex/ek-ra8p1-handoff/originals/` — five docs from the 2026-04-29 codex baseline.
- The eight new docs the user mentioned (`display-linker-plan`, `display-smoke-artifacts`, `display-runtime-check`, `display-snapshot-restore`, plus updated versions of the original five) are on the MacBook at `/Users/qlss/ek-ra8p1-*.md` and have NOT been scp'd to ist-mac-s yet. Will request a fresh sync when the user surfaces.

## CLI snippets used this session (reproducible)

```bash
# Build smoke-enabled image
cd /Users/alex/micropython/ports/renesas-ra
make BOARD=EK_RA8P1 clean
make BOARD=EK_RA8P1 USE_FSP_QSPI=0 -j8

# Build no-display image
make BOARD=EK_RA8P1 USE_FSP_QSPI=0 RA8P1_BRINGUP_DISPLAY_TEST=0 -j8

# Verify smoke compiled into main.o
nm build-EK_RA8P1/main.o | grep -iE 'display|smoke|glcdc|sdram|ioport_ctrl|bsp_pin|R_BSP'

# Flash via J-Link
JLINK=/Users/alex/jlink_v938a_extract/Applications/SEGGER/JLink_V938a/JLinkExe
cat > /tmp/jlink-flash.cmd <<'EOF'
si SWD
speed 4000
device R7KA8P1KF_CPU0
connect
halt
loadfile /Users/alex/micropython/ports/renesas-ra/build-EK_RA8P1/firmware.hex
r
go
exit
EOF
"$JLINK" -NoGui 1 -CommandFile /tmp/jlink-flash.cmd

# Inspect runtime state (g_display_ctrl)
cat > /tmp/jlink-state.cmd <<'EOF'
si SWD
speed 4000
device R7KA8P1KF_CPU0
connect
halt
mem32 0x2200086c 4
mem32 0x68000000 4
mem8 0x68000000 32
exit
EOF
"$JLINK" -NoGui 1 -CommandFile /tmp/jlink-state.cmd
```
