# frozen_string_literal: true

require "faraday"
require "fileutils"
require "ipaddr"
require "json"
require "uri"

module Aggregators::Sdk
  class ArgyleService
    ENVIRONMENTS = {
      sandbox: {
        base_url: "https://api-sandbox.argyle.com/v2",
        api_key_id: ENV["ARGYLE_API_TOKEN_SANDBOX_ID"],
        api_key_secret: ENV["ARGYLE_API_TOKEN_SANDBOX_SECRET"],
        webhook_secret: ENV["ARGYLE_SANDBOX_WEBHOOK_SECRET"]
      },
      production: {
        base_url: "https://api.argyle.com/v2",
        api_key_id: ENV["ARGYLE_API_TOKEN_ID"],
        api_key_secret: ENV["ARGYLE_API_TOKEN_SECRET"],
        webhook_secret: ENV["ARGYLE_WEBHOOK_SECRET"]
      },
      mock: {
        base_url: "http://localhost:3000",
        api_key_id: "mock",
        api_key_secret: "mock",
        webhook_secret: "mock"
      }
    }

    # See: https://console.argyle.com/flows
    FLOW_ID = "EV7MFL8Y"

    EMPLOYER_SEARCH_ENDPOINT = "employer-search"
    PAYSTUBS_ENDPOINT = "paystubs"
    IDENTITIES_ENDPOINT = "identities"
    USERS_ENDPOINT = "users"
    USER_TOKENS_ENDPOINT = "user-tokens"
    ACCOUNTS_ENDPOINT = "accounts"
    EMPLOYMENTS_ENDPOINT = "employments"
    GIGS_ENDPOINT = "gigs"
    SHIFTS_ENDPOINT = "shifts"
    WEBHOOKS_ENDPOINT = "webhooks"
    PAYROLL_DOCUMENTS_ENDPOINT = "payroll-documents"

    # Timeout (seconds) for retrieving a single paystub document file from the
    # signed storage URL. These downloads can be large, so they get a longer
    # budget than the default 5s API request timeout.
    PAYSTUB_RETRIEVAL_TIMEOUT = 60

    # Upper bound on pages walked by #with_pagination. Argyle terminates a list
    # by omitting `next`; this guards against a response that keeps handing back
    # a cursor forever. Exceeding it raises rather than truncating, so a genuine
    # work history longer than this surfaces instead of being silently cut off.
    MAX_PAGINATION_PAGES = 100

    # Raised when pagination cannot be completed -- a page we cannot safely
    # follow, or more pages than MAX_PAGINATION_PAGES. Partial results would
    # understate a claimant's income, so this surfaces rather than returning a
    # short list that looks complete.
    class PaginationError < StandardError; end

    attr_reader :webhook_secret

    # Factory method to return MockArgyleService when environment is "mock".
    def self.new(environment, api_key_id = nil, api_key_secret = nil, webhook_secret = nil, fixture_user: nil)
      if environment.to_s == "mock" || environment.to_sym == :mock
        require_relative "mock_argyle_service"
        MockArgyleService.allocate.tap do |instance|
          instance.send(:initialize, environment, api_key_id, api_key_secret, webhook_secret, fixture_user: fixture_user)
        end
      else
        super
      end
    end

    def initialize(environment, api_key_id = nil, api_key_secret = nil, webhook_secret = nil, fixture_user: nil)
      # Note: fixture_user is accepted but unused here. It's used by MockArgyleService
      # and needs to be in this signature so the factory method's `super` call works.
      @environment = ENVIRONMENTS.fetch(environment.to_sym) { |env| raise KeyError.new("ArgyleService unknown environment: #{env}") }
      @api_key_id = api_key_id || @environment[:api_key_id]
      @api_key_secret = api_key_secret || @environment[:api_key_secret]
      @webhook_secret = webhook_secret || @environment[:webhook_secret]
      @base_url = @environment[:base_url]

      client_options = {
        request: {
          open_timeout: 5,
          timeout: 5,
          params_encoder: Faraday::FlatParamsEncoder
        },
        url: @base_url,
        headers: {
          "Content-Type" => "application/json"
        }
      }
      @http = Faraday.new(client_options) do |conn|
        conn.set_basic_auth @api_key_id, @api_key_secret
        conn.response :raise_error
        conn.response :json, content_type: "application/json"
        conn.response :logger,
          Rails.logger,
          headers: true,
          bodies: true,
          log_level: :debug
      end
    end

    def get_webhook_subscriptions
      @http.get(build_url(WEBHOOKS_ENDPOINT)).body
    end

    def create_webhook_subscription(events, url, name, config = {})
      payload = {
        events: events,
        name: name,
        url: url,
        config: config.presence,
        secret: @webhook_secret
      }

      @http.post(build_url(WEBHOOKS_ENDPOINT), payload.to_json).body
    end

    def delete_webhook_subscription(id)
      @http.delete(build_url("#{WEBHOOKS_ENDPOINT}/#{id}")).body
    end

    # Search for Argyle employer
    # https://docs.argyle.com/api-reference/employer-search#list
    def employer_search(query, status = %w[healthy issues])
      @http.get(build_url(EMPLOYER_SEARCH_ENDPOINT), { q: query, status: status }).body
    end

    # https://docs.argyle.com/api-reference/users#retrieve
    def fetch_user_api(user:)
      @http.get(build_url("#{USERS_ENDPOINT}/#{user}")).body
    end

    # https://docs.argyle.com/api-reference/identities#list
    def fetch_identities_api(account: nil, user: nil, employment: nil, limit: 10)
      params = {
        account: account,
        user: user,
        employment: employment,
        limit: limit
      }.compact
      @http.get(build_url(IDENTITIES_ENDPOINT), params).body
    end

    # https://docs.argyle.com/api-reference/accounts#list
    # Note: we get all account information from the identities endpoint, so this is not
    # currently used.
    def fetch_accounts_api(user: nil, item: nil, ongoing_refresh_status: nil, limit: 10)
      valid_statuses = %w[idle enabled disabled]
      if ongoing_refresh_status && !valid_statuses.include?(ongoing_refresh_status)
        raise ArgumentError, "Invalid ongoing_refresh_status: #{ongoing_refresh_status}"
      end

      params = {
        user: user,
        item: item,
        ongoing_refresh_status: ongoing_refresh_status,
        limit: limit }.compact

      @http.get(build_url(ACCOUNTS_ENDPOINT), params).body
    end

    # https://docs.argyle.com/api-reference/accounts#retrieve
    def fetch_account_api(account: nil)
      raise ArgumentError, "account is required" if account.nil?
      @http.get(build_url("#{ACCOUNTS_ENDPOINT}/#{account}")).body
    end

    # https://docs.argyle.com/api-reference/users#delete
    def delete_user(argyle_user_id:)
      @http.delete(build_url("#{USERS_ENDPOINT}/#{argyle_user_id}")).body
    end

    # https://docs.argyle.com/api-reference/paystubs#list
    def fetch_paystubs_api(
      account: nil,
      user: nil,
      employment: nil,
      from_start_date: nil,
      to_start_date: nil,
      limit: 200
    )
      params = {
        account: account,
        user: user,
        employment: employment,
        from_start_date: from_start_date,
        to_start_date: to_start_date,
        limit: limit }.compact

      with_pagination(PAYSTUBS_ENDPOINT, params)
    end

    def create_user(cbv_flow_end_user_id = nil)
      params = cbv_flow_end_user_id.present? ? { external_id: cbv_flow_end_user_id } : {}
      @http.post(build_url(USERS_ENDPOINT), params.to_json).body
    end

    # https://docs.argyle.com/api-reference/user-tokens#create
    def create_user_token(user_id)
      @http.post(build_url(USER_TOKENS_ENDPOINT), { user: user_id }.to_json).body
    end

    # https://docs.argyle.com/api-reference/gigs#list
    def fetch_gigs_api(account: nil, user: nil,
                       from_start_datetime: nil,
                       to_start_datetime: nil, limit: 200)
      params = {
        account: account,
        user: user,
        from_start_datetime: from_start_datetime,
        to_start_datetime: to_start_datetime,
        limit: limit }.compact

      with_pagination(GIGS_ENDPOINT, params)
    end

    # https://docs.argyle.com/api-reference/shifts#list
    def fetch_shifts_api(**params)
      @http.get(SHIFTS_ENDPOINT, params).body
    end

    # https://docs.argyle.com/api-reference/employments#list
    # Note: we get all employment information from the identities endpoint, so this is not
    # currently used.
    def fetch_employments_api(user: nil, account: nil)
      raise ArgumentError if user.nil? && account.nil?
      params = { user: user, account: account }.compact
      @http.get(build_url(EMPLOYMENTS_ENDPOINT), params).body
    end

    # https://docs.argyle.com/api-reference/payroll-documents#list
    def fetch_payroll_documents_api(account: nil, user: nil, employment: nil, limit: 200)
      params = { account: account, user: user, employment: employment, limit: limit }.compact
      with_pagination(PAYROLL_DOCUMENTS_ENDPOINT, params)
    end

    # https://docs.argyle.com/api-reference/payroll-documents#retrieve
    def fetch_payroll_document_api(id:)
      @http.get(build_url("#{PAYROLL_DOCUMENTS_ENDPOINT}/#{id}")).body
    end

    # Returns [bytes, content_type] for the file at file_url.
    # Argyle responds with a 302 to a GCS signed URL on a different host.
    # Step 1: authenticated request to get the redirect location.
    # Step 2: unauthenticated request to the signed GCS URL.
    def fetch_payroll_document_file(file_url:)
      # file_url comes from an Argyle response body, and @http carries our API
      # credentials as connection-level basic auth -- which Faraday sends even
      # when handed an absolute URL on another host. Confirm the target really
      # is the Argyle API before attaching them to a request.
      redirect_resp = @http.get(argyle_api_url!(file_url))
      storage_url = redirect_resp.headers["location"]
      raise "fetch_payroll_document_file: no redirect location returned for #{file_url}" if storage_url.blank?

      conn = Faraday.new(request: { timeout: PAYSTUB_RETRIEVAL_TIMEOUT }) do |c|
        c.response :raise_error
      end
      # This connection is deliberately unauthenticated, but the location header
      # is still attacker-influenced, so keep it off internal addresses.
      resp = conn.get(external_storage_url!(storage_url))
      [ resp.body, resp.headers["content-type"] ]
    end

    def build_url(endpoint)
      @http.build_url(endpoint).to_s
    end

    private

    # Pages through an Argyle list endpoint, combining every page's `results`
    # into a single response.
    #
    # The `next` URL in Argyle's response is deliberately NOT dereferenced. It
    # is attacker-influenced data, and requesting it with @http would send our
    # Argyle API credentials (set as connection-level basic auth) to whatever
    # host it names. Instead we take only the opaque `cursor` token out of it
    # and re-issue the request against our own base_url and endpoint, so the
    # scheme, host and path can never be influenced by the response body.
    def with_pagination(endpoint, params = {})
      results = []
      cursor = nil
      pages = 0

      loop do
        # Argyle's own `next` URL carries the cursor alone -- the token already
        # encodes the original filters (limit, user, rowKey, ...) -- so passing
        # `params` again alongside it would be redundant and could conflict.
        page_params = cursor.present? ? { cursor: cursor } : params
        requested_url = build_url(endpoint)
        response = @http.get(requested_url, page_params).body
        results.concat(Array(response["results"]))

        next_url = response["next"]
        warn_on_pagination_path_drift(next_url, requested_url, endpoint)
        cursor = extract_cursor(next_url)

        # A `next` we cannot reduce to a cursor means the response shape changed
        # under us -- a new API version or a new pagination scheme. Stopping
        # quietly here would return a partial page indistinguishable from a
        # complete one, so fail instead.
        if cursor.blank? && next_url.present?
          raise PaginationError,
            "ArgyleService: unusable pagination cursor in #{next_url.inspect} for #{endpoint}"
        end

        break if cursor.blank?

        pages += 1
        if pages >= MAX_PAGINATION_PAGES
          raise PaginationError,
            "ArgyleService: pagination exceeded #{MAX_PAGINATION_PAGES} pages for #{endpoint}; " \
            "refusing to return truncated results"
        end
      end

      { "results" => results, "next" => nil }
    end

    # Pulls just the opaque `cursor` query parameter out of a `next` URL,
    # discarding its scheme, host and path. Returns nil for anything we cannot
    # parse or that carries no cursor, which ends pagination.
    def extract_cursor(next_url)
      return nil if next_url.blank?

      uri = begin
        URI.parse(next_url)
      rescue URI::InvalidURIError
        return nil
      end

      Rack::Utils.parse_nested_query(uri.query.to_s)["cursor"].presence
    end

    # We reuse only the cursor from Argyle's `next` URL, which means a change to
    # its path -- most plausibly a new API version -- would otherwise be
    # discarded without a trace. Surface it so the version bump in
    # ENVIRONMENTS[:base_url] happens deliberately, rather than being noticed
    # later as missing records.
    def warn_on_pagination_path_drift(next_url, requested_url, endpoint)
      return if next_url.blank?

      advertised = begin
        URI.parse(next_url).path.presence
      rescue URI::InvalidURIError
        nil
      end
      return if advertised.blank?

      requested_path = URI.parse(requested_url).path
      return if advertised == requested_path

      message = "ArgyleService: pagination path #{advertised.inspect} differs from requested " \
                "#{requested_path.inspect} for #{endpoint} -- API version drift?"
      Rails.logger.warn(message)
      NewRelic::Agent.notice_error(StandardError.new(message)) if defined?(NewRelic::Agent)
    end

    # Returns url if it addresses the configured Argyle API origin, raising
    # otherwise. Relative paths are resolved against base_url and accepted.
    # Deliberately compares scheme/host/port exactly -- a substring or suffix
    # test admits hosts like "argyle.example.com" and "notargyle.com".
    def argyle_api_url!(url)
      uri = parse_uri!(url)
      base = URI.parse(@base_url)

      # No host means a relative reference; Faraday resolves it against base_url.
      return @http.build_url(url).to_s if uri.host.blank?

      unless uri.userinfo.nil? &&
             uri.scheme == base.scheme &&
             uri.host == base.host &&
             uri.port == base.port
        raise ArgumentError,
          "ArgyleService: refusing to send credentials to non-Argyle host #{uri.host.inspect}"
      end

      uri.to_s
    end

    # Returns url if it is a plain https URL on a public host, raising
    # otherwise. Guards the redirect hop to signed storage, which legitimately
    # leaves the Argyle origin and so cannot be checked against an allowlist.
    #
    # Only IP literals are rejected here; a hostname that resolves to a private
    # address would still pass. Closing that gap requires checking the address
    # at connect time, which is a larger change than this fix.
    def external_storage_url!(url)
      uri = parse_uri!(url)

      unless uri.scheme == "https" && uri.userinfo.nil? && uri.host.present?
        raise ArgumentError, "ArgyleService: refusing to fetch storage URL #{uri.scheme.inspect}"
      end

      literal = begin
        IPAddr.new(uri.host)
      rescue IPAddr::InvalidAddressError
        nil
      end

      if literal && (literal.loopback? || literal.link_local? || literal.private?)
        raise ArgumentError, "ArgyleService: refusing to fetch internal address #{uri.host.inspect}"
      end

      uri.to_s
    end

    def parse_uri!(url)
      URI.parse(url.to_s)
    rescue URI::InvalidURIError
      raise ArgumentError, "ArgyleService: could not parse URL"
    end
  end
end
