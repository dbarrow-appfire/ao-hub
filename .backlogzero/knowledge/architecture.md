---
name: architecture
description: Verified data-flow diagram across the four integration layers and the external systems they talk to
type: knowledge
scope: global
updated: 2026-09-14 (DEV-104)
captured_sha: 492f9d5bd926b27f7cba2372be82c0188e89816f
sources:
  - dobase/app/jobs/twenty_mail_sync_job.rb
  - dobase/app/jobs/caldav_sync_job.rb
  - dobase/app/jobs/caldav_sync_scheduler_job.rb
  - dobase/app/services/twenty_client.rb
  - dobase/app/services/twenty_sync/calendar_event.rb
  - dobase/app/controllers/api/v1/contacts_controller.rb
  - dobase/config/routes_snippet.rb
  - twenty-apps/dobase-bridge/src/components/DobaseSidebar.tsx
  - mcp-server/server.py
sources_sha256:
  dobase/app/controllers/api/v1/contacts_controller.rb: b1b363b741deccd281fd702cb21ad59cfa225573763834cffaaf92ad010bbc00
  dobase/app/jobs/caldav_sync_job.rb: ac6fd99e1eef90f34d03601c3f70a7ebd1012689d0ed47e58530e936b581df0a
  dobase/app/jobs/caldav_sync_scheduler_job.rb: 01a85eedeed25bc793edb9ee0b0754d2473cc2d338c18d16302fd7022a320fda
  dobase/app/jobs/twenty_mail_sync_job.rb: c75636526dc29eecaf0dc5b7775524b1c71fe2f64850103d694fe49d69cdb747
  dobase/app/services/twenty_client.rb: aca64bc94ce26568047fe805db7ff9fd8a361a16b5cd6526e18b46740d31449e
  dobase/app/services/twenty_sync/calendar_event.rb: 4fbd83d748477ba88489b86951e6bd845f9c42a66df94383597f982448f9e36c
  dobase/config/routes_snippet.rb: 9f4c0a3bdf990262b69a5af8be7384ec18f0010f5087663a4c261478e9c84ed9
  mcp-server/server.py: 390691875e5b93fe965a9fe4336c01e353017745d9adad42b3059bc2a5f13edb
  twenty-apps/dobase-bridge/src/components/DobaseSidebar.tsx: b124a865fa8736f0c7187971aeefef236d8a681923645d574858d1c9ad67e703
---

```mermaid
flowchart LR
    subgraph Dobase["Dobase Rails app (patched)"]
        CaldavScheduler["CaldavSyncSchedulerJob\n(every 15 min)"] -->|perform_later per user| CaldavJob["CaldavSyncJob"]
        MailJob["TwentyMailSyncJob"]
        ContactsAPI["Api::V1::ContactsController\n/api/v1/contacts/:id/{chat_threads,documents,files}"]
    end

    Radicale[("Radicale CalDAV server\nDOBASE_CALDAV_URL")]
    TwentyREST[("Twenty CRM REST API\nTWENTY_API_URL")]

    CaldavJob -->|list events| Radicale
    CaldavJob -->|normalize + upsert| CalEvt["TwentySync::CalendarEvent"]
    CalEvt -->|find/create/update task,\nfind person, link taskTarget| TwentyClient["TwentyClient service"]
    MailJob -->|find person + create timeline activity| TwentyClient
    TwentyClient -->|HTTParty REST calls| TwentyREST

    Sidebar["DobaseSidebar.tsx\n(Twenty SDK app, browser)"] -->|fetch, Bearer DOBASE_TOKEN| ContactsAPI
    MCP["mcp-server/server.py\n(FastMCP tools)"] -->|httpx, Bearer DOBASE_API_TOKEN| ContactsAPI
    MCP -->|httpx, Bearer TWENTY_API_KEY| TwentyREST

    Tokens["shared/design-tokens/shared_tokens.css"] -.->|CSS vars, no runtime link| Sidebar
```

## Non-obvious edges

- `ContactsAPI` is currently a stub: `chat_threads`, `documents`, and `files` all `render json: []` (marked `# TODO: DEV-114/115/116` in [dobase/app/controllers/api/v1/contacts_controller.rb](../../dobase/app/controllers/api/v1/contacts_controller.rb)). Both consumers of this endpoint — `DobaseSidebar.tsx` and the three `get_dobase_contact_*` MCP tools in `mcp-server/server.py` — will always get an empty list until those handlers are implemented. See [knowledge/gotchas.md](gotchas.md).
- `mcp-server/server.py` talks to Twenty's REST API directly (not through `TwentyClient`, which is Ruby-only) — it has its own `httpx`-based auth headers (`_twenty_headers`, `_dobase_headers`).
- `shared_tokens.css` has no build-time or runtime import in this repo; both host apps are expected to copy/symlink/`@import` it per [shared/design-tokens/README.md](../../shared/design-tokens/README.md) — there's no code here that wires it up.
- `TwentySync::CalendarEvent.link_contact` only tries to match the **first** attendee email that resolves to a Twenty person (`person_for` returns on first match, order = `attendee_emails` array order from the iCal `ATTENDEE` lines) — if the organizer is listed before the actual counterparty, the task could get linked to the wrong (or no) person.
