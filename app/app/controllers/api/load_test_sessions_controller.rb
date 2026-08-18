class Api::LoadTestSessionsController < ApplicationController
  include NonProductionAccessible

  skip_forgery_protection

  # Only allow in non-production environments (development/test/demo)
  before_action :ensure_non_production_environment

  def create
    client_agency_id = params[:client_agency_id] || "sandbox"
    scenario = params[:scenario] || "synced"

    # Validate client_agency_id
    unless ClientAgencyConfig.client_agency_ids.include?(client_agency_id)
      return render json: { error: "Invalid client_agency_id" }, status: :unprocessable_content
    end

    # Create test data based on scenario
    cbv_flow, account_ids = case scenario
                            when "synced"
                              create_synced_flow(client_agency_id)
                            when "pending"
                              create_pending_flow(client_agency_id)
                            when "failed"
                              create_failed_flow(client_agency_id)
                            else
                              return render json: { error: "Invalid scenario: #{scenario}" }, status: :unprocessable_content
                            end

    # Set session using Rails' session mechanism (Rails will encrypt the cookie)
    session[:cbv_flow_id] = cbv_flow.id

    render json: {
      success: true,
      cbv_flow_id: cbv_flow.id,
      account_id: account_ids.first,
      account_ids: account_ids,
      fixture_user: params[:fixture_user],
      client_agency_id: client_agency_id,
      scenario: scenario,
      csrf_token: form_authenticity_token,
      message: "Session created. Cookie will be set in Set-Cookie header."
    }, status: :created
  end

  private

  # Account IDs to seed onto the flow. When a ?fixture_user= is given, use every
  # account in that fixture's request_accounts.json so multi-employer demo
  # fixtures (e.g. paystubs_some_images) create matching PayrollAccounts — the
  # mock service then returns each account's data. Falls back to Bob's single
  # hard-coded id so existing single-account load tests are unchanged.
  def argyle_account_ids
    fixture_user = params[:fixture_user].presence
    return [ argyle_account_id ] unless fixture_user

    accounts_path = Rails.root.join("spec", "support", "fixtures", "argyle", fixture_user, "request_accounts.json")
    if File.exist?(accounts_path)
      ids = Array(JSON.parse(File.read(accounts_path))["results"]).filter_map { |a| a["id"] }
      return ids if ids.any?
    end

    [ argyle_account_id ]
  end

  def argyle_account_id
    # hard coded to bob's id to match the mock api service
    "019571bc-2f60-3955-d972-dbadfe0913a8"
  end

  def ensure_non_production_environment
    unless is_not_production?
      render json: { error: "This endpoint is only available in non-production environments" }, status: :forbidden
    end
  end

  def create_synced_flow(client_agency_id)
    cbv_applicant = CbvApplicant.create!(client_agency_id: client_agency_id)
    cbv_flow = CbvFlow.create!(
      client_agency_id: client_agency_id,
      cbv_applicant: cbv_applicant,
      consented_to_authorized_use_at: Time.current
    )

    account_ids = argyle_account_ids

    account_ids.each do |account_id|
      # Create a fully synced payroll account per employer in the fixture.
      payroll_account = PayrollAccount::Argyle.create!(
        cbv_flow: cbv_flow,
        aggregator_account_id: account_id,
        supported_jobs: %w[accounts income paystubs employment identity],
        synchronization_status: :succeeded
      )

      # Create successful webhook events matching Argyle's actual event names
      # See: Aggregators::Webhooks::Argyle::SUBSCRIBED_WEBHOOK_EVENTS
      [
        { event_name: "accounts.connected", event_outcome: "success" },       # accounts job
        { event_name: "identities.added", event_outcome: "success" },        # identity + income jobs
        { event_name: "paystubs.fully_synced", event_outcome: "success" }    # paystubs + employment jobs
      ].each do |event|
        WebhookEvent.create!(
          payroll_account: payroll_account,
          event_name: event[:event_name],
          event_outcome: event[:event_outcome]
        )
      end
    end

    [ cbv_flow, account_ids ]
  end

  def create_pending_flow(client_agency_id)
    cbv_applicant = CbvApplicant.create!(client_agency_id: client_agency_id)
    cbv_flow = CbvFlow.create!(
      client_agency_id: client_agency_id,
      cbv_applicant: cbv_applicant,
      consented_to_authorized_use_at: Time.current
    )

    # Create pending payroll account
    payroll_account = PayrollAccount::Argyle.create!(
      cbv_flow: cbv_flow,
      aggregator_account_id: argyle_account_id,
      supported_jobs: %w[accounts income paystubs employment identity],
      synchronization_status: :in_progress
    )

    # Create initial webhook event (account connected, but sync still in progress)
    WebhookEvent.create!(
      payroll_account: payroll_account,
      event_name: "accounts.connected",
      event_outcome: "success"
    )

    [ cbv_flow, [ argyle_account_id ] ]
  end

  def create_failed_flow(client_agency_id)
    cbv_applicant = CbvApplicant.create!(client_agency_id: client_agency_id)
    cbv_flow = CbvFlow.create!(
      client_agency_id: client_agency_id,
      cbv_applicant: cbv_applicant,
      consented_to_authorized_use_at: Time.current
    )

    # Create failed payroll account
    payroll_account = PayrollAccount::Argyle.create!(
      cbv_flow: cbv_flow,
      aggregator_account_id: argyle_account_id,
      supported_jobs: %w[accounts income paystubs employment identity],
      synchronization_status: :failed
    )

    # Create failed webhook events - paystubs job failed
    [
      { event_name: "accounts.connected", event_outcome: "success" },
      { event_name: "paystubs.fully_synced", event_outcome: "error" }  # This marks paystubs/employment as failed
    ].each do |event|
      WebhookEvent.create!(
        payroll_account: payroll_account,
        event_name: event[:event_name],
        event_outcome: event[:event_outcome]
      )
    end

    [ cbv_flow, [ argyle_account_id ] ]
  end
end
