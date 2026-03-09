RSpec.shared_context "partner setup", shared_context: :metadata do
  before(:all) do
    partners = [ nil, :az_des, :la_ldh, :pa_dhs ]

    # TODO
    # PartnerApplicationAttribute.delete_all
    # PartnerConfig.delete_all

    @sandbox = PartnerConfig.find_by(partner_id: 'sandbox') || FactoryBot.create(:partner_config)

    attributes = [
      { name: 'first_name', trait: nil },
      { name: 'middle_name', trait: :middle_name },
      { name: 'last_name', trait: :last_name },
      { name: 'date_of_birth', trait: :date_of_birth },
      { name: 'case_number', trait: :case_number }
    ]

    partners.each do |partner|
      p_id = case partner
             when :az_des then 'az_des'
             when :la_ldh then 'la_ldh'
             when :pa_dhs then 'pa_dhs'
             else 'sandbox'
             end

      config = PartnerConfig.find_by(partner_id: p_id) ||
                (partner ? FactoryBot.create(:partner_config, partner) : FactoryBot.create(:partner_config))

      attributes.each do |a_data|
        unless PartnerApplicationAttribute.exists?(partner_config: config, name: a_data[:name])
          if a_data[:trait]
            FactoryBot.create(:partner_application_attribute, a_data[:trait], partner_config: config)
          else
            FactoryBot.create(:partner_application_attribute, partner_config: config)
          end
        end
      end
    end
  end
end
