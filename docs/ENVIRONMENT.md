# Environment Variables

See [Confluence — Environment Variables](https://danappfire.atlassian.net/wiki/spaces/DEV/pages/85786648) for full documentation.

| Variable | App | Purpose |
|----------|-----|---------|
| `TWENTY_API_URL` | Dobase (Rails) | Base URL of Twenty REST API |
| `TWENTY_API_KEY` | Dobase (Rails) | API key from Twenty Settings → API & Webhooks |
| `DOBASE_CALDAV_URL` | Dobase (Rails) | Root URL of Radicale CalDAV server |
| `DOBASE_URL` | Twenty SDK App | Base URL of Dobase API layer |
| `DOBASE_TOKEN` | Twenty SDK App | Scoped service account token for the SDK app's `/api/v1` calls; independently rotatable |
| `DOBASE_API_URL` | MCP server | Dobase base URL for API calls |
| `DOBASE_API_TOKEN` | MCP server | Separate scoped service account token for the MCP server; must not reuse `DOBASE_TOKEN` |

Never commit secrets. Use `.env` locally and your platform's secret manager in production. See [Token Strategy](./TOKEN_STRATEGY.md) for the security decision, scopes, and rotation approach.
