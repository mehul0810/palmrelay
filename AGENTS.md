# PalmRelay development

- The product controls the user's existing desktop ChatGPT/Codex session. Do not substitute a separate AI runtime or API chat product without the owner's direction.
- Do not claim a control works until actual desktop state changes are verified. Demo state is never live state.
- Preserve pairing authentication, encryption, local opt-in, unavailable capability states, stale-command checks, and explicit acknowledgement. Never retry a timed-out mutation automatically.
- No credential scraping, private endpoint or hardware identity impersonation, global keystroke injection, or arbitrary shell/script commands from the phone.
- Do not bypass a tool's app-access restriction using another automation method. Leave the specific live verification for the user when necessary.
- Approval responses require exact structured request context. Do not map generic approval buttons through Accessibility.
- Read current Git status and repository rules before publishing. No force pushes, destructive cleanup, protected-branch writes, permission changes, releases, deploys, or App Store/TestFlight submission without explicit owner approval.
- Run `swift test` and compile both Xcode schemes for changes to shared code. Keep generated project changes deterministic with `scripts/generate-project.py`.
- Keep local-only data and credentials out of commits. Do not invent a signing team or add a license without an owner decision.
