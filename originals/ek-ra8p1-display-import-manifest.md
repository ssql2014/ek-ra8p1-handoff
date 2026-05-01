EK-RA8P1 display import manifest

Date: 2026-04-29

Goal

- Import the smallest useful display baseline from official Renesas EK-RA8P1 examples into the current MicroPython board support.
- Do not pull in camera, touch, menu, or full demo UI on the first pass.

Confirmed source roots

1. Quickstart
- `/Users/qlss/tmp/ra-fsp-examples/example_projects/ek_ra8p1/_quickstart/quickstart_ek_ra8p1_ep/e2studio`

2. GLCDC
- `/Users/qlss/tmp/ra-fsp-examples/example_projects/ek_ra8p1/glcdc/glcdc_ek_ra8p1_ep/e2studio`

3. MIPI CSI
- `/Users/qlss/tmp/ra-fsp-examples/example_projects/ek_ra8p1/mipi_csi/mipi_csi_ek_ra8p1_ep/e2studio`

Minimal first-pass import set

Use as primary baseline:

- `quickstart ... /configuration.xml`
- `quickstart ... /ra_cfg.txt`
- `quickstart ... /src/display_thread_entry.c`
- `quickstart ... /src/display_thread_entry.h`
- `quickstart ... /src/board_hw_cfg.c`
- `quickstart ... /src/board_hw_cfg.h`
- `quickstart ... /src/common_init.c`
- `quickstart ... /src/common_init.h`
- `quickstart ... /src/hal_entry.c`

Use as GLCDC cross-check:

- `glcdc ... /configuration.xml`
- `glcdc ... /ra_cfg.txt`
- `glcdc ... /src/glcdc_ep.h`
- `glcdc ... /src/hal_entry.c`

Second-pass optional files

- `quickstart ... /src/menu_lcd.c`
- `quickstart ... /src/menu_lcd.h`

These are useful for understanding panel drawing flow, but they are not required for the first milestone if the goal is only a solid-color or test-pattern screen.

Do not import in first pass

- `camera_thread_entry.c`
- `ov5640*`
- `touch_FT5316*`
- `tp_thread_entry*`
- `menu_*`
- `images/*`
- `mipi_csi.c`
- `glcdc_display.c`

Reason:

- They add camera, touch, demo UI, or asset baggage.
- First milestone should be only:
  - power panel path
  - initialize display controller
  - paint known framebuffer pattern

Expected MicroPython integration targets

1. Board configuration source of truth
- `boards/EK_RA8P1/configuration.xml` (new file to introduce)

2. Generated board support
- `boards/EK_RA8P1/ra_gen/*`
- `boards/EK_RA8P1/ra_cfg/fsp_cfg/*`

3. Minimal C glue
- a new focused display bring-up source, likely under:
  - `boards/EK_RA8P1/`
  - or `ra/`

First milestone definition

- Build and flash MicroPython with display init compiled in.
- Before any Python exposure:
  - initialize display path
  - show a solid color or simple pattern

Only after that

- consider exposing framebuffer or drawing APIs to Python
