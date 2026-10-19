"""
Lea Proves — the desktop extraction layer for HerProof.

Mirrors how iMazing ships: the user connects her phone to her computer once,
the app reads an unencrypted iPhone backup locally, narrows what is relevant
on-device (no cloud AI per photo), and assembles the lawyer-ready record.
Raw data never leaves the machine; the report is the only artifact.

Layers (see docs/LEA_PROVES_SPEC.md):
  backup.py     read an unencrypted iPhone backup (messages, calls, media)
  android.py    Android via ADB (SMS, call log, media folders) — to-test tier
  relevance.py  on-device narrowing: date range, screenshots, person filter
  review.py     apply the user's removals (single / day / type / keep-all)
  dossier.py    fingerprinted dossier + UPL-safe declaration scaffold
  cli.py        python -m proves ...
"""

__version__ = "0.1.0"
