# frozen_string_literal: true

# One row per CalDAV occurrence synced to Twenty. twenty_task_id and
# content_hash stay nil until Twenty has accepted the task.
#
# Jira: DEV-107
class TwentyCalendarSync < ApplicationRecord
  belongs_to :user

  # Uniqueness of [user_id, occurrence_key] is left to the unique index:
  # create_or_find_by! relies on ActiveRecord::RecordNotUnique, which a
  # uniqueness validation would pre-empt with RecordInvalid.
  validates :event_uid, :occurrence_key, :starts_at, presence: true

  # Half-open [from, to), matching the occurrence filter used for the CalDAV window.
  scope :in_window, ->(from, to) { where(starts_at: from...to) }
end
