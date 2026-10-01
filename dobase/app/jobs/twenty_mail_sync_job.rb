# frozen_string_literal: true

class TwentyMailSyncJob < ApplicationJob
  MAX_ATTEMPTS = 3
  LOG_TAG = '[TwentyMailSyncJob]'

  queue_as :integrations

  # A lambda rather than :exponentially_longer/:polynomially_longer keeps Rails 5.1–8.x
  # compatibility: waits of 2s then 4s. The block must not re-raise, so adapter-level
  # retries can't exceed the cap.
  retry_on TwentyClient::RetryableError, attempts: MAX_ATTEMPTS, wait: ->(executions) { 2**executions } do |job, error|
    job.log_failure('twenty_sync_giving_up', error)
  end

  # rescue_from rather than discard_on, whose block form needs Rails 6.0. Swallowing the
  # error drops the job without a retry.
  rescue_from TwentyClient::ClientError do |error|
    event = error.is_a?(TwentyClient::AuthenticationError) ? 'twenty_sync_credentials_rejected' : 'twenty_sync_discarded'
    log_failure(event, error)
  end

  rescue_from TwentyClient::MissingCredentialsError do |error|
    log_failure('twenty_sync_skipped', error)
  end

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
  rescue TwentyClient::Error => e
    # Non-retryable errors (ClientError/MissingCredentialsError) are logged once by their
    # rescue_from handler below; logging them here too would duplicate the line.
    if e.is_a?(TwentyClient::RetryableError)
      retrying = executions < MAX_ATTEMPTS
      Rails.logger.public_send(retrying ? :warn : :error, log_line('twenty_call_failed', e))
    end
    raise
  end

  def log_failure(event, error)
    Rails.logger.error(log_line(event, error))
  end

  private

  # Only the mail_id argument is logged, never the correspondent email or subject.
  def log_line(event, error)
    status = error.status || (error.is_a?(TwentyClient::RetryableError) ? 'network' : 'none')
    "#{LOG_TAG} event=#{event} mail_id=#{arguments.first} endpoint=\"#{error.endpoint || 'n/a'}\" " \
      "status=#{status} attempt=#{executions}/#{MAX_ATTEMPTS} error=#{error.class.name} message=\"#{error.message}\""
  end
end
