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
    │   └── twenty_mail_sync_job_test.rb # Mail sync retry, discard and logging
    └── services/
        └── twenty_client_test.rb        # Twenty error classification and redaction
```

## Dependencies (Gemfile)

```ruby
gem 'httparty'
gem 'calendav', '~> 0.5.0'

group :test do
  gem 'webmock', '~> 3.23'
end
```

These go in the host Dobase `Gemfile`; this repo has no Gemfile of its own. WebMock stubs the Twenty HTTP calls in `test/`.

## Environment variables

See root `.env.example` — requires `TWENTY_API_URL`, `TWENTY_API_KEY`, `DOBASE_CALDAV_URL`.

## Failure handling

`TwentyClient` sorts every failed Twenty call into one of these error classes. `TwentyMailSyncJob` then decides what to do with it:

| Failure | Error class | Job behaviour |
|---------|-------------|---------------|
| Network error, timeout (10s), HTTP 429, HTTP 5xx | `TwentyClient::RetryableError` | Retried |
| HTTP 401 / 403 | `TwentyClient::AuthenticationError` (credential error) | Discarded after one try |
| Blank `TWENTY_API_URL` / `TWENTY_API_KEY` | `TwentyClient::ConfigurationError` (configuration error) | Discarded after one try, no request made |
| Any other non-2xx (other 4xx, 3xx), or a non-JSON body from `GET /rest/people` | `TwentyClient::NonRetryableError` | Discarded after one try |

- **Retries:** at most 3 attempts. The waits are 2s and then 4s (`retry_on` with a proc wait, no jitter). If the third attempt fails, the job gives up without raising, so backends with their own retry logic (e.g. Sidekiq) don't retry past the cap.
- **Credential and configuration errors** are discarded rather than retried. Other jobs in the queue keep running.
- **Missing env:** `TWENTY_API_URL` and `TWENTY_API_KEY` are now read when a request is made, not at load time. A blank value fails that one job with `ConfigurationError` (`"TWENTY_API_KEY is not set"`) instead of raising `KeyError` when the module autoloads or the app boots.
- **Logging:** each failed attempt writes one `twenty_mail_sync.failure <json>` line. Attempts that will be retried log at WARN; every other outcome logs at ERROR. The JSON fields are `job`, `job_id`, `mail_id`, `http_method`, `endpoint` (path only, e.g. `/rest/people`), `status` (`null` for network errors), `error_class`, `message`, `attempt`, `max_attempts` and `outcome`. `outcome` is one of `retrying`, `gave_up`, `failed_non_retryable`, `skipped_invalid_credentials` or `skipped_missing_credentials`.
- **Never logged:** the API key, the `Authorization` header, full URLs or query strings, the mail subject and the correspondent email. Error messages contain only the method, path and status. Messages wrapped from network exceptions are redacted, so the key, bearer tokens and email addresses become `[REDACTED]`. ActiveJob's own retry/discard log lines repeat the error message, so they get the same protection.
- **Known limitation:** mail sync is not idempotent. If Twenty saved a `POST /rest/timelineActivities` but the response timed out, the retry creates a duplicate activity.

## Documentation

- [Webhook Bridge](https://danappfire.atlassian.net/wiki/spaces/DEV/pages/85458945)
- [Dobase API Layer](https://danappfire.atlassian.net/wiki/spaces/DEV/pages/85655553)

## Jira

- Epic DEV-98 (Webhook Bridge)
- Story DEV-111 (Dobase API Layer)
