# frozen_string_literal: true

require 'icalendar'
require 'icalendar/recurrence'

module TwentySync
  # Expands the iCalendar payload of one CalDAV resource into the occurrences
  # that start inside [from, to). Pure: no database or HTTP access.
  #
  # Occurrence keys are the event UID, or "UID|<original start as ISO8601 UTC>"
  # for an occurrence of a recurring event, so a RECURRENCE-ID override keeps
  # the key of the occurrence it replaces.
  #
  # Jira: DEV-107
  class EventOccurrences
    class ParseError < StandardError; end

    Occurrence = Struct.new(
      :key, :uid, :starts_at, :ends_at, :all_day, :summary, :description, :location, :emails, :cancelled,
      keyword_init: true
    )

    # Recurrences are expanded over a padded range so all-day occurrences
    # (which ice_cube expands at the process's local midnight) are not lost at
    # the edges. The exact [from, to) filter runs after UTC conversion.
    EXPANSION_PADDING = 1.day

    def self.from_calendar_data(calendar_data, from:, to:, exclude_email:)
      new(from, to, exclude_email).occurrences(calendar_data)
    end

    def initialize(from, to, exclude_email)
      @from = from
      @to = to
      @exclude_email = normalize_email(exclude_email)
    end

    def occurrences(calendar_data)
      parse(calendar_data)
        .group_by { |component| component.uid.to_s }
        .flat_map { |uid, components| expand(uid, components) }
        .select { |occurrence| occurrence.starts_at >= @from && occurrence.starts_at < @to }
        .sort_by(&:starts_at)
    rescue ParseError
      raise
    rescue StandardError => e
      # Only the error class: the message may quote calendar content.
      raise ParseError, "Unparseable calendar data (#{e.class})"
    end

    private

    def parse(calendar_data)
      raise ParseError, 'Calendar data is blank' if calendar_data.to_s.strip.empty?
      raise ParseError, 'VEVENT without UID' if missing_uid?(calendar_data)

      components = Icalendar::Calendar.parse(calendar_data).flat_map(&:events)
      raise ParseError, 'Calendar data has no VEVENT' if components.empty?
      raise ParseError, 'VEVENT without UID' if components.any? { |component| component.uid.to_s.strip.empty? }
      raise ParseError, 'VEVENT without DTSTART' if components.any? { |component| component.dtstart.nil? }

      components
    end

    # icalendar assigns a random UID to a parsed VEVENT that lacks one, which
    # would give the event a new key on every sync, so check the raw text.
    # VALARMs are stripped first because they may carry their own UID.
    def missing_uid?(calendar_data)
      calendar_data.scan(/^BEGIN:VEVENT\r?$(.*?)^END:VEVENT\r?$/mi).any? do |(body)|
        !body.gsub(/^BEGIN:VALARM\r?$.*?^END:VALARM\r?$/mi, '').match?(/^UID[;:]/i)
      end
    end

    def expand(uid, components)
      overrides, masters = components.partition(&:recurrence_id)
      master = masters.first
      if master && !recurring?(master)
        starts_at = to_utc(master.dtstart)
        return [build(master, uid, uid, starts_at)]
      end

      by_key = {}
      master&.occurrences_between(@from - EXPANSION_PADDING, @to + EXPANSION_PADDING)&.each do |expanded|
        starts_at = all_day?(master) ? zone_midnight(expanded.start_time.getlocal.to_date) : expanded.start_time.utc
        key = recurrence_key(uid, starts_at)
        by_key[key] = build(master, key, uid, starts_at)
      end
      overrides.each do |override|
        key = recurrence_key(uid, to_utc(override.recurrence_id))
        by_key[key] = build(override, key, uid, to_utc(override.dtstart))
      end
      by_key.values
    end

    def build(component, key, uid, starts_at)
      Occurrence.new(
        key: key,
        uid: uid,
        starts_at: starts_at,
        ends_at: starts_at + duration(component),
        all_day: all_day?(component),
        summary: component.summary.to_s.strip.presence,
        description: component.description.to_s.strip.presence,
        location: component.location.to_s.strip.presence,
        emails: emails(component),
        cancelled: component.status.to_s.strip.casecmp?('CANCELLED')
      )
    end

    def recurring?(component)
      component.rrule.any? || component.rdate.any?
    end

    def all_day?(component)
      component.dtstart.is_a?(Icalendar::Values::Date)
    end

    def recurrence_key(uid, starts_at)
      "#{uid}|#{starts_at.utc.iso8601}"
    end

    # The schedule resolves DTEND or DURATION (or neither) to an end time.
    def duration(component)
      seconds = component.schedule.end_time - component.schedule.start_time
      return seconds.seconds unless all_day?(component)

      # Whole days, so the end lands on Time.zone midnight across DST changes.
      [(seconds / 1.day.to_f).round, 1].max.days
    end

    def to_utc(value)
      return zone_midnight(value) if value.is_a?(Icalendar::Values::Date)

      Icalendar::Recurrence::TimeUtil.to_time(value).utc
    end

    def zone_midnight(date)
      Time.zone.local(date.year, date.month, date.day)
    end

    def emails(component)
      addresses = Array(component.attendee) + Array(component.organizer)
      addresses.filter_map { |address| normalize_email(address) }.uniq - [@exclude_email]
    end

    def normalize_email(address)
      email = address.to_s.strip.sub(/\Amailto:/i, '').downcase
      email if email.include?('@')
    end
  end
end
