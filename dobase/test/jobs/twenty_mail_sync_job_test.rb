# frozen_string_literal: true

require 'test_helper'
require 'webmock/minitest'

class TwentyMailSyncJobTest < ActiveJob::TestCase
  TWENTY_URL = 'https://twenty.example.test'
  FAKE_KEY = 'test-twenty-key-not-real'
  FAKE_EMAIL = 'person@example.test'
  PEOPLE_URL = %r{\Ahttps://twenty\.example\.test/rest/people}
  ACTIVITIES_URL = 'https://twenty.example.test/rest/timelineActivities'
  ENV_KEYS = %w[TWENTY_API_URL TWENTY_API_KEY].freeze
  JSON_HEADERS = { 'Content-Type' => 'application/json' }.freeze
  MATCH_BODY = { data: { people: { edges: [{ node: { id: 'person-1' } }] } } }.freeze
  EMPTY_BODY = { data: { people: { edges: [] } } }.freeze
  FakeMail = Struct.new(:id, :subject, :correspondent_email)

  setup do
    @original_env = ENV_KEYS.to_h { |name| [name, ENV.fetch(name, nil)] }
    ENV['TWENTY_API_URL'] = TWENTY_URL
    ENV['TWENTY_API_KEY'] = FAKE_KEY

    # Plain singleton swap so the test does not depend on minitest/mock.
    @original_find = Mail.method(:find)
    Mail.define_singleton_method(:find) { |id| FakeMail.new(id, 'Fake subject', FAKE_EMAIL) }

    @original_logger = ActiveJob::Base.logger
    ActiveJob::Base.logger = ActiveSupport::TaggedLogging.new(Logger.new(@log = StringIO.new))
  end

  teardown do
    Mail.define_singleton_method(:find, @original_find)
    ActiveJob::Base.logger = @original_logger
    @original_env.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
    WebMock.reset!
  end

  test '503 on every attempt retries 3 times then gives up without raising' do
    stub_people(people_response(status: 503))

    assert_nothing_raised { perform_enqueued_jobs { TwentyMailSyncJob.perform_later(42) } }

    assert_requested :get, PEOPLE_URL, times: 3
    assert_not_requested :post, ACTIVITIES_URL
  end

  test 'timeout on every attempt retries 3 times' do
    stub_request(:get, PEOPLE_URL).to_timeout

    assert_nothing_raised { perform_enqueued_jobs { TwentyMailSyncJob.perform_later(42) } }

    assert_requested :get, PEOPLE_URL, times: 3
  end

  test 'connection refused on every attempt retries 3 times' do
    stub_request(:get, PEOPLE_URL).to_raise(Errno::ECONNREFUSED)

    assert_nothing_raised { perform_enqueued_jobs { TwentyMailSyncJob.perform_later(42) } }

    assert_requested :get, PEOPLE_URL, times: 3
  end

  test 'retries back off 2 seconds then 4 seconds' do
    stub_people(people_response(status: 503))

    freeze_time do
      job = TwentyMailSyncJob.new(42)

      job.perform_now
      assert_enqueued_with(job: TwentyMailSyncJob, args: [42], at: 2.seconds.from_now)

      clear_enqueued_jobs
      job.perform_now
      assert_enqueued_with(job: TwentyMailSyncJob, args: [42], at: 4.seconds.from_now)
    end
  end

  test '429 then 200 retries once and creates the activity once' do
    stub_people(people_response(status: 429), people_response(body: MATCH_BODY))
    stub_activity(status: 201)

    assert_nothing_raised { perform_enqueued_jobs { TwentyMailSyncJob.perform_later(42) } }

    assert_requested :get, PEOPLE_URL, times: 2
    assert_requested :post, ACTIVITIES_URL, times: 1
  end

  test '400 on lookup is discarded after one attempt' do
    stub_people(people_response(status: 400))

    assert_nothing_raised { TwentyMailSyncJob.perform_now(42) }

    assert_requested :get, PEOPLE_URL, times: 1
    assert_no_enqueued_jobs
  end

  test '404 on lookup is discarded after one attempt' do
    stub_people(people_response(status: 404))

    assert_nothing_raised { TwentyMailSyncJob.perform_now(42) }

    assert_requested :get, PEOPLE_URL, times: 1
    assert_no_enqueued_jobs
  end

  test '422 on create_activity is discarded after one attempt' do
    stub_people(people_response(body: MATCH_BODY))
    stub_activity(status: 422)

    assert_nothing_raised { TwentyMailSyncJob.perform_now(42) }

    assert_requested :post, ACTIVITIES_URL, times: 1
    assert_no_enqueued_jobs
    assert_includes @log.string, '"outcome":"failed_non_retryable"'
  end

  test '401 skips the mail as invalid credentials' do
    assert_skipped_invalid_credentials(401)
  end

  test '403 skips the mail as invalid credentials' do
    assert_skipped_invalid_credentials(403)
  end

  test 'missing TWENTY_API_KEY skips the mail without calling Twenty' do
    ENV.delete('TWENTY_API_KEY')
    stub_request(:any, /twenty/)

    assert_nothing_raised { TwentyMailSyncJob.perform_now(42) }

    assert_not_requested :any, /twenty/
    assert_no_enqueued_jobs
    assert_includes @log.string, '"outcome":"skipped_missing_credentials"'
    assert_includes @log.string, 'TWENTY_API_KEY is not set'
    assert_includes @log.string, '"mail_id":42'
  end

  test 'a credential failure does not stop the next job' do
    stub_people(people_response(status: 401), people_response(body: MATCH_BODY))
    stub_activity(status: 201)

    assert_nothing_raised do
      perform_enqueued_jobs do
        TwentyMailSyncJob.perform_later(1)
        TwentyMailSyncJob.perform_later(2)
      end
    end

    assert_requested :get, PEOPLE_URL, times: 2
    assert_requested :post, ACTIVITIES_URL, times: 1
    assert_includes @log.string, '"mail_id":1'
  end

  test '200 with no matching person creates nothing and logs no failure' do
    stub_people(people_response(body: EMPTY_BODY))

    assert_nothing_raised { perform_enqueued_jobs { TwentyMailSyncJob.perform_later(42) } }

    assert_requested :get, PEOPLE_URL, times: 1
    assert_not_requested :post, ACTIVITIES_URL
    assert_not_includes @log.string, 'twenty_mail_sync.failure'
  end

  test 'persistent 503 logs one failure line per attempt with full context' do
    stub_people(people_response(status: 503))

    perform_enqueued_jobs { TwentyMailSyncJob.perform_later(42) }

    payloads = failure_payloads
    assert_equal 3, payloads.size
    assert_equal [1, 2, 3], payloads.map { |p| p['attempt'] }
    assert_equal %w[retrying retrying gave_up], payloads.map { |p| p['outcome'] }
    payloads.each do |payload|
      assert_equal 3, payload['max_attempts']
      assert_equal 42, payload['mail_id']
      assert_equal '/rest/people', payload['endpoint']
      assert_equal 'GET', payload['http_method']
      assert_equal 503, payload['status']
      assert_equal 'TwentyClient::RetryableError', payload['error_class']
      assert_equal 'TwentyMailSyncJob', payload['job']
    end
  end

  test 'timeout failure lines have no status' do
    stub_request(:get, PEOPLE_URL).to_timeout

    perform_enqueued_jobs { TwentyMailSyncJob.perform_later(42) }

    payloads = failure_payloads
    assert_equal 3, payloads.size
    payloads.each do |payload|
      assert_nil payload['status']
      assert_equal 'TwentyClient::RetryableError', payload['error_class']
    end
  end

  test 'log excludes secrets and email on success' do
    stub_people(people_response(body: MATCH_BODY))
    stub_activity(status: 201)

    assert_log_redacted
  end

  test 'log excludes secrets and email on 503' do
    stub_people(people_response(status: 503))

    assert_log_redacted
  end

  test 'log excludes secrets and email on timeout' do
    stub_request(:get, PEOPLE_URL).to_timeout

    assert_log_redacted
  end

  test 'log excludes secrets and email on 401' do
    stub_people(people_response(status: 401))

    assert_log_redacted
  end

  test 'log excludes secrets and email on 400' do
    stub_people(people_response(status: 400))

    assert_log_redacted
  end

  test 'log excludes secrets and email when the key is missing' do
    ENV.delete('TWENTY_API_KEY')
    stub_request(:any, /twenty/)

    assert_log_redacted
  end

  test 'retrying is logged at WARN and gave_up at ERROR' do
    logger = Logger.new(@log = StringIO.new)
    logger.formatter = ->(severity, _time, _progname, msg) { "#{severity} #{msg}\n" }
    ActiveJob::Base.logger = ActiveSupport::TaggedLogging.new(logger)
    stub_people(people_response(status: 503))

    perform_enqueued_jobs { TwentyMailSyncJob.perform_later(42) }

    lines = failure_lines
    assert_equal 3, lines.size
    assert lines[0].start_with?('WARN '), lines[0]
    assert lines[1].start_with?('WARN '), lines[1]
    assert lines[2].start_with?('ERROR '), lines[2]
    assert_includes lines[2], '"outcome":"gave_up"'
  end

  private

  def assert_log_redacted
    assert_nothing_raised { perform_enqueued_jobs { TwentyMailSyncJob.perform_later(42) } }

    log = @log.string
    assert_not_empty log
    assert_not_includes log, FAKE_KEY
    assert_not_includes log, 'Bearer '
    assert_not_includes log, FAKE_EMAIL
  end

  def failure_lines
    @log.string.lines.grep(/twenty_mail_sync\.failure /)
  end

  def failure_payloads
    failure_lines.map { |line| JSON.parse(line[/twenty_mail_sync\.failure (\{.*\})/, 1]) }
  end

  def assert_skipped_invalid_credentials(status)
    stub_people(people_response(status: status))

    assert_nothing_raised { TwentyMailSyncJob.perform_now(42) }

    assert_requested :get, PEOPLE_URL, times: 1
    assert_no_enqueued_jobs
    assert_includes @log.string, '"outcome":"skipped_invalid_credentials"'
    assert_includes @log.string, '"mail_id":42'
  end

  def stub_people(*responses)
    stub_request(:get, PEOPLE_URL).to_return(*responses)
  end

  def stub_activity(status:)
    stub_request(:post, ACTIVITIES_URL).to_return(status: status, body: '{}', headers: JSON_HEADERS)
  end

  def people_response(status: 200, body: nil)
    { status: status, body: body&.to_json || '', headers: JSON_HEADERS }
  end
end
