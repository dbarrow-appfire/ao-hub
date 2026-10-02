# frozen_string_literal: true

require 'calendav'
require 'calendav/credentials/standard'

class CaldavSyncJob < ApplicationJob
  WINDOW = 37.days

  queue_as :integrations
  # One run per user at a time, so overlapping schedules cannot race on the same mapping rows.
  limits_concurrency to: 1, key: ->(user_id) { user_id }, duration: 15.minutes if respond_to?(:limits_concurrency)

  def perform(user_id)
    user = User.find(user_id)
    return if user.caldav_url.blank? || user.caldav_token.blank?

    client = Calendav.client(
      Calendav::Credentials::Standard.new(
        host: ENV.fetch('DOBASE_CALDAV_URL'),
        username: user.email,
        password: user.caldav_token
      )
    )
    from = Time.current
    to = from + WINDOW
    calendar = client.calendars.find(user.caldav_url)
    events = client.events.list(calendar.url, from: from, to: to)

    person_cache = {}
    seen_keys = events.flat_map do |event|
      TwentySync::CalendarEvent.upsert(user, event, from: from, to: to, person_cache: person_cache)
    end
    # Only reached when listing and every upsert succeeded, so a failed run never deletes tasks.
    TwentySync::CalendarEvent.prune(user, seen_keys, from: from, to: to)
  end
end
