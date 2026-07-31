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
└── spec/
    ├── spec_helper.rb
    ├── services/
    │   └── twenty_client_spec.rb
    └── jobs/
        └── twenty_mail_sync_job_spec.rb
```

## Dependencies (Gemfile)

```ruby
gem 'httparty'
gem 'calendav', '~> 0.5.0'
gem 'activejob'

group :test do
  gem 'rspec'
  gem 'webmock'
end
```

## Environment variables

See root `.env.example` — requires `TWENTY_API_URL`, `TWENTY_API_KEY`, `DOBASE_CALDAV_URL`.

## Resilience

`TwentyClient` and `TwentyMailSyncJob` are hardened against Twenty API failures and credential problems:

- **Error classes** (`app/services/twenty_client.rb`) — `TwentyClient::Error` is the base class, with three subclasses:
  - `MissingCredentialsError` — raised when `TWENTY_API_URL` or `TWENTY_API_KEY` is unset/empty. Credentials are read lazily on each call rather than at load time, so a missing env var fails the call instead of crashing boot.
  - `TransientError` — raised for network/timeout failures (`Net::OpenTimeout`, `Net::ReadTimeout`, `Errno::ECONNREFUSED`, `SocketError`, `Timeout::Error`, `HTTParty::Error`) and for HTTP 429 / 5xx responses. These are safe to retry.
  - `RequestError` — raised for other non-2xx responses (e.g. 4xx). These are not retried.
- **Secret-free logging** — any request failure logs one `Rails.logger.error` line built from an explicit whitelist: HTTP method, request path, status code, and the response body truncated to ~500 characters. Headers (including the `Authorization: Bearer` token) are never included.
- **Job retry/discard semantics** (`app/jobs/twenty_mail_sync_job.rb`) — `TwentyMailSyncJob`:
  - `retry_on TwentyClient::TransientError` with polynomially-longer backoff, up to 5 attempts.
  - `discard_on TwentyClient::MissingCredentialsError`, logging a secret-free error before discarding — a missing credential won't resolve itself on retry.
  - `discard_on ActiveJob::DeserializationError` — e.g. the referenced mail record was deleted before the job ran.

## Tests

RSpec specs live under `dobase/spec/`, covering the error classes above, secret-free logging, and job retry/discard behaviour. WebMock stubs all Twenty API calls (`WebMock.disable_net_connect!`). Run with:

```sh
bundle exec rspec
```

## Documentation

- [Webhook Bridge](https://danappfire.atlassian.net/wiki/spaces/DEV/pages/85458945)
- [Dobase API Layer](https://danappfire.atlassian.net/wiki/spaces/DEV/pages/85655553)

## Jira

- Epic DEV-98 (Webhook Bridge)
- Story DEV-111 (Dobase API Layer)
