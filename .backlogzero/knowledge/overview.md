---
name: overview
description: What this repo is, its four layers, and which parts are stubs vs implemented — read first
type: knowledge
scope: global
updated: '2026-09-14'
captured_sha: 66675a3ba747fe4209006a396b61416c5b2dfef2
sources:
  - README.md
  - dobase/app/controllers/api/v1/contacts_controller.rb
  - dobase/app/services/twenty_sync/calendar_event.rb
  - twenty-apps/dobase-bridge/src/components/DobaseSidebar.tsx
sources_sha256:
  README.md: 8958065db0c391b2d6d39df33c262bb5f206849a5aca44d1a52da55c5705fd95
  dobase/app/controllers/api/v1/contacts_controller.rb: b1b363b741deccd281fd702cb21ad59cfa225573763834cffaaf92ad010bbc00
  dobase/app/services/twenty_sync/calendar_event.rb: fcd37eb5e8cdc345744d6897835790e368030903e6bc3a260136841675818ec4
  twenty-apps/dobase-bridge/src/components/DobaseSidebar.tsx: b124a865fa8736f0c7187971aeefef236d8a681923645d574858d1c9ad67e703
---

The four-layer split and directory-to-layer mapping in [README.md](../../README.md) and
[CONTRIBUTING.md](../../CONTRIBUTING.md) are accurate — see those for layer ownership,
branch naming, and commit conventions. This page tracks what's real code vs scaffold,
since the READMEs describe the intended end state, not the current state.

## Implementation status by layer

This repo is an early scaffold (single commit, ~21 files). Most of the actual data-moving
logic is still a stub:

- **`dobase/` (Rails patches)** — not a runnable app, just files meant to be merged into an
  existing Dobase Rails install (per `dobase/README.md`).
  - `TwentyMailSyncJob` and `TwentyClient` (person lookup + activity creation) are fully wired.
  - `CaldavSyncJob` fetches CalDAV events but hands them to
    `TwentySync::CalendarEvent.upsert`, which unconditionally `raise NotImplementedError`
    (`dobase/app/services/twenty_sync/calendar_event.rb:11`, tracked as DEV-107). Calling
    `CaldavSyncJob#perform` today will always raise once it finds ≥1 event.
  - `Api::V1::ContactsController#chat_threads`/`#documents`/`#files` all `render json: []`
    unconditionally (DEV-114/115/116) — auth (`authenticate_api_token!`) is real, the data
    layer is not.
- **`twenty-apps/dobase-bridge/` (Twenty SDK app)** — per its own README this is "a starter
  layout," not a generated Twenty app: there's no `twenty.config`, no app entrypoint, just
  one component (`DobaseSidebar.tsx`) intended to be merged into a real
  `create-twenty-app` scaffold later.
  - Because the backing `ContactsController` endpoints return `[]`, the sidebar's fetches
    always resolve to empty threads/docs/files lists in the current state of the repo.
- **`mcp-server/`** — fully implemented as written; all five `@mcp.tool()` functions make
  real HTTP calls (no stubs). It duplicates the "hit Twenty REST + Dobase `/api/v1`"
  pattern from the other two layers independently in Python.
- **`shared/design-tokens/`** — just a static CSS file; no build step or consumer wiring
  exists in this repo (each side is expected to `@import`/copy it manually per its README).

## Key constraint (already documented, don't re-litigate)

README.md states one-way writes only (Dobase → Twenty) and no Kanban/Todo sync — this is
a hard product constraint, not an oversight. Any new sync job or endpoint should preserve it.
