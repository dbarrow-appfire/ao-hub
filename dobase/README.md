# Dobase integration patches

Rails code to merge into the Dobase application for Layer 1 (webhook bridge) and Layer 2 prerequisite (API layer).

## Structure

```
dobase/
├── app/
│   ├── jobs/
│   │   ├── twenty_mail_sync_job.rb      # Email → Twenty timeline
│   │   ├── caldav_sync_job.rb           # Calendar → Twenty tasks, one user per run
│   │   └── caldav_sync_schedule_job.rb  # Fans out caldav_sync_job.rb per user
│   ├── models/
│   │   └── twenty_calendar_sync.rb      # CalDAV occurrence → Twenty task mapping
│   ├── services/
│   │   ├── twenty_client.rb             # Twenty REST API wrapper
│   │   └── twenty_sync/
│   │       ├── calendar_event.rb        # Task upsert/prune logic
│   │       └── event_occurrences.rb     # iCalendar → occurrences parser (pure)
│   └── controllers/api/v1/
│       └── contacts_controller.rb       # JSON API for SDK app
├── config/
│   ├── recurring_snippet.yml            # 15-minute schedule to add to config/recurring.yml
│   └── routes_snippet.rb                # Routes to add to config/routes.rb
└── db/
    └── migrate/
        └── 20261002000000_create_twenty_calendar_syncs.rb
```

## Dependencies (Gemfile)

```ruby
gem 'httparty'
gem 'calendav', '~> 0.5.0'
# calendav returns raw iCalendar; this expands RRULE/RDATE/EXDATE into per-occurrence times (pinned to the verified version).
gem 'icalendar-recurrence', '~> 1.2.1'
```

`icalendar-recurrence` pulls in `icalendar` and `ice_cube`.

## Install

1. Add the gems above to the Dobase `Gemfile` and run `bundle install`.
2. Copy `app/` into the Dobase app.
3. Copy `db/migrate/20261002000000_create_twenty_calendar_syncs.rb` into Dobase's `db/migrate/` and run
   `bin/rails db:migrate`. It creates `twenty_calendar_syncs` with a foreign key to `users`.
4. Paste the uncommented `production:` block from `config/recurring_snippet.yml` into `config/recurring.yml`
   (Solid Queue). Make sure a Solid Queue scheduler is running and a worker serves the `integrations` queue.
   The snippet also shows sidekiq-cron and whenever equivalents for other backends.
5. Paste `config/routes_snippet.rb` (uncommented) inside `config/routes.rb`.
6. Set the environment variables below.

Calendar sync expects `User#email`, `User#caldav_url` (the user's calendar URL) and `User#caldav_token` on the
host app's `User` model. Users with a blank `caldav_url` or `caldav_token` are skipped.

## Environment variables

See root `.env.example` and `docs/ENVIRONMENT.md` — requires `TWENTY_API_URL`, `TWENTY_API_KEY`,
`DOBASE_CALDAV_URL` and `DOBASE_API_TOKEN`.

## Calendar sync semantics

- **Schedule.** Every 15 minutes `CaldavSyncScheduleJob` enqueues one `CaldavSyncJob` per user with CalDAV
  credentials. On Solid Queue, `limits_concurrency` keeps one run per user at a time.
- **Window.** Each run lists events in `[now, now + 37 days)`. Occurrences starting exactly at the end of
  the window are excluded.
- **Identity.** Each occurrence is tracked by a `twenty_calendar_syncs` row keyed by the event `UID`. For an
  occurrence of a recurring event the key is `UID|<original start as ISO8601 UTC>`.
- **Recurring events.** RRULE/RDATE series are expanded, so each occurrence in the window becomes its own
  Twenty task. EXDATEs are skipped. A `RECURRENCE-ID` override replaces the occurrence it moves and keeps that
  occurrence's key.
- **Create / update.** A new key creates a task. A known key updates the same task only when its content
  (title, description, location, times, all-day flag, attendees) has changed. If the task was deleted in
  Twenty, it is recreated. The mapping row stores the task id and content hash only after Twenty accepts the
  write.
- **Delete.** A task is deleted, and its row destroyed, when an in-window occurrence is gone from CalDAV or
  marked `STATUS:CANCELLED`. A task that is already gone in Twenty counts as deleted. Rows whose occurrence
  is now in the past are never pruned.
- **Contact links.** Attendee and organizer emails, excluding the user's own, are matched to Twenty people
  by primary email. Each match becomes a task target. Events with no match are still synced, without a
  target. On update, only person targets are reconciled; links to other records are left alone.
- **Failures.** A Twenty error raises `TwentyClient::Error` (method, path and status only) and the job fails,
  so the backend retries it. Pruning only runs after the listing and every upsert succeed, so a failed run
  never deletes tasks. Unparseable calendar data is logged with the user id and ETag, and that resource's
  existing tasks are kept.
- **One-way.** Edits made to a task in Twenty are not written back to CalDAV. They are overwritten the
  next time the event changes.

### Unverified Twenty REST shapes

These request and response shapes have not been checked against a live Twenty instance. Verify them
against the targeted Twenty version before relying on calendar sync:

- `POST /rest/tasks` with `title`, `dueAt` and `bodyV2.markdown`, returning the id at `data.createTask.id`
  (`data.id` and a top-level `id` are also accepted). A missing id raises
  `TwentySync::CalendarEvent::MissingTaskId`.
- `PATCH`/`DELETE /rest/tasks/:id`, returning 404 for a task that no longer exists.
- `POST /rest/taskTargets` with `taskId` and `personId`, returning the id at `data.createTaskTarget.id`
  (same fallbacks).
- `GET /rest/taskTargets?filter=taskId[eq]:<id>`, returning `data.taskTargets.edges[].node`. A different
  envelope reads as no targets, so every update would add duplicate targets instead of failing.
- `GET /rest/people?filter=email.primaryEmail[eq]:<email>`, shared with mail sync. A different envelope
  reads as no match, so tasks are created without contact links.

## Documentation

- [Webhook Bridge](https://danappfire.atlassian.net/wiki/spaces/DEV/pages/85458945)
- [Dobase API Layer](https://danappfire.atlassian.net/wiki/spaces/DEV/pages/85655553)

## Jira

- Epic DEV-98 (Webhook Bridge)
- DEV-107 (Calendar sync)
- Story DEV-111 (Dobase API Layer)
