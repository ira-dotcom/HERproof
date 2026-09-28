# HerProof in Swift

The pipeline that used to run on a Mac, running on the phone the evidence is
already on.

## What is here

| Module | What it does |
|---|---|
| `Sources/HerProofKit` | The engine: importing, fingerprinting, dating, the CDC matchers, incident grouping, the flags list |
| `Sources/HerProofUI` | The app: pattern map, timeline, vault, packet, and the cover screen |
| `Tests/HerProofKitTests` | The engine's tests |

```
swift test          # the engine, on macOS
```

The app targets iOS 17 and up. Open the package in Xcode and add it to an app
target, or run the UI module in a SwiftUI preview.

## What changed in the port, and why

**No capture rig.** The Python version drove an iPhone from a Mac over USB with
WebDriverAgent, which needed Xcode, Developer Mode and Trust This Computer. On
the phone none of that exists: the messages, the screenshots and the photos are
already here. Import is the share sheet, the Photos picker and a WhatsApp export
from Files.

**Nothing leaves the phone.** `organize.py` sent every incident's messages to
Gemini for a neutral summary, and `ingest.py` sent screenshot text too. The
engine here reaches no network at all. `Organizer.organize` takes a summarizer,
and the default writes nothing rather than inventing a sentence nobody said. A
model can be handed in later, on purpose, with her knowing.

**The matchers are unchanged.** Same nine categories, same patterns, same NISVS
items and prevalence figures, same one hit per category, same rule that only the
other person's messages are classified. Reality denial still appears with no
figure beside it and says why.

**Times stay as the screen showed them.** A trailing Z or an offset is dropped,
not applied, so nothing shifts when the phone crosses a time zone with the
evidence on it.

**A gap is still missing evidence.** Stretches with no messages are flagged as
possible missing records, never as a calm period.

## Still to do

- The DVRO packet renderer (DV-100 and the exhibit list) is not ported yet; the
  packet screen counts what would go in it.
- Photo exhibits: EXIF dating and fingerprinting on import.
- The Python pipeline stays in the repo root and still runs.

HerProof is not a law firm and does not give legal advice.
US National Domestic Violence Hotline: 1-800-799-7233, or text START to 88788.
