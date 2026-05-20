# Single source of truth for transmitted filenames. Every transmitter
# and the webhook payload builder MUST call this — never inline - so they match deterministically.
class TransmissionFilename
  MAX_TOTAL_LENGTH = 100

  # Per-method extension for file-producing transmissions.
  EXTENSIONS = {
    sftp:            ".pdf",
    unencrypted_s3:  ".tar.gz",
    encrypted_s3:    ".tar.gz.gpg"
  }.freeze

  # Legacy partners shipped before the VMI rename and have downstream automation
  # that parses the `CBVPilot_`
  # prefix for these agencies and use `VMI_` for everyone else.
  LEGACY_FILENAME_PREFIX_AGENCY_IDS = %w[pa_dhs az_des].freeze
  LEGACY_FILENAME_PREFIX = "CBVPilot".freeze
  DEFAULT_FILENAME_PREFIX = "VMI".freeze

  # The full remote path where this transmission lands.
  # e.g. path/to/inbox/VMI_00012345_20260513_ConfABC123.pdf
  def self.full_path(cbv_flow:, agency:, method_type:, remote_directory:)
    basename = basename_for(cbv_flow: cbv_flow, agency: agency, method_type: method_type)
    dir = remote_directory_for(method_type: method_type, remote_directory: remote_directory)
    dir.empty? ? basename : File.join(dir, basename)
  end

  # Basename (stem + extension). All file-producing methods share
  # the same deterministic stem; only the extension differs by method_type.
  # e.g. VMI_00012345_20260513_ConfABC123.pdf
  def self.basename_for(cbv_flow:, agency:, method_type:)
    extension = EXTENSIONS.fetch(method_type) do
      raise KeyError, "TransmissionFilename: `#{method_type}` is not a file-producing method (only #{EXTENSIONS.keys.join(', ')} are)"
    end
    if cbv_flow.consented_to_authorized_use_at.nil?
      raise "Cannot generate transmission filename: consent timestamp is missing for cbv_flow #{cbv_flow.id}"
    end

    full = stem(cbv_flow, agency) + extension

    # 100-char total ceiling due to POSIXv7 (circa 1979) limitation in the filename for Ruby's tar package. (origin: PR #439)
    if full.length > MAX_TOTAL_LENGTH
      raise "Transmission filename exceeds #{MAX_TOTAL_LENGTH} chars (#{full.length}): #{full}"
    end

    full
  end

  # The configured remote directory for a file-producing transmission method, or nil otherwise.
  def self.remote_directory_from_config(method_type:, configuration:)
    return nil unless EXTENSIONS.key?(method_type)
    configuration["path_prefix"]
  end

  # remote directory, normalized & validated across file-based transmission methods.
  # Returns "" when blank (use base directory)
  # e.g. path/to/inbox
  def self.remote_directory_for(method_type:, remote_directory:)
    return "" if remote_directory.blank?

    if %i[unencrypted_s3 encrypted_s3].include?(method_type) && remote_directory.start_with?("/")
      raise ArgumentError,
            "TransmissionFilename: remote_directory for #{method_type} must not start with '/' (got #{remote_directory.inspect})"
    end

    remote_directory
  end

  def self.formatted_partner_identifier(cbv_flow)
    cbv_flow.cbv_applicant.partner_identifier.to_s.rjust(8, "0")
  end

  def self.formatted_consent_stamp(cbv_flow, agency)
    cbv_flow.consented_to_authorized_use_at.in_time_zone(agency.timezone).strftime("%Y%m%d")
  end

  def self.filename_prefix_for(agency)
    LEGACY_FILENAME_PREFIX_AGENCY_IDS.include?(agency.id) ? LEGACY_FILENAME_PREFIX : DEFAULT_FILENAME_PREFIX
  end

  # a stem is a filename without an extension.
  # This pure function is deterministic because consented_to_authorized_use_at is set once at consent time and not mutated.
  # e.g. VMI_00012345_20260513_ConfABC123
  def self.stem(cbv_flow, agency)
    "#{filename_prefix_for(agency)}_#{formatted_partner_identifier(cbv_flow)}_#{formatted_consent_stamp(cbv_flow, agency)}_Conf#{cbv_flow.confirmation_code}"
  end
end
