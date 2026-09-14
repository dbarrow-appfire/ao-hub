---
name: architecture
description: Real runtime call graph between the four layers — who calls what HTTP endpoint
type: knowledge
scope: global
updated: '2026-09-14'
captured_sha: 66675a3ba747fe4209006a396b61416c5b2dfef2
sources:
  - dobase/app/jobs/twenty_mail_sync_job.rb
  - dobase/app/jobs/caldav_sync_job.rb
  - dobase/app/services/twenty_client.rb
  - dobase/app/services/twenty_sync/calendar_event.rb
  - dobase/app/controllers/api/v1/contacts_controller.rb
  - twenty-apps/dobase-bridge/src/components/DobaseSidebar.tsx
  - mcp-server/server.py
sources_sha256:
  dobase/app/controllers/api/v1/contacts_controller.rb: b1b363b741deccd281fd702cb21ad59cfa225573763834cffaaf92ad010bbc00
  dobase/app/jobs/caldav_sync_job.rb: b7b6b4d02ad7a8153aa764ee9206f1c6c56fec00d5d7afd76c9bd164fe05fa71
  dobase/app/jobs/twenty_mail_sync_job.rb: c75636526dc29eecaf0dc5b7775524b1c71fe2f64850103d694fe49d69cdb747
  dobase/app/services/twenty_client.rb: 8ebd3d0ead65a31a5861b655d9e468469625e894bde75648ae072996b9d0ccc3
  dobase/app/services/twenty_sync/calendar_event.rb: fcd37eb5e8cdc345744d6897835790e368030903e6bc3a260136841675818ec4
  mcp-server/server.py: 390691875e5b93fe965a9fe4336c01e353017745d9adad42b3059bc2a5f13edb
  twenty-apps/dobase-bridge/src/components/DobaseSidebar.tsx: b124a865fa8736f0c7187971aeefef236d8a681923645d574858d1c9ad67e703
---

```mermaid
flowchart LR
    subgraph rails["dobase/ (Rails patches)"]
        MailJob["TwentyMailSyncJob"]
        CaldavJob["CaldavSyncJob"]
        TC["TwentyClient"]
        CE["TwentySync::CalendarEvent
        (upsert raises NotImplementedError)"]
        Ctrl["Api::V1::ContactsController
        (chat_threads/documents/files return [])"]
    end

    Radicale[("Radicale CalDAV server
    DOBASE_CALDAV_URL")]
    Twenty[["Twenty CRM REST API
    TWENTY_API_URL"]]

    subgraph sdk["twenty-apps/dobase-bridge/"]
        Sidebar["DobaseSidebar.tsx"]
    end

    subgraph mcp["mcp-server/"]
        MCP["server.py tools"]
    end

    MailJob --> TC
    CaldavJob --> Radicale
    CaldavJob --> CE
    TC -->|"GET /rest/people
    POST /rest/timelineActivities"| Twenty
    Sidebar -->|"GET /api/v1/contacts/:id/
    chat_threads,documents,files"| Ctrl
    MCP -->|"GET /rest/people
    GET /rest/timelineActivities"| Twenty
    MCP -->|"GET /api/v1/contacts/:id/
    chat_threads,documents,files"| Ctrl
```

## Non-obvious edges

- `CaldavJob → CE` exists structurally but `CalendarEvent.upsert` always raises, so no
  CalDAV event ever actually reaches Twenty yet.
- `Sidebar → Ctrl` and `MCP → Ctrl` hit the exact same three Dobase endpoints
  independently (React fetch vs Python httpx) — there is no shared client between them.
- `TC → Twenty` and `MCP → Twenty` both parse the same nested shape,
  `resp.json()["data"]["<type>"]["edges"][*]["node"]`, independently in Ruby and Python.
  See [[gotchas]] for why this matters if Twenty's API response shape ever changes.
- `shared/design-tokens/shared_tokens.css` is not shown above because it has no runtime
  HTTP edge — it's a static asset each side is expected to copy/`@import` manually.
