# New Opportunities for Buddi Ultra

*Synthesis of six research passes (54 raw ideas), scored against the live codebase at the local checkout. Claims spot-checked by reading `HookSocketServer.swift`, `buddi-hook.py`, `ToolApprovalHandler.swift`, `BuddiSessionBridge.swift`, `SpriteAnimator.swift`, `UsageService.swift`, and `LiveActivityModifier.swift`.*

## Executive summary

Buddi Ultra is already a read-mostly status display, but the code reveals it is one short step from being a **two-way fleet control tower**. Three structural facts dominate the opportunity set. First, the outbound write path is *already proven*: `ToolApprovalHandler.sendMessage()` injects literal text + Enter into any tmux/cmux session, and `ChatView` already uses it per-session, so "answer / broadcast / quick-prompt to live agents from the notch" is new UI on existing infrastructure, not new infrastructure. Second, the attention plumbing (`BuddiSessionBridge.playWaitingForInputNotificationIfNeeded` + `TerminalVisibilityDetector` + NSSound, gated on "is the terminal focused") is the perfect carrier for **Slack/webhook fan-out and a stall watchdog**, the hardest part (detecting an unattended blocked session) is done. Third, the highest-value *ambient* wins exploit the always-visible strip via the existing `liveActivity`/`ActivityType` primitive and the `UsageService` poller: a **collapsed-strip fleet beacon, a burn-rate forecast on the 5h/7d bars, and per-session cost attribution.** The single biggest lever for Jose's reality (many concurrent agents + an agency) is collapsing "which of my N agents is blocked on ME right now" into a zero-click glance, and then letting him resolve it in place.

A note that *raises* feasibility on one headline idea: `BuddyTask.error`/`.success` are not just defined, `SpriteAnimator.swift` and `ASCIISpriteView.swift` already **render** them (red cross, success countdown). Only the `BuddiSessionBridge` phase to task mapping fails to emit them. Lighting up success/error glyphs is therefore nearly free.

## Top 10 Opportunities

| Rank | Opportunity | Impact | Feasibility | Effort | What it does in one line |
|---|---|---|---|---|---|
| 1 | "Who needs me now" beacon in the collapsed strip | 5 | 5 | quick-win | Always-visible pip-row + count of agents blocked on you, click to jump |
| 2 | Reply / approve a blocked session from the notch | 5 | 5 | quick-win | Answer a "waiting for input" or permission prompt in place, no terminal hunt |
| 3 | Slack / webhook fan-out on "needs you" / "done" | 5 | 5 | quick-win | POST to your Slack webhook when an unfocused session stalls or finishes |
| 4 | Light up buddy success/error glyph on outcome | 4 | 5 | quick-win | Green check / red ! on the buddy when a session finishes clean or fails |
| 5 | Burn-rate forecast + pre-emptive rate-limit alert | 5 | 4 | quick-win | "5h cap in ~38 min, resets in 2h" amber alert on the usage bars |
| 6 | Broadcast a prompt to all idle sessions | 5 | 4 | quick-win | Type once, fan "commit + push, summarize" to every waiting agent |
| 7 | Per-session cost & token meter | 5 | 3 | medium | Live "$3.40 / 412k tok" per session by tailing the JSONL transcript |
| 8 | Stuck/stalled-session watchdog | 4 | 4 | quick-win | Flag + ping sessions parked on approval/processing past a threshold |
| 9 | Quick-prompt launcher (hot-key, type, route) | 4 | 4 | medium | Raycast-style global hot-key drops a prompt box that targets a session |
| 10 | Remote-VM session support (add the TCP listener) | 4 | 3 | medium | Surface + approve Railway/cloud agents the hook already streams over SSH |

*Scoring: Impact = value to Jose's multi-agent + agency context (1-5); Feasibility = grounded ease given existing code (1-5). Priority = Impact x Feasibility. Ranks 1-6 all score >= 20.*

## Recommendation: ship the "fleet attention loop"

Ship **beacon (#1) -> in-place reply/approve (#2) -> Slack fan-out (#3)**, with the **buddy success/error glyph (#4)** riding along. They're individually quick wins, share the same plumbing (`SessionStore` phases, `BuddiSessionBridge` attention detection, `ToolApprovalHandler` send/approve, `TerminalVisibilityDetector`), and together convert Buddi from "shows me my agents" into "tells me which agent needs me, lets me unblock it without leaving my current app, and pings me when I've stepped away." Roughly two focused days, zero backend, no new permissions.

**Caveat:** the *reply* leg of #2 and the broadcast of #6 only reach tmux/cmux-backed sessions (the `ChatView` gate proves the send path can't write to a plain-terminal session). The beacon, approve/deny-over-socket, Slack fan-out, watchdog, and buddy glyph have no such constraint, so lead with those.

## Quick wins (under a day each)

1. **Buddy success/error glyph (#4)** ~2h. Single mapping change in `BuddiSessionBridge.swift`; the art already renders `.error`/`.success`.
2. **Slack/webhook fan-out (#3)** ~2-3h. Drop a `URLSession` POST into the existing `playWaitingForInputNotificationIfNeeded` path; one Defaults key + one settings field.
3. **Stuck-session watchdog (#8)** ~3-4h. `SessionState.lastActivity` + `phase` exist; add a `Timer` in `ClaudeSessionMonitor`, reuse the notification path from #3.
4. **Broadcast prompt to idle sessions (#6)** ~3-4h. Loop `ClaudeSessionMonitor.instances`, filter `isInMultiplexer && waitingForInput`, call `sendMessage` per target (with a confirm step).
5. **One-tap canned commands per session** (`/clear`, commit+push, typecheck) ~3-4h. Row actions in `InstanceRow` backed by a Defaults list (mirror `musicControlSlots`).

## Moonshots

1. **Per-session cost meter -> daily fleet digest (#7).** Forward `transcript_path` (one line in `buddi-hook.py`, not currently sent) so Buddi tails each JSONL and sums tokens against a price table (you already maintain one in boa-hub's `api_usage` ledger). Live "$3.40 / 412k tok" per session, rolled into an end-of-day card. ccusage-style accounting, live, in the notch, zero API calls.
2. **Remote-VM control tower (#10).** `buddi-hook.py` already implements the `BUDDI_HOST` TCP path, but `HookSocketServer.swift` binds only `AF_UNIX`. Add a loopback TCP `DispatchSource` behind a toggle; everything downstream keys on `sessionId`. Approve a remote Railway deploy and watch its cost from the same notch as local sessions.
3. **Voice-to-Claude push-to-talk.** Hold a hot-key, dictate via on-device `Speech.framework`, inject the transcript into the active session on release. Honest effort: large (mic entitlement, privacy strings, record animation) — the only genuinely new subsystem here.
