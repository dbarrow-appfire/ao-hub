# frozen_string_literal: true

module TwentyClient
  BASE = ENV.fetch('TWENTY_API_URL')
  KEY = ENV.fetch('TWENTY_API_KEY')

  class Error < StandardError; end

  NETWORK_ERRORS = [HTTParty::Error, SocketError, Timeout::Error, SystemCallError].freeze

  def self.request(verb, path, **options)
    HTTParty.public_send(verb, "#{BASE}#{path}", **options)
  rescue *NETWORK_ERRORS => e
    raise Error, "Twenty #{verb.to_s.upcase} #{path} failed (#{e.class.name})"
  end

  def self.ensure_success!(resp, verb, path)
    return if resp.success?

    raise Error, "Twenty #{verb} #{path} failed (#{resp.code})"
  end

  def self.find_person_by_email(email)
    path = '/rest/people'
    resp = request(
      :get,
      path,
      query: { filter: "email.primaryEmail[eq]:#{email}" },
      headers: auth_headers
    )
    ensure_success!(resp, 'GET', path)
    resp.parsed_response.dig('data', 'people', 'edges', 0, 'node')
  end

  def self.create_activity(payload)
    path = '/rest/timelineActivities'
    resp = request(
      :post,
      path,
      body: payload.to_json,
      headers: auth_headers.merge('Content-Type' => 'application/json')
    )
    ensure_success!(resp, 'POST', path)
    resp.parsed_response
  end

  def self.find_activity(id)
    path = "/rest/timelineActivities/#{id}"
    resp = request(:get, path, headers: auth_headers)
    return nil if resp.code == 404

    ensure_success!(resp, 'GET', path)
    resp.parsed_response.dig('data', 'timelineActivity')
  end

  def self.auth_headers
    { 'Authorization' => "Bearer #{KEY}" }
  end
end
