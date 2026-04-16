require "rspec/core/rake_task"

# No-op event logger used by rake tasks to avoid attempting a real SQS
# connection during local CLI invocations.
class NoopEventLogger
  def track(*) = nil
end

namespace :integration do
  # Spec files tagged `integration: true`. Add new integration specs here so
  # they get picked up by `integration:rspec:*` convenience tasks.
  INTEGRATION_SPECS = {
    webhook: "spec/services/transmitters/webhook_transmitter_integration_spec.rb",
    sftp:    "spec/services/transmitters/sftp_transmitter_integration_spec.rb"
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

      # 3. Generate a ready-to-use invitation with a long expiration (just
      # under the 1-year cap) so it remains usable across dev sessions.
      puts "Creating a convenience invitation..."
      invitation_params = {
        language: "en",
        expiration_days: 364,
        client_agency_id: "integration_test",
        email_address: user.email,
        cbv_applicant_attributes: {
          client_agency_id: "integration_test",
          case_number: "ABC1234",
          first_name: "Jane",
          last_name: "Doe"
        }
      }
      invitation = CbvInvitationService.new(NoopEventLogger.new)
        .invite(invitation_params, user, delivery_method: nil)

      if invitation.persisted?
        puts "  Tokenized URL: #{invitation.to_url}"
        puts "  Expires: #{invitation.expires_at_local}"
      else
        puts "  Failed to create invitation: #{invitation.errors.full_messages.join(', ')}"
      end
      puts

      puts "=== Setup Complete ==="
      puts
      puts "Open the Tokenized URL above in your browser to start the CBV flow."
    end

    desc "Remove the integration_test partner and service account"
    task teardown: :environment do
      puts "=== Integration Test Partner Teardown ==="

      # Destroy flows, invitations, and applicants for the integration_test
      # agency first so FK constraints don't block the user/partner deletion.
      # Order matters: webhook_events -> payroll_accounts -> cbv_flows ->
      # cbv_flow_invitations -> cbv_applicants.
      flow_ids = CbvFlow.where(client_agency_id: "integration_test").pluck(:id)
      payroll_account_ids = PayrollAccount.where(cbv_flow_id: flow_ids).pluck(:id)
      WebhookEvent.where(payroll_account_id: payroll_account_ids).delete_all

      flows_count = CbvFlow.where(client_agency_id: "integration_test").destroy_all.size
      invitations_count = CbvFlowInvitation.where(client_agency_id: "integration_test").destroy_all.size
      applicants_count = CbvApplicant.where(client_agency_id: "integration_test").destroy_all.size
      if (flows_count + invitations_count + applicants_count) > 0
        puts "  Removed #{flows_count} flow(s), #{invitations_count} invitation(s), #{applicants_count} applicant(s)"
      end

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
    RSpec::Core::RakeTask.new(:all) do |t|
      t.pattern = INTEGRATION_SPECS.values
      t.rspec_opts = "--tag integration"
    end

    INTEGRATION_SPECS.each do |name, path|
      desc "Run #{name} transmitter integration spec"
      RSpec::Core::RakeTask.new(name) do |t|
        t.pattern = path
        t.rspec_opts = "--tag integration"
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
end
