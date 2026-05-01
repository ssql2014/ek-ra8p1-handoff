# headless_codegen.py — Eclipse EASE Python script to regenerate FSP outputs
# from a staged configuration.xml inside e²studio without GUI clicks.
#
# Run with (after FSP 6.4.0 e²studio is installed):
#   "/Applications/Renesas e2 studio with RA FSP 6.4.0.app/Contents/MacOS/e2studio" \
#       -nosplash \
#       -application org.eclipse.ease.runtime.headless.cli \
#       -data "/tmp/fsp-gen-workspace" \
#       -script "/Users/alex/ek-ra8p1-handoff/scripts/headless_codegen.py" \
#       -consoleLog
#
# (App ID may need adjustment after install — probe with -listApps. The EASE
# headless CLI is provided by org.eclipse.ease.cli or org.eclipse.ease.runtime.)
#
# Required EASE script modules (loaded below):
#   /RA/SmartDemo  — project creation
#   /RA/ProjectGen — getAvailableBoards / getAvailableFspVersions etc.
#   /FSP/SmartDemo — openConfigurationEditor (regen on save)
#
# Strategy:
#   1. Create or reuse a workspace project named EK_RA8P1_GEN.
#   2. Copy staged configuration.xml + ra_cfg.txt into that project.
#   3. Open the configuration editor (which triggers code generation on save).
#   4. Save → ra_gen/* + ra_cfg/fsp_cfg/* materialize.

# These calls are EASE Python (Jython under Eclipse) — pure Python with the
# loadModule() injection from EASE.

# pylint: disable=undefined-variable

loadModule("/RA/SmartDemo")
loadModule("/RA/ProjectGen")
loadModule("/FSP/SmartDemo")

import os
import shutil

PROJECT_NAME = "EK_RA8P1_GEN"
BOARD = "EK-RA8P1"
FSP_VERSION = "6.4.0"
TEMPLATE = "Bare Metal - Minimal"  # adjust after probing getAvailableTemplates()
TOOLCHAIN = "GCC ARM Embedded"
STAGED_CFG = "/Users/alex/micropython/ports/renesas-ra/boards/EK_RA8P1/configuration.xml"
STAGED_RA_CFG_TXT = "/Users/alex/micropython/ports/renesas-ra/boards/EK_RA8P1/ra_cfg.txt"

# Step 1: probe available options before committing
print("Available boards:", list(getAvailableBoards()))
print("Available FSP versions:", list(getAvailableFspVersions(BOARD)))
print("Available templates:", list(getAvailableTemplates(BOARD, FSP_VERSION)))
print("Available toolchains:", list(getAvailableToolchains()))

# Step 2: create or reopen project
# (createCProject returns a future; .run() blocks until generation completes)
proj = createCProject(BOARD, TEMPLATE)
proj.fspVersion(FSP_VERSION)
proj.toolchain(TOOLCHAIN)
proj.run()

# Step 3: replace configuration with our staged baseline
ws_root = os.environ.get("WORKSPACE", "/tmp/fsp-gen-workspace")
proj_root = os.path.join(ws_root, PROJECT_NAME)
shutil.copyfile(STAGED_CFG, os.path.join(proj_root, "configuration.xml"))
shutil.copyfile(STAGED_RA_CFG_TXT, os.path.join(proj_root, "ra_cfg.txt"))
print("Replaced configuration.xml and ra_cfg.txt in", proj_root)

# Step 4: trigger regeneration
# openConfigurationEditor(...).save() pattern — exact API name TBD after probe
editor = openConfigurationEditor(PROJECT_NAME, "BSP")  # any valid tab triggers full regen
editor.save()  # triggers Generate Project Content
print("Code generation complete. Outputs at:")
print("  ", os.path.join(proj_root, "ra_gen"))
print("  ", os.path.join(proj_root, "ra_cfg/fsp_cfg"))
