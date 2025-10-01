namespace :load_test do
  desc "Generate test sessions with synced payroll accounts for load testing"
  task :seed_sessions, [:count, :client_agency_id] => :environment do |t, args|
    count = args[:count]&.to_i || 100
    client_agency_id = args[:client_agency_id] || "sandbox"

    unless Rails.application.config.client_agencies.client_agency_ids.include?(client_agency_id)
      puts "Error: Invalid client_agency_id '#{client_agency_id}'"
      puts "Valid options: #{Rails.application.config.client_agencies.client_agency_ids.join(', ')}"
      exit 1
    end

    puts "Creating #{count} test sessions for client_agency: #{client_agency_id}"
    puts "=" * 60

    cookies = []

    count.times do |i|
      # Create a CbvApplicant
      cbv_applicant = CbvApplicant.create!(
        client_agency_id: client_agency_id
      )

      # Create a CbvFlow
      cbv_flow = CbvFlow.create!(
        client_agency_id: client_agency_id,
        cbv_applicant: cbv_applicant
      )

      # Create a fully synced Pinwheel PayrollAccount
      account_id = "test_account_#{i}"
      payroll_account = PayrollAccount::Pinwheel.create!(
        cbv_flow: cbv_flow,
        pinwheel_account_id: account_id,
        supported_jobs: %w[income paystubs employment identity],
        synchronization_status: :succeeded
      )

      # Create webhook events to simulate successful sync
      webhook_events = [
        { event_name: "paystubs.fully_synced", event_outcome: "success" },
        { event_name: "employment.added", event_outcome: "success" },
        { event_name: "income.added", event_outcome: "success" },
        { event_name: "identity.added", event_outcome: "success" }
      ]

      webhook_events.each do |event|
        WebhookEvent.create!(
          payroll_account: payroll_account,
          event_name: event[:event_name],
          event_outcome: event[:event_outcome]
        )
      end

      # Generate a session cookie
      session_data = { cbv_flow_id: cbv_flow.id }
      cookie_value = Rails.application.message_verifier(:cookie_store)
        .generate(session_data, purpose: "cookie.cbv_flow_id")

      cookies << cookie_value

      # Output progress every 10 flows
      if (i + 1) % 10 == 0
        puts "Created #{i + 1}/#{count} test sessions..."
      end
    end

    puts "=" * 60
    puts "✓ Successfully created #{count} test sessions"
    puts ""
    puts "Export cookies for k6:"
    puts "export COOKIES='#{cookies.join(',')}'"
  end

  desc "Clean up test sessions created by seed_sessions"
  task :cleanup_sessions, [:client_agency_id] => :environment do |t, args|
    client_agency_id = args[:client_agency_id] || "sandbox"

    # Find flows without confirmation codes (incomplete) from the test agency
    test_flows = CbvFlow.incomplete.where(client_agency_id: client_agency_id)

    puts "Found #{test_flows.count} incomplete test sessions for #{client_agency_id}"
    print "Delete these sessions? (y/n): "

    response = STDIN.gets.chomp.downcase
    if response == 'y'
      count = test_flows.count

      # Delete in proper order to avoid foreign key constraint violations
      test_flows.each do |flow|
        flow.payroll_accounts.each do |account|
          # Use destroy_all to properly delete webhook events
          account.webhook_events.destroy_all
        end
        flow.destroy
      end

      puts "✓ Deleted #{count} test sessions"
    else
      puts "Cancelled"
    end
  end
end
