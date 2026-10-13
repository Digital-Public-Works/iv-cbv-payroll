require "rails_helper"

RSpec.describe Cbv::ApplicantInformationsController, type: :controller do
  include ActiveSupport::Testing::TimeHelpers
  describe "#show" do
    let(:cbv_flow) do
      create(:cbv_flow)
    end

    before do
      session[:cbv_flow_id] = cbv_flow.id
    end

    context "when the user is uninvited" do
      let(:cbv_flow) { create(:cbv_flow, cbv_applicant: create(:cbv_applicant, :blank)) }

      render_views

      it "renders the sandbox fields" do
        get :show

        expect(response.body).to include("first_name")
        expect(response.body).to include("middle_name")
        expect(response.body).to include("last_name")
        expect(response.body).to include("date_of_birth")
        expect(response.body).to include("case_number")
      end

      it "stays on the same page and shows the right errors when required fields are missing" do
        post :update, params: {
          cbv_applicant: {
            cbv_applicant: {
              first_name: "Daph", # required
              middle_name: "",
              last_name: nil, # required, nil
              date_of_birth: { month: "", day: "", year: "" }, # required, parses to nil
              case_number: nil # required, nil
            }
          }
        }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).not_to include(I18n.t("cbv.applicant_informations.sandbox.fields.first_name.blank"))
        expect(response.body).not_to include(I18n.t("cbv.applicant_informations.sandbox.fields.middle_name.blank"))
        expect(response.body).to include(I18n.t("cbv.applicant_informations.sandbox.fields.last_name.blank"))
        expect(response.body).to include(I18n.t("cbv.applicant_informations.sandbox.fields.date_of_birth.blank"))
        expect(response.body).to include(I18n.t("cbv.applicant_informations.sandbox.fields.case_number.blank"))
      end

      it "redirects to summary when fields are satisfied" do
        post :update, params: {
          cbv_applicant: {
            cbv_applicant: {
              first_name: "Daph", # required
              middle_name: "",
              last_name: "Gold", # required
              date_of_birth: {
                month: "03",
                day: "19",
                year: "1992"
              }, # required
              case_number: "9971" # required
            }
          }
        }

        expect(response).to redirect_to(cbv_flow_summary_path)
      end

      it "tracks ApplicantSubmittedInformationPage event with identity_age_range_applicant when form is successfully submitted" do
        allow(MixpanelEventTrackingJob).to receive(:perform_later).with("CbvPageView", anything, anything)

        expect(MixpanelEventTrackingJob).to receive(:perform_later).with("ApplicantSubmittedInformationPage", anything, hash_including(
          cbv_flow_id: cbv_flow.id,
          cbv_applicant_id: cbv_flow.cbv_applicant_id,
          client_agency_id: cbv_flow.client_agency_id,
          invitation_id: cbv_flow.cbv_flow_invitation_id,
          identity_age_range_applicant: "30-39"
        ))

        post :update, params: {
          cbv_applicant: {
            cbv_applicant: {
              first_name: "Daph",
              middle_name: "",
              last_name: "Gold",
              date_of_birth: {
                month: "03",
                day: "19",
                year: "1992"
              },
              case_number: "9971"
            }
          }
        }
      end

      it "does not track ApplicantSubmittedInformationPage event when form submission fails" do
        allow(MixpanelEventTrackingJob).to receive(:perform_later).with("CbvPageView", anything, anything)

        expect(MixpanelEventTrackingJob).not_to receive(:perform_later).with("ApplicantSubmittedInformationPage", anything, anything)

        post :update, params: {
          cbv_applicant: {
            cbv_applicant: {
              first_name: "Daph",
              middle_name: "",
              last_name: nil, # required but missing (nil triggers validation)
              date_of_birth: {
                month: "03",
                day: "19",
                year: "1992"
              },
              case_number: "9971"
            }
          }
        }
      end

      it "stays on the page if fields are satisfied and the force_show parameter is present" do
        get :show, params: {
          cbv_applicant: {
            cbv_applicant: {
              first_name: "Daph", # required
              middle_name: "",
              last_name: "Gold", # required
              date_of_birth: {
                month: "01",
                day: "01",
                year: "1980"
              }, # required
              case_number: "9971" # required
            }
          },
          force_show: true
        }

        expect(response.body).to include("first_name")
        expect(response.body).to include("middle_name")
        expect(response.body).to include("last_name")
        expect(response.body).to include("case_number")
      end
    end

    context "when the user is invited" do
      let(:cbv_flow) { create(:cbv_flow, :invited) }

      render_views

      it "redirects to the summary" do
        get :show

        expect(response).to redirect_to(cbv_flow_summary_path)
      end
    end
  end

  describe "the scope the rendered form posts under" do
    let(:cbv_flow) { create(:cbv_flow, cbv_applicant: create(:cbv_applicant, :blank)) }

    before { session[:cbv_flow_id] = cbv_flow.id }

    it "accepts cbv_applicant[cbv_applicant][...] as the browser sends it" do
      post :update, params: {
        cbv_applicant: {
          cbv_applicant: {
            first_name: "Daph",
            last_name: "Gold",
            date_of_birth: { month: "03", day: "19", year: "1992" },
            case_number: "9971"
          }
        }
      }

      expect(cbv_flow.cbv_applicant.reload.case_number).to eq("9971")
      expect(response).to redirect_to(cbv_flow_summary_path)
    end
  end

  describe "required_for_submit attributes" do
    render_views

    let(:cbv_flow) { create(:cbv_flow, cbv_applicant: create(:cbv_applicant, :blank)) }

    before do
      session[:cbv_flow_id] = cbv_flow.id
      config = PartnerConfig.find_by(partner_id: "sandbox")
      # beacon_id is caseworker-only for sandbox, so it is not on the user-input
      # list — marking it required_for_submit must still surface it here.
      PartnerApplicationAttribute.where(partner_config: config, name: "beacon_id")
                                 .update_all(required_for_submit: true)
      ClientAgencyConfig.reset!
    end

    it "shows the field even though the partner does not list it for user input" do
      cbv_flow.cbv_applicant.update!(
        first_name: "Daph", middle_name: "Q", last_name: "Gold",
        date_of_birth: Date.new(1992, 3, 19), case_number: "9971"
      )

      get :show

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("beacon_id")
    end

    it "keeps the applicant on the page while it is blank" do
      post :update, params: {
        cbv_applicant: {
          cbv_applicant: {
            first_name: "Daph",
            last_name: "Gold",
            date_of_birth: { month: "03", day: "19", year: "1992" },
            case_number: "9971"
          }
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "continues once it has a value" do
      post :update, params: {
        cbv_applicant: {
          cbv_applicant: {
            first_name: "Daph",
            last_name: "Gold",
            date_of_birth: { month: "03", day: "19", year: "1992" },
            case_number: "9971",
            beacon_id: "WELID123"
          }
        }
      }

      expect(response).to redirect_to(cbv_flow_summary_path)
    end
  end

  describe "#update age range tracking" do
    let(:cbv_flow) { create(:cbv_flow) }

    before do
      session[:cbv_flow_id] = cbv_flow.id
    end

    it "tracks ApplicantSubmittedInformationPage with the age range derived from the submitted DOB" do
      travel_to Date.new(2025, 1, 1) do
        allow(MixpanelEventTrackingJob).to receive(:perform_later).with("CbvPageView", anything, anything)

        expect(MixpanelEventTrackingJob).to receive(:perform_later).with("ApplicantSubmittedInformationPage", anything, hash_including(
          cbv_flow_id: cbv_flow.id,
          cbv_applicant_id: cbv_flow.cbv_applicant_id,
          client_agency_id: "sandbox",
          invitation_id: cbv_flow.cbv_flow_invitation_id,
          identity_age_range_applicant: "26-29"
        ))

        post :update, params: {
          cbv_applicant: {
            cbv_applicant: {
              first_name: "Daph",
              last_name: "Gold",
              date_of_birth: {
                month: "06",
                day: "15",
                year: "1998"
              },
              case_number: "1234567890123"
            }
          }
        }

        expect(response).to redirect_to(cbv_flow_summary_path)
      end
    end
  end
end
