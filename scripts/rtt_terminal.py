#!/usr/bin/env python3
"""
RTT terminal for the EK-RA8P1 MicroPython REPL.

- Uses pylink-square to keep a single J-Link session open.
- Continuously drains RTT up-buffer 0 to stdout.
- Reads stdin (raw mode) and writes to RTT down-buffer 0.

Run:
    python3 rtt_terminal.py

Quit:
    Ctrl-] (group separator) or Ctrl-X.

Requires:
    pip3 install --break-system-packages pylink-square
"""

from __future__ import annotations
import os
import select
import sys
import termios
import tty
import time

import pylink

DEVICE = "R7KA8P1KF_CPU0"
DLL_PATH = "/Users/alex/jlink_v938a_extract/Applications/SEGGER/JLink_V938a/libjlinkarm.dylib"
RTT_BLOCK_ADDR = 0x2200124c  # _SEGGER_RTT control-block (read from firmware.map if rebuilt)
SPEED_KHZ = 4000

QUIT_KEYS = (0x1D, 0x18)  # Ctrl-] and Ctrl-X


def main() -> int:
    jlink = pylink.JLink(lib=pylink.Library(dllpath=DLL_PATH))
    jlink.open()
    jlink.set_tif(pylink.enums.JLinkInterfaces.SWD)
    jlink.connect(DEVICE, speed=SPEED_KHZ, verbose=False)
    # Tell pylink where the control block lives (avoids the failing memory scan
    # since RA8P1's SRAM at 0x22000000 is outside the default scan range).
    jlink.rtt_start(block_address=RTT_BLOCK_ADDR)

    # Wait for the control block to be ready.
    deadline = time.time() + 5.0
    while time.time() < deadline:
        try:
            n = jlink.rtt_get_num_up_buffers()
            if n > 0:
                break
        except pylink.errors.JLinkRTTException:
            pass
        time.sleep(0.05)
    else:
        print("rtt_terminal: control block not ready", file=sys.stderr)
        return 1

    sys.stdout.write("[rtt_terminal] connected; press Ctrl-] or Ctrl-X to quit\r\n")
    sys.stdout.flush()

    # Switch terminal to raw mode so individual keys reach the MCU.
    fd = sys.stdin.fileno()
    old_attrs = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        while True:
            # Drain TX (target → host).
            try:
                data = jlink.rtt_read(0, 4096)
            except pylink.errors.JLinkRTTException:
                data = []
            if data:
                sys.stdout.buffer.write(bytes(data))
                sys.stdout.flush()

            # Drain RX (host → target).
            r, _, _ = select.select([fd], [], [], 0.02)
            if r:
                ch = os.read(fd, 64)
                if not ch:
                    break
                if any(b in QUIT_KEYS for b in ch):
                    break
                try:
                    jlink.rtt_write(0, list(ch))
                except pylink.errors.JLinkRTTException as e:
                    sys.stderr.write(f"\r\n[rtt_terminal] write failed: {e}\r\n")
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old_attrs)
        try:
            jlink.rtt_stop()
        except Exception:
            pass
        jlink.close()
        sys.stdout.write("\r\n[rtt_terminal] disconnected\r\n")
        sys.stdout.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
