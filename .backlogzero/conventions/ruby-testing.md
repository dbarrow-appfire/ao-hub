---
name: ruby-testing
description: RSpec conventions used in dobase/spec — instance_double, allow/have_received, one it block per behavior
type: convention
scope:
  - dobase/**
updated: 2026-09-14 (DEV-104)
captured_sha: 492f9d5bd926b27f7cba2372be82c0188e89816f
sources:
  - dobase/spec/jobs/caldav_sync_scheduler_job_spec.rb
  - dobase/spec/services/twenty_sync/calendar_event_spec.rb
sources_sha256:
  dobase/spec/jobs/caldav_sync_scheduler_job_spec.rb: 45cf9fc9fadd97676b776ee57748664bb885ba38a58085c95c19694a1b0008e3
  dobase/spec/services/twenty_sync/calendar_event_spec.rb: 5375b1a81298baadabfeab8f79cabed8759c826d9a4c44f56ec9c5a6ce57edaa
---

Spec files mirror the `app/` path under `spec/` (e.g. `app/services/twenty_sync/calendar_event.rb` → `spec/services/twenty_sync/calendar_event_spec.rb`).

## Patterns observed in both spec files

- Collaborators are stubbed with `instance_double` (for models like `User`) and `allow(Module).to receive(:method)` (for module-level service objects like `TwentyClient`) — no real HTTP calls, no `webmock`/`vcr` fixtures in this repo.
- Assertions use `have_received` (message-spy style) after exercising the subject, not return-value assertions on the stubs themselves.
- Each `it` block tests exactly one behavior/branch (e.g. separate `it`s for "creates a new task" vs. "updates the existing task", rather than one test asserting both).
- Expected payloads are built as a full literal hash (`expected_payload`) and passed to `have_received(...).with(expected_payload)` for an exact match — not a partial/`hash_including` match — even though only a couple of fields vary between tests.

Follow this same shape (per-branch `it` blocks, exact-payload `have_received` assertions, `instance_double`/`allow` over real HTTP) for new specs under `dobase/spec/`.
