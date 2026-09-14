---
name: git-workflow
description: Branch naming and commit message convention — see CONTRIBUTING.md, with one observed extension
type: convention
scope: global
updated: 2026-09-14 (DEV-104)
captured_sha: 492f9d5bd926b27f7cba2372be82c0188e89816f
sources:
  - CONTRIBUTING.md
sources_sha256:
  CONTRIBUTING.md: f0d0b6e0485437d0bfd17f285655703c047946353b47000f3ce9657264df654f
---

Branch naming (`feature/DEV-100-...`, `fix/DEV-103-...`) and the base commit message convention (`DEV-100: add TwentyClient service module`) are documented in [CONTRIBUTING.md](../../CONTRIBUTING.md) — follow that as the source of truth.

Observed commits on this branch extend the documented format with a conventional-commit type after the Jira key, e.g. `DEV-104: fix: add nil guards and consistent safe navigation in caldav event normalization`. When in doubt, use `DEV-<n>: <type>: <description>` (`fix`, `feat`, etc.) rather than the bare `DEV-<n>: <description>` shown in CONTRIBUTING.md's example.
