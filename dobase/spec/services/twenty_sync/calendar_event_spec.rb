# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TwentySync::CalendarEvent do
  describe '.upsert' do
    let(:user) { instance_double(User) }
    let(:starts_at) { Time.utc(2026, 8, 3, 14, 30, 0) }
    let(:event) do
      {
        uid: 'event-uid-123',
        title: 'Quarterly Planning',
        description: 'Discuss roadmap priorities',
        starts_at: starts_at,
        ends_at: starts_at + 3600,
        attendee_emails: ['alice@example.com', 'bob@example.com']
      }
    end
    let(:expected_payload) do
      {
        title: 'Quarterly Planning',
        body: 'Discuss roadmap priorities',
        status: 'TODO',
        dueAt: '2026-08-03T14:30:00Z',
        TwentyClient::TASK_UID_FIELD.to_sym => 'event-uid-123'
      }
    end

    it 'creates a new task when no existing task matches the UID' do
      allow(TwentyClient).to receive(:find_task_by_uid).with('event-uid-123').and_return(nil)
      allow(TwentyClient).to receive(:find_person_by_email).and_return(nil)
      allow(TwentyClient).to receive(:create_task).with(expected_payload).and_return({ 'id' => 'task-1' })
      allow(TwentyClient).to receive(:update_task)
      allow(TwentyClient).to receive(:task_targets).and_return([])
      allow(TwentyClient).to receive(:create_task_target)

      TwentySync::CalendarEvent.upsert(user, event)

      expect(TwentyClient).to have_received(:create_task).with(expected_payload)
      expect(TwentyClient).not_to have_received(:update_task)
    end

    it 'updates the existing task when a task with the UID exists' do
      allow(TwentyClient).to receive(:find_task_by_uid).with('event-uid-123').and_return({ 'id' => 'task-1' })
      allow(TwentyClient).to receive(:find_person_by_email).and_return(nil)
      allow(TwentyClient).to receive(:update_task).with('task-1', expected_payload).and_return({ 'id' => 'task-1' })
      allow(TwentyClient).to receive(:create_task)
      allow(TwentyClient).to receive(:task_targets).and_return([])
      allow(TwentyClient).to receive(:create_task_target)

      TwentySync::CalendarEvent.upsert(user, event)

      expect(TwentyClient).to have_received(:update_task).with('task-1', expected_payload)
      expect(TwentyClient).not_to have_received(:create_task)
    end

    it 'links the task to the contact when an attendee email matches a Twenty person' do
      allow(TwentyClient).to receive(:find_task_by_uid).and_return(nil)
      allow(TwentyClient).to receive(:create_task).and_return({ 'id' => 'task-9' })
      allow(TwentyClient).to receive(:find_person_by_email).with('alice@example.com').and_return(nil)
      allow(TwentyClient).to receive(:find_person_by_email).with('bob@example.com').and_return({ 'id' => 'person-5' })
      allow(TwentyClient).to receive(:task_targets).with('task-9').and_return([])
      allow(TwentyClient).to receive(:create_task_target)

      TwentySync::CalendarEvent.upsert(user, event)

      expect(TwentyClient).to have_received(:create_task_target).with('task-9', 'person-5')
    end

    it 'still creates the task but does not link when no attendee matches a contact' do
      allow(TwentyClient).to receive(:find_task_by_uid).and_return(nil)
      allow(TwentyClient).to receive(:create_task).and_return({ 'id' => 'task-9' })
      allow(TwentyClient).to receive(:find_person_by_email).and_return(nil)
      allow(TwentyClient).to receive(:task_targets).and_return([])
      allow(TwentyClient).to receive(:create_task_target)

      TwentySync::CalendarEvent.upsert(user, event)

      expect(TwentyClient).to have_received(:create_task).once
      expect(TwentyClient).not_to have_received(:create_task_target)
    end
  end
end
