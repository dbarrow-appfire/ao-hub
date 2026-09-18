2026-09-18 · first-run · created .backlogzero

- Indexed the four-layer Dobase↔Twenty CRM scaffold (dobase/, twenty-apps/dobase-bridge/, mcp-server/, shared/design-tokens/).
- Wrote knowledge/overview.md: repo is a scaffold with several stubbed endpoints (contacts_controller, CalendarEvent.upsert) that consumers depend on.
- Wrote knowledge/architecture.md: mermaid flowchart of the real HTTP call graph across the four layers, including the divergence in mcp-server/README.md's architecture note (the MCP server calls Twenty directly, not just Dobase).
- Wrote knowledge/gotchas.md: load-time env var failure in TwentyClient, guaranteed NotImplementedError in CaldavSyncJob, client-side secret exposure risk in DobaseSidebar.tsx, and the always-empty Dobase API stubs.
- Wrote conventions/http-client-patterns.md: shared auth-header helper pattern, Twenty's REST filter DSL, and the Ruby-vs-Python difference in HTTP error handling before unwrapping responses.
