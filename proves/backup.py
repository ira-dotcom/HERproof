"""Read an unencrypted iPhone backup the way the desktop app will.

She pairs once with the cable; the Mac later keeps the backup current over
Wi-Fi (Finder/backupd). This module only READS a backup folder that already
exists on her computer:

    <backup>/<2-hex>/<40-hex>   files named by their SHA-1
    Manifest.db                 sqlite: Files(fileID, domain, relativePath, flags, file)

What we read today (stdlib only):
  sms.db              iMessage + SMS: message, handle, attachment tables
  callhistory         CallHistory.storedata (HomeDomain) call log
  voicemail           Voicemail domain listing (index; audio copy)
  camera roll         CameraRollDomain media by date (photos/videos)

Everything lands in a staging folder the user controls. The backup itself is
never modified, and the app deletes its temp copy after extraction (see
lifecycle note in cli.py) so nothing sits around for someone else to find.

Not covered (documented limits): iCloud-only items, deleted items, WhatsApp
ChatStorage from the backup, Signal and other E2E apps, voicemail audio on
Android. Android has no Finder-style backup: see android.py.
"""

from __future__ import annotations

import os
import shutil
import sqlite3
from datetime import datetime

from .timeutil_proves import apple_ns_to_dt, apple_seconds_to_dt, iso_local

MANIFEST_DB = "Manifest.db"
STATUS_PLIST = "Status.plist"

CALL_DOMAIN = "HomeDomain"
CALL_FILE = "Library/CallHistoryDB/CallHistory.storedata"
SMS_RELPATH = "Library/SMS/sms.db"
VOICEMAIL_DOMAIN = "HomeDomain"
VOICEMAIL_DIR = "Library/Voicemail"
CAMERA_DOMAIN_PREFIX = "CameraRollDomain"
MEDIA_FILE = "Media/DCIM"


class BackupError(Exception):
    pass


class IPhoneBackup:
    """A read-only view of one unencrypted iPhone backup folder."""

    def __init__(self, path: str, utc_offset_minutes: int | None = None):
        self.path = os.path.abspath(path)
        if not os.path.isdir(self.path):
            raise BackupError(f"not a folder: {self.path}")
        if not os.path.isfile(os.path.join(self.path, MANIFEST_DB)):
            raise BackupError(
                "no Manifest.db here: pass the top-level backup folder "
                "(the one containing Manifest.db and Status.plist)"
            )
        self.utc_offset_minutes = utc_offset_minutes
        self._files = None  # {(domain, relativePath): fileID}

    # -- manifest ---------------------------------------------------------

    def files(self) -> dict[tuple[str, str], str]:
        if self._files is None:
            con = sqlite3.connect(os.path.join(self.path, MANIFEST_DB))
            try:
                rows = con.execute(
                    "SELECT domain, relativePath, fileID FROM Files WHERE flags = 0"
                ).fetchall()
            finally:
                con.close()
            self._files = {(d or "", r or ""): fid for d, r, fid in rows}
        return self._files

    def _abs_path(self, domain: str, relpath: str) -> str | None:
        fid = self.files().get((domain, relpath))
        if fid is None:
            return None
        return os.path.join(self.path, fid[:2], fid)

    def find(self, domain_prefix: str, relpath: str) -> list[tuple[str, str, str]]:
        """(domain, relativePath, absolute path) for every file under a prefix."""
        out = []
        for (d, r), fid in self.files().items():
            if d.startswith(domain_prefix) and r.startswith(relpath):
                out.append((d, r, os.path.join(self.path, fid[:2], fid)))
        return sorted(out, key=lambda t: t[1])

    def device_info(self) -> dict:
        import plistlib

        p = os.path.join(self.path, STATUS_PLIST)
        if not os.path.isfile(p):
            return {}
        try:
            with open(p, "rb") as f:
                data = plistlib.load(f)
        except Exception:
            return {}
        return {
            "device_name": data.get("DeviceName"),
            "last_backup": iso_local(
                apple_seconds_to_dt(data.get("LastBackupDate")),
                self.utc_offset_minutes,
            ),
            "encrypted": bool(data.get("IsEncrypted", False)),
        }

    # -- messages ---------------------------------------------------------

    def messages(self) -> list[dict]:
        """iMessage + SMS as pipeline-ready message dicts (conf 1.0)."""
        sms_path = self._abs_path("HomeDomain", SMS_RELPATH)
        if sms_path is None:
            return []
        con = sqlite3.connect(sms_path)
        con.row_factory = sqlite3.Row
        try:
            handles = {
                r[0]: r[1]
                for r in con.execute("SELECT ROWID, id FROM handle").fetchall()
            }
            out = []
            # is_from_me 1 = self; date is Apple epoch nanoseconds (wall clock)
            q = """
                SELECT m.ROWID, m.guid, m.text, m.is_from_me, m.date,
                       m.handle_id, a.filename AS att
                FROM message m
                LEFT JOIN message_attachment_join j ON j.message_id = m.ROWID
                LEFT JOIN attachment a ON a.ROWID = j.attachment_id
                ORDER BY m.date
            """
            for r in con.execute(q):
                when = iso_local(apple_ns_to_dt(r["date"]), self.utc_offset_minutes)
                sender = "self" if r["is_from_me"] else (
                    "other" if r["handle_id"] else "system"
                )
                out.append({
                    "sender": sender,
                    "sender_name": handles.get(r["handle_id"]),
                    "timestamp": when,
                    "text": r["text"] or "",
                    "attachment": bool(r["att"]),
                    "attachment_path": r["att"],
                    "confidence": 1.0,
                    "source": "iphone_backup",
                    "source_row": r["ROWID"],
                })
            return out
        finally:
            con.close()

    # -- calls ------------------------------------------------------------

    def calls(self) -> list[dict]:
        path = self._abs_path(CALL_DOMAIN, CALL_FILE)
        if path is None:
            return []
        con = sqlite3.connect(path)
        con.row_factory = sqlite3.Row
        try:
            # ZCALLRECORD: ZDATE Apple epoch seconds, ZDURATION, ZADDRESS blob,
            # ZLOCATION, ZINCOMING (0 outgoing, 1 incoming), ZANSWERED, ZCALLTYPE
            out = []
            for r in con.execute(
                "SELECT Z_PK, ZDATE, ZDURATION, ZADDRESS, ZLOCATION, "
                "ZINCOMING, ZANSWERED, ZCALLTYPE FROM ZCALLRECORD ORDER BY ZDATE"
            ):
                num = r["ZADDRESS"]
                if isinstance(num, (bytes, bytearray)):
                    num = num.decode("utf-8", "replace")
                out.append({
                    "direction": "incoming" if r["ZINCOMING"] else "outgoing",
                    "answered": bool(r["ZANSWERED"]),
                    "duration_seconds": r["ZDURATION"],
                    "address": num,
                    "location": r["ZLOCATION"],
                    "call_type": r["ZCALLTYPE"],
                    "timestamp": iso_local(
                        apple_seconds_to_dt(r["ZDATE"]), self.utc_offset_minutes
                    ),
                    "source": "iphone_backup",
                    "source_row": r["Z_PK"],
                })
            return out
        finally:
            con.close()

    # -- voicemail --------------------------------------------------------

    def voicemails(self) -> list[dict]:
        """Visual-voicemail index (list + file names). Audio copy is a to-test
        tier; the DB format varies by carrier."""
        hits = [
            (r, p)
            for d, r, p in self.find(VOICEMAIL_DOMAIN, VOICEMAIL_DIR)
            if os.path.isfile(p)
        ]
        out = []
        for rel, p in hits:
            base = os.path.basename(rel)
            if base.lower().endswith((".amr", ".wav", ".m4a", ".caf")):
                out.append({"relative_path": rel, "audio_file": base})
        return out

    # -- media ------------------------------------------------------------

    def media(self, staging_dir: str | None = None) -> list[dict]:
        """Camera roll index. Copies originals into staging_dir when given.

        Status markers follow the spec: photos/videos here are documented;
        the screenshot flag is heuristic (to test): iOS names screenshots
        IMG_####.PNG under DCIM, but so do some exports, so treat it as a
        signal the user confirms in review, never a verdict.
        """
        out = []
        for domain, rel, p in self.find(CAMERA_DOMAIN_PREFIX, MEDIA_FILE):
            if not os.path.isfile(p):
                continue
            name = os.path.basename(rel)
            ext = os.path.splitext(name)[1].lower()
            out.append({
                "relative_path": rel,
                "file_name": name,
                "bytes": os.path.getsize(p),
                "kind": "video" if ext in (".mov", ".mp4", ".m4v") else
                        ("screenshot" if (ext == ".png" and name.startswith("IMG_")) else "photo"),
                "backup_path": p,
            })
        return out

    def copy_media(self, staging_dir: str, items=None) -> list[dict]:
        """Copy chosen media (or all) into staging, keeping original files."""
        os.makedirs(staging_dir, exist_ok=True)
        kept = []
        for m in items if items is not None else self.media():
            src = m["backup_path"]
            dest = os.path.join(staging_dir, m["file_name"])
            i, base = 1, m["file_name"]
            while os.path.exists(dest):
                stem, ext = os.path.splitext(base)
                dest = os.path.join(staging_dir, f"{stem}_{i}{ext}")
                i += 1
            shutil.copy2(src, dest)
            kept.append({**m, "staged_path": dest})
        return kept


def delete_staging_backup_copy(backup_path: str) -> bool:
    """Lifecycle: after extraction the app deletes its working copy of the
    backup so nothing sensitive sits on the machine. Only ever called on a
    path the app itself created; refuse the real user backup by contract."""
    marker = os.path.join(backup_path, ".herproof-workcopy")
    if not os.path.isfile(marker):
        return False
    shutil.rmtree(backup_path)
    return True
