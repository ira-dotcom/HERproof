"""Timestamp helpers shared by the proves package.

Apple epoch: seconds since 2001-01-01T00:00:00Z (Core Data / backup dates).
Backups store device-local wall time in most tables; we surface both the
naive local reading and, when a timezone offset is supplied, an ISO string
that matches the pipeline's naive-local convention.
"""

from datetime import datetime, timedelta, timezone

APPLE_EPOCH = datetime(2001, 1, 1, tzinfo=timezone.utc)


def apple_seconds_to_dt(seconds):
    """Core Data timestamp (seconds since 2001-01-01 UTC) -> aware datetime."""
    if seconds is None:
        return None
    try:
        return APPLE_EPOCH + timedelta(seconds=float(seconds))
    except (TypeError, ValueError, OverflowError):
        return None


def apple_ns_to_dt(nanoseconds):
    if nanoseconds is None:
        return None
    try:
        return APPLE_EPOCH + timedelta(microseconds=float(nanoseconds) / 1000.0)
    except (TypeError, ValueError, OverflowError):
        return None


def iso_local(dt_obj, utc_offset_minutes=None):
    """Render as a naive local ISO string, like the rest of the pipeline.

    Backup tables store wall-clock seconds as if UTC; the device's real
    offset (from the backup's status plist) shifts it back to local time.
    """
    if dt_obj is None:
        return None
    if utc_offset_minutes:
        dt_obj = dt_obj - timedelta(minutes=utc_offset_minutes)
    return dt_obj.replace(tzinfo=None).isoformat()
