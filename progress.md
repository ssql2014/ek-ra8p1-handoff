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

## 2026-06-05 Ethernet official EP bring-up

- Flashed and ran the official FSP 6.4.0 EK-RA8P1 Ethernet FreeRTOS+TCP example:
  `/Users/alex/ra-fsp-examples/example_projects/ek_ra8p1/ethernet/ethernet_ek_ra8p1_ep/e2studio/ethernet_ek_ra8p1_ep.hex`.
- RTT block address used: `0x220011ac`.
- Runtime RTT output reaches the example banner and keeps printing `Network is Down...`.
- The sample source returns `Network is Down` before checking PHY link when DHCP has not yet offered an address, so RTT alone was ambiguous.
- Added `/Users/alex/ra8p1-jlink-ethernet-phy-diag.cmd` and ran it through tmux session `ra8p1-device:device`.
- J-Link register evidence from the running official hex:
  - `R_ETHA0->EAMS = 0x00000001`: ETHA0 disabled mode.
  - `R_ETHA1->EAMS = 0x00000003`: ETHA1 operation mode.
  - `R_RMAC1->MPSM` after Clause 22 PHY address 0, register 1 reads: `0x79494100`.
  - Decoded PHY BMSR: `0x7949`; link status bit 2 is clear, auto-negotiation-complete bit 5 is clear.
- Conclusion: RMAC1/MDIO is alive and the official driver has selected the expected RA8P1 RGMII1 path, but the GPY111 PHY reports no physical Ethernet link. This is not currently a MicroPython/FSP software-driver failure.
- Next physical checks:
  - RJ45 cable must be connected to a live Ethernet switch/router port, not just USB.
  - Confirm the RJ45 link/activity LED on the EK-RA8P1 Ethernet connector lights or blinks.
  - Try a known-good cable and a known-good DHCP router/switch port.
  - If the LED stays dark with known-good network gear, inspect board Ethernet E-point/solder-link continuity for the RGMII1 path referenced by the official pin comments (`E18`-`E24`, `E33`, `E34`, `E36`, `E37`, `E38`).

## 2026-06-05 CEU official EP bring-up

- Flashed and ran the official FSP 6.4.0 EK-RA8P1 CEU example:
  `/Users/alex/ra-fsp-examples/example_projects/ek_ra8p1/ceu/ceu_ek_ra8p1_ep/e2studio/ceu_ek_ra8p1_ep.hex`.
- RTT block address used: `0x22000870`.
- Required board-side settings from the official readme:
  - OV5640 camera module on Camera Expansion Port `J35`.
  - `J41` open to use `P405`/`P406` for parallel camera.
  - `SW4-1` OFF, `SW4-2` OFF, `SW4-3` OFF, `SW4-4` OFF, `SW4-5` OFF, `SW4-6` ON, `SW4-7` OFF, `SW4-8` OFF.
- Runtime result:
  - The example reaches the CEU menu, so GPT, I2C master open, and `camera_open()` all completed.
  - SRAM/VGA path: selected `2`, printed `CEU Capture Successful !`, then `Image data matches color bars to accuracy ratio: 0.00%` and trapped with `ceu_check_image FAILED`, error code `0x25`.
  - SDRAM/SXGA path: selected `1`, printed `CEU Capture Successful !`, then the same `0.00%` color-bar check failure and error code `0x25`.
- J-Link buffer evidence:
  - `g_image_vga_sram` from the launch file is `0x22001148`; samples show non-zero image data such as `FC00FC00`, `D800D800`, and `98FC98FC`.
  - `g_image_sxga_sdram` from the launch file is `0x68000000`; samples show non-zero image data such as `FC00FC00`, `00100010`, and `10101010`.
- Conclusion: the original CEU driver path is not dead; both SRAM and SDRAM captures complete and write buffers. The remaining issue is that the captured data does not match the example's expected OV5640 test-pattern color bar. Next checks are physical/format oriented: verify `J41` is open, `SW4-6` is ON, the OV5640 FFC orientation/lock at `J35`, and whether the sensor is outputting the expected test pattern and YCbCr byte order.

## 2026-06-05 MIPI-CSI official EP bring-up

- Flashed and ran the official FSP 6.4.0 EK-RA8P1 MIPI-CSI example:
  `/Users/alex/ra-fsp-examples/example_projects/ek_ra8p1/mipi_csi/mipi_csi_ek_ra8p1_ep/e2studio/mipi_csi_ek_ra8p1_ep.hex`.
- Console path used: J-Link OB VCOM `/dev/cu.usbmodem0010802448941`, 115200 8N1, via tmux pane `ra8p1-device:device`.
- The example booted to the VCOM menu after reset/go from a second tmux J-Link pane.
- Runtime result:
  - Selected QVGA (`3`), then camera test pattern (`2`).
  - Output: `Image data matches color bars to accuracy ratio: 100.00%`.
  - Selected live camera (`1`).
  - Output: `Live camera streaming started`.
- J-Link buffer evidence from the running example:
  - Sampled `vin_image_buffer_1` at `0x68258000` and `0x68259000`.
  - Sampled additional VIN/launch-file image regions at `0x68384000` and `0x684B0000`.
  - The sampled SDRAM words are non-zero and change-patterned, for example `00000020` and `00200000`, while the core was halted in thread mode (`IPSR = 000`), not a fault.
- Conclusion: the original MIPI-CSI + VIN + SDRAM driver path is validated on the board for both sensor test-pattern mode and live-camera start. This is currently the cleanest camera path to port into MicroPython.

## 2026-06-05 MicroPython MIPI-CSI SW4-all-OFF bring-up log

- Board state from user: all `SW4` positions OFF. Per Changhao, `SW4-6 ON` selects MIPI-DSI and `SW4-6 OFF` selects CSI; software can also drive `MIPI_SEL` through PI4IOE5V6408 at I2C address `0x43`.
- Official CSI source check:
  - `mipi_csi.c` calls `set_switch_state(MIPI_SEL_PIN, HIGH_STATE)`.
  - `switch_init.h` defines switch address `0x43`, registers `PIN_DIR_REG 0x03`, `OUTPUT_STATE_REG 0x05`, `OUTPUT_ENABLE_REG 0x07`, and MIPI select pin 6.
  - Conclusion: MicroPython should drive U15 pin 6 high for CSI when SW4 is all OFF.
- Official CSI binary retest with SW4 all OFF:
  - Flashed `/Users/alex/ra-fsp-examples/example_projects/ek_ra8p1/mipi_csi/mipi_csi_ek_ra8p1_ep/e2studio/mipi_csi_ek_ra8p1_ep.hex`.
  - Serial script `/Users/alex/ra8p1-official-mipi-csi-serial.py` reported `Image data matches color bars` and `[serial] OFFICIAL_MIPI_CSI_PASS`.
  - Conclusion: the board, camera, and SW4-all-OFF plus software switch path are good.
- MicroPython no-readback CSI build with software CSI select:
  - Build path: `/Users/alex/micropython/ports/renesas-ra/build-EK_RA8P1-mipi-csi-fullclocks`.
  - U15 after software select: `DIR=0x20 OUT=0x20 OE=0xdf`.
  - Initial runtime clock evidence was bad: `system_core_clock=8000000`, `clock_pclkd_hz=8000000`, `gpt_cfg_period_counts=10`.
  - Conclusion: that image was effectively using 8 MHz startup clocks, so CAM_XCLK was about 800 kHz and CSI lane activity was expected to fail.
- Clean full-clock MicroPython build:
  - Build command used a fresh directory:
    `make -C /Users/alex/micropython/ports/renesas-ra BOARD=EK_RA8P1 BUILD=build-EK_RA8P1-mipi-csi-fullclocks2 RA8P1_BRINGUP_MIPI_CSI_TEST=1 RA8P1_BRINGUP_MIPI_CSI_BOOT_PROBE=1 RA8P1_CSI_USE_FSP_IIC=1 RA8P1_SAFE_BOOT_CLOCKS=1 RA8P1_SAFE_BOOT_SDRAM=1 RA8P1_SAFE_BOOT_SDRAM_HEAP=0 RA8P1_CSI_MIPI_SEL_STATE=1 RA8P1_CSI_VERIFY_CAMERA_WRITES=0 -j4`.
  - ELF verification showed `SystemInit_MicroPythonSafeBoot()` calling `bsp_clock_init()` and `SystemCoreClockUpdate()`.
  - Flashed `/Users/alex/micropython/ports/renesas-ra/build-EK_RA8P1-mipi-csi-fullclocks2/firmware.bin` through tmux pane `%1`; J-Link reported `O.K.`.
  - Runtime clock evidence improved: `system_core_clock=1000000000`, `clock_pclkd_hz=250000000`, `clock_pclka_hz=125000000`, `clock_gptclk_hz=250000000`.
  - Conclusion: do not reuse the older `build-EK_RA8P1-mipi-csi-fullclocks` directory when changing safe-boot clock flags; use a clean build dir or force startup/system object rebuild.
- I2C/camera failure after full-clock boot:
  - U15 remained correct: `switch_read(3/5/7) -> 0x20 0x20 0xdf`.
  - Bitbang probe showed `0x43` ACK, but `0x3c` and `0x78` did not ACK.
  - FSP camera reads returned `-0x12c`; status showed `last_i2c_err=300`, backend `3` (FSP IIC), and `p709_pfs=0xc04`.
  - Decoding `p709_pfs=0xc04`: output, drive high, output LOW. OV5640 was being held in reset/powerdown.
  - Manual verification in RTT REPL:
    `from machine import Pin; Pin("P709", Pin.OUT).value(1)`.
  - After forcing P709 high, `i2c_probe(0x3c)=True` and `camera_read(0x300a/0x300b) -> 0x56 0x40`.
  - Conclusion: current MicroPython CSI root cause is P709 being left low after boot/init, not SW4, U15, camera address, or the I2C bus.
- Next source fix:
  - Ensure the MicroPython CSI path leaves `BSP_IO_PORT_07_PIN_09` high after board/pin initialization and after camera reset.
  - Rebuild and retest `c.start_probe_select(True)` before changing CSI/VIN configuration further.
- Repo hygiene note:
  - `boards/EK_RA8P1/configuration.xml` currently does not fully match generated `ra_gen/bsp_clock_cfg.h` for the CSI clock tree. Before commit, align the XML with the generated clock config or regenerate both together.
- P709-high source fix retest:
  - Source change: leave `BSP_IO_PORT_07_PIN_09` high in the MicroPython CSI pin path and generated EK_RA8P1 pin data, and record `p709_level` in `ra8p1_mipi_csi.status()`.
  - Build command:
    `make -C /Users/alex/micropython/ports/renesas-ra BOARD=EK_RA8P1 BUILD=build-EK_RA8P1-mipi-csi-p709fix RA8P1_BRINGUP_MIPI_CSI_TEST=1 RA8P1_BRINGUP_MIPI_CSI_BOOT_PROBE=1 RA8P1_CSI_USE_FSP_IIC=1 RA8P1_SAFE_BOOT_CLOCKS=1 RA8P1_SAFE_BOOT_SDRAM=1 RA8P1_SAFE_BOOT_SDRAM_HEAP=0 RA8P1_CSI_MIPI_SEL_STATE=1 RA8P1_CSI_VERIFY_CAMERA_WRITES=1 -j4`.
  - Flashed `/Users/alex/micropython/ports/renesas-ra/build-EK_RA8P1-mipi-csi-p709fix/firmware.bin` through tmux pane `%1`; J-Link reported `O.K.`.
  - Runtime proof:
    - `system_core_clock=1000000000`, `clock_pclkd_hz=250000000`, `clock_pclka_hz=125000000`, `clock_gptclk_hz=250000000`.
    - `p709_pfs=0xc07`, `p709_level=1`.
    - U15 switch registers remain CSI-selected: `switch_read(3/5/7) -> 0x20 0x20 0xdf`.
    - `i2c_probe(0x43)=True`, `i2c_probe(0x3c)=True`, `camera_read(0x300a/0x300b) -> 0x56 0x40`.
    - Camera table verification passed: `camera_writes=172`, `camera_readbacks=172`, `camera_mismatch_reg=0`, `last_camera_err=0`.
  - CSI/VIN result after boot probe and a manual `c.start_probe_select(True)`:
    - `phase=41`, `err=0`, `probe_runs=2`.
    - `csi_rxst=0`, `csi_dlst0=0`, `csi_dlst1=0`, `csi_vcst0=0`, `csi_gsst=0`.
    - `vin_lc=0`, `vin_callbacks=0`, `csi_callbacks=0`, while `vin_ms_or=0x18001c`.
  - Conclusion: the P709/I2C/camera-programming blocker is fixed. Do not repeat SW4/U15/I2C ACK debugging for this state. The remaining MicroPython CSI blocker is no MIPI lane/VIN activity after the camera is configured and streaming.
  - Next checks: compare MicroPython MIPI PHY, CSI, VIN, IRQ/vector, and CAM_XCLK configuration against the official passing CSI example; also align `configuration.xml` with generated clock/pin data before committing.

## 2026-06-05 Ethernet link retest after physical replug/check

- Reflashed and restarted the official Ethernet example through tmux pane `%1`.
- Waited for the example to initialize, then reran `/Users/alex/ra8p1-jlink-ethernet-phy-diag.cmd`.
- Result is unchanged:
  - `R_ETHA0->EAMS = 0x00000001`.
  - `R_ETHA1->EAMS = 0x00000003`.
  - `R_RMAC1->MPSM = 0x79494100`.
  - Decoded PHY BMSR remains `0x7949`: link-status bit 2 is clear and auto-negotiation-complete bit 5 is clear.
- Conclusion: Ethernet is still blocked on physical link. Keep using RMAC1/GPY111 as the software path; do not spend more software time here until the RJ45 link/activity LED and a live switch/router connection are confirmed.

## 2026-06-06 MicroPython CSI display-stripe observation

- User observed that the LCD currently shows stripes.
- Current firmware path checked through tmux pane `%2`, not by changing board state:
  - MicroPython REPL is alive and `import ra8p1_mipi_csi as c` works.
  - `system_core_clock=1000000000`, `clock_pclkd_hz=250000000`, `clock_pclka_hz=125000000`, `clock_gptclk_hz=250000000`.
  - `p709_level=1`, `U15` remains CSI-selected from prior run (`DIR=0x20 OUT=0x20 OE=0xdf`), and previous camera programming/readback evidence is still good.
  - Read-only `c.status()` / `c.last_probe()` still show no active capture path: `csi_rxst=0`, `csi_dlst0=0`, `csi_dlst1=0`, `csi_vcst0=0`, `vin_lc=0`, `vin_callbacks=0`, `csi_callbacks=0`, `active_samples=0`.
- Source/config fact relevant to the observation:
  - `vin_image_buffer_1/2/3` and `g_framebuffer` are placed in `.sdram_noinit`, so visible LCD stripes can be stale SDRAM/framebuffer content or uninitialized GLCDC output.
- Conclusion:
  - The visible stripes are not yet proof that MicroPython MIPI-CSI/VIN is receiving frames.
  - Do not treat this as a CSI success unless it coincides with non-zero CSI lane/VC status or VIN line/callback activity.
- Next checks:
  - Add or use a controlled framebuffer/VIN-buffer clear/fill test to distinguish stale display memory from live capture.
  - Continue the official-passing versus MicroPython register comparison for MIPI PHY, CSI, VIN, GPT/XCLK, and GLCDC framebuffer source.

### Controlled GLCDC framebuffer fill

- Symbol lookup from current `build-EK_RA8P1-mipi-csi-csicfg1/firmware.elf`:
  - `g_framebuffer = 0x68000000`.
  - `vin_image_buffer_3 = 0x68258000`, `vin_image_buffer_2 = 0x68384000`, `vin_image_buffer_1 = 0x684b0000`.
- Through tmux pane `%2`, ran a MicroPython-only SDRAM write:
  - `base = 0x68000000`
  - `words = 1024 * 80`
  - `machine.mem32[base + i * 4] = 0x0000ff00`
  - REPL confirmed `FB_FILL_TOP80_GREEN_DONE 0x68000000 81920`.
- Awaiting visual observation:
  - If the LCD top area changes to a green band, the visible stripes are GLCDC framebuffer content and not proof of live CSI.
  - If the LCD does not change, GLCDC may not be reading `g_framebuffer` in the current state, or the observed stripes may be coming from another panel/DSI state.

## 2026-06-06 MicroPython CEU source bring-up

- Priority changed to CEU first. CEU here is the RA Capture Engine Unit for parallel/DVP camera capture, not the MIPI CSI path.
- Hardware requirements from the official EK-RA8P1 CEU example:
  - `J35`: OV5640 camera FFC installed and locked.
  - `J41`: both shunts removed/open so `P405/P406` are not routed to the audio codec.
  - `SW4`: `SW4-6 ON`, and `SW4-1/2/3/4/5/7/8 OFF`.
  - `SW4-7` is `USBFS_ROLE`, not CEU camera routing, so keep it OFF for this CEU setup.
- Source now lands in the MicroPython repo instead of only transient REPL state:
  - Added CEU build gate `RA8P1_BRINGUP_CEU_TEST=1`.
  - Added CEU FSP config header `ports/renesas-ra/boards/EK_RA8P1/ra_cfg/fsp_cfg/r_ceu_cfg.h`.
  - Added gated CEU IRQ/vector entries for `EVENT_CEU_CEUI` / `ceu_isr`.
  - Added `ports/renesas-ra/ra8p1_ceu.c` with a `ra8p1_ceu` module exposing `init()`, `status()`, `capture()`, `buffer()`, `i2c_probe()`, `camera_id()`, `camera_read()`, `camera_write()`, `camera_open()`, and `test_pattern()`.
  - The module locally muxes DVP pins for CEU only under the CEU gate: `P400/P902/P405/P406/P700/P701/P702/P703/PB02/PB03/PB04`, drives `P501` as GPT12 camera XCLK, uses bitbang I2C on `P511/P512`, and leaves `P709` high for camera reset release.
- Build command:
  `make -C /Users/alex/micropython/ports/renesas-ra BOARD=EK_RA8P1 RA8P1_BRINGUP_CEU_TEST=1 -j8`
- Build result:
  - Success.
  - Firmware outputs: `/Users/alex/micropython/ports/renesas-ra/build-EK_RA8P1/firmware.bin`, `.hex`, `.elf`.
  - ELF size summary: `text=302760`, `data=492`, `bss=5536816`.
- Next board test:
  - Do not flash/test this CEU firmware until the board is in the CEU hardware state above, especially `SW4-6 ON` and `J41` open.
  - First runtime success criteria should be `ra8p1_ceu.capture()` returning `capture_ready=1`, non-zero callback/event evidence, and non-zero buffer sample data. Do not require the official color-bar match yet; the prior official CEU example already captured non-zero buffers but failed its strict color-bar comparison.

### CEU full-clock runtime retest

- Initial CEU flash/runtime after the first build exposed the same safe-boot clock trap seen during CSI work:
  - `_SEGGER_RTT` moved from the old hardcoded `0x220014d8` to `0x22001564`; RTT input did not work until `%2` was restarted with `RTT_BLOCK_ADDR=0x22001564`.
  - `import ra8p1_ceu as ceu` worked.
  - `ceu.init()` returned normally.
  - `ceu.i2c_probe()` returned `True`.
  - `ceu.camera_id()` returned `(86, 64)` (`0x56 0x40`).
  - `ceu.status()` showed `system_core_clock=8000000`, `clock_pclkd_hz=8000000`, `clock_gptclk_hz=0`; this image was not suitable for capture testing.
- Source fixes made after that finding:
  - `ports/renesas-ra/Makefile`: RA8P1 `startup.o` and `system.o` now receive explicit `MICROPY_RA8P1_SAFE_BOOT*` target-specific flags so command-line safe-boot clock settings reach `SystemInit_MicroPythonSafeBoot()`.
  - `ports/renesas-ra/ra8p1_ceu.c`: `clock_gptclk_hz` status now handles `BSP_CLOCKS_SOURCE_CLOCK_PLL2P`.
- Clean full-clock CEU build:
  - Build command:
    `make -C /Users/alex/micropython/ports/renesas-ra BOARD=EK_RA8P1 BUILD=build-EK_RA8P1-ceu-fullclocks RA8P1_BRINGUP_CEU_TEST=1 RA8P1_SAFE_BOOT_CLOCKS=1 RA8P1_SAFE_BOOT_SDRAM=1 RA8P1_SAFE_BOOT_SDRAM_HEAP=0 -j8`
  - Build result: success; `build-EK_RA8P1-ceu-fullclocks/firmware.bin`, `.hex`, `.elf`.
  - Static ELF verification:
    - `_SEGGER_RTT = 0x22001564`.
    - `SystemInit_MicroPythonSafeBoot()` calls `bsp_clock_init()` and `SystemCoreClockUpdate()`.
  - Flashed `/Users/alex/micropython/ports/renesas-ra/build-EK_RA8P1-ceu-fullclocks/firmware.bin` through tmux pane `%1`; J-Link reported compare/erase/program/verify complete and `O.K.`.
- Runtime proof after full-clock flash, through tmux pane `%2`:
  - RTT restarted with `RTT_BLOCK_ADDR=0x22001564`.
  - `ceu.init()` returned normally.
  - `system_core_clock=1000000000`, `clock_pclkd_hz=250000000`, `clock_gptclk_hz=300000000`.
  - `last_pin_err=0`, `last_gpt_open_err=0`, `last_gpt_start_err=0`, `last_i2c_err=0`, `last_camera_err=0`, `last_ceu_open_err=0`.
  - `p501_level=0`, `p709_level=1`, `i2c_scl=1`, `i2c_sda=1`.
  - `ceu.camera_id()` still returned `(86, 64)` (`0x56 0x40`) at full clocks.
- Current blocker before capture:
  - User previously set all `SW4` positions OFF for CSI/MIPI testing.
  - CEU capture must not be interpreted until board routing is set to CEU: `SW4-6 ON`, all other `SW4` positions OFF, and `J41` remains open/removed.

### CEU MicroPython DVP signal retest after hardware adjustment

- User reported the CEU hardware adjustment is done.
- Reused the current MicroPython CEU image through tmux pane `%2`:
  - Firmware: `/Users/alex/micropython/ports/renesas-ra/build-EK_RA8P1-ceu-fullclocks/firmware.bin`.
  - RTT block: `0x22001568`.
  - `ceu.deinit()` then `ceu.init()` returned normally.
- Runtime proof:
  - `ceu.camera_id()` returned `(86, 64)` (`0x56 0x40`).
  - `xclk_actual_hz=25000000`.
  - `p501_level=1`, `p709_level=1`.
  - `ceu.sample_pins(100000)` still showed no DVP input activity:
    - `pclk=(0, 0, 0, 251724800)`.
    - `hsync=(0, 0, 0, 251724800)`.
    - `vsync=(0, 0, 0, 251724800)`.
    - `d0=(0, 0, 0, 251724800)`.
    - `d7=(0, 0, 0, 251724800)`.
- Interpretation:
  - I2C, OV5640 identity, XCLK, and reset-release are alive.
  - The CEU pins are muxed (`0x0f010400`) but the MCU still observes PCLK/HSYNC/VSYNC/data lines low with no edges.
  - Do not spend more time on CEU IRQ/callback tuning until the physical DVP route is proven or disproven.
- Next discriminator:
  - Flash the official Renesas CEU hex `/Users/alex/ra-fsp-examples/example_projects/ek_ra8p1/ceu/ceu_ek_ra8p1_ep/e2studio/ceu_ek_ra8p1_ep.hex` and use RTT block `0x22000870`.
  - If official CEU also cannot capture, treat this as board routing/camera connector/switch state.
  - If official CEU captures, compare its generated pin/clock/IIC/camera/CEU runtime against `ra8p1_ceu.c`.

### Official Renesas CEU hex retest

- Stopped MicroPython RTT in tmux pane `%2` with `Ctrl-]`.
- Flashed official CEU hex through tmux pane `%1`:
  - J-Link command: `/Users/alex/jlink_v938a_extract/Applications/SEGGER/JLink_V938a/JLinkExe -CommanderScript /Users/alex/ra8p1-jlink-official-ceu.cmd`.
  - Script: `/Users/alex/ra8p1-jlink-official-ceu.cmd`.
  - Hex: `/Users/alex/ra-fsp-examples/example_projects/ek_ra8p1/ceu/ceu_ek_ra8p1_ep/e2studio/ceu_ek_ra8p1_ep.hex`.
  - Result: J-Link reported `O.K.` and `Script processing completed`.
- Started official RTT through tmux pane `%2`:
  - `RTT_BLOCK_ADDR=0x22000870 /opt/homebrew/bin/python3 /Users/alex/ek-ra8p1-handoff/scripts/rtt_terminal.py`.
  - Official banner appeared for `r_ceu Module`, Example Project `1.0`, FSP `6.4.0`.
- Selected `2. SRAM` / VGA 640x480 from the official menu.
- Result:
  - Official app printed `Image Capturing Operation started`.
  - Then failed with `[ERR] In Function: ceu_operation(), ** CEU Callback event not received **`.
  - Returned error code `0x14` (`FSP_ERR_TIMEOUT`).
- Interpretation:
  - Current failure reproduces on the official Renesas CEU hex, so the immediate blocker is not the MicroPython CEU wrapper, CEU IRQ vector wiring, or the MicroPython camera table.
  - Treat current state as a board routing / DVP physical signal problem until proven otherwise.
- Manual check needed now:
  - Verify `SW4-6 ON`, `SW4-1/2/3/4/5/7/8 OFF`.
  - Verify `J41` has both shunts removed/open.
  - Verify the OV5640 FFC is fully inserted and locked in `J35`, with the correct orientation and no partial insertion.
  - If available, scope/logic-analyzer check `PARCAM_PCLK` / `PB04` while the official CEU example is at `Image Capturing Operation started`; PCLK should toggle if the camera DVP output is physically routed.

### Official CEU PFS/PIDR snapshot after timeout

- Added read-only J-Link script `/Users/alex/ra8p1-jlink-ceu-pfs-pidr.cmd`.
- After the official CEU app failed both `2. SRAM/VGA` and `1. SDRAM/SXGA` with `FSP_ERR_TIMEOUT`, stopped RTT and read CEU-related PFS/PIDR registers.
- Relevant PFS readbacks:
  - `P400/D0 = 0x0f010c40`.
  - `P902/D1 = 0x0f010c00`.
  - `P405/D2 = 0x0f010c00`.
  - `P406/D3 = 0x0f010c00`.
  - `P700..P703/D4..D7 = 0x0f010c02, 0x0f010c00, 0x0f010c00, 0x0f010c00`.
  - `PB02/VSYNC = 0x0f010000`.
  - `PB03/HSYNC = 0x0f010000`.
  - `PB04/PCLK = 0x0f010c00`.
  - `P501/CAM_XCLK = 0x03010800`.
  - `P709/CAMERA_RESET = 0x00000407`.
- Port input snapshots:
  - `port4 PCNTR2/PIDR = 0x00007e04`.
  - `port7 PCNTR2/PIDR = 0x0000fed1`.
  - `port9 PCNTR2/PIDR = 0x0000febe`.
  - `port11 PCNTR2/PIDR = 0x00007fe3`.
- Interpretation:
  - The official CEU hex configures the CEU pin functions.
  - `port11 PIDR` has `PB04/PCLK`, `PB03/HSYNC`, and `PB02/VSYNC` all low at the post-timeout snapshot, matching the MicroPython `sample_pins()` no-edge/no-high evidence for the sync/clock lines.
  - The next useful check is still physical routing/switch/FFC or a scope on `PARCAM_PCLK`; this is no longer a MicroPython-only failure.

### CEU U15 software route fix

- Root cause found after comparing the current MicroPython and official CEU timeout against the earlier official CEU success:
  - U15 / `PI4IOE5V6408` at I2C address `0x43` was left in the previous MIPI/CSI software state:
    `DIR=0x20 OUT=0x20 OE=0xdf`.
  - With `OUT bit5 = 1`, MicroPython saw no DVP activity:
    `pclk=(0, 0, 0, 251724800)` and `hsync/vsync/d0..d7` also stayed low.
  - Temporarily forcing `OUT bit5 = 0` through the MicroPython REPL immediately restored `PCLK` activity:
    `PLOW9 pclk=(18396, 8368, 0, 251724802)`.
  - Keeping U15 bit5 low allowed CEU capture to complete:
    `CAPLOW9 0 1 941 16777216 0 3078 1699374853`.
- Interpretation:
  - For CEU / parallel camera routing, U15 bit5 must be driven low.
  - The physical `SW4-6 ON` setting can be overridden by the expander when bit5 is configured as an enabled output, so do not rely on physical SW4 alone after CSI/DSI tests have set U15 to the high MIPI/CSI route.
  - This explains why the official CEU hex succeeded earlier but later timed out: the board-level expander state drifted between tests.
- Source fix landed in `/Users/alex/micropython/ports/renesas-ra/ra8p1_ceu.c`:
  - Added `ra8p1_ceu_switch_select_parallel_camera()`.
  - `ceu.init()` and `ceu.camera_open()` now set U15 bit5 to output low by writing `OUTPUT_STATE_REG &= ~0x20`, `PIN_DIR_REG |= 0x20`, and `OUTPUT_ENABLE_REG &= ~0x20`.
  - `ceu.status()` now exposes `last_switch_err`.
- Rebuild command:
  `make -C /Users/alex/micropython/ports/renesas-ra BOARD=EK_RA8P1 BUILD=build-EK_RA8P1-ceu-fullclocks RA8P1_BRINGUP_CEU_TEST=1 RA8P1_SAFE_BOOT_CLOCKS=1 RA8P1_SAFE_BOOT_SDRAM=1 RA8P1_SAFE_BOOT_SDRAM_HEAP=0 -j8`
- Build result:
  - Success.
  - Size: `text=307052`, `data=492`, `bss=5536840`.
  - New `_SEGGER_RTT = 0x2200156c`.
- Flash/test result through tmux `ra8p1-device`:
  - Flashed `/Users/alex/micropython/ports/renesas-ra/build-EK_RA8P1-ceu-fullclocks/firmware.bin` through pane `%1`; J-Link reported `O.K.`.
  - RTT restarted through pane `%2` with `RTT_BLOCK_ADDR=0x2200156c`.
  - Deliberately recreated the bad route state before init:
    `PREHI10 0 0 0 32 32 223`.
  - New `ceu.init()` corrected the route:
    `POSTSW10 32 0 223 0 0 25000000`
    (`DIR=0x20`, `OUT=0`, `OE=0xdf`, `last_switch_err=0`, `last_camera_err=0`, `xclk_actual_hz=25 MHz`).
  - Final capture succeeded:
    `CAP10 0 1 815 16777216 3079 2969570001 0`
    (`last_capture_start_err=0`, `capture_ready=1`, `callbacks=815`, non-zero buffer sample, `last_switch_err=0`).
  - `ceu.buffer()` returned the expected VGA YUV422 buffer length and readable non-zero data:
    `BUF10 614400 [0, 252, 0, 252, 0, 252, 0, 252, 0, 252, 0, 252, 0, 252, 0, 252]`.
- Current CEU status:
  - MicroPython CEU single-frame capture is now working on the board.
  - Keep U15 bit5 low for CEU/parallel camera. CSI/MIPI tests may need bit5 high again, so the active driver should set it explicitly for its route before touching the camera.

### CEU callback-count cleanup

- Source cleanup:
  - Added `RA8P1_CEU_SWITCH_ROUTE_MASK` so the U15 route bit is not encoded as repeated raw `0x20`/bit-shift expressions.
  - `ceu.capture()` now clears `ra8p1_ceu_callbacks` before each capture, so `status()["callbacks"]` in the returned capture dictionary is per-capture evidence instead of a boot-lifetime cumulative count.
- Rebuild command:
  `make -C /Users/alex/micropython/ports/renesas-ra BOARD=EK_RA8P1 BUILD=build-EK_RA8P1-ceu-fullclocks RA8P1_BRINGUP_CEU_TEST=1 RA8P1_SAFE_BOOT_CLOCKS=1 RA8P1_SAFE_BOOT_SDRAM=1 RA8P1_SAFE_BOOT_SDRAM_HEAP=0 -j8`
- Build result:
  - Success.
  - Size: `text=307060`, `data=492`, `bss=5536840`.
  - `_SEGGER_RTT = 0x2200156c`.
- Flash/test through tmux `ra8p1-device`:
  - Flashed the rebuilt CEU firmware through pane `%1`; J-Link reported `O.K.`.
  - RTT restarted through pane `%2` with `RTT_BLOCK_ADDR=0x2200156c`.
  - Deliberately recreated the bad MIPI/CSI route state:
    `PREHI11 0 0 0 32 32 223`.
  - First capture auto-corrected the route and succeeded:
    `CAP11A 0 1 6 16777216 3079 342536773 0`.
  - Second capture also succeeded with `callbacks=6`, proving the count is no longer cumulative:
    `CAP11B 0 1 6 16777216 3079 3835295205 0`.

### CEU final smoke after route fix

- Board smoke through tmux `ra8p1-device`, RTT pane `%2`, still using `_SEGGER_RTT = 0x2200156c`:
  - `SMOKE12_ID (86, 64)` confirms OV5640 ID readback.
  - `SMOKE12_SW 0 32 0 223 0` confirms U15 is in CEU route state:
    `err=0`, `DIR=0x20`, `OUT=0x00`, `OE=0xdf`, physical `SW4-6` sampled low.
  - `SMOKE12_CAP 0 1 8 16777216 3079 2453830625 0` confirms CEU single-frame capture:
    `last_capture_start_err=0`, `capture_ready=1`, per-capture callback count is 8,
    frame-end event `0x01000000`, non-zero buffer sample, `last_switch_err=0`.
  - `SMOKE12_BUF 614400 [0, 252, 0, 252, 0, 252, 0, 252]` confirms the Python buffer view is readable and the size matches `640 * 480 * 2`.
- CEU commit checklist:
  - `/Users/alex/micropython/ports/renesas-ra/ra8p1_ceu.c`
  - `/Users/alex/micropython/ports/renesas-ra/boards/EK_RA8P1/ra_cfg/fsp_cfg/r_ceu_cfg.h`
  - CEU-related gates in `/Users/alex/micropython/ports/renesas-ra/Makefile` and `/Users/alex/micropython/ports/renesas-ra/boards/EK_RA8P1/mpconfigboard.mk`.
  - CEU IRQ/vector entries in `/Users/alex/micropython/ports/renesas-ra/boards/EK_RA8P1/ra_gen/vector_data.c` and `/Users/alex/micropython/ports/renesas-ra/boards/EK_RA8P1/ra_gen/vector_data.h`.
- Default build gate check:
  - Command:
    `make -C /Users/alex/micropython/ports/renesas-ra BOARD=EK_RA8P1 BUILD=build-EK_RA8P1-default-check -j8`
  - Result: success. Existing FSP/clock macro redefinition warnings only.
  - Size: `text=293912`, `data=492`, `bss=4922280`.
- Repo documentation update:
  - Added CEU/DVP bring-up notes to `/Users/alex/micropython/ports/renesas-ra/boards/EK_RA8P1/README.md`.
  - The README now records the `RA8P1_BRINGUP_CEU_TEST=1` build command, `J35`/`J41`/U15 route requirements, and the `SMOKE12` proof markers.
- Current no-op build checks after README update:
  - CEU build command completed without relinking:
    `make -C /Users/alex/micropython/ports/renesas-ra BOARD=EK_RA8P1 BUILD=build-EK_RA8P1-ceu-fullclocks RA8P1_BRINGUP_CEU_TEST=1 RA8P1_SAFE_BOOT_CLOCKS=1 RA8P1_SAFE_BOOT_SDRAM=1 RA8P1_SAFE_BOOT_SDRAM_HEAP=0 -j8`
  - Default build command completed without rebuilding:
    `make -C /Users/alex/micropython/ports/renesas-ra BOARD=EK_RA8P1 BUILD=build-EK_RA8P1-default-check -j8`
  - Module gate verified:
    `build-EK_RA8P1-ceu-fullclocks/genhdr/moduledefs.h` contains `mp_module_ra8p1_ceu`;
    `build-EK_RA8P1-default-check/genhdr/moduledefs.h` does not contain `ra8p1_ceu`.
  - `git diff --check` on tracked CEU-related files is clean.
  - No trailing whitespace in `ra8p1_ceu.c`, `r_ceu_cfg.h`, or `EK_RA8P1/README.md`.

### CEU API hardening after final smoke

- Source cleanup in `/Users/alex/micropython/ports/renesas-ra/ra8p1_ceu.c`:
  - Added bounds checks for `sample_pins(samples)`, `i2c_probe(addr)`,
    `camera_read(reg)`, `camera_write(reg, value)`, and `capture(timeout_ms)`.
  - `switch_state()` now attempts to restore U15 output state, output enable,
    and direction even if the temporary physical-switch sample path hits an
    I2C error after saving state. The returned dict now includes `restore_err`.
  - `camera_id()`, `camera_read()`, `camera_write()`, and `test_pattern()` now
    prepare the board route, XCLK, and camera reset-release state before
    accessing OV5640 registers. This removes the previous fresh-boot dependency
    on an earlier `init()`/`capture()`.
- Rebuild result:
  - Command:
    `make -C /Users/alex/micropython/ports/renesas-ra BOARD=EK_RA8P1 BUILD=build-EK_RA8P1-ceu-fullclocks RA8P1_BRINGUP_CEU_TEST=1 RA8P1_SAFE_BOOT_CLOCKS=1 RA8P1_SAFE_BOOT_SDRAM=1 RA8P1_SAFE_BOOT_SDRAM_HEAP=0 -j8`
  - Success. Existing FSP/clock macro redefinition warnings only.
  - Size: `text=307384`, `data=492`, `bss=5536840`.
  - `_SEGGER_RTT = 0x2200156c`.
- Flash/test through tmux `ra8p1-device`:
  - Flashed through pane `%1`; J-Link reported `O.K.` and `Script processing completed`.
  - RTT restarted through pane `%2`.
  - `ARG14 sample_hi ValueError samples too large`.
  - `ARG14 addr_hi ValueError addr must be 0..127`.
  - `ARG14 reg_neg ValueError reg must be 0..65535`.
  - `ARG14 val_hi ValueError value must be 0..255`.
  - `ARG14 timeout_hi ValueError timeout must be 0..60000 ms`.
  - Fresh-boot camera register access now works:
    `CID14 (86, 64)`.
  - U15 sample/restore path:
    `SW14 0 32 0 223 0 0`
    (`err=0`, `DIR=0x20`, `OUT=0`, `OE=0xdf`, sampled `SW4-6=0`, `restore_err=0`).
  - Capture remains good:
    `CAP14 0 1 6 16777216 3078 230752593 0`.
  - Buffer view remains good:
    `BUF14 614400 [0, 252, 0, 252, 0, 252, 0, 252]`.
- Default gate after hardening:
  - `make -C /Users/alex/micropython/ports/renesas-ra BOARD=EK_RA8P1 BUILD=build-EK_RA8P1-default-check -j8` completed without rebuilding.
  - `build-EK_RA8P1-default-check/genhdr/moduledefs.h` still does not contain `ra8p1_ceu`.
  - `git diff --check` on tracked CEU-related files is clean.
  - No trailing whitespace in `ra8p1_ceu.c`, `r_ceu_cfg.h`, or `EK_RA8P1/README.md`.

### CEU final restore-path validation

- Tightened `switch_state()` restore logic again:
  - The function now only writes back U15 registers whose original values were
    successfully saved, so an I2C read failure cannot expand into a default-zero
    write to an unknown U15 register state.
- Rebuild result:
  - Command:
    `make -C /Users/alex/micropython/ports/renesas-ra BOARD=EK_RA8P1 BUILD=build-EK_RA8P1-ceu-fullclocks RA8P1_BRINGUP_CEU_TEST=1 RA8P1_SAFE_BOOT_CLOCKS=1 RA8P1_SAFE_BOOT_SDRAM=1 RA8P1_SAFE_BOOT_SDRAM_HEAP=0 -j8`
  - Success. Existing FSP/clock macro redefinition warnings only.
  - Size: `text=307356`, `data=492`, `bss=5536840`.
  - `_SEGGER_RTT = 0x2200156c`.
- Flash/test through tmux `ra8p1-device`:
  - Flashed through pane `%1`; J-Link reached `Script processing completed`.
  - RTT restarted through pane `%2`.
  - Parameter validation remains correct:
    `ARG15 sample_hi ValueError samples too large`,
    `ARG15 addr_hi ValueError addr must be 0..127`,
    `ARG15 reg_neg ValueError reg must be 0..65535`,
    `ARG15 val_hi ValueError value must be 0..255`,
    `ARG15 timeout_hi ValueError timeout must be 0..60000 ms`.
  - Fresh-boot camera register access remains correct:
    `CID15 (86, 64)`.
  - U15 physical-sample/restore path remains correct:
    `SW15 0 32 0 223 0 0`.
  - CEU capture remains correct:
    `CAP15 0 1 6 16777216 3079 3886210041 0`.
  - Python buffer view remains correct:
    `BUF15 614400 [0, 252, 0, 252, 0, 252, 0, 252]`.
- Final gate checks:
  - Default build command completed without rebuilding:
    `make -C /Users/alex/micropython/ports/renesas-ra BOARD=EK_RA8P1 BUILD=build-EK_RA8P1-default-check -j8`
  - `build-EK_RA8P1-default-check/genhdr/moduledefs.h` still does not contain `ra8p1_ceu`.
  - `git diff --check` on tracked CEU-related files is clean.
  - No trailing whitespace in `ra8p1_ceu.c`, `r_ceu_cfg.h`, or `EK_RA8P1/README.md`.

### CEU live-display pin-conflict validation

- User goal for this pass: make the MicroPython CEU camera work and display on
  the board LCD, then diagnose the visible green fast flashing / jumping
  stripes.
- Source changes in `/Users/alex/micropython/ports/renesas-ra/ra8p1_ceu.c`:
  - Added `display_frame()`, `live()`, `yuv_order()`, and YUV422-to-XRGB8888
    rendering into `g_framebuffer[0]`.
  - Added cache maintenance around CEU DMA capture and GLCDC framebuffer flips.
  - Added `restore_display_pins()` and `snapshot_display()` after discovering
    that the CEU DVP route shares the parallel LCD pins.
  - `deinit()` now stops CEU/XCLK and restores the shared pins to
    `LCD_GRAPHICS`.
- Pin-conflict evidence from generated board config:
  - `P09_02` is `PARLCD_D3B3_PARCAM_D1`.
  - `P11_02` is `PARLCD_D16R0_PARCAM_VSYNC`.
  - `P11_03` is `PARLCD_D15G7_PARCAM_HSYNC`.
  - `P11_04` is `PARLCD_D14G6_PARCAM_PCLK`.
  - `ra8p1_ceu.c` must mux those same pins to `IOPORT_PERIPHERAL_CEU` for
    capture, so the current parallel GLCDC LCD output cannot be a reliable
    simultaneous live preview path.
- Rebuild result:
  - Command:
    `make -C /Users/alex/micropython/ports/renesas-ra BOARD=EK_RA8P1 BUILD=build-EK_RA8P1-ceu-fullclocks RA8P1_BRINGUP_CEU_TEST=1 RA8P1_SAFE_BOOT_CLOCKS=1 RA8P1_SAFE_BOOT_SDRAM=1 RA8P1_SAFE_BOOT_SDRAM_HEAP=0 -j8`
  - Success. Existing FSP/clock macro redefinition warnings only.
  - Size after snapshot-display change: `text=309840`, `data=496`,
    `bss=5536872`.
  - `_SEGGER_RTT = 0x22001590`.
- Flash/test through tmux `ra8p1-device`:
  - Flashed through pane `%1`; J-Link reported `O.K.` and
    `Script processing completed`.
  - RTT restarted through pane `%2` with
    `RTT_BLOCK_ADDR=0x22001590`.
  - API and restore-path check:
    `API19 True True True`.
  - Initial display-pin restore check:
    `REST19 1 0 0 0 419496960 419496960 419496960 419496962`
    (`display_pins_restored=1`, restore err `0`, CEU/XCLK closed).
  - Controlled camera test-pattern live run still captured/flipped without
    FSP errors but user still saw green fast flashing:
    `PAT18 30 0 90 0 3075 3367756289 0 1`.
  - Single-frame capture-then-restore display proof:
    `SNAP19 1 1 0 0 1 0 0 1 3076 16967265 1 419496960 419496960 419496960 419496962`.
  - Real-image single-frame proof with OV5640 test pattern disabled:
    `SNAP20 1 1 0 0 1 0 0 2 4042 4109247169 0 419496960 419496960 419496960 419496962`.
- Current conclusion:
  - CEU capture and framebuffer conversion are working from MicroPython.
  - Continuous preview on the current parallel GLCDC LCD path is blocked by
    shared CEU/LCD pins, not by cache coherency alone or by OV5640 byte order.
  - For true live camera preview, move the display side to a non-overlapping
    route, most likely MIPI-DSI. The current `snapshot_display()` API is a
    low-rate proof path only.

### CEU image-clarity and OV5640 DVP mapping sweep

- User-visible state at start of this pass:
  - Green fast flicker / jumping green bars were gone after using the
    capture-then-restore display path.
  - Remaining issue: image was still unclear.
- Additional source/runtime state:
  - `ra8p1_ceu.c` was extended with a fixed internal SRAM capture buffer at
    `0x22030000`, `status()["buffer_in_sram"]`, and `capture_reuse(timeout)`.
  - Latest flashed firmware exposed `capture_reuse`, `camera_write`, and
    `timing()`; REPL proof:
    `API37 True True (0, 0, 0, 0, 0)`.
- Negative tests already ruled out:
  - Moving CEU capture buffer from SDRAM to fixed internal SRAM did not remove
    the stripes:
    `SRAM30 570621952 614400 1 0 0 3076 3376323721 1 0 0 0 0 0`.
  - Pure `capture()` without the display path did not remove stripes:
    `CAP32 570621952 614400 1 0 6 16777216 3081 3300613913 1 1 1`.
  - Waiting 1 second before capture did not remove stripes:
    `CAP35 570621952 614400 1 0 6 16777216 3079 677098981 1 1 25000000`.
- `0x4740` sweep with test pattern and SRAM buffer:
  - `0x00` / `0x01` were worse.
  - `0x20` / `0x21` were still the best of that sweep but retained stripes.
  - `0x02` / `0x03` / `0x22` / `0x23` produced flat/bad frames.
  - Montage: `/Users/alex/ceu_dump_42_reg4740_montage.png`.
- Important DVP data-order finding:
  - Official EK-RA8P1 CEU test-pattern first word is `0xFF80FF80`, i.e. first
    bytes `[128, 255, 128, 255]` in little-endian memory.
  - Current MicroPython init table still used `{0x4745, 0x00}` and produced
    `[0, 252, 0, 252, ...]`, consistent with the useful 8-bit data lane being
    shifted.
  - Runtime sweep of OV5640 register `0x4745`:
    - `REG45 0x0 ... [0, 252, 0, 252, ...]`
    - `REG45 0x2 ... [128, 255, 128, 255, ...]`
    - `REG45 0x6 ... [128, 255, 128, 255, ...]`
  - Conclusion: `0x4745` must not remain `0x00` for this board/camera route.
    `0x02` and `0x06` both fix the leading byte pattern; `0x06` was the more
    stable candidate in repeated captures.
- J-Link dump note:
  - Do not use bare `JLinkExe` in pane `%1`; it is not on that shell PATH and
    produced `zsh: command not found: JLinkExe`.
  - Use:
    `/Users/alex/jlink_v938a_extract/Applications/SEGGER/JLink_V938a/JLinkExe -NoGui 1 -CommanderScript /Users/alex/ra8p1-jlink-dump-ceu.cmd`
  - When waiting for dumps, include a unique shell marker; otherwise `tmi wait`
    can match old `Script processing completed` text already in the pane.
- Corrected raw dumps and render artifacts:
  - `/Users/alex/ceu_dump_43_reg4745_02.yuv`
  - `/Users/alex/ceu_dump_44_reg4745_06.yuv`
  - `/Users/alex/ceu_dump_45_reg4745_montage.png`
- Official one-line match scoring on-board:
  - Method: load the official EK-RA8P1 `g_cam_vga_color_one_line[]` into
    MicroPython as a 1280-byte reference and compare every captured 32-bit word
    against that same line for all 480 rows.
  - First timing sweep, hsync/vsync polarity unchanged:
    - `SCORE46 0x2 (0, 0, 0, 0, 0) ... 41620 27`
    - `SCORE46 0x2 (0, 1, 0, 0, 0) ... 54283 35`
    - `SCORE46 0x2 (0, 0, 1, 0, 0) ... 54447 35`
    - `SCORE46 0x6 (0, 0, 0, 0, 0) ... 53103 34`
    - `SCORE46 0x6 (0, 1, 0, 0, 0) ... 69738 45`
  - Focused polarity sweep:
    - `hpol=1` combinations scored `0`, so keep hsync polarity unchanged.
    - Best observed in that pass:
      `SCORE47 0x6 (0, 1, 0, 0, 1) ... 61850 40`.
  - Current interpretation:
    - `0x4745=0x06` plus `hdsel=1` is the best measured temporary setting but
      still far below the official example's pass threshold.
    - Remaining stripes are not explained by buffer placement, display render
      order, hsync polarity, or the old `0x4745=0x00` issue alone.
- Real-image display test with temporary best setting:
  - REPL sequence:
    `deinit(); yuv_order(0); test_pattern(False); timing(0,1,0,0,0); init(); camera_write(0x4740,0x20); camera_write(0x4745,0x06); capture_reuse(3000); restore_display_pins(); display_frame()`
  - Runtime proof:
    `REAL48 0 7 4096 3681320724 1 0 0 0 1 0 0 0`.
  - Follow-up test-pattern dump showed `hdsel=1` changes the byte phase:
    `DUMP49 ... [255, 128, 255, 128, ...]`.
  - Rendered order montage for this byte phase:
    `/Users/alex/ceu_dump_51_hdsel1_orders_montage.png`.
  - Interpretation: `hdsel=1` can improve the one-line score in some frames
    but does not really fix the visible stripe pattern and can move the stream
    to `Y,Cb,Y,Cr` phase instead of the official `Cb,Y,Cr,Y` phase.
- Real-image display test with only the DVP lane fix:
  - REPL sequence:
    `deinit(); yuv_order(0); test_pattern(False); timing(0,0,0,0,0); init(); camera_write(0x4740,0x20); camera_write(0x4745,0x06); capture_reuse(3000); restore_display_pins(); display_frame()`
  - Runtime proof:
    `REAL52 0 8 4096 855197198 1 0 0 1 0 0 0 0`.
  - Current visual-feedback request to user: compare `REAL52` against the
    previous unclear image and the `REAL48` `hdsel=1` image.
- Source update:
  - `/Users/alex/micropython/ports/renesas-ra/ra8p1_ceu.c` now defines
    `RA8P1_CEU_OV5640_DVP_DATA_ORDER (0x06U)` and uses that value for OV5640
    register `0x4745` in the init table.
  - Build-only verification, not flashed yet:
    `make -C /Users/alex/micropython/ports/renesas-ra BOARD=EK_RA8P1 BUILD=build-EK_RA8P1-ceu-fullclocks RA8P1_BRINGUP_CEU_TEST=1 RA8P1_SAFE_BOOT_CLOCKS=1 RA8P1_SAFE_BOOT_SDRAM=1 RA8P1_SAFE_BOOT_SDRAM_HEAP=0 -j8`
  - Build succeeded with existing FSP/clock macro redefinition warnings.
  - Size: `text=310464`, `data=528`, `bss=4922472`.
  - Generated:
    `build-EK_RA8P1-ceu-fullclocks/firmware.elf`,
    `build-EK_RA8P1-ceu-fullclocks/firmware.hex`,
    `build-EK_RA8P1-ceu-fullclocks/firmware.bin`.

### CEU PCLK divider fix

- OV5640 `0x3824` sweep with `0x4745=0x06`, default CEU timing, and official
  test-pattern scoring:
  - `SCORE53 0x1 0 9 51836 33 [128, 255, 128, 255, 128, 255, 128, 255]`
  - `SCORE53 0x2 0 3 153120 99 [128, 255, 128, 255, 128, 255, 128, 255]`
  - `SCORE53 0x3 0 4 153120 99 [128, 255, 128, 255, 128, 255, 128, 255]`
  - `SCORE53 0x4 0 3 152640 99 [128, 255, 128, 255, 128, 255, 128, 255]`
  - `SCORE53 0x8 20 95 0 0 [255, 255, 255, 255, 255, 255, 255, 255]`
  - `SCORE53 0x10 20 95 0 0 [255, 255, 255, 255, 255, 255, 255, 255]`
- Selected `0x3824=0x02` as the least aggressive passing value.
- Test-pattern proof:
  - `DUMP54 0 4 152640 99 [128, 255, 128, 255, 128, 255, 128, 255, 128, 255, 128, 255, 128, 255, 128, 255]`
  - Raw dump: `/Users/alex/ceu_dump_54_reg4745_06_3824_02.yuv`
  - Montage: `/Users/alex/ceu_dump_55_3824_compare_montage.png`
  - The `0x3824=0x02` image is clean color bars; the earlier `0x3824=0x01`
    image has heavy horizontal stripes.
- Real-image display proof with the same settings:
  - REPL sequence:
    `deinit(); yuv_order(0); test_pattern(False); timing(0,0,0,0,0); init(); camera_write(0x4740,0x20); camera_write(0x4745,0x06); camera_write(0x3824,0x02); capture_reuse(3000); restore_display_pins(); display_frame()`
  - Runtime proof:
    `REAL56 0 4 4096 247919230 1 0 0 2 0 0 0 0`.
  - User visual feedback is still requested for the real camera image, but the
    raw test-pattern artifact proves the stripe corruption is fixed at the CEU
    capture level.
  - Source update:
  - `/Users/alex/micropython/ports/renesas-ra/ra8p1_ceu.c` now defines
    `RA8P1_CEU_OV5640_PCLK_MANUAL_DIVIDER (0x02U)` and uses that value for
    OV5640 register `0x3824` in the init table.
  - Build-only verification, not flashed yet:
    `make -C /Users/alex/micropython/ports/renesas-ra BOARD=EK_RA8P1 BUILD=build-EK_RA8P1-ceu-fullclocks RA8P1_BRINGUP_CEU_TEST=1 RA8P1_SAFE_BOOT_CLOCKS=1 RA8P1_SAFE_BOOT_SDRAM=1 RA8P1_SAFE_BOOT_SDRAM_HEAP=0 -j8`
  - Build succeeded with existing FSP/clock macro redefinition warnings.
  - Size: `text=310464`, `data=528`, `bss=4922472`.

### CEU source-default proof and real-image clarity tests

- Flashed the CEU source-default firmware after landing the DVP lane and PCLK
  divider fixes in `ports/renesas-ra/ra8p1_ceu.c`.
  - Firmware path:
    `/Users/alex/micropython/ports/renesas-ra/build-EK_RA8P1-ceu-fullclocks/firmware.bin`.
  - J-Link proof marker in pane `%1`: `__FLASH57_DONE__`.
- Source-default test-pattern proof, with no runtime `camera_write()` overrides:
  - REPL proof:
    `SRC58 0 3 152640 99 [128, 255, 128, 255, 128, 255, 128, 255, 128, 255, 128, 255, 128, 255, 128, 255]`.
  - Interpretation: the init-table defaults now produce a clean OV5640 color
    bar frame at the CEU buffer level.
- Source-default real-image proof:
  - REPL proof:
    `REAL58 0 3 4096 148128495 1 0 1 0`.
  - Follow-up user feedback: green flashing stripes were gone, but the image
    was still not clear.
- Captured and dumped a source-default real frame for local inspection:
  - REPL proof:
    `REAL59 0 3 4096 1815487254 1 0 3 0`.
  - J-Link dump marker: `__DUMP59_DONE__`.
  - Raw dump: `/Users/alex/ceu_dump_59_real_source_default.yuv`.
  - Rendered PNGs:
    `/Users/alex/ceu_dump_59_real_CBYCRY.png`,
    `/Users/alex/ceu_dump_59_real_orders_montage.png`.
  - Interpretation: the real frame is recognizable and naturally colored in
    the `Cb,Y,Cr,Y` order used by the MicroPython display path; the remaining
    blur is present in the raw frame, not introduced by LCD rendering.
- Read current OV5640 auto-exposure/gain state after the source-default frame:
  - Compact readback:
    `REG61 3500=00 3501=5c 3502=00 350a=00 350b=22 3503=00 3a18=00 3a19=f8 3406=00`.
  - Interpretation: auto exposure was active, exposure was about `0x5c00`,
    and analog gain was about `0x22`.
- Runtime short-exposure test:
  - Registers forced:
    `3503=07`, `3501=20`, `350b=20`.
  - REPL proof:
    `EXP62 0 4 2719025358 3500=00 3501=20 3502=00 350a=00 350b=20 3503=07`.
  - J-Link dump marker: `__DUMP62_DONE__`.
  - Raw dump: `/Users/alex/ceu_dump_62_real_short_exp.yuv`.
  - Result: image was much darker and not a good default, but the face/edge
    shape suggested that exposure/highlight behavior contributes to perceived
    blur.
- Runtime mid-exposure/high-gain test:
  - Registers forced:
    `3503=07`, `3501=40`, `350b=30`.
  - REPL proof:
    `EXP64 0 4 97516254 3500=00 3501=40 3502=00 350a=00 350b=30 3503=07`.
  - J-Link dump marker: `__DUMP64_DONE__`.
  - Raw dump: `/Users/alex/ceu_dump_64_real_mid_exp_gain.yuv`.
  - Comparison artifact:
    `/Users/alex/ceu_dump_65_auto_exp_sweep_compare.png`.
  - Interpretation: `EXP64` is visibly clearer than the first auto-exposure
    frame in local render, while still using the same CEU byte order and source
    routing fixes. Do not treat the remaining clarity issue as a CEU data-lane,
    SRAM/SDRAM, or LCD pin-restore bug unless new stripes or corruption return.

### CEU green-flicker mitigation with GLCDC stop retry and backlight gate

- User reported green flashing bars returned on the LCD even after the raw CEU
  capture data was clean. Local pin data shows this is plausible because several
  parallel LCD pins are hard-shared with CEU/parallel camera, including:
  `PB02=PARLCD_D16/PARCAM_VSYNC`, `PB03=PARLCD_D15/PARCAM_HSYNC`, and
  `PB04=PARLCD_D14/PARCAM_PCLK`.
- Runtime backlight polarity proof:
  - `P514` is `DISP_BLEN`.
  - REPL proof:
    `BL70_INIT 1`, `BL70_SET 0`, `BL70_SET 1`, `BL70_RESTORE 1`.
  - Manual single-frame gate proof:
    `SNAP71_BL 0`
    `SNAP71 0 3 0 0 1 0 2 3 BL 1`.
- Source update in `/Users/alex/micropython/ports/renesas-ra/ra8p1_ceu.c`:
  - Added `ra8p1_ceu_display_backlight_set()` for `P514/DISP_BLEN`.
  - `snapshot_display()` and `live()` now turn the backlight off before GLCDC
    stop / CEU capture / shared-pin muxing, then restore LCD pins, render, and
    turn the backlight back on.
  - Added `last_display_stop_err`, `last_display_backlight_err`, and
    `display_backlight_on` to `status()`.
  - Added retry handling for `R_GLCDC_Stop()` returning
    `FSP_ERR_INVALID_UPDATE_TIMING` (`1006`) while GLCDC registers are updating.
- Build/flash proof:
  - Build command:
    `make -C /Users/alex/micropython/ports/renesas-ra BOARD=EK_RA8P1 BUILD=build-EK_RA8P1-ceu-fullclocks RA8P1_BRINGUP_CEU_TEST=1 RA8P1_SAFE_BOOT_CLOCKS=1 RA8P1_SAFE_BOOT_SDRAM=1 RA8P1_SAFE_BOOT_SDRAM_HEAP=0 -j8`
  - Build succeeded with existing FSP/clock macro redefinition warnings.
  - Final size: `text=310824`, `data=528`, `bss=4922480`.
  - J-Link pane `%1` flash marker: `__FLASH76_DONE__`.
  - RTT control block after this build: `_SEGGER_RTT=0x220015b8`.
- Device proof after flashing:
  - `SNAP77 0 3 0 0 0 1 1 0 2 1`
  - `SNAP78 0 3 0 0 0 1 1 0 2 2`
  - `LIVE79 0 3 0 0 0 1 1 0 2 5`
  - Field order for these compact proofs:
    `last_capture_frame_err callbacks/last_live_completed last_display_stop_err last_display_backlight_err last_display_flip_err display_pins_restored display_backlight_on xclk_open glcdc_state display_frames`.
  - Interpretation: source-level backlight gating plus GLCDC stop retry runs
    single-frame capture and a 3-frame live loop without CEU, backlight, GLCDC
    stop, or display flip errors. Ask user to visually confirm whether the
    remaining display behavior is now short black-frame blanking instead of
    green flicker.
- Visual confirmation:
  - User confirmed after the flashed `__FLASH76_DONE__` build that the green
    bars no longer flicker on the LCD.
  - Conclusion: keep the `P514/DISP_BLEN` backlight gate and GLCDC stop retry
    in the MicroPython CEU path. The remaining image-quality work should focus
    on camera exposure/focus/format tuning, not the previous green-flicker
    display artifact.

### CEU blurry/blocky image buffer inspection and runtime image-tuning sweep

- User reported the remaining live image was blurry/blocky after green flicker
  was fixed.
- Current source-default frame:
  - REPL proof:
    `SNAP80 0 3 4096 1947878953 0 0 0 1 1 0 2 6`
  - Register readback:
    `REG80 3406=00 3500=00 3501=5c 3502=00 3503=00 350a=00 350b=34 3824=02 3a18=00 3a19=f8 4300=30 4301=01 4740=20 4745=06 5001=a3 501f=00 5300=08 5301=30 5302=3f 5303=10 5680=00 5681=00 5682=0a 5683=20 5684=00 5685=00 5686=07 5687=98`.
  - J-Link dumps:
    `/Users/alex/ceu_dump_80_current_blurry.yuv`,
    `/Users/alex/ceu_dump_80_framebuffer0_xrgb8888.bin`,
    `/Users/alex/ceu_dump_80_framebuffer1_xrgb8888.bin`.
  - Render artifacts:
    `/Users/alex/ceu_dump_80_current_blurry_CBYCRY.png`,
    `/Users/alex/ceu_dump_80_orders_montage.png`,
    `/Users/alex/ceu_dump_80_raw_fb_compare.png`,
    `/Users/alex/ceu_dump_80_analysis.json`.
  - Important result: framebuffer page0 crop matches the CEU raw render exactly
    (`mean_abs_rgb_diff=0.0` in `/Users/alex/ceu_dump_80_analysis.json`).
    Page1 was stale color-bar/noise content. Therefore the blur/softness is
    already present in the camera/CEU raw frame, not introduced by the GLCDC
    framebuffer or YUV-to-XRGB display conversion path.
  - Block-boundary metric was not high (`block8_ratio ~= 1.03`,
    `block16_ratio ~= 1.05`), so the raw frame does not show strong codec-like
    8x8/16x16 blocking. The perceived blockiness is more likely low VGA
    resolution, sensor scaling/ISP, exposure, or focus.
- Runtime image-tuning sweep, all through tmux panes:
  - `TUNE82`: manual exposure/gain only, displayed on LCD and dumped to
    `/Users/alex/ceu_dump_82_mid_exp_gain.yuv`.
    Proof:
    `TUNE82 0 4 4096 3283458271 0 7`
    and
    `TUNE82_REG 3500=00 3501=40 3502=00 350a=00 350b=30 3503=07 ... 5300=08 5301=30 5302=3f 5303=10 ...`.
  - OV5640 datasheet check: CIP edge enhancement is controlled by
    `0x5300..0x530F`; `0x5308[6]` enables manual edge MT.
  - `TUNE83`: `TUNE82` plus `0x5308=0x65`, displayed on LCD and dumped to
    `/Users/alex/ceu_dump_83_mid_exp_mipi_isp.yuv`.
    Proof:
    `TUNE83 0 3 4096 2122081979 0 8`
    and `TUNE83_REG ... 5308=65 ...`.
  - `TUNE84`: exposure raised to `0x3501=0x50`, gain `0x350b=0x30`,
    `0x5308=0x65`, displayed on LCD and dumped to
    `/Users/alex/ceu_dump_84_exp50_edge.yuv`.
    Proof:
    `TUNE84 0 5 4096 1220870920 0 9`
    and
    `TUNE84_REG 3500=00 3501=50 3502=00 350a=00 350b=30 3503=07 5300=08 5301=30 5302=3f 5303=10 5308=65 5309=08 530a=30 530b=04 530c=06`.
  - Comparison artifacts:
    `/Users/alex/ceu_dump_80_82_83_84_compare.png`,
    `/Users/alex/ceu_dump_80_82_83_84_crop_compare.png`,
    `/Users/alex/ceu_dump_80_82_83_84_analysis.json`.
  - Interpretation: `TUNE84` is the best runtime candidate so far: less
    overexposed than auto, brighter than `TUNE82/TUNE83`, and higher edge
    metrics than `TUNE82`. Do not yet bake it in as a default because it uses
    manual exposure and may be room-light dependent. A better source-level next
    step is a persistent MicroPython tuning/preset API that is re-applied after
    `snapshot_display()` or `live()` reopens the OV5640.
- User then reported green-bar flicker plus blocky image again. This is not a
  normal final state.
  - Important distinction: `TUNE82/TUNE83/TUNE84` used the manual sequence
    `init(); capture_reuse(); restore_display_pins(); display_frame()` and
    intentionally did not go through the `snapshot_display()`/`live()`
    backlight gate. That can visibly expose the shared CEU/LCD pin switching
    artifact.
  - Safe-path retest after the report:
    `SNAP85_SAFE 0 3 0 0 0 1 1 0 2 10`.
  - Field order:
    `last_capture_frame_err callbacks last_display_stop_err last_display_backlight_err last_display_flip_err display_pins_restored display_backlight_on xclk_open glcdc_state display_frames`.
  - Interpretation: the source-level safe path still reports no capture,
    backlight, GLCDC stop, or display flip errors. Ask the user for visual
    confirmation after `SNAP85_SAFE`; if green bars still flicker after this
    safe path, continue debugging LCD/CEU shared-pin restore timing instead of
    treating the issue as expected behavior.

### CEU tuning API source-level safe-path proof

- Source change added a persistent MicroPython tuning API in
  `/Users/alex/micropython/ports/renesas-ra/ra8p1_ceu.c`:
  `ceu.tuning([enabled[, exposure[, gain[, edge_ctrl]]]])`.
  - `ceu.tuning()` returns `(enabled, exposure, gain, edge_ctrl)`.
  - `ceu.tuning(1)` selects the previous best candidate from `TUNE84`:
    exposure `0x500`, gain `0x30`, edge control `0x65`.
  - Tuning is re-applied inside the OV5640 open path, so
    `snapshot_display()` and `live()` can use it without bypassing the
    display/backlight safe path.
- Build:
  `make -C /Users/alex/micropython/ports/renesas-ra BOARD=EK_RA8P1 BUILD=build-EK_RA8P1-ceu-fullclocks RA8P1_BRINGUP_CEU_TEST=1 RA8P1_SAFE_BOOT_CLOCKS=1 RA8P1_SAFE_BOOT_SDRAM=1 RA8P1_SAFE_BOOT_SDRAM_HEAP=0 -j8`
  completed successfully. New RTT control block was `_SEGGER_RTT=0x220015cc`.
- Flashed through tmux pane `%1` with
  `/Users/alex/ra8p1-jlink-normal.cmd`; J-Link reported Program & Verify OK
  for `/Users/alex/micropython/ports/renesas-ra/build-EK_RA8P1-ceu-fullclocks/firmware.bin`.
- Restarted RTT through tmux pane `%2` using
  `RTT_BLOCK_ADDR=0x220015cc /opt/homebrew/bin/python3 /Users/alex/ek-ra8p1-handoff/scripts/rtt_terminal.py`.
- REPL proof after enabling source-level tuning:
  - `TUNEAPI (0, 1280, 48, 101)`
  - `TUNESET (1, 1280, 48, 101)`
  - `SNAP86_TUNED 0 2 0 0 0 1 1 0 2 1 0 1 1280 48 101`
  - `REG86 3500=00 3501=50 3502=00 3503=07 350a=00 350b=30 5308=65`
  - Field order:
    `last_capture_frame_err callbacks last_display_stop_err last_display_backlight_err last_display_flip_err display_pins_restored display_backlight_on xclk_open glcdc_state display_frames last_tuning_err tuning_enabled tuning_exposure tuning_gain tuning_edge_ctrl`.
- J-Link dump after `SNAP86_TUNED`:
  `/Users/alex/ceu_dump_86_tuning_api.yuv`.
  - Dump script:
    `/Users/alex/ra8p1-jlink-dump-ceu-86.cmd`.
  - Rendered image:
    `/Users/alex/ceu_dump_86_tuning_api_CBYCRY.png`.
  - Comparison artifacts:
    `/Users/alex/ceu_dump_80_84_86_compare.png`,
    `/Users/alex/ceu_dump_80_84_86_crop_compare.png`,
    `/Users/alex/ceu_dump_80_84_86_analysis.json`.
  - Metrics from `/Users/alex/ceu_dump_80_84_86_analysis.json`:
    `86_tuning_api_safe` had `y_mean=133.70`, `center_edge_mean_abs=1.77`,
    `block8_ratio=1.019`, and `block16_ratio=1.034`.
- Interpretation:
  - `SNAP86_TUNED` proves the tuning values are now applied by the source-level
    safe path: manual exposure/gain/edge registers read back correctly and all
    display/backlight error fields remain zero.
  - The `86` frame is a valid camera frame, not green-bar corruption or GLCDC
    format/pitch corruption.
  - The low block-boundary ratios again argue against a codec-like 8x8/16x16
    block artifact. Remaining softness is more likely OV5640 focus, motion,
    room lighting/manual exposure choice, or the expected limits of VGA sensor
    scaling/ISP.
- Realtime finite-loop proof with the same tuning state:
  - REPL command used `ceu.live(10, 3000)`.
  - Output:
    `LIVE87 0 4 0 0 0 1 1 0 2 11 10 10 0 1 1280 48 101`.
  - Field order:
    `last_capture_frame_err callbacks last_display_stop_err last_display_backlight_err last_display_flip_err display_pins_restored display_backlight_on xclk_open glcdc_state display_frames last_live_requested last_live_completed last_tuning_err tuning_enabled tuning_exposure tuning_gain tuning_edge_ctrl`.
  - Interpretation: the source-level safe realtime path completed all 10
    requested frames with tuning enabled and no capture/display/backlight
    errors. If the LCD still visibly glitches, treat it as a visual timing issue
    not reflected in these error counters; otherwise this is the first
    successful MicroPython CEU camera-to-LCD finite live proof with source-level
    tuning.

### CEU display-path split tests after user suspected LCD/display issue

- User reported the remaining symptom looked like a display issue.
- Static synthetic-display split test:
  - Filled `ceu.buffer()` with five vertical grayscale bars in CEU native
    `CB,Y,CR,Y` order, then called `ceu.display_frame()` without running a new
    camera capture.
  - User observed the LCD showed normal five bars.
  - REPL proof:
    `DISP88_BARS 0 0 1 1 2 12 0`.
  - Field order:
    `last_display_flip_err last_display_backlight_err display_pins_restored display_backlight_on glcdc_state display_frames yuv_order`.
  - Interpretation: static framebuffer rendering, YUV-to-XRGB conversion,
    GLCDC bufferChange, cache clean, and LCD output are good for a synthetic
    CEU buffer.
- OV5640 internal test-pattern split test:
  - Enabled `ceu.test_pattern(True)`, captured through CEU, and displayed via
    `snapshot_display(3000)`.
  - User observed the LCD test pattern was stable.
  - REPL proof:
    `PAT89 0 3 0 0 0 1 1 0 2 13 1 1`.
  - Field order:
    `last_capture_frame_err callbacks last_display_stop_err last_display_backlight_err last_display_flip_err display_pins_restored display_backlight_on xclk_open glcdc_state display_frames test_pattern tuning_enabled`.
  - Interpretation: the camera-output-to-CEU-capture-to-LCD-display path is
    stable for an internal fixed sensor pattern. This shifts the remaining
    real-image softness/blockiness away from the static display path and toward
    real-scene sensor settings, focus, motion, lighting, or OV5640 ISP behavior.
- Restored real camera image after the test-pattern check:
  - Command turned `ceu.test_pattern(False)` back off, kept `ceu.tuning(1)`,
    and ran `ceu.snapshot_display(3000)`.
  - REPL proof:
    `REAL90 0 3 0 0 0 1 1 0 2 14 0 1`.
  - Field order:
    `last_capture_frame_err callbacks last_display_stop_err last_display_backlight_err last_display_flip_err display_pins_restored display_backlight_on xclk_open glcdc_state display_frames test_pattern tuning_enabled`.
  - Interpretation: real camera display returned with test pattern disabled
    and tuning enabled; error counters still do not show a GLCDC/backlight/pin
    restore failure.
- Runtime clock check after asking whether the main frequency was too low:
  - REPL proof:
    `CLK92 system_core_clock=1000000000 clock_pclkd_hz=250000000 clock_gptclk_hz=300000000 xclk_target_hz=24000000 xclk_config_period_counts=13 xclk_info_clock_hz=0 xclk_info_period_counts=0 xclk_actual_hz=0 clock_pclkd_hz=250000000 display_frames=18 last_capture_frame_err=0 last_display_flip_err=0`.
  - Interpretation: this run is not on the earlier bad 8 MHz runtime clock
    path. CPU is reporting 1 GHz, PCLKD 250 MHz, and GPTCLK 300 MHz. Since
    `snapshot_display()` closes XCLK after capture, `xclk_info_clock_hz` reads
    zero in the idle status snapshot; the configured XCLK period is 13 counts
    from GPTCLK, about 23.1 MHz, close to the 24 MHz target.

### GitHub wrap-up snapshot

- FSP fork commit pushed:
  `https://github.com/ssql2014/fsp/tree/ra8p1-micropython-bringup`
  at `7c1f97a5991506e746718616c3cbc2c13e85df1a`.
- MicroPython commit pushed to `ssql2014/micropython master`:
  `8d8fc07 ra8p1: add gated CEU and MIPI camera bring-up`.
- The MicroPython commit includes:
  - FSP submodule URL moved to `https://github.com/ssql2014/fsp.git` and
    pinned to the RA8P1 safe-boot/DSI diagnostics commit.
  - Gated `ra8p1_ceu` and `ra8p1_mipi_csi` modules.
  - EK_RA8P1 generated CEU, GPT, IIC, MIPI-CSI, MIPI-DSI, VIN, GLCDC and vector
    configuration.
  - README notes for the current CEU/DVP route and runtime smoke.
- Build checks after staging:
  - CEU:
    `make -C /Users/alex/micropython/ports/renesas-ra BOARD=EK_RA8P1 BUILD=build-EK_RA8P1-ceu-fullclocks RA8P1_BRINGUP_CEU_TEST=1 RA8P1_SAFE_BOOT_CLOCKS=1 RA8P1_SAFE_BOOT_SDRAM=1 RA8P1_SAFE_BOOT_SDRAM_HEAP=0 -j8`
    completed successfully.
  - MIPI-CSI:
    `make -C /Users/alex/micropython/ports/renesas-ra BOARD=EK_RA8P1 BUILD=build-EK_RA8P1-mipi-csi RA8P1_BRINGUP_MIPI_CSI_TEST=1 RA8P1_SAFE_BOOT_CLOCKS=1 RA8P1_SAFE_BOOT_SDRAM=1 RA8P1_SAFE_BOOT_SDRAM_HEAP=0 -j8`
    completed successfully with existing macro redefinition warnings and a few
    unused helper warnings.
  - MIPI-DSI:
    `make -C /Users/alex/micropython/ports/renesas-ra BOARD=EK_RA8P1 BUILD=build-EK_RA8P1-mipi-dsi RA8P1_BRINGUP_DISPLAY_TEST=1 RA8P1_BRINGUP_MIPI_DSI_TEST=1 RA8P1_SAFE_BOOT_CLOCKS=1 RA8P1_SAFE_BOOT_SDRAM=1 RA8P1_SAFE_BOOT_SDRAM_HEAP=0 -j8`
    completed successfully with existing macro redefinition warnings.
