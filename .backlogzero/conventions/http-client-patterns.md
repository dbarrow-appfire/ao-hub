---
name: http-client-patterns
description: Recurring HTTP client conventions (auth headers, Twenty filter syntax, edge/node unwrapping) shared across the Ruby and Python layers
type: convention
scope: global
updated: 2026-09-18 (IONE-959)
captured_sha: 66675a3ba747fe4209006a396b61416c5b2dfef2
sources:
  - dobase/app/services/twenty_client.rb
  - mcp-server/server.py
  - twenty-apps/dobase-bridge/src/components/DobaseSidebar.tsx
sources_sha256:
  dobase/app/services/twenty_client.rb: 8ebd3d0ead65a31a5861b655d9e468469625e894bde75648ae072996b9d0ccc3
  mcp-server/server.py: 390691875e5b93fe965a9fe4336c01e353017745d9adad42b3059bc2a5f13edb
  twenty-apps/dobase-bridge/src/components/DobaseSidebar.tsx: b124a865fa8736f0c7187971aeefef236d8a681923645d574858d1c9ad67e703
---

Layer ownership, branch naming, and commit message format are defined in [CONTRIBUTING.md](../../CONTRIBUTING.md) — follow that for workflow. This page covers patterns that recur in the HTTP client code across layers but aren't written down anywhere.

## Auth header shape

Every layer that calls Twenty or Dobase sends `Authorization: Bearer <token>` built by a small dedicated helper, never inlined at the call site:

- Ruby: `TwentyClient.auth_headers` (`dobase/app/services/twenty_client.rb:24-26`)
- Python: `_twenty_headers()` / `_dobase_headers()` (`mcp-server/server.py:19-24`)
- TSX: inline `opts` object built once before the `Promise.all` (`DobaseSidebar.tsx:46`)

When adding a new outbound call in any of these files, reuse the existing header helper rather than constructing headers inline.

## Twenty REST filter syntax

Twenty's REST API is queried with `field[operator]:value` filter strings, e.g. `"name.firstName[ilike]:%{query}%"` (`mcp-server/server.py:33`) and `"email.primaryEmail[eq]:#{email}"` (`dobase/app/services/twenty_client.rb:10`). This is Twenty's own query DSL, not something either client library builds for you — any new Twenty REST call needs the filter string hand-built in this form.

## Response unwrapping differs by success handling, not by shape

Both the Ruby and Python clients unwrap Twenty list responses the same way — `data.<resource>.edges[].node` — but only the Python side calls `resp.raise_for_status()` before doing so (`mcp-server/server.py:36,50`). `TwentyClient` (Ruby) does not check HTTParty's response status at all before calling `.dig` (`dobase/app/services/twenty_client.rb:13`), so a non-2xx Twenty response silently returns `nil` there instead of raising. Match whichever layer you're editing — don't assume Ruby call sites will raise on HTTP errors.
