# frozen_string_literal: true

class TwentyMailSyncJob < ApplicationJob
  queue_as :integrations

  MAX_ATTEMPTS = 3

  # Proc wait gives exact 2s/4s backoff; :exponentially_longer is deprecated since Rails 7.1.
  # The block is intentionally empty: perform has already logged gave_up, and re-raising
  # would let backends with their own retries (e.g. Sidekiq) retry beyond the cap.
  retry_on TwentyClient::RetryableError,
           attempts: MAX_ATTEMPTS,
           wait: ->(executions) { 2.seconds * (2**(executions - 1)) } do |_job, _error|
  end

  # Covers AuthenticationError and ConfigurationError: skip this mail, keep the queue moving.
  discard_on TwentyClient::NonRetryableError

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
    log_twenty_failure(e, mail_id)
    raise
  end

  private

  # Logs ids and request metadata only — never the subject, correspondent email, headers or URLs.
  def log_twenty_failure(error, mail_id)
    outcome = twenty_failure_outcome(error)
    payload = {
      job: self.class.name,
      job_id: job_id,
      mail_id: mail_id,
      http_method: error.http_method,
      endpoint: error.endpoint,
      status: error.status,
      error_class: error.class.name,
      message: error.message,
      attempt: executions,
      max_attempts: MAX_ATTEMPTS,
      outcome: outcome
    }
    logger.public_send(outcome == 'retrying' ? :warn : :error, "twenty_mail_sync.failure #{payload.to_json}")
  end

  def twenty_failure_outcome(error)
    case error
    when TwentyClient::ConfigurationError then 'skipped_missing_credentials'
    when TwentyClient::AuthenticationError then 'skipped_invalid_credentials'
    when TwentyClient::NonRetryableError then 'failed_non_retryable'
    else executions < MAX_ATTEMPTS ? 'retrying' : 'gave_up'
    end
  end
end
