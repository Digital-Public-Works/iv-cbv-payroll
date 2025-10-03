namespace :load_test do
  desc "Generate test sessions with synced payroll accounts for load testing"
  task :bake_cookies, [:count, :client_agency_id] => :environment do |t, args|
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

      # Create a fully synced Argyle PayrollAccount
      account_id = "test_account_#{i}"
      payroll_account = PayrollAccount::Argyle.create!(
        cbv_flow: cbv_flow,
        aggregator_account_id: account_id,
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

      # Generate encrypted session cookie using the same encryption Rails uses
      # Use Rails' actual key_generator to ensure consistent iterations
      secret = Rails.application.key_generator.generate_key("authenticated encrypted cookie", ActiveSupport::MessageEncryptor.key_len("aes-256-gcm"))
      sign_secret = Rails.application.key_generator.generate_key("signed encrypted cookie", 64)

      encryptor = ActiveSupport::MessageEncryptor.new(secret, sign_secret, cipher: "aes-256-gcm", serializer: Marshal)

      # Encrypt the session data
      session_data = { "cbv_flow_id" => cbv_flow.id }
      cookie_value = encryptor.encrypt_and_sign(session_data)

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

  desc "Generate tokenized invitation links for load testing"
  task :bake_invitations, [:count, :client_agency_id] => :environment do |t, args|
    count = args[:count]&.to_i || 100
    client_agency_id = args[:client_agency_id] || "sandbox"

    unless Rails.application.config.client_agencies.client_agency_ids.include?(client_agency_id)
      puts "Error: Invalid client_agency_id '#{client_agency_id}'"
      puts "Valid options: #{Rails.application.config.client_agencies.client_agency_ids.join(', ')}"
      exit 1
    end

    # Create a test user for the invitations
    user = User.find_or_create_by!(
      client_agency_id: "az_des"
    )

    puts "Creating #{count} tokenized invitations for client_agency: #{client_agency_id}"
    puts "=" * 60

    tokens = []
    urls = []

    count.times do |i|
      # Create invitation params
      cbv_applicant_params = {
        first_name: "Load",
        last_name: "Test#{i}",
        snap_application_date: Date.today
      }

      invitation_params = {
        client_agency_id: client_agency_id,
        email_address: "loadtest#{i}@example.com",
        language: "en",
        user: user,
        cbv_applicant_attributes: {
          client_agency_id: client_agency_id,
          **cbv_applicant_params
        }
      }

      # Create the invitation without sending email
      invitation = CbvFlowInvitation.create!(invitation_params)

      # Create a synced CbvFlow from the invitation
      cbv_flow = CbvFlow.create_from_invitation(invitation)

      # Create a fully synced Argyle PayrollAccount
      account_id = "test_account_#{i}"
      payroll_account = PayrollAccount::Argyle.create!(
        cbv_flow: cbv_flow,
        aggregator_account_id: account_id,
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

      tokens << invitation.auth_token
      urls << invitation.to_url

      # Output progress every 10 invitations
      if (i + 1) % 10 == 0
        puts "Created #{i + 1}/#{count} tokenized invitations..."
      end
    end

    puts "=" * 60
    puts "✓ Successfully created #{count} tokenized invitations"
    puts ""
    puts "Tokens for load testing:"
    puts "export TOKENS='#{tokens.join(',')}'"
    puts ""
    puts "First URL example:"
    puts urls.first
  end

  desc "Convert invitation tokens to session cookies for load testing"
  task :tokens_to_cookies, [:tokens] => :environment do |t, args|
    unless args[:tokens].present?
      puts "Error: No tokens provided"
      puts "Usage: bin/rails 'load_test:tokens_to_cookies[token1,token2,token3]'"
      exit 1
    end

    tokens = args[:tokens].split(",")
    cookies = []

    puts "Converting #{tokens.count} tokens to session cookies..."
    puts "=" * 60

    tokens.each_with_index do |token, i|
      invitation = CbvFlowInvitation.find_by(auth_token: token.strip)

      unless invitation
        puts "Warning: Token #{i + 1} not found, skipping..."
        next
      end

      if invitation.expired?
        puts "Warning: Token #{i + 1} has expired, skipping..."
        next
      end

      # Get or create the CbvFlow for this invitation
      cbv_flow = invitation.cbv_flows.first || CbvFlow.create_from_invitation(invitation)

      # Generate encrypted session cookie using the same encryption Rails uses
      # Use Rails' actual key_generator to ensure consistent iterations
      secret = Rails.application.key_generator.generate_key("authenticated encrypted cookie", ActiveSupport::MessageEncryptor.key_len("aes-256-gcm"))
      sign_secret = Rails.application.key_generator.generate_key("signed encrypted cookie", 64)

      encryptor = ActiveSupport::MessageEncryptor.new(secret, sign_secret, cipher: "aes-256-gcm", serializer: Marshal)

      session_data = { "cbv_flow_id" => cbv_flow.id }
      cookie_value = encryptor.encrypt_and_sign(session_data)

      cookies << cookie_value

      if (i + 1) % 10 == 0
        puts "Converted #{i + 1}/#{tokens.count} tokens..."
      end
    end

    puts "=" * 60
    puts "✓ Successfully converted #{cookies.count} tokens to cookies"
    puts ""
    puts "Export cookies for k6:"
    puts "export COOKIES='#{cookies.join(",")}'"
  end

  desc "Clean up test sessions created by seed_sessions"
  task :cleanup_cookies, [:client_agency_id] => :environment do |t, args|
    client_agency_id = args[:client_agency_id] || "sandbox"

    # Find flows without confirmation codes (incomplete) from the test agency
    test_flows = CbvFlow.incomplete.where(client_agency_id: client_agency_id)

    puts "Found #{test_flows.count} incomplete test sessions for #{client_agency_id}"
    print "Delete these sessions? (y/n): "

    response = STDIN.gets.chomp.downcase
    if response == "y"
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
