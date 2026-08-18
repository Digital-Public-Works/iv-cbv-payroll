# frozen_string_literal: true

module Aggregators::Sdk
  class MockArgyleService
    attr_reader :webhook_secret

    # Use Bob's fixtures as the default mock data
    MOCK_FIXTURE_USER = "bob"

    # Non-production override so a real CBV flow (which does not pass an explicit
    # fixture_user) can be pointed at a specific demo fixture. Set e.g.
    # MOCK_ARGYLE_FIXTURE_USER=paystubs_some_images before booting the server.
    def initialize(environment, api_key_id = nil, api_key_secret = nil, webhook_secret = nil, fixture_user: nil)
      @environment = ArgyleService::ENVIRONMENTS.fetch(environment.to_sym)
      @webhook_secret = webhook_secret || @environment[:webhook_secret]
      @fixture_user = fixture_user || ENV["MOCK_ARGYLE_FIXTURE_USER"].presence || MOCK_FIXTURE_USER
      @fixture_path = Rails.root.join("spec", "support", "fixtures", "argyle", @fixture_user)
    end

    def fetch_identities_api(account: nil, user: nil, employment: nil, limit: 10)
      load_fixture("request_identity.json")
    end

    def fetch_account_api(account: nil)
      load_fixture("request_account.json")
    end

    def fetch_paystubs_api(account: nil, user: nil, employment: nil, from_start_date: nil, to_start_date: nil, limit: 200)
      filter_results_by_account(load_fixture("request_paystubs.json"), account)
    end

    def fetch_gigs_api(account: nil, user: nil, from_start_datetime: nil, to_start_datetime: nil, limit: 200)
      filter_results_by_account(load_fixture("request_gigs.json"), account)
    end

    def employer_search(query, status = %w[healthy issues])
      load_fixture("request_employer_search.json")
    end

    def fetch_accounts_api(user: nil, item: nil, ongoing_refresh_status: nil, limit: 10)
      load_fixture("request_accounts.json")
    end

    def create_user(cbv_flow_end_user_id = nil)
      load_fixture("../response_create_user.json")
    end

    def create_user_token(user_id)
      load_fixture("../response_create_user_token.json")
    end

    # Webhook methods - return empty/success responses
    def get_webhook_subscriptions
      { "results" => [], "next" => nil }
    end

    def create_webhook_subscription(events, url, name, config = {})
      load_fixture("../response_create_webhook_subscription.json")
    end

    def delete_webhook_subscription(id)
      nil # 204 No Content
    end

    def delete_user(argyle_user_id:)
      nil # 204 No Content
    end

    # Returns payout-statement documents for the given account.
    #
    # A fixture may provide either:
    #   - request_payroll_documents.json (plural): an array (or {"results" => [...]})
    #     of documents, each tagged with an "account" — these ARE filtered by the
    #     requested account, so a multi-employer fixture can expose images for some
    #     accounts and none for others; or
    #   - request_payroll_document.json (singular): a single document returned as-is
    #     (legacy behavior, not filtered by account).
    # A fixture with neither file returns no documents (the no-images case).
    def fetch_payroll_documents_api(account: nil, user: nil, employment: nil, limit: 200)
      plural_path = @fixture_path.join("request_payroll_documents.json")

      if File.exist?(plural_path)
        parsed = JSON.parse(File.read(plural_path))
        docs = parsed.is_a?(Hash) ? (parsed["results"] || []) : Array(parsed)
        docs = docs.select { |d| d["account"] == account } if account.present?
        { "results" => docs, "next" => nil }
      elsif File.exist?(@fixture_path.join("request_payroll_document.json"))
        { "results" => [ load_fixture("request_payroll_document.json") ], "next" => nil }
      else
        { "results" => [], "next" => nil }
      end
    end

    def fetch_payroll_document_api(id:)
      load_fixture("request_payroll_document.json")
    end

    # Returns the bytes of a minimal valid 1-page PDF (checked in as a
    # shared fixture) and a PDF content type. Tests that need a different
    # shape (image content type, multi-page, etc.) should stub this method.
    def fetch_payroll_document_file(file_url:)
      [ File.binread(SHARED_PAYSTUB_PDF_FIXTURE), "application/pdf" ]
    end

    SHARED_PAYSTUB_PDF_FIXTURE = Rails.root.join(
      "spec", "support", "fixtures", "argyle", "shared", "mock_paystub.pdf"
    ).freeze

    private

    # Real Argyle returns only the requested account's records; the fixtures,
    # however, may bundle several accounts in one file. When the requested
    # account matches at least one record, return just that account's records
    # (so multi-employer fixtures partition correctly). Otherwise return the
    # payload untouched — preserving behavior for single-account fixtures and
    # callers that pass no/unknown account.
    def filter_results_by_account(data, account)
      return data unless account.present? && data.is_a?(Hash) && data["results"].is_a?(Array)

      matching = data["results"].select { |record| record["account"] == account }
      return data if matching.empty?

      data.merge("results" => matching)
    end

    def load_fixture(filename)
      file_path = @fixture_path.join(filename)
      JSON.parse(File.read(file_path))
    rescue Errno::ENOENT => e
      Rails.logger.warn "MockArgyleService: Fixture not found: #{file_path}"
      { "results" => [], "next" => nil }
    end
  end
end
