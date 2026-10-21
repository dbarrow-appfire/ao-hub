# frozen_string_literal: true

ENV['TWENTY_API_URL'] ||= 'https://twenty.test'
ENV['TWENTY_API_KEY'] ||= 'test-key'

require 'test_helper'
require 'minitest/mock'

class TwentyClientTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:code, :parsed_response) do
    def success?
      code.between?(200, 299)
    end
  end

  EMAIL = 'person@example.test'

  test 'find_person_by_email returns the first node and sends the filter' do
    captured = nil
    stub = lambda do |url, **opts|
      captured = { url: url, opts: opts }
      FakeResponse.new(200, { 'data' => { 'people' => { 'edges' => [{ 'node' => { 'id' => 'p-1' } }] } } })
    end

    result = HTTParty.stub(:get, stub) { TwentyClient.find_person_by_email(EMAIL) }

    assert_equal({ 'id' => 'p-1' }, result)
    assert_equal "#{TwentyClient::BASE}/rest/people", captured[:url]
    assert_equal "email.primaryEmail[eq]:#{EMAIL}", captured[:opts][:query][:filter]
    assert_equal "Bearer #{TwentyClient::KEY}", captured[:opts][:headers]['Authorization']
  end

  test 'find_person_by_email returns nil when there are no edges' do
    stub = ->(_url, **_opts) { FakeResponse.new(200, { 'data' => { 'people' => { 'edges' => [] } } }) }

    assert_nil HTTParty.stub(:get, stub) { TwentyClient.find_person_by_email(EMAIL) }
  end

  test 'find_person_by_email raises a redacted error on a 500' do
    stub = ->(_url, **_opts) { FakeResponse.new(500, { 'error' => "boom #{EMAIL} #{TwentyClient::KEY}" }) }

    error = assert_raises(TwentyClient::Error) do
      HTTParty.stub(:get, stub) { TwentyClient.find_person_by_email(EMAIL) }
    end

    assert_equal 'Twenty GET /rest/people failed (500)', error.message
    refute_includes error.message, EMAIL
    refute_includes error.message, TwentyClient::KEY
  end

  test 'find_person_by_email wraps network errors without echoing the message' do
    stub = ->(_url, **_opts) { raise SocketError, "getaddrinfo failed for #{TwentyClient::BASE}?#{EMAIL}" }

    error = assert_raises(TwentyClient::Error) do
      HTTParty.stub(:get, stub) { TwentyClient.find_person_by_email(EMAIL) }
    end

    assert_equal 'Twenty GET /rest/people failed (SocketError)', error.message
    refute_includes error.message, EMAIL
  end

  test 'find_activity returns the timeline activity on a 200' do
    stub = ->(_url, **_opts) { FakeResponse.new(200, { 'data' => { 'timelineActivity' => { 'id' => 'a-1' } } }) }

    assert_equal({ 'id' => 'a-1' }, HTTParty.stub(:get, stub) { TwentyClient.find_activity('a-1') })
  end

  test 'find_activity returns nil on a 404' do
    stub = ->(_url, **_opts) { FakeResponse.new(404, {}) }

    assert_nil HTTParty.stub(:get, stub) { TwentyClient.find_activity('a-1') }
  end

  test 'find_activity raises a redacted error on a 500' do
    stub = ->(_url, **_opts) { FakeResponse.new(500, { 'error' => TwentyClient::KEY }) }

    error = assert_raises(TwentyClient::Error) do
      HTTParty.stub(:get, stub) { TwentyClient.find_activity('a-1') }
    end

    assert_equal 'Twenty GET /rest/timelineActivities/a-1 failed (500)', error.message
  end

  test 'create_activity posts a JSON payload and returns the parsed body' do
    captured = nil
    stub = lambda do |url, **opts|
      captured = { url: url, opts: opts }
      FakeResponse.new(201, { 'data' => { 'id' => 'a-1' } })
    end
    payload = { id: 'a-1', name: 'Test subject', type: 'EMAIL', linkedObjectRecordId: 'p-1', linkedObjectName: 'person' }

    result = HTTParty.stub(:post, stub) { TwentyClient.create_activity(payload) }

    assert_equal({ 'data' => { 'id' => 'a-1' } }, result)
    assert_equal "#{TwentyClient::BASE}/rest/timelineActivities", captured[:url]
    assert_equal 'application/json', captured[:opts][:headers]['Content-Type']
    body = JSON.parse(captured[:opts][:body])
    assert_equal 'p-1', body['linkedObjectRecordId']
    assert_equal 'person', body['linkedObjectName']
    assert_equal 'a-1', body['id']
  end

  test 'create_activity raises a redacted error on a 400' do
    stub = ->(_url, **_opts) { FakeResponse.new(400, { 'error' => TwentyClient::KEY }) }

    error = assert_raises(TwentyClient::Error) do
      HTTParty.stub(:post, stub) { TwentyClient.create_activity(id: 'a-1') }
    end

    assert_equal 'Twenty POST /rest/timelineActivities failed (400)', error.message
    refute_includes error.message, TwentyClient::KEY
  end

  test 'create_activity wraps a refused connection' do
    stub = ->(_url, **_opts) { raise Errno::ECONNREFUSED }

    assert_raises(TwentyClient::Error) do
      HTTParty.stub(:post, stub) { TwentyClient.create_activity(id: 'a-1') }
    end
  end
end
