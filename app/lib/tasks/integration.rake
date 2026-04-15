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

    # 2. Create a test user
    puts "Ensuring test user exists..."
    user = User.find_or_initialize_by(email: "test@integration.local")
    if user.new_record?
      user.client_agency_id = "integration_test"
      user.save!
      puts "  Created user: test@integration.local"
    else
      puts "  User already exists: test@integration.local"
    end
    puts

    puts "=== Setup Complete ==="
    puts
    puts "Next steps:"
    puts "  1. Make sure Docker services are running:"
    puts "     docker compose -f docker-compose.integration.yml up -d"
    puts "  2. Start the Rails server:"
    puts "     bin/rails server"
    puts "  3. Restart the Rails server (so the new route constraint is loaded)"
    puts "  4. Go to http://localhost:3000/cbv/links/integration_test"
    puts "     (generic link — no login required, goes straight to CBV flow)"
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

    user = User.find_by(email: "test@integration.local")
    if user
      user.destroy!
      puts "  Removed test user"
    else
      puts "  No test user found"
    end

    ClientAgencyConfig.reset!
    puts "=== Teardown Complete ==="
  end
end
