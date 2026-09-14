# Dobase API and MCP Token Strategy

See [Confluence — Dobase + Twenty CRM Integration Technical Specification v0.1](https://danappfire.atlassian.net/wiki/spaces/DEV/pages/85786648) for the broader integration design this decision sits within.

**Jira:** [DEV-142](https://danappfire.atlassian.net/browse/DEV-142) — Define Dobase API and MCP token strategy.

## 1. Security decision

The MCP server uses its own, separate, least-privilege scoped Dobase service-account
token (`DOBASE_API_TOKEN`) rather than reusing the token issued to the Twenty SDK app
(`DOBASE_TOKEN`).

**Rationale:** Letting the MCP server present a token minted for a different caller —
or letting an LLM agent pass through a token it received from an upstream
caller/user — is the MCP *token-passthrough* anti-pattern, a form of confused deputy:
the receiving service (Dobase) cannot tell whose authority is actually being exercised,
so it ends up granting the MCP server (and anything the LLM agent decides to do with
it) whatever scope was issued for a completely different client. Issuing MCP its own
token means:

- Dobase can scope, rate-limit, audit, and revoke the MCP server's access independently
  of the Twenty SDK app's access.
- A compromise or misuse of one caller's token (e.g. an over-eager LLM agent tool call)
  cannot be used to impersonate the other caller.
- Each token's blast radius is limited to exactly the endpoints that caller needs.

## 2. Token scopes

All tokens below are read-only against the `/api/v1` contact endpoints. None of them
carry delete, admin, or billing scope.

| Token | Used by | Scope granted | Notes |
|-------|---------|----------------|-------|
| `DOBASE_TOKEN` | Twenty SDK app (`DobaseSidebar.tsx`) | Read-only: `GET /api/v1/contacts/:id/chat_threads`, `GET /api/v1/contacts/:id/documents`, `GET /api/v1/contacts/:id/files` | No write/delete/admin/billing scope. |
| `DOBASE_API_TOKEN` | MCP server (`mcp-server/server.py`) | Read-only: `GET /api/v1/contacts/:id/chat_threads`, `GET /api/v1/contacts/:id/documents`, `GET /api/v1/contacts/:id/files` | Separate service-account token from `DOBASE_TOKEN` — see security decision above. No write/delete/admin/billing scope. |
| `TWENTY_API_KEY` | MCP server (`mcp-server/server.py`) | Read-only against Twenty `people` and `timelineActivities` (`GET /rest/people`, `GET /rest/timelineActivities`) | Twenty's permission model does not offer per-key, per-object read/write granularity as fine as Dobase's — this scope is **best-effort**, configured as narrowly as Twenty's API key settings allow, not a hard guarantee enforced by Twenty itself. |

## 3. Secrets storage & rotation

- **Local development:** secrets live in `.env` (gitignored), following the existing
  pattern documented in [ENVIRONMENT.md](./ENVIRONMENT.md).
- **Production:** secrets are stored in the deployment platform's secret manager. No
  specific vendor is mandated; whichever manager is used must provide:
  - encryption at rest
  - access auditing (who read/changed a secret, and when)
  - rotation and revocation without a code deploy
  - runtime injection into the process environment (not baked into container images or
    build artifacts)
- **NFR-3:** secrets must never be logged, in any environment. Log identifiers or
  redacted placeholders, never the raw token value.

## Current state & follow-ups

- `ContactsController#authenticate_api_token!` (`dobase/app/controllers/api/v1/contacts_controller.rb`)
  today constant-time compares the incoming bearer token against a single
  `ENV['DOBASE_API_TOKEN']` — there is currently no way to accept multiple distinct
  tokens (one per caller) at the enforcement layer, which is the gap this document's
  scoping decision depends on closing. Any future multi-token implementation must keep
  using `ActiveSupport::SecurityUtils.secure_compare` (not `==`) to avoid introducing a
  timing side-channel. Tracked as a deferred follow-up ticket.
- `DobaseSidebar.tsx` reads `process.env.DOBASE_TOKEN` directly in a component that
  renders in the browser; if bundled as-is into a real Twenty SDK app, the token would
  ship in client-side JS instead of staying server-side. Recommended fix is a
  server-side proxy route in the Twenty app that holds `DOBASE_TOKEN` and forwards
  requests, so the token never reaches the browser. Tracked as a deferred follow-up
  ticket.
