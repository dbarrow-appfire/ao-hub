# frozen_string_literal: true

module TwentyClient
  class ApiError < StandardError
    attr_reader :status, :body, :http_method, :path

    def initialize(status:, body:, http_method:, path:)
      @status      = status
      @body        = body
      @http_method = http_method
      @path        = path
      super("Twenty API #{http_method.upcase} #{path} failed: #{status}")
    end
  end

  def self.find_person_by_email(email)
    parsed = request(:get, '/rest/people', query: { filter: "emails.primaryEmail[eq]:#{email}" })
    parsed.dig('data', 'people', 0)
  end

  def self.create_activity(payload)
    request(:post, '/rest/timelineActivities', body: payload)
  end

  def self.auth_headers
    { 'Authorization' => "Bearer #{api_key}" }
  end

  class << self
    private

    def base_url
      ENV.fetch('TWENTY_API_URL')
    end

    def api_key
      ENV.fetch('TWENTY_API_KEY')
    end

    def request(http_method, path, query: nil, body: nil)
      url     = base_url + path
      headers = auth_headers
      headers = headers.merge('Content-Type' => 'application/json') if body

      options          = { headers: headers }
      options[:query]  = query      if query
      options[:body]   = body.to_json if body

      begin
        resp = HTTParty.public_send(http_method, url, **options)
      rescue HTTParty::Error, SocketError, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED
        raise ApiError.new(status: nil, body: nil, http_method: http_method, path: path)
      end

      unless (200..299).cover?(resp.code)
        Rails.logger.error(
          "TwentyClient #{http_method.upcase} #{path} failed " \
          "status=#{resp.code} body=#{resp.body.to_s[0, 500]}"
        )
        raise ApiError.new(status: resp.code, body: resp.body, http_method: http_method, path: path)
      end

      resp.parsed_response
    end
  end
end
