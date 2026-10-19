"""Apply the user's removals. She never adds from 3,000 clicks; things arrive
pre-selected and she removes a photo, a day, or a type, or keeps everything
in one click. Selection state is a plain JSON file she can diff and keep."""

from __future__ import annotations


def apply(candidates, removals):
    """removals: list of ops
        {"op": "remove_file",  "file_name": "..."}
        {"op": "remove_day",   "day": "2026-09-24"}
        {"op": "remove_kind",  "kind": "media"}          # or "call"/"messages"
        {"op": "remove_type",  "media_kind": "screenshot"}
        {"op": "keep_all"}
    Applied in order, so a keep_all followed by one remove_day is legal."""
    for c in candidates:
        c["included"] = True
    for op in removals:
        kind = op.get("op")
        if kind == "keep_all":
            for c in candidates:
                c["included"] = True
        elif kind == "remove_file":
            name = op["file_name"]
            for c in candidates:
                if c.get("file_name") == name or c.get("source_file") == name:
                    c["included"] = False
        elif kind == "remove_day":
            for c in candidates:
                if c.get("day") == op["day"]:
                    c["included"] = False
        elif kind == "remove_kind":
            for c in candidates:
                if c.get("kind") == op["kind"]:
                    c["included"] = False
        elif kind == "remove_type":
            for c in candidates:
                if c.get("record", {}).get("kind") == op["media_kind"]:
                    c["included"] = False
        else:
            raise ValueError(f"unknown removal op: {kind!r}")
    return candidates


def selected(candidates):
    return [c for c in candidates if c["included"]]
