require "rails_helper"

RSpec.describe Cbv::SuccessesController do
  include PinwheelApiHelper

  describe "#show" do
    let(:cbv_flow) { create(:cbv_flow, :invited, confirmation_code: "ABC12345") }
    let(:cbv_flow_without_invitation) { create(:cbv_flow, confirmation_code: "ABC12345") }
    let(:agency_config) { ClientAgencyConfig.instance["sandbox"] }

    before do
      pinwheel_stub_request_end_user_paystubs_response
      pinwheel_stub_request_end_user_accounts_response
      session[:cbv_flow_id] = cbv_flow.id
    end

    context "when rendering views" do
      render_views

      it "renders properly" do
        get :show
        expect(response).to be_successful
      end

      it "shows confirmation code in view" do
        get :show
        expect(response.body).to include(cbv_flow.confirmation_code)
      end

      it "shows copy link button" do
        get :show
        expect(response.body).to include(I18n.t("cbv.successes.show.copy_link"))
        expect(response.body).to have_selector('button[data-copy-link-target="copyLinkButton"]')
      end

      it "gives the copy link button a descriptive accessible name" do
        get :show
        expect(response.body).to include(I18n.t("cbv.successes.show.copy_link_accessible_context"))
      end

      it "shows the invitation link in a labelled read-only field that is not hidden on small screens" do
        get :show
        page = Nokogiri::HTML(response.body)
        input = page.at_css("input#invitation_link")

        expect(input).to be_present
        expect(input["readonly"]).not_to be_nil
        expect(input["value"]).to include("?origin=shared")
        expect(input["class"].split).not_to include("display-none")
        expect(page.at_css('label[for="invitation_link"]')).to be_present
      end

      it "shows a link to the CBV survey" do
        get :show
        page = Nokogiri::HTML(response.body)
        survey_link = page.at_xpath("//*[normalize-space(text()) = '#{I18n.t("cbv.successes.show.survey")}']")

        expect(survey_link).to be_present
        expect(survey_link["href"]).to eq(feedbacks_path(form: "survey", referer: cbv_flow_success_url))
      end

      it "shows the default what's next copy" do
        get :show
        expect(response.body).to include(I18n.t("cbv.successes.show.whats_next_1_title.default"))
      end

      context "when the agency does not encourage link sharing" do
        before do
          stub_client_agency_config_value("sandbox", "encourage_link_sharing", false)
        end

        it "does not show the share link section" do
          get :show
          expect(response.body).not_to include(I18n.t("cbv.successes.show.share_invitation_link_title"))
          expect(response.body).not_to have_selector('button[data-copy-link-target="copyLinkButton"]')
          expect(response.body).not_to have_selector("input#invitation_link")
        end
      end

      context "when the partner overrides the what's next copy" do
        before do
          partner = PartnerConfig.find_by(partner_id: "sandbox")
          {
            "cbv.successes.show.whats_next_1_title" => "Complete your pre-application.",
            "cbv.successes.show.whats_next_1_li_1" => "Your employment verification is complete.",
            "cbv.successes.show.whats_next_1_li_2_html" => "Go to %{website_link}.",
            "cbv.successes.show.whats_next_1_link_label" => "your profile"
          }.each do |key, value|
            PartnerTranslation.create!(partner_config: partner, locale: "en", key: key, value: value)
          end
          stub_client_agency_config_value("sandbox", "agency_contact_website", "https://example.com/profile")
        end

        it "shows the partner's copy with a link to the configured portal URL" do
          get :show
          page = Nokogiri::HTML(response.body)

          expect(response.body).to include("Complete your pre-application.")
          expect(response.body).to include("Your employment verification is complete.")
          expect(response.body).not_to include(I18n.t("cbv.successes.show.whats_next_1_title.default"))
          link = page.at_css('a[href="https://example.com/profile"]')
          expect(link).to be_present
          expect(link.text).to include("your profile")
        end
      end

      describe "#invitation_link" do
        context "in any environment" do
          before do
            stub_client_agency_config_value("sandbox", "agency_domain", "sandbox")
          end

          it "uses agency demo domain with shared origin" do
            get :show

            expected_url = "https://sandbox.#{ENV["DOMAIN_NAME"]}/en/start/#{cbv_flow.cbv_flow_invitation.auth_token}?origin=shared"
            expect(response.body).to include(expected_url)
          end
        end

        context "in non-production environment" do
          before do
            stub_client_agency_config_value("sandbox", "agency_domain", "demo.divt.app")
          end

          it "uses agency demo domain with shared origin" do
            get :show
            expected_url = "https://demo.divt.app.#{ENV["DOMAIN_NAME"]}/en/start/#{cbv_flow.cbv_flow_invitation.auth_token}?origin=shared"
            expect(response.body).to include(expected_url)
          end
        end

        context "when the cbv_flow originates from a generic link" do
          before do
            session[:cbv_flow_id] = cbv_flow_without_invitation.id
            stub_client_agency_config_value("sandbox", "agency_domain", "demo.divt.app")
          end

          it "generates a simplified generic link with shared origin" do
            get :show

            expected_url = "https://demo.divt.app/en?origin=shared"
            expect(response.body).to include(expected_url)
          end

          context "with missing host configuration" do
            before do
              session[:cbv_flow_id] = cbv_flow_without_invitation.id
              stub_client_agency_config_value("sandbox", "agency_domain", nil)
            end

            it "generates a generic link with shared origin" do
              get :show

              expected_url = "http://localhost/en/cbv/links/sandbox"
              expect(response.body).to include(expected_url)
            end
          end
        end
      end
    end
  end
end
