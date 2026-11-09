class CreatePartnerAttributeUsages < ActiveRecord::Migration[8.1]
  def up
    create_table :partner_attribute_usages do |t|
      t.references :partner_config, null: false, foreign_key: true
      t.string :context, null: false
      t.string :name, null: false
      t.boolean :required, default: false, null: false
      t.integer :position, default: 0, null: false
      t.timestamps
    end

    add_index :partner_attribute_usages,
      [ :partner_config_id, :context, :name ],
      unique: true,
      name: "idx_partner_attribute_usages_unique"
    add_index :partner_attribute_usages,
      [ :partner_config_id, :context, :position ],
      name: "idx_partner_attribute_usages_order"

    # Backfill from the columns this table replaces, so every partner keeps
    # behaving exactly as it does today: everything was offered on an invitation
    # (required ones mandatory), and the applicant-information page showed
    # whatever had show_on_applicant_form set.
    say_with_time "Backfilling partner_attribute_usages" do
      rows = select_all(<<~SQL)
        SELECT id, partner_config_id, name, required, show_on_applicant_form
        FROM partner_application_attributes
        ORDER BY partner_config_id, id
      SQL

      positions = Hash.new(0)
      rows.each do |row|
        insert_usage(row, "invitation", row["required"], positions)
        insert_usage(row, "applicant_input_page", row["required"], positions) if row["show_on_applicant_form"]
      end
      rows.count
    end
  end

  def down
    drop_table :partner_attribute_usages
  end

  private

  def insert_usage(row, context, required, positions)
    key = [ row["partner_config_id"], context ]
    position = positions[key]
    positions[key] += 1

    execute(<<~SQL)
      INSERT INTO partner_attribute_usages
        (partner_config_id, context, name, required, position, created_at, updated_at)
      VALUES
        (#{row["partner_config_id"].to_i},
         #{quote(context)},
         #{quote(row["name"])},
         #{required ? "TRUE" : "FALSE"},
         #{position},
         NOW(), NOW())
      ON CONFLICT DO NOTHING
    SQL
  end
end
