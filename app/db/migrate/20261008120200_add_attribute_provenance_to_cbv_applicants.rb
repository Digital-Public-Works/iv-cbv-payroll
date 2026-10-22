class AddAttributeProvenanceToCbvApplicants < ActiveRecord::Migration[8.1]
  def change
    # Per-value provenance for applicant attributes, keyed by attribute name:
    #   { "date_of_birth" => { "source" => "applicant", "at" => "2026-10-08T..." } }
    # Attributes with no entry came from the invitation (caseworker or partner API).
    add_column :cbv_applicants, :attribute_provenance, :jsonb, default: {}, null: false
  end
end
