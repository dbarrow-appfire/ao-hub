# Contributing

This repository is scaffolded for the Dobase + Twenty CRM integration test environment.

## Workflow

1. Pick a Jira issue from the [DEV project](https://danappfire.atlassian.net/jira/software/projects/DEV)
2. Read the corresponding Confluence page in the [DEV space](https://danappfire.atlassian.net/wiki/spaces/DEV/pages/85262347)
3. Implement in the appropriate layer directory
4. Open a PR referencing the Jira issue (e.g. `DEV-100`)

## Layer ownership

| Directory | Layer | Primary language |
|-----------|-------|------------------|
| `dobase/` | Webhook bridge + API | Ruby |
| `twenty-apps/dobase-bridge/` | Twenty SDK app | TypeScript/React |
| `mcp-server/` | MCP tools | Python |
| `shared/design-tokens/` | CSS tokens | CSS |

## Branch naming

```
feature/DEV-100-twenty-api-client
fix/DEV-103-mail-sync-retry
```

## Commit messages

Reference Jira keys where applicable:

```
DEV-100: add TwentyClient service module
DEV-114: implement chat_threads API endpoint
```
