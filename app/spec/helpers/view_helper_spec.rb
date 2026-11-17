require 'rails_helper'

RSpec.describe ViewHelper, type: :helper do
  describe "#switch_locale_link" do
    let(:params) { { controller: "pages", action: "home" } }

    before do
      allow(helper).to receive(:t).and_return("Language Name")
      allow(helper.request).to receive(:params).and_return(ActionController::Parameters.new(params).permit!)
    end

    it "generates a link with the new locale" do
      link = helper.switch_locale_link(:es)
      expect(link).to include("/es")
    end

    it "does not allow host injection via params" do
      malicious_params = params.merge(host: "evil.com")
      allow(helper.request).to receive(:params).and_return(ActionController::Parameters.new(malicious_params).permit!)

      link = helper.switch_locale_link(:es)
      expect(link).not_to include("evil.com")
      expect(link).to include("/es")
    end
  end
end
