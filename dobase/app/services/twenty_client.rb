# frozen_string_literal: true

module TwentyClient
  BASE = ENV.fetch('TWENTY_API_URL')
  KEY = ENV.fetch('TWENTY_API_KEY')

  def self.find_person_by_email(email)
    resp = HTTParty.get(
      "#{BASE}/rest/people",
      query: { filter: "email.primaryEmail[eq]:#{email}" },
      headers: auth_headers
    )
    resp.parsed_response.dig('data', 'people', 'edges', 0, 'node')
  end

  def self.create_activity(payload)
    HTTParty.post(
      "#{BASE}/rest/timelineActivities",
      body: payload.to_json,
      headers: auth_headers.merge('Content-Type' => 'application/json')
    )
  end

  def self.create_task(payload)
    path = '/rest/tasks'
    resp = HTTParty.post("#{BASE}#{path}", body: payload.to_json, headers: json_headers)
    check!(resp, 'POST', path)
    created_id(resp, 'createTask')
  end

  def self.update_task(task_id, payload)
    path = "/rest/tasks/#{task_id}"
    resp = HTTParty.patch("#{BASE}#{path}", body: payload.to_json, headers: json_headers)
    check!(resp, 'PATCH', path)
  end

  def self.delete_task(task_id)
    path = "/rest/tasks/#{task_id}"
    resp = HTTParty.delete("#{BASE}#{path}", headers: auth_headers)
    check!(resp, 'DELETE', path)
  end

  def self.create_task_target(task_id, person_id)
    path = '/rest/taskTargets'
    resp = HTTParty.post(
      "#{BASE}#{path}",
      body: { taskId: task_id, personId: person_id }.to_json,
      headers: json_headers
    )
    check!(resp, 'POST', path)
    created_id(resp, 'createTaskTarget')
  end

  def self.list_task_targets(task_id)
    path = '/rest/taskTargets'
    resp = HTTParty.get(
      "#{BASE}#{path}",
      query: { filter: "taskId[eq]:#{task_id}" },
      headers: auth_headers
    )
    check!(resp, 'GET', path)
    edges = resp.parsed_response.dig('data', 'taskTargets', 'edges') if resp.parsed_response.is_a?(Hash)
    Array(edges).map { |edge| edge['node'] }
  end

  def self.delete_task_target(target_id)
    path = "/rest/taskTargets/#{target_id}"
    resp = HTTParty.delete("#{BASE}#{path}", headers: auth_headers)
    check!(resp, 'DELETE', path)
  end

  def self.auth_headers
    { 'Authorization' => "Bearer #{KEY}" }
  end

  def self.json_headers
    auth_headers.merge('Content-Type' => 'application/json')
  end

  # Raises unless the response is 2xx. The message carries only the HTTP method,
  # path and status, never the request body, headers or API key.
  def self.check!(resp, method, path)
    status = resp.code.to_i
    raise Error.new(method, path, status) unless status.between?(200, 299)

    resp
  end

  # Twenty REST create responses are unverified for the targeted version, so accept
  # `data.<createX>.id`, `data.id` or a top-level `id`.
  def self.created_id(resp, create_key)
    body = resp.parsed_response
    return unless body.is_a?(Hash)

    body.dig('data', create_key, 'id') || body.dig('data', 'id') || body['id']
  end

  class Error < StandardError
    attr_reader :status

    def initialize(method, path, status)
      @status = status
      super("Twenty #{method} #{path} failed with status #{status}")
    end
  end
end
