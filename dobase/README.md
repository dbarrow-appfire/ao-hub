# Dobase integration patches

Rails code to merge into the Dobase application for Layer 1 (webhook bridge) and Layer 2 prerequisite (API layer).

## Structure

```
dobase/
├── app/
│   ├── jobs/
│   │   ├── twenty_mail_sync_job.rb      # Email → Twenty timeline
│   │   └── caldav_sync_job.rb           # Calendar → Twenty tasks
│   ├── services/
│   │   ├── twenty_client.rb             # Twenty REST API wrapper
│   │   └── twenty_sync/
│   │       └── calendar_event.rb        # Calendar event upsert logic
│   └── controllers/api/v1/
│       └── contacts_controller.rb       # JSON API for SDK app
├── config/
│   └── routes_snippet.rb                # Routes to add to config/routes.rb
└── test/
    ├── jobs/
    │   └── twenty_mail_sync_job_test.rb # Mail sync job tests
    └── services/
        └── twenty_client_test.rb        # Twenty REST wrapper tests
```

## Dependencies (Gemfile)

```ruby
gem 'httparty'
gem 'calendav', '~> 0.5.0'
```

## Environment variables

See root `.env.example` — requires `TWENTY_API_URL`, `TWENTY_API_KEY`, `DOBASE_CALDAV_URL`.

## Mail sync semantics

`TwentyMailSyncJob` (queue `integrations`) takes a Mail id and writes one EMAIL timeline activity to the matching Twenty person.

- The activity id is `UUIDv5(URL_NAMESPACE, 'dobase:mail:<id>')`. The job looks it up before creating, and looks it up again after a failed create, so retries do not duplicate activities.
- `TwentyClient::Error` (non-2xx response or network failure) is retried 5 times with polynomial backoff. The message holds only the verb, path and status or exception class, never the body, headers or query.
- A missing Mail is discarded. A blank correspondent email is skipped. No matching Twenty person returns cleanly.
- Unverified Twenty REST assumptions: the `data.<plural>.edges[].node` envelope, a client-supplied `id` accepted on create, and `GET /rest/timelineActivities/:id` returning `data.timelineActivity` (404 when absent).
- Nothing enqueues the job yet.

Run the tests from a Dobase checkout with `bin/rails test test/jobs test/services`. The test files set dummy `TWENTY_API_URL` and `TWENTY_API_KEY` if they are not already set.

## Documentation

- [Webhook Bridge](https://danappfire.atlassian.net/wiki/spaces/DEV/pages/85458945)
- [Dobase API Layer](https://danappfire.atlassian.net/wiki/spaces/DEV/pages/85655553)

## Jira

- Epic DEV-98 (Webhook Bridge)
- Story DEV-111 (Dobase API Layer)
