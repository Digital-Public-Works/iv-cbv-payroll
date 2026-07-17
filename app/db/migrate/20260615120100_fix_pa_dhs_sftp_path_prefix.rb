# The original PA DHS seed (20260225160200_build_database_partner_configs) created the
# SFTP remote-directory config under a mislabeled key, "PA_DHS_SFTP_URL", holding the
# value of ENV['PA_DHS_SFTP_DIRECTORY']. Because the key was not "sftp_directory", the
# later rename migration (20260526155906) never corrected it, so PA DHS has no
# "path_prefix" config while every other SFTP partner does. This renames it so all SFTP
# transmission configs consistently use "path_prefix".
class FixPaDhsSftpPathPrefix < ActiveRecord::Migration[7.2]
  def up
    rename_pa_dhs_sftp_key(from: %w[PA_DHS_SFTP_URL sftp_directory], to: "path_prefix")
  end

  def down
    rename_pa_dhs_sftp_key(from: %w[path_prefix], to: "PA_DHS_SFTP_URL")
  end

  private

  def rename_pa_dhs_sftp_key(from:, to:)
    config = PartnerConfig.find_by(partner_id: "pa_dhs")
    return unless config

    PartnerTransmissionConfig
      .joins(:partner_transmission_method)
      .where(partner_transmission_methods: { partner_config_id: config.id, method_type: "sftp" })
      .where(key: from)
      .update_all(key: to)
  end
end
