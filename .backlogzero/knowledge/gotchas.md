---
name: gotchas
description: Runtime failure modes and a client-side secret exposure risk found by reading the code, not documented elsewhere
type: knowledge
scope: global
updated: 2026-09-18 (IONE-959)
captured_sha: 66675a3ba747fe4209006a396b61416c5b2dfef2
sources:
  - dobase/app/services/twenty_client.rb
  - dobase/app/jobs/caldav_sync_job.rb
  - dobase/app/services/twenty_sync/calendar_event.rb
  - twenty-apps/dobase-bridge/src/components/DobaseSidebar.tsx
  - dobase/app/controllers/api/v1/contacts_controller.rb
sources_sha256:
  dobase/app/controllers/api/v1/contacts_controller.rb: b1b363b741deccd281fd702cb21ad59cfa225573763834cffaaf92ad010bbc00
  dobase/app/jobs/caldav_sync_job.rb: b7b6b4d02ad7a8153aa764ee9206f1c6c56fec00d5d7afd76c9bd164fe05fa71
  dobase/app/services/twenty_client.rb: 8ebd3d0ead65a31a5861b655d9e468469625e894bde75648ae072996b9d0ccc3
  dobase/app/services/twenty_sync/calendar_event.rb: fcd37eb5e8cdc345744d6897835790e368030903e6bc3a260136841675818ec4
  twenty-apps/dobase-bridge/src/components/DobaseSidebar.tsx: b124a865fa8736f0c7187971aeefef236d8a681923645d574858d1c9ad67e703
---

## `TwentyClient` fails at load time if env vars are unset

`BASE = ENV.fetch('TWENTY_API_URL')` and `KEY = ENV.fetch('TWENTY_API_KEY')` are module-level constants (`dobase/app/services/twenty_client.rb:4-5`), evaluated once when the file is first loaded — not lazily per-request. If either var is missing when Rails autoloads `TwentyClient`, it raises `KeyError` at boot/autoload time rather than at call time. `docs/ENVIRONMENT.md` lists these vars but doesn't flag that they're load-time-required.

## `CaldavSyncJob` will always raise on non-empty calendars

`CaldavSyncJob#perform` (`dobase/app/jobs/caldav_sync_job.rb:22`) calls `TwentySync::CalendarEvent.upsert` for every event it fetches, with no rescue. `CalendarEvent.upsert` is a stub that always raises `NotImplementedError` (`dobase/app/services/twenty_sync/calendar_event.rb:11`). Any invocation of this job against a calendar with ≥1 upcoming event in the next 37 days will fail the job. Don't assume the job "just needs scheduling" — the upsert logic itself (DEV-107) is unwritten.

## `DobaseSidebar.tsx` reads secrets via `process.env` in a React component

`DOBASE_URL` and `DOBASE_TOKEN` are read with `process.env.DOBASE_URL` / `process.env.DOBASE_TOKEN` directly inside the component body (`twenty-apps/dobase-bridge/src/components/DobaseSidebar.tsx:38-39`), then sent as a `Bearer` header from the browser (`fetch(..., opts)`). Unless the Twenty SDK build step inlines these at build time from a server-only source, this pattern risks shipping `DOBASE_TOKEN` into the client bundle. When implementing this for real, route the fetch through a server-side proxy instead of calling Dobase directly from client code with a bearer token.

## Dobase API stub endpoints always return `[]`

`Api::V1::ContactsController#chat_threads`/`#documents`/`#files` (`dobase/app/controllers/api/v1/contacts_controller.rb:9,13,17`) are hardcoded to `render json: []`. Both `DobaseSidebar.tsx` and the MCP server's `get_dobase_contact_*` tools call these endpoints, so testing either of those consumers end-to-end will show "no threads/documents/files" regardless of real Dobase data until DEV-114/115/116 are implemented. See [[overview]].
