# Environment Variables

See [Confluence — Environment Variables](https://danappfire.atlassian.net/wiki/spaces/DEV/pages/85786648) for full documentation.

| Variable | App | Purpose |
|----------|-----|---------|
| `TWENTY_API_URL` | Dobase (Rails) | Base URL of Twenty REST API |
| `TWENTY_API_KEY` | Dobase (Rails) | API key from Twenty Settings → API & Webhooks |
| `DOBASE_CALDAV_URL` | Dobase (Rails) | Root URL of Radicale CalDAV server |
| `CALDAV_SYNC_WINDOW_DAYS` | Dobase (Rails) | Size of the rolling window (in days) for CalDAV event polling; defaults to `37` |
| `TWENTY_TASK_CALDAV_UID_FIELD` | Dobase (Rails) | Name of the Twenty task custom field storing the CalDAV event UID; defaults to `caldavUid` |
| `DOBASE_URL` | Twenty SDK App | Base URL of Dobase API layer |
| `DOBASE_TOKEN` | Twenty SDK App | Service account token for `/api/v1` endpoints |
| `DOBASE_API_URL` | MCP server | Dobase base URL for API calls |
| `DOBASE_API_TOKEN` | MCP server | Token for Dobase API authentication |

Never commit secrets. Use `.env` locally and your platform's secret manager in production.
