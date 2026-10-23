# PalmRelay

**Your AI workspace, within reach.**

A native iPhone control deck and macOS companion inspired by the controls of Codex Micro. PalmRelay is independent software, not affiliated with OpenAI or Work Louder.

## Preview status

This is a **buildable 0.1 prototype, not complete Codex Micro parity**. Both apps compile. The iPhone includes a clearly marked interactive demo. The experimental Mac Accessibility adapter must be verified against the user's installed desktop version before claiming live support.

| Control | This build |
| --- | --- |
| Fast Mode | Explicit on/off command, exact label matching, desktop state readback. Unavailable if the desktop does not expose a readable toggle. **Live verification pending.** |
| Six task pads | Manually map visible task buttons on the Mac. No automatic task discovery or live agent status. |
| New chat / Continue / Send | Map an exact visible, pressable control; desktop action dispatch is reported separately from its result. |
| Voice | Map a visible desktop voice button; uses the Mac microphone. No phone audio or push-to-talk lifecycle yet. |
| Reasoning / workflow pads | Map visible desktop controls. Does not automatically open menus, compose prompts, or run arbitrary scripts. |
| Approve / Decline | Unavailable in live mode. Requires a structured request ID, exact command preview, and stale-request protection in a future adapter. |
| Pairing | Nearby discovery, mandatory encrypted transport, ephemeral ECDH/AES-GCM channel, matching code confirmed on both devices. |

Demo controls simulate the deck locally and never send desktop commands. Grey/unavailable live controls explain what is missing when tapped.

## Open and run

Requires Xcode 15+ (validated with Xcode 26.5), iOS 17+, and macOS 14+. No external Swift dependencies, API keys, or OpenAI login in PalmRelay.

1. Open `PalmRelay.xcodeproj`.
2. Select **PalmRelayCompanion** and **My Mac**, then Run.
3. Select **PalmRelay** and an iPhone simulator, then Run. Choose **Connect your Mac → Explore demo controls** to preview without desktop access. You can also set the launch argument `--demo`.
4. For a physical phone, select your own development team in Signing & Capabilities, select your device, and Run. No signing identity is committed.

### Connect a real Mac

1. On Mac, choose **Start pairing**. On iPhone, choose **Find my Mac**, then select the Mac.
2. Compare the eight-digit code on both screens and confirm on both. Reject any mismatch.
3. In the Mac companion, request Accessibility access and enable it yourself in System Settings → Privacy & Security → Accessibility. Reopen the companion if macOS requires it.
4. Open a task in ChatGPT / Codex. Enable desktop control in the companion, refresh visible controls, and map exact labels.
5. For Fast Mode, ensure the selected control exposes an on/off Accessibility value. If it does not, the app intentionally cannot toggle it. Follow `docs/DESKTOP-VERIFICATION.md`.

Pairing grants the phone the ability to invoke configured desktop buttons. Disconnecting ends access and disables the Mac adapter. Moving the iPhone app to the background disconnects it. Pair again when you return. Keep the Mac awake; this build has no internet relay or background notifications.

## Build and test

If command line tools point elsewhere, select Xcode for these commands without changing system settings:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test
xcodebuild -project PalmRelay.xcodeproj -scheme PalmRelay -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath build/ios CODE_SIGNING_ALLOWED=NO build
xcodebuild -project PalmRelay.xcodeproj -scheme PalmRelayCompanion -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build/mac CODE_SIGNING_ALLOWED=NO build
```

The committed project has shared schemes. After adding Swift source files, regenerate it with `python3 scripts/generate-project.py`. The generator is deterministic and uses only Python's standard library.

## Structure

- `Apps/iOS`: SwiftUI deck, connection flow, demo, command acknowledgement handling.
- `Apps/Mac`: Companion UI and opt-in Accessibility adapter.
- `Sources/RelayCore`: Typed protocol, pairing cryptography, command validation, unique-control matching.
- `Sources/RelayLink`: Local Multipeer Connectivity transport.
- `Tests/RelayCoreTests`: Pairing, tampering, replay, stale commands, and unavailable-control checks.
- `docs`: Integration limitations, validation evidence, and next milestones.

## Boundaries

No private OpenAI endpoint calls, credential scraping, JavaScript injection, global key synthesis, or shell commands from the phone. Desktop text is hashed locally to detect changes; the phone receives the target window title, assigned task labels, capabilities, and results. There is no analytics or cloud backend. Mappings are stored locally on the Mac; pairing keys are memory-only.

The Accessibility adapter uses public macOS APIs but is **not an official OpenAI control API**. UI labels and state availability can change. A production release also needs device testing, accessibility review, application icons, signing, privacy disclosures, encryption/export review, and name clearance. No App Store/TestFlight submission is configured.

Reference: [Codex Micro controls](https://learn.chatgpt.com/docs/features/codex-micro), [Codex App Server](https://learn.chatgpt.com/docs/app-server). App Server is not used here: access to the existing desktop task and Fast Mode setting has not been established through it.

## Task discovery foundation

RelayCore includes a read-only task catalog with regression tests for documented App Server summaries and status events. It is not connected to the live desktop. See [Task discovery](docs/TASK-DISCOVERY.md) for freshness, pagination, and the remaining iPhone-only integration decision.
