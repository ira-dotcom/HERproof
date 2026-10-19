"""Assemble the dossier: fingerprinted files, index, and the UPL-safe
declaration scaffold. The agent's work ends at organized records and a draft
she reviews; it never advises on her rights, never recommends a legal
strategy, and never tells her what to file. A lawyer gives the advice."""

from __future__ import annotations

import hashlib
import json
import os
from collections import OrderedDict
from datetime import datetime, timezone


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def manifest(files):
    """Deterministic SHA-256 fingerprint list, sorted by file name."""
    rows = []
    for path in sorted(files):
        rows.append(OrderedDict([
            ("file", os.path.basename(path)),
            ("sha256", sha256_file(path)),
            ("bytes", os.path.getsize(path)),
        ]))
    return rows


def build(dossier_dir, entries_subset, media_paths, timeline=None, meta=None):
    """Write the dossier folder:
        dossier/
          index.json     everything, machine-readable
          manifest.json  fingerprints
          media/         original files, untouched (lawyers don't trust re-encodes)
          declaration_draft.md   scaffold only, gated on review
    Returns (index_path, manifest_path, declaration_path)."""
    os.makedirs(dossier_dir, exist_ok=True)
    media_dir = os.path.join(dossier_dir, "media")
    os.makedirs(media_dir, exist_ok=True)
    for src in media_paths:
        if os.path.isfile(src):
            dest = os.path.join(media_dir, os.path.basename(src))
            if not os.path.exists(dest):
                with open(src, "rb") as a, open(dest, "wb") as b:
                    b.write(a.read())

    all_files = [os.path.join(media_dir, f) for f in sorted(os.listdir(media_dir))]
    rows = manifest(all_files)

    index = OrderedDict([
        ("generated_at", datetime.now(timezone.utc).isoformat()),
        ("meta", meta or {}),
        ("counts", {"messages": sum(len(e.get("messages", [])) for e in entries_subset),
                    "media_files": len(rows)}),
        ("entries", entries_subset),
        ("timeline", timeline),
        ("manifest", rows),
    ])
    index_path = os.path.join(dossier_dir, "index.json")
    with open(index_path, "w") as f:
        json.dump(index, f, indent=2)

    manifest_path = os.path.join(dossier_dir, "manifest.json")
    with open(manifest_path, "w") as f:
        json.dump({"algorithm": "SHA-256", "files": rows}, f, indent=2)

    return index_path, manifest_path, declaration_scaffold(dossier_dir)


def declaration_scaffold(dossier_dir):
    """UPL-safe draft: assembles her record in neutral language. Empty until
    she marks the selection reviewed; the file says so, loudly."""
    path = os.path.join(dossier_dir, "declaration_draft.md")
    with open(path, "w") as f:
        f.write(
            "# Declaration draft (scaffold)\n\n"
            "This file assembles the records you selected, in date order, in "
            "neutral language. It is not legal advice and it does not tell you "
            "what to file. A lawyer reviews everything below and tells you what "
            "it means and what to do.\n\n"
            "Nothing is written here until you confirm your selection is final, "
            "because a draft assembled before review is a draft nobody checked.\n"
        )
    return path


def fill_declaration(dossier_dir, entries_subset, reviewed=False):
    """Fill the scaffold from her selected records. Refuses unless reviewed,
    by design: the UPL gate is a feature, not a formality."""
    if not reviewed:
        raise PermissionError(
            "selection not marked reviewed: the draft stays empty until she "
            "confirms it, and the product never ships an unchecked draft"
        )
    lines = [
        "# Declaration draft (scaffold, for lawyer review)",
        "",
        "Records I selected, in date order. Neutral language only.",
        "",
    ]
    for e in sorted(entries_subset, key=lambda e: (e.get("exif_timestamp") or "")):
        for m in e.get("messages", []):
            ts = m.get("timestamp") or "(no time)"
            who = m.get("sender_name") or m.get("sender")
            body = " ".join((m.get("text") or "").split())
            lines.append(f"- {ts} {who}: {body}")
    lines += [
        "",
        "Reviewed by me on " + datetime.now(timezone.utc).date().isoformat() + ".",
        "A lawyer reviews this before anything is filed.",
        "",
    ]
    path = os.path.join(dossier_dir, "declaration_draft.md")
    with open(path, "w") as f:
        f.write("\n".join(lines))
    return path
