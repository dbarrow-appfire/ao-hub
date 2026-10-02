# frozen_string_literal: true

require 'test_helper'

class TwentySync::EventOccurrencesTest < ActiveSupport::TestCase
  FROM = Time.utc(2026, 10, 1)
  TO = FROM + 37.days

  def occurrences(calendar_data, exclude_email: 'owner@example.test')
    TwentySync::EventOccurrences.from_calendar_data(calendar_data, from: FROM, to: TO, exclude_email: exclude_email)
  end

  def calendar(*vevents)
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//ao-hub test//EN\n#{vevents.join}END:VCALENDAR\n"
  end

  def vevent(body)
    "BEGIN:VEVENT\n#{body}END:VEVENT\n"
  end

  test 'a single event yields one occurrence keyed by its UID' do
    data = calendar(vevent(<<~ICS))
      UID:single-1
      SUMMARY:Quarterly review
      DESCRIPTION:Agenda
      LOCATION:Room 1
      DTSTART:20261010T100000Z
      DTEND:20261010T110000Z
    ICS

    occurrence = occurrences(data).sole

    assert_equal 'single-1', occurrence.key
    assert_equal 'single-1', occurrence.uid
    assert_equal Time.utc(2026, 10, 10, 10), occurrence.starts_at
    assert_equal Time.utc(2026, 10, 10, 11), occurrence.ends_at
    assert_equal 'Quarterly review', occurrence.summary
    assert_equal 'Agenda', occurrence.description
    assert_equal 'Room 1', occurrence.location
    assert_equal false, occurrence.all_day
    assert_equal false, occurrence.cancelled
    assert_equal [], occurrence.emails
  end

  test 'a weekly RRULE yields one occurrence per week with UID|start keys' do
    data = calendar(vevent(<<~ICS))
      UID:weekly-1
      SUMMARY:Standup
      DTSTART:20261005T090000Z
      DTEND:20261005T093000Z
      RRULE:FREQ=WEEKLY;COUNT=5
    ICS

    result = occurrences(data)

    assert_equal %w[
      weekly-1|2026-10-05T09:00:00Z
      weekly-1|2026-10-12T09:00:00Z
      weekly-1|2026-10-19T09:00:00Z
      weekly-1|2026-10-26T09:00:00Z
      weekly-1|2026-11-02T09:00:00Z
    ], result.map(&:key)
    assert(result.all? { |occurrence| occurrence.uid == 'weekly-1' })
    assert(result.all? { |occurrence| occurrence.ends_at - occurrence.starts_at == 30.minutes })
  end

  test 'an EXDATE removes that occurrence' do
    data = calendar(vevent(<<~ICS))
      UID:weekly-1
      DTSTART:20261005T090000Z
      DTEND:20261005T093000Z
      RRULE:FREQ=WEEKLY;COUNT=5
      EXDATE:20261019T090000Z
    ICS

    assert_equal %w[
      weekly-1|2026-10-05T09:00:00Z
      weekly-1|2026-10-12T09:00:00Z
      weekly-1|2026-10-26T09:00:00Z
      weekly-1|2026-11-02T09:00:00Z
    ], occurrences(data).map(&:key)
  end

  test 'a RECURRENCE-ID override replaces the occurrence but keeps its original key' do
    master = vevent(<<~ICS)
      UID:weekly-1
      SUMMARY:Standup
      DTSTART:20261005T090000Z
      DTEND:20261005T093000Z
      RRULE:FREQ=WEEKLY;COUNT=3
    ICS
    override = vevent(<<~ICS)
      UID:weekly-1
      RECURRENCE-ID:20261012T090000Z
      SUMMARY:Standup (moved)
      DTSTART:20261013T140000Z
      DTEND:20261013T150000Z
    ICS

    result = occurrences(calendar(master, override))

    assert_equal %w[
      weekly-1|2026-10-05T09:00:00Z
      weekly-1|2026-10-12T09:00:00Z
      weekly-1|2026-10-19T09:00:00Z
    ], result.map(&:key)
    moved = result.find { |occurrence| occurrence.key == 'weekly-1|2026-10-12T09:00:00Z' }
    assert_equal Time.utc(2026, 10, 13, 14), moved.starts_at
    assert_equal Time.utc(2026, 10, 13, 15), moved.ends_at
    assert_equal 'Standup (moved)', moved.summary
  end

  test 'a cancelled event is flagged rather than dropped' do
    data = calendar(vevent(<<~ICS))
      UID:cancelled-1
      STATUS:CANCELLED
      DTSTART:20261010T100000Z
      DTEND:20261010T110000Z
    ICS

    occurrence = occurrences(data).sole

    assert_equal 'cancelled-1', occurrence.key
    assert_equal true, occurrence.cancelled
  end

  test 'occurrences before from are dropped and one exactly at from is kept' do
    before = vevent("UID:before-1\nDTSTART:20260930T235959Z\nDTEND:20261001T003000Z\n")
    at_from = vevent("UID:at-from-1\nDTSTART:20261001T000000Z\nDTEND:20261001T010000Z\n")

    assert_equal ['at-from-1'], occurrences(calendar(before, at_from)).map(&:key)
  end

  test 'an occurrence starting exactly at to is dropped and one just before is kept' do
    just_before = vevent("UID:last-1\nDTSTART:20261106T235959Z\nDTEND:20261107T003000Z\n")
    at_to = vevent("UID:at-to-1\nDTSTART:20261107T000000Z\nDTEND:20261107T010000Z\n")

    assert_equal ['last-1'], occurrences(calendar(just_before, at_to)).map(&:key)
  end

  test 'recurrences outside the window are dropped' do
    data = calendar(vevent(<<~ICS))
      UID:daily-1
      DTSTART:20260929T090000Z
      DTEND:20260929T100000Z
      RRULE:FREQ=DAILY;COUNT=4
    ICS

    assert_equal %w[daily-1|2026-10-01T09:00:00Z daily-1|2026-10-02T09:00:00Z], occurrences(data).map(&:key)
  end

  test 'an all-day event starts at Time.zone midnight and spans whole days' do
    data = calendar(vevent(<<~ICS))
      UID:all-day-1
      SUMMARY:Offsite
      DTSTART;VALUE=DATE:20261020
      DTEND;VALUE=DATE:20261022
    ICS

    occurrence = Time.use_zone('Europe/Berlin') { occurrences(data).sole }

    assert_equal 'all-day-1', occurrence.key
    assert_equal true, occurrence.all_day
    assert_equal Time.utc(2026, 10, 19, 22), occurrence.starts_at
    assert_equal Time.utc(2026, 10, 21, 22), occurrence.ends_at
  end

  test 'a TZID weekly event crossing the DST change keeps its local time with exact UTC keys' do
    # Europe/Berlin leaves summer time (UTC+2) for UTC+1 on 2026-10-25.
    data = calendar(vevent(<<~ICS))
      UID:berlin-1
      DTSTART;TZID=Europe/Berlin:20261019T090000
      DTEND;TZID=Europe/Berlin:20261019T100000
      RRULE:FREQ=WEEKLY;COUNT=3
    ICS

    result = occurrences(data)

    assert_equal %w[
      berlin-1|2026-10-19T07:00:00Z
      berlin-1|2026-10-26T08:00:00Z
      berlin-1|2026-11-02T08:00:00Z
    ], result.map(&:key)
    assert_equal [Time.utc(2026, 10, 19, 7), Time.utc(2026, 10, 26, 8), Time.utc(2026, 11, 2, 8)],
                 result.map(&:starts_at)
    assert(result.all? { |occurrence| occurrence.ends_at - occurrence.starts_at == 1.hour })
  end

  test 'garbage input raises ParseError without quoting the input' do
    err = assert_raises(TwentySync::EventOccurrences::ParseError) { occurrences('not a calendar at all') }

    refute_includes err.message, 'not a calendar'
  end

  test 'blank input raises ParseError' do
    assert_raises(TwentySync::EventOccurrences::ParseError) { occurrences(nil) }
  end

  test 'a VEVENT without a UID raises ParseError' do
    data = calendar(vevent("SUMMARY:No uid\nDTSTART:20261010T100000Z\nDTEND:20261010T110000Z\n"))

    assert_raises(TwentySync::EventOccurrences::ParseError) { occurrences(data) }
  end

  test 'a UID inside a VALARM does not count as the VEVENT UID' do
    data = calendar(vevent(<<~ICS))
      DTSTART:20261010T100000Z
      DTEND:20261010T110000Z
      BEGIN:VALARM
      UID:alarm-1
      ACTION:DISPLAY
      TRIGGER:-PT5M
      END:VALARM
    ICS

    assert_raises(TwentySync::EventOccurrences::ParseError) { occurrences(data) }
  end

  test 'attendee and organizer emails are normalized and the user own email is excluded' do
    data = calendar(vevent(<<~ICS))
      UID:meeting-1
      DTSTART:20261010T100000Z
      DTEND:20261010T110000Z
      ORGANIZER:mailto:Owner@Example.test
      ATTENDEE;CN=Guest One:MAILTO:Guest.One@Example.test
      ATTENDEE:mailto:guest-two@example.test
      ATTENDEE:mailto:owner@example.test
    ICS

    occurrence = occurrences(data, exclude_email: 'OWNER@example.test').sole

    assert_equal %w[guest.one@example.test guest-two@example.test], occurrence.emails
  end
end
