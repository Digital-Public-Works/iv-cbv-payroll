require "rails_helper"

RSpec.describe AdminApi::Config do
  describe ".enabled?" do
    it "is false when the service secret is unset or blank" do
      [ nil, "", "  " ].each do |value|
        stub_environment_variable("ADMIN_API_SERVICE_SECRET", value) do
          expect(described_class.enabled?).to be(false)
        end
      end
    end

    it "is true when the service secret is set" do
      stub_environment_variable("ADMIN_API_SERVICE_SECRET", "secret") do
        expect(described_class.enabled?).to be(true)
      end
    end
  end

  describe ".settings_writable?" do
    it "is false when unset, so a forgotten flag behaves like prod" do
      stub_environment_variable("ADMIN_API_SETTINGS_WRITABLE", nil) do
        expect(described_class.settings_writable?).to be(false)
      end
    end

    it "is false for anything other than true" do
      %w[false 0 yes 1 truthy].each do |value|
        stub_environment_variable("ADMIN_API_SETTINGS_WRITABLE", value) do
          expect(described_class.settings_writable?).to be(false)
        end
      end
    end

    it "is true for true, ignoring case and surrounding space" do
      [ "true", "TRUE", " true " ].each do |value|
        stub_environment_variable("ADMIN_API_SETTINGS_WRITABLE", value) do
          expect(described_class.settings_writable?).to be(true)
        end
      end
    end
  end
end
