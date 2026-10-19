"""Android via ADB, the to-test tier of the spec.

Google Play would block an SMS/call-log app anyway, so Android ships through
the desktop app too. What works over ADB without root:
  SMS + call log    content://sms and content://call_log (documented)
  camera/screenshot folders   /sdcard/DCIM and /sdcard/Pictures/Screenshots
  WhatsApp          export chat only; the on-device DB is SQLCipher (documented)

Safety: the app walks her back through turning USB debugging OFF after
capture. Leaving it on is a real risk on a phone the abuser may touch, so
this module raises if it ever sees debugging enabled and refuses to continue
without the user's explicit ack flag.
"""

from __future__ import annotations

import subprocess


class AndroidError(Exception):
    pass


def _adb(args, ack_debugging=False):
    cmd = ["adb", *args]
    try:
        proc = subprocess.run(cmd, capture_output=True, timeout=30)
    except FileNotFoundError as ex:
        raise AndroidError(f"adb not installed: {ex}") from ex
    if proc.returncode != 0:
        raise AndroidError(proc.stderr.decode("utf-8", "replace").strip())
    return proc.stdout.decode("utf-8", "replace")


def guard(ack_debugging=False):
    """Refuse to run unless USB debugging is off, or she explicitly accepted
    the risk in the UI (the desktop app shows that dialog; the CLI takes the
    flag). After capture, the app turns it back off."""
    state = _adb(["shell", "settings", "global", "adb_enabled"]).strip()
    if state.endswith("1") and not ack_debugging:
        raise AndroidError(
            "USB debugging is on: the app stops here until it is turned off "
            "again after capture (safety first), or the user accepts the risk"
        )
    return True


def sms(ack_debugging=False):
    guard(ack_debugging)
    out = _adb(["shell", "content", "query", "--uri", "content://sms"])
    rows = []
    for line in out.splitlines():
        row = {}
        for part in line.strip().split("Row: ")[-1:]:  # keep the last segment
            for kv in part.split(","):
                if "=" in kv:
                    k, v = kv.split("=", 1)
                    row[k.strip()] = v.strip()
        rows.append(row)
    return rows


def call_log(ack_debugging=False):
    guard(ack_debugging)
    return _adb(["shell", "content", "query", "--uri", "content://call_log/calls"])
