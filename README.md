# Dobase + Twenty CRM Integration

Four-layer integration connecting [Dobase](https://github.com/dobase/dobase) (self-hosted workspace) with [Twenty CRM](https://github.com/twentyhq/twenty).

## Architecture

| Layer | Directory | Purpose |
|-------|-----------|---------|
| 1 — Webhook bridge | `dobase/` | Sync mail and calendar from Dobase → Twenty |
| 2 — Twenty SDK app | `twenty-apps/dobase-bridge/` | Surface Dobase chat, docs, and files in Twenty |
| 3 — MCP server | `mcp-server/` | AI-queryable tools for Dobase data |
| 4 — Design tokens | `shared/design-tokens/` | Shared CSS custom properties |

## Documentation

- **Confluence:** [DEV space — Dobase + Twenty CRM Integration](https://danappfire.atlassian.net/wiki/spaces/DEV/pages/85262347)
- **Jira:** [DEV project](https://danappfire.atlassian.net/jira/software/projects/DEV) (DEV-98 through DEV-143)

## Repository layout

```
dobase-twenty-integration/
├── dobase/                         # Rails patches (jobs, services, API)
│   ├── app/
│   │   ├── jobs/
│   │   ├── services/
│   │   └── controllers/api/v1/
│   └── README.md
├── twenty-apps/
│   └── dobase-bridge/              # Twenty SDK app
├── shared/
│   └── design-tokens/
│       └── shared_tokens.css
├── mcp-server/                     # fast-mcp tools
├── docs/
│   └── ENVIRONMENT.md
└── .env.example
```

## Getting started

1. Copy `.env.example` to `.env` and fill in credentials.
2. See each layer's README for setup instructions.
3. Follow the [Implementation Sequence](https://danappfire.atlassian.net/wiki/spaces/DEV/pages/85196802) in Confluence.

## GitHub

See [docs/GITHUB_SETUP.md](docs/GITHUB_SETUP.md) for initial commit and push instructions.

## Key constraints

- **One-way writes:** Dobase → Twenty for activity sync only
- **No Kanban/Todo sync** between Dobase and Twenty pipeline
- **File references only** — binary content is never copied to Twenty
