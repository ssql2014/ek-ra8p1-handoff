EK-RA8P1 VCOM / SCI8 bring-up handoff

Date: 2026-04-28

Current status

- Board is now back on the normal MicroPython mainline image, not the temporary LED visibility test image.
  - `boards/EK_RA8P1/mpconfigboard.h` now carries the LED bring-up switch as:
    - `#define MICROPY_RA8P1_BRINGUP_LED_TEST (0)`
  - `main.c` still contains the temporary direct-BSP LED test block, but it is now gated behind that macro and therefore disabled in the current image.
  - The latest normal image was rebuilt successfully on the remote host:
    - `build-EK_RA8P1/firmware.elf`
    - `build-EK_RA8P1/firmware.hex`
    - `build-EK_RA8P1/firmware.bin`
  - The rebuilt mainline image was flashed successfully through on-board `J-Link OB-RA4M2` and resumed.
  - This means current software work can continue on the proper MicroPython board-support path without the always-on LED dead-loop contaminating behavior.

- Display software integration status:
  - Current `ports/renesas-ra/boards/EK_RA8P1` tree does **not** contain any generated display-controller stack.
  - Direct inspection of:
    - `boards/EK_RA8P1/ra_gen`
    - `boards/EK_RA8P1/ra_cfg/fsp_cfg`
    showed no `GLCDC`, `display`, `graphics`, or LCD-related generated FSP instances.
  - This means there is no existing EK-RA8P1 display initialization path in the current MicroPython tree yet.
  - Therefore the next valid software step for display bring-up is not debugging current code; it is importing the official Renesas display sample configuration into the EK_RA8P1 board support as a new baseline.
  - That source is now confirmed locally from `renesas/ra-fsp-examples` cloned at:
    - `/Users/qlss/tmp/ra-fsp-examples`
  - Exact EK-RA8P1 display sample paths confirmed:
    - `example_projects/ek_ra8p1/_quickstart/quickstart_ek_ra8p1_ep/e2studio`
    - `example_projects/ek_ra8p1/glcdc/glcdc_ek_ra8p1_ep/e2studio`
    - `example_projects/ek_ra8p1/mipi_csi/mipi_csi_ek_ra8p1_ep/e2studio`
  - Recommended import order:
    1. `quickstart_ek_ra8p1_ep`
    2. `glcdc_ek_ra8p1_ep`
    3. `mipi_csi_ek_ra8p1_ep`
  - Minimal first-pass import manifest prepared at:
    - [ek-ra8p1-display-import-manifest.md](/Users/qlss/ek-ra8p1-display-import-manifest.md)
  - Official quickstart baseline files are now already staged into the active remote MicroPython board tree:
    - `/Users/alex/micropython/ports/renesas-ra/boards/EK_RA8P1/configuration.xml`
    - `/Users/alex/micropython/ports/renesas-ra/boards/EK_RA8P1/ra_cfg.txt`
  - This moves the display work from "source discovery" to "config inspection and generated-file import".
  - Config inspection of the staged quickstart baseline already confirms these display-path facts:
    - `r_glcdc` is present as display instance:
      - `g_plcd_display`
    - `r_mipi_csi` and `r_mipi_phy` are also present in the same baseline, but they are not required for the first solid-color display milestone.
    - `DAVE2D` is stacked under the display path in the sample baseline.
    - SDRAM is enabled and the display framebuffers are allocated in:
      - `.sdram_noinit`
    - GLCDC framebuffer layout in the sample:
      - Layer 1:
        - `fb_background`
        - `768x450`
        - `RGB565`
        - section `.sdram_noinit`
      - Layer 2:
        - `fb_foreground`
        - `1024x600`
        - `ARGB4444`
        - 2 framebuffers
        - section `.sdram_noinit`
    - Key GLCDC output signals confirmed in `configuration.xml` / `ra_cfg.txt`:
      - `LCD_CLK`: `P515`
      - `LCD_TCON0`: `P806`
      - `LCD_TCON1`: `P805`
      - `LCD_TCON2`: `P807`
      - `LCD_TCON3`: `P513`
      - `LCD_DATA0..23`: spread across `P914/P915/P903/P902/P910/P911/P912/P913/P904/P207/P112/P300/P609/P610/P611/P612/P613/P614/P615/P707/P711/P712/P713/P714/P715/P301/P302/P303/PB00..PB06`
    - Several of these LCD pins are marked in the sample with board notes such as:
      - `See SW4 in manual`
      - `Enable when connected`
    - Therefore, after generated-file import, the next likely blocker for visible pixels will be board switch/jumper state rather than missing signal assignments.
  - Current display-generation blocker:
    - official sample snapshot includes `configuration.xml` and `ra_cfg.txt`, but not generated `ra_gen/*` or `ra_cfg/fsp_cfg/*`
    - current remote environment does not expose an obvious e2studio/FSP generation CLI
    - additional broad search on the local machine and `/Users/alex` also found only project directories named `e2studio`, not an installed `e2studio.app` / `FSPConfiguration` tool
    - follow-up non-standard-path sweep (`/opt`, `/usr/local`, `/Applications`, `/Volumes`, `~/Applications`) and Spotlight-name search also came back empty
    - Renesas official docs now confirm this is expected:
      - the generator comes from the installed `FSP Platform Installer` / `e² studio`, or from installed standalone `RA Smart Configurator (RASC)`
      - it is not something bundled inside the example-project snapshot itself
      - official macOS installer names to target are:
        - `FSP macOS Platform Installer`
        - `FSP RASC macOS Installer`
      - official download entry pages are:
        - https://www.renesas.com/en/software-tool/ra-flexible-software-package-fsp
        - https://www.renesas.com/en/software-tool/e2studio-information-ra-family
      - current web check also confirms the public FSP page explicitly advertises the Apple Silicon path via `FSP RASC macOS Installer`
      - installation guide note:
        - [ek-ra8p1-fsp-install-next-step.md](/Users/qlss/ek-ra8p1-fsp-install-next-step.md)
        - includes the additional Renesas download-form entry:
          - `https://info.renesas.com/fsp`
        - current web check confirms this is a gated download form, not a direct anonymous file listing
    - blocker note:
      - [ek-ra8p1-display-generation-blocker.md](/Users/qlss/ek-ra8p1-display-generation-blocker.md)
      - [ek-ra8p1-fsp-install-next-step.md](/Users/qlss/ek-ra8p1-fsp-install-next-step.md)

- Attached display context:
  - The pictured screen is consistent with the EK-RA8P1 kit's included `7.0-inch, 1024x600 parallel LCD board`.
  - It is part of the graphics expansion hardware path, not something the current UART/VCOM or LED test image will light automatically.
  - Therefore, with the board currently flashed with the LED visibility test image, the display is expected to remain dark.
  - The next valid path to light the display is to switch from the current LED test image to an official Renesas display sample / graphics sample that configures the display controller and panel path.
  - External references that make this practical:
    - Renesas board page says the kit includes the `7.0-inch, 1024x600 parallel LCD board`.
    - Renesas community confirms the official EK-RA8P1 camera/LCD example works on real hardware.
    - Quick Start Guide notes the display path needs significant current; use a root host USB port or powered hub.
    - Renesas community also has a real-world "whole white LCD" case resolved by reseating the FFC and locking the connector properly.
  - Official sample names / paths to use next:
    - `quickstart_ek_ra8p1_ep` (Quick Start example; docs explicitly say to use its `Debug_Flat` build)
    - `glcdc_ek_ra8p1_ep` (known-good GLCDC configuration reference; Renesas support explicitly recommended copying its `.xml` when a user could not get basic LCD working)
    - `mipi_csi_ek_ra8p1_ep/e2studio` (Renesas community reports this official camera/LCD example works on real EK-RA8P1 hardware)
  - Source links confirmed:
    - Quick Start Guide: `quickstart_ek_ra8p1_ep Debug_Flat`
    - Renesas community "whole white LCD" thread points to `quickstart_ek_ra8p1_ep` and says `SW4` should be all `OFF`
    - Same thread reports one real fix was re-seating the LCD FFC and fully closing the connector lock
    - Renesas community "Trouble getting basic LCD functionality" thread points to `mipi_csi_ek_ra8p1_ep/e2studio` as known-good real hardware example
  - Known physical conditions from official/community references:
    - for the quickstart example, community support said `SW4` should be all `OFF`
    - if the panel goes all-white, first re-seat the LCD FFC and confirm the connector lock is fully closed

- Prior Andy / Renesas reply already read and absorbed:
  - RA8P1 peripherals in scope can follow official examples
  - those peripherals are considered compatible on RA8P1
  - recommended FSP version: `6.4.0`
  - storage recommendation: `external OSPI flash`
  - integration recommendation: direct wrapping of FSP drivers
  - board reference path: `FSP -> BSP -> Board -> EK-RA8P1`
- Previous reply metadata:
  - From: `feng.chen.kc@renesas.com`
  - Subject: `RE: EK-RA8P1 technical alignment questions`

- Startup/runtime blockers were fixed earlier:
  - `g_init_info` / `.bss/.data` init fixed
  - main stack moved out of `.bss`
  - system reaches `main()`, REPL path, and idle/WFI
- REPL UART routing corrected from wrong `SCI6/P301/P302` assumption to official board VCOM route:
  - `SCI8`
  - `PD02` = TX
  - `PD03` = RX
- External engineer feedback:
  - RA8P1 has multiple UART/SCI channels, but other UART validation paths require separate wiring.
  - This is consistent with current conclusion that on-board J-Link VCOM is tied to the `SCI8` / `PD02` / `PD03` path, not arbitrary UARTs.
- Technical escalation contact provided by user:
  - `changhao.li@iseentech.com`
  - Use this contact for technical questions if external clarification is needed.
  - Draft prepared at:
    - [ek-ra8p1-changhao-email-draft.md](/Users/qlss/ek-ra8p1-changhao-email-draft.md)
  - Compact evidence summary prepared at:
    - [ek-ra8p1-changhao-evidence-summary.md](/Users/qlss/ek-ra8p1-changhao-evidence-summary.md)
  - Sent successfully via `lily2@iseentech.com` using `smtp.exmail.qq.com:465`
  - IMAP sent-folder confirmation:
    - Folder: `Sent Messages`
    - Date: `Wed, 29 Apr 2026 11:30:23 +0800`
    - From: `lily2@iseentech.com`
    - To: `changhao.li@iseentech.com`
    - Subject: `EK-RA8P1 SCI_B8 VCOM path and internal loopback question`

- Latest `lily2` inbox baseline checked:
  - No new Andy / Renesas reply after:
    - `From: Feng Chen <feng.chen.kc@renesas.com>`
    - `Subject: RE: EK-RA8P1 technical alignment questions`
    - `Date: Tue, 28 Apr 2026 09:52:02 +0000`
  - Rechecked again on `2026-04-29`; inbox still has only 3 relevant matches:
    - Feng Chen old reply
    - Changhao first reply
    - Changhao second reply

- New reply received from Changhao:
  - From: `李昌壕 <changhao.li@iseentech.com>`
  - Subject: `回复：EK-RA8P1 SCI_B8 VCOM path and internal loopback question`
  - Date: `Wed, 29 Apr 2026 11:48:57 +0800`
  - Key points:
    - `RA8P1 SCI_B UART` does **not** support internal loopback / self-test mode
    - no additional board-side condition is required for VCOM beyond the documented route
    - no special limitation / requirement for `SCI_B8`
    - `PD02 <-> PD03` should **not** be shorted on EK-RA8P1 because they are already connected to J-Link Virtual COM
  - Interpretation:
    - this reply resolved several dead-end branches,
    - but it did **not** identify the final root cause of why J-Link Virtual COM still produces `UART_BYTES 0` on the host.

- New SEGGER-side lead:
  - SEGGER official docs say J-Link / J-Link OB VCOM can be enabled or disabled independently of target firmware.
  - Relevant Commander command is `VCOM Enable` / `VCOM Disable`.
  - After changing VCOM state, SEGGER requires disconnecting and reconnecting the probe so the CDC interface re-enumerates on the host.
  - This is now a high-value external-chain branch because:
    - official Renesas `SCI8/PD02/PD03/115200` example also produced zero host-visible bytes
    - Changhao ruled out internal loopback and extra board-side UART conditions
    - MCU-side `SCI_B8` open / write / TXI ISR / final `PFS` are already proven
  - Executed on remote host with extracted SEGGER `JLinkExe` from cached V9.38a package:
    - `JLink> VCOM enable`
    - probe detected as `J-Link OB-RA4M2`, serial `1080244894`
  - Remaining blocker:
    - SEGGER says this takes effect only after probe power-cycle / USB reconnect
  - Prepared post-replug verification helper:
    - [ek-ra8p1-check-vcom-after-replug.sh](/Users/qlss/ek-ra8p1-check-vcom-after-replug.sh)
    - It reconnects to the remote Mac, opens `/dev/cu.usbmodem*` at `115200 8N1`, and prints `UART_NODE`, `UART_BYTES`, `UART_HEX`, and `UART_ASCII`.
  - Latest validation run after `VCOM enable` still showed:
    - `UART_NODE /dev/cu.usbmodem0010802448941`
    - `UART_BYTES 0`
  - Interpretation:
    - either the required physical probe/USB power-cycle did not actually happen yet,
    - or VCOM being enabled was not the root cause and the external J-Link CDC path is still the blocker.
  - After a real power-cycle / replug reported by the user, re-check still showed:
    - `UART_NODE /dev/cu.usbmodem0010802448941`
    - `UART_BYTES 0`
  - So `VCOM enable` + actual replug still did not restore host-visible UART data.
  - New board-side checkpoints from Renesas docs:
    - Quick Start Guide notes that debug LED `LED5` keeps blinking when J-Link drivers are not detected by the EK-RA8P1.
    - Default J-Link OB jumper baseline from EK-RA8P1 user manual:
      - `J6`: pins `2-3`
      - `J8`: pins `1-2`
      - `J9`: pins `2-3`
      - `J29`: pins `1-2`, `3-4`, `5-6`, `7-8`
    - These are now the highest-value physical checks if `UART_BYTES` stays zero after a real USB/probe replug.
  - Additional Renesas community clue:
    - In an EK-RA8P1 thread about a Baby Crying demo with "no UART debug output", Renesas support first asked to verify `SW4-5 = OFF` so I2C is enabled.
    - This is demo-specific rather than a proven VCOM root cause, but it shows board-side switch state can affect the observed bring-up behavior and should be checked if that demo path is revisited.
  - Condensed field checklist prepared:
    - [ek-ra8p1-physical-vcom-checklist.md](/Users/qlss/ek-ra8p1-physical-vcom-checklist.md)
- `SCI_B8` path now uses FSP `R_SCI_B_UART_Open()` and IRQ vectors are present in final image.
- TX software path is proven alive:
  - `ra_sci_tx_ch()` hit with `R0=8`, `R1=0x4D`
  - `sci_b_uart_txi_isr` hit
- Runtime pinmux is correct:
  - `PD02 PFS = 0x04010006`
  - `PD03 PFS = 0x04010C02`

Most important negative result

- Renesas official prebuilt EK-RA8P1 example that uses `SCI8/PD02/PD03/115200` also produced zero host-visible bytes on `/dev/cu.usbmodem0010802448941`.
- Therefore the current blocker is no longer attributable only to the MicroPython firmware tree.

Host-side serial node

- Correct external CDC node on remote Mac:
  - `/dev/cu.usbmodem0010802448941`
- Confirmed to belong to SEGGER J-Link OB serial:
  - USB serial number `001080244894`

Current special test firmware on board

- `main.c` currently contains a temporary local loopback probe for RA8P1:
  - sends bytes: `55 AA 33 CC 4C 4F 4F 50`
  - polls RX for up to `500 ms`
  - then stops in `for (;; nop)`
- Build succeeded and was flashed.

Relevant RAM symbols in current image

- `ra8p1_loop_tx      = 0x2200000c`
- `ra8p1_loop_errcode = 0x22000d00`
- `ra8p1_loop_elapsed_ms = 0x22000d04`
- `ra8p1_loop_rx_count = 0x22000d08`
- `ra8p1_loop_rx      = 0x22000d0c`

Latest observed loopback result

- `errcode = 0`
- `elapsed = 500 ms`
- `rx_count = 0`
- `rx buffer = all 0`

Interpretation

- If `PD02` and `PD03` were NOT physically shorted, this result is expected and proves nothing about UART RX.
- If `PD02` and `PD03` WERE physically shorted, then local UART loopback failed and the problem is still on the MCU UART side.

Important conclusion

- No usable internal `SCI_B` loopback mode was found in:
  - `r_sci_b_uart`
  - RA8P1 `SCI_B` register bit definitions
- So the next decisive test is physical, not another firmware tweak.

Next action

1. Physically short `PD02 <-> PD03`.
2. Re-run J-Link halt and read:
   - `0x22000d00` x3 as 32-bit
   - `0x22000d0c` as bytes
3. Decision:
   - `rx_count > 0`: MCU UART is fine, issue is board VCOM / U7 / host chain.
   - `rx_count = 0`: issue remains in `SCI8` local UART path.
4. Only after this decision point:
   - either pursue board-side VCOM / U7 / host-chain debugging,
   - or prepare a focused technical question set for `changhao.li@iseentech.com`.

Useful commands

- Flash current image:
  - `JLinkExe -NoGui 1 -CommandFile ...` with device `R7KA8P1KF_CPU0`
- Read loopback state:
  - `mem32 0x22000d00 3`
  - `mem8  0x22000d0c 16`
## 2026-04-29 LED direct-BSP blink update

- Board is now running a temporary LED visibility test image, not the normal customer MicroPython image.
- Previous MicroPython LED path was partly blocked by board pin generation:
  - `MICROPY_HW_LED3` originally pointed to `pin_PA07`
  - build failed because `pin_PA07` was not generated as a MicroPython pin object
- To bypass that and isolate board visibility, the test image was changed to drive official EK-RA8P1 LED GPIOs directly via BSP `R_IOPORT_PinWrite()` in `main.c`.
- Directly driven pins:
  - `P600`
  - `P303`
  - `PA07`
- Flash status:
  - rebuilt `build-EK_RA8P1/firmware.hex`
  - flashed via J-Link OB successfully
  - J-Link reported `Contents already match`
  - target was reset and resumed

Current meaning:

- If the three user LEDs still show no visible activity, the problem is no longer in the MicroPython LED macro/object chain.
- Remaining suspicion moves lower:
  - actual board LED polarity/behavior
  - whether the observed LEDs are the correct three user LEDs
  - deeper board power/reset/visibility issue

### Runtime GPIO proof

- The temporary image was halted twice while running in the direct-BSP LED loop (`PC = 0x0200FED0` both times).
- Port register samples changed between the two halts, which proves firmware is actively toggling the LED GPIO outputs:
  - Port 3 (`P303`) @ `0x40400060`
    - sample A: `00080008 0000F10F`
    - sample B: `00000008 0000F107`
  - Port 6 (`P600`) @ `0x404000C0`
    - sample A: `00000001 0000FEFE`
    - sample B: `00010001 0000FEFF`
  - Port A (`PA07`) @ `0x40400140`
    - sample A: `00000080 00007F10`
    - sample B: `00800080 00007FB0`

Meaning:

- The MCU is definitely running.
- The firmware is definitely toggling the three intended LED GPIO pins.
- If no visible LED activity is observed on the board, the remaining issue is board-visible behavior, polarity, or LED identification, not the firmware control path.

### Official LED board-side condition

- Official EK-RA8P1 documentation maps:
  - `LED1` (Blue) -> `P600`
  - `LED2` (Green) -> `P303`
  - `LED3` (Red) -> `PA07`
- The same documentation shows board-side trace-cut jumpers:
  - `E27`: `LED1 <-> P600`
  - `E26`: `LED2 <-> P303`
  - `E28`: `LED3 <-> PA07`

Meaning:

- Even if firmware is toggling the correct GPIOs, the LEDs will remain dark if `E26/E27/E28` are open.

## 2026-04-29 EK_RA8P1 pin generation cleanup

- Root cause of the earlier `LED3` build break was confirmed to be a board pin list omission:
  - `boards/EK_RA8P1/pins.csv` had `PDxx` entries, but no `PAxx` entries
  - `make-pins.py` already supports `PXNN` names, including `PA07`
- Software fix applied:
  - inserted `PA00..PA15` into `boards/EK_RA8P1/pins.csv`
  - restored `boards/EK_RA8P1/mpconfigboard.h` to the correct definition:
    - `#define MICROPY_HW_LED3 (pin_PA07)`
- Clean build result:
  - `build-EK_RA8P1/firmware.elf`
  - `build-EK_RA8P1/firmware.hex`
  - `build-EK_RA8P1/firmware.bin`
  all regenerated successfully after the pin-list fix
- Post-fix generation proof:
  - `build-EK_RA8P1/genhdr/pins.h` now contains `#define pin_PA07 (&pin_PA07_obj)`
  - `build-EK_RA8P1/pins_EK_RA8P1.c` now exports `PA07`

Meaning:

- The EK-RA8P1 board support is back on the proper MicroPython pin-object path for `LED3`.
- The previous temporary `pin_P303` placeholder in `mpconfigboard.h` is no longer needed.
