# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TwentyMailSyncJob do
  let(:mail_id) { 42 }
  let(:mail) { double('Mail', subject: 'Hello', correspondent_email: 'ada@example.test') }

  before do
    allow(Mail).to receive(:find).with(mail_id).and_return(mail)
  end

  context 'when TwentyClient raises MissingCredentialsError' do
    before do
      allow(TwentyClient).to receive(:find_person_by_email)
        .and_raise(TwentyClient::MissingCredentialsError, 'TWENTY_API_KEY is not set')
      allow(TwentyClient).to receive(:create_activity)
    end

    it 'logs an error entry containing the mail_id' do
      logged_messages = []
      allow(Rails.logger).to receive(:error) { |message| logged_messages << message }

      described_class.new.perform(mail_id)

      expect(logged_messages).not_to be_empty
      parsed = JSON.parse(logged_messages.first)
      expect(parsed).to include(
        'mail_id' => mail_id,
        'error_class' => 'TwentyClient::MissingCredentialsError'
      )
    end

    it 'returns normally without raising' do
      expect { described_class.new.perform(mail_id) }.not_to raise_error
    end

    it 'does not call create_activity' do
      described_class.new.perform(mail_id)

      expect(TwentyClient).not_to have_received(:create_activity)
    end
  end
end
