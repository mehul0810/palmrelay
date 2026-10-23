# Read-only task discovery foundation

This milestone adds a transport-independent `TaskCatalog` to RelayCore. It is
compiled into both app targets but is not connected to the live desktop or UI.
It does not enable any controls, approvals, pairing, listeners, or new runtime.

## Protocol boundary

The [official App Server documentation](https://learn.chatgpt.com/docs/app-server)
was reviewed on 2026-10-23. `thread/list` provides cursor-paginated summaries with
runtime status. `thread/status/changed` reports a thread ID and its new status.
`notLoaded` means not loaded, not completed. Names may be absent. The catalog
uses IDs for identity and does not decode preview text, transcript paths, or turns.
Unknown status types remain explicitly unknown.

The future supported connection owner must correlate JSON-RPC responses, decode
only their result into `TaskListPage`, and serialize catalog access with status
events. Call `refresh()` for a new snapshot/connection, retain the returned session
token, and pass the exact `nextRequest` for each page. Pass that session token with
each decoded status notification. Call `disconnect()` as soon as the connection is
lost. A reconnect must start a new refresh before delivering results or events.
Do not resume a task merely to discover it.

## Behavior

- Refresh clears the previous list and invalidates outstanding requests/events.
- Each accepted page advances exactly once. Duplicate IDs within a page, empty
  IDs, and cursor loops reject the whole page without partial changes.
- Overlap across pages updates by ID; equal titles remain separate tasks.
- Events during pagination take precedence over snapshot status, including when
  the matching task appears in a later page. Unknown events never create rows.
- `phase` distinguishes an incomplete list from a completed empty result.
- Status expires after five seconds based on local receipt time. Future local
  timestamps also show out-of-date status. Disconnection preserves cached names
  but labels all status disconnected. Callers must display `statusLabel`, not a
  raw cached status, when claiming current state.
- Approval-waiting flags are display data and confer no approval capability.

Transport ordering is required: this protocol does not supply a status-event
sequence number. The five-second window is a presentation policy, not proof of
continuous observation. A future integration must arrange read-only refreshes
or mark status stale. Request failure handling must call disconnect or refresh;
there is no mutation retry behavior.

## Architecture remains unresolved

The user's desired iPhone-only control of an existing desktop conversation still
needs an explicitly supported third-party connection/pairing contract. An App
Server response schema does not establish that contract, selected-chat tracking,
or Fast Mode control. This change does not substitute a companion or a separate
AI session for that requirement. The existing uncommitted transport/control work
in `/Users/mehulgohil/Apps/macos/PalmRelay` was inspected only and preserved.

## Verification

Seven regression tests cover documented decoding, future statuses, IDs versus
names, paging overlap, replayed pages, refresh/disconnect invalidation, events
arriving during paging, stale/future timestamps, malformed pages, cursor cycles,
and empty results. The Xcode project is regenerated using the existing script.
Local Xcode builds require the user to accept the installed Xcode license; no
license acceptance or system toolchain change is performed by this milestone.
