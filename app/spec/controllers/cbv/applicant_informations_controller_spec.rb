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

      it "marks the step complete even though the page was never shown" do
        expect { get :show }
          .to change { cbv_flow.reload.applicant_information_completed_at }
          .from(nil)
      end
    end

    context "when the flow began at a generic link" do
      let(:cbv_flow) { create(:cbv_flow, :generic) }

      render_views

      it "shows the page, since an auto-created invitation carries no applicant data" do
        get :show

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("case_number")
      end

      it "asks only for what is still blank" do
        cbv_flow.cbv_applicant.update!(first_name: "Daph")

        get :show

        expect(response.body).not_to include("first_name")
        expect(response.body).to include("last_name")
      end

      it "leaves the step incomplete while data is still missing" do
        get :show

        expect(cbv_flow.reload.applicant_information_completed_at).to be_nil
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

  describe "editing information that is already filled in" do
    # The "edit my information" link on the summary renders every field
    # prefilled, so an unchanged field is posted back along with the edited one.
    let(:cbv_flow) { create(:cbv_flow, :invited) }
    let(:applicant) { cbv_flow.cbv_applicant }

    before { session[:cbv_flow_id] = cbv_flow.id }

    def edit(overrides)
      post :update, params: {
        force_show: "true",
        cbv_applicant: {
          cbv_applicant: {
            first_name: applicant.first_name,
            middle_name: applicant.middle_name,
            last_name: applicant.last_name,
            date_of_birth: { month: "03", day: "19", year: "1992" },
            case_number: applicant.case_number
          }.merge(overrides)
        }
      }
    end

    it "marks a value the applicant changed as applicant-provided" do
      edit(last_name: "Changed")

      expect(applicant.reload).to be_applicant_provided(:last_name)
    end

    it "leaves values the applicant did not touch attributed to whoever supplied them" do
      edit(last_name: "Changed")

      expect(applicant.reload.applicant_provided_attributes).to eq([ "last_name" ])
    end

    it "re-attributes a value that arrived from the payroll sync once the applicant edits it" do
      applicant.update!(first_name: "FromArgyle")

      edit(first_name: "Corrected")

      expect(applicant.reload).to be_applicant_provided(:first_name)
    end

    it "drops the attribution when the applicant clears a value they had supplied" do
      edit(middle_name: "Q")
      expect(applicant.reload).to be_applicant_provided(:middle_name)

      edit(middle_name: "")

      expect(applicant.reload).not_to be_applicant_provided(:middle_name)
      expect(applicant.middle_name).to be_nil
    end

    it "does not re-stamp a value that is resubmitted unchanged" do
      edit(last_name: "Changed")
      first_stamp = applicant.reload.provenance_for(:last_name)["at"]

      travel_to(1.hour.from_now) { edit(last_name: "Changed") }

      expect(applicant.reload.provenance_for(:last_name)["at"]).to eq(first_stamp)
    end
  end

  describe "required_for_submit attributes" do
    render_views

    let(:cbv_flow) { create(:cbv_flow, :generic) }

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

    it "does not let the step complete while it is blank" do
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
      expect(cbv_flow.reload.applicant_information_completed_at).to be_nil
    end

    it "completes the step once it has a value" do
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

      expect(cbv_flow.reload.applicant_information_completed_at).to be_present
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

  describe "#update in a generic flow" do
    let(:cbv_flow) { create(:cbv_flow, :generic) }

    let(:valid_params) do
      {
        cbv_applicant: {
          cbv_applicant: {
            first_name: "Daph",
            middle_name: "",
            last_name: "Gold",
            date_of_birth: { month: "03", day: "19", year: "1992" },
            case_number: "9971"
          }
        }
      }
    end

    before { session[:cbv_flow_id] = cbv_flow.id }

    it "records what the applicant typed as applicant-provided" do
      post :update, params: valid_params

      applicant = cbv_flow.cbv_applicant.reload
      expect(applicant.applicant_provided_attributes)
        .to match_array(%w[first_name last_name date_of_birth case_number])
      expect(applicant.provenance_for(:first_name)["source"]).to eq("applicant")
    end

    it "does not record a field the applicant left blank" do
      post :update, params: valid_params

      expect(cbv_flow.cbv_applicant.reload).not_to be_applicant_provided(:middle_name)
    end

    it "marks the applicant-information step complete" do
      expect { post :update, params: valid_params }
        .to change { cbv_flow.reload.applicant_information_completed_at }
        .from(nil)
    end

    it "records nothing when the submission is rejected" do
      post :update, params: valid_params.deep_merge(
        cbv_applicant: { cbv_applicant: { last_name: nil } }
      )

      expect(cbv_flow.cbv_applicant.reload.applicant_provided_attributes).to be_empty
      expect(cbv_flow.reload.applicant_information_completed_at).to be_nil
    end

    describe "releasing the deferred report validation" do
      let(:validator) { instance_double(DeferredReportValidator, run: result) }
      let(:payroll_account) { create(:payroll_account, :argyle_fully_synced, cbv_flow: cbv_flow) }

      before { allow(DeferredReportValidator).to receive(:new).and_return(validator) }

      context "when nothing usable came back from any account" do
        let(:result) do
          DeferredReportValidator::Result.new(valid_accounts: [], invalid_accounts: [ payroll_account ])
        end

        it "sends the applicant to the validation failure page rather than the summary" do
          payroll_account.update!(synchronization_status: :failed)

          post :update, params: valid_params

          expect(response).to redirect_to(
            cbv_flow_validation_failures_path(user: { account_id: payroll_account.aggregator_account_id })
          )
        end
      end

      context "when at least one account is usable" do
        let(:result) do
          DeferredReportValidator::Result.new(valid_accounts: [ payroll_account ], invalid_accounts: [])
        end

        it "continues to the summary" do
          payroll_account.update!(synchronization_status: :succeeded)

          post :update, params: valid_params

          expect(response).to redirect_to(cbv_flow_summary_path)
        end
      end
    end
  end
end
