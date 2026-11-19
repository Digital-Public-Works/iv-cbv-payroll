require "rails_helper"

# One browser, one session, two tabs: invitation A opened first, then
# invitation B (same partner) in another tab. The session now holds B's flow;
# tab A's page still says it's for A (the cbv-flow-id meta tag, sent back as
# X-CBV-Flow-Id). See CbvFlowTabBinding.
RSpec.describe "CBV flow tab binding", type: :request do
  let(:header) { CbvFlowTabBinding::TAB_FLOW_HEADER }
  let(:invitation_a) { create(:cbv_flow_invitation) }
  let(:invitation_b) { create(:cbv_flow_invitation) }
  let!(:flow_a) { open_link(invitation_a) }
  let!(:flow_b) { open_link(invitation_b) }

  # Runs before the let!s above open the links, so they use this host too.
  prepend_before { host! "sandbox.verifymyincome.org" }

  def open_link(invitation, headers: {})
    get "/start/#{invitation.auth_token}", headers: headers
    CbvFlow.where(cbv_flow_invitation: invitation).order(:id).last
  end

  it "renders the flow a page was rendered for into the page" do
    get "/cbv/entry"

    expect(response.body).to include(%(<meta name="cbv-flow-id" content="#{flow_b.id}">))
  end

  # Turbo keeps no copy of flow pages (they hold applicant data, and a
  # restored copy could be for a flow this browser has moved on from)...
  it "turns off Turbo's page cache on flow pages" do
    get "/cbv/entry"

    expect(response.body).to include(%(<meta name="turbo-cache-control" content="no-cache">))
  end

  # ...except the page an invitation link renders: Back to it must not fetch
  # /start/:token again, which would open the invitation again and start
  # another flow.
  it "leaves Turbo's page cache on for the page an invitation link renders" do
    get "/start/#{create(:cbv_flow_invitation).auth_token}"

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("turbo-cache-control")
  end

  # The locale comes from the URL; an unknown one falls back to the default
  # rather than producing a path no route matches.
  it "redirects in a valid language whatever locale the request names" do
    get "/cbv/entry", params: { locale: "zz" }, headers: { header => flow_a.id.to_s }

    expect(response).to redirect_to(cbv_flow_session_switched_path(locale: "en"))
  end

  it "keeps a valid language when redirecting" do
    get "/es/cbv/entry", headers: { header => flow_a.id.to_s }

    expect(response).to redirect_to(cbv_flow_session_switched_path(locale: "es"))
  end

  it "lets the tab whose flow the session holds carry on" do
    get "/cbv/entry", headers: { header => flow_b.id.to_s }

    expect(response).to have_http_status(:ok)
  end

  it "doesn't check requests that come from no page (a typed URL or a refresh)" do
    get "/cbv/entry"

    expect(response).to have_http_status(:ok)
  end

  it "sends the stale tab's page requests to the 'no longer active' page" do
    get "/cbv/entry", headers: { header => flow_a.id.to_s }

    expect(response).to redirect_to(cbv_flow_session_switched_path(locale: "en"))
  end

  it "refuses the stale tab's form submissions without touching either flow" do
    expect {
      patch "/cbv/applicant_information",
            params: { cbv_applicant: { first_name: "Alice" } },
            headers: { header => flow_a.id.to_s }
    }.not_to change { [ flow_a.cbv_applicant.reload.first_name, flow_b.cbv_applicant.reload.first_name ] }

    expect(response).to redirect_to(cbv_flow_session_switched_path(locale: "en"))
    expect(session[:cbv_flow_id]).to eq(flow_b.id)
  end

  # Native form submissions (e.g. employer search after the payroll modal)
  # skip Turbo, so they send the page's flow as a field instead of a header.
  it "refuses a stale page's PDF download" do
    get "/cbv/submit.pdf", params: { cbv_flow_tab_id: flow_a.id }

    expect(response).to redirect_to(cbv_flow_session_switched_path(locale: "en"))
  end

  it "checks the flow sent as a form field too" do
    get "/cbv/synchronizations", params: { user: { account_id: "acct" }, cbv_flow_tab_id: flow_a.id }
    expect(response).to redirect_to(cbv_flow_session_switched_path(locale: "en"))

    get "/cbv/entry", params: { cbv_flow_tab_id: flow_b.id }
    expect(response).to have_http_status(:ok)
  end

  it "answers the stale tab's background poll with a turbo-stream redirect" do
    patch "/cbv/synchronizations",
          headers: { header => flow_a.id.to_s, "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:conflict)

    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(action="redirect"))
    expect(response.body).to include(cbv_flow_session_switched_path)
  end

  it "refuses the stale tab an Argyle token for the other flow" do
    expect_any_instance_of(Aggregators::Sdk::ArgyleService).not_to receive(:create_user)

    post "/api/argyle/tokens", params: { item_id: "item_000012375" }.to_json,
                               headers: { header => flow_a.id.to_s, "Content-Type" => "application/json" }

    expect(response).to redirect_to(cbv_flow_session_switched_path(locale: "en"))
    expect(flow_b.reload.argyle_user_id).to be_nil
  end

  it "still lets a link opened from a stale page start a new flow" do
    invitation_c = create(:cbv_flow_invitation)

    expect { open_link(invitation_c, headers: { header => flow_a.id.to_s }) }.to change(CbvFlow, :count).by(1)

    expect(response).to have_http_status(:ok)
    expect(session[:cbv_flow_id]).to eq(CbvFlow.last.id)
  end

  it "shows the 'no longer active' page without ending the session" do
    get cbv_flow_session_switched_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("cbv.sessions.switched.title"))
    expect(response.body).to include(%(name="turbo-visit-control" content="reload"))
    expect(session[:cbv_flow_id]).to eq(flow_b.id)
  end

  describe "requests that only record analytics" do
    let(:event_logger) { instance_double(GenericEventTracker, track: nil) }

    before { allow(GenericEventTracker).to receive(:new).and_return(event_logger) }

    it "records the stale tab's user events without the other flow's details" do
      post "/api/events/user_action",
           params: { events: { event_name: "ApplicantViewedHelpText", attributes: {} } }.to_json,
           headers: { header => flow_a.id.to_s, "Content-Type" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(event_logger).to have_received(:track)
        .with("ApplicantViewedHelpText", anything, hash_excluding("cbv_flow_id", :cbv_flow_id))
    end

    it "attributes user events to the session's flow for its own tab" do
      post "/api/events/user_action",
           params: { events: { event_name: "ApplicantViewedHelpText", attributes: {} } }.to_json,
           headers: { header => flow_b.id.to_s, "Content-Type" => "application/json" }

      expect(event_logger).to have_received(:track)
        .with("ApplicantViewedHelpText", anything, hash_including(cbv_flow_id: flow_b.id))
    end

    it "records user events when the session's flow no longer exists" do
      flow_b.destroy!

      post "/api/events/user_action",
           params: { events: { event_name: "ApplicantViewedHelpText", attributes: {} } }.to_json,
           headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(event_logger).to have_received(:track)
        .with("ApplicantViewedHelpText", anything, hash_excluding("cbv_flow_id", :cbv_flow_id))
    end
  end

  describe "activity tracking for the timeout" do
    it "records activity on a page request" do
      travel 10.minutes do
        get "/cbv/entry"

        expect(session[:last_seen]).to eq(Time.current.to_i)
      end
    end

    # Only what restarts a tab's browser timer (a full page load) counts, or a
    # single idle tab's timeout could be refused (see Cbv::SessionsController#end).
    it "doesn't count frame loads, prefetches or downloads as activity" do
      before = session[:last_seen]

      travel 10.minutes do
        get "/cbv/entry", headers: { "Turbo-Frame" => "employers" }
        get "/cbv/entry", headers: { "X-Sec-Purpose" => "prefetch" }
        get "/cbv/submit.pdf"

        expect(session[:last_seen]).to eq(before)
      end
    end

    it "doesn't count the synchronizations page's background poll as activity" do
      before = session[:last_seen]

      travel 10.minutes do
        patch "/cbv/synchronizations", headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(session[:last_seen]).to eq(before)
      end
    end
  end
end
