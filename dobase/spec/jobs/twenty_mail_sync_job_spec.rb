# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TwentyMailSyncJob do
  before do
    stub_const('Mail', Class.new do
      def self.find(id); end
    end)
  end

  describe '#perform' do
    it 'retries the job when TwentyClient.find_person_by_email raises TransientError' do
      mail = double('mail', subject: 'Hello there', correspondent_email: 'ada@example.com')
      allow(Mail).to receive(:find).with('mail-1').and_return(mail)
      allow(TwentyClient).to receive(:find_person_by_email)
        .with('ada@example.com')
        .and_raise(TwentyClient::TransientError, 'temporary outage')

      expect do
        described_class.new('mail-1').perform_now
      end.to change { described_class.queue_adapter.enqueued_jobs.size }.by(1)
    end

    it 'discards the job and logs an error when TwentyClient.find_person_by_email raises MissingCredentialsError' do
      mail = double('mail', subject: 'Hello there', correspondent_email: 'ada@example.com')
      allow(Mail).to receive(:find).with('mail-1').and_return(mail)
      allow(TwentyClient).to receive(:find_person_by_email)
        .with('ada@example.com')
        .and_raise(TwentyClient::MissingCredentialsError, 'TWENTY_API_KEY is not set')
      expect(Rails.logger).to receive(:error)

      expect do
        described_class.new('mail-1').perform_now
      end.not_to raise_error
    end

    it 'creates exactly one timeline activity for a matching contact' do
      mail = double('mail', subject: 'Hello there', correspondent_email: 'ada@example.com')
      contact = { 'id' => 'contact-1' }
      allow(Mail).to receive(:find).with('mail-1').and_return(mail)
      allow(TwentyClient).to receive(:find_person_by_email).with('ada@example.com').and_return(contact)
      allow(TwentyClient).to receive(:create_activity)

      described_class.new('mail-1').perform_now

      expect(TwentyClient).to have_received(:create_activity).once.with(
        name: 'Hello there',
        type: 'EMAIL',
        linkedObjectRecordId: 'contact-1',
        linkedObjectName: 'person'
      )
    end
  end
end
