# dobase-bridge — Twenty SDK App

Native Twenty app that surfaces Dobase chat threads, documents, and files inside CRM detail views.

## Scaffold

This directory is a starter layout. To initialize the official Twenty SDK app:

```bash
cd twenty-apps
npx create-twenty-app@latest dobase-bridge
cd dobase-bridge
yarn twenty auth:login
yarn twenty dev
```

Then merge the `src/` files from this scaffold into the generated app.

## Custom objects

Define in Twenty workspace after deployment:

- **DobaseThread** — chat thread references linked to person
- **DobaseDocument** — document references linked to person or opportunity
- **DobaseFile** — file metadata references (no binary copy)

## Environment variables

| Variable | Purpose |
|----------|---------|
| `DOBASE_URL` | Base URL of Dobase API |
| `DOBASE_TOKEN` | Bearer token for `/api/v1` endpoints |

## Documentation

- [Twenty SDK App](https://danappfire.atlassian.net/wiki/spaces/DEV/pages/85491713)
- [Custom Objects](https://danappfire.atlassian.net/wiki/spaces/DEV/pages/85590040)
- [Embedded React Sidebar](https://danappfire.atlassian.net/wiki/spaces/DEV/pages/85688321)

## Jira

- Epic DEV-110 (Twenty SDK App)
