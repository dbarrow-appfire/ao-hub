---
name: code-style
description: Per-layer code style patterns inferred from existing files — follow these when adding new files in each layer
type: convention
scope: global
updated: '2026-09-14'
captured_sha: 66675a3ba747fe4209006a396b61416c5b2dfef2
sources:
  - dobase/app/jobs/twenty_mail_sync_job.rb
  - dobase/app/services/twenty_client.rb
  - mcp-server/server.py
  - twenty-apps/dobase-bridge/src/components/DobaseSidebar.tsx
sources_sha256:
  dobase/app/jobs/twenty_mail_sync_job.rb: c75636526dc29eecaf0dc5b7775524b1c71fe2f64850103d694fe49d69cdb747
  dobase/app/services/twenty_client.rb: 8ebd3d0ead65a31a5861b655d9e468469625e894bde75648ae072996b9d0ccc3
  mcp-server/server.py: 390691875e5b93fe965a9fe4336c01e353017745d9adad42b3059bc2a5f13edb
  twenty-apps/dobase-bridge/src/components/DobaseSidebar.tsx: b124a865fa8736f0c7187971aeefef236d8a681923645d574858d1c9ad67e703
---

Layer ownership and languages are already documented in
[CONTRIBUTING.md](../../CONTRIBUTING.md). This page covers the finer style patterns
actually used in the existing files, which aren't written down anywhere.

## Ruby (`dobase/`)

- Every file starts with `# frozen_string_literal: true`.
- Services are plain modules with `self.` class methods (`TwentyClient`,
  `TwentySync::CalendarEvent`), not instantiated classes — no `initialize`/instance state.
- Jobs (`ApplicationJob` subclasses) declare `queue_as :integrations` and keep `perform`
  to a few lines that delegate to a service object; no business logic in the job itself.
- Env vars are read via `ENV.fetch(...)` (raises if missing) in service modules, not in
  jobs or controllers.

## Python (`mcp-server/`)

- Every network-calling tool is `async def`, decorated `@mcp.tool()`, opens its own
  `async with httpx.AsyncClient() as client:` per call (no shared/module-level client).
- Every tool calls `resp.raise_for_status()` before touching `resp.json()` — new tools
  added here should keep doing this even though the Ruby side doesn't (see [[gotchas]]).
- Header-building is factored into small `_dobase_headers()` / `_twenty_headers()`
  helpers rather than inlined per call.

## TypeScript/React (`twenty-apps/dobase-bridge/`)

- One `interface` per API shape declared at the top of the file, matching the JSON the
  corresponding Dobase endpoint returns (`DobaseThread`, `DobaseDocument`, `DobaseFile`).
- Inline styles via a `const styles: Record<string, React.CSSProperties>` object at the
  bottom of the file, referencing `var(--token-name)` from
  `shared/design-tokens/shared_tokens.css` rather than hardcoded colors/sizes.
- `tsconfig.json` has `strict: true` — new components should type props/state explicitly
  (as `DobaseSidebarProps` does) rather than relying on inference.
