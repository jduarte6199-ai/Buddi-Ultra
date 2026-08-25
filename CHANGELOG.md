# Changelog

All notable changes to Buddi Ultra. Versions follow semver; build numbers
increase monotonically for Sparkle.

## 0.2.0 (unreleased)

### Added
- Inbox tab: Slack unread DMs, ClickUp tasks due today or overdue, and BOA
  hub tickets, with inline token setup stored in the Keychain
  (docs/INTEGRATIONS.md).
- Claude activity history in the Inbox: every notch popup (ready, approval,
  meeting) is logged and reviewable after the fact.
- Session popups as a floating dynamic-island bubble under the notch: green
  "Ready" with the chat title and last message, amber "Approve?" with inline
  approve/deny pinned to the exact displayed permission, quick-reply option
  buttons for AskUserQuestion, and blue meeting reminders 10 minutes before
  calendar events.
- Memory monitor in the Buddy tab: RAM and swap pressure bars plus one-click
  cleanup of zombie Claude CLI sessions.
- Jump-to-session from popups and the instances list raises the exact
  VS Code / Cursor / VSCodium / Windsurf window (project-root aware editor
  CLI, exact window via Accessibility when granted).
- Loom quick-launch button in the notch header; starts the recording
  directly when Accessibility is granted.
- Unanswered-chats counter on the closed notch.
- Media source cycling with a vertical swipe over the music box.
- iPhone-style swipe navigation between tabs, with real horizontal scrollers
  (calendar day wheel, shelf strip) keeping their gesture.

### Fixed
- One physical swipe equals one tab switch: inertia extends a gesture but
  can never start one.
- Chat titles and ordering for VS Code sessions (content-block messages).
- Popup event storms from SubagentStop, simultaneous events being dropped,
  and approval popups outliving their permission.
- Host-app focus broken by substring matching in the terminal registry.

## 0.1.3

Upstream baseline (Buddi by TalkValue) plus the Buddi Ultra rebrand.
