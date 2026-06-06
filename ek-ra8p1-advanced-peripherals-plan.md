# EK-RA8P1 Advanced Peripherals Porting Plan

Date: 2026-06-04
Context: Andy asked about porting advanced peripherals: CEU, MIPI-CSI,
MIPI-DSI, and Ethernet.

## Short reply for Andy

The EK-RA8P1 MicroPython port can be extended to cover these peripherals, but
they are not the same class of work as GPIO/PWM/I2C/SPI/ADC/DAC/CANFD.
Ethernet is the best first target because the board has the GPY111 PHY support
in the RA8P1 FSP BSP and MicroPython already has lwIP integration hooks.
MIPI-DSI is next because the current display path already uses GLCDC and the
FSP tree contains the DSI/PHY drivers, but the generated board configuration
currently routes GLCDC to parallel RGB, not to a MIPI panel.
MIPI-CSI and CEU are camera-capture work and need a sensor/module definition,
frame-buffer ownership, and a Python-facing image-buffer API before the port
can claim useful support.

Recommended sequencing:

1. Ethernet bring-up to `network.LAN` using RA8P1 RGMII1/GPY111 plus lwIP.
2. MIPI-DSI display bring-up as an alternate display backend after the target
   panel and init command sequence are fixed.
3. Camera capture: MIPI-CSI for serial camera modules, CEU for parallel camera
   modules, with a minimal `camera.capture()` style API first.

## Current local evidence

- FSP v6.4.0 is present in `lib/fsp` and includes:
  - `r_ceu`
  - `r_mipi_csi`
  - `r_mipi_dsi`
  - `r_mipi_phy`
  - `r_ether`
  - `r_ether_phy`
  - `rm_lwip_ether`
  - `rm_lwip_sys_baremetal`
- EK_RA8P1 current generated instances in `boards/EK_RA8P1/ra_gen` only expose
  GLCDC and IOPORT at the `common_data.*` level. There is no generated CEU,
  MIPI-CSI, MIPI-DSI, Ethernet, PHY, or lwIP wrapper instance yet.
- The current `ports/renesas-ra/Makefile` always compiles GLCDC and SCI UART,
  and has RA8P1-specific additions for ADC_B, DAC_B, CANFD, RTT, and display.
  It does not yet add the FSP source files needed by CEU, MIPI, Ethernet, or
  the lwIP Ethernet wrapper.
- `boards/EK_RA8P1/configuration.xml` contains board symbolic names for
  Ethernet, MIPI, and camera pins. It also contains MIPI CSI/MIPI PHY component
  availability, but not active generated peripheral instances.
- `lib/fsp/ra/board/ra8p1_ek/board_ethernet_phy.h` identifies the board PHY as
  GPY111:
  - `ETHER_PHY_CFG_TARGET_GPY111_ENABLE`
  - `ETHER_PHY_LSI_TYPE_KIT_COMPONENT ETHER_PHY_LSI_TYPE_GPY111`
  - `BOARD_PHY_REF_CLK`

## Ethernet plan

Goal: provide a MicroPython-visible LAN interface, preferably compatible with
existing `network.LAN` behavior rather than creating a board-only API.

FSP/board work:

1. In e2 studio/FSP configurator, add RA8P1 Ethernet for the board path:
   - RGMII1 or the board-supported path used by EK-RA8P1.
   - GPY111 PHY.
   - `r_ether`/`r_ether_phy` or RA8P1 RMAC path if FSP selects `r_rmac`.
   - `rm_lwip_ether`.
   - bare-metal lwIP system port, not FreeRTOS.
2. Regenerate and import:
   - `ra_gen/common_data.*`
   - `ra_gen/vector_data.*`
   - `ra_cfg/fsp_cfg/r_ether*_cfg.h` or `r_rmac*_cfg.h`
   - `rm_lwip*_cfg.h`
   - pin mux updates.
3. Add Makefile gates, for example `RA8P1_ENABLE_ETHERNET ?= 0`, then include
   the FSP Ethernet, PHY, and lwIP wrapper sources only when enabled.

MicroPython work:

1. Audit `MICROPY_PY_LWIP` for EK_RA8P1 and enable only after the FSP wrapper
   compiles cleanly.
2. Add a RA Ethernet network driver binding:
   - initialize FSP Ethernet/PHY/lwIP netif
   - implement link status
   - expose DHCP/static IP
   - expose MAC address
   - poll or IRQ-drive RX/TX without FreeRTOS
3. Validate with:
   - link up/down
   - DHCP lease
   - ping both directions
   - TCP socket connect/listen from MicroPython
   - sustained RX/TX smoke test.

Risk:

- Medium. The board and FSP have the pieces, but the MicroPython RA port has
  only generic lwIP hooks, not an RA Ethernet netif driver today.

Current official-example status as of 2026-06-05:

- Official FSP 6.4.0 EK-RA8P1 Ethernet FreeRTOS+TCP hex boots and reaches RTT.
- The board path is RMAC/RGMII1 with GPY111 PHY; J-Link MDIO diagnostics show
  `ETHA1` in operation mode and PHY register reads working.
- PHY BMSR readback is `0x7949`, so link status bit 2 and auto-negotiation bit
  5 are both clear. The immediate blocker is physical Ethernet link, not the
  MicroPython network binding.

## Current official-driver validation status

- MIPI-DSI/GLCDC: original FSP driver path works after the RA8P1 safe-boot
  graphics-domain fix. `ra8p1_display.init()` succeeds without the diagnostic
  bring-up macro, and GLCDC reports enabled background output.
- MIPI-CSI/VIN: official EK-RA8P1 example works through J-Link OB VCOM. QVGA
  test pattern reports `100.00%` color-bar match, live camera mode starts, and
  VIN buffers in SDRAM contain image data.
- CEU: official EK-RA8P1 example reaches menu and captures into both SRAM/VGA
  and SDRAM/SXGA buffers, but the sample's color-bar check reports `0.00%`.
  This is now a hardware/format/debug issue, not a dead CEU driver path.
- Ethernet: official EK-RA8P1 example runs, RMAC1/MDIO reads the GPY111 PHY,
  but BMSR reports link down and auto-negotiation incomplete. This is blocked
  on physical link validation before software integration can be trusted.

## MIPI-DSI plan

Goal: support DSI display output as an alternate display path to the current
validated parallel RGB GLCDC output.

FSP/board work:

1. Fix the target panel first: exact resolution, lanes, pixel format, lane
   rate, DCS init sequence, reset/backlight pins, TE usage.
2. Add `r_mipi_dsi` and `r_mipi_phy` instances in FSP.
3. Rewire GLCDC output through DSI in the generated configuration.
4. Import generated `common_data.*`, `vector_data.*`, and MIPI config headers.
5. Add Makefile sources:
   - `r_mipi_dsi/r_mipi_dsi.c`
   - `r_mipi_phy/r_mipi_phy.c`

MicroPython work:

1. Keep the current `ra8p1_display` framebuffer API shape if possible.
2. Add a backend switch:
   - parallel RGB GLCDC, current path
   - GLCDC over DSI, new path
3. Add a low-level method for panel command/status if needed, but avoid
   exposing raw DSI unless Andy specifically needs it.

Risk:

- Medium-high. The framebuffer side is already solved, but DSI success depends
  on panel-specific timing and command sequences. Without the exact target
  panel/module, this cannot be validated meaningfully.

## MIPI-CSI plan

Goal: receive frames from a MIPI CSI camera module into a buffer accessible
from MicroPython.

FSP/board work:

1. Identify the exact sensor/module:
   - MIPI lanes
   - lane rate
   - output format, for example RAW8/RAW10/YUV/RGB
   - frame size and frame rate
   - I2C/I3C control bus and reset/power pins
2. Add `r_mipi_csi` and `r_mipi_phy` instances.
3. Add required CSI interrupts to `vector_data.*`.
4. Allocate capture buffers in SDRAM with cache/alignment handling.

MicroPython work:

1. Implement a minimal camera module:
   - `open()`
   - `configure(width, height, format)`
   - `capture([buffer])`
   - `status()`
2. Return a `memoryview` or fill a caller-provided bytearray to avoid copies.
3. Decide whether color conversion is in C, Python, or not supported initially.

Risk:

- High. CSI is sensor-specific and data-heavy. The current port has SDRAM and
  display framebuffers, but no camera buffer lifecycle or image-format API.

## CEU plan

Goal: support parallel camera capture through the Capture Engine Unit.

FSP/board work:

1. Identify the parallel camera source and signal wiring:
   - VIO_D0..D15 width used
   - VIO_CLK
   - VIO_HD/VIO_VD
   - reset/power/XCLK pins
2. Resolve pin conflicts. `ra_cfg.txt` shows many CEU functions share pins with
   SDRAM, Ethernet, GLCDC, I3C, and other board functions. This means CEU may
   require a board mode choice rather than being always-on with the current
   SDRAM/display/Ethernet layout.
3. Add `r_ceu` instance and capture interrupts.
4. Add Makefile source:
   - `r_ceu/r_ceu.c`

MicroPython work:

1. Reuse the same camera Python API as MIPI-CSI where possible.
2. Keep the first CEU milestone to a single-frame capture into SDRAM.
3. Add multi-buffer/continuous capture only after single-frame capture is
   stable.

Risk:

- High. The CEU pin mux appears to conflict with several currently useful board
  functions. Feasibility depends on the actual camera connector/module and
  which board features Andy needs simultaneously.

## Open questions for Andy

1. Which exact board/module combination is required for each peripheral?
2. For MIPI-DSI, what is the target display panel and init command sequence?
3. For MIPI-CSI, what is the target camera sensor/module and pixel format?
4. For CEU, is a parallel camera module actually required, or is MIPI-CSI the
   camera requirement?
5. For Ethernet, does Andy need plain TCP/IP sockets only, or PTP/TSN/switch
   features from RA8P1 ESWM as well?
6. Should the deliverable be MicroPython-friendly APIs, low-level FSP wrappers,
   or both?

## Suggested first implementation milestone

Start with MIPI-CSI camera capture unless Ethernet physical link is fixed first.
CSI now has the strongest board-level proof because the official driver
validates test pattern, starts live mode, and writes SDRAM buffers.

CSI first milestone:

1. Import the official MIPI-CSI/VIN/camera generated instance set into
   `boards/EK_RA8P1` behind a build gate.
2. Add the missing HAL sources and vector entries for MIPI-CSI, VIN, MIPI PHY,
   I2C camera control, and SDRAM buffer ownership.
3. Expose a minimal MicroPython camera module:
   - `open()`
   - `set_resolution("qvga" | "vga")`
   - `test_pattern()`
   - `capture()` returning a `memoryview` over SDRAM.
4. Keep color conversion out of the first milestone; return the native buffer
   format and document stride/format.

Ethernet remains the next best implementation milestone after link is proven:

1. Generate a clean EK_RA8P1 Ethernet/lwIP FSP project.
2. Import generated Ethernet instance files into this tree.
3. Add a build gate and compile with `RA8P1_ENABLE_ETHERNET=1`.
4. Bring link up and DHCP in C.
5. Expose `network.LAN` and validate MicroPython socket IO.

This gives Andy a useful advanced peripheral first and exercises the missing
class of integration work: generated FSP instance import, IRQ/vector updates,
extra HAL sources, and Python-visible driver binding.
