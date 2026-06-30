# GitHub setup and initial commit

Follow these steps to create the GitHub repository and push the scaffold.

## Prerequisites

- [Git](https://git-scm.com/) installed
- [GitHub CLI](https://cli.github.com/) (`gh`) installed and authenticated (`gh auth login`)

## 1. Open a terminal in the project

```powershell
cd "C:\Users\Daniel Barrow\Projects\dobase-twenty-integration"
```

## 2. Initialize git (if not already done)

```powershell
git init
git branch -M main
```

## 3. Review what will be committed

```powershell
git status
```

You should see ~21 files across `dobase/`, `twenty-apps/`, `mcp-server/`, `shared/`, and root docs. `.env` should **not** appear (it is gitignored).

## 4. Stage all files

```powershell
git add .
```

## 5. Create the initial commit

```powershell
git commit -m "Initial scaffold for Dobase + Twenty CRM integration

Four-layer monorepo: webhook bridge, Twenty SDK app, MCP server,
and shared design tokens. Aligned with DEV Jira project and Confluence docs."
```

## 6. Create the GitHub repository

**Option A — using GitHub CLI (recommended):**

```powershell
gh repo create dobase-twenty-integration --public --source=. --remote=origin --description "Dobase + Twenty CRM integration — webhook bridge, SDK app, MCP server, design tokens"
```

Add `--private` instead of `--public` if you want a private repo.

**Option B — create on GitHub.com manually:**

1. Go to https://github.com/new
2. Repository name: `dobase-twenty-integration`
3. Do **not** initialize with README (this repo already has one)
4. Create the repository
5. Link and push:

```powershell
git remote add origin https://github.com/YOUR_USERNAME/dobase-twenty-integration.git
git push -u origin main
```

If you used Option A, push with:

```powershell
git push -u origin main
```

## 7. Verify

```powershell
gh repo view --web
```

Or visit `https://github.com/YOUR_USERNAME/dobase-twenty-integration`.

## Optional next steps

- Add a GitHub Actions workflow for linting
- Link the repo in Confluence [Test Environment Guide](https://danappfire.atlassian.net/wiki/spaces/DEV/pages/85262369)
- Enable Jira GitHub integration for DEV-98 through DEV-143

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `git: command not found` | Install Git for Windows |
| `gh: command not found` | Install GitHub CLI |
| `gh auth` required | Run `gh auth login` |
| Accidentally staged `.env` | `git reset HEAD .env` — never commit secrets |
