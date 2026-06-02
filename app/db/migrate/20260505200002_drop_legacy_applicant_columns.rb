class DropLegacyApplicantColumns < ActiveRecord::Migration[7.2]
  def up
    remove_column :cbv_applicants, :case_number
    remove_column :cbv_applicants, :first_name
    remove_column :cbv_applicants, :middle_name
    remove_column :cbv_applicants, :last_name
  end

  def down
    add_column :cbv_applicants, :case_number, :string
    add_column :cbv_applicants, :first_name, :string
    add_column :cbv_applicants, :middle_name, :string
    add_column :cbv_applicants, :last_name, :string

    execute <<~SQL
      UPDATE cbv_applicants
      SET
        case_number = partner_identifier,
        first_name  = agency_partner_metadata ->> 'first_name',
        middle_name = agency_partner_metadata ->> 'middle_name',
        last_name   = agency_partner_metadata ->> 'last_name'
    SQL
  end
end
