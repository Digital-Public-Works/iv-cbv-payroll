class PayrollAccount < ApplicationRecord
  include Discard::Model
  default_scope -> { kept }

  def self.sti_name
    # "PayrollAccount::Pinwheel" => "pinwheel"
    name.demodulize.underscore
  end

  def self.sti_class_for(type_name)
    # "pinwheel" => PayrollAccount::Pinwheel
    PayrollAccount.const_get(type_name.capitalize)
  end

  belongs_to :cbv_flow
  has_many :webhook_events

  # sync status, does not impact data quality
  enum :synchronization_status, {
    unknown: "unknown",              # defines the method: sync_unknown?
    in_progress: "in_progress",      # defines the method: sync_in_progress?
    succeeded: "succeeded",          # defines the method: sync_succeeded?
    failed: "failed"                 # defines the method: sync_failed?
  }, prefix: "sync"

  # status of the report itself, determined by UsefulReportValidator
  enum :report_status, {
    unknown: "unknown",              # defines the method: report_unknown?
    useful: "useful",                # defines the method: report_useful?
    not_useful: "not_useful"         # defines the method: report_not_useful?
  }, prefix: "report"

  before_save :mark_report_not_useful_when_sync_failed

  # sync finished and we don't know for sure it is not useful
  def presumed_usable?
    sync_succeeded? && !report_not_useful?
  end

  # The sync finished and the report is known to be usable.
  def usable?
    sync_succeeded? && report_useful?
  end

  # Returns whether we have received all expected webhooks for the sync
  # process, regardless of whether any of them are errors.
  #
  # To determine whether the sync was ultimately successful, use the value of
  # the `synchronization_status` column (via `sync_succeeded?`).
  def has_fully_synced?
    raise NotImplementedError
  end

  # Returns whether the job was successful.
  def job_succeeded?(job)
    raise NotImplementedError
  end

  # Returns the status of the job. Valid return values are:
  #   :unsupported - The job is not supported for this account.
  #   :succeeded   - The job completed successfully.
  #   :failed      - The job completed with an error.
  #   :in_progress - The job has not yet completed.
  def job_status(job)
    raise NotImplementedError
  end

  # Returns whether the minimal set of webhooks succeeded.
  #
  # This is an early way to bail out of even fetching the report if we know the
  # data is not going to be present.
  def necessary_jobs_succeeded?
    raise NotImplementedError
  end

  # Redact data associated with this PayrollAccount when triggered by the
  # DataRetentionService.
  def redact!
    raise NotImplementedError
  end

  private

  # failed sync is not a userful report
  def mark_report_not_useful_when_sync_failed
    self.report_status = :not_useful if sync_failed?
  end

  def find_webhook_event(event_name, event_outcome = nil)
    webhook_events.find do |webhook_event|
      webhook_event.event_name == event_name &&
        (event_outcome.nil? || webhook_event.event_outcome == event_outcome.to_s)
    end
  end
end
