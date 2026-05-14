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

  # stem + extension (used to actually write the file + webhook payload builder)
  def self.for(cbv_flow, agency, method_type)
    extension = EXTENSIONS.fetch(method_type.to_sym) do
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

  def self.formatted_partner_identifier(cbv_flow)
    cbv_flow.cbv_applicant.partner_identifier.to_s.rjust(8, "0")
  end

  def self.formatted_consent_stamp(cbv_flow, agency)
    cbv_flow.consented_to_authorized_use_at.in_time_zone(agency.timezone).strftime("%Y%m%d")
  end

  # a stem is a filename without an extension.
  # This pure function is deterministic because consented_to_authorized_use_at is set once at consent time and not mutated.
  def self.stem(cbv_flow, agency)
    "CBVPilot_#{formatted_partner_identifier(cbv_flow)}_#{formatted_consent_stamp(cbv_flow, agency)}_Conf#{cbv_flow.confirmation_code}"
  end
end
