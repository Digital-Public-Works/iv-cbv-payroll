require "rails_helper"
require "constraints/client_agency_id_constraint"

RSpec.describe ClientAgencyIdConstraint do
  subject(:constraint) { described_class.new }

  def request_for(client_agency_id)
    instance_double(ActionDispatch::Request, path_parameters: { client_agency_id: client_agency_id })
  end

  it "matches a known partner id (loaded dynamically from the database)" do
    expect(constraint.matches?(request_for("sandbox"))).to be(true)
  end

  it "does not match an unknown partner id" do
    expect(constraint.matches?(request_for("definitely-not-a-partner"))).to be(false)
  end

  it "does not match a blank id" do
    expect(constraint.matches?(request_for(nil))).to be(false)
  end
end
