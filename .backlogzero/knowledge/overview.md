---
name: overview
description: What this repo is (four-layer Dobase↔Twenty CRM integration scaffold) and its current implementation status
type: knowledge
scope: global
updated: 2026-09-18 (IONE-959)
captured_sha: 66675a3ba747fe4209006a396b61416c5b2dfef2
sources:
  - README.md
  - dobase/app/controllers/api/v1/contacts_controller.rb
  - dobase/app/services/twenty_sync/calendar_event.rb
  - dobase/app/jobs/caldav_sync_job.rb
sources_sha256:
  README.md: 8958065db0c391b2d6d39df33c262bb5f206849a5aca44d1a52da55c5705fd95
  dobase/app/controllers/api/v1/contacts_controller.rb: b1b363b741deccd281fd702cb21ad59cfa225573763834cffaaf92ad010bbc00
  dobase/app/jobs/caldav_sync_job.rb: b7b6b4d02ad7a8153aa764ee9206f1c6c56fec00d5d7afd76c9bd164fe05fa71
  dobase/app/services/twenty_sync/calendar_event.rb: fcd37eb5e8cdc345744d6897835790e368030903e6bc3a260136841675818ec4
---

Four-layer architecture (webhook bridge, Twenty SDK app, MCP server, shared design tokens) and the key constraints (one-way Dobase→Twenty writes, no Kanban sync, file references only) are documented in [README.md](../../README.md). Layer ownership, branch naming, and commit conventions are in [CONTRIBUTING.md](../../CONTRIBUTING.md).

## Implementation status (not stated in README)

This is a **scaffold**, not a working integration — most of the wiring exists but the business logic is stubbed:

- `Api::V1::ContactsController#chat_threads`, `#documents`, `#files` all hardcode `render json: []` (see `dobase/app/controllers/api/v1/contacts_controller.rb:9,13,17`, tagged `TODO: DEV-114/115/116`). Every consumer of the Dobase API layer — the Twenty SDK sidebar (`DobaseSidebar.tsx`) and the MCP server tools — will receive empty lists until these are implemented.
- `TwentySync::CalendarEvent.upsert` unconditionally raises `NotImplementedError` (`dobase/app/services/twenty_sync/calendar_event.rb:11`). `CaldavSyncJob#perform` calls it for every fetched CalDAV event with no rescue, so **any run of `CaldavSyncJob` that finds one or more events will raise and fail the job**.
- `TwentyMailSyncJob` and `TwentyClient` (mail sync, contact lookup, activity creation) are fully implemented and are the only end-to-end working path in the repo.

When picking up a DEV-1xx ticket in this repo, check whether it's asking you to fill in one of these stubs before assuming supporting infrastructure is missing.
