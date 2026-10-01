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
└── config/
    └── routes_snippet.rb                # Routes to add to config/routes.rb
```

## Dependencies (Gemfile)

```ruby
gem 'httparty'
gem 'calendav', '~> 0.5.0'
```

## Environment variables

See root `.env.example` — requires `TWENTY_API_URL`, `TWENTY_API_KEY`, `DOBASE_CALDAV_URL`, `DOBASE_API_TOKEN`.

## Mail sync failure handling

`TwentyMailSyncJob` classifies every failed Twenty call (`TwentyClient` raises typed errors; HTTP timeout is 10s):

| Failure | Outcome | Final log event |
|---------|---------|-----------------|
| Network error or timeout, HTTP 429, HTTP 5xx | Retried via ActiveJob `retry_on`: up to 3 executions, waits of 2s then 4s. `Retry-After` is ignored. | `twenty_sync_giving_up` |
| HTTP 401/403 | Discarded, no retry | `twenty_sync_credentials_rejected` |
| Any other 4xx | Discarded, no retry | `twenty_sync_discarded` |
| `TWENTY_API_URL`/`TWENTY_API_KEY` missing or blank | Discarded before any HTTP call | `twenty_sync_skipped` |

Credentials are read when each call is made, not at boot, so missing Twenty vars no longer stop the app from booting.

Each failed attempt also logs `twenty_call_failed` (`warn` while a retry remains, `error` otherwise). Every line has this format:

```
[TwentyMailSyncJob] event=... mail_id=... endpoint="METHOD /path" status=... attempt=N/3 error=<class> message="..."
```

`status` is `network` for network errors and timeouts. Lines never include the API key, the `Authorization` header, the query string, the correspondent email or the subject.

Known limitation: there is no dedupe. If Twenty writes the activity but the response fails (e.g. a timeout or 5xx after the write), the retry creates a duplicate activity.

Requirements: Rails >= 5.1 (ActiveJob), and `webmock` in the host's `:test` group for testing this behaviour. `webmock` is test-only, not a runtime gem.

## Documentation

- [Webhook Bridge](https://danappfire.atlassian.net/wiki/spaces/DEV/pages/85458945)
- [Dobase API Layer](https://danappfire.atlassian.net/wiki/spaces/DEV/pages/85655553)

## Jira

- Epic DEV-98 (Webhook Bridge)
- Story DEV-111 (Dobase API Layer)
