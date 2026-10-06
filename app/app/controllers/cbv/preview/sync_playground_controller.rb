# Dev-only playground for manually testing the /synchronizations page (e.g. with a
# screen reader). It renders the real sync partials and polls
# the real Cbv::SynchronizationsController#update; buttons on the same page insert
# the webhook events Argyle would send.
class Cbv::Preview::SyncPlaygroundController < ApplicationController
  layout "preview"

  JOBS = %w[accounts identity income employment paystubs].freeze

  # Button id => [event name, outcome]. Argyle completes jobs in pairs; see
  # Aggregators::Webhooks::Argyle::SUBSCRIBED_WEBHOOK_EVENTS.
  EVENTS = {
    "identities.added" => [ "identities.added", "success" ],
    "paystubs.fully_synced" => [ "paystubs.fully_synced", "success" ],
    "paystubs_failed" => [ "paystubs.fully_synced", "error" ]
  }.freeze

  before_action :ensure_non_production_environment
  before_action :set_payroll_account, only: %i[webhook poll]

  # Every load (or reload) starts a fresh sync with everything loading.
  def show
    start_sync
  end

  def webhook
    event_name, event_outcome = EVENTS[params[:event]]
    return head :unprocessable_content unless event_name && @payroll_account

    @payroll_account.webhook_events.create!(event_name: event_name, event_outcome: event_outcome)
    render turbo_stream: helpers.safe_join([
      turbo_stream.update(
        "sync-playground-log",
        "Sent #{event_name} (#{event_outcome}) at #{Time.current.strftime('%H:%M:%S')}. " \
        "The page picks it up on its next poll (within 2s)."
      ),
      turbo_stream.replace(
        "sync-playground-statuses",
        partial: "cbv/preview/sync_playground/statuses",
        locals: { payroll_account: @payroll_account.reload }
      )
    ])
  end

  # Used instead of the real endpoint when "redirect when complete" is unchecked:
  # same morph as the real poll, but never redirects.
  def poll
    render turbo_stream: turbo_stream.replace(:synchronization, partial: "cbv/synchronizations/status", method: :morph)
  end

  private

  def current_agency
    @current_agency ||= agency_config["sandbox"]
  end

  def ensure_non_production_environment
    unless is_not_production?
      render plain: "Preview routes are only available in non-production environments", status: :forbidden
    end
  end

  def set_payroll_account
    @cbv_flow = CbvFlow.find_by(id: session[:cbv_flow_id])
    @payroll_account = @cbv_flow && PayrollAccount::Argyle.find_by(
      cbv_flow: @cbv_flow,
      aggregator_account_id: session[:sync_playground_account_id]
    )
  end

  # A fresh sandbox flow + Argyle account with only `accounts.connected`, so every
  # indicator starts as loading. The flow goes in the session so the real
  # SynchronizationsController#update can find it.
  def start_sync
    @cbv_flow = CbvFlow.create_without_invitation("sandbox", nil)
    @payroll_account = PayrollAccount::Argyle.create!(
      cbv_flow: @cbv_flow,
      aggregator_account_id: "sync-playground-#{SecureRandom.hex(4)}",
      supported_jobs: JOBS
    )
    @payroll_account.webhook_events.create!(event_name: "accounts.connected", event_outcome: "success")

    session[:cbv_flow_id] = @cbv_flow.id
    session[:sync_playground_account_id] = @payroll_account.aggregator_account_id
  end
end
