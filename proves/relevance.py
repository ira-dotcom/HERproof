"""On-device relevance narrowing: layer 2 of the spec.

Free and local. No cloud AI per photo. Signals used, in order:
  1. the phone's own records  (exact): chat media, calls, voicemail filtered
     to the chosen person and date range; gallery filtered to the chosen dates
  2. cheap on-device heuristics: screenshot flag, filename, EXIF timestamp

Agreed defaults (spec, Oct 2026):
  date range          on
  screenshots         on
  people/face detect  OFF (catches every family photo; needs a real model)
  bias                include too much, let her remove

Output: a review bundle (review.json) of candidates, each with `included`
(the pre-selection), `reasons`, and a `day` grouping key.
"""

from __future__ import annotations

import os
from collections import defaultdict


def _day_of(ts):
    return (ts or "")[:10] or None


def _in_range(ts, date_from, date_to):
    if not ts:
        return True  # keep undated items; the user rules on them in review
    day = _day_of(ts)
    if date_from and day < date_from:
        return False
    if date_to and day > date_to:
        return False
    return True


def narrow(entries, calls=None, media=None, person=None,
           date_from=None, date_to=None, screenshots=True):
    """Build the review bundle from pipeline entries + extracted raw records.

    entries  list[dict]  entries.json-shaped (messages inside)
    calls    list[dict]  proves.backup.calls() records
    media    list[dict]  proves.backup.media()/copy_media() records
    person   str|None    number, handle id, or sender_name to keep
    """
    calls = calls or []
    media = media or []
    candidates = []

    # --- messages: exact, already the chosen person's when person given ---
    for e in entries:
        msgs = []
        for m in e.get("messages", []):
            if person and not _matches_person(m, person):
                continue
            msgs.append(m)
        if not msgs:
            continue
        reasons = ["phone records (exact)"]
        if e.get("source_type") == "screenshot" and screenshots:
            reasons.append("screenshot")
        candidates.append({
            "kind": "messages",
            "source_file": e.get("source_file"),
            "day": _day_of(msgs[0].get("timestamp") or e.get("exif_timestamp")),
            "count": len(msgs),
            "included": True,  # chosen person's chats: included by default
            "reasons": reasons,
            "entries": [{"source_file": e.get("source_file"),
                         "source_type": e.get("source_type"),
                         "exif_timestamp": e.get("exif_timestamp"),
                         "file_hash": e.get("file_hash"),
                         "messages": msgs}],
        })

    # --- calls: exact filter on the chosen number ---
    for c in calls:
        if person and not _matches_person(c, person, address=True):
            continue
        candidates.append({
            "kind": "call",
            "source_row": c.get("source_row"),
            "day": _day_of(c.get("timestamp")),
            "count": 1,
            "included": True,
            "reasons": ["phone records (exact)"],
            "record": c,
        })

    # --- gallery: date range + screenshot flag; faces stay OFF by default ---
    for m in media:
        reasons = []
        day = _day_of(m.get("captured_at") or m.get("exif_timestamp"))
        ok = _in_range(day, date_from, date_to)
        if not ok:
            continue
        if m.get("kind") == "screenshot":
            if not screenshots:
                continue
            reasons.append("screenshot")
        else:
            reasons.append("in date range")
            if date_from is None and date_to is None:
                reasons = ["gallery: no range set, user confirms"]
        is_shot = m.get("kind") == "screenshot"
        included = screenshots if is_shot else bool(date_from or date_to)
        if not is_shot and not (date_from or date_to):
            reasons = ["gallery: turn it on (no range set), she confirms"]
        candidates.append({
            "kind": "media",
            "file_name": m.get("file_name"),
            "day": day,
            "count": 1,
            "included": included,
            "reasons": reasons or ["gallery: turn it on (no range set), she confirms"],
            "record": m,
        })

    return candidates


def _digits(s):
    return "".join(ch for ch in str(s or "") if ch.isdigit())


def _matches_person(record, person, address=False):
    """Free and deliberate, never fuzzy: a number matches the full number or
    the last 7+ digits of it; a name matches only the exact display name."""
    p = (person or "").strip()
    if not p:
        return True
    if address:
        fields = [record.get("address"), record.get("location")]
    else:
        fields = [record.get("sender_name")]
    want = _digits(p)
    if want:
        return any(
            _digits(f) and (want == _digits(f) or
                            (len(want) >= 7 and _digits(f).endswith(want)))
            for f in fields)
    return any(str(f or "").strip().lower() == p.lower() for f in fields)


def group_by_day(candidates):
    days = defaultdict(list)
    for c in candidates:
        days[c.get("day") or "no date"].append(c)
    return dict(sorted(days.items()))


def counts(candidates):
    inc = sum(c["count"] for c in candidates if c["included"])
    return {"candidates": len(candidates),
            "included_items": inc,
            "days": len(group_by_day(candidates))}
