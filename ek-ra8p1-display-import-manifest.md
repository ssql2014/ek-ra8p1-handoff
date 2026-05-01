# EK_RA8P1 Display Import Manifest

## Goal

Generate the missing display-related FSP output for the MicroPython board tree at:

- `/Users/alex/micropython/ports/renesas-ra/boards/EK_RA8P1`

The local board already has merged display declarations in `configuration.xml` and `ra_cfg.txt`, but the generated display files are absent from `ra_gen/` and `ra_cfg/fsp_cfg/`.

## Primary harvest sources

Use these two example projects as the reference source of truth:

### 1. MIPI DSI example

- `/Users/alex/ra-fsp-examples/example_projects/ek_ra8p1/mipi_dsi/mipi_dsi_ek_ra8p1_ep/e2studio/configuration.xml`
- `/Users/alex/ra-fsp-examples/example_projects/ek_ra8p1/mipi_dsi/mipi_dsi_ek_ra8p1_ep/e2studio/ra_cfg.txt`
- `/Users/alex/ra-fsp-examples/example_projects/ek_ra8p1/mipi_dsi/mipi_dsi_ek_ra8p1_ep/e2studio/src/mipi_dsi_ep.c`
- `/Users/alex/ra-fsp-examples/example_projects/ek_ra8p1/mipi_dsi/mipi_dsi_ek_ra8p1_ep/e2studio/src/mipi_dsi_ep.h`
- `/Users/alex/ra-fsp-examples/example_projects/ek_ra8p1/mipi_dsi/mipi_dsi_ek_ra8p1_ep/e2studio/src/gt911.c`
- `/Users/alex/ra-fsp-examples/example_projects/ek_ra8p1/mipi_dsi/mipi_dsi_ek_ra8p1_ep/e2studio/src/gt911.h`
- `/Users/alex/ra-fsp-examples/example_projects/ek_ra8p1/mipi_dsi/mipi_dsi_ek_ra8p1_ep/e2studio/src/common_utils.h`
- `/Users/alex/ra-fsp-examples/example_projects/ek_ra8p1/mipi_dsi/mipi_dsi_ek_ra8p1_ep/e2studio/src/hal_entry.c`

Use this as the main source for:

- panel bring-up
- MIPI PHY / DSI configuration
- touch controller reference code
- SDRAM-backed display buffers

### 2. GLCDC example

- `/Users/alex/ra-fsp-examples/example_projects/ek_ra8p1/glcdc/glcdc_ek_ra8p1_ep/e2studio/configuration.xml`
- `/Users/alex/ra-fsp-examples/example_projects/ek_ra8p1/glcdc/glcdc_ek_ra8p1_ep/e2studio/ra_cfg.txt`
- `/Users/alex/ra-fsp-examples/example_projects/ek_ra8p1/glcdc/glcdc_ek_ra8p1_ep/e2studio/src/glcdc_ep.h`
- `/Users/alex/ra-fsp-examples/example_projects/ek_ra8p1/glcdc/glcdc_ek_ra8p1_ep/e2studio/src/common_utils.h`
- `/Users/alex/ra-fsp-examples/example_projects/ek_ra8p1/glcdc/glcdc_ek_ra8p1_ep/e2studio/src/hal_entry.c`

Use this as the supporting source for:

- GLCDC timing and layer properties
- framebuffer section placement
- related display stack defaults

## Important constraint

The example repositories do not include the generated display output we need to harvest.

They contain:

- `configuration.xml`
- `ra_cfg.txt`
- app-side `src/*`

They do not contain a ready-made generated display tree under `ra_gen/` or `ra_cfg/fsp_cfg/*`.

So the actual workflow is:

1. import the example config into e2 studio / FSP 6.4.0
2. run code generation
3. harvest the newly generated files
4. merge the generated files back into the MicroPython board tree

## Expected generated outputs to harvest

After a successful import + generate step, harvest the display-related outputs from the generated project into the MicroPython board tree.

At minimum inspect and compare:

- `ra_gen/hal_data.c`
- `ra_gen/hal_data.h`
- `ra_gen/common_data.c`
- `ra_gen/common_data.h`
- `ra_gen/pin_data.c`
- `ra_gen/vector_data.c`
- `ra_gen/vector_data.h`
- `ra_gen/bsp_pin_cfg.h`
- `ra_gen/bsp_api.h`
- `ra_gen/bsp_clock_cfg.h`

And the non-BSP FSP config headers that are currently missing from the board:

- `ra_cfg/fsp_cfg/*.h`
- `ra_cfg/fsp_cfg/*/*` if the generator creates subtrees beyond `bsp/`

## Current board evidence

The local board config already shows display content is present logically:

- `configuration.xml` contains:
  - `r_drw`
  - `r_glcdc`
  - `r_mipi_csi`
  - `r_mipi_phy`
  - `module.driver.display_on_glcdc...`
- `ra_cfg.txt` contains:
  - `Module "Graphics LCD (r_glcdc)"`
  - `Instance "g_plcd_display Graphics LCD (r_glcdc)"`
  - SDRAM-backed display buffer sections

This is why the missing piece is generation, not source discovery.
