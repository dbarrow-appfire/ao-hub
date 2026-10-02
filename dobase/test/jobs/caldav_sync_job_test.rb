# frozen_string_literal: true

# TwentyClient reads these with ENV.fetch at load time and CaldavSyncJob reads the
# CalDAV host per run; fake placeholders keep the test bootable without real services.
ENV['TWENTY_API_URL'] ||= 'https://twenty.example.test'
ENV['TWENTY_API_KEY'] ||= 'fake-twenty-api-key'
ENV['DOBASE_CALDAV_URL'] ||= 'https://dobase.example.test/dav'

require 'test_helper'
require_relative '../support/stub_helper'

class CaldavSyncJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include StubHelper

  NOW = Time.utc(2026, 10, 1, 12)
  USER_CALENDAR_URL = 'https://dobase.example.test/dav/calendars/owner/default/'
  RESOLVED_CALENDAR_URL = 'https://dobase.example.test/dav/calendars/owner/default/resolved/'

  FakeCalendar = Struct.new(:url)
  FakeEvent = Struct.new(:url, :calendar_data, :etag, keyword_init: true)

  # Stands in for a Calendav client: answers both `calendars.find` and
  # `events.list`, recording what the job asked for.
  class FakeCalendav
    attr_accessor :credentials
    attr_reader :found_url, :listed

    def initialize(events: [], list_error: nil)
      @events = events
      @list_error = list_error
    end

    def calendars
      self
    end

    def events
      self
    end

    def find(url)
      @found_url = url
      FakeCalendar.new(RESOLVED_CALENDAR_URL)
    end

    def list(url, from:, to:)
      @listed = { url: url, from: from, to: to }
      raise @list_error if @list_error

      @events
    end
  end

  # Records the job's calls into TwentySync::CalendarEvent.
  Calls = Struct.new(:upserts, :prunes)

  # The only place that knows the host User's required columns: adjust here if
  # Dobase's User needs more than these to save.
  def create_user(caldav_url: USER_CALENDAR_URL, caldav_token: 'fake-caldav-token')
    User.create!(
      email: "user-#{SecureRandom.hex(4)}@example.test",
      caldav_url: caldav_url,
      caldav_token: caldav_token
    )
  end

  # The job adds 37 calendar days in the app's zone, so across a DST change the
  # end is not NOW + 37 * 86_400 seconds.
  def window_end
    NOW.in_time_zone + 37.days
  end

  def event(name)
    FakeEvent.new(url: "#{RESOLVED_CALENDAR_URL}#{name}.ics", calendar_data: 'BEGIN:VCALENDAR', etag: "\"#{name}\"")
  end

  # Runs CaldavSyncJob#perform directly (not perform_now), so a host
  # ApplicationJob `retry_on` cannot swallow the errors under test.
  # `keys_by_url` is what the stubbed upsert returns for each event URL.
  def sync(user, client, keys_by_url: {})
    calls = Calls.new([], [])
    upsert = lambda do |sync_user, calendar_event, **opts|
      calls.upserts << { user_id: sync_user.id, url: calendar_event.url, **opts }
      keys_by_url.fetch(calendar_event.url, [])
    end
    prune = ->(sync_user, keys, **opts) { calls.prunes << { user_id: sync_user.id, keys: keys, **opts } }
    connect = lambda do |credentials|
      client.credentials = credentials
      client
    end

    with_stub(Calendav, :client, connect) do
      with_stub(TwentySync::CalendarEvent, :upsert, upsert) do
        with_stub(TwentySync::CalendarEvent, :prune, prune) do
          travel_to(NOW) { CaldavSyncJob.new.perform(user.id) }
        end
      end
    end
    calls
  end

  # Fixture users may already carry CalDAV credentials; make them ineligible so
  # the schedule assertions count only the users created by the test.
  def clear_existing_caldav_credentials!
    User.update_all(caldav_url: nil)
  end

  def enqueued_sync_args
    enqueued_jobs.select { |job| job[:job] == CaldavSyncJob }.map { |job| job[:args] }
  end

  # --- CaldavSyncJob ---

  test 'lists events over a window exactly 37 days long starting now' do
    client = FakeCalendav.new

    sync(create_user, client)

    assert_equal 37.days, CaldavSyncJob::WINDOW
    assert_equal NOW, client.listed[:from]
    assert_equal window_end, client.listed[:to]
    assert_equal 37, (client.listed[:to].to_date - client.listed[:from].to_date).to_i
  end

  test 'lists the calendar resolved from the user caldav_url' do
    client = FakeCalendav.new

    sync(create_user, client)

    assert_equal USER_CALENDAR_URL, client.found_url
    assert_equal RESOLVED_CALENDAR_URL, client.listed[:url]
  end

  test 'connects with standard credentials for the user' do
    user = create_user
    client = FakeCalendav.new

    sync(user, client)

    assert_instance_of Calendav::Credentials::Standard, client.credentials
    assert_equal URI(ENV.fetch('DOBASE_CALDAV_URL')), client.credentials.host
    assert_equal user.email, client.credentials.username
    assert_equal 'fake-caldav-token', client.credentials.password
  end

  test 'prunes with the union of the keys returned by every upsert' do
    user = create_user
    first = event('standup')
    second = event('review')
    client = FakeCalendav.new(events: [first, second])

    calls = sync(user, client, keys_by_url: {
      first.url => ['standup|2026-10-02T09:00:00Z', 'standup|2026-10-09T09:00:00Z'],
      second.url => ['review']
    })

    assert_equal [{
      user_id: user.id,
      keys: ['standup|2026-10-02T09:00:00Z', 'standup|2026-10-09T09:00:00Z', 'review'],
      from: NOW,
      to: window_end
    }], calls.prunes
  end

  test 'upserts every event with the same window and one shared person cache' do
    client = FakeCalendav.new(events: [event('standup'), event('review')])

    calls = sync(create_user, client)

    assert_equal [event('standup').url, event('review').url], calls.upserts.map { |c| c[:url] }
    assert(calls.upserts.all? { |c| c[:from] == NOW && c[:to] == window_end })
    assert_same calls.upserts.first[:person_cache], calls.upserts.last[:person_cache]
  end

  test 'prunes with no keys when the calendar has no events in the window' do
    calls = sync(create_user, FakeCalendav.new(events: []))

    assert_equal [[]], calls.prunes.map { |c| c[:keys] }
  end

  test 'a CalDAV request error propagates without upserting or pruning' do
    error = Calendav::RequestError.new(Struct.new(:status).new(503))
    client = FakeCalendav.new(events: [event('standup')], list_error: error)
    upsert_calls = 0
    prune_calls = 0

    with_stub(Calendav, :client, ->(_credentials) { client }) do
      with_stub(TwentySync::CalendarEvent, :upsert, ->(*, **) { upsert_calls += 1 }) do
        with_stub(TwentySync::CalendarEvent, :prune, ->(*, **) { prune_calls += 1 }) do
          raised = assert_raises(Calendav::RequestError) { CaldavSyncJob.new.perform(create_user.id) }
          assert_same error, raised
        end
      end
    end

    assert_equal 0, upsert_calls
    assert_equal 0, prune_calls
  end

  test 'a failing upsert propagates without pruning' do
    second = event('review')
    client = FakeCalendav.new(events: [event('standup'), second])
    failure = TwentyClient::Error.new('POST', '/rest/tasks', 500)
    prune_calls = 0

    with_stub(Calendav, :client, ->(_credentials) { client }) do
      with_stub(TwentySync::CalendarEvent, :upsert, ->(_user, e, **) { e.url == second.url ? raise(failure) : ['standup'] }) do
        with_stub(TwentySync::CalendarEvent, :prune, ->(*, **) { prune_calls += 1 }) do
          raised = assert_raises(TwentyClient::Error) { CaldavSyncJob.new.perform(create_user.id) }
          assert_same failure, raised
        end
      end
    end

    assert_equal 0, prune_calls
  end

  test 'a user without a caldav_url returns early without connecting' do
    connects = 0

    with_stub(Calendav, :client, ->(_credentials) { connects += 1 }) do
      assert_nil CaldavSyncJob.new.perform(create_user(caldav_url: '').id)
    end

    assert_equal 0, connects
  end

  test 'a user without a caldav_token returns early without connecting' do
    connects = 0

    with_stub(Calendav, :client, ->(_credentials) { connects += 1 }) do
      assert_nil CaldavSyncJob.new.perform(create_user(caldav_token: nil).id)
    end

    assert_equal 0, connects
  end

  test 'an unknown user id raises RecordNotFound' do
    missing_id = (User.maximum(:id) || 0) + 1

    assert_raises(ActiveRecord::RecordNotFound) { CaldavSyncJob.new.perform(missing_id) }
  end

  # --- CaldavSyncScheduleJob ---

  test 'schedule enqueues exactly one sync job per user with CalDAV credentials' do
    clear_existing_caldav_credentials!
    eligible = [create_user, create_user]

    assert_enqueued_jobs 2, only: CaldavSyncJob, queue: 'integrations' do
      CaldavSyncScheduleJob.perform_now
    end

    assert_equal eligible.map { |u| [u.id] }.sort, enqueued_sync_args.sort
  end

  test 'schedule enqueues nothing for users missing a caldav_url or caldav_token' do
    clear_existing_caldav_credentials!
    create_user(caldav_url: nil)
    create_user(caldav_url: '')
    create_user(caldav_token: nil)
    create_user(caldav_token: '')

    assert_no_enqueued_jobs(only: CaldavSyncJob) { CaldavSyncScheduleJob.perform_now }
  end

  test 'schedule skips ineligible users while enqueueing eligible ones' do
    clear_existing_caldav_credentials!
    eligible = create_user
    create_user(caldav_token: '')

    CaldavSyncScheduleJob.perform_now

    assert_equal [[eligible.id]], enqueued_sync_args
  end
end
