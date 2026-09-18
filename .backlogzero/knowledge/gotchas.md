---
name: gotchas
description: Runtime failure modes and a client-side secret exposure risk found by reading the code, not documented elsewhere
type: knowledge
scope: global
updated: 2026-09-18 (IONE-959)
captured_sha: f98d5089dd6598ad4c481f35a75ec8832e189bee
sources:
  - dobase/app/services/twenty_client.rb
  - dobase/app/jobs/twenty_mail_sync_job.rb
  - dobase/spec/services/twenty_client_spec.rb
  - dobase/spec/jobs/twenty_mail_sync_job_spec.rb
sources_sha256:
  dobase/app/jobs/twenty_mail_sync_job.rb: 9515833f6f56859df8b87a53737b14031f7cca8a1af748801b1b21a1412b3df5
  dobase/app/services/twenty_client.rb: 7653ee76f075acd33050a743fc683a72e705258343949f6534467f822157adbd
  dobase/spec/jobs/twenty_mail_sync_job_spec.rb: da76161ef55be8d01ef3156877924fa82573f6b091916c1a7be00819ec657b44
  dobase/spec/services/twenty_client_spec.rb: d5975e012e24f62a8cb82b6d7ffef0625f19f064eb7a34e4be5e91cfc300de2b
---

## `TwentyClient` now checks credentials per-call, not at load time

`base_url` and `api_key` are private class methods (`dobase/app/services/twenty_client.rb:66-78`) that read `ENV['TWENTY_API_URL']`/`ENV['TWENTY_API_KEY']` lazily on every call and raise `TwentyClient::MissingCredentialsError` (not `KeyError`) when either is nil or blank. This replaced the old module-level `BASE = ENV.fetch(...)` constants that raised at Rails autoload time. `TwentyMailSyncJob` specifically rescues `MissingCredentialsError` and logs+skips instead of failing the job (`dobase/app/jobs/twenty_mail_sync_job.rb:17-24`) — any other caller of `TwentyClient` still needs its own rescue if it wants to survive missing credentials rather than propagate the error.

## `TwentyClient` retries only specific failures, with jittered exponential backoff

`with_retry` (`dobase/app/services/twenty_client.rb:95-109`) retries up to `MAX_ATTEMPTS = 3` only for `RETRYABLE_STATUSES` (429/500/502/503/504) and a fixed list of network exceptions (`Net::OpenTimeout`, `Net::ReadTimeout`, `SocketError`, `Errno::ECONNRESET`, `Errno::ECONNREFUSED`) — any other status (e.g. 401, 422) raises `NonRetryableError` immediately with no backoff. Backoff is `(2**attempt) + rand` seconds and uncapped, so specs stub `backoff_sleep` rather than sleeping for real. `log_failure` logs endpoint/status/attempt/error_class as JSON but deliberately excludes the request body, API key, and `Bearer` header — `dobase/spec/services/twenty_client_spec.rb` has a dedicated test asserting the log never contains the secret, `Bearer`, or the queried email.

## `CaldavSyncJob` will always raise on non-empty calendars

`CaldavSyncJob#perform` (`dobase/app/jobs/caldav_sync_job.rb:22`) calls `TwentySync::CalendarEvent.upsert` for every event it fetches, with no rescue. `CalendarEvent.upsert` is a stub that always raises `NotImplementedError` (`dobase/app/services/twenty_sync/calendar_event.rb:11`). Any invocation of this job against a calendar with ≥1 upcoming event in the next 37 days will fail the job. Don't assume the job "just needs scheduling" — the upsert logic itself (DEV-107) is unwritten.

## `DobaseSidebar.tsx` reads secrets via `process.env` in a React component

`DOBASE_URL` and `DOBASE_TOKEN` are read with `process.env.DOBASE_URL` / `process.env.DOBASE_TOKEN` directly inside the component body (`twenty-apps/dobase-bridge/src/components/DobaseSidebar.tsx:38-39`), then sent as a `Bearer` header from the browser (`fetch(..., opts)`). Unless the Twenty SDK build step inlines these at build time from a server-only source, this pattern risks shipping `DOBASE_TOKEN` into the client bundle. When implementing this for real, route the fetch through a server-side proxy instead of calling Dobase directly from client code with a bearer token.

## Dobase API stub endpoints always return `[]`

`Api::V1::ContactsController#chat_threads`/`#documents`/`#files` (`dobase/app/controllers/api/v1/contacts_controller.rb:9,13,17`) are hardcoded to `render json: []`. Both `DobaseSidebar.tsx` and the MCP server's `get_dobase_contact_*` tools call these endpoints, so testing either of those consumers end-to-end will show "no threads/documents/files" regardless of real Dobase data until DEV-114/115/116 are implemented. See [[overview]].
