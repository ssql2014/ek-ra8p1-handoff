EK-RA8P1 display integration plan

Date: 2026-04-29

Current fact

- The current MicroPython EK_RA8P1 board support has no display stack configured.
- Remote inspection showed:
  - `boards/EK_RA8P1/ra_gen`
  - `boards/EK_RA8P1/ra_cfg/fsp_cfg`
  contain no `GLCDC`, `display`, `graphics`, `MIPI`, or LCD-related generated FSP instances.
- So there is nothing meaningful to "fix" in-place for display yet.
- The official quickstart display baseline has now been staged into the MicroPython board directory on the remote host as source-of-truth inputs:
  - `boards/EK_RA8P1/configuration.xml`
  - `boards/EK_RA8P1/ra_cfg.txt`

Implication

- Display bring-up must start by importing a known-good Renesas sample configuration, not by patching the current EK_RA8P1 MicroPython files blindly.

Recommended source order

1. `quickstart_ek_ra8p1_ep`
- Best first reference because it is explicitly tied to EK-RA8P1 and its attached LCD path.

2. `glcdc_ek_ra8p1_ep`
- Best configuration reference for the display controller itself.

3. `mipi_csi_ek_ra8p1_ep/e2studio`
- Good cross-check for a known working camera/LCD pipeline on the same hardware family.

Exact source paths confirmed locally

The official `renesas/ra-fsp-examples` repository was cloned locally at:
- `/Users/qlss/tmp/ra-fsp-examples`

Confirmed EK-RA8P1 display sample projects:

1. Quickstart
- `/Users/qlss/tmp/ra-fsp-examples/example_projects/ek_ra8p1/_quickstart/quickstart_ek_ra8p1_ep/e2studio`
- Key files:
  - `configuration.xml`
  - `ra_cfg.txt`
  - `src/display_thread_entry.c`
  - `src/display_thread_entry.h`
  - `src/menu_lcd.c`
  - `src/menu_lcd.h`
  - `src/board_hw_cfg.c`
  - `src/board_hw_cfg.h`
  - `src/hal_entry.c`

2. GLCDC-only reference
- `/Users/qlss/tmp/ra-fsp-examples/example_projects/ek_ra8p1/glcdc/glcdc_ek_ra8p1_ep/e2studio`
- Key files:
  - `configuration.xml`
  - `ra_cfg.txt`
  - `src/glcdc_ep.h`
  - `src/hal_entry.c`

3. MIPI CSI + display reference
- `/Users/qlss/tmp/ra-fsp-examples/example_projects/ek_ra8p1/mipi_csi/mipi_csi_ek_ra8p1_ep/e2studio`
- Key files:
  - `configuration.xml`
  - `ra_cfg.txt`
  - `src/glcdc_display.c`
  - `src/glcdc_display.h`
  - `src/mipi_csi.c`
  - `src/mipi_csi.h`
  - `src/hal_entry.c`

Import targets inside MicroPython board support

1. `boards/EK_RA8P1/ra_gen`
- expected future additions:
  - display-related generated `hal_data.c/.h`
  - display vectors if used
  - generated pin data for LCD/GLCDC signals

2. `boards/EK_RA8P1/ra_cfg/fsp_cfg`
- expected future additions:
  - display-related FSP config headers
  - board/BSP options required by the graphics path

3. `boards/EK_RA8P1/configuration.xml`
- expected new source of truth for re-generation

4. MicroPython glue layer
- decide later whether first milestone is:
  - only panel clear / splash test
  - or a minimal framebuffer exposed to MicroPython

First milestone

- Do not try to expose Python APIs yet.
- First get a minimal C-side display init path that:
  - powers up the official panel path
  - enables the display controller
  - paints a known solid color or pattern

What is already solved and does not block this

- EK_RA8P1 pin generation cleanup for `PA07`
- LED temporary bring-up block is now gated off by:
  - `MICROPY_RA8P1_BRINGUP_LED_TEST (0)`
- Mainline MicroPython build/flash path is healthy enough to continue software work

Next concrete software task

- Obtain one official EK-RA8P1 display sample project and extract:
  - generated FSP files
  - configuration XML
  - LCD-related pin assignments
  - display init entry points
- Then stage those into a branchable EK_RA8P1 display baseline inside MicroPython.

Immediate recommended baseline

- Start from:
  - `quickstart_ek_ra8p1_ep/e2studio/configuration.xml`
- Cross-check against:
  - `glcdc_ek_ra8p1_ep/e2studio/configuration.xml`
- Use `mipi_csi_ek_ra8p1_ep` only as a secondary source for:
  - `glcdc_display.c/.h`
  - camera/display interaction patterns

Minimal import scope is now split out explicitly in:
- [ek-ra8p1-display-import-manifest.md](/Users/qlss/ek-ra8p1-display-import-manifest.md)

Status after staging

- The following two files are already copied into the active remote MicroPython board tree:
  - `/Users/alex/micropython/ports/renesas-ra/boards/EK_RA8P1/configuration.xml`
  - `/Users/alex/micropython/ports/renesas-ra/boards/EK_RA8P1/ra_cfg.txt`
- This means the next display task is no longer "find source files".
- The next display task is:
  - inspect those staged quickstart configs,
  - identify the exact generated display modules/pins they imply,
  - and import/regenerate the matching `ra_gen` / `ra_cfg/fsp_cfg` display support into the MicroPython board tree.

Current blocker

- The official sample snapshot does not include generated:
  - `ra_gen/*`
  - `ra_cfg/fsp_cfg/*`
- The current remote environment also does not expose an obvious FSP/e2studio generation CLI.
- Blocker summary is captured in:
  - [ek-ra8p1-display-generation-blocker.md](/Users/qlss/ek-ra8p1-display-generation-blocker.md)
