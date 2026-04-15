require "open3"

namespace :integration do
  desc "Set up the integration_test partner for local e2e testing against Docker services"
  task setup: :environment do
    puts "=== Integration Test Setup ==="
    puts

    # 1. Generate GPG keypair
    puts "Generating GPG keypair..."
    gpg_home = Rails.root.join("tmp", "integration-gpg").to_s
    FileUtils.rm_rf(gpg_home)
    FileUtils.mkdir_p(gpg_home)

    key_script = <<~SCRIPT
      %echo Generating integration test GPG key
      Key-Type: RSA
      Key-Length: 2048
      Name-Real: Integration Test
      Name-Email: integration@test.local
      Expire-Date: 0
      %no-protection
      %commit
    SCRIPT

    env = { "GNUPGHOME" => gpg_home }
    stdout, stderr, status = Open3.capture3(env, "gpg", "--batch", "--generate-key", stdin_data: key_script)
    abort "GPG key generation failed:\n#{stderr}" unless status.success?

    public_key, stderr, status = Open3.capture3(env, "gpg", "--armor", "--export", "integration@test.local")
    abort "GPG key export failed:\n#{stderr}" unless status.success? && public_key.present?

    key_path = Rails.root.join("tmp", "integration-gpg-public-key.asc")
    File.write(key_path, public_key)
    puts "  GPG public key written to #{key_path}"
    puts "  GPG home (with private key for decryption): #{gpg_home}"
    puts

    # 2. Load and apply the partner config
    puts "Applying integration_test partner config..."
    yaml_path = Rails.root.join("..", "docs", "app", "integration-test-partner.yml").to_s

    loader = PartnerConfigLoader.new(yaml_path)
    loader.load!

    # Inject the generated GPG public key
    loader.data[:transmission_methods].each do |tm|
      next unless tm[:method_type] == "encrypted_s3"
      tm[:configs]&.each do |config|
        config[:value] = public_key if config[:key] == "public_key"
      end
    end

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
    puts "  Transmission methods: #{changes[:transmission_methods][:created]} created, #{changes[:transmission_methods][:updated]} updated, #{changes[:transmission_methods][:deleted]} deleted"
    puts "  Application attributes: #{changes[:application_attributes][:created]} created, #{changes[:application_attributes][:updated]} updated, #{changes[:application_attributes][:deleted]} deleted"
    puts "  Translations: #{changes[:translations][:created]} created, #{changes[:translations][:updated]} updated, #{changes[:translations][:deleted]} deleted"
    puts

    # 3. Create a test user
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

  desc "Tear down the integration_test partner and clean up GPG keys"
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

    gpg_home = Rails.root.join("tmp", "integration-gpg")
    if File.exist?(gpg_home)
      FileUtils.rm_rf(gpg_home)
      puts "  Removed GPG keys from #{gpg_home}"
    end

    key_file = Rails.root.join("tmp", "integration-gpg-public-key.asc")
    File.delete(key_file) if File.exist?(key_file)

    ClientAgencyConfig.reset!
    puts "=== Teardown Complete ==="
  end
end
