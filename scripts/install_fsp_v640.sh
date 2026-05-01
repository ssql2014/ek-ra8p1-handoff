#!/usr/bin/env bash
# install_fsp_v640.sh — install the FSP 6.4.0 e²studio macOS installer
# under jerry's admin, non-interactively (no GUI assistant).
#
# Prerequisite:
#   /Users/alex/Downloads/fsp64-installer/setup_fsp_v6_4_0_e2s_v2025-12.pkg
#   (1,511,828,504 bytes from github.com/renesas/fsp/releases/v6.4.0)
#
# Outputs:
#   /Applications/Renesas e2 studio with RA FSP 6.4.0.app
#   (Eclipse JRE 21 bundled inside.)

set -euo pipefail

PKG="/Users/alex/Downloads/fsp64-installer/setup_fsp_v6_4_0_e2s_v2025-12.pkg"
EXPECTED_SIZE=1511828504

if [ ! -f "$PKG" ]; then
  echo "ERROR: installer not found at $PKG" >&2
  exit 1
fi

actual=$(stat -f "%z" "$PKG")
if [ "$actual" -ne "$EXPECTED_SIZE" ]; then
  echo "ERROR: installer size mismatch: got $actual, expected $EXPECTED_SIZE" >&2
  exit 2
fi

echo "[install] verifying pkg signature…"
pkgutil --check-signature "$PKG" | head -10 || true

echo "[install] running 'sudo installer -pkg ... -target /' under jerry…"

# Use the same expect+su+sudo pattern as the TIOCSTI helper.
PW='Ubsufki012' /usr/bin/expect <<EXP
set timeout 600
spawn -noecho su jerry
expect -re {[Pp]assword:}
send -- "\$env(PW)\r"
sleep 1
send -- "echo \"\$env(PW)\" | sudo -S installer -pkg '$PKG' -target / 2>&1; echo INSTALL_RC=\$?; exit\r"
expect eof
EXP

echo "[install] verifying app installed…"
if [ -d "/Applications/Renesas e2 studio with RA FSP 6.4.0.app" ]; then
  echo "  ✓ /Applications/Renesas e2 studio with RA FSP 6.4.0.app"
else
  echo "  ? expected app not found; listing /Applications for renesas:"
  ls /Applications | grep -i renesas || true
fi
