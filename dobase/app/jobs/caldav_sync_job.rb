# frozen_string_literal: true

require 'calendav'
require 'icalendar'

class CaldavSyncJob < ApplicationJob
  queue_as :integrations

  retry_on Net::OpenTimeout, Net::ReadTimeout, Errno::ETIMEDOUT, wait: :exponentially_longer, attempts: 5

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
      to: sync_window_days.days.from_now
    )

    events.each do |event|
      begin
        TwentySync::CalendarEvent.upsert(user, normalize(event))
      rescue StandardError => e
        identifier = event.respond_to?(:uid) ? event.uid : event.try(:href)
        Rails.logger.error("CaldavSyncJob: failed to sync event #{identifier} (#{e.class}): #{e.message}")
      end
    end
  end

  private

  def sync_window_days
    ENV.fetch('CALDAV_SYNC_WINDOW_DAYS', '37').to_i
  end

  def normalize(event)
    vevent = Icalendar::Calendar.parse(event.calendar_data).first.events.first

    {
      uid: vevent.uid.to_s,
      title: vevent.summary.to_s,
      description: vevent.description.to_s,
      starts_at: vevent.dtstart&.to_time,
      ends_at: vevent.dtend&.to_time,
      attendee_emails: Array(vevent.attendee).map { |attendee| attendee.to_s.sub(/\Amailto:/i, '') }
    }
  end
end
