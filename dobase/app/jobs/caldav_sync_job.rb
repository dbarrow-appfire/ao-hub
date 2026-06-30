# frozen_string_literal: true

require 'calendav'

class CaldavSyncJob < ApplicationJob
  queue_as :integrations

  def perform(user_id)
    user = User.find(user_id)
    client = Calendav.client(
      :basic,
      host: ENV.fetch('DOBASE_CALDAV_URL'),
      username: user.email,
      password: user.caldav_token
    )
    calendar = client.calendars.find(user.caldav_url)
    events = client.events.list(
      calendar.url,
      from: Time.current,
      to: 37.days.from_now
    )
    events.each { |event| TwentySync::CalendarEvent.upsert(user, event) }
  end
end
