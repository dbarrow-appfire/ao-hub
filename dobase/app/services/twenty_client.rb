# frozen_string_literal: true

module TwentyClient
  TIMEOUT_SECONDS = 10

  # Timeout::Error covers Net::OpenTimeout, Net::ReadTimeout and Net::WriteTimeout.
  NETWORK_ERRORS = [
    Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH,
    Errno::ENETUNREACH, Errno::ETIMEDOUT, SocketError, EOFError
  ].freeze

  class Error < StandardError
    attr_reader :endpoint, :status

    def initialize(message = nil, endpoint: nil, status: nil)
      super(message)
      @endpoint = endpoint
      @status = status
    end
  end

  class RetryableError < Error; end
  class ClientError < Error; end
  class AuthenticationError < ClientError; end
  class MissingCredentialsError < Error; end

  def self.find_person_by_email(email)
    resp = request(:get, '/rest/people', query: { filter: "email.primaryEmail[eq]:#{email}" })
    resp.parsed_response.dig('data', 'people', 'edges', 0, 'node')
  end

  def self.create_activity(payload)
    request(
      :post,
      '/rest/timelineActivities',
      body: payload.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )
  end

  def self.base_url
    credential('TWENTY_API_URL')
  end

  def self.api_key
    credential('TWENTY_API_KEY')
  end

  def self.auth_headers
    { 'Authorization' => "Bearer #{api_key}" }
  end

  # Blank values count as missing. The message names the variable, never its value.
  def self.credential(name, endpoint = nil)
    value = ENV[name].to_s.strip
    raise MissingCredentialsError.new("#{name} is not set", endpoint: endpoint) if value.empty?

    value
  end
  private_class_method :credential

  # Error messages carry only METHOD /path and the status: never the URL, query string,
  # headers or raw body, so they are safe to log.
  def self.request(method, path, headers: {}, **options)
    endpoint = "#{method.to_s.upcase} #{path}"
    url = "#{credential('TWENTY_API_URL', endpoint)}#{path}"
    headers = { 'Authorization' => "Bearer #{credential('TWENTY_API_KEY', endpoint)}" }.merge(headers)

    begin
      resp = HTTParty.public_send(method, url, headers: headers, timeout: TIMEOUT_SECONDS, **options)
    rescue *NETWORK_ERRORS => e
      raise RetryableError.new("Twenty #{endpoint} failed with #{e.class}", endpoint: endpoint)
    end
    return resp if resp.code.between?(200, 299)

    message = "Twenty #{endpoint} failed with #{resp.code}"
    body = begin
      resp.parsed_response
    rescue JSON::ParserError
      nil
    end
    message += " (#{body['error']})" if body.is_a?(Hash) && body.key?('error')

    error_class =
      if [401, 403].include?(resp.code) then AuthenticationError
      elsif resp.code == 429 || resp.code >= 500 then RetryableError
      else ClientError
      end
    raise error_class.new(message, endpoint: endpoint, status: resp.code)
  end
  private_class_method :request
end
