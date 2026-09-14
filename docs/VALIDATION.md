# Validation · 2026-09-14

Environment: Apple silicon Mac, Xcode 26.5 (17F42), iOS 26.5 Simulator SDK. Builds use unsigned local output; no signing team, provisioning profile, release, or deployment was created.

| Check | Result |
| --- | --- |
| Core Swift tests | 9 passed, 0 failures |
| iOS simulator build | Passed, Debug, arm64 and x86_64 |
| Mac companion build | Passed, Debug, Apple silicon |
| iPhone 17 Pro simulator install / launch | Passed in isolated `--demo` mode |
| Visual inspection | Deck rendered with task pads, Fast Mode, and command controls |
| Simulator click interaction | Not verified: computer-use tool returned `noWindowsAvailable` on clicks |
| Real ChatGPT/Codex control | Not verified: computer-use tool denied access to this app |
| Physical iPhone-to-Mac pairing | Not verified; requires device testing |
| GitHub CI | See current Actions result; local checks above are independent |

Core tests cover two-sided confirmation, encrypted round trips, replay rejection, sender reflection rejection, tampering, foreign sessions, commitment/reveal validation, duplicate/missing button matches, stale/duplicate commands, absent Fast Mode intent, approval rejection, disconnected capabilities, and protocol round trips.

The native adapter is intentionally not executed during automated development checks. Follow `DESKTOP-VERIFICATION.md` before claiming live control support. Readable Fast Mode state is a release gate.
