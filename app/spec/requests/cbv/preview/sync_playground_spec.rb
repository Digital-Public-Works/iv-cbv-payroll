require "rails_helper"

RSpec.describe "Sync playground (dev only)", type: :request do
  let(:playground_account) { PayrollAccount::Argyle.order(:created_at).last }

  describe "GET /cbv/preview/sync_playground" do
    it "starts a new sync with every indicator loading, using the real sync partials" do
      expect { get cbv_flow_preview_sync_playground_path }.to change(PayrollAccount::Argyle, :count).by(1)

      expect(response).to have_http_status(:success)
      statuses = Nokogiri::HTML(response.body).css(".synchronizations-indicator > span").map { |label| label.text.squish }
      expect(statuses).to eq([
        "Personal details, loading",
        "Income, loading",
        "Employment, loading",
        "Pay Stubs, loading"
      ])
      expect(session[:cbv_flow_id]).to eq(playground_account.cbv_flow_id)
    end

    it "polls the real sync endpoint by default and the playground endpoint when redirect is off" do
      get cbv_flow_preview_sync_playground_path
      polling = Nokogiri::HTML(response.body).at_css("[data-controller='polling']")
      expect(polling["data-polling-url-value"]).to eq(
        cbv_flow_synchronizations_path(user: { account_id: playground_account.aggregator_account_id })
      )

      get cbv_flow_preview_sync_playground_path(redirect: "0")
      polling = Nokogiri::HTML(response.body).at_css("[data-controller='polling']")
      expect(polling["data-polling-url-value"]).to eq(cbv_flow_preview_sync_playground_poll_path)
    end

    it "starts a fresh sync on every load" do
      get cbv_flow_preview_sync_playground_path
      first_account_id = session[:sync_playground_account_id]

      expect { get cbv_flow_preview_sync_playground_path }.to change(PayrollAccount::Argyle, :count).by(1)
      expect(session[:sync_playground_account_id]).not_to eq(first_account_id)
    end

    context "outside non-production environments" do
      before do
        allow_any_instance_of(Cbv::Preview::SyncPlaygroundController).to receive(:is_not_production?).and_return(false)
      end

      it "is forbidden" do
        get cbv_flow_preview_sync_playground_path

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "POST /cbv/preview/sync_playground/webhook" do
    before { get cbv_flow_preview_sync_playground_path }

    it "completes personal details and income with identities.added" do
      post cbv_flow_preview_sync_playground_webhook_path, params: { event: "identities.added" }

      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(playground_account.reload.job_status("identity")).to eq(:succeeded)
      expect(playground_account.job_status("income")).to eq(:succeeded)
      expect(playground_account.job_status("paystubs")).to eq(:in_progress)
    end

    it "completes employment and paystubs with paystubs.fully_synced" do
      post cbv_flow_preview_sync_playground_webhook_path, params: { event: "paystubs.fully_synced" }

      expect(playground_account.reload.job_status("employment")).to eq(:succeeded)
      expect(playground_account.job_status("paystubs")).to eq(:succeeded)
    end

    it "fails paystubs with paystubs_failed" do
      post cbv_flow_preview_sync_playground_webhook_path, params: { event: "paystubs_failed" }

      expect(playground_account.reload.job_status("paystubs")).to eq(:failed)
      expect(playground_account.job_status("employment")).to eq(:failed)
    end

    it "rejects unknown events" do
      post cbv_flow_preview_sync_playground_webhook_path, params: { event: "accounts.removed" }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /cbv/preview/sync_playground/poll" do
    before do
      get cbv_flow_preview_sync_playground_path
      post cbv_flow_preview_sync_playground_webhook_path, params: { event: "identities.added" }
      post cbv_flow_preview_sync_playground_webhook_path, params: { event: "paystubs.fully_synced" }
    end

    it "morphs the status and never redirects, even once fully synced" do
      2.times { patch cbv_flow_preview_sync_playground_poll_path }

      stream = Nokogiri::HTML(response.body).at_css("turbo-stream")
      expect(stream["action"]).to eq("replace")
      expect(stream["method"]).to eq("morph")
      expect(response.body).not_to include("turbo-stream action=\"redirect\"")
    end

    it "lets the real sync endpoint redirect after showing the completed state for one poll" do
      real_path = cbv_flow_synchronizations_path(user: { account_id: playground_account.aggregator_account_id })

      patch real_path
      expect(response.body).not_to include("turbo-stream action=\"redirect\"")

      patch real_path
      expect(response.body).to include("turbo-stream action=\"redirect\"")
    end
  end

  describe "failed paystubs" do
    it "shows Pay Stubs as unavailable once the sync is done" do
      get cbv_flow_preview_sync_playground_path
      %w[identities.added paystubs_failed].each do |event|
        post cbv_flow_preview_sync_playground_webhook_path, params: { event: event }
      end
      patch cbv_flow_preview_sync_playground_poll_path

      paystubs = Nokogiri::HTML(response.body).at_css("#synchronizations-indicator-paystubs")
      expect(paystubs.at_css("span").text.squish).to eq("Pay Stubs, unavailable")
      expect(paystubs.at_css("use")["xlink:href"]).to include("#priority_high")
    end
  end
end
