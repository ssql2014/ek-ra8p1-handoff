# EK_RA8P1 Display Integration Plan

## Objective

Complete the display/FSP side of the EK_RA8P1 MicroPython board by generating and importing the display-related FSP output that is currently missing from the board tree.

Destination tree:

- `/Users/alex/micropython/ports/renesas-ra/boards/EK_RA8P1`

## Source-of-truth split

Use the Renesas examples with this division of responsibility:

### MIPI DSI example = primary source

Use:

- `/Users/alex/ra-fsp-examples/example_projects/ek_ra8p1/mipi_dsi/mipi_dsi_ek_ra8p1_ep/e2studio`

This is the primary reference for:

- display bring-up flow
- MIPI physical/link configuration
- touch controller support
- SDRAM-backed image buffers

### GLCDC example = secondary source

Use:

- `/Users/alex/ra-fsp-examples/example_projects/ek_ra8p1/glcdc/glcdc_ek_ra8p1_ep/e2studio`

This is the supporting reference for:

- GLCDC timing/layer settings
- framebuffer placement
- display stack defaults

## Recommended execution order

1. Install or provision e2 studio + FSP 6.4.0 on a machine that can run the generator.
2. Import the MIPI DSI EK_RA8P1 example first.
3. Generate code and capture the full generated tree.
4. Import the GLCDC EK_RA8P1 example second.
5. Generate code and diff it against the MIPI output to identify the display-related overlap.
6. Compare both generated outputs against the current MicroPython `EK_RA8P1` board tree.
7. Merge only the display-relevant generated files into the MicroPython board.
8. Rebuild MicroPython for `BOARD=EK_RA8P1`.
9. Only after generated artifacts are stable, wire or adapt any app-side display/touch code.

## Merge rules

Treat these as configuration-generated artifacts that should come from FSP generation, not manual reinvention:

- `ra_gen/hal_data.c`
- `ra_gen/hal_data.h`
- `ra_gen/common_data.c`
- `ra_gen/common_data.h`
- `ra_gen/pin_data.c`
- `ra_gen/vector_data.c`
- `ra_gen/vector_data.h`
- `ra_gen/bsp_pin_cfg.h`
- `ra_cfg/fsp_cfg/*`

Treat these as app/reference code that may need selective porting, not blind copying:

- `src/mipi_dsi_ep.c`
- `src/mipi_dsi_ep.h`
- `src/gt911.c`
- `src/gt911.h`
- `src/glcdc_ep.h`
- `src/common_utils.h`
- `src/hal_entry.c`

## What not to do

- Do not assume the example repo already contains the ready-made generated display artifacts.
- Do not manually fabricate display `ra_cfg/fsp_cfg` headers if generation can be run properly.
- Do not treat the current absence of generated display files as evidence that the merged XML is wrong; the XML already contains display modules.

## Success condition

This track is complete when:

1. `ra_gen` and `ra_cfg/fsp_cfg` contain the display-related generated outputs
2. the MicroPython EK_RA8P1 board builds with those artifacts
3. display/touch code can proceed against generated headers and instances instead of guessed placeholders
