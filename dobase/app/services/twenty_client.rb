# frozen_string_literal: true

module TwentyClient
  # Messages carry only method, endpoint path and status — never URLs, headers or bodies.
  class Error < StandardError
    attr_reader :http_method, :endpoint, :status

    def initialize(message = nil, http_method: nil, endpoint: nil, status: nil)
      super(message)
      @http_method = http_method
      @endpoint = endpoint
      @status = status
    end
  end

  class RetryableError < Error; end
  class NonRetryableError < Error; end
  class AuthenticationError < NonRetryableError; end
  class ConfigurationError < NonRetryableError; end

  TIMEOUT = 10

  # Timeout::Error also covers Net::OpenTimeout and Net::ReadTimeout.
  RETRYABLE_EXCEPTIONS = [
    Timeout::Error,
    Net::WriteTimeout,
    Errno::ECONNREFUSED,
    Errno::ECONNRESET,
    Errno::EHOSTUNREACH,
    Errno::ETIMEDOUT,
    SocketError,
    EOFError
  ].freeze

  def self.find_person_by_email(email)
    resp = request(:get, '/rest/people', query: { filter: "email.primaryEmail[eq]:#{email}" })
    unless resp.parsed_response.is_a?(Hash)
      raise NonRetryableError.new(
        "GET /rest/people returned an unexpected body (HTTP #{resp.code})",
        http_method: 'GET', endpoint: '/rest/people', status: resp.code
      )
    end

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

  def self.request(method, path, headers: {}, **opts)
    http_method = method.to_s.upcase

    begin
      url = "#{base_url}#{path}"
      all_headers = auth_headers.merge(headers)
    rescue ConfigurationError => e
      raise ConfigurationError.new(e.message, http_method: http_method, endpoint: path)
    end

    begin
      resp = HTTParty.public_send(method, url, headers: all_headers, timeout: TIMEOUT, **opts)
    rescue *RETRYABLE_EXCEPTIONS => e
      # cause: nil so the unredacted original message is not chained onto the error.
      raise RetryableError.new(
        "#{http_method} #{path} failed: #{e.class}: #{redact(e.message)}",
        http_method: http_method, endpoint: path, status: nil
      ), cause: nil
    end

    status = resp.code
    return resp if (200..299).cover?(status)

    message = "#{http_method} #{path} returned HTTP #{status}"
    error_class =
      if status == 429 || (500..599).cover?(status)
        RetryableError
      elsif [401, 403].include?(status)
        AuthenticationError
      else
        NonRetryableError
      end
    raise error_class.new(message, http_method: http_method, endpoint: path, status: status)
  end

  def self.auth_headers
    { 'Authorization' => "Bearer #{api_key}" }
  end

  def self.base_url
    fetch_env('TWENTY_API_URL')
  end

  def self.api_key
    fetch_env('TWENTY_API_KEY')
  end

  # Scrubs the API key, bearer tokens and email addresses from wrapped exception messages.
  def self.redact(text)
    redacted = text.to_s
    key = ENV.fetch('TWENTY_API_KEY', '')
    redacted = redacted.gsub(key, '[REDACTED]') if key.present?
    redacted
      .gsub(/Bearer\s+\S+/i, '[REDACTED]')
      .gsub(/[^\s@]+@[^\s@]+\.[^\s@]+/, '[REDACTED]')
  end

  def self.fetch_env(name)
    value = ENV.fetch(name, '')
    raise ConfigurationError, "#{name} is not set" if value.blank?

    value
  end
end
