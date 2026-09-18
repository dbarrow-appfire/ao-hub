# frozen_string_literal: true

class TwentyMailSyncJob < ApplicationJob
  queue_as :integrations

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
  rescue TwentyClient::MissingCredentialsError => e
    Rails.logger.error({
      event: 'twenty_mail_sync_skipped',
      mail_id: mail_id,
      error_class: e.class.name
    }.to_json)
    nil
  end
end
