"""Dobase + Twenty MCP server — exposes cross-system tools for LLM agents."""

import os

import httpx
from dotenv import load_dotenv
from fastmcp import FastMCP

load_dotenv()

mcp = FastMCP("dobase-twenty")

DOBASE_API_URL = os.environ.get("DOBASE_API_URL", "")
DOBASE_API_TOKEN = os.environ.get("DOBASE_API_TOKEN", "")
TWENTY_API_URL = os.environ.get("TWENTY_API_URL", "")
TWENTY_API_KEY = os.environ.get("TWENTY_API_KEY", "")


def _dobase_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {DOBASE_API_TOKEN}"}


def _twenty_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {TWENTY_API_KEY}"}


@mcp.tool()
async def search_twenty_contacts(query: str) -> list[dict]:
    """Search Twenty CRM contacts by name or email fragment."""
    async with httpx.AsyncClient() as client:
        resp = await client.get(
            f"{TWENTY_API_URL}/rest/people",
            params={"filter": f"name.firstName[ilike]:%{query}%"},
            headers=_twenty_headers(),
        )
        resp.raise_for_status()
        edges = resp.json().get("data", {}).get("people", {}).get("edges", [])
        return [e["node"] for e in edges]


@mcp.tool()
async def get_twenty_contact_timeline(person_id: str) -> list[dict]:
    """Fetch timeline activities for a Twenty contact."""
    async with httpx.AsyncClient() as client:
        resp = await client.get(
            f"{TWENTY_API_URL}/rest/timelineActivities",
            params={"filter": f"linkedObjectRecordId[eq]:{person_id}"},
            headers=_twenty_headers(),
        )
        resp.raise_for_status()
        edges = resp.json().get("data", {}).get("timelineActivities", {}).get("edges", [])
        return [e["node"] for e in edges]


@mcp.tool()
async def get_dobase_contact_threads(contact_id: str) -> list[dict]:
    """List Dobase chat threads for a contact."""
    async with httpx.AsyncClient() as client:
        resp = await client.get(
            f"{DOBASE_API_URL}/api/v1/contacts/{contact_id}/chat_threads",
            headers=_dobase_headers(),
        )
        resp.raise_for_status()
        return resp.json()


@mcp.tool()
async def get_dobase_contact_documents(contact_id: str) -> list[dict]:
    """List Dobase documents linked to a contact."""
    async with httpx.AsyncClient() as client:
        resp = await client.get(
            f"{DOBASE_API_URL}/api/v1/contacts/{contact_id}/documents",
            headers=_dobase_headers(),
        )
        resp.raise_for_status()
        return resp.json()


@mcp.tool()
async def get_dobase_contact_files(contact_id: str) -> list[dict]:
    """List Dobase file references for a contact (metadata only)."""
    async with httpx.AsyncClient() as client:
        resp = await client.get(
            f"{DOBASE_API_URL}/api/v1/contacts/{contact_id}/files",
            headers=_dobase_headers(),
        )
        resp.raise_for_status()
        return resp.json()


if __name__ == "__main__":
    mcp.run()
