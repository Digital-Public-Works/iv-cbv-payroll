class Api::LoadTestSessionsController < ApplicationController
  skip_forgery_protection

  # Only allow in development/test environments
  before_action :ensure_dev_environment

  def create
    client_agency_id = params[:client_agency_id] || "sandbox"
    scenario = params[:scenario] || "synced"

    # Validate client_agency_id
    unless Rails.application.config.client_agencies.client_agency_ids.include?(client_agency_id)
      return render json: { error: "Invalid client_agency_id" }, status: :unprocessable_entity
    end

    # Create test data based on scenario
    cbv_flow, account_id = case scenario
                           when "synced"
                             create_synced_flow(client_agency_id)
                           when "pending"
                             create_pending_flow(client_agency_id)
                           when "failed"
                             create_failed_flow(client_agency_id)
                           else
                             return render json: { error: "Invalid scenario: #{scenario}" }, status: :unprocessable_entity
                           end

    # Set session using Rails' session mechanism (Rails will encrypt the cookie)
    session[:cbv_flow_id] = cbv_flow.id

    render json: {
      success: true,
      cbv_flow_id: cbv_flow.id,
      account_id: account_id,
      client_agency_id: client_agency_id,
      scenario: scenario,
      message: "Session created. Cookie will be set in Set-Cookie header."
    }, status: :created
  end

  private

  def ensure_dev_environment
    unless Rails.env.development? || Rails.env.test?
      render json: { error: "This endpoint is only available in development/test" }, status: :forbidden
    end
  end

  def create_synced_flow(client_agency_id)
    cbv_applicant = CbvApplicant.create!(client_agency_id: client_agency_id)
    cbv_flow = CbvFlow.create!(
      client_agency_id: client_agency_id,
      cbv_applicant: cbv_applicant
    )

    # Create fully synced payroll account
    account_id = "test_#{SecureRandom.hex(8)}"
    payroll_account = PayrollAccount::Argyle.create!(
      cbv_flow: cbv_flow,
      aggregator_account_id: account_id,
      supported_jobs: %w[income paystubs employment identity],
      synchronization_status: :succeeded
    )

    # Create successful webhook events
    [
      { event_name: "paystubs.fully_synced", event_outcome: "success" },
      { event_name: "employment.added", event_outcome: "success" },
      { event_name: "income.added", event_outcome: "success" },
      { event_name: "identity.added", event_outcome: "success" }
    ].each do |event|
      WebhookEvent.create!(
        payroll_account: payroll_account,
        event_name: event[:event_name],
        event_outcome: event[:event_outcome]
      )
    end

    [ cbv_flow, account_id ]
  end

  def create_pending_flow(client_agency_id)
    cbv_applicant = CbvApplicant.create!(client_agency_id: client_agency_id)
    cbv_flow = CbvFlow.create!(
      client_agency_id: client_agency_id,
      cbv_applicant: cbv_applicant
    )

    # Create pending payroll account
    account_id = "test_#{SecureRandom.hex(8)}"
    PayrollAccount::Argyle.create!(
      cbv_flow: cbv_flow,
      aggregator_account_id: account_id,
      supported_jobs: %w[income paystubs employment identity],
      synchronization_status: :in_progress
    )

    [ cbv_flow, account_id ]
  end

  def create_failed_flow(client_agency_id)
    cbv_applicant = CbvApplicant.create!(client_agency_id: client_agency_id)
    cbv_flow = CbvFlow.create!(
      client_agency_id: client_agency_id,
      cbv_applicant: cbv_applicant
    )

    # Create failed payroll account
    account_id = "test_#{SecureRandom.hex(8)}"
    payroll_account = PayrollAccount::Argyle.create!(
      cbv_flow: cbv_flow,
      aggregator_account_id: account_id,
      supported_jobs: %w[income paystubs employment identity],
      synchronization_status: :failed
    )

    # Create failed webhook events
    WebhookEvent.create!(
      payroll_account: payroll_account,
      event_name: "paystubs.failed",
      event_outcome: "error"
    )

    [ cbv_flow, account_id ]
  end
end
