# Lea Proves: desktop companion (spec, implementation map)

Full product spec lives in the shared Google Doc "Lea Proves Desktop Companion".
This file maps it onto this codebase, so a reviewer can jump from a spec line
to the module that carries it.

| Spec piece | Where it lives here | Status |
|---|---|---|
| One-time cable pairing, unencrypted iPhone backup read | `proves/backup.py` (`IPhoneBackup`) | working on the fixture; needs one real phone test |
| Wi-Fi after first pairing | property of Finder/backupd, consumed here as an existing backup folder | macOS app layer, out of repo |
| Raw data stays on the computer, report is the only artifact | `proves/backup.py` is read-only; staging copies only what she chose | tested (`test_readonly_never_writes_backup`) |
| Backup deleted after extraction | `proves/backup.py::delete_staging_backup_copy` (only ever deletes an app-made work copy, marked `.herproof-workcopy`) | implemented, refuses the real backup by contract |
| On-device relevance picking, no cloud AI per photo | `proves/relevance.py` | implemented, tested |
| Defaults: date range + screenshots on, people/face off, include too much | `proves/relevance.py` constants in `narrow()` | tested |
| Quick review, not 3,000 clicks | `proves/review.py` (remove a file / day / kind / media type, keep-all) | tested |
| Calls + voicemail index | `proves/backup.py::calls()`, `voicemails()` | calls tested; voicemail audio is a to-test tier |
| Gallery with signals | `proves/backup.py::media()` (screenshot flag is a heuristic she confirms) | tested |
| Android via computer | `proves/android.py` (ADB: SMS, call log, media; USB-debugging safety guard) | scaffold, to-test tier |
| Fingerprinted dossier | `proves/dossier.py::manifest()` (SHA-256, deterministic order) + `index.json` | tested |
| UPL compliance: draft she reviews, never advice | `proves/dossier.py::declaration_scaffold/fill_declaration` (gated on `reviewed`; refuses otherwise) | tested |
| Timeline from the existing pipeline | `proves/cli.py dossier --with-timeline` calls `organize.py` functions directly | wired |
| Distribution: notarized .dmg via website, Sparkle updates | macOS app layer, out of repo (spec section "Distribution and updates") | not in repo |

## Try it

```
python3 -m proves extract --backup <path-to-backup> --staging ./stage --out raw.json
python3 -m proves narrow  --raw raw.json --review review.json --person "+15551230001" \
    --from 2026-01-01 --to 2026-09-30
python3 -m proves review  --review review.json --remove remove_type:screenshot --mark-reviewed
python3 -m proves dossier --review review.json --dossier ./dossier --with-timeline --fill-declaration
```

`python3 -m unittest discover -s tests` runs the suite (21 tests, stdlib only,
no new dependencies).
