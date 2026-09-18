# frozen_string_literal: true

module TwentyClient
  class Error < StandardError; end

  class MissingCredentialsError < Error; end

  class RetryableError < Error
    attr_reader :status

    def initialize(message, status: nil)
      super(message)
      @status = status
    end
  end

  class NonRetryableError < Error
    attr_reader :status

    def initialize(message, status: nil)
      super(message)
      @status = status
    end
  end

  MAX_ATTEMPTS = 3
  RETRYABLE_STATUSES = [429, 500, 502, 503, 504].freeze
  RETRYABLE_EXCEPTIONS = [
    Net::OpenTimeout,
    Net::ReadTimeout,
    SocketError,
    Errno::ECONNRESET,
    Errno::ECONNREFUSED
  ].freeze

  def self.find_person_by_email(email)
    resp = with_retry(endpoint: '/rest/people') do
      raw = HTTParty.get(
        "#{base_url}/rest/people",
        query: { filter: "email.primaryEmail[eq]:#{email}" },
        headers: auth_headers
      )
      check_response!(raw, endpoint: '/rest/people')
    end
    resp.parsed_response.dig('data', 'people', 'edges', 0, 'node')
  end

  def self.create_activity(payload)
    with_retry(endpoint: '/rest/timelineActivities') do
      raw = HTTParty.post(
        "#{base_url}/rest/timelineActivities",
        body: payload.to_json,
        headers: auth_headers.merge('Content-Type' => 'application/json')
      )
      check_response!(raw, endpoint: '/rest/timelineActivities')
    end
  end

  def self.auth_headers
    { 'Authorization' => "Bearer #{api_key}" }
  end

  class << self
    private

    def base_url
      value = ENV['TWENTY_API_URL']
      raise MissingCredentialsError, 'TWENTY_API_URL is not set' if value.nil? || value.empty?

      value
    end

    def api_key
      value = ENV['TWENTY_API_KEY']
      raise MissingCredentialsError, 'TWENTY_API_KEY is not set' if value.nil? || value.empty?

      value
    end

    def check_response!(resp, endpoint:)
      status = resp.code
      return resp if status >= 200 && status < 300

      if RETRYABLE_STATUSES.include?(status)
        raise RetryableError.new("Twenty API call to #{endpoint} failed", status: status)
      end

      raise NonRetryableError.new("Twenty API call to #{endpoint} failed", status: status)
    end

    def backoff_sleep(attempt)
      sleep((2**attempt) + rand)
    end

    def with_retry(endpoint:)
      attempt = 0
      begin
        attempt += 1
        yield
      rescue *RETRYABLE_EXCEPTIONS, RetryableError => e
        status = e.respond_to?(:status) ? e.status : nil
        log_failure(endpoint: endpoint, status: status, attempt: attempt, error: e)
        if attempt < MAX_ATTEMPTS
          backoff_sleep(attempt)
          retry
        end
        raise
      end
    end

    def log_failure(endpoint:, status:, attempt:, error:)
      Rails.logger.error({
        event: 'twenty_api_call_failed',
        endpoint: endpoint,
        status: status,
        attempt: attempt,
        error_class: error.class.name
      }.to_json)
    end
  end
end
