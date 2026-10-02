# frozen_string_literal: true

# TwentyClient reads these with ENV.fetch at load time; fake placeholders keep the
# test bootable without a real Twenty instance.
ENV['TWENTY_API_URL'] ||= 'https://twenty.example.test'
ENV['TWENTY_API_KEY'] ||= 'fake-twenty-api-key'

require 'test_helper'
require_relative '../../support/stub_helper'

class TwentySync::CalendarEventTest < ActiveSupport::TestCase
  include StubHelper

  FROM = Time.utc(2026, 10, 1)
  TO = FROM + 37.days
  EVENT_URL = 'https://dobase.example.test/dav/calendars/owner/default/review-1.ics'

  FakeEvent = Struct.new(:url, :calendar_data, :etag, keyword_init: true)

  # Records every TwentyClient call. A response may be a value, an exception
  # (raised) or a callable (invoked with the call's arguments).
  class FakeTwenty
    METHODS = %i[
      create_task update_task delete_task create_task_target list_task_targets delete_task_target
      find_person_by_email
    ].freeze
    DEFAULTS = { create_task: 'task-1', create_task_target: 'target-1', list_task_targets: [] }.freeze

    attr_reader :calls

    def initialize(responses = {})
      @responses = DEFAULTS.merge(responses)
      @calls = []
    end

    def call(name, *args)
      @calls << [name, *args]
      response = @responses[name]
      response = response.call(*args) if response.respond_to?(:call)
      raise response if response.is_a?(Exception)

      response
    end
  end

  def with_fake_twenty(fake, methods = FakeTwenty::METHODS, &block)
    return yield if methods.empty?

    name, *rest = methods
    with_stub(TwentyClient, name, ->(*args) { fake.call(name, *args) }) { with_fake_twenty(fake, rest, &block) }
  end

  # Any persisted user works: the sync only reads #id and #email.
  def user
    @user ||= User.first || User.create!(email: 'owner@example.test')
  end

  def event(summary: 'Quarterly review', uid: 'review-1', url: EVENT_URL, extra: '')
    FakeEvent.new(url: url, etag: '"etag-1"', calendar_data: <<~ICS)
      BEGIN:VCALENDAR
      VERSION:2.0
      BEGIN:VEVENT
      UID:#{uid}
      SUMMARY:#{summary}
      DESCRIPTION:Agenda
      LOCATION:Room 1
      DTSTART:20261010T100000Z
      DTEND:20261010T110000Z
      #{extra}END:VEVENT
      END:VCALENDAR
    ICS
  end

  def with_guest(summary: 'Quarterly review', uid: 'review-1', url: EVENT_URL)
    event(summary: summary, uid: uid, url: url, extra: <<~ICS)
      ATTENDEE:mailto:guest@example.test
      ATTENDEE:mailto:#{user.email}
    ICS
  end

  def payload(title = 'Quarterly review')
    {
      title: title,
      dueAt: '2026-10-10T10:00:00Z',
      bodyV2: { markdown: "When: 2026-10-10T10:00:00Z to 2026-10-10T11:00:00Z\nLocation: Room 1\n\nAgenda" }
    }
  end

  def upsert(calendar_event, fake, person_cache: {})
    with_fake_twenty(fake) do
      TwentySync::CalendarEvent.upsert(user, calendar_event, from: FROM, to: TO, person_cache: person_cache)
    end
  end

  def sync_row(key = 'review-1')
    TwentyCalendarSync.find_by!(user: user, occurrence_key: key)
  end

  # --- upsert ---

  test 'upsert creates a task and a mapping row for a new event' do
    fake = FakeTwenty.new

    keys = upsert(event, fake)

    assert_equal ['review-1'], keys
    assert_equal [[:create_task, payload]], fake.calls
    row = sync_row
    assert_equal 'review-1', row.event_uid
    assert_equal 'task-1', row.twenty_task_id
    assert_equal Time.utc(2026, 10, 10, 10), row.starts_at
    assert_equal EVENT_URL, row.event_url
    assert_match(/\A\h{64}\z/, row.content_hash)
  end

  test 'upsert of an unchanged event makes no Twenty calls' do
    upsert(event, FakeTwenty.new)
    fake = FakeTwenty.new

    keys = upsert(event, fake)

    assert_equal ['review-1'], keys
    assert_equal [], fake.calls
    assert_equal 1, TwentyCalendarSync.where(user: user).count
  end

  test 'upsert of a changed event updates the same task' do
    upsert(event, FakeTwenty.new)
    old_hash = sync_row.content_hash
    fake = FakeTwenty.new

    upsert(event(summary: 'Quarterly review (rescheduled)'), fake)

    assert_equal [
      [:update_task, 'task-1', payload('Quarterly review (rescheduled)')],
      [:list_task_targets, 'task-1']
    ], fake.calls
    row = sync_row
    assert_equal 'task-1', row.twenty_task_id
    refute_equal old_hash, row.content_hash
    assert_equal 1, TwentyCalendarSync.where(user: user).count
  end

  test 'upsert recreates the task when the update gets a 404' do
    upsert(event, FakeTwenty.new)
    fake = FakeTwenty.new(
      update_task: TwentyClient::Error.new('PATCH', '/rest/tasks/task-1', 404), create_task: 'task-2'
    )

    upsert(event(summary: 'Quarterly review (rescheduled)'), fake)

    assert_equal [
      [:update_task, 'task-1', payload('Quarterly review (rescheduled)')],
      [:create_task, payload('Quarterly review (rescheduled)')]
    ], fake.calls
    assert_equal 'task-2', sync_row.twenty_task_id
  end

  test 'upsert propagates an update error other than 404 and keeps the old hash' do
    upsert(event, FakeTwenty.new)
    old_hash = sync_row.content_hash
    fake = FakeTwenty.new(update_task: TwentyClient::Error.new('PATCH', '/rest/tasks/task-1', 500))

    err = assert_raises(TwentyClient::Error) { upsert(event(summary: 'Changed'), fake) }

    assert_equal 500, err.status
    assert_equal 'task-1', sync_row.twenty_task_id
    assert_equal old_hash, sync_row.content_hash
  end

  test 'upsert propagates a create 500 and leaves the row without a task id' do
    fake = FakeTwenty.new(create_task: TwentyClient::Error.new('POST', '/rest/tasks', 500))

    err = assert_raises(TwentyClient::Error) { upsert(event, fake) }

    assert_equal 500, err.status
    row = sync_row
    assert_nil row.twenty_task_id
    assert_nil row.content_hash
  end

  test 'upsert creates the task on the next run after a failed create' do
    failing = FakeTwenty.new(create_task: TwentyClient::Error.new('POST', '/rest/tasks', 500))
    assert_raises(TwentyClient::Error) { upsert(event, failing) }
    fake = FakeTwenty.new

    upsert(event, fake)

    assert_equal [[:create_task, payload]], fake.calls
    assert_equal 'task-1', sync_row.twenty_task_id
  end

  test 'upsert raises MissingTaskId when Twenty returns no task id' do
    fake = FakeTwenty.new(create_task: nil)

    assert_raises(TwentySync::CalendarEvent::MissingTaskId) { upsert(event, fake) }

    assert_nil sync_row.twenty_task_id
  end

  test 'upsert links the task to the Twenty person matching an attendee' do
    fake = FakeTwenty.new(find_person_by_email: { 'id' => 'person-1' })

    upsert(with_guest, fake)

    assert_equal [
      [:create_task, payload],
      [:find_person_by_email, 'guest@example.test'],
      [:create_task_target, 'task-1', 'person-1']
    ], fake.calls
  end

  test 'upsert still creates the task when no attendee matches a Twenty person' do
    fake = FakeTwenty.new(find_person_by_email: nil)

    keys = upsert(with_guest, fake)

    assert_equal ['review-1'], keys
    assert_equal [[:create_task, payload], [:find_person_by_email, 'guest@example.test']], fake.calls
    assert_equal 'task-1', sync_row.twenty_task_id
  end

  test 'upsert on a changed event replaces stale person targets and keeps other targets' do
    upsert(with_guest, FakeTwenty.new(find_person_by_email: { 'id' => 'person-1' }))
    targets = [
      { 'id' => 'target-old', 'taskId' => 'task-1', 'personId' => 'person-2' },
      { 'id' => 'target-company', 'taskId' => 'task-1', 'companyId' => 'company-1' }
    ]
    fake = FakeTwenty.new(find_person_by_email: { 'id' => 'person-1' }, list_task_targets: targets)

    upsert(with_guest(summary: 'Changed'), fake)

    assert_equal [
      [:update_task, 'task-1', payload('Changed')],
      [:find_person_by_email, 'guest@example.test'],
      [:list_task_targets, 'task-1'],
      [:delete_task_target, 'target-old'],
      [:create_task_target, 'task-1', 'person-1']
    ], fake.calls
  end

  test 'person_cache looks each email up once across events' do
    fake = FakeTwenty.new(find_person_by_email: { 'id' => 'person-1' })
    cache = {}

    upsert(with_guest(uid: 'review-1'), fake, person_cache: cache)
    upsert(with_guest(uid: 'review-2', url: "#{EVENT_URL}-2"), fake, person_cache: cache)

    assert_equal 1, fake.calls.count { |name, *| name == :find_person_by_email }
    assert_equal 2, fake.calls.count { |name, *| name == :create_task_target }
    assert_equal({ 'guest@example.test' => { 'id' => 'person-1' } }, cache)
  end

  test 'person_cache remembers a miss too' do
    fake = FakeTwenty.new(find_person_by_email: nil)
    cache = {}

    upsert(with_guest(uid: 'review-1'), fake, person_cache: cache)
    upsert(with_guest(uid: 'review-2', url: "#{EVENT_URL}-2"), fake, person_cache: cache)

    assert_equal 1, fake.calls.count { |name, *| name == :find_person_by_email }
    assert_equal({ 'guest@example.test' => nil }, cache)
  end

  test 'upsert skips a cancelled event and does not return its key' do
    fake = FakeTwenty.new

    keys = upsert(event(extra: "STATUS:CANCELLED\n"), fake)

    assert_equal [], keys
    assert_equal [], fake.calls
    assert_equal 0, TwentyCalendarSync.where(user: user).count
  end

  test 'upsert of unparseable data returns the existing keys for the resource and logs no content' do
    TwentyCalendarSync.create!(user: user, event_uid: 'weekly-1', occurrence_key: 'weekly-1|2026-10-05T09:00:00Z',
                               starts_at: Time.utc(2026, 10, 5, 9), event_url: EVENT_URL, twenty_task_id: 'task-a')
    TwentyCalendarSync.create!(user: user, event_uid: 'weekly-1', occurrence_key: 'weekly-1|2026-10-12T09:00:00Z',
                               starts_at: Time.utc(2026, 10, 12, 9), event_url: EVENT_URL, twenty_task_id: 'task-b')
    TwentyCalendarSync.create!(user: user, event_uid: 'other-1', occurrence_key: 'other-1',
                               starts_at: Time.utc(2026, 10, 7, 9), event_url: "#{EVENT_URL}-other")
    garbage = FakeEvent.new(url: EVENT_URL, etag: '"etag-9"', calendar_data: 'SECRET AGENDA not a calendar')
    fake = FakeTwenty.new
    logs = []

    keys = with_stub(Rails.logger, :warn, ->(message) { logs << message }) { upsert(garbage, fake) }

    assert_equal %w[weekly-1|2026-10-05T09:00:00Z weekly-1|2026-10-12T09:00:00Z], keys.sort
    assert_equal [], fake.calls
    assert_equal 3, TwentyCalendarSync.where(user: user).count
    message = logs.sole
    assert_includes message, "user_id=#{user.id}"
    assert_includes message, 'etag="etag-9"'
    refute_includes message, 'SECRET AGENDA'
  end

  # --- prune ---

  def create_row(key, starts_at: FROM + 5.days, task_id: "task-#{key}")
    TwentyCalendarSync.create!(user: user, event_uid: key, occurrence_key: key, starts_at: starts_at,
                               event_url: "#{EVENT_URL}-#{key}", twenty_task_id: task_id)
  end

  def prune(seen_keys, fake)
    with_fake_twenty(fake) { TwentySync::CalendarEvent.prune(user, seen_keys, from: FROM, to: TO) }
  end

  def remaining_keys
    TwentyCalendarSync.where(user: user).order(:occurrence_key).pluck(:occurrence_key)
  end

  test 'prune deletes the task of an unseen in-window row and destroys the row' do
    create_row('kept')
    create_row('gone')
    fake = FakeTwenty.new

    prune(['kept'], fake)

    assert_equal [[:delete_task, 'task-gone']], fake.calls
    assert_equal ['kept'], remaining_keys
  end

  test 'prune destroys an unseen row that never got a task without calling Twenty' do
    create_row('unsynced', task_id: nil)
    fake = FakeTwenty.new

    prune([], fake)

    assert_equal [], fake.calls
    assert_equal [], remaining_keys
  end

  test 'prune treats a delete 404 as already deleted' do
    create_row('gone')
    fake = FakeTwenty.new(delete_task: TwentyClient::Error.new('DELETE', '/rest/tasks/task-gone', 404))

    prune([], fake)

    assert_equal [[:delete_task, 'task-gone']], fake.calls
    assert_equal [], remaining_keys
  end

  test 'prune raises on a delete 500 and keeps the row' do
    create_row('gone')
    fake = FakeTwenty.new(delete_task: TwentyClient::Error.new('DELETE', '/rest/tasks/task-gone', 500))

    err = assert_raises(TwentyClient::Error) { prune([], fake) }

    assert_equal 500, err.status
    assert_equal ['gone'], remaining_keys
    assert_equal 'task-gone', sync_row('gone').twenty_task_id
  end

  test 'prune keeps rows that started before from' do
    create_row('past', starts_at: FROM - 1.second)
    fake = FakeTwenty.new

    prune([], fake)

    assert_equal [], fake.calls
    assert_equal ['past'], remaining_keys
  end

  test 'prune deletes an unseen row starting exactly at from' do
    create_row('at-from', starts_at: FROM)
    fake = FakeTwenty.new

    prune([], fake)

    assert_equal [[:delete_task, 'task-at-from']], fake.calls
    assert_equal [], remaining_keys
  end
end
