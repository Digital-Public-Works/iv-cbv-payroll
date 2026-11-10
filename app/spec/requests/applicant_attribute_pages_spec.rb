require "rails_helper"

# End-to-end evaluation of the two applicant-facing attribute pages.
#
# These never hand-write params. Each example renders the real page, reads the
# input names out of the HTML, and posts exactly what a browser would. A spec
# that invents its own param shape passes happily against a controller that
# reads a shape the form never sends — which is precisely how the agency-scoped
# param key (`cbv_applicant_pa_dhs[...]`) stayed broken while green.
RSpec.describe "Applicant attribute pages", type: :request do
  let(:partner) { PartnerConfig.find_by(partner_id: "sandbox") }

  # Replace the seeded sandbox usages with just what an example is about.
  def configure(landing_page: {}, applicant_input_page: {}, required_for_submit: [])
    PartnerAttributeUsage.where(partner_config_id: partner.id).delete_all
    { PartnerAttributeUsage::LANDING_PAGE => landing_page,
      PartnerAttributeUsage::APPLICANT_INPUT_PAGE => applicant_input_page }.each do |context, fields|
      fields.each_with_index do |(name, required), i|
        PartnerAttributeUsage.create!(partner_config: partner, context: context,
                                      name: name.to_s, required: required, position: i)
      end
    end
    partner.partner_application_attributes.update_all(required_for_submit: false)
    if required_for_submit.any?
      partner.partner_application_attributes
             .where(name: required_for_submit.map(&:to_s)).update_all(required_for_submit: true)
    end
    ClientAgencyConfig.reset!
  end

  def set_regex(name, pattern)
    partner.partner_application_attributes.where(name: name.to_s).update_all(validation_regex: pattern)
    ClientAgencyConfig.reset!
  end

  # The form on the page that collects applicant attributes.
  def applicant_form
    Nokogiri::HTML(response.body).css("form").find { |f| f.css("input[name^='cbv_applicant[']").any? }
  end

  # Names of the attribute inputs the page actually rendered.
  def rendered_fields
    form = applicant_form
    return [] if form.nil?

    form.css("input[name^='cbv_applicant[']")
        .filter_map { |i| i["name"][/\[cbv_applicant\]\[([^\[\]]+)\]/, 1] }
        .uniq
  end

  # The value the page prefilled an input with.
  def rendered_value(field)
    applicant_form&.at_css("input[name$='[#{field}]']")&.[]("value")
  end

  # Build the POST body out of the inputs the page actually rendered, filling in
  # `values`, and send it to the action the form names.
  def submit_rendered_form(values)
    form = applicant_form
    raise "no applicant form on the page (status #{response.status})" if form.nil?

    pairs = form.css("input[name]").filter_map do |input|
      name = input["name"]
      next if %w[utf8 authenticity_token commit button].include?(name)
      next if %w[submit button].include?(input["type"])
      next [ name, input["value"].to_s ] if input["type"] == "hidden"

      leaf = name[/\[([^\[\]]+)\]\z/, 1]
      next if leaf.nil?
      parent = name[/\[([^\[\]]+)\]\[[^\[\]]+\]\z/, 1]
      value =
        if values.key?(leaf.to_sym) then values[leaf.to_sym]
        elsif parent && values[parent.to_sym].is_a?(Hash) then values[parent.to_sym][leaf.to_sym]
        end
      [ name, value.to_s ]
    end

    body = pairs.map { |k, v| "#{CGI.escape(k)}=#{CGI.escape(v)}" }.join("&")
    patch form["action"], params: Rack::Utils.parse_nested_query(body)
  end

  def follow_all_redirects!(limit = 10)
    limit.times do
      break unless response.redirect?
      follow_redirect!
    end
    # Paths carry the locale prefix (/en/...); compare on the route itself.
    request.path.sub(%r{\A/(en|es)(?=/)}, "")
  end

  # Clicking the partner's generic link and following it as a browser would.
  # Returns the path the applicant actually lands on.
  def start_generic_flow
    host! "sandbox.verifymyincome.org"
    get "/start"
    follow_all_redirects!
  end

  def applicant
    CbvFlow.last.cbv_applicant.reload
  end

  before do
    stub_client_agency_config_value("sandbox", "agency_domain", "sandbox")
    allow(MixpanelEventTrackingJob).to receive(:perform_later)
  end

  describe "the /start landing page" do
    context "when the partner asks for nothing there" do
      before { configure(landing_page: {}, applicant_input_page: { first_name: true }) }

      it "passes straight through to the consent page" do
        expect(start_generic_flow).to eq("/cbv/entry")
        expect(CbvFlow.last.landing_page_completed_at).to be_present
      end
    end

    context "when the partner asks for a field the applicant has not supplied" do
      before { configure(landing_page: { case_number: true }, applicant_input_page: {}) }

      it "renders that field, and only that field" do
        expect(start_generic_flow).to eq("/cbv/landing_page")

        expect(response).to have_http_status(:ok)
        expect(rendered_fields).to eq(%w[case_number])
      end

      it "saves what the applicant types and moves on to consent" do
        start_generic_flow

        submit_rendered_form(case_number: "123456")

        expect(applicant.case_number).to eq("123456")
        expect(follow_all_redirects!).to eq("/cbv/entry")
        expect(CbvFlow.last.landing_page_completed_at).to be_present
      end

      it "records the value as applicant-provided" do
        start_generic_flow
        submit_rendered_form(case_number: "123456")

        expect(applicant).to be_applicant_provided(:case_number)
      end

      it "keeps the applicant on the page when a required value is blank" do
        start_generic_flow

        submit_rendered_form(case_number: "")

        expect(response).to have_http_status(:unprocessable_content)
        expect(CbvFlow.last.landing_page_completed_at).to be_nil
      end
    end

    context "when the field has a validation_regex" do
      before do
        configure(landing_page: { case_number: true }, applicant_input_page: {})
        set_regex(:case_number, '\A\d{6}\z')
      end

      it "rejects a value that does not match and keeps it off the record" do
        start_generic_flow

        submit_rendered_form(case_number: "12345")

        expect(response).to have_http_status(:unprocessable_content)
        expect(applicant.case_number).to be_nil
      end

      it "accepts a value that matches" do
        start_generic_flow

        submit_rendered_form(case_number: "123456")

        expect(applicant.case_number).to eq("123456")
        expect(follow_all_redirects!).to eq("/cbv/entry")
      end
    end

    context "when the applicant supplied it on an earlier visit" do
      before { configure(landing_page: { case_number: true }, applicant_input_page: {}) }

      # Each visit mints its own invitation and applicant, so nothing is carried
      # over — a matching device cookie does not establish it is the same person.
      it "asks again on a blank form" do
        start_generic_flow
        submit_rendered_form(case_number: "123456")
        follow_all_redirects!

        expect(start_generic_flow).to eq("/cbv/landing_page")
        expect(rendered_fields).to eq(%w[case_number])
        expect(rendered_value("case_number")).to be_blank
      end

      it "does not ask twice within the same flow" do
        start_generic_flow
        submit_rendered_form(case_number: "123456")

        expect(follow_all_redirects!).to eq("/cbv/entry")
      end
    end

    it "is never shown to an invitation flow" do
      configure(landing_page: { case_number: true }, applicant_input_page: {})
      invitation = create(:cbv_flow_invitation, client_agency_id: "sandbox")

      get "/start/#{invitation.auth_token}"

      expect(response).to have_http_status(:ok)
      expect(CbvFlow.last.landing_page_completed_at).to be_nil
    end
  end

  # Each click of a partner's generic link is an independent attempt at a
  # report. Nothing is carried over from a previous visit: new invitation, new
  # applicant record, new flow.
  describe "returning to /start" do
    before { configure(landing_page: { case_number: true }, applicant_input_page: {}) }

    def first_flow
      @first_flow ||= CbvFlow.last
    end

    it "starts a new flow on a new invitation" do
      start_generic_flow
      submit_rendered_form(case_number: "123456")
      follow_all_redirects!
      first_flow

      expect { start_generic_flow }
        .to change(CbvFlow, :count).by(1)
      expect(CbvFlowInvitation.count).to eq(2)

      expect(CbvFlow.last).not_to eq(first_flow)
      expect(CbvFlow.last.cbv_flow_invitation_id).not_to eq(first_flow.cbv_flow_invitation_id)
    end

    it "marks the new flow generic too" do
      start_generic_flow
      submit_rendered_form(case_number: "123456")
      follow_all_redirects!

      start_generic_flow

      expect(CbvFlow.last).to be_generic
    end

    it "gives the new flow its own applicant record" do
      start_generic_flow
      submit_rendered_form(case_number: "123456")
      follow_all_redirects!
      first_flow

      start_generic_flow

      expect(CbvFlow.last.cbv_applicant_id).not_to eq(first_flow.cbv_applicant_id)
      expect(CbvFlow.last.cbv_applicant.case_number).to be_nil
    end

    it "leaves the earlier flow's data untouched" do
      start_generic_flow
      submit_rendered_form(case_number: "123456")
      follow_all_redirects!
      first_flow

      start_generic_flow

      expect(first_flow.cbv_applicant.reload.case_number).to eq("123456")
    end

    it "starts a new flow even when the landing page was never submitted" do
      start_generic_flow
      first_flow

      expect { start_generic_flow }.to change(CbvFlow, :count).by(1)
      expect(CbvFlow.last.cbv_flow_invitation_id).not_to eq(first_flow.cbv_flow_invitation_id)
    end
  end

  describe "the applicant-information page" do
    before { configure(landing_page: {}, applicant_input_page: { first_name: true, middle_name: false }) }

    def reach_applicant_information
      start_generic_flow
      get "/cbv/applicant_information"
    end

    it "renders the fields the partner asks for that are still blank" do
      reach_applicant_information

      expect(response).to have_http_status(:ok)
      expect(rendered_fields).to match_array(%w[first_name middle_name])
    end

    it "shows a value the payroll provider supplied, prefilled and editable" do
      start_generic_flow
      applicant = CbvFlow.last.cbv_applicant
      applicant.first_name = "FromArgyle"
      applicant.record_attribute_provenance([ :first_name ], source: CbvApplicant::PAYROLL_PROVIDER_SOURCE)
      applicant.save!

      get "/cbv/applicant_information"

      expect(rendered_fields).to include("first_name")
      expect(rendered_value("first_name")).to eq("FromArgyle")
    end

    it "re-attributes it to the applicant once they correct it" do
      start_generic_flow
      applicant = CbvFlow.last.cbv_applicant
      applicant.first_name = "FromArgyle"
      applicant.record_attribute_provenance([ :first_name ], source: CbvApplicant::PAYROLL_PROVIDER_SOURCE)
      applicant.save!

      get "/cbv/applicant_information"
      submit_rendered_form(first_name: "Corrected", middle_name: "")

      applicant.reload
      expect(applicant.first_name).to eq("Corrected")
      expect(applicant).to be_applicant_provided(:first_name)
    end

    it "leaves it attributed to the provider when confirmed unchanged" do
      start_generic_flow
      applicant = CbvFlow.last.cbv_applicant
      applicant.first_name = "FromArgyle"
      applicant.record_attribute_provenance([ :first_name ], source: CbvApplicant::PAYROLL_PROVIDER_SOURCE)
      applicant.save!

      get "/cbv/applicant_information"
      submit_rendered_form(first_name: "FromArgyle", middle_name: "")

      applicant.reload
      expect(applicant).not_to be_applicant_provided(:first_name)
      expect(applicant.provenance_for(:first_name)["source"]).to eq("payroll_provider")
    end

    it "does not ask again for a value that is already present" do
      start_generic_flow
      CbvFlow.last.cbv_applicant.update!(first_name: "Daph")

      get "/cbv/applicant_information"

      expect(rendered_fields).to eq(%w[middle_name])
    end

    it "saves the submission and continues to the summary" do
      reach_applicant_information

      submit_rendered_form(first_name: "Daph", middle_name: "Q")

      expect(applicant.first_name).to eq("Daph")
      expect(response).to redirect_to(cbv_flow_summary_path)
      expect(CbvFlow.last.applicant_information_completed_at).to be_present
    end

    it "blocks on a blank required field" do
      reach_applicant_information

      submit_rendered_form(first_name: "", middle_name: "")

      expect(response).to have_http_status(:unprocessable_content)
      expect(CbvFlow.last.applicant_information_completed_at).to be_nil
    end

    context "when nothing is left to collect" do
      before { configure(landing_page: {}, applicant_input_page: {}) }

      it "is skipped, and the step still counts as passed" do
        start_generic_flow

        get "/cbv/applicant_information"

        expect(response).to redirect_to(cbv_flow_summary_path)
        expect(CbvFlow.last.applicant_information_completed_at).to be_present
      end
    end

    context "when an attribute is required_for_submit but not on the user-input list" do
      before do
        configure(landing_page: {}, applicant_input_page: { first_name: true }, required_for_submit: [ :beacon_id ])
      end

      it "is surfaced on the page anyway, so the applicant can supply it" do
        reach_applicant_information

        expect(rendered_fields).to match_array(%w[first_name beacon_id])
      end

      it "blocks the step until it has a value" do
        reach_applicant_information
        submit_rendered_form(first_name: "Daph", beacon_id: "")

        expect(response).to have_http_status(:unprocessable_content)
        expect(CbvFlow.last.applicant_information_completed_at).to be_nil
      end

      it "lets the applicant through once it does" do
        reach_applicant_information
        submit_rendered_form(first_name: "Daph", beacon_id: "WELID1")

        expect(applicant.beacon_id).to eq("WELID1")
        expect(CbvFlow.last.applicant_information_completed_at).to be_present
      end
    end
  end
end
