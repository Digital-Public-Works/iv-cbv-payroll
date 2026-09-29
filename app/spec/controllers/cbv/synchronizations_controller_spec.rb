require 'rails_helper'

RSpec.describe Cbv::SynchronizationsController do
  render_views

  let(:cbv_flow) { create(:cbv_flow, :invited) }
  let(:errored_jobs) { [] }
  let(:payroll_account) { create(:payroll_account, :pinwheel_fully_synced, with_errored_jobs: errored_jobs, cbv_flow: cbv_flow) }
  let(:nonexistent_id) { "nonexistent-id" }

  before do
    session[:cbv_flow_id] = cbv_flow.id
  end

  describe "#show" do
    context "when account exists" do
      it "redirects to the payment details page" do
        get :show, params: { user: { account_id: payroll_account.aggregator_account_id } }

        expect(response).to redirect_to(cbv_flow_payment_details_path(user: { account_id: payroll_account.aggregator_account_id }))
      end
    end

    context "when account doesn't exist" do
      it "renders the page" do
        get :show, params: { user: { account_id: nonexistent_id } }

        expect(response).to be_successful
        expect(response).to render_template(:show)
      end
    end

    context "when account exists and is still syncing" do
      before do
        allow_any_instance_of(PayrollAccount::Pinwheel).to receive(:has_fully_synced?).and_return(false)
      end

      it "renders the header and guidance copy" do
        get :show, params: { user: { account_id: payroll_account.aggregator_account_id } }

        expect(response.body).to include(I18n.t("cbv.synchronizations.status.header"))
        expect(response.body).to include(I18n.t("cbv.synchronizations.status.typical_duration"))
        expect(response.body).to include(I18n.t("cbv.synchronizations.status.keep_window_open"))
      end

      it "renders the indicators in order: personal details, income, employment, paystubs" do
        get :show, params: { user: { account_id: payroll_account.aggregator_account_id } }

        # Visible label text only; the nested usa-sr-only status word is excluded.
        labels = Nokogiri::HTML(response.body).css(".synchronizations-indicator > span").map { |label| label.xpath("text()").text.strip }
        expect(labels).to eq(%w[identity income employment paystubs].map { |key|
          I18n.t("cbv.synchronizations.indicators.#{key}")
        })
      end

      it "gives each indicator a screen-reader status after its label" do
        get :show, params: { user: { account_id: payroll_account.aggregator_account_id } }

        # Pinwheel fully synced factory: the first three jobs succeeded, while paystubs
        # stays in progress because has_fully_synced? is stubbed false.
        statuses = Nokogiri::HTML(response.body).css(".synchronizations-indicator > span").map { |label| label.text.squish }
        expect(statuses).to eq([
          "Personal details, complete",
          "Income, complete",
          "Employment, complete",
          "Paystubs, loading"
        ])
      end

      it "makes each indicator label a polite, atomic live region" do
        get :show, params: { user: { account_id: payroll_account.aggregator_account_id } }

        labels = Nokogiri::HTML(response.body).css(".synchronizations-indicator > span")
        expect(labels.size).to eq(4)
        labels.each do |label|
          expect(label["aria-live"]).to eq("polite")
          expect(label["aria-atomic"]).to eq("true")
        end
      end
    end
  end

  describe "#update" do
    it "does not fire tracking event if its for the polling purposes" do
      expect_any_instance_of(GenericEventTracker).not_to receive(:track)

      patch :update, params: { user: { account_id: payroll_account.aggregator_account_id } }
    end

    context "when account exists and is fully synced" do
      it "redirects to the payment details page" do
        patch :update, params: { user: { account_id: payroll_account.aggregator_account_id } }

        expect(response.body).to include("cbv/payment_details")
        expect(response.body).to include("turbo-stream action=\"redirect\"")
      end
    end

    context "when account exists but is not fully synced" do
      before do
        allow_any_instance_of(PayrollAccount::Pinwheel).to receive(:has_fully_synced?).and_return(false)
      end

      it "continues polling" do
        patch :update, params: { user: { account_id: payroll_account.aggregator_account_id } }

        expect(response.body).to include("turbo-frame id=\"synchronization\"")
      end

      it "morphs the status so spinners keep rotating in sync between polls" do
        patch :update, params: { user: { account_id: payroll_account.aggregator_account_id } }

        stream = Nokogiri::HTML(response.body).at_css("turbo-stream")
        expect(stream["action"]).to eq("replace")
        expect(stream["method"]).to eq("morph")
      end

      it "gives each indicator a stable id for morphing" do
        patch :update, params: { user: { account_id: payroll_account.aggregator_account_id } }

        ids = Nokogiri::HTML(response.body).css(".synchronizations-indicator").map { |indicator| indicator["id"] }
        expect(ids).to eq(%w[identity income employment paystubs].map { |key| "synchronizations-indicator-#{key}" })
      end
    end

    context "when account exists but paystubs synchronization fails" do
      let(:errored_jobs) { [ "paystubs" ] }

      it "redirects to the payment details page" do
        patch :update, params: { user: { account_id: payroll_account.aggregator_account_id } }

        expect(response.body).to include("cbv/payment_details")
        expect(response.body).to include("turbo-stream action=\"redirect\"")
      end
    end

    context "when account doesn't exist" do
      it "continues polling" do
        patch :update, params: { user: { account_id: nonexistent_id } }

        expect(response.body).to include("turbo-frame id=\"synchronization\"")
      end
    end

    context "when payroll_account is nil" do
      before do
        controller.instance_variable_set(:@payroll_account, nil)
      end

      it "renders partial and continues polling" do
        patch :update, params: { user: { account_id: nonexistent_id } }

        expect(response.body).to include("turbo-frame id=\"synchronization\"")
        expect(response.body).not_to include("synchronization_failures")
        expect(response).to render_template(partial: "_status")
      end
    end

    context "when argyle encounters 'accounts.update' system_error webhook" do
      let(:errored_jobs) { [ "accounts" ] }
      let(:payroll_account) { create(:payroll_account, :argyle_fully_synced, :argyle_system_error_encountered, with_errored_jobs: errored_jobs, cbv_flow: cbv_flow) }

      it "redirects to the synchronizations failures page" do
        patch :update, params: { user: { account_id: payroll_account.aggregator_account_id } }

        expect(response.body).to include("cbv/synchronization_failures")
        expect(response.body).to include("turbo-stream action=\"redirect\"")
      end
    end
  end
end
