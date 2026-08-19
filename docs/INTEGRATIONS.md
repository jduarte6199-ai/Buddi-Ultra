# Buddi Inbox integrations

The Inbox tab polls three sources every 60 seconds. Tokens are stored in the
macOS login Keychain (never in UserDefaults, never committed). Each section
of the tab shows an inline setup field until its token exists.

## Slack (unread DMs and group DMs)

1. Create an app at https://api.slack.com/apps ("From scratch", BOA workspace).
2. OAuth & Permissions > User Token Scopes:
   `channels:history`, `channels:read`, `groups:history`, `groups:read`,
   `im:history`, `im:read`, `mpim:history`, `mpim:read`, `users:read`.
3. Install to Workspace, copy the User OAuth Token (`xoxp-...`).
4. Paste it in the Inbox tab's Slack section.

v1 surfaces unread direct messages and group DMs (capped at 30 conversations
per refresh). Channel mentions need `search:read` or an events backend and are
deliberately out of scope for the polling MVP.

## ClickUp (my tasks due today or overdue)

1. ClickUp > avatar > Settings > Apps > API Token (`pk_...`).
2. Paste it in the Inbox tab's ClickUp section.

v1 lists open tasks assigned to the token's user with a due date before the
end of today, across every team the token can see. Rows deep-link to the task.

## BOA hub tickets

Buddi calls `GET {hubBaseURL}/api/dev/tickets` with
`Authorization: Bearer <agent token>` and lists tickets whose status is not
closed/done/resolved. Rows link to `{hubBaseURL}/dev`.

### Hub-side work required (boa-hub repo)

The hub currently authenticates that route with Clerk sessions only. To let
Buddi (a native app, no browser session) read and act on tickets:

1. Add an env var `HUB_AGENT_TOKEN` (long random string, one per human).
2. In `src/app/api/dev/tickets/route.ts` (and `[id]` + `[id]/comments`),
   accept `Authorization: Bearer $HUB_AGENT_TOKEN` as an alternative to
   `requireDeveloper()` for GET, PATCH (status changes), and POST comments.
   Constant-time comparison, and log agent-token usage distinctly.
3. Optionally scope the token read-only at first (GET only) and expand to
   PATCH/comment once the Buddi UI grows approve/hold/close buttons.

Until that lands, the hub section shows "Error: HTTP 401", which is expected.

### Buddi-side phase 2 (after the hub endpoint exists)

- Inline actions per ticket row: Start / Hold / Close, comment.
- Amber bubble popup when a new ticket lands (reuse SessionPopupBanner queue).
- Severity-colored badges and a pending-tickets count on the closed notch.
