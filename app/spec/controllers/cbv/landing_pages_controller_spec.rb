require "rails_helper"

RSpec.describe Cbv::LandingPagesController do
  let(:cbv_flow) { create(:cbv_flow, :generic) }
  let(:applicant) { cbv_flow.cbv_applicant }

  # The seeded sandbox partner asks for nothing at the landing page by default;
  # these examples configure what each one is about.
  def ask_for(name, required: true, position: 0, regex: nil)
    config = PartnerConfig.find_by(partner_id: "sandbox")
    PartnerAttributeUsage.create!(
      partner_config: config,
      context: PartnerAttributeUsage::LANDING_PAGE,
      name: name,
      required: required,
      position: position
    )
    if regex
      PartnerApplicationAttribute.where(partner_config: config, name: name).update_all(validation_regex: regex)
    end
    ClientAgencyConfig.reset!
  end

  before do
    allow(MixpanelEventTrackingJob).to receive(:perform_later)
    session[:cbv_flow_id] = cbv_flow.id
  end

  describe "#show" do
    render_views

    context "when the partner asks for nothing here" do
      it "passes straight through to the consent page" do
        get :show

        expect(response).to redirect_to(cbv_flow_entry_path)
      end

      it "marks the step complete so the applicant is not bounced back" do
        expect { get :show }.to change { cbv_flow.reload.landing_page_completed_at }.from(nil)
      end
    end

    context "when the partner asks for an attribute the applicant has not supplied" do
      before { ask_for("case_number") }

      it "renders the page with an input for it" do
        get :show

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("case_number")
      end

      it "leaves the step incomplete" do
        get :show

        expect(cbv_flow.reload.landing_page_completed_at).to be_nil
      end
    end

    context "when everything it asks for already has a value" do
      before do
        ask_for("case_number")
        applicant.update!(case_number: "12345678")
      end

      it "still asks, so the applicant can confirm or correct it" do
        get :show

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("12345678")
        expect(cbv_flow.reload.landing_page_completed_at).to be_nil
      end
    end
  end

  describe "#update" do
    before { ask_for("case_number") }

    let(:params) { { cbv_applicant: { cbv_applicant: { case_number: "12345678" } } } }

    # The form is `form_with model: @cbv_applicant`, so a browser posts under the
    # model's param key. Specs that hand-write an agency-suffixed key would pass
    # against a controller that never reads what the form sends.
    it "accepts the scope the rendered form actually posts under" do
      post :update, params: { cbv_applicant: { cbv_applicant: { case_number: "12345678" } } }

      expect(applicant.reload.case_number).to eq("12345678")
      expect(response).to redirect_to(cbv_flow_entry_path)
    end

    it "saves the value and continues to the consent page" do
      post :update, params: params

      expect(applicant.reload.case_number).to eq("12345678")
      expect(response).to redirect_to(cbv_flow_entry_path)
    end

    it "marks the value as applicant-provided" do
      post :update, params: params

      expect(applicant.reload).to be_applicant_provided(:case_number)
    end

    it "marks the step complete" do
      expect { post :update, params: params }
        .to change { cbv_flow.reload.landing_page_completed_at }.from(nil)
    end

    it "rejects a blank required value" do
      post :update, params: { cbv_applicant: { cbv_applicant: { case_number: "" } } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(cbv_flow.reload.landing_page_completed_at).to be_nil
    end

    context "when the attribute has a validation_regex" do
      before { ask_for("beacon_id", position: 1, regex: '\A\d{8}\z') }

      it "rejects a value that does not match" do
        post :update, params: {
          cbv_applicant: { cbv_applicant: { case_number: "12345678", beacon_id: "not-digits" } }
        }

        expect(response).to have_http_status(:unprocessable_content)
        expect(applicant.reload.beacon_id).to be_nil
      end

      it "accepts a value that matches" do
        post :update, params: {
          cbv_applicant: { cbv_applicant: { case_number: "12345678", beacon_id: "87654321" } }
        }

        expect(response).to redirect_to(cbv_flow_entry_path)
        expect(applicant.reload.beacon_id).to eq("87654321")
      end
    end
  end
end
