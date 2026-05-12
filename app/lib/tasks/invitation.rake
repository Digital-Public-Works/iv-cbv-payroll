namespace :invitation do
  desc "create invitation link to start flow, ex: rake invitation:create[la_ldh], (default: la_ldh)"
  task :create, [ :client_agency_id ] => :environment do |_, args|
    log = ActiveSupport::Logger.new($stdout)
    begin
      raise "❌ Can't run this in prod! ❌" if Rails.env.production?

      client_agency_id = args[:client_agency_id] || "la_ldh"
      user = User.find_or_create_by(
        email: "ffs-eng+#{client_agency_id}@navapbc.com",
        client_agency_id: client_agency_id
      )

      user.update(is_service_account: true)
      agency = ClientAgencyConfig.instance[client_agency_id]

      # to use this rake to create an example invitation for another partner, this sample metadata would need to be expanded to include the values required by that partner
      sample_metadata = {
        "first_name" => "Joe",
        "last_name" => "Schmoe",
        "date_of_birth" => Date.new(1990, 1, 1)
      }
      applicant_attrs = {
        client_agency_id: client_agency_id,
        partner_identifier: rand(1000..9999).to_s
      }
      # Only carry sample fields when the agency has them configured. Real
      # columns and partner-defined attributes alike are routed correctly.
      sample_metadata.each do |key, value|
        applicant_attrs[key.to_sym] = value if agency&.applicant_attributes&.key?(key)
      end

      invite = CbvFlowInvitation.new({
        user: user,
        client_agency_id: client_agency_id,
        language: "en",
        email_address: user.email,
        cbv_applicant_attributes: applicant_attrs
      })
      invite.save!
      log.info "Invite link created successfully! 🎉"
      log.info invite.to_url(origin: nil).gsub("https", "http")
    rescue => e
      log.error "Failed to created invite link ☹️ : #{e}"
    end
  end
end
