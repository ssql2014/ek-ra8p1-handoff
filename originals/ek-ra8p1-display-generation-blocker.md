EK-RA8P1 display generation blocker

Date: 2026-04-29

Confirmed facts

1. Official sample files staged
- Remote MicroPython board tree now contains:
  - `/Users/alex/micropython/ports/renesas-ra/boards/EK_RA8P1/configuration.xml`
  - `/Users/alex/micropython/ports/renesas-ra/boards/EK_RA8P1/ra_cfg.txt`

2. Official sample snapshot does not include generated FSP outputs
- In:
  - `/Users/qlss/tmp/ra-fsp-examples/example_projects/ek_ra8p1/_quickstart/quickstart_ek_ra8p1_ep/e2studio`
- present:
  - `configuration.xml`
  - `ra_cfg.txt`
  - `src/*`
- not present:
  - `ra_gen/*`
  - `ra_cfg/fsp_cfg/*`

3. Current remote environment does not expose a direct generator CLI
- No visible `e2studio`
- No visible `FSPConfiguration`
- Repository build system consumes `ra_gen` / `ra_cfg/fsp_cfg`, but does not generate them from XML by itself

4. Broad local search still did not find an installed FSP generation tool
- Searched:
  - `/Applications`
  - `/Users/qlss`
  - `/Users/alex`
- Search methods used:
  - `find ... -iname 'e2studio*.app'`
  - `find ... -iname 'FSPConfiguration*'`
  - `mdfind` for `e2studio`, `FSPConfiguration`, and `Renesas`
- Results only surfaced:
  - example-project directories named `e2studio`
  - cloned `ra-fsp-examples` content
- Results did **not** surface:
  - an actual `e2studio.app`
  - a visible `FSPConfiguration` app or CLI
  - another obvious installed generator entry point
- Additional non-standard-path sweep was also empty:
  - searched `/opt`, `/usr/local`, `/Applications`, `/Volumes`, and `~/Applications`
  - searched Spotlight display names for:
    - `e2 studio`
    - `RA Smart Configurator`
    - `FSP Platform Installer`
    - `FSPConfiguration`
  - no installed tool entry point was found

5. Official Renesas docs confirm the generator comes from the installer, not from the sample tree
- Renesas RA FSP page says the supported installation paths are:
  - `FSP Platform Installer` (includes `e² studio`, toolchain, and FSP packs)
  - `RA Smart Configurator (RASC) Installer` for 3rd-party IDE use
- Renesas RA Smart Configurator page says:
  - `You need to download the platform installer included FSP to use RA Smart Configurator`
- FSP documentation says:
  - FSP is integrated into `e² studio`
  - the `RA Configuration editor` is available in `e² studio` and through standalone `RA Smart Configurator`
- Therefore the missing piece is not hidden in the example repo; it is an uninstalled Renesas toolchain/configuration package.
- Official download entry points now confirmed:
  - RA FSP page exposes:
    - `FSP MacOS Platform Installer`
    - `FSP RASC macOS Installer`
  - RA-family e² studio page says:
    - download the RA platform installer from the `Latest (macOS)` entry
    - install FSP with e² studio on macOS is an officially supported flow
  - Web search result confirms the public FSP page explicitly lists:
    - `For macOS (Apple Silicon) download: FSP RASC macOS Installer`

Official sources

- `e² studio - information for RA Family`:
  - https://www.renesas.com/en/software-tool/e2studio-information-ra-family
- `RA Flexible Software Package (FSP)`:
  - https://www.renesas.com/en/software-tool/ra-flexible-software-package-fsp
- `RA Smart Configurator`:
  - https://www.renesas.com/en/software-tool/ra-smart-configurator
- `FSP Starting Development`:
  - https://renesas.github.io/fsp/_s_t_a_r_t__d_e_v.html

Implication

- Display bring-up cannot proceed to compiled `GLCDC` integration by file copy alone.
- The next required step is to regenerate display-enabled:
  - `ra_gen/*`
  - `ra_cfg/fsp_cfg/*`
from the staged `configuration.xml`, using one of:
  - an installed `FSP Platform Installer` / `e² studio` environment
  - an installed standalone `RA Smart Configurator (RASC)` environment

What is still useful right now

- We already extracted the baseline facts:
  - `g_plcd_display`
  - `GLCDC`
  - `SDRAM`
  - framebuffer sections and sizes
  - timing/data pin assignments
- So once generation tooling is available, import scope is already well bounded.

Recommended next step

1. Use an e2studio/FSP-capable machine to open:
   - `boards/EK_RA8P1/configuration.xml`
   - or install one of the official macOS tools on this machine first:
     - `FSP macOS Platform Installer`
     - `FSP RASC macOS Installer`
2. Generate:
   - `ra_gen/*`
   - `ra_cfg/fsp_cfg/*`
3. Copy those generated outputs back into:
   - `/Users/alex/micropython/ports/renesas-ra/boards/EK_RA8P1/`
4. Then build a first C-side solid-color display test in MicroPython

Practical interpretation

- This is no longer a discovery problem.
- The next software move is explicitly one of:
  - install the official Renesas macOS toolchain/configurator on this machine
  - or switch to another machine where it is already installed
- If installing here, the shortest path is:
  1. open the RA FSP page
  2. download either `FSP MacOS Platform Installer` or `FSP RASC macOS Installer`
  3. install
  4. regenerate `ra_gen/*` and `ra_cfg/fsp_cfg/*` from staged `configuration.xml`
- Download gating is now also confirmed:
  - Renesas serves the installer through a filled download form at `https://info.renesas.com/fsp`
  - this session does not yet have a completed download transaction or pre-downloaded installer
  - so the remaining blocker is partly administrative/user-driven, not technical discovery
