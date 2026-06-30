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

  def self.auth_headers
    { 'Authorization' => "Bearer #{KEY}" }
  end
end
