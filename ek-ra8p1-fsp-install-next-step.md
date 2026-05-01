# EK_RA8P1 FSP Install Next Step

## Why this step exists

The current blocker is not lack of XML content. The blocker is that this host has no working FSP generation environment.

The board tree already has staged:

- `configuration.xml`
- `ra_cfg.txt`

But it cannot turn those into the missing display-generated files without the Renesas tooling.

## Minimum tool requirement

Provision a machine with:

- Java runtime compatible with e2 studio / FSP tooling
- Renesas e2 studio
- FSP 6.4.0 support matching the staged board config

Target part already staged:

- `R7KA8P1KFLCAC`

## Immediate next step

On the machine that can run the tooling:

1. install Java if missing
2. install e2 studio with FSP 6.4.0 support
3. import:
   - `/Users/alex/ra-fsp-examples/example_projects/ek_ra8p1/mipi_dsi/mipi_dsi_ek_ra8p1_ep/e2studio/configuration.xml`
   - `/Users/alex/ra-fsp-examples/example_projects/ek_ra8p1/glcdc/glcdc_ek_ra8p1_ep/e2studio/configuration.xml`
4. run code generation for each
5. export or copy the generated output trees for harvest

## Follow-up after generation

Once generation works, compare the generated trees against:

- `/Users/alex/micropython/ports/renesas-ra/boards/EK_RA8P1/ra_gen`
- `/Users/alex/micropython/ports/renesas-ra/boards/EK_RA8P1/ra_cfg/fsp_cfg`

The expected result is the appearance of the currently missing display-specific outputs.

## Sanity check before spending more time

If e2 studio imports the XML and still refuses to generate display artifacts, then the next debugging axis is:

- mismatched configurator version
- missing display middleware pack
- import corruption between the merged board XML and the example XML

But that is the second-order problem. The first-order problem right now is simply that generation tooling is absent.
