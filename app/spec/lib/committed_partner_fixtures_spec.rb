require "rails_helper"
require "partner_config_loader"

# Guards the committed (generic, fake) partner fixture pairs against schema
# drift: if a required-credential-key or partition rule changes in
# PartnerConfigLoader, these fail until the fixtures are updated. Real partner
# configs live in the private store and cannot be committed to this public repo,
# so these fakes are the only per-partner shape check CI can run.
RSpec.describe "committed partner config fixtures" do
  docs_dir = Rails.root.join("..", "docs", "app")

  fixtures = {
    "demo" => {
      settings: docs_dir.join("demo-partner.settings.yml"),
      credentials: docs_dir.join("demo-partner.credentials.demo.yml")
    },
    "integration_test" => {
      settings: docs_dir.join("integration-test-partner.settings.yml"),
      credentials: docs_dir.join("integration-test-partner.credentials.yml")
    }
  }

  fixtures.each do |partner_id, paths|
    context "#{partner_id} fixture pair" do
      let(:loader) { PartnerConfigLoader.new(paths[:settings].to_s, paths[:credentials].to_s) }

      it "both documents exist" do
        expect(File.exist?(paths[:settings])).to be(true), "missing #{paths[:settings]}"
        expect(File.exist?(paths[:credentials])).to be(true), "missing #{paths[:credentials]}"
      end

      it "loads and validates without errors" do
        loader.load!
        loader.validate!
        expect(loader.errors).to be_empty, "validation errors: #{loader.errors.join('; ')}"
        expect(loader.yaml_data[:partner_id]).to eq(partner_id)
      end
    end
  end
end
