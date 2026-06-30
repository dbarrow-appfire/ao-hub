# frozen_string_literal: true

module TwentySync
  class CalendarEvent
  # TODO: Implement upsert logic — create or update Twenty tasks from CalDAV events.
  # Link to relevant Twenty contact where attendee email matches.
  #
  # Jira: DEV-107

    def self.upsert(user, event)
      raise NotImplementedError, 'Calendar event upsert not yet implemented'
    end
  end
end
