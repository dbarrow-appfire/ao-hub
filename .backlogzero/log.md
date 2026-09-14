2026-09-14 · first-run · created .backlogzero

- Added knowledge/overview.md, knowledge/architecture.md, knowledge/gotchas.md, conventions/ruby-testing.md, conventions/git-workflow.md.
- Key findings: repo is a patch/scaffold overlay (not a runnable app in `dobase/` or `twenty-apps/`); `Api::V1::ContactsController` endpoints are TODO stubs returning `[]`; `dobase/README.md` Gemfile list omits the `icalendar` gem actually required by `caldav_sync_job.rb`; `DobaseSidebar.tsx` reads the Dobase bearer token client-side.
