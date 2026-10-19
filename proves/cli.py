"""Command line for the Lea Proves desktop layer.

    python -m proves extract  --backup ~/Library/.../Backup --staging ./stage
    python -m proves narrow   --review ./review.json --person "+1..." \\
        --from 2026-01-01 --to 2026-09-30
    python -m proves review   --review ./review.json --remove 'remove_day:2026-09-24' ...
    python -m proves dossier  --review ./review.json --dossier ./dossier

Extraction never modifies the backup. The Mac app deletes its own temp copy
after extraction; this CLI leaves the user's backup alone.
"""

from __future__ import annotations

import argparse
import json
import sys

from . import backup, dossier, relevance, review


def cmd_extract(args):
    b = backup.IPhoneBackup(args.backup, utc_offset_minutes=args.utc_offset)
    info = b.device_info()
    if info.get("encrypted"):
        print("! backup is encrypted: enter the password once in the desktop "
              "app; this reader only covers unencrypted backups", file=sys.stderr)
    messages = b.messages()
    calls = b.calls()
    voices = b.voicemails()
    staging = None
    if args.staging:
        staging = b.copy_media(args.staging)
    print(json.dumps({
        "device": info,
        "message_count": len(messages),
        "call_count": len(calls),
        "voicemails": len(voices),
        "media_files": len(b.media()),
        "staged_media": [m["file_name"] for m in staging or []],
    }, indent=2))
    if args.out:
        with open(args.out, "w") as f:
            json.dump({"messages": messages, "calls": calls,
                       "voicemails": voices, "media": staging or b.media()}, f, indent=2)


def cmd_narrow(args):
    data = json.load(open(args.raw))
    entries = _entries_from_raw(data, args.person)
    cands = relevance.narrow(
        entries, calls=data.get("calls", []), media=data.get("media", []),
        person=args.person, date_from=args.from_date, date_to=args.to_date,
        screenshots=not args.no_screenshots,
    )
    bundle = {"person": args.person, "date_from": args.from_date,
              "date_to": args.to_date, "candidates": cands,
              "counts": relevance.counts(cands)}
    with open(args.review, "w") as f:
        json.dump(bundle, f, indent=2)
    print(json.dumps(bundle["counts"], indent=2))


def _entries_from_raw(data, person):
    """Group raw backup messages into entries.json-shaped records so
    organize.py and the packet run unchanged downstream."""
    from collections import OrderedDict

    by_day = OrderedDict()
    for m in data.get("messages", []):
        if person and not relevance._matches_person(m, person):
            continue
        day = (m.get("timestamp") or "")[:10] or "no date"
        by_day.setdefault(day, []).append(m)
    return [{"source_file": f"iphone_backup_{day}",
             "source_type": "iphone_backup",
             "imported_at": "",
             "file_hash": None,
             "parse_error": None,
             "exif_timestamp": None,
             "raw_text": "",
             "messages": msgs}
            for day, msgs in by_day.items()]


def cmd_review(args):
    bundle = json.load(open(args.review))
    removals = []
    for spec in args.remove or []:
        kind, _, value = spec.partition(":")
        op = {"op": kind}
        if value:
            op["day" if kind == "remove_day" else
               "file_name" if kind == "remove_file" else
               "kind" if kind == "remove_kind" else "media_kind"] = value
        removals.append(op)
    bundle["candidates"] = review.apply(bundle["candidates"], removals)
    bundle["counts"] = relevance.counts(bundle["candidates"])
    bundle["reviewed"] = args.mark_reviewed
    with open(args.review, "w") as f:
        json.dump(bundle, f, indent=2)
    print(json.dumps(bundle["counts"], indent=2))


def cmd_dossier(args):
    bundle = json.load(open(args.review))
    if not bundle.get("reviewed"):
        print("! selection not marked reviewed; the declaration draft stays "
              "empty until she confirms (UPL gate). Pass --reviewed if she "
              "confirmed in the app.", file=sys.stderr)
        return 2
    entries = [c["entries"] for c in review.selected(bundle["candidates"])
               if c["kind"] == "messages"]
    entries = [e for chunk in entries for e in chunk]
    media_paths = [c["record"]["staged_path"] for c in review.selected(bundle["candidates"])
                   if c["kind"] == "media" and c["record"].get("staged_path")]
    timeline = None
    if args.with_timeline:
        import organize  # repo-root pipeline, unchanged
        msgs, overlap_dropped = organize.load_messages(entries)
        msgs.sort(key=organize.sort_key)
        incidents = organize.group_incidents(msgs)
        timeline = {
            "overlap_dropped": overlap_dropped,
            "messages": msgs,
            "incidents": incidents,
        }
    paths = dossier.build(args.dossier, entries, media_paths, timeline=timeline,
                          meta={"person": bundle.get("person")})
    if args.fill_declaration:
        dossier.fill_declaration(args.dossier, entries, reviewed=True)
    print(json.dumps({"dossier": args.dossier,
                      "index": paths[0], "manifest": paths[1],
                      "declaration_draft": paths[2]}, indent=2))


def main(argv=None):
    p = argparse.ArgumentParser(prog="proves")
    sub = p.add_subparsers(dest="cmd", required=True)

    e = sub.add_parser("extract"); e.set_defaults(func=cmd_extract)
    e.add_argument("--backup", required=True)
    e.add_argument("--staging")
    e.add_argument("--out")
    e.add_argument("--utc-offset", type=int, default=None,
                   help="device UTC offset in minutes, from the backup Status.plist")

    n = sub.add_parser("narrow"); n.set_defaults(func=cmd_narrow)
    n.add_argument("--raw", required=True)
    n.add_argument("--review", required=True)
    n.add_argument("--person")
    n.add_argument("--from", dest="from_date")
    n.add_argument("--to", dest="to_date")
    n.add_argument("--no-screenshots", action="store_true")

    r = sub.add_parser("review"); r.set_defaults(func=cmd_review)
    r.add_argument("--review", required=True)
    r.add_argument("--remove", action="append", default=[])
    r.add_argument("--mark-reviewed", action="store_true")

    d = sub.add_parser("dossier"); d.set_defaults(func=cmd_dossier)
    d.add_argument("--review", required=True)
    d.add_argument("--dossier", required=True)
    d.add_argument("--reviewed", action="store_true")
    d.add_argument("--with-timeline", action="store_true")
    d.add_argument("--workdir")
    d.add_argument("--fill-declaration", action="store_true")

    args = p.parse_args(argv)
    return args.func(args) or 0


if __name__ == "__main__":
    sys.exit(main())
