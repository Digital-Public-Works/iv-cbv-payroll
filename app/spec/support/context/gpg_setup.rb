RSpec.shared_context "gpg_setup" do
  before(:all) do
    @original_gpg_home = ENV['GNUPGHOME']
    @gpg_home = Rails.root.join('tmp', 'gpghome').to_s
    ENV['GNUPGHOME'] = @gpg_home
    FileUtils.mkdir_p(@gpg_home)

    key_script = <<~SCRIPT
      %echo Generating a basic OpenPGP key
      Key-Type: RSA
      Key-Length: 2048
      Subkey-Type: RSA
      Subkey-Length: 2048
      Name-Real: Test MOVEit
      Name-Email: test@example.com
      Expire-Date: 0
      %no-protection
      %commit
      %echo done
    SCRIPT

    Open3.popen3("gpg", "--batch", "--generate-key") do |stdin, stdout, stderr, wait_thr|
      stdin.write(key_script)
      stdin.close_write

      wait_thr.join
    end

    @public_key = GPGME::Key.find(:public, 'test@example.com').first.export(armor: true).to_s
    # Verify that the key was imported successfully
    raise "Failed to import GPG key" unless @public_key
  end

  # dotenv >= 3 restores ENV after every example (config.dotenv.autorestore),
  # which wipes the GNUPGHOME set in before(:all). Re-assert it per example so
  # gpg can still find the keyring generated above.
  before do
    ENV['GNUPGHOME'] = @gpg_home
  end

  after(:all) do
    FileUtils.remove_entry @gpg_home if @gpg_home && File.exist?(@gpg_home)
    ENV['GNUPGHOME'] = @original_gpg_home
  end
end
