require "rails_helper"

# Verifies that partner routes are resolved dynamically from the database at
# request time rather than enumerated into the route table at boot.
RSpec.describe "Dynamic client agency routing", type: :routing do
  it "recognizes the caseworker route for a known partner id" do
    expect(get: "/sandbox").to be_routable
  end

  it "does not recognize a route for an unknown partner id" do
    expect(get: "/definitely-not-a-partner").not_to be_routable
  end

  it "recognizes the generic link route for a known partner id" do
    expect(get: "/cbv/links/sandbox").to be_routable
  end

  # Verify that a newly-created partner is routable.
  it "recognizes a partner created after the routes were drawn" do
    partner = FactoryBot.create(:partner_config, partner_id: "brand_new_partner", domain: "brandnew")
    FactoryBot.create(:partner_application_attribute, partner_config: partner)

    expect(get: "/brand_new_partner").to be_routable
  end
end
