# frozen_string_literal: true

class TwentyMailSyncJob < ApplicationJob
  queue_as :integrations

  discard_on ActiveRecord::RecordNotFound
  retry_on TwentyClient::TransientError, HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout,
           wait: :polynomially_longer, attempts: 5

  def perform(mail_id)
    Rails.logger.info("[TwentyMailSyncJob] mail_id=#{mail_id}")

    mail = Mail.find(mail_id)
    return if mail.correspondent_email.blank?

    contact = TwentyClient.find_person_by_email(mail.correspondent_email)
    return unless contact

    enqueue_activity(mail, contact)
  end

  private

  def enqueue_activity(mail, contact)
    TwentyClient.create_activity(
      name: mail.subject,
      type: 'EMAIL',
      linkedObjectRecordId: contact['id'],
      linkedObjectName: 'person',
      externalId: "dobase-mail-#{mail.id}"
    )
  end
end
