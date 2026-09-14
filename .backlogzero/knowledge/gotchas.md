---
name: gotchas
description: Non-obvious traps in the current code — secret leakage, unhandled errors, duplicated response parsing
type: knowledge
scope: global
updated: '2026-09-14'
captured_sha: 66675a3ba747fe4209006a396b61416c5b2dfef2
sources:
  - twenty-apps/dobase-bridge/src/components/DobaseSidebar.tsx
  - dobase/app/services/twenty_client.rb
  - mcp-server/server.py
  - dobase/app/services/twenty_sync/calendar_event.rb
sources_sha256:
  dobase/app/services/twenty_client.rb: 8ebd3d0ead65a31a5861b655d9e468469625e894bde75648ae072996b9d0ccc3
  dobase/app/services/twenty_sync/calendar_event.rb: fcd37eb5e8cdc345744d6897835790e368030903e6bc3a260136841675818ec4
  mcp-server/server.py: 390691875e5b93fe965a9fe4336c01e353017745d9adad42b3059bc2a5f13edb
  twenty-apps/dobase-bridge/src/components/DobaseSidebar.tsx: b124a865fa8736f0c7187971aeefef236d8a681923645d574858d1c9ad67e703
---

## `DOBASE_TOKEN` is read client-side in the sidebar component

`DobaseSidebar.tsx:38-39` reads `process.env.DOBASE_URL` / `process.env.DOBASE_TOKEN`
directly inside a React component that renders in the browser. `docs/ENVIRONMENT.md`
lists `DOBASE_TOKEN` as a "Service account token" — a secret. If this component is
bundled as-is into a real Twenty SDK app (client-side JS), the bearer token would ship
in the browser bundle/network requests, not stay server-side. Before wiring this into a
real `create-twenty-app` scaffold, this fetch needs to move behind a server-side proxy
route in the Twenty app rather than calling Dobase directly from the client.

## Twenty REST response shape is parsed twice, independently

Both `dobase/app/services/twenty_client.rb` (Ruby) and `mcp-server/server.py` (Python)
independently unwrap Twenty's GraphQL-over-REST envelope:
`data.<objectName>.edges[].node`. There's no shared schema/type for this — if Twenty's
API shape changes, both implementations need to be updated in lockstep, and nothing
will catch a mismatch at compile time (Ruby: `dig` silently returns `nil` on mismatch;
Python: `.get(...)` chains, silently returns `[]`).

## Ruby HTTP calls don't check for failure

`TwentyClient.find_person_by_email` / `.create_activity` (`dobase/app/services/twenty_client.rb`)
call `HTTParty.get`/`.post` and use the response directly with no status check — a 4xx/5xx
from Twenty is not raised or logged, it just produces a `nil` dig result or a discarded
response. Contrast with `mcp-server/server.py`, which calls `resp.raise_for_status()`
after every `httpx` call. Any Ruby-side sync job silently no-ops on Twenty API errors.

## `CalendarEvent.upsert` always raises

`dobase/app/services/twenty_sync/calendar_event.rb:11` is `raise NotImplementedError`
unconditionally — `CaldavSyncJob#perform` will raise (and, depending on `ApplicationJob`
retry config, may retry forever) as soon as `client.events.list` returns any event. Don't
assume calendar sync "just needs enabling" — it needs the upsert logic implemented first
(tracked as DEV-107).

## Stub endpoints return `[]`, not an error

`Api::V1::ContactsController#chat_threads/#documents/#files` all return `render json: []`
regardless of whether the contact exists. A 200 with an empty array looks identical to "no
data" from the client side (sidebar or MCP tools) — there's no way to distinguish "contact
not found" from "not implemented yet" from "genuinely has none" today.
