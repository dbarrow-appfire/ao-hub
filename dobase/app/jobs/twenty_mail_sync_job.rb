# frozen_string_literal: true

class TwentyMailSyncJob < ApplicationJob
  queue_as :integrations

  retry_on TwentyClient::TransientError, wait: :polynomially_longer, attempts: 5

  discard_on TwentyClient::MissingCredentialsError do |job, error|
    Rails.logger.error("TwentyMailSyncJob discarded for job_id=#{job.job_id}: missing credentials (#{error.message})")
  end

  discard_on ActiveJob::DeserializationError

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
