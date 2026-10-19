"""Lea Proves desktop layer: unit tests (stdlib unittest, no new deps).

Builds a synthetic unencrypted iPhone backup fixture on disk (Manifest.db +
sms.db + CallHistory.storedata) the same way a real backup is laid out, then
runs the pipeline over it. No real device data is ever needed for CI.
"""

import datetime as dt
import json
import os
import sqlite3
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from proves import backup, dossier, relevance, review  # noqa: E402
from proves.timeutil_proves import apple_ns_to_dt, apple_seconds_to_dt, iso_local  # noqa: E402

WHEN = dt.datetime(2026, 9, 24, 21, 45, tzinfo=dt.timezone.utc)
APPLE_WHEN = (WHEN - dt.datetime(2001, 1, 1, tzinfo=dt.timezone.utc)).total_seconds()


def _write_sqlite(dest, script):
    con = sqlite3.connect(dest)
    con.executescript(script)
    con.commit()
    con.close()


class _Fixture:
    """Synthesizes a minimal unencrypted backup folder."""

    def __init__(self, root):
        self.bak = os.path.join(root, "backup")
        os.makedirs(self.bak)
        import plistlib

        with open(os.path.join(self.bak, "Status.plist"), "wb") as f:
            plistlib.dump({"DeviceName": "Ira's iPhone", "IsEncrypted": False,
                           "LastBackupDate": APPLE_WHEN}, f)
        self.con = sqlite3.connect(os.path.join(self.bak, "Manifest.db"))
        self.con.execute(
            "CREATE TABLE Files (fileID TEXT PRIMARY KEY, domain TEXT, "
            "relativePath TEXT, flags INTEGER, file BLOB)")

    def add(self, domain, relpath, script=None, data=None):
        fid = os.urandom(20).hex()
        self.con.execute("INSERT INTO Files VALUES (?,?,?,?,?)",
                         (fid, domain, relpath, 0, b""))
        self.con.commit()
        dest = os.path.join(self.bak, fid[:2], fid)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        if script is not None:
            _write_sqlite(dest, script)
        elif data is not None:
            with open(dest, "wb") as f:
                f.write(data)

    def close(self):
        self.con.close()


def _make_backup(root):
    fx = _Fixture(root)
    fx.add("HomeDomain", "Library/SMS/sms.db", script="""
        CREATE TABLE handle (ROWID INTEGER PRIMARY KEY, id TEXT);
        CREATE TABLE message (ROWID INTEGER PRIMARY KEY, guid TEXT, text TEXT,
            is_from_me INTEGER, date INTEGER, handle_id INTEGER);
        CREATE TABLE attachment (ROWID INTEGER PRIMARY KEY, filename TEXT);
        CREATE TABLE message_attachment_join (message_id INTEGER, attachment_id INTEGER);
        INSERT INTO handle VALUES (1, '+15551230001');
        INSERT INTO handle VALUES (2, '+15551230002');
        INSERT INTO message VALUES (1,'g1','where are you',0,{d},1);
        INSERT INTO message VALUES (2,'g2','omw',1,{d},1);
        INSERT INTO message VALUES (3,'g3','wrong person',0,{d},2);
        INSERT INTO attachment VALUES (1, 'Library/SMS/Attachments/img.png');
        INSERT INTO message_attachment_join VALUES (1, 1);
    """.format(d=int(APPLE_WHEN * 1e9)))
    fx.add("HomeDomain", "Library/CallHistoryDB/CallHistory.storedata", script="""
        CREATE TABLE ZCALLRECORD (Z_PK INTEGER PRIMARY KEY, ZDATE REAL,
            ZDURATION REAL, ZADDRESS BLOB, ZLOCATION TEXT, ZINCOMING INTEGER,
            ZANSWERED INTEGER, ZCALLTYPE INTEGER);
        INSERT INTO ZCALLRECORD VALUES (1, {s}, 45.0, '+15551230001',
            'Oakland, CA', 1, 1, 1);
    """.format(s=APPLE_WHEN))
    fx.add("CameraRollDomain", "Media/DCIM/100APPLE/IMG_0001.PNG",
           data=b"pngdata")
    fx.add("CameraRollDomain", "Media/DCIM/100APPLE/IMG_0002.JPG",
           data=b"jpgdata")
    fx.close()
    return fx.bak


class TestBackup(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.b = backup.IPhoneBackup(_make_backup(self.tmp.name),
                                     utc_offset_minutes=0)

    def tearDown(self):
        self.tmp.cleanup()

    def test_device_info(self):
        info = self.b.device_info()
        self.assertEqual(info["device_name"], "Ira's iPhone")
        self.assertFalse(info["encrypted"])
        self.assertTrue(info["last_backup"].startswith("2026-09-24"))

    def test_messages_shape(self):
        msgs = self.b.messages()
        self.assertEqual(len(msgs), 3)
        m0 = msgs[0]
        self.assertEqual(m0["sender"], "other")
        self.assertEqual(m0["sender_name"], "+15551230001")
        self.assertEqual(m0["confidence"], 1.0)
        self.assertEqual(m0["source"], "iphone_backup")
        self.assertTrue(m0["attachment"])
        self.assertTrue(m0["timestamp"].startswith("2026-09-24"))

    def test_calls(self):
        calls = self.b.calls()
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0]["direction"], "incoming")
        self.assertEqual(calls[0]["duration_seconds"], 45.0)
        self.assertEqual(calls[0]["timestamp"], "2026-09-24T21:45:00")

    def test_media_flags(self):
        kinds = {m["file_name"]: m["kind"] for m in self.b.media()}
        self.assertEqual(kinds["IMG_0001.PNG"], "screenshot")
        self.assertEqual(kinds["IMG_0002.JPG"], "photo")

    def test_copy_media_keeps_originals(self):
        with tempfile.TemporaryDirectory() as stage:
            staged = self.b.copy_media(stage)
            self.assertEqual(len(staged), 2)
            for m in staged:
                self.assertTrue(os.path.isfile(m["staged_path"]))

    def test_readonly_never_writes_backup(self):
        before = {p: os.path.getsize(os.path.join(dp, p))
                  for dp, _, fs in os.walk(self.b.path) for p in fs}
        self.b.messages(); self.b.calls(); self.b.media()
        after = {p: os.path.getsize(os.path.join(dp, p))
                 for dp, _, fs in os.walk(self.b.path) for p in fs}
        self.assertEqual(before, after)

    def test_rejects_wrong_folder(self):
        with self.assertRaises(backup.BackupError):
            backup.IPhoneBackup(self.tmp.name)


class TestTime(unittest.TestCase):
    def test_apple_epoch_roundtrip(self):
        self.assertEqual(iso_local(apple_seconds_to_dt(APPLE_WHEN)),
                         "2026-09-24T21:45:00")
        self.assertEqual(iso_local(apple_ns_to_dt(APPLE_WHEN * 1e9)),
                         "2026-09-24T21:45:00")


class TestRelevance(unittest.TestCase):
    def _entries(self):
        return [{"source_file": "iphone_backup_2026-09-24",
                 "source_type": "iphone_backup",
                 "messages": [
                     {"sender": "other", "sender_name": "+15551230001",
                      "timestamp": "2026-09-24T21:45:00", "text": "where are you"},
                     {"sender": "other", "sender_name": "+15551230002",
                      "timestamp": "2026-09-24T22:00:00", "text": "wrong thread"},
                 ]}]

    def test_person_filter_by_number(self):
        cands = relevance.narrow(self._entries(), person="+15551230001")
        self.assertEqual([c["count"] for c in cands], [1])

    def test_no_fuzzy_person_match(self):
        # a 3-digit fragment is not a person: nothing matches
        cands = relevance.narrow(self._entries(), person="551")
        self.assertEqual(cands, [])  # no match, no candidate, no guess
        # suffix of 7+ digits matches: how she'd actually type it
        cands = relevance.narrow(self._entries(), person="5551230001")
        self.assertEqual([c["count"] for c in cands], [1])

    def test_defaults_screenshots_on(self):
        media = [{"file_name": "IMG_0001.PNG", "kind": "screenshot",
                  "captured_at": "2026-09-24"},
                 {"file_name": "IMG_0002.JPG", "kind": "photo",
                  "captured_at": "2026-09-24"}]
        cands = relevance.narrow([], media=media)
        included = [c["file_name"] for c in cands if c["included"]]
        # screenshots on by default; plain gallery photos wait for a range
        self.assertEqual(included, ["IMG_0001.PNG"])
        fam = [c for c in cands if c["file_name"] == "IMG_0002.JPG"][0]
        self.assertFalse(fam["included"])
        self.assertIn("she confirms", fam["reasons"][0])

    def test_no_range_media_needs_her_confirm(self):
        cands = relevance.narrow([], media=[{"file_name": "fam.jpg",
                                             "kind": "photo"}])
        self.assertFalse(cands[0]["included"])
        self.assertIn("confirms", cands[0]["reasons"][0])

    def test_date_range_narrows_gallery(self):
        media = [{"file_name": "a.jpg", "kind": "photo",
                  "captured_at": "2026-01-01"},
                 {"file_name": "b.jpg", "kind": "photo",
                  "captured_at": "2026-09-24"}]
        cands = relevance.narrow([], media=media, date_from="2026-09-01",
                                 date_to="2026-09-30")
        included = [c["file_name"] for c in cands if c["included"]]
        self.assertEqual(included, ["b.jpg"])

    def test_calls_filtered_by_number(self):
        calls = [{"source_row": 1, "direction": "incoming",
                  "address": "+15551230001", "timestamp": "2026-09-24T21:45:00",
                  "duration_seconds": 45.0},
                 {"source_row": 2, "direction": "outgoing",
                  "address": "+15551230002", "timestamp": "2026-09-24T22:00:00",
                  "duration_seconds": 3.0}]
        cands = relevance.narrow([], calls=calls, person="+15551230001")
        self.assertEqual(len([c for c in cands if c["included"]]), 1)


class TestReview(unittest.TestCase):
    def _cands(self):
        return [
            {"kind": "media", "file_name": "a.jpg", "day": "2026-09-24",
             "count": 1, "included": True,
             "record": {"kind": "photo", "staged_path": "/x/a.jpg"}},
            {"kind": "media", "file_name": "b.png", "day": "2026-09-25",
             "count": 1, "included": True,
             "record": {"kind": "screenshot"}},
            {"kind": "call", "day": "2026-09-24", "count": 1, "included": True,
             "record": {}},
        ]

    def test_remove_day(self):
        out = review.apply(self._cands(), [{"op": "remove_day",
                                            "day": "2026-09-24"}])
        self.assertEqual([c["included"] for c in out], [False, True, False])

    def test_remove_type_screenshot(self):
        out = review.apply(self._cands(), [{"op": "remove_type",
                                            "media_kind": "screenshot"}])
        self.assertEqual([c["included"] for c in out], [True, False, True])

    def test_keep_all_then_remove_one(self):
        out = review.apply(self._cands(), [
            {"op": "keep_all"},
            {"op": "remove_file", "file_name": "a.jpg"}])
        self.assertEqual([c["included"] for c in out], [False, True, True])

    def test_unknown_op_raises(self):
        with self.assertRaises(ValueError):
            review.apply(self._cands(), [{"op": "explode"}])


class TestDossier(unittest.TestCase):
    def test_manifest_deterministic(self):
        with tempfile.TemporaryDirectory() as tmp:
            p1 = os.path.join(tmp, "one.txt"); p2 = os.path.join(tmp, "two.txt")
            open(p1, "w").write("hello"); open(p2, "w").write("world")
            m1 = dossier.manifest([p1, p2]); m2 = dossier.manifest([p2, p1])
            self.assertEqual(m1, m2)
            self.assertEqual(m1[0]["file"], "one.txt")
            self.assertEqual(len(m1[0]["sha256"]), 64)

    def test_upl_gate_blocks_unreviewed_draft(self):
        with tempfile.TemporaryDirectory() as tmp:
            dossier.build(tmp, [], [])
            with self.assertRaises(PermissionError):
                dossier.fill_declaration(tmp, [], reviewed=False)
            path = dossier.fill_declaration(
                tmp, [{"messages": [{"sender": "other",
                                     "sender_name": "J",
                                     "timestamp": "2026-09-24T21:45:00",
                                     "text": "where are you"}]}], reviewed=True)
            text = open(path).read()
            self.assertIn("where are you", text)
            self.assertIn("for lawyer review", text)
            self.assertNotIn("You should file", text)  # never advises

    def test_index_counts(self):
        with tempfile.TemporaryDirectory() as tmp:
            with tempfile.TemporaryDirectory() as src:
                p = os.path.join(src, "IMG_0001.PNG")
                open(p, "wb").write(b"png")
                dossier.build(tmp, [{"messages": [{"text": "x"}]}], [p])
            idx = json.load(open(os.path.join(tmp, "index.json")))
            self.assertEqual(idx["counts"]["messages"], 1)
            self.assertEqual(idx["counts"]["media_files"], 1)
            self.assertTrue(os.path.isfile(os.path.join(tmp, "media",
                                                        "IMG_0001.PNG")))


if __name__ == "__main__":
    unittest.main()
