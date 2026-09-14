# Desktop verification

## Required proof

This build has not been run against the real ChatGPT/Codex UI. The development session's computer-use tool refused access to that app. Do not bypass that restriction with another automation technology. Build and core tests do not prove desktop control.

The user should perform the following check on a disposable task with no pending approval:

1. Run the two apps and complete pairing. Confirm that neither side can control anything before both confirmations.
2. Explicitly grant the companion Accessibility access and enable desktop control.
3. Open the intended ChatGPT/Codex task. Refresh visible controls in PalmRelay Companion.
4. Find and map the exact Fast Mode control. If it is absent, ambiguous, or has no readable boolean Accessibility value, record that result. Do not replace it with an unverified keyboard shortcut, private endpoint, or hardware identity spoofing.
5. Confirm the phone shows the current on/off state. Tap once. Check that the same desktop task changes state and that the phone reports verified state. Tap again and check restoration.
6. Change Fast Mode manually on the desktop. The phone should reflect it after a poll without sending an action.
7. Switch desktop tasks between a state update and a phone command. The stale command must fail or be idempotent; it must not blindly toggle a different task.
8. Disconnect or background the iPhone. Subsequent commands must not run; re-pairing is required.
9. Test mapped New chat, Continue, Send, Voice, reasoning, and workflow buttons individually on disposable content. A successful Accessibility press is dispatch evidence, not evidence that a task completed.

Record desktop app version, macOS version, iPhone/iOS version, mapped control labels, state exposure, and before/after observations. Never include credentials or conversation bodies in a report.

## Known limits

- English default labels are candidates, not verified contracts. Users can select actual labels exposed by their app.
- The adapter scopes scans to the focused window of exactly one supported running app. Two supported app processes make targeting ambiguous and disable controls.
- Tree scanning is bounded. Large or slow windows fail closed.
- Streaming content can change the local view fingerprint and invalidate a command. This favors refusing a stale command over acting on the wrong view.
- A time-of-check/time-of-use race remains possible with UI automation. Structured, task-ID-bound APIs are the preferred long-term adapter.
- Approve/Decline are deliberately not implemented through Accessibility.
- Nearby pairing and physical iPhone-to-Mac transport still need device validation. Crypto unit tests alone do not prove local network discovery.

If Fast Mode is not readable, the first follow-up is finding an officially supported desktop control interface or an explicit, stable Accessibility state. Do not claim the primary use case is delivered until this proof passes.
