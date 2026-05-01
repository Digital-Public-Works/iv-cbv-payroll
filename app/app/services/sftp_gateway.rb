class SftpGateway
  attr_reader :url, :user, :password, :port
  def initialize(options)
    @url = options[:url]
    @user = options[:user]
    @password = options[:password]
    @port = (options[:port] || 22).to_i
  end

  def upload_data(local_file, remote_file_location)
    ssh_options = {
      password: password,
      port: port
    }

    # Use password-only auth so Net::SSH does not scan local SSH keys (which can
    # require optional gems such as ed25519/bcrypt_pbkdf).
    if password.present?
      ssh_options.merge!(
        keys: [],
        auth_methods: %w[password keyboard-interactive],
        non_interactive: true
      )
    end

    session = Net::SSH.start(url, user, **ssh_options)
    sftp = Net::SFTP::Session.new(session)
    sftp.connect!
    sftp.upload! local_file, remote_file_location
    sftp.channel.eof!
    # https://github.com/net-ssh/net-ssh/issues/716
    sftp.close_channel
  end
end
