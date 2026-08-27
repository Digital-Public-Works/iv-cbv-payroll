require "tmpdir"

RSpec.shared_context "gpg_setup" do
  before(:all) do
    @original_gpg_home = ENV['GNUPGHOME']

    # Each example group gets its own throwaway GNUPGHOME. Every group that
    # includes this context used to share Rails.root/tmp/gpghome, so a failed
    # teardown left a partial keyring behind for the *next* group (and, since
    # tmp/ is gitignored, for the next rspec run too). Generating into a shared
    # home also accumulated several keys under the same test@example.com uid,
    # and the lookup below takes .first — which could select a key whose secret
    # material had already been swept away, giving GPGME::Error::NoSecretKey on
    # decrypt while encrypt still succeeded.
    #
    # Kept under Dir.tmpdir rather than Rails.root/tmp to keep the path short:
    # gpg-agent's sockets live in GNUPGHOME and unix socket paths cap out around
    # 108 characters, which a deep project path can exceed silently.
    @gpg_home = Dir.mktmpdir("gpghome")
    FileUtils.chmod(0o700, @gpg_home)
    ENV['GNUPGHOME'] = @gpg_home

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

    key = GPGME::Key.find(:public, 'test@example.com').first
    # Fail loudly here rather than with a NoMethodError on nil, so a broken
    # keyring is reported against setup instead of the first example to decrypt.
    raise "Failed to generate GPG key in #{@gpg_home}" if key.nil?
    @public_key = key.export(armor: true).to_s
  end

  # dotenv >= 3 restores ENV after every example (config.dotenv.autorestore),
  # which wipes the GNUPGHOME set in before(:all). Re-assert it per example so
  # gpg can still find the keyring generated above.
  before do
    ENV['GNUPGHOME'] = @gpg_home
  end

  after(:all) do
    if @gpg_home
      # autorestore may have already reverted GNUPGHOME, so point it back before
      # stopping the agent — gpgconf acts on whichever home is current.
      ENV['GNUPGHOME'] = @gpg_home

      # Stop gpg-agent before deleting its directory. It removes its own
      # S.gpg-agent* sockets on shutdown, which races the delete: FileUtils
      # stats a socket, gpg-agent unlinks it, and the delete blows up with
      # ENOENT partway through, leaving the keyring half-removed.
      system("gpgconf", "--kill", "gpg-agent", out: File::NULL, err: File::NULL)

      # rm_rf rather than remove_entry: it tolerates entries that disappear
      # underneath it, so a lingering socket can't abort the cleanup.
      FileUtils.rm_rf(@gpg_home)
    end

    ENV['GNUPGHOME'] = @original_gpg_home
  end
end
