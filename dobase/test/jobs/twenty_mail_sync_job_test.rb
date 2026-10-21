# frozen_string_literal: true

ENV['TWENTY_API_URL'] ||= 'https://twenty.test'
ENV['TWENTY_API_KEY'] ||= 'test-key'

require 'test_helper'
require 'minitest/mock'

class TwentyMailSyncJobTest < ActiveJob::TestCase
  FakeMail = Struct.new(:id, :subject, :correspondent_email)

  MAIL = FakeMail.new(42, 'Test subject', ' person@example.test ')
  ACTIVITY_ID = Digest::UUID.uuid_v5(Digest::UUID::URL_NAMESPACE, 'dobase:mail:42')
  CONTACT = { 'id' => 'p-1' }.freeze
  NEVER = ->(*) { flunk 'unexpected call' }

  def run_job(mail: MAIL, person: ->(_email) { CONTACT }, find: ->(_id) {}, create: ->(_payload) {}, &block)
    Mail.stub(:find, mail) do
      TwentyClient.stub(:find_person_by_email, person) do
        TwentyClient.stub(:find_activity, find) do
          TwentyClient.stub(:create_activity, create, &block)
        end
      end
    end
  end

  test 'runs on the integrations queue' do
    assert_equal 'integrations', TwentyMailSyncJob.new.queue_name
  end

  test 'creates an activity for a matching contact' do
    created = []
    person = lambda do |email|
      assert_equal 'person@example.test', email
      CONTACT
    end

    run_job(person: person, create: ->(payload) { created << payload }) { TwentyMailSyncJob.perform_now(42) }

    assert_equal 1, created.size
    assert_equal(
      { id: ACTIVITY_ID, name: 'Test subject', type: 'EMAIL', linkedObjectRecordId: 'p-1', linkedObjectName: 'person' },
      created.first
    )
  end

  test 'falls back to a placeholder when the subject is nil' do
    created = []
    mail = FakeMail.new(42, nil, 'person@example.test')

    run_job(mail: mail, create: ->(payload) { created << payload }) { TwentyMailSyncJob.perform_now(42) }

    assert_equal '(no subject)', created.first[:name]
  end

  test 'returns cleanly when no contact matches' do
    run_job(person: ->(_email) {}, find: NEVER, create: NEVER) { TwentyMailSyncJob.perform_now(42) }
  end

  test 'skips a blank correspondent email' do
    run_job(mail: FakeMail.new(42, 'Test subject', '   '), person: NEVER, find: NEVER, create: NEVER) do
      TwentyMailSyncJob.perform_now(42)
    end
  end

  test 'skips a nil correspondent email' do
    run_job(mail: FakeMail.new(42, 'Test subject', nil), person: NEVER, find: NEVER, create: NEVER) do
      TwentyMailSyncJob.perform_now(42)
    end
  end

  test 'discards the job when the mail is missing' do
    missing = ->(_id) { raise ActiveRecord::RecordNotFound }

    Mail.stub(:find, missing) do
      assert_no_enqueued_jobs { TwentyMailSyncJob.perform_now(42) }
    end
  end

  test 're-running does not create a second activity' do
    created = []
    store = nil
    create = lambda do |payload|
      created << payload
      store = { 'id' => payload[:id] }
    end

    run_job(find: ->(_id) { store }, create: create) do
      TwentyMailSyncJob.perform_now(42)
      TwentyMailSyncJob.perform_now(42)
    end

    assert_equal 1, created.size
  end

  test 'does not create when the activity already exists' do
    run_job(find: ->(id) { { 'id' => id } }, create: NEVER) { TwentyMailSyncJob.perform_now(42) }
  end

  test 'treats a failed create as success when the activity now exists' do
    lookups = 0
    find = lambda do |id|
      lookups += 1
      lookups == 1 ? nil : { 'id' => id }
    end
    create = ->(_payload) { raise TwentyClient::Error, 'Twenty POST /rest/timelineActivities failed (500)' }

    run_job(find: find, create: create) { TwentyMailSyncJob.new.perform(42) }

    assert_equal 2, lookups
  end

  test 're-raises a failed create when the activity does not exist' do
    create = ->(_payload) { raise TwentyClient::Error, 'Twenty POST /rest/timelineActivities failed (500)' }

    run_job(create: create) do
      assert_raises(TwentyClient::Error) { TwentyMailSyncJob.new.perform(42) }
    end
  end

  test 'retries on a Twenty error during contact lookup' do
    person = ->(_email) { raise TwentyClient::Error, 'Twenty GET /rest/people failed (500)' }

    run_job(person: person, find: NEVER, create: NEVER) do
      assert_enqueued_with(job: TwentyMailSyncJob, args: [42], queue: 'integrations') do
        TwentyMailSyncJob.perform_now(42)
      end
    end
  end
end
