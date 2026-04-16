namespace :integration do
  desc "Set up the integration_test partner for local e2e testing against Docker services"
  task setup: :environment do
    puts "=== Integration Test Setup ==="
    puts

    # 1. Load and apply the partner config
    puts "Applying integration_test partner config..."
    yaml_path = Rails.root.join("..", "docs", "app", "integration-test-partner.yml").to_s

    loader = PartnerConfigLoader.new(yaml_path)
    loader.load!
    loader.validate!

    unless loader.valid?
      puts "Validation errors:"
      loader.errors.each { |e| puts "  - #{e}" }
      abort "Cannot apply invalid config."
    end

    if loader.warnings.any?
      puts "Warnings:"
      loader.warnings.each { |w| puts "  - #{w}" }
    end

    changes = loader.apply!
    puts "  Config: #{changes[:config]}"
    puts "  Transmission configs: #{changes[:transmission_configs][:created]} created, #{changes[:transmission_configs][:updated]} updated, #{changes[:transmission_configs][:deleted]} deleted"
    puts "  Application attributes: #{changes[:application_attributes][:created]} created, #{changes[:application_attributes][:updated]} updated, #{changes[:application_attributes][:deleted]} deleted"
    puts "  Translations: #{changes[:translations][:created]} created, #{changes[:translations][:updated]} updated, #{changes[:translations][:deleted]} deleted"
    puts

    # 2. Create a service account user with an API access token
    puts "Ensuring service account user exists..."
    user = User.find_or_create_by!(
      email: "ffs-eng+integration_test@digitalpublicworks.org",
      client_agency_id: "integration_test"
    )
    user.update!(is_service_account: true)

    access_token = user.api_access_tokens.first || user.api_access_tokens.create!
    puts "  Service account: #{user.email}"
    puts "  API access token: #{access_token.access_token}"
    puts

    puts "=== Setup Complete ==="
    puts
    puts "Next steps:"
    puts "  1. Make sure Docker services are running:"
    puts "     docker compose -f docker-compose.integration.yml up -d"
    puts "  2. Start the Rails server:"
    puts "     bin/rails server"
    puts "  3. Create a CBV invitation via the API:"
    puts
    puts "     curl -X POST http://localhost:3000/api/v1/invitations \\"
    puts "       -H 'Authorization: Bearer #{access_token.access_token}' \\"
    puts "       -H 'Content-Type: application/json' \\"
    puts "       -d '{\"language\":\"en\",\"agency_partner_metadata\":{\"case_number\":\"ABC1234\",\"first_name\":\"Jane\",\"last_name\":\"Doe\"}}'"
    puts
    puts "     The response will include a `tokenized_url` — open that in your browser."
  end

  desc "Tear down the integration_test partner"
  task teardown: :environment do
    puts "=== Integration Test Teardown ==="

    pc = PartnerConfig.find_by(partner_id: "integration_test")
    if pc
      pc.destroy!
      puts "  Removed integration_test partner config"
    else
      puts "  No integration_test partner found"
    end

    user = User.find_by(email: "ffs-eng+integration_test@digitalpublicworks.org")
    if user
      user.destroy!
      puts "  Removed service account user"
    else
      puts "  No service account user found"
    end

    ClientAgencyConfig.reset!
    puts "=== Teardown Complete ==="
  end
end
