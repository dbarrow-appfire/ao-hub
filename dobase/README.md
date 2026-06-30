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

See root `.env.example` — requires `TWENTY_API_URL`, `TWENTY_API_KEY`, `DOBASE_CALDAV_URL`.

## Documentation

- [Webhook Bridge](https://danappfire.atlassian.net/wiki/spaces/DEV/pages/85458945)
- [Dobase API Layer](https://danappfire.atlassian.net/wiki/spaces/DEV/pages/85655553)

## Jira

- Epic DEV-98 (Webhook Bridge)
- Story DEV-111 (Dobase API Layer)
