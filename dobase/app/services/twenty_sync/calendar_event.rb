# frozen_string_literal: true

module TwentySync
  class CalendarEvent
    def self.upsert(user, event)
      payload = {
        title: event[:title],
        body: event[:description],
        status: 'TODO',
        dueAt: event[:starts_at].utc.iso8601,
        TwentyClient::TASK_UID_FIELD.to_sym => event[:uid]
      }

      existing_task = TwentyClient.find_task_by_uid(event[:uid])
      task = existing_task ? TwentyClient.update_task(existing_task['id'], payload) : TwentyClient.create_task(payload)

      link_contact(task, event[:attendee_emails])

      task
    end

    def self.link_contact(task, attendee_emails)
      return unless task && task['id']

      person = person_for(attendee_emails)
      return unless person

      already_linked = TwentyClient.task_targets(task['id']).any? { |target| target['personId'] == person['id'] }
      TwentyClient.create_task_target(task['id'], person['id']) unless already_linked
    end
    private_class_method :link_contact

    def self.person_for(attendee_emails)
      Array(attendee_emails).each do |email|
        person = TwentyClient.find_person_by_email(email)
        return person if person
      end
      nil
    end
    private_class_method :person_for
  end
end
