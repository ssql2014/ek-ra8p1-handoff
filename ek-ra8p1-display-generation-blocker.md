# EK_RA8P1 Display Generation Blocker

## Symptom

The board staging tree at:

- `/Users/alex/micropython/ports/renesas-ra/boards/EK_RA8P1`

contains:

- `configuration.xml`
- `ra_cfg.txt`
- a partial `ra_gen/`
- only `ra_cfg/fsp_cfg/bsp/*`

It does not contain the expected display-related generated config and driver outputs.

## What is already merged

The merged board configuration is not empty or display-free. It already declares display-related modules.

### In `configuration.xml`

Observed locally:

- `r_drw`
- `r_glcdc`
- `r_mipi_csi`
- `r_mipi_phy`
- `module.driver.display_on_glcdc...`
- SDRAM-backed display buffer sections such as `.sdram_noinit`

### In `ra_cfg.txt`

Observed locally:

- `Module "Graphics LCD (r_glcdc)"`
- `Instance "g_plcd_display Graphics LCD (r_glcdc)"`
- MIPI-related pins and names
- SDRAM configuration and SDRAM pinmux

## Actual blocker

This host does not have the toolchain required to turn the staged FSP metadata into full generated code:

- no Java runtime installed for this flow
- no e2 studio
- no FSP configurator / RASC generation path

So the state is:

1. display config has been staged into `configuration.xml` / `ra_cfg.txt`
2. generation was never completed on this host
3. therefore `ra_gen` and `ra_cfg/fsp_cfg` never acquired the display-specific files

## Why the example repo alone is not enough

The local `ra-fsp-examples` tree contains the EK_RA8P1 display examples, but only as source projects:

- `configuration.xml`
- `ra_cfg.txt`
- `src/*`

Those examples do not ship the generated display artifacts we need to transplant directly.

That means the next engineer must run the generation step in e2 studio / FSP 6.4.0 before any harvest can happen.

## Practical implication

Do not spend time looking for a missing hidden generated file in the example repo snapshot.

The real missing step is:

- import project
- generate FSP output
- then harvest and merge
