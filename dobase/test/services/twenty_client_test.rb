# frozen_string_literal: true

# TwentyClient reads these with ENV.fetch at load time; fake placeholders keep the
# test bootable without a real Twenty instance.
ENV['TWENTY_API_URL'] ||= 'https://twenty.example.test'
ENV['TWENTY_API_KEY'] ||= 'fake-twenty-api-key'

require 'test_helper'
require 'json'
require_relative '../support/stub_helper'

class TwentyClientTest < ActiveSupport::TestCase
  include StubHelper

  FakeResponse = StubHelper::FakeResponse

  test 'create_task returns the id of the created task on 2xx' do
    calls = []
    response = FakeResponse.new(code: 201, parsed_response: { 'data' => { 'createTask' => { 'id' => 'task-123' } } })
    stub = lambda do |url, **opts|
      calls << [url, opts]
      response
    end

    id = with_stub(HTTParty, :post, stub) { TwentyClient.create_task(title: 'Standup') }

    assert_equal 'task-123', id
    url, opts = calls.sole
    assert_equal "#{TwentyClient::BASE}/rest/tasks", url
    assert_equal({ 'title' => 'Standup' }, JSON.parse(opts[:body]))
    assert_equal 'application/json', opts[:headers]['Content-Type']
  end

  test 'create_task raises Error with status 500 without leaking the API key' do
    response = FakeResponse.new(code: 500, parsed_response: { 'error' => 'boom' })

    err = assert_raises(TwentyClient::Error) do
      with_stub(HTTParty, :post, response) { TwentyClient.create_task(title: 'Standup') }
    end

    assert_equal 500, err.status
    assert_equal 'Twenty POST /rest/tasks failed with status 500', err.message
    refute err.message.include?(TwentyClient::KEY), 'error message must not contain the API key'
  end

  test 'update_task raises Error with status 404 when the task is gone' do
    response = FakeResponse.new(code: 404, parsed_response: nil)

    err = assert_raises(TwentyClient::Error) do
      with_stub(HTTParty, :patch, response) { TwentyClient.update_task('task-123', title: 'Moved') }
    end

    assert_equal 404, err.status
    assert_equal 'Twenty PATCH /rest/tasks/task-123 failed with status 404', err.message
  end

  test 'delete_task succeeds on 204' do
    calls = []
    response = FakeResponse.new(code: 204, parsed_response: nil)
    stub = lambda do |url, **opts|
      calls << [url, opts]
      response
    end

    result = with_stub(HTTParty, :delete, stub) { TwentyClient.delete_task('task-123') }

    assert_same response, result
    url, opts = calls.sole
    assert_equal "#{TwentyClient::BASE}/rest/tasks/task-123", url
    assert_equal "Bearer #{TwentyClient::KEY}", opts[:headers]['Authorization']
  end

  test 'list_task_targets returns the nodes filtered by task id' do
    calls = []
    nodes = [
      { 'id' => 'target-1', 'taskId' => 'task-123', 'personId' => 'person-1' },
      { 'id' => 'target-2', 'taskId' => 'task-123', 'companyId' => 'company-1' }
    ]
    body = { 'data' => { 'taskTargets' => { 'edges' => nodes.map { |node| { 'node' => node } } } } }
    stub = lambda do |url, **opts|
      calls << [url, opts]
      FakeResponse.new(code: 200, parsed_response: body)
    end

    result = with_stub(HTTParty, :get, stub) { TwentyClient.list_task_targets('task-123') }

    assert_equal nodes, result
    url, opts = calls.sole
    assert_equal "#{TwentyClient::BASE}/rest/taskTargets", url
    assert_equal({ filter: 'taskId[eq]:task-123' }, opts[:query])
  end

  test 'list_task_targets returns [] for an empty envelope' do
    body = { 'data' => { 'taskTargets' => { 'edges' => [] } } }
    response = FakeResponse.new(code: 200, parsed_response: body)

    result = with_stub(HTTParty, :get, response) { TwentyClient.list_task_targets('task-123') }

    assert_equal [], result
  end

  test 'list_task_targets returns [] when the body has no data envelope' do
    response = FakeResponse.new(code: 200, parsed_response: {})

    result = with_stub(HTTParty, :get, response) { TwentyClient.list_task_targets('task-123') }

    assert_equal [], result
  end

  test 'list_task_targets raises Error on a non-2xx response' do
    response = FakeResponse.new(code: 503, parsed_response: nil)

    err = assert_raises(TwentyClient::Error) do
      with_stub(HTTParty, :get, response) { TwentyClient.list_task_targets('task-123') }
    end

    assert_equal 503, err.status
  end
end
