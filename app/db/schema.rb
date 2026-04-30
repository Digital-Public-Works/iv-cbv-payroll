# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2026_04_15_000001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pgcrypto"
  enable_extension "plpgsql"

  create_table "api_access_tokens", force: :cascade do |t|
    t.string "access_token"
    t.integer "user_id"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "cbv_applicants", force: :cascade do |t|
    t.string "case_number"
    t.string "first_name"
    t.string "middle_name"
    t.string "last_name"
    t.string "agency_id_number"
    t.string "client_id_number"
    t.date "snap_application_date"
    t.string "beacon_id"
    t.datetime "redacted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "client_agency_id"
    t.jsonb "income_changes"
    t.date "date_of_birth"
    t.string "doc_id"
  end

  create_table "cbv_flow_invitations", force: :cascade do |t|
    t.string "email_address"
    t.string "auth_token"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "client_agency_id"
    t.datetime "redacted_at"
    t.bigint "user_id"
    t.string "language"
    t.bigint "cbv_applicant_id"
    t.datetime "expires_at", precision: nil
    t.index ["auth_token"], name: "index_cbv_flow_invitations_on_auth_token", unique: true, where: "(redacted_at IS NULL)"
    t.index ["cbv_applicant_id"], name: "index_cbv_flow_invitations_on_cbv_applicant_id"
    t.index ["user_id"], name: "index_cbv_flow_invitations_on_user_id"
  end

  create_table "cbv_flow_transmissions", force: :cascade do |t|
    t.bigint "cbv_flow_id", null: false
    t.integer "method_type", null: false
    t.integer "status", default: 0, null: false
    t.jsonb "configuration", default: {}, null: false
    t.datetime "succeeded_at"
    t.text "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["cbv_flow_id", "method_type"], name: "idx_cbv_flow_transmissions_on_flow_and_method", unique: true
    t.index ["cbv_flow_id"], name: "index_cbv_flow_transmissions_on_cbv_flow_id"
  end

  create_table "cbv_flows", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.date "payroll_data_available_from"
    t.bigint "cbv_flow_invitation_id"
    t.string "pinwheel_token_id"
    t.uuid "end_user_id", default: -> { "gen_random_uuid()" }, null: false
    t.jsonb "additional_information", default: {}
    t.string "client_agency_id"
    t.string "confirmation_code"
    t.datetime "transmitted_at"
    t.datetime "consented_to_authorized_use_at"
    t.datetime "redacted_at"
    t.bigint "cbv_applicant_id"
    t.string "argyle_user_id"
    t.boolean "has_other_jobs"
    t.string "device_id"
    t.index ["cbv_applicant_id"], name: "index_cbv_flows_on_cbv_applicant_id"
    t.index ["cbv_flow_invitation_id"], name: "index_cbv_flows_on_cbv_flow_invitation_id"
  end

  create_table "partner_application_attributes", force: :cascade do |t|
    t.bigint "partner_config_id", null: false
    t.string "name", null: false
    t.text "description"
    t.boolean "required", default: true, null: false
    t.integer "data_type", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "show_on_caseworker_report", default: false, null: false
    t.boolean "redactable", default: false, null: false
    t.string "redact_type"
    t.string "form_field_type", default: "text_field"
    t.boolean "show_on_applicant_form", default: true, null: false
    t.boolean "show_on_caseworker_form", default: true, null: false
    t.index ["partner_config_id"], name: "index_partner_application_attributes_on_partner_config_id"
  end

  create_table "partner_configs", force: :cascade do |t|
    t.string "partner_id", null: false
    t.boolean "active_demo", default: false, null: false
    t.boolean "active_prod", default: false, null: false
    t.string "timezone", null: false
    t.string "name", null: false
    t.string "website"
    t.string "domain"
    t.string "logo_path"
    t.string "argyle_environment"
    t.boolean "staff_portal_enabled", default: false, null: false
    t.boolean "pilot_ended", default: false, null: false
    t.string "default_origin"
    t.boolean "generic_links_enabled", default: false, null: false
    t.boolean "invitation_links_enabled", default: false, null: false
    t.integer "pay_income_days_w2"
    t.integer "pay_income_days_gig"
    t.integer "invitation_valid_days_default"
    t.boolean "weekly_report_enabled", default: false, null: false
    t.text "weekly_report_recipients"
    t.string "weekly_report_variant"
    t.boolean "report_customization_show_earnings_list", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "include_invitation_details_on_weekly_report", default: false, null: false
    t.string "state_name"
    t.index ["partner_id"], name: "index_partner_configs_on_partner_id", unique: true
  end

  create_table "partner_translations", force: :cascade do |t|
    t.bigint "partner_config_id", null: false
    t.string "locale"
    t.string "key"
    t.text "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["partner_config_id"], name: "index_partner_translations_on_partner_config_id"
  end

  create_table "partner_transmission_configs", force: :cascade do |t|
    t.bigint "partner_config_id"
    t.string "key", null: false
    t.text "value"
    t.boolean "is_encrypted", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "partner_transmission_method_id", null: false
    t.index ["partner_config_id"], name: "index_partner_transmission_configs_on_partner_config_id"
    t.index ["partner_transmission_method_id"], name: "idx_on_partner_transmission_method_id_917bdbc05f"
  end

  create_table "partner_transmission_methods", force: :cascade do |t|
    t.bigint "partner_config_id", null: false
    t.integer "method_type", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["partner_config_id"], name: "index_partner_transmission_methods_on_partner_config_id"
  end

  create_table "payroll_accounts", force: :cascade do |t|
    t.bigint "cbv_flow_id", null: false
    t.string "aggregator_account_id"
    t.datetime "income_synced_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "supported_jobs", default: [], array: true
    t.string "type", default: "pinwheel", null: false
    t.string "synchronization_status", default: "unknown"
    t.datetime "redacted_at"
    t.datetime "discarded_at"
    t.index ["cbv_flow_id"], name: "index_payroll_accounts_on_cbv_flow_id"
    t.index ["discarded_at"], name: "index_payroll_accounts_on_discarded_at"
  end

  create_table "users", force: :cascade do |t|
    t.string "client_agency_id", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "invalidated_session_ids"
    t.boolean "is_service_account", default: false
    t.index ["email", "client_agency_id"], name: "index_users_on_email_and_client_agency_id", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "webhook_events", force: :cascade do |t|
    t.string "event_name"
    t.string "event_outcome"
    t.bigint "payroll_account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["payroll_account_id"], name: "index_webhook_events_on_payroll_account_id"
  end

  add_foreign_key "cbv_flow_invitations", "users"
  add_foreign_key "cbv_flow_transmissions", "cbv_flows"
  add_foreign_key "cbv_flows", "cbv_flow_invitations"
  add_foreign_key "partner_application_attributes", "partner_configs"
  add_foreign_key "partner_translations", "partner_configs"
  add_foreign_key "partner_transmission_configs", "partner_configs"
  add_foreign_key "partner_transmission_configs", "partner_transmission_methods"
  add_foreign_key "partner_transmission_methods", "partner_configs"
  add_foreign_key "payroll_accounts", "cbv_flows"
  add_foreign_key "webhook_events", "payroll_accounts"
end
