class AddValidationFieldsToPartnerApplicationAttributes < ActiveRecord::Migration[8.1]
  def change
    # Applied to a value the applicant types in, when one is configured.
    add_column :partner_application_attributes, :validation_regex, :string

    # The applicant cannot get past the applicant-information step, and so
    # cannot submit a report, while an attribute marked here has no value.
    add_column :partner_application_attributes, :required_for_submit, :boolean, default: false, null: false
  end
end
