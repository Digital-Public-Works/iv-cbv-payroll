require "rails_helper"

RSpec.describe Aggregators::PaystubsPdfService do
  let(:cbv_flow)       { create(:cbv_flow, :invited) }
  let(:argyle_service) { instance_double(Aggregators::Sdk::ArgyleService) }

  let(:sample_pdf_bytes) do
    File.binread(
      Rails.root.join("spec", "support", "fixtures", "argyle", "shared", "mock_paystub.pdf")
    )
  end

  # Create a payroll account with a known ID and attach it to the flow.
  let(:account_id) { "test-acct-1" }
  before do
    create(:payroll_account, :argyle_fully_synced, cbv_flow: cbv_flow, aggregator_account_id: account_id)
  end

  # Returns a payroll-document hash as the list endpoint would.
  def doc(id, available_date:, file_url: "https://example.test/#{id}", document_type: "payout-statement")
    { "id" => id, "document_type" => document_type, "file_url" => file_url, "available_date" => available_date }
  end

  def stub_docs(account:, docs:)
    allow(argyle_service).to receive(:fetch_payroll_documents_api)
      .with(account: account)
      .and_return({ "results" => docs })
  end

  def stub_file(url, bytes: sample_pdf_bytes, content_type: "application/pdf")
    allow(argyle_service).to receive(:fetch_payroll_document_file)
      .with(file_url: url)
      .and_return([ bytes, content_type ])
  end

  subject do
    described_class.new(cbv_flow: cbv_flow, argyle_service: argyle_service)
  end

  describe "#generate" do
    context "happy path: account has valid payout-statement docs" do
      before do
        stub_docs(account: account_id, docs: [
          doc("doc-c", available_date: "2024-03-01T00:00:00Z"),
          doc("doc-a", available_date: "2024-01-01T00:00:00Z"),
          doc("doc-b", available_date: "2024-02-01T00:00:00Z")
        ])
        %w[doc-a doc-b doc-c].each { |id| stub_file("https://example.test/#{id}") }
      end

      it "returns a Result with combined PDF content" do
        result = subject.generate
        expect(result).to be_a(described_class::Result)
        expect(result.content).to start_with("%PDF")
        expect(result.file_size).to eq(result.content.bytesize)
      end

      it "fetches files in available_date ascending order" do
        order = []
        allow(argyle_service).to receive(:fetch_payroll_document_file) do |file_url:|
          order << file_url.split("/").last
          [ sample_pdf_bytes, "application/pdf" ]
        end

        subject.generate
        expect(order).to eq(%w[doc-a doc-b doc-c])
      end

      it "reports a page_count > 0" do
        expect(subject.generate.page_count).to be > 0
      end
    end

    context "with docs from multiple accounts in mixed order" do
      let(:account_id_b) { "test-acct-2" }
      before do
        create(:payroll_account, :argyle_fully_synced, cbv_flow: cbv_flow, aggregator_account_id: account_id_b)

        stub_docs(account: account_id, docs: [
          doc("doc-a3", available_date: "2024-03-01T00:00:00Z"),
          doc("doc-a1", available_date: "2024-01-01T00:00:00Z")
        ])
        stub_docs(account: account_id_b, docs: [
          doc("doc-b2", available_date: "2024-02-01T00:00:00Z"),
          doc("doc-b1", available_date: "2024-01-01T00:00:00Z")
        ])
        %w[doc-a1 doc-a3 doc-b1 doc-b2].each { |id| stub_file("https://example.test/#{id}") }
      end

      it "groups by account (most-recent-doc account first), ascending within group" do
        captured_refs = nil
        allow(subject).to receive(:fetch_documents_parallel) do |refs|
          captured_refs = refs
          refs.map { { bytes: sample_pdf_bytes, content_type: "application/pdf" } }
        end

        subject.generate
        expect(captured_refs.map { |r| r[:document_id] }).to eq(%w[doc-a1 doc-a3 doc-b1 doc-b2])
      end
    end

    context "when no accounts have any payout-statement docs" do
      before do
        stub_docs(account: account_id, docs: [])
      end

      it "raises NoPaystubsError" do
        expect { subject.generate }.to raise_error(described_class::NoPaystubsError)
      end
    end

    context "when docs have wrong document_type or blank file_url" do
      before do
        stub_docs(account: account_id, docs: [
          doc("doc-w2",   available_date: "2024-01-01T00:00:00Z", document_type: "W-2"),
          doc("doc-nurl", available_date: "2024-01-01T00:00:00Z", file_url: ""),
          doc("doc-ok",   available_date: "2024-02-01T00:00:00Z")
        ])
        stub_file("https://example.test/doc-ok")
      end

      it "skips them and still succeeds with the valid doc" do
        result = subject.generate
        expect(result).to be_a(described_class::Result)
        expect(argyle_service).not_to have_received(:fetch_payroll_document_file)
          .with(file_url: "https://example.test/doc-w2")
      end
    end

    context "when every doc is filtered out (all wrong type)" do
      before do
        stub_docs(account: account_id, docs: [
          doc("doc-1", available_date: "2024-01-01T00:00:00Z", document_type: "W-2")
        ])
      end

      it "raises NoPaystubsError" do
        expect { subject.generate }.to raise_error(described_class::NoPaystubsError)
      end
    end

    context "when a file fetch fails" do
      before do
        stub_docs(account: account_id, docs: [
          doc("doc-a", available_date: "2024-01-01T00:00:00Z"),
          doc("doc-b", available_date: "2024-02-01T00:00:00Z")
        ])
        stub_file("https://example.test/doc-a")
        allow(argyle_service).to receive(:fetch_payroll_document_file)
          .with(file_url: "https://example.test/doc-b")
          .and_raise(Faraday::ServerError.new("boom"))
      end

      it "raises so the job retries the whole bundle" do
        expect { subject.generate }.to raise_error(Faraday::ServerError)
      end
    end

    context "with an image content type" do
      let(:image_bytes) { "\x89PNG\r\n\x1a\n".b + ("\x00" * 16) }

      before do
        stub_docs(account: account_id, docs: [
          doc("doc-img", available_date: "2024-01-01T00:00:00Z"),
          doc("doc-pdf", available_date: "2024-02-01T00:00:00Z")
        ])
        stub_file("https://example.test/doc-img", bytes: image_bytes, content_type: "image/png")
        stub_file("https://example.test/doc-pdf")

        wicked = instance_double(WickedPdf)
        allow(WickedPdf).to receive(:new).and_return(wicked)
        allow(wicked).to receive(:pdf_from_string).and_return(sample_pdf_bytes)
      end

      it "wraps the image into a PDF via wicked_pdf" do
        result = subject.generate
        expect(result.content).to start_with("%PDF")
        expect(WickedPdf).to have_received(:new).at_least(:once)
      end
    end

    context "with an unsupported content type" do
      before do
        stub_docs(account: account_id, docs: [
          doc("doc-zip", available_date: "2024-01-01T00:00:00Z"),
          doc("doc-pdf", available_date: "2024-02-01T00:00:00Z")
        ])
        stub_file("https://example.test/doc-zip", content_type: "application/zip", bytes: "PK\x03\x04")
        stub_file("https://example.test/doc-pdf")
      end

      it "skips the unsupported doc and continues" do
        allow(Rails.logger).to receive(:warn)
        result = subject.generate
        expect(result).to be_a(described_class::Result)
        expect(Rails.logger).to have_received(:warn).with(/unsupported content-type=application\/zip/)
      end
    end
  end

  # Coverage for the caseworker cover page (the transmitter path passes
  # current_agency + aggregator_report; the client-download path does not).
  # These let ApplicationController.renderer.render run for real against the
  # actual template + layout — the step the recent change touched — but stub
  # the HTML->PDF conversion so the suite doesn't depend on the wkhtmltopdf
  # binary. A missing helper or a broken layout helper would surface here as a
  # rescued render failure rather than being swallowed silently in production.
  describe "#generate with a caseworker cover page" do
    # The cover template formats consented_to_authorized_use_at unguarded, so
    # the flow needs a consent timestamp for the render to succeed.
    let(:cbv_flow) { create(:cbv_flow, :invited, consented_to_authorized_use_at: 10.minutes.ago) }

    let(:current_agency) do
      instance_double(ClientAgencyConfig::ClientAgency,
        id:        "cover_test",
        logo_path: "https://example.test/logo.png" # URL logo => no asset-pipeline lookup
      ).tap { |a| allow(a).to receive(:present?).and_return(true) }
    end

    let(:aggregator_report) do
      instance_double(Aggregators::AggregatorReports::CompositeReport,
        summarize_by_employer: {},
        from_date:             Date.new(2024, 1, 1),
        to_date:               Date.new(2024, 1, 31)
      ).tap { |r| allow(r).to receive(:present?).and_return(true) }
    end

    let(:service_with_cover) do
      described_class.new(
        cbv_flow:          cbv_flow,
        argyle_service:    argyle_service,
        current_agency:    current_agency,
        aggregator_report: aggregator_report
      )
    end

    def no_cover_page_count
      described_class.new(cbv_flow: cbv_flow, argyle_service: argyle_service).generate.page_count
    end

    before do
      # One real paystub PDF so the merged body has content.
      stub_docs(account: account_id, docs: [ doc("doc-a", available_date: "2024-01-01T00:00:00Z") ])
      stub_file("https://example.test/doc-a")

      # Real HTML render; stub only the HTML->PDF step and capture the HTML.
      wicked = instance_double(WickedPdf)
      allow(WickedPdf).to receive(:new).and_return(wicked)
      allow(wicked).to receive(:pdf_from_string) { |html| @cover_html = html; sample_pdf_bytes }
    end

    it "renders the cover via ApplicationController.renderer and prepends it to the bundle" do
      allow(ApplicationController).to receive(:renderer).and_call_original
      baseline = no_cover_page_count

      result = service_with_cover.generate

      expect(result).to be_a(described_class::Result)
      expect(result.content).to start_with("%PDF")
      expect(result.page_count).to be > baseline                # cover added page(s)
      expect(ApplicationController).to have_received(:renderer)  # used the new render path
      expect(@cover_html).to include("cbv-header__pilot-name")   # the real template rendered
    end

    it "does not silently drop the cover on a successful render" do
      allow(Rails.logger).to receive(:warn)
      service_with_cover.generate
      expect(Rails.logger).not_to have_received(:warn).with(/caseworker cover generation failed/)
    end

    context "when the agency has no logo configured" do
      let(:current_agency) do
        instance_double(ClientAgencyConfig::ClientAgency, id: "cover_test", logo_path: "")
          .tap { |a| allow(a).to receive(:present?).and_return(true) }
      end

      it "still renders the cover via the textual agency-header fallback" do
        allow(Rails.logger).to receive(:warn)
        result = service_with_cover.generate

        expect(result).to be_a(described_class::Result)
        expect(@cover_html).to include("cbv-header__pilot-name")
        expect(Rails.logger).not_to have_received(:warn).with(/caseworker cover generation failed/)
      end
    end

    context "when cover rendering raises" do
      before do
        allow(ApplicationController).to receive(:renderer).and_raise(StandardError.new("render boom"))
        allow(Rails.logger).to receive(:warn)
      end

      it "logs and returns the paystub bundle without the cover" do
        baseline = no_cover_page_count

        result = service_with_cover.generate

        expect(result).to be_a(described_class::Result)
        expect(result.page_count).to eq(baseline) # cover omitted, paystubs intact
        expect(Rails.logger).to have_received(:warn).with(/caseworker cover generation failed/)
      end
    end

    it "does not attempt a cover render when current_agency/aggregator_report are absent" do
      allow(ApplicationController).to receive(:renderer).and_call_original

      described_class.new(cbv_flow: cbv_flow, argyle_service: argyle_service).generate

      expect(ApplicationController).not_to have_received(:renderer)
    end
  end
end
