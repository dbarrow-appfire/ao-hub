# frozen_string_literal: true

module TwentyClient
  BASE = ENV.fetch('TWENTY_API_URL')
  KEY = ENV.fetch('TWENTY_API_KEY')
  TASK_UID_FIELD = ENV.fetch('TWENTY_TASK_CALDAV_UID_FIELD', 'caldavUid')

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

  def self.find_task_by_uid(uid)
    resp = HTTParty.get(
      "#{BASE}/rest/tasks",
      query: { filter: "#{TASK_UID_FIELD}[eq]:#{uid}" },
      headers: auth_headers
    )
    resp.parsed_response.dig('data', 'tasks', 'edges', 0, 'node')
  end

  def self.create_task(payload)
    resp = HTTParty.post(
      "#{BASE}/rest/tasks",
      body: payload.to_json,
      headers: auth_headers.merge('Content-Type' => 'application/json')
    )
    resp.parsed_response.dig('data', 'createTask')
  end

  def self.update_task(id, payload)
    resp = HTTParty.patch(
      "#{BASE}/rest/tasks/#{id}",
      body: payload.to_json,
      headers: auth_headers.merge('Content-Type' => 'application/json')
    )
    resp.parsed_response.dig('data', 'updateTask')
  end

  def self.create_task_target(task_id, person_id)
    resp = HTTParty.post(
      "#{BASE}/rest/taskTargets",
      body: { taskId: task_id, personId: person_id }.to_json,
      headers: auth_headers.merge('Content-Type' => 'application/json')
    )
    resp.parsed_response.dig('data', 'createTaskTarget')
  end

  def self.task_targets(task_id)
    resp = HTTParty.get(
      "#{BASE}/rest/taskTargets",
      query: { filter: "taskId[eq]:#{task_id}" },
      headers: auth_headers
    )
    (resp.parsed_response.dig('data', 'taskTargets', 'edges') || []).map { |edge| edge['node'] }
  end

  def self.auth_headers
    { 'Authorization' => "Bearer #{KEY}" }
  end
end
