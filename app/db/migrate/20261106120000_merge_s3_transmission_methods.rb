# Folds encrypted_s3 (2) and unencrypted_s3 (5) into a single s3 (6) method.
# The s3 transmitter encrypts exactly when the config has a public_key, so:
#
# - every encrypted_s3 partner method must already have a public_key, or its
#   reports would start going out unencrypted;
# - no unencrypted_s3 partner method may carry a public_key, or its reports
#   would silently start going out encrypted (with a .gpg name); and
# - no partner (or flow) can have both, since a flow records one transmission
#   per method_type (unique index on cbv_flow_transmissions).
#
# Any of these aborts the migration with the offending ids instead of
# guessing. Uses raw integers, not the model enums, which no longer know 2 or 5.
class MergeS3TransmissionMethods < ActiveRecord::Migration[8.1]
  ENCRYPTED_S3 = 2
  UNENCRYPTED_S3 = 5
  S3 = 6

  def up
    check_encrypted_methods_have_public_key!
    check_unencrypted_methods_have_no_public_key!
    check_no_partner_has_both!
    check_no_flow_has_both!

    execute <<~SQL
      UPDATE partner_transmission_methods
      SET method_type = #{S3}, updated_at = NOW()
      WHERE method_type IN (#{ENCRYPTED_S3}, #{UNENCRYPTED_S3})
    SQL

    execute <<~SQL
      UPDATE cbv_flow_transmissions
      SET method_type = #{S3}, updated_at = NOW()
      WHERE method_type IN (#{ENCRYPTED_S3}, #{UNENCRYPTED_S3})
    SQL
  end

  # Splits s3 back out by whether a public_key is configured.
  def down
    execute <<~SQL
      UPDATE partner_transmission_methods ptm
      SET method_type = CASE WHEN #{partner_method_has_public_key_sql} THEN #{ENCRYPTED_S3} ELSE #{UNENCRYPTED_S3} END,
          updated_at = NOW()
      WHERE ptm.method_type = #{S3}
    SQL

    execute <<~SQL
      UPDATE cbv_flow_transmissions
      SET method_type = CASE WHEN COALESCE(configuration->>'public_key', '') <> '' THEN #{ENCRYPTED_S3} ELSE #{UNENCRYPTED_S3} END,
          updated_at = NOW()
      WHERE method_type = #{S3}
    SQL
  end

  private

  def partner_method_has_public_key_sql
    <<~SQL.squish
      EXISTS (
        SELECT 1 FROM partner_transmission_configs ptc
        WHERE ptc.partner_transmission_method_id = ptm.id
          AND ptc.key = 'public_key'
          AND COALESCE(ptc.value, '') <> ''
      )
    SQL
  end

  def check_encrypted_methods_have_public_key!
    ids = select_values(<<~SQL)
      SELECT ptm.id FROM partner_transmission_methods ptm
      WHERE ptm.method_type = #{ENCRYPTED_S3} AND NOT #{partner_method_has_public_key_sql}
    SQL
    abort_with("encrypted_s3 partner_transmission_methods without a public_key (they would send unencrypted as s3)", ids)

    # Pending or failed transmissions retry with their stored configuration.
    ids = select_values(<<~SQL)
      SELECT id FROM cbv_flow_transmissions
      WHERE method_type = #{ENCRYPTED_S3}
        AND status <> 1
        AND configuration <> '{}'::jsonb
        AND COALESCE(configuration->>'public_key', '') = ''
    SQL
    abort_with("unsent encrypted_s3 cbv_flow_transmissions without a public_key in their configuration", ids)
  end

  def check_unencrypted_methods_have_no_public_key!
    ids = select_values(<<~SQL)
      SELECT ptm.id FROM partner_transmission_methods ptm
      WHERE ptm.method_type = #{UNENCRYPTED_S3} AND #{partner_method_has_public_key_sql}
    SQL
    abort_with("unencrypted_s3 partner_transmission_methods with a public_key (they would start encrypting as s3)", ids)

    ids = select_values(<<~SQL)
      SELECT id FROM cbv_flow_transmissions
      WHERE method_type = #{UNENCRYPTED_S3}
        AND status <> 1
        AND COALESCE(configuration->>'public_key', '') <> ''
    SQL
    abort_with("unsent unencrypted_s3 cbv_flow_transmissions with a public_key in their configuration", ids)
  end

  def check_no_partner_has_both!
    ids = select_values(<<~SQL)
      SELECT partner_config_id FROM partner_transmission_methods
      WHERE method_type IN (#{ENCRYPTED_S3}, #{UNENCRYPTED_S3})
      GROUP BY partner_config_id HAVING COUNT(*) > 1
    SQL
    abort_with("partner_configs with more than one S3 transmission method", ids)
  end

  def check_no_flow_has_both!
    ids = select_values(<<~SQL)
      SELECT cbv_flow_id FROM cbv_flow_transmissions
      WHERE method_type IN (#{ENCRYPTED_S3}, #{UNENCRYPTED_S3})
      GROUP BY cbv_flow_id HAVING COUNT(*) > 1
    SQL
    abort_with("cbv_flows with both an encrypted_s3 and an unencrypted_s3 transmission", ids)
  end

  def abort_with(problem, ids)
    return if ids.empty?

    raise "Cannot merge S3 transmission methods: #{problem} (ids: #{ids.join(', ')}). Fix these rows, then re-run."
  end
end
