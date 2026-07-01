# frozen_string_literal: true

class TwentyMailSyncJob < ApplicationJob
  queue_as :integrations
  retry_on TwentyClient::ApiError, wait: :exponentially_longer, attempts: 5

  def perform(mail_id)
    mail = Mail.find(mail_id)
    contact = TwentyClient.find_person_by_email(mail.correspondent_email)
    return unless contact

    TwentyClient.create_activity(
      name: mail.subject,
      type: 'EMAIL',
      linkedObjectRecordId: contact['id'],
      linkedObjectName: 'person'
    )
  end
end
