# frozen_string_literal: true

# Fans out one CaldavSyncJob per user with CalDAV credentials. Run every
# 15 minutes by the recurring entry in config/recurring_snippet.yml.
#
# Jira: DEV-107
class CaldavSyncScheduleJob < ApplicationJob
  queue_as :integrations

  def perform
    User.where.not(caldav_url: [nil, ''])
        .where.not(caldav_token: [nil, ''])
        .find_each { |user| CaldavSyncJob.perform_later(user.id) }
  end
end
