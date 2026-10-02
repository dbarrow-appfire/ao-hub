# frozen_string_literal: true

require 'digest'
require 'json'

module TwentySync
  class CalendarEvent
    # Creates or updates one Twenty task per CalDAV occurrence in [from, to),
    # tracked by TwentyCalendarSync rows, and links each task to the Twenty
    # people whose email matches an attendee or the organizer.
    #
    # Jira: DEV-107

    class MissingTaskId < StandardError; end

    # Returns the occurrence keys that are still live in Dobase, for prune.
    # person_cache is shared across a sync run so each email is looked up once.
    def self.upsert(user, event, from:, to:, person_cache: {})
      occurrences = EventOccurrences.from_calendar_data(
        event.calendar_data, from: from, to: to, exclude_email: user.email
      )
      live = occurrences.reject(&:cancelled)
      live.each { |occurrence| sync_occurrence(user, event, occurrence, person_cache) }
      live.map(&:key)
    rescue EventOccurrences::ParseError => e
      # Keep what is already synced for this resource rather than letting prune delete it.
      Rails.logger.warn(
        "TwentySync::CalendarEvent skipped event user_id=#{user.id} etag=#{event.etag}: #{e.message}"
      )
      TwentyCalendarSync.where(user: user, event_url: event.url).pluck(:occurrence_key)
    end

    # Deletes the Twenty task of every in-window row whose occurrence was not
    # seen in this run. Rows before from are left alone: they left the window
    # by passing, not by being removed.
    def self.prune(user, seen_keys, from:, to:)
      TwentyCalendarSync.where(user: user).in_window(from, to)
                        .where.not(occurrence_key: seen_keys).find_each do |row|
        delete_task(row.twenty_task_id) if row.twenty_task_id
        row.destroy!
      end
    end

    def self.sync_occurrence(user, event, occurrence, person_cache)
      digest = content_hash(occurrence)
      row = TwentyCalendarSync.create_or_find_by!(user: user, occurrence_key: occurrence.key) do |new_row|
        new_row.event_uid = occurrence.uid
        new_row.starts_at = occurrence.starts_at
        new_row.event_url = event.url
      end
      return if row.twenty_task_id && row.content_hash == digest

      row.with_lock do
        # with_lock reloads, so re-check in case a concurrent run got here first.
        next if row.twenty_task_id && row.content_hash == digest

        task_id =
          if row.twenty_task_id.nil?
            create_task(occurrence, person_cache)
          else
            update_task(row.twenty_task_id, occurrence, person_cache)
          end
        row.update!(
          twenty_task_id: task_id, content_hash: digest, starts_at: occurrence.starts_at, event_url: event.url
        )
      end
    end

    def self.create_task(occurrence, person_cache)
      task_id = TwentyClient.create_task(task_payload(occurrence))
      raise MissingTaskId, 'Twenty POST /rest/tasks returned no task id' unless task_id

      person_ids(occurrence, person_cache).each { |person_id| TwentyClient.create_task_target(task_id, person_id) }
      task_id
    end

    # Recreates the task when it was deleted in Twenty.
    def self.update_task(task_id, occurrence, person_cache)
      begin
        TwentyClient.update_task(task_id, task_payload(occurrence))
      rescue TwentyClient::Error => e
        raise unless e.status == 404

        return create_task(occurrence, person_cache)
      end
      reconcile_targets(task_id, person_ids(occurrence, person_cache))
      task_id
    end

    # Only person targets are reconciled; links to other records are left alone.
    def self.reconcile_targets(task_id, wanted_person_ids)
      targets = TwentyClient.list_task_targets(task_id).select { |target| target['personId'] }
      targets.reject { |target| wanted_person_ids.include?(target['personId']) }
             .each { |target| TwentyClient.delete_task_target(target['id']) }
      linked = targets.map { |target| target['personId'] }
      (wanted_person_ids - linked).each { |person_id| TwentyClient.create_task_target(task_id, person_id) }
    end

    def self.delete_task(task_id)
      TwentyClient.delete_task(task_id)
    rescue TwentyClient::Error => e
      # Already gone in Twenty counts as deleted.
      raise unless e.status == 404
    end

    def self.person_ids(occurrence, person_cache)
      occurrence.emails.filter_map do |email|
        person_cache[email] = TwentyClient.find_person_by_email(email) unless person_cache.key?(email)
        person_cache[email]&.dig('id')
      end.uniq
    end

    def self.task_payload(occurrence)
      {
        title: occurrence.summary || '(No title)',
        dueAt: occurrence.starts_at.utc.iso8601,
        bodyV2: { markdown: task_body(occurrence) }
      }
    end

    def self.task_body(occurrence)
      starts_at = occurrence.starts_at.utc.iso8601
      ends_at = occurrence.ends_at.utc.iso8601
      lines = [occurrence.all_day ? "All day: #{starts_at} to #{ends_at}" : "When: #{starts_at} to #{ends_at}"]
      lines << "Location: #{occurrence.location}" if occurrence.location
      lines << '' << occurrence.description if occurrence.description
      lines.join("\n")
    end

    def self.content_hash(occurrence)
      Digest::SHA256.hexdigest(
        [
          occurrence.summary, occurrence.description, occurrence.location, occurrence.all_day,
          occurrence.starts_at.utc.iso8601, occurrence.ends_at.utc.iso8601, occurrence.emails.sort
        ].to_json
      )
    end

    private_class_method :sync_occurrence, :create_task, :update_task, :reconcile_targets, :delete_task,
                         :person_ids, :task_payload, :task_body, :content_hash
  end
end
