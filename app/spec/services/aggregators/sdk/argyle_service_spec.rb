require 'rails_helper'

RSpec.describe Aggregators::Sdk::ArgyleService, type: :service do
  include ArgyleApiHelper

  let(:api_key_secret) { 'api_key_secret' }
  let(:webhook_secret) { 'test_webhook_secret' }
  let(:service) { described_class.new("sandbox", "FAKE_API_KEY", api_key_secret, webhook_secret) }
  let(:account_id) { 'account123' }
  let(:user_id) { 'user123' }

  describe '#initialize' do
    before do
      # Stub out the values in ArgyleService::ENVIRONMENTS with known values we
      # can assert are loaded correctly.
      stub_const("#{described_class}::ENVIRONMENTS", described_class::ENVIRONMENTS.dup.tap do |hash|
        hash[:sandbox][:api_key_secret] = api_key_secret
        hash[:production][:api_key_secret] = "production-#{api_key_secret}"
      end)
    end

    context 'when the environment is sandbox' do
      let(:service) { described_class.new("sandbox") }

      it 'initializes with the correct environment' do
        expect(service.instance_variable_get(:@api_key_secret)).to eq(api_key_secret)
      end
    end

    context 'when the environment is production' do
      let(:service) { described_class.new("production") }

      it 'initializes with the correct environment' do
        expect(service.instance_variable_get(:@api_key_secret)).to eq("production-#{api_key_secret}")
      end
    end
  end

  describe '#fetch_identities_api' do
    let(:requests) { WebMock::RequestRegistry.instance.requested_signatures.hash.keys }

    before do
      argyle_stub_request_identities_response("bob")
    end

    it 'calls the correct endpoint' do
      service.fetch_identities_api
      expect(requests.first.uri.to_s).to include("/v2/identities")
    end

    it 'sets limit of 100 identities by default' do
      service.fetch_identities_api
      expect(requests.first.uri.query).to include("limit=10")
    end

    it 'accepts param account' do
      service.fetch_identities_api(account: account_id)
      expect(requests.first.uri.query).to include("account=account123")
      expect(requests.first.uri.query).to include("limit=10")
    end

    it 'accepts param user' do
      service.fetch_identities_api(user: user_id)
      expect(requests.first.uri.query).to include("user=user123")
      expect(requests.first.uri.query).to include("limit=10")
    end

    it 'accepts multiple params' do
      service.fetch_identities_api(account: account_id, user: user_id, limit: 50)
      expect(requests.first.uri.query).to include("account=account123")
      expect(requests.first.uri.query).to include("user=user123")
      expect(requests.first.uri.query).to include("limit=50")
    end

    it 'returns a non-empty response' do
      response = service.fetch_identities_api
      expect(response).not_to be_empty
      expect(response).to be_an_instance_of(Hash)
      expect(response).to have_key("results")
      expect(response).to have_key("next")
    end

    it 'raises Faraday::ServerError on 500 error' do
      stub_request(:get, "https://api-sandbox.argyle.com/v2/identities?limit=10")
        .to_return(status: 500, body: "", headers: {})

      expect { service.fetch_identities_api }.to raise_error(Faraday::ServerError)
    end
  end

  describe '#fetch_accounts_api' do
    let(:requests) { WebMock::RequestRegistry.instance.requested_signatures.hash.keys }

    before do
      argyle_stub_request_accounts_response("bob")
    end

    it 'calls the correct endpoint' do
      service.fetch_accounts_api
      expect(requests.first.uri.to_s).to include("/v2/accounts")
    end

    it 'sets limit of 10 accounts by default' do
      service.fetch_accounts_api
      expect(requests.first.uri.query).to include("limit=10")
    end

    it 'accepts param user' do
      service.fetch_accounts_api(user: user_id)
      expect(requests.first.uri.query).to include("user=user123")
      expect(requests.first.uri.query).to include("limit=10")
    end

    it 'accepts param ongoing_refresh_status' do
      service.fetch_accounts_api(ongoing_refresh_status: "enabled")
      expect(requests.first.uri.query).to include("ongoing_refresh_status=enabled")
      expect(requests.first.uri.query).to include("limit=10")
    end

    it 'rejects invalid ongoing_refresh_status' do
      expect { service.fetch_accounts_api(ongoing_refresh_status: "invalid_status") }.to raise_error(ArgumentError, "Invalid ongoing_refresh_status: invalid_status")
    end

    it 'accepts multiple params including ongoing_refresh_status' do
      service.fetch_accounts_api(user: user_id, ongoing_refresh_status: "enabled", limit: 50)
      expect(requests.first.uri.query).to include("user=user123")
      expect(requests.first.uri.query).to include("ongoing_refresh_status=enabled")
      expect(requests.first.uri.query).to include("limit=50")
    end

    it 'returns a non-empty response' do
      response = service.fetch_accounts_api
      expect(response).not_to be_empty
      expect(response).to be_an_instance_of(Hash)
      expect(response).to have_key("results")
      expect(response).to have_key("next")
    end

    it 'raises Faraday::ServerError on 500 error' do
      stub_request(:get, "https://api-sandbox.argyle.com/v2/accounts?limit=10")
      .to_return(status: 500, body: "", headers: {})

      expect { service.fetch_accounts_api }.to raise_error(Faraday::ServerError)
    end
  end

  describe '#fetch_account_api' do
    let(:requests) { WebMock::RequestRegistry.instance.requested_signatures.hash.keys }
    let(:account_id) { "019571bc-2f60-3955-d972-dbadfe0913a8" }

    before do
      argyle_stub_request_account_response("bob")
    end

    it 'calls the correct endpoint' do
      service.fetch_account_api(account: account_id)
      expect(requests.first.uri.to_s).to include("/v2/accounts/#{account_id}")
    end

    it 'returns a non-empty response' do
      response = service.fetch_account_api(account: account_id)
      expect(response).not_to be_empty
      expect(response).to be_an_instance_of(Hash)
    end

    it 'raises an ArgumentError' do
      expect { service.fetch_account_api }.to raise_error(ArgumentError, "account is required")
    end

    it 'raises Faraday::ServerError on 500 error' do
      stub_request(:get, "https://api-sandbox.argyle.com/v2/accounts/#{account_id}")
        .to_return(status: 500, body: "", headers: {})

      expect { service.fetch_account_api(account: account_id) }.to raise_error(Faraday::ServerError)
    end
  end

  describe '#fetch_paystubs_api' do
    let(:requests) { WebMock::RequestRegistry.instance.requested_signatures.hash.keys }

    before do
      argyle_stub_request_paystubs_response("bob")
    end

    it 'calls the correct endpoint' do
      service.fetch_paystubs_api
      expect(requests.first.uri.to_s).to include("/v2/paystubs")
    end

    it 'sets limit of 100 paystubs by default' do
      service.fetch_paystubs_api
      expect(requests.first.uri.query).to include("limit=200")
    end

    it 'accepts param account' do
      service.fetch_paystubs_api(account: account_id)
      expect(requests.first.uri.query).to include("account=account123")
      expect(requests.first.uri.query).to include("limit=200")
    end

    it 'accepts param user' do
      service.fetch_paystubs_api(user: user_id)
      expect(requests.first.uri.query).to include("user=user123")
      expect(requests.first.uri.query).to include("limit=200")
    end

    it 'accepts multiple params' do
      service.fetch_paystubs_api(account: account_id, user: user_id, limit: 50)
      expect(requests.first.uri.query).to include("account=account123")
      expect(requests.first.uri.query).to include("user=user123")
      expect(requests.first.uri.query).to include("limit=50")
    end

    it 'returns a non-empty response' do
      response = service.fetch_paystubs_api
      expect(response).not_to be_empty
      expect(response).to be_an_instance_of(Hash)
      expect(response).to have_key("results")
      expect(response).to have_key("next")
    end

    it 'raises Faraday::ServerError on 500 error' do
      stub_request(:get, "https://api-sandbox.argyle.com/v2/paystubs?limit=200")
        .to_return(status: 500, body: "", headers: {})

      expect { service.fetch_paystubs_api }.to raise_error(Faraday::ServerError)
    end

    context "when the response is paginated" do
      before do
        argyle_stub_request_paystubs_response("busy_joe")
      end

      it "fetches multiple pages of records" do
        service.fetch_paystubs_api

        expect(a_request(:get, "https://api-sandbox.argyle.com/v2/paystubs?limit=200"))
          .to have_been_requested

        expect(a_request(:get, %r{/paystubs\?cursor=}))
          .to have_been_requested
      end

      it "returns all records in a big array" do
        # Each page has 5 items
        expect(service.fetch_paystubs_api["results"].length).to eq(10)
      end
    end
  end

  describe '#fetch_employments_api' do
    before do
      argyle_stub_request_employments_response("bob")
    end

    it 'accepts param account' do
      service.fetch_employments_api(account: account_id)
      assert_requested :get, "https://api-sandbox.argyle.com/v2/employments?account=account123"
    end

    it 'accepts param user' do
      service.fetch_employments_api(user: user_id)
      assert_requested :get, "https://api-sandbox.argyle.com/v2/employments?user=user123"
    end

    it 'rejects empty params' do
      expect { service.fetch_employments_api }.to raise_error(ArgumentError)
    end

    it 'returns a non-empty response' do
      response = service.fetch_employments_api(account: account_id)
      expect(response).not_to be_empty
    end

    it 'raises Faraday::ServerError on 500 error' do
      stub_request(:get, "https://api-sandbox.argyle.com/v2/employments?account=account123")
        .to_return(status: 500, body: "", headers: {})

      expect { service.fetch_employments_api(account: account_id) }.to raise_error(Faraday::ServerError)
    end
  end

  describe "#fetch_gigs_api" do
    context "when the response is paginated" do
      before do
        argyle_stub_request_gigs_response("bob")
      end

      it "fetches multiple pages of records" do
        service.fetch_gigs_api

        expect(a_request(:get, "https://api-sandbox.argyle.com/v2/gigs?limit=200"))
          .to have_been_requested

        expect(a_request(:get, %r{/gigs\?cursor=}))
          .to have_been_requested
      end

      it "returns all records in a big array" do
        # Each page has 50 items
        expect(service.fetch_gigs_api["results"].length).to eq(100)
      end
    end
  end

  describe '#create_user' do
    context 'with external_id' do
      let(:external_id) { 'external_123' }

      it 'makes a POST request with external_id' do
        stub = stub_request(:post, "https://api-sandbox.argyle.com/v2/users")
          .with(body: { external_id: external_id }.to_json)
        service.create_user(external_id)
        expect(stub).to have_been_requested
      end
    end

    context 'without external_id' do
      it 'makes a POST request without external_id' do
        stub = stub_request(:post, "https://api-sandbox.argyle.com/v2/users")
        service.create_user
        expect(stub).to have_been_requested
      end
    end
  end

  describe "#employer_search" do
    before do
      argyle_stub_request_employer_search_response("bob")
    end

    it "makes a request with the proper arguments" do
      service.employer_search("walgreens")
      expect(a_request(:get, "https://api-sandbox.argyle.com/v2/employer-search?q=walgreens&status=healthy&status=issues"))
        .to have_been_requested
    end
  end

  describe '#get_webhook_subscriptions' do
    it 'makes a GET request to webhooks endpoint' do
      stub = stub_request(:get, "https://api-sandbox.argyle.com/v2/webhooks")
      service.get_webhook_subscriptions
      expect(stub).to have_been_requested
    end
  end

  describe '#create_webhook_subscription' do
    let(:events) { [ 'users.fully_synced' ] }
    let(:url) { 'https://example.com/webhook' }
    let(:name) { 'Test Webhook' }
    let(:expected_payload) do
      {
        events: events,
        name: name,
        url: url,
        config: nil,
        secret: webhook_secret
      }
    end

    it 'makes a POST request to create webhook subscription with correct payload' do
      stub = stub_request(:post, "https://api-sandbox.argyle.com/v2/webhooks")
        .with(body: expected_payload.to_json)
      service.create_webhook_subscription(events, url, name)
      expect(stub).to have_been_requested
    end
  end

  describe '#delete_webhook_subscription' do
    let(:webhook_id) { '123' }

    it 'makes a DELETE request to remove webhook subscription' do
      stub = stub_request(:delete, "https://api-sandbox.argyle.com/v2/webhooks/#{webhook_id}")
      service.delete_webhook_subscription(webhook_id)
      expect(stub).to have_been_requested
    end
  end

  describe '#delete_argyle_user' do
    let(:argyle_user_id) { '123' }

    it 'makes a DELETE request to remove argyle user' do
      stub = stub_request(:delete, "https://api-sandbox.argyle.com/v2/users/#{argyle_user_id}")
      service.delete_user(argyle_user_id: argyle_user_id)
      expect(stub).to have_been_requested
    end
  end

  # Regression coverage for the pagination SSRF / credential-leak fix. The
  # `next` URL in an Argyle response is attacker-influenced, and @http attaches
  # our API credentials to any absolute URL it is handed, so `next` must never
  # be requested directly -- only its opaque `cursor` token is reused.
  describe 'pagination cursor handling' do
    def stub_first_page_with_next(next_url)
      stub_request(:get, "https://api-sandbox.argyle.com/v2/paystubs?limit=200")
        .to_return(
          status: 200,
          body: { results: [ { id: "page-1" } ], next: next_url }.to_json,
          headers: { 'Content-Type': 'application/json;charset=UTF-8' }
        )
    end

    # Every one of these passed the previous `next_cursor.include?("argyle")`
    # guard, which matched the substring anywhere in the URL.
    [
      "https://evil.example.com/argyle?cursor=abc",
      "https://argyle.evil.example.com/steal?cursor=abc",
      "https://evil.example.com/?x=argyle&cursor=abc",
      "http://argyle.com/downgraded?cursor=abc",
      "http://169.254.169.254/latest/meta-data/?argyle&cursor=abc",
      "https://user:pw@evil.example.com/argyle?cursor=abc"
    ].each do |hostile_url|
      it "does not request the hostile host in #{hostile_url}" do
        stub_first_page_with_next(hostile_url)
        hostile_host = URI.parse(hostile_url).host
        # The cursor token is still reused -- against our own origin.
        stub_request(:get, "https://api-sandbox.argyle.com/v2/paystubs?cursor=abc")
          .to_return(
            status: 200,
            body: { results: [], next: nil }.to_json,
            headers: { 'Content-Type': 'application/json;charset=UTF-8' }
          )

        service.fetch_paystubs_api

        expect(a_request(:get, %r{\Ahttps?://#{Regexp.escape(hostile_host)}})).not_to have_been_requested
      end
    end

    it 'reuses only the cursor token, requesting our own host' do
      stub_first_page_with_next("https://evil.example.com/argyle?cursor=STOLEN-TOKEN")
      page_two = stub_request(:get, "https://api-sandbox.argyle.com/v2/paystubs?cursor=STOLEN-TOKEN")
        .to_return(
          status: 200,
          body: { results: [ { id: "page-2" } ], next: nil }.to_json,
          headers: { 'Content-Type': 'application/json;charset=UTF-8' }
        )

      response = service.fetch_paystubs_api

      expect(page_two).to have_been_requested
      expect(response["results"].map { |r| r["id"] }).to eq([ "page-1", "page-2" ])
    end

    it 'ends pagination normally when next is absent' do
      stub_first_page_with_next(nil)

      expect(service.fetch_paystubs_api["results"].length).to eq(1)
    end

    # Returning a short list that looks complete would understate income, so an
    # advertised page we cannot follow has to surface as an error.
    it 'raises when next carries no cursor parameter' do
      stub_first_page_with_next("https://api-sandbox.argyle.com/v2/paystubs")

      expect { service.fetch_paystubs_api }
        .to raise_error(described_class::PaginationError, /unusable pagination cursor/)
    end

    it 'raises when next is unparseable' do
      stub_first_page_with_next("http://[not-a-url")

      expect { service.fetch_paystubs_api }
        .to raise_error(described_class::PaginationError, /unusable pagination cursor/)
    end

    context 'when Argyle advertises a different API version' do
      let(:drifted) { "https://api-sandbox.argyle.com/v3/paystubs?cursor=V3TOKEN" }

      before do
        stub_first_page_with_next(drifted)
        stub_request(:get, "https://api-sandbox.argyle.com/v2/paystubs?cursor=V3TOKEN")
          .to_return(
            status: 200,
            body: { results: [], next: nil }.to_json,
            headers: { 'Content-Type': 'application/json;charset=UTF-8' }
          )
      end

      it 'warns about the path drift instead of discarding it silently' do
        expect(Rails.logger).to receive(:warn).with(/pagination path "\/v3\/paystubs" differs from requested "\/v2\/paystubs"/)

        service.fetch_paystubs_api
      end

      it 'reports the drift to NewRelic' do
        expect(NewRelic::Agent).to receive(:notice_error)
          .with(an_instance_of(StandardError))

        service.fetch_paystubs_api
      end

      it 'still pins the request to the configured version' do
        service.fetch_paystubs_api

        expect(a_request(:get, "https://api-sandbox.argyle.com/v2/paystubs?cursor=V3TOKEN")).to have_been_requested
        expect(a_request(:get, %r{/v3/})).not_to have_been_requested
      end
    end

    it 'does not warn when the next path matches the request' do
      stub_first_page_with_next("https://api-sandbox.argyle.com/v2/paystubs?cursor=abc")
      stub_request(:get, "https://api-sandbox.argyle.com/v2/paystubs?cursor=abc")
        .to_return(
          status: 200,
          body: { results: [], next: nil }.to_json,
          headers: { 'Content-Type': 'application/json;charset=UTF-8' }
        )
      expect(Rails.logger).not_to receive(:warn)

      service.fetch_paystubs_api
    end

    context 'when the cursor never clears' do
      before do
        stub_const("#{described_class}::MAX_PAGINATION_PAGES", 3)
        stub_first_page_with_next("https://api-sandbox.argyle.com/v2/paystubs?cursor=loop")
        stub_request(:get, "https://api-sandbox.argyle.com/v2/paystubs?cursor=loop")
          .to_return(
            status: 200,
            body: { results: [ { id: "loop" } ], next: "https://api-sandbox.argyle.com/v2/paystubs?cursor=loop" }.to_json,
            headers: { 'Content-Type': 'application/json;charset=UTF-8' }
          )
      end

      it 'raises rather than returning truncated results' do
        expect { service.fetch_paystubs_api }
          .to raise_error(described_class::PaginationError, /exceeded 3 pages/)
      end

      it 'stops requesting once the cap is reached' do
        expect { service.fetch_paystubs_api }.to raise_error(described_class::PaginationError)

        expect(a_request(:get, "https://api-sandbox.argyle.com/v2/paystubs?cursor=loop"))
          .to have_been_made.times(2)
      end
    end
  end

  describe '#fetch_payroll_document_file' do
    let(:argyle_file_url) { "https://api-sandbox.argyle.com/v2/payroll-documents/doc-1/file" }

    def stub_redirect_to(location)
      stub_request(:get, argyle_file_url).to_return(status: 302, headers: { "location" => location })
    end

    it 'follows an Argyle redirect to external signed storage' do
      stub_redirect_to("https://storage.googleapis.com/signed/doc-1.pdf")
      storage = stub_request(:get, "https://storage.googleapis.com/signed/doc-1.pdf")
        .to_return(status: 200, body: "PDFBYTES", headers: { "content-type" => "application/pdf" })

      bytes, content_type = service.fetch_payroll_document_file(file_url: argyle_file_url)

      expect(storage).to have_been_requested
      expect(bytes).to eq("PDFBYTES")
      expect(content_type).to eq("application/pdf")
    end

    it 'refuses to send credentials to a non-Argyle file_url' do
      expect {
        service.fetch_payroll_document_file(file_url: "https://evil.example.com/argyle/file")
      }.to raise_error(ArgumentError, /non-Argyle host/)

      expect(a_request(:get, %r{evil\.example\.com})).not_to have_been_requested
    end

    it 'refuses a redirect to a private address' do
      stub_redirect_to("https://169.254.169.254/latest/meta-data/")

      expect {
        service.fetch_payroll_document_file(file_url: argyle_file_url)
      }.to raise_error(ArgumentError, /internal address/)
    end

    it 'refuses a plaintext redirect' do
      stub_redirect_to("http://storage.googleapis.com/signed/doc-1.pdf")

      expect {
        service.fetch_payroll_document_file(file_url: argyle_file_url)
      }.to raise_error(ArgumentError, /storage URL/)
    end
  end
end
