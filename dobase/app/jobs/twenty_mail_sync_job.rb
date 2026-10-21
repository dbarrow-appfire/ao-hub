# frozen_string_literal: true

require 'active_support/core_ext/digest/uuid'

class TwentyMailSyncJob < ApplicationJob
  queue_as :integrations

  retry_on TwentyClient::Error, wait: :polynomially_longer, attempts: 5
  discard_on ActiveRecord::RecordNotFound

  def perform(mail_id)
    mail = Mail.find(mail_id)
    email = mail.correspondent_email.to_s.strip
    return if email.blank?

    contact = TwentyClient.find_person_by_email(email)
    return unless contact

    activity_id = Digest::UUID.uuid_v5(Digest::UUID::URL_NAMESPACE, "dobase:mail:#{mail.id}")
    return if TwentyClient.find_activity(activity_id)

    begin
      TwentyClient.create_activity(
        id: activity_id,
        name: mail.subject.presence || '(no subject)',
        type: 'EMAIL',
        linkedObjectRecordId: contact['id'],
        linkedObjectName: 'person'
      )
    rescue TwentyClient::Error
      raise unless TwentyClient.find_activity(activity_id)
    end
  end
end
