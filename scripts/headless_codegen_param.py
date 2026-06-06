# Eclipse EASE script for parameterized RA FSP generation.
#
# Usage:
#   e2studio -nosplash -application org.eclipse.ease.runScript \
#     -engine org.eclipse.ease.lang.python.py4j.engine \
#     -workspace /tmp/fsp-gen-mipi-csi \
#     -script file:///Users/alex/ek-ra8p1-handoff/scripts/headless_codegen_param.py \
#     <project> <board> <fsp-version> <template> <toolchain> <configuration.xml> <ra_cfg.txt>

# pylint: disable=undefined-variable

import os
import shutil

loadModule("/RA/SmartDemo")
loadModule("/RA/ProjectGen")
loadModule("/FSP/SmartDemo")

DEFAULTS = [
    "EK_RA8P1_MIPI_CSI_GEN",
    "EK-RA8P1",
    "6.4.0",
    "Bare Metal - Minimal",
    "GCC ARM Embedded",
    "/Users/alex/ra-fsp-examples/example_projects/ek_ra8p1/mipi_csi/mipi_csi_ek_ra8p1_ep/e2studio/configuration.xml",
    "/Users/alex/ra-fsp-examples/example_projects/ek_ra8p1/mipi_csi/mipi_csi_ek_ra8p1_ep/e2studio/ra_cfg.txt",
]

params = list(argv) if len(argv) == 7 else DEFAULTS

PROJECT_NAME = params[0]
BOARD = params[1]
FSP_VERSION = params[2]
TEMPLATE = params[3]
TOOLCHAIN = params[4]
STAGED_CFG = params[5]
STAGED_RA_CFG_TXT = params[6]

print("Available boards:", list(getAvailableBoards()))
print("Available FSP versions:", list(getAvailableFspVersions(BOARD)))
print("Available templates:", list(getAvailableTemplates(BOARD, FSP_VERSION)))
print("Available toolchains:", list(getAvailableToolchains()))

proj = createCProject(BOARD, TEMPLATE)
proj.fspVersion(FSP_VERSION)
proj.toolchain(TOOLCHAIN)
proj.name(PROJECT_NAME)
proj.run()

ws_root = os.environ.get("WORKSPACE", "/tmp/fsp-gen-workspace")
proj_root = os.path.join(ws_root, PROJECT_NAME)
shutil.copyfile(STAGED_CFG, os.path.join(proj_root, "configuration.xml"))
shutil.copyfile(STAGED_RA_CFG_TXT, os.path.join(proj_root, "ra_cfg.txt"))
print("Replaced configuration.xml and ra_cfg.txt in", proj_root)

editor = openConfigurationEditor(PROJECT_NAME, "BSP")
editor.save()
print("Code generation complete:", proj_root)
