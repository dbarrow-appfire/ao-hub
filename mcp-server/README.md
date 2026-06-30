# Dobase + Twenty MCP Server

Exposes Dobase and Twenty data to LLM-based tools via the Model Context Protocol.

## Setup

```bash
cd mcp-server
python -m venv .venv
.venv\Scripts\activate   # Windows
pip install -r requirements.txt
```

## Run

```bash
export DOBASE_API_URL=http://localhost:3000
export DOBASE_API_TOKEN=your-token
export TWENTY_API_URL=https://app.twenty.com
export TWENTY_API_KEY=your-key

python server.py
```

## Tools

| Tool | Description |
|------|-------------|
| `search_twenty_contacts` | Search Twenty CRM contacts by name or email |
| `get_twenty_contact_timeline` | Fetch timeline activities for a contact |
| `get_dobase_contact_threads` | List Dobase chat threads for a contact |
| `get_dobase_contact_documents` | List Dobase documents for a contact |
| `get_dobase_contact_files` | List Dobase file references for a contact |

## Documentation

- [MCP Server](https://danappfire.atlassian.net/wiki/spaces/DEV/pages/85524481)
- [Setup and Configuration](https://danappfire.atlassian.net/wiki/spaces/DEV/pages/85393410)
- [MCP Tools Reference](https://danappfire.atlassian.net/wiki/spaces/DEV/pages/85721089)

## Jira

- Epic DEV-124 (MCP Server)

## Architecture note

Twenty's native MCP server handles CRM reads/writes. This server handles Dobase communication data. Configure both in your AI client.
