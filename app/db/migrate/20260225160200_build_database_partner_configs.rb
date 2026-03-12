class BuildDatabasePartnerConfigs < ActiveRecord::Migration[7.2]
  def up
    insert_pa_dhs
    insert_az_des
    insert_sandbox
  end

  def down
    PartnerConfig.where(partner_id: %(pa_dhs az_des sandbox)).each { |pc| pc.destroy }
  end

  def insert_pa_dhs
    pc = PartnerConfig.create(
      partner_id: "pa_dhs",
      active_demo: true,
      active_prod: true,
      name: "Department of Human Services",
      website: "https://www.compass.dhs.pa.gov/home/",
      timezone: "America/New_York",
      domain: "pa",
      argyle_environment: "sandbox",
      logo_path: "pa_compass_logo.svg",
      generic_links_enabled: false,
      invitation_links_enabled: true,
      transmission_method: :sftp,
      pilot_ended: false,
      pay_income_days_w2: 90,
      pay_income_days_gig: 90,
      staff_portal_enabled: false,
      weekly_report_enabled: true,
      weekly_report_recipients: "test@example.com",
      weekly_report_variant: "invitations",
      invitation_valid_days_default: 10,
      report_customization_show_earnings_list: true
    )

    pc.partner_transmission_configs.create(
      partner_id: "pa_dhs",
      key: "user",
      value: ENV['AZ_DES_SFTP_USER']
    )
    pc.partner_transmission_configs.create(
      partner_id: "pa_dhs",
      key: "password",
      value: ENV['AZ_DES_SFTP_PASSWORD']
    )
    pc.partner_transmission_configs.create(
      partner_id: "pa_dhs",
      key: "url",
      value: ENV['AZ_DES_SFTP_URL']
    )
    pc.partner_transmission_configs.create(
      partner_id: "pa_dhs",
      key: "sftp_directory",
      value: ENV['AZ_DES_SFTP_DIRECTORY']
    )
  end

  def insert_az_des
    pc = PartnerConfig.create(
      partner_id: "az_des",
      active_demo: true,
      active_prod: true,
      name: "Department of Economic Security/Family Assistance Administration",
      website: "https://myfamilybenefits.azdes.gov/",
      timezone: "America/Phoenix",
      domain: "az",
      argyle_environment: "sandbox",
      logo_path: "des_logo.png",
      generic_links_enabled: false,
      invitation_links_enabled: true,
      transmission_method: :sftp,
      pilot_ended: false,
      pay_income_days_w2: 90,
      pay_income_days_gig: 90,
      staff_portal_enabled: false,
      weekly_report_enabled: true,
      weekly_report_recipients: "test@example.com",
      weekly_report_variant: "invitations",
      invitation_valid_days_default: 10,
      report_customization_show_earnings_list: true
    )

    pc.partner_transmission_configs.create(
      partner_id: "az_des",
      key: "user",
      value: ENV['AZ_DES_SFTP_USER']
    )
    pc.partner_transmission_configs.create(
      partner_id: "az_des",
      key: "password",
      value: ENV['AZ_DES_SFTP_PASSWORD']
    )
    pc.partner_transmission_configs.create(
      partner_id: "az_des",
      key: "url",
      value: ENV['AZ_DES_SFTP_URL']
    )
    pc.partner_transmission_configs.create(
      partner_id: "az_des",
      key: "sftp_directory",
      value: ENV['AZ_DES_SFTP_DIRECTORY']
    )
  end

  def insert_sandbox
    pc = PartnerConfig.create(
      partner_id: "sandbox",
      active_demo: true,
      active_prod: true,
      name: "CBV Test Agency",
      website: "ttps://www.example.com/contact",
      timezone: "America/New_York",
      domain: "sandbox",
      argyle_environment: "sandbox",
      logo_path: "",
      generic_links_enabled: false,
      invitation_links_enabled: true,
      transmission_method: :shared_email,
      pilot_ended: false,
      pay_income_days_w2: 90,
      pay_income_days_gig: 90,
      staff_portal_enabled: true,
      weekly_report_enabled: true,
      weekly_report_recipients: "andre@digitalpublicworks.org,jeff@digitalpublicworks.org",
      weekly_report_variant: "invitations",
      invitation_valid_days_default: 14,
      report_customization_show_earnings_list: true
    )

    pc.partner_transmission_configs.create(
      partner_id: "sandbox",
      key: "email",
      value: "test@example.com"
    )
  end
end
