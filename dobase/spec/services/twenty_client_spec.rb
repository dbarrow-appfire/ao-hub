# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TwentyClient do
  let(:email) { 'ada@example.test' }
  let(:original_api_url) { ENV['TWENTY_API_URL'] }
  let(:original_api_key) { ENV['TWENTY_API_KEY'] }

  def http_response(code:, body: {})
    double('HTTParty::Response', code: code, parsed_response: body)
  end

  before do
    ENV['TWENTY_API_URL'] = 'https://twenty.example.test'
    ENV['TWENTY_API_KEY'] = 'test-api-key-fake-9f3a2c'
    allow(TwentyClient).to receive(:backoff_sleep)
  end

  after do
    ENV['TWENTY_API_URL'] = original_api_url
    ENV['TWENTY_API_KEY'] = original_api_key
  end

  describe 'retryable failures' do
    context 'when Twenty responds with 500 on every attempt' do
      it 'retries exactly MAX_ATTEMPTS times then raises RetryableError' do
        allow(HTTParty).to receive(:get).and_return(http_response(code: 500))

        expect do
          TwentyClient.find_person_by_email(email)
        end.to raise_error(TwentyClient::RetryableError)

        expect(HTTParty).to have_received(:get).exactly(3).times
        expect(TwentyClient).to have_received(:backoff_sleep).exactly(2).times
      end
    end

    context 'when Twenty responds with 429 on every attempt' do
      it 'retries up to MAX_ATTEMPTS times then raises RetryableError' do
        allow(HTTParty).to receive(:get).and_return(http_response(code: 429))

        expect do
          TwentyClient.find_person_by_email(email)
        end.to raise_error(TwentyClient::RetryableError)

        expect(HTTParty).to have_received(:get).exactly(3).times
        expect(TwentyClient).to have_received(:backoff_sleep).exactly(2).times
      end
    end

    context 'when HTTParty raises Net::ReadTimeout on every attempt' do
      it 'retries then re-raises Net::ReadTimeout after MAX_ATTEMPTS attempts' do
        allow(HTTParty).to receive(:get).and_raise(Net::ReadTimeout)

        expect do
          TwentyClient.find_person_by_email(email)
        end.to raise_error(Net::ReadTimeout)

        expect(HTTParty).to have_received(:get).exactly(3).times
        expect(TwentyClient).to have_received(:backoff_sleep).exactly(2).times
      end
    end
  end

  describe 'non-retryable failures' do
    context 'when Twenty responds with 401' do
      it 'raises NonRetryableError with status 401 after a single call and no backoff' do
        allow(HTTParty).to receive(:get).and_return(http_response(code: 401))

        expect do
          TwentyClient.find_person_by_email(email)
        end.to raise_error(TwentyClient::NonRetryableError) do |error|
          expect(error.status).to eq(401)
        end

        expect(HTTParty).to have_received(:get).exactly(1).time
        expect(TwentyClient).not_to have_received(:backoff_sleep)
      end
    end

    context 'when Twenty responds with 422' do
      it 'fails immediately after a single call without retrying' do
        allow(HTTParty).to receive(:get).and_return(http_response(code: 422))

        expect do
          TwentyClient.find_person_by_email(email)
        end.to raise_error(TwentyClient::NonRetryableError) do |error|
          expect(error.status).to eq(422)
        end

        expect(HTTParty).to have_received(:get).exactly(1).time
        expect(TwentyClient).not_to have_received(:backoff_sleep)
      end
    end
  end

  describe 'successful calls' do
    context 'when Twenty responds with 200' do
      it 'returns the parsed person node without raising' do
        expected_node = { 'id' => 'person-1', 'name' => { 'firstName' => 'Ada' } }
        body = {
          'data' => {
            'people' => {
              'edges' => [{ 'node' => expected_node }]
            }
          }
        }
        allow(HTTParty).to receive(:get).and_return(http_response(code: 200, body: body))

        result = TwentyClient.find_person_by_email(email)

        expect(result).to eq(expected_node)
        expect(HTTParty).to have_received(:get).exactly(1).time
      end
    end
  end

  describe 'failure logging' do
    context 'when a call fails' do
      it 'logs a JSON string with endpoint, status, attempt, and error_class keys' do
        logged_messages = []
        allow(Rails.logger).to receive(:error) { |message| logged_messages << message }
        allow(HTTParty).to receive(:get).and_return(http_response(code: 500))

        expect do
          TwentyClient.find_person_by_email(email)
        end.to raise_error(TwentyClient::RetryableError)

        expect(logged_messages).not_to be_empty
        parsed = JSON.parse(logged_messages.first)
        expect(parsed).to include(
          'endpoint' => '/rest/people',
          'status' => 500,
          'attempt' => 1,
          'error_class' => 'TwentyClient::RetryableError'
        )
      end
    end

    context 'when a call fails and logging occurs' do
      it 'never includes the API key value, the Bearer scheme, or the query email' do
        secret_api_key = ENV.fetch('TWENTY_API_KEY')
        logged_messages = []
        allow(Rails.logger).to receive(:error) { |message| logged_messages << message }
        allow(HTTParty).to receive(:get).and_return(http_response(code: 500))

        expect do
          TwentyClient.find_person_by_email(email)
        end.to raise_error(TwentyClient::RetryableError)

        combined_log = logged_messages.join

        expect(combined_log).not_to include(secret_api_key)
        expect(combined_log).not_to include('Bearer')
        expect(combined_log).not_to include(email)
      end
    end
  end
end
