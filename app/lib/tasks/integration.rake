namespace :integration do
  # Spec files tagged `integration: true`. Add new integration specs here so
  # they get picked up by `integration:rspec:*` convenience tasks.
  INTEGRATION_SPECS = {
    webhook:      "spec/services/transmitters/webhook_transmitter_integration_spec.rb",
    sftp:         "spec/services/transmitters/sftp_transmitter_integration_spec.rb",
    encrypted_s3: "spec/services/transmitters/encrypted_s3_transmitter_integration_spec.rb",
    json:         "spec/services/transmitters/json_transmitter_integration_spec.rb"
  }.freeze

  COMPOSE_FILE = ENV.fetch("INTEGRATION_COMPOSE_FILE", "docker-compose.integration.yml").freeze

  namespace :partner do
    desc "Create the integration_test partner, service account, and API access token"
    task setup: :environment do
      puts "=== Integration Test Partner Setup ==="
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
      puts "     docker compose -f #{COMPOSE_FILE} up -d"
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

    desc "Remove the integration_test partner and service account"
    task teardown: :environment do
      puts "=== Integration Test Partner Teardown ==="

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

  namespace :rspec do
    desc "Run all integration specs (requires Docker services — see integration:docker:up)"
    task all: :environment do
      verify_docker_services_running!
      run_rspec(INTEGRATION_SPECS.values)
    end

    INTEGRATION_SPECS.each do |name, path|
      desc "Run #{name} transmitter integration spec"
      task name => :environment do
        verify_docker_services_running!
        run_rspec([ path ])
      end
    end
  end

  namespace :docker do
    desc "Start Docker services for integration tests"
    task :up do
      sh "docker compose -f #{COMPOSE_FILE} up -d"
    end

    desc "Stop Docker services for integration tests"
    task :down do
      sh "docker compose -f #{COMPOSE_FILE} down"
    end

    desc "Show Docker service status"
    task :ps do
      sh "docker compose -f #{COMPOSE_FILE} ps"
    end
  end

  def run_rspec(spec_paths)
    cmd = [ "bundle", "exec", "rspec", "--tag", "integration", *spec_paths ]
    puts "Running: #{cmd.join(' ')}"
    sh(*cmd)
  end

  def verify_docker_services_running!
    status = `docker compose -f #{COMPOSE_FILE} ps --status running --format '{{.Service}}' 2>/dev/null`.split("\n")
    required = %w[sftp minio webhook-api json-api]
    missing = required - status

    return if missing.empty?

    abort <<~MSG
      Docker services not running: #{missing.join(', ')}

      Start them with:
        bundle exec rake integration:docker:up

      Or check status with:
        bundle exec rake integration:docker:ps
    MSG
  end
end
