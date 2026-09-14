---
name: gotchas
description: Sharp edges verified in code — stubbed endpoints, missing gem, client-side token exposure, required env vars with no defaults
type: knowledge
scope: global
updated: 2026-09-14 (DEV-104)
captured_sha: 492f9d5bd926b27f7cba2372be82c0188e89816f
sources:
  - dobase/app/controllers/api/v1/contacts_controller.rb
  - dobase/app/jobs/caldav_sync_job.rb
  - dobase/app/services/twenty_client.rb
  - dobase/README.md
  - twenty-apps/dobase-bridge/src/components/DobaseSidebar.tsx
sources_sha256:
  dobase/README.md: c91ed4e578bcef17bb732a3acac054a9556e41589d55391358af68031c1df6c0
  dobase/app/controllers/api/v1/contacts_controller.rb: b1b363b741deccd281fd702cb21ad59cfa225573763834cffaaf92ad010bbc00
  dobase/app/jobs/caldav_sync_job.rb: ac6fd99e1eef90f34d03601c3f70a7ebd1012689d0ed47e58530e936b581df0a
  dobase/app/services/twenty_client.rb: aca64bc94ce26568047fe805db7ff9fd8a361a16b5cd6526e18b46740d31449e
  twenty-apps/dobase-bridge/src/components/DobaseSidebar.tsx: b124a865fa8736f0c7187971aeefef236d8a681923645d574858d1c9ad67e703
---

## Dobase contact endpoints are unimplemented stubs

`chat_threads`, `documents`, and `files` on `Api::V1::ContactsController` all `render json: []` with `# TODO: DEV-<n>` comments — they are not partially working, they always return an empty array regardless of `contact_id`. Any work that depends on real data flowing through `DobaseSidebar.tsx` or the `get_dobase_contact_threads` / `get_dobase_contact_documents` / `get_dobase_contact_files` MCP tools requires implementing these three controller actions first (DEV-114, DEV-115, DEV-116 per the TODO comments).

## `dobase/README.md` Gemfile list is missing `icalendar`

[dobase/README.md](../../dobase/README.md) lists only `httparty` and `calendav (~> 0.5.0)` under "Dependencies (Gemfile)". Diverges from dobase/README.md: it omits `icalendar`, which `dobase/app/jobs/caldav_sync_job.rb` requires directly (`require 'icalendar'`) and uses to parse `event.calendar_data` in `normalize`. Anyone merging these patches into the host Gemfile needs to add `icalendar` too, or `CaldavSyncJob` will raise `LoadError` at boot.

## `TwentyClient::BASE` / `KEY` use `ENV.fetch` with no default

`dobase/app/services/twenty_client.rb` sets `BASE = ENV.fetch('TWENTY_API_URL')` and `KEY = ENV.fetch('TWENTY_API_KEY')` at module load time with no fallback — if either is unset, requiring this file raises `KeyError` immediately (not a runtime error on first call). `TASK_UID_FIELD` does have a default (`caldavUid`). This matches the "required" framing in `docs/ENVIRONMENT.md`, but note the failure mode is a hard crash at load time, not a graceful runtime error.

## `DOBASE_TOKEN` is read client-side in the Twenty SDK sidebar

`DobaseSidebar.tsx` reads `process.env.DOBASE_URL` / `process.env.DOBASE_TOKEN` directly inside a `useEffect` that runs in the browser and sends the token as a `Bearer` header from the client. For this to work at all, the Twenty SDK build must inline `DOBASE_TOKEN` into the browser bundle, meaning the Dobase service-account token would be visible to anyone who opens dev tools in the Twenty UI. If implementing the real fetch logic here, prefer proxying through a server-side Twenty SDK endpoint rather than shipping the token to the browser.

## `contacts_controller#authenticate_api_token!` compares against an empty-string default

`ENV.fetch('DOBASE_API_TOKEN', '')` falls back to `''` if unset. `secure_compare` is only reached when `token.present?` is true, so an unset `DOBASE_API_TOKEN` still rejects all requests (no requests carry an empty `Authorization` header that would `.present?`) — this is not currently exploitable, but don't remove the `token.present?` guard, since without it an empty incoming token would successfully match an empty-string default.
