---
name: architecture
description: Real runtime shape of the four layers and how they call each other over HTTP
type: knowledge
scope: global
updated: 2026-09-18 (IONE-959)
captured_sha: 66675a3ba747fe4209006a396b61416c5b2dfef2
sources:
  - dobase/app/services/twenty_client.rb
  - dobase/app/jobs/twenty_mail_sync_job.rb
  - dobase/app/jobs/caldav_sync_job.rb
  - dobase/app/controllers/api/v1/contacts_controller.rb
  - dobase/config/routes_snippet.rb
  - mcp-server/server.py
  - twenty-apps/dobase-bridge/src/components/DobaseSidebar.tsx
  - shared/design-tokens/shared_tokens.css
sources_sha256:
  dobase/app/controllers/api/v1/contacts_controller.rb: b1b363b741deccd281fd702cb21ad59cfa225573763834cffaaf92ad010bbc00
  dobase/app/jobs/caldav_sync_job.rb: b7b6b4d02ad7a8153aa764ee9206f1c6c56fec00d5d7afd76c9bd164fe05fa71
  dobase/app/jobs/twenty_mail_sync_job.rb: c75636526dc29eecaf0dc5b7775524b1c71fe2f64850103d694fe49d69cdb747
  dobase/app/services/twenty_client.rb: 8ebd3d0ead65a31a5861b655d9e468469625e894bde75648ae072996b9d0ccc3
  dobase/config/routes_snippet.rb: 9f4c0a3bdf990262b69a5af8be7384ec18f0010f5087663a4c261478e9c84ed9
  mcp-server/server.py: 390691875e5b93fe965a9fe4336c01e353017745d9adad42b3059bc2a5f13edb
  shared/design-tokens/shared_tokens.css: 9476661a2685c0da97ea9b9d00f55ffa59c54342aa18c5eda27490dcd0e69296
  twenty-apps/dobase-bridge/src/components/DobaseSidebar.tsx: b124a865fa8736f0c7187971aeefef236d8a681923645d574858d1c9ad67e703
---

```mermaid
flowchart LR
    CalDAV[Radicale CalDAV server]
    Dobase[Dobase Rails app]
    TwentyAPI[Twenty CRM REST API]
    Sidebar[dobase-bridge Twenty SDK app<br/>DobaseSidebar.tsx]
    MCP[MCP server<br/>mcp-server/server.py]
    Tokens[shared_tokens.css]

    Dobase -- "TwentyMailSyncJob → TwentyClient.find_person_by_email<br/>GET /rest/people" --> TwentyAPI
    Dobase -- "TwentyClient.create_activity<br/>POST /rest/timelineActivities" --> TwentyAPI
    Dobase -- "CaldavSyncJob, DOBASE_CALDAV_URL" --> CalDAV
    Sidebar -- "GET /api/v1/contacts/:id/chat_threads,documents,files<br/>Bearer DOBASE_TOKEN" --> Dobase
    MCP -- "search_twenty_contacts, get_twenty_contact_timeline<br/>GET /rest/people, /rest/timelineActivities" --> TwentyAPI
    MCP -- "get_dobase_contact_threads/documents/files<br/>GET /api/v1/contacts/:id/..." --> Dobase
    Tokens -.->|imported by| Dobase
    Tokens -.->|imported by| Sidebar
```

Notes on edges not obvious from the diagram alone:

- The MCP server (`mcp-server/server.py`) talks to **both** Twenty and Dobase directly with its own `httpx` clients and its own `TWENTY_API_KEY`/`DOBASE_API_TOKEN` — it does not go through the Rails `dobase/` layer to reach Twenty. This means Twenty credentials are configured twice in this system (once in `dobase/`, once in `mcp-server/`), each read from its own env var pair.
- `Dobase` is the only layer with a CalDAV edge; the SDK app and MCP server only ever see Dobase's `/api/v1/contacts/:id/...` REST endpoints (routes defined in `dobase/config/routes_snippet.rb`), which are currently stubbed to return `[]` — see [[overview]].
- `shared_tokens.css` has no runtime edge — it's a static file consumed via copy/symlink (Dobase) or `@import` (Twenty core, not in this repo) or `var(--token-name)` (SDK app inline styles).

Diverges from `mcp-server/README.md`: the README's "Architecture note" states "Twenty's native MCP server handles CRM reads/writes. This server handles Dobase communication data." — but `server.py` itself defines `search_twenty_contacts` and `get_twenty_contact_timeline`, which call Twenty's REST API directly (`mcp-server/server.py:28-52`). This server is not limited to Dobase data.
