# This file is copied to spec/ when you run 'rails generate rspec:install'
require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
# Prevent database truncation if the environment is production
abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"
require "view_component/test_helpers"
require "support/context/gpg_setup"
require "view_component/system_test_helpers"

require "active_job/test_helper"

# Capybara configuration for E2E tests
require "axe-rspec"
require "capybara/rspec"
if ENV["E2E_SHOW_BROWSER"]
  Capybara.default_driver = :selenium_chrome
else
  Capybara.register_driver :selenium_chrome_custom do |app|
    options = Selenium::WebDriver::Chrome::Options.new
    # These are copied from `selenium_chrome_headless` upstream and can be
    # removed after the next Capybara version is released.
    # See: https://github.com/teamcapybara/capybara/blob/b3325b1/lib/capybara/registrations/drivers.rb#L31
    options.add_argument("--headless=new")
    options.add_argument("--disable-gpu")
    options.add_argument('--disable-site-isolation-trials')
    options.add_argument('disable-background-timer-throttling')
    options.add_argument('disable-backgrounding-occluded-windows')
    options.add_argument('disable-renderer-backgrounding')

    # Set 'prefers-reduced-motion' CSS property, which will instruct USWDS to
    # skip transitions. This prevents axe matchers (for accessibility/contrast
    # checking) from running on partially-opened modals.
    options.add_argument("--force-prefers-reduced-motion")

    Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
  end
  Capybara.default_driver = :selenium_chrome_custom
end
Capybara.javascript_driver = Capybara.default_driver


Rails.application.load_tasks

# Add additional requires below this line. Rails is not loaded until this point!

# Requires supporting ruby files with custom matchers and macros, etc, in
# spec/support/ and its subdirectories. Files matching `spec/**/*_spec.rb` are
# run as spec files by default. This means that files in spec/support that end
# in _spec.rb will both be required and run as specs, causing the specs to be
# run twice. It is recommended that you do not name files matching this glob to
# end with _spec.rb. You can configure this pattern with the --pattern
# option on the command line or in ~/.rspec, .rspec or `.rspec-local`.
#
# The following line is provided for convenience purposes. It has the downside
# of increasing the boot-up time by auto-requiring all files in the support
# directory. Alternatively, in the individual `*_spec.rb` files, manually
# require only the support files necessary.
#
Dir[Rails.root.join('spec', 'support', '**', '*.rb')].sort.each { |f| require f }

# Checks for pending migrations and applies them before tests are run.
# If you are not using ActiveRecord, you can remove these lines.
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  Rails.logger.info e.to_s.strip
  exit 1
end

VCR.configure do |config|
  if ENV["E2E_RECORD_MODE"]
    # Necessary to set up webhook subscriptions to Argyle/Pinwheel.
    config.allow_http_connections_when_no_cassette = true
  end
  config.cassette_library_dir = "spec/fixtures/vcr_cassettes" # Overwritten in E2E tests
  config.hook_into :webmock
  config.ignore_localhost = true
  config.ignore_hosts %w[
    logs.browser-intake-datadoghq.com
    firefox-settings-attachments.cdn.mozilla.net
    firefox.settings.services.mozilla.com plugin.argyle.com
    switchboard.pwhq.net passwordsleakcheck-pa.googleapis.com
    optimizationguide-pa.googleapis.com cdn.getpinwheel.com featuregates.org
    datadog events.statsigapi.net content-signature-2.cdn.mozilla.net
    content-autofill.googleapis.com
  ]
  config.default_cassette_options = { record: :once }
end

RSpec.configure do |config|
  # Include a handful of useful helpers we've written
  config.include TestHelpers

  # If you're not using ActiveRecord, or you'd prefer not to run each of your
  # examples within a transaction, remove the following line or assign false
  # instead of true.
  config.use_transactional_fixtures = true

  config.before(:suite) do
    partners = [ nil, :az_des, :la_ldh, :pa_dhs ]

    PartnerApplicationAttribute.delete_all
    PartnerTransmissionConfig.delete_all
    PartnerTransmissionMethod.delete_all
    PartnerConfig.delete_all

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

    # LA LDH needs to set case_number to optional and needs a doc_id PAA
    la_ldh_config = PartnerConfig.find_by(partner_id: 'la_ldh')
    PartnerApplicationAttribute.where(partner_config: la_ldh_config, name: 'case_number')
      .update_all(required: false)

    # LA LDH needs doc_id
    FactoryBot.create(:partner_application_attribute,
      partner_config: la_ldh_config,
      name: 'doc_id',
      description: 'Document ID',
      required: false,
      data_type: 'string',
      redactable: false
    )

    # AZ DES and PA DHS need income_changes
    az_des_config = PartnerConfig.find_by(partner_id: 'az_des')
    pa_dhs_config = PartnerConfig.find_by(partner_id: 'pa_dhs')
    PartnerApplicationAttribute.where(partner_config: az_des_config, name: 'case_number')
      .update_all(required: true, show_on_caseworker_report: true)

    [ az_des_config, pa_dhs_config ].each do |config|
      FactoryBot.create(:partner_application_attribute,
        partner_config: config,
        name: 'income_changes',
        description: 'income changes',
        required: false,
        data_type: 'string',
        redactable: false
      )
    end

    # Sandbox caseworker-only fields
    sandbox_config = PartnerConfig.find_by(partner_id: 'sandbox')
    [
      { name: 'beacon_id', description: "Your WELID", form_field_type: 'text_field' },
      { name: 'agency_id_number', description: "Client's agency ID number", form_field_type: 'text_field' },
      { name: 'client_id_number', description: "CIN", form_field_type: 'text_field' },
      { name: 'snap_application_date', description: "SNAP application or recertification interview date", form_field_type: 'date_picker' }
    ].each do |attrs|
      FactoryBot.create(:partner_application_attribute,
        partner_config: sandbox_config,
        name: attrs[:name],
        description: attrs[:description],
        required: false,
        data_type: attrs[:data_type] || 'string',
        form_field_type: attrs[:form_field_type],
        redactable: false,
        show_on_applicant_form: false,
        show_on_caseworker_form: true
      )
    end

    ClientAgencyConfig.reset!
    Rails.application.reload_routes!
  end


  config.before(:each) do
    ClientAgencyConfig.reset!
  end

  # You can uncomment this line to turn off ActiveRecord support entirely.
  # config.use_active_record = false

  # RSpec Rails can automatically mix in different behaviours to your tests
  # based on their file location, for example enabling you to call `get` and
  # `post` in specs under `spec/controllers`.
  #
  # You can disable this behaviour by removing the line below, and instead
  # explicitly tag your specs with their type, e.g.:
  #
  #     RSpec.describe UsersController, type: :controller do
  #       # ...
  #     end
  #
  # The different available types are documented in the features, such as in
  # https://relishapp.com/rspec/rspec-rails/docs
  config.infer_spec_type_from_file_location!

  # Filter lines from Rails gems in backtraces.
  config.filter_rails_from_backtrace!
  # arbitrary gems may also be filtered via:
  # config.filter_gems_from_backtrace("gem name")

  config.include ViewComponent::TestHelpers, type: :component
  config.include ViewComponent::SystemTestHelpers, type: :component
  config.include Capybara::RSpecMatchers, type: :component

  # activejob helper
  config.include ActiveJob::TestHelper
  config.before(:each) { clear_enqueued_jobs && clear_performed_jobs }

  config.include ActiveSupport::Testing::TimeHelpers

  # Print some helpful debugging info about the last test failure, since
  # sometimes it's a bit hard to tell which page the error is coming from.
  config.after(js: true) do |test|
    if test.exception.present?
      begin
        Rails.logger.error "[E2E] Last page accessed: #{URI(page.current_url).path}"
        screenshot_path = Rails.root.join("tmp", "failure_#{test.full_description.gsub(/[^a-z0-9]+/i, "_")}.png")
        page.save_screenshot(screenshot_path)
        Rails.logger.error "[E2E] Screenshot saved to: #{screenshot_path}"
      rescue => ex
        Rails.logger.error "[E2E] Failed to print debug info: #{ex}"
      end
    end
  end
end
