# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TwentyClient do
  let(:api_url) { 'https://twenty.example.test' }
  let(:api_key) { 'super-secret-token' }
  let(:activity_payload) { { name: 'Mail synced', type: 'EMAIL', linkedObjectRecordId: 'contact-1', linkedObjectName: 'person' } }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('TWENTY_API_URL').and_return(api_url)
    allow(ENV).to receive(:[]).with('TWENTY_API_KEY').and_return(api_key)
  end

  describe '.find_person_by_email' do
    it 'raises MissingCredentialsError when TWENTY_API_KEY is unset' do
      allow(ENV).to receive(:[]).with('TWENTY_API_KEY').and_return(nil)

      expect { described_class.find_person_by_email('ada@example.com') }
        .to raise_error(TwentyClient::MissingCredentialsError, 'TWENTY_API_KEY is not set')
    end

    it 'raises MissingCredentialsError when TWENTY_API_KEY is empty' do
      allow(ENV).to receive(:[]).with('TWENTY_API_KEY').and_return('')

      expect { described_class.find_person_by_email('ada@example.com') }
        .to raise_error(TwentyClient::MissingCredentialsError, 'TWENTY_API_KEY is not set')
    end

    it 'returns the exact person node hash on a successful response' do
      node = { 'id' => 'person-123', 'name' => { 'firstName' => 'Ada', 'lastName' => 'Lovelace' } }
      stub_request(:get, "#{api_url}/rest/people")
        .with(
          query: { filter: 'email.primaryEmail[eq]:ada@example.com' },
          headers: { 'Authorization' => "Bearer #{api_key}" }
        )
        .to_return(
          status: 200,
          body: { data: { people: { edges: [{ node: node }] } } }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      result = described_class.find_person_by_email('ada@example.com')

      expect(result).to eq(node)
    end
  end

  describe '.create_activity' do
    it 'raises TransientError on a stubbed 503 response' do
      stub_request(:post, "#{api_url}/rest/timelineActivities")
        .to_return(status: 503, body: 'Service Unavailable')

      expect { described_class.create_activity(activity_payload) }
        .to raise_error(TwentyClient::TransientError, 'Transient Twenty API error (status 503)')
    end

    it 'raises RequestError on a stubbed 404 response' do
      stub_request(:post, "#{api_url}/rest/timelineActivities")
        .to_return(status: 404, body: 'Not Found')

      expect { described_class.create_activity(activity_payload) }
        .to raise_error(TwentyClient::RequestError, 'Twenty API request failed (status 404)')
    end

    it 'logs the http method, request path, and status on a stubbed 500 response' do
      logged_message = nil
      allow(Rails.logger).to receive(:error) { |message| logged_message = message }

      stub_request(:post, "#{api_url}/rest/timelineActivities")
        .to_return(status: 500, body: 'Internal Server Error')

      expect { described_class.create_activity(activity_payload) }
        .to raise_error(TwentyClient::TransientError)

      expect(logged_message).to include('post')
      expect(logged_message).to include('/rest/timelineActivities')
      expect(logged_message).to include('500')
    end

    it 'does not log the api key or authorization scheme on a stubbed 500 response' do
      logged_message = nil
      allow(Rails.logger).to receive(:error) { |message| logged_message = message }

      stub_request(:post, "#{api_url}/rest/timelineActivities")
        .to_return(status: 500, body: 'Internal Server Error')

      expect { described_class.create_activity(activity_payload) }
        .to raise_error(TwentyClient::TransientError)

      expect(logged_message).not_to include(api_key)
      expect(logged_message).not_to include('Authorization')
      expect(logged_message).not_to include('Bearer')
    end
  end
end
