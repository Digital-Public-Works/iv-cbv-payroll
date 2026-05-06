class BackfillPartnerIdentifierAndMetadata < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def up
    # Legacy backfill for existing partners before they get the updated dynamic partner params functionality
    execute <<~SQL
      UPDATE cbv_applicants
      SET
        partner_identifier = case_number,
        agency_partner_metadata = jsonb_strip_nulls(
          jsonb_build_object(
            'first_name',  first_name,
            'middle_name', middle_name,
            'last_name',   last_name
          )
        )
    SQL

    # backfill existing partners to use the 'default' which has been case_number. This only needs to run a single time
    execute <<~SQL
      UPDATE partner_configs
      SET partner_identifier_name = 'case_number'
      WHERE partner_identifier_name IS NULL
    SQL
  end

  # no down migration since it would be a moot point, this is only additive / updates new column
end
