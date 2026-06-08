class RenameSftpDirectoryToPathPrefix < ActiveRecord::Migration[7.2]
  def up
    PartnerTransmissionConfig.where(key: "sftp_directory").update_all(key: "path_prefix")
  end

  def down
    PartnerTransmissionConfig
      .joins(:partner_transmission_method)
      .where(partner_transmission_methods: { method_type: "sftp" }, key: "path_prefix")
      .update_all(key: "sftp_directory")
  end
end
