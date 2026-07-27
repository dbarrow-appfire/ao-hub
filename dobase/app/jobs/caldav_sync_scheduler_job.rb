# frozen_string_literal: true

class CaldavSyncSchedulerJob < ApplicationJob
  queue_as :integrations

  def perform
    User.where.not(caldav_url: nil).each do |user|
      CaldavSyncJob.perform_later(user.id)
    end
  end
end
