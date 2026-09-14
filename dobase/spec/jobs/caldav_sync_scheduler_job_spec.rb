# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CaldavSyncSchedulerJob do
  describe '#perform' do
    it 'enqueues one CaldavSyncJob per calendar-enabled user' do
      users = [
        instance_double(User, id: 1, caldav_url: 'https://caldav.example.com/one'),
        instance_double(User, id: 2, caldav_url: 'https://caldav.example.com/two')
      ]
      allow(User).to receive_message_chain(:where, :not).and_return(users)
      allow(CaldavSyncJob).to receive(:perform_later)

      described_class.new.perform

      expect(CaldavSyncJob).to have_received(:perform_later).with(1).once
      expect(CaldavSyncJob).to have_received(:perform_later).with(2).once
    end

    it 'skips users without a caldav_url' do
      user = instance_double(User, id: 3, caldav_url: nil)
      matching_users = [user].reject { |candidate| candidate.caldav_url.nil? }
      allow(User).to receive_message_chain(:where, :not).and_return(matching_users)
      allow(CaldavSyncJob).to receive(:perform_later)

      described_class.new.perform

      expect(CaldavSyncJob).not_to have_received(:perform_later)
    end
  end
end
