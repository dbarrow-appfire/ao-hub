---
name: http-client-patterns
description: Recurring HTTP client conventions (auth headers, Twenty filter syntax, edge/node unwrapping) shared across the Ruby and Python layers
type: convention
scope: global
updated: 2026-09-18 (IONE-959)
captured_sha: f98d5089dd6598ad4c481f35a75ec8832e189bee
sources:
  - dobase/app/services/twenty_client.rb
  - mcp-server/server.py
  - twenty-apps/dobase-bridge/src/components/DobaseSidebar.tsx
sources_sha256:
  dobase/app/services/twenty_client.rb: 7653ee76f075acd33050a743fc683a72e705258343949f6534467f822157adbd
  mcp-server/server.py: 390691875e5b93fe965a9fe4336c01e353017745d9adad42b3059bc2a5f13edb
  twenty-apps/dobase-bridge/src/components/DobaseSidebar.tsx: b124a865fa8736f0c7187971aeefef236d8a681923645d574858d1c9ad67e703
---

Layer ownership, branch naming, and commit message format are defined in [CONTRIBUTING.md](../../CONTRIBUTING.md) — follow that for workflow. This page covers patterns that recur in the HTTP client code across layers but aren't written down anywhere.

## Auth header shape

Every layer that calls Twenty or Dobase sends `Authorization: Bearer <token>` built by a small dedicated helper, never inlined at the call site:

- Ruby: `TwentyClient.auth_headers` (`dobase/app/services/twenty_client.rb:59-61`)
- Python: `_twenty_headers()` / `_dobase_headers()` (`mcp-server/server.py:19-24`)
- TSX: inline `opts` object built once before the `Promise.all` (`DobaseSidebar.tsx:46`)

When adding a new outbound call in any of these files, reuse the existing header helper rather than constructing headers inline.

## Twenty REST filter syntax

Twenty's REST API is queried with `field[operator]:value` filter strings, e.g. `"name.firstName[ilike]:%{query}%"` (`mcp-server/server.py:33`) and `"email.primaryEmail[eq]:#{email}"` (`dobase/app/services/twenty_client.rb:40`). This is Twenty's own query DSL, not something either client library builds for you — any new Twenty REST call needs the filter string hand-built in this form.

## Response status checking now differs by strategy, not by presence

Both the Ruby and Python clients unwrap Twenty list responses the same way — `data.<resource>.edges[].node`. `TwentyClient` (Ruby) used to skip status checking entirely, but as of the retry hardening it checks every response via `check_response!` (`dobase/app/services/twenty_client.rb:80-89`), raising `TwentyClient::RetryableError` for 429/500/502/503/504 or `TwentyClient::NonRetryableError` for any other non-2xx — it no longer silently returns `nil` on failure. Python's `mcp-server/server.py` still just calls `resp.raise_for_status()` once with no retry (`mcp-server/server.py:36,50`). So both layers now raise on HTTP errors, but only the Ruby layer retries transient failures with backoff (see [[gotchas]]) — don't assume the Python layer will retry just because Ruby does.
