# frozen_string_literal: true

# Maps each synced CalDAV occurrence to the Twenty task created for it.
# occurrence_key is the event UID, or "UID|<RECURRENCE-ID as ISO8601 UTC>" for
# an occurrence of a recurring event.
#
# Jira: DEV-107
class CreateTwentyCalendarSyncs < ActiveRecord::Migration[8.0]
  def change
    create_table :twenty_calendar_syncs do |t|
      # The composite indexes below all lead with user_id, so no standalone index.
      t.references :user, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.string :event_uid, null: false
      t.string :occurrence_key, null: false
      t.datetime :starts_at, null: false
      t.string :event_url
      t.string :twenty_task_id
      t.string :content_hash

      t.timestamps
    end

    add_index :twenty_calendar_syncs, %i[user_id occurrence_key], unique: true
    add_index :twenty_calendar_syncs, %i[user_id starts_at]
    add_index :twenty_calendar_syncs, %i[user_id event_url]
  end
end
