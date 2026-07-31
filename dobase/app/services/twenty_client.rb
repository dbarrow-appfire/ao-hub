# frozen_string_literal: true

module TwentyClient
  class Error < StandardError; end
  class MissingCredentialsError < Error; end
  class TransientError < Error; end
  class RequestError < Error; end

  TRANSIENT_EXCEPTIONS = [
    Net::OpenTimeout,
    Net::ReadTimeout,
    Errno::ECONNREFUSED,
    SocketError,
    Timeout::Error,
    HTTParty::Error
  ].freeze

  def self.find_person_by_email(email)
    response = request(
      :get,
      '/rest/people',
      query: { filter: "email.primaryEmail[eq]:#{email}" },
      headers: auth_headers
    )
    response.dig('data', 'people', 'edges', 0, 'node')
  end

  def self.create_activity(payload)
    request(
      :post,
      '/rest/timelineActivities',
      body: payload.to_json,
      headers: auth_headers.merge('Content-Type' => 'application/json')
    )
  end

  def self.auth_headers
    { 'Authorization' => "Bearer #{api_key}" }
  end

  def self.base_url
    value = ENV['TWENTY_API_URL']
    raise MissingCredentialsError, 'TWENTY_API_URL is not set' if value.nil? || value.empty?

    value
  end

  def self.api_key
    value = ENV['TWENTY_API_KEY']
    raise MissingCredentialsError, 'TWENTY_API_KEY is not set' if value.nil? || value.empty?

    value
  end

  def self.request(method, path, **options)
    response = HTTParty.send(method, "#{base_url}#{path}", **options)
  rescue *TRANSIENT_EXCEPTIONS => e
    log_failure(method: method, path: path, status: nil, body: e.message)
    raise TransientError, "Network error calling Twenty API: #{e.message}"
  else
    status = response.code
    return response.parsed_response if status >= 200 && status < 300

    log_failure(method: method, path: path, status: status, body: response.body)
    raise TransientError, "Transient Twenty API error (status #{status})" if status == 429 || (status >= 500 && status <= 599)

    raise RequestError, "Twenty API request failed (status #{status})"
  end

  def self.log_failure(method:, path:, status:, body:)
    Rails.logger.error(
      "TwentyClient request failed method=#{method} path=#{path} status=#{status} body=#{body.to_s[0, 500]}"
    )
  end

  private_class_method :base_url, :api_key, :request, :log_failure
end
