# frozen_string_literal: true

require 'test_helper'
require 'webmock/minitest'

class TwentyClientTest < ActiveSupport::TestCase
  TWENTY_URL = 'https://twenty.example.test'
  FAKE_KEY = 'test-twenty-key-not-real'
  FAKE_EMAIL = 'person@example.test'
  PEOPLE_URL = %r{\Ahttps://twenty\.example\.test/rest/people}
  ACTIVITIES_URL = 'https://twenty.example.test/rest/timelineActivities'
  ENV_KEYS = %w[TWENTY_API_URL TWENTY_API_KEY].freeze

  setup do
    @original_env = ENV_KEYS.to_h { |name| [name, ENV.fetch(name, nil)] }
    ENV['TWENTY_API_URL'] = TWENTY_URL
    ENV['TWENTY_API_KEY'] = FAKE_KEY
  end

  teardown do
    @original_env.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
    WebMock.reset!
  end

  test 'find_person_by_email returns the first node on 200' do
    stub_people(body: { data: { people: { edges: [{ node: { id: 'person-1' } }] } } })

    node = TwentyClient.find_person_by_email(FAKE_EMAIL)

    assert_equal 'person-1', node['id']
    assert_requested :get, PEOPLE_URL, times: 1
  end

  test 'find_person_by_email returns nil on 200 with no edges' do
    stub_people(body: { data: { people: { edges: [] } } })

    assert_nil TwentyClient.find_person_by_email(FAKE_EMAIL)
    assert_requested :get, PEOPLE_URL, times: 1
  end

  test '503 raises RetryableError with request context' do
    stub_people(status: 503)

    error = assert_raises(TwentyClient::RetryableError) { TwentyClient.find_person_by_email(FAKE_EMAIL) }

    assert_equal TwentyClient::RetryableError, error.class
    assert_equal 503, error.status
    assert_equal '/rest/people', error.endpoint
    assert_equal 'GET', error.http_method
    assert_requested :get, PEOPLE_URL, times: 1
  end

  test '500 raises RetryableError' do
    error = assert_people_error(500, TwentyClient::RetryableError)

    assert_equal 500, error.status
  end

  test '429 raises RetryableError' do
    error = assert_people_error(429, TwentyClient::RetryableError)

    assert_equal 429, error.status
  end

  test '400 raises NonRetryableError that is not retryable' do
    error = assert_people_error(400, TwentyClient::NonRetryableError)

    assert_equal 400, error.status
    assert_not_kind_of TwentyClient::RetryableError, error
  end

  test '404 raises NonRetryableError' do
    error = assert_people_error(404, TwentyClient::NonRetryableError)

    assert_equal 404, error.status
  end

  test '422 on create_activity raises NonRetryableError' do
    stub_request(:post, ACTIVITIES_URL).to_return(status: 422)

    error = assert_raises(TwentyClient::NonRetryableError) { TwentyClient.create_activity(activity_payload) }

    assert_equal TwentyClient::NonRetryableError, error.class
    assert_equal 422, error.status
    assert_equal '/rest/timelineActivities', error.endpoint
    assert_equal 'POST', error.http_method
    assert_requested :post, ACTIVITIES_URL, times: 1
  end

  test '401 raises AuthenticationError' do
    error = assert_people_error(401, TwentyClient::AuthenticationError)

    assert_equal 401, error.status
  end

  test '403 raises AuthenticationError' do
    error = assert_people_error(403, TwentyClient::AuthenticationError)

    assert_equal 403, error.status
  end

  test '200 with an HTML body raises NonRetryableError' do
    stub_request(:get, PEOPLE_URL)
      .to_return(status: 200, body: '<html><body>Login</body></html>', headers: { 'Content-Type' => 'text/html' })

    error = assert_raises(TwentyClient::NonRetryableError) { TwentyClient.find_person_by_email(FAKE_EMAIL) }

    assert_equal TwentyClient::NonRetryableError, error.class
    assert_equal 200, error.status
    assert_equal '/rest/people', error.endpoint
    assert_requested :get, PEOPLE_URL, times: 1
  end

  test 'create_activity on 201 does not raise and sends the camelCase payload' do
    stub_request(:post, ACTIVITIES_URL).to_return(status: 201, body: '{}', headers: json_headers)

    assert_nothing_raised { TwentyClient.create_activity(activity_payload) }

    assert_requested(:post, ACTIVITIES_URL, times: 1) do |req|
      body = JSON.parse(req.body)
      body['linkedObjectRecordId'] == 'person-1' && body['linkedObjectName'] == 'person'
    end
  end

  test 'timeout raises RetryableError with no status' do
    stub_request(:get, PEOPLE_URL).to_timeout

    error = assert_raises(TwentyClient::RetryableError) { TwentyClient.find_person_by_email(FAKE_EMAIL) }

    assert_equal TwentyClient::RetryableError, error.class
    assert_nil error.status
    assert_equal '/rest/people', error.endpoint
    assert_requested :get, PEOPLE_URL, times: 1
  end

  test 'connection refused raises RetryableError' do
    stub_request(:get, PEOPLE_URL).to_raise(Errno::ECONNREFUSED)

    error = assert_raises(TwentyClient::RetryableError) { TwentyClient.find_person_by_email(FAKE_EMAIL) }

    assert_equal TwentyClient::RetryableError, error.class
    assert_nil error.status
    assert_requested :get, PEOPLE_URL, times: 1
  end

  test 'socket error raises RetryableError with a redacted message' do
    stub_request(:get, PEOPLE_URL).to_raise(SocketError.new("boom #{FAKE_EMAIL} #{FAKE_KEY}"))

    error = assert_raises(TwentyClient::RetryableError) { TwentyClient.find_person_by_email(FAKE_EMAIL) }

    assert_equal TwentyClient::RetryableError, error.class
    assert_not_includes error.message, FAKE_EMAIL
    assert_not_includes error.message, FAKE_KEY
    assert_includes error.message, '[REDACTED]'
    assert_nil error.cause
  end

  test 'missing TWENTY_API_KEY raises ConfigurationError without a request' do
    ENV.delete('TWENTY_API_KEY')
    stub_people(body: { data: { people: { edges: [] } } })

    error = assert_raises(TwentyClient::ConfigurationError) { TwentyClient.find_person_by_email(FAKE_EMAIL) }

    assert_equal TwentyClient::ConfigurationError, error.class
    assert_equal 'TWENTY_API_KEY is not set', error.message
    assert_equal '/rest/people', error.endpoint
    assert_not_requested :any, /twenty/
  end

  test 'blank TWENTY_API_URL raises ConfigurationError without a request' do
    ENV['TWENTY_API_URL'] = ''
    stub_request(:any, /twenty/)

    error = assert_raises(TwentyClient::ConfigurationError) { TwentyClient.find_person_by_email(FAKE_EMAIL) }

    assert_equal TwentyClient::ConfigurationError, error.class
    assert_equal 'TWENTY_API_URL is not set', error.message
    assert_not_requested :any, /twenty/
  end

  test 'loading the client with no Twenty env does not raise' do
    ENV_KEYS.each { |name| ENV.delete(name) }
    source = File.expand_path('../../app/services/twenty_client.rb', __dir__)

    # Reloading redefines TIMEOUT/RETRYABLE_EXCEPTIONS; silence the constant warnings.
    assert_nothing_raised { silence_warnings { load source } }
  end

  test 'error message and inspect exclude secrets and emails' do
    stub_people(status: 401)

    error = assert_raises(TwentyClient::AuthenticationError) { TwentyClient.find_person_by_email(FAKE_EMAIL) }

    [error.message, error.inspect].each do |text|
      assert_not_includes text, FAKE_KEY
      assert_not_includes text, 'Bearer '
      assert_not_includes text, FAKE_EMAIL
    end
  end

  test 'redact scrubs bearer tokens and email addresses' do
    assert_equal '[REDACTED] [REDACTED]', TwentyClient.redact('Bearer abc.def x@example.test')
  end

  private

  def stub_people(status: 200, body: nil)
    stub_request(:get, PEOPLE_URL).to_return(status: status, body: body&.to_json || '', headers: json_headers)
  end

  def assert_people_error(status, error_class)
    stub_people(status: status)

    error = assert_raises(error_class) { TwentyClient.find_person_by_email(FAKE_EMAIL) }

    assert_equal error_class, error.class
    assert_equal '/rest/people', error.endpoint
    assert_requested :get, PEOPLE_URL, times: 1
    error
  end

  def activity_payload
    { name: 'Fake subject', type: 'EMAIL', linkedObjectRecordId: 'person-1', linkedObjectName: 'person' }
  end

  def json_headers
    { 'Content-Type' => 'application/json' }
  end
end
