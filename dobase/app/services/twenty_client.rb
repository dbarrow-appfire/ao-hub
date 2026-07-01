# frozen_string_literal: true

module TwentyClient
  class TransientError < StandardError; end
  class ClientError < StandardError; end

  BASE = ENV.fetch('TWENTY_API_URL')
  KEY = ENV.fetch('TWENTY_API_KEY')

  def self.find_person_by_email(email)
    resp = HTTParty.get(
      "#{BASE}/rest/people",
      query: { filter: "email.primaryEmail[eq]:#{email}" },
      headers: auth_headers
    )
    handle_response(resp).dig('data', 'people', 'edges', 0, 'node')
  end

  def self.create_activity(payload)
    resp = HTTParty.post(
      "#{BASE}/rest/timelineActivities",
      body: payload.to_json,
      headers: auth_headers.merge('Content-Type' => 'application/json')
    )
    handle_response(resp)
  end

  def self.auth_headers
    { 'Authorization' => "Bearer #{KEY}" }
  end

  private_class_method def self.handle_response(resp)
    code = resp.code
    return resp.parsed_response if code >= 200 && code < 300
    raise TransientError, "Twenty API error #{code}: #{resp.body}" if code >= 500 || code == 429
    raise ClientError, "Twenty API error #{code}: #{resp.body}"
  end
end
