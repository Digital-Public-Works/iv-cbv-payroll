require "rails_helper"

RSpec.describe Aggregators::PaystubsPdfService do
  let(:cbv_flow) { create(:cbv_flow, :invited, :with_argyle_account) }
  let(:argyle_service) { instance_double(Aggregators::Sdk::ArgyleService) }

  # Build a report with three paystubs in non-chronological order so the
  # ordering assertion is meaningful. Each paystub has a backing
  # payroll_document unless overridden.
  let(:aggregator_report) do
    build(:argyle_report, :with_argyle_account).tap do |r|
      r.paystubs = [
        paystub("ps-c", "doc-c", "2024-03-01"),
        paystub("ps-a", "doc-a", "2024-01-01"),
        paystub("ps-b", "doc-b", "2024-02-01")
      ]
    end
  end

  let(:sample_pdf_bytes) do
    File.binread(
      Rails.root.join("spec", "support", "fixtures", "argyle", "shared", "mock_paystub.pdf")
    )
  end

  def paystub(id, doc_id, pay_date)
    Aggregators::ResponseObjects::Paystub.new(
      id: id,
      account_id: "acct",
      pay_date: pay_date,
      payroll_document_id: doc_id
    )
  end

  def stub_document(id, document_type: "paystub", file_url: "https://example.test/#{id}")
    allow(argyle_service)
      .to receive(:fetch_payroll_document_api)
      .with(id: id)
      .and_return(
        "id" => id,
        "document_type" => document_type,
        "file_url" => file_url
      )
  end

  def stub_file(url, bytes: sample_pdf_bytes, content_type: "application/pdf")
    allow(argyle_service)
      .to receive(:fetch_payroll_document_file)
      .with(file_url: url)
      .and_return([ bytes, content_type ])
  end

  subject do
    described_class.new(
      cbv_flow: cbv_flow,
      aggregator_report: aggregator_report,
      argyle_service: argyle_service
    )
  end

  describe "#generate" do
    context "happy path: all paystubs have valid PDF documents" do
      before do
        %w[doc-a doc-b doc-c].each do |id|
          stub_document(id)
          stub_file("https://example.test/#{id}")
        end
      end

      it "returns a Result with combined PDF content" do
        result = subject.generate
        expect(result).to be_a(described_class::Result)
        expect(result.content).to start_with("%PDF")
        expect(result.file_size).to eq(result.content.bytesize)
      end

      it "fetches all documents in pay_date ascending order" do
        order = []
        allow(argyle_service).to receive(:fetch_payroll_document_api) do |id:|
          order << id
          { "id" => id, "document_type" => "paystub", "file_url" => "https://example.test/#{id}" }
        end

        subject.generate
        expect(order).to eq(%w[doc-a doc-b doc-c])
      end

      it "reports a page_count > 0" do
        expect(subject.generate.page_count).to be > 0
      end
    end

    context "when a paystub has no payroll_document_id" do
      before do
        aggregator_report.paystubs[0] = paystub("ps-c", nil, "2024-03-01")
        %w[doc-a doc-b].each do |id|
          stub_document(id)
          stub_file("https://example.test/#{id}")
        end
      end

      it "skips that paystub and logs a warning" do
        allow(Rails.logger).to receive(:warn)
        subject.generate
        expect(Rails.logger).to have_received(:warn).with(/no payroll_document/)
        expect(argyle_service).not_to have_received(:fetch_payroll_document_api).with(id: nil)
      end
    end

    context "when a document is not document_type=paystub" do
      before do
        stub_document("doc-a", document_type: "profile_picture")
        stub_document("doc-b")
        stub_document("doc-c")
        stub_file("https://example.test/doc-b")
        stub_file("https://example.test/doc-c")
      end

      it "skips that document and logs" do
        allow(Rails.logger).to receive(:warn)
        result = subject.generate
        expect(result).to be_a(described_class::Result)
        expect(Rails.logger).to have_received(:warn).with(/type=profile_picture/)
        expect(argyle_service).not_to have_received(:fetch_payroll_document_file).with(
          file_url: "https://example.test/doc-a"
        )
      end
    end

    context "when no paystubs have a backing payroll_document" do
      before do
        aggregator_report.paystubs = aggregator_report.paystubs.map do |p|
          paystub(p.id, nil, p.pay_date)
        end
      end

      it "raises NoPaystubsError" do
        expect { subject.generate }.to raise_error(described_class::NoPaystubsError)
      end
    end

    context "when every doc is filtered out (all wrong type)" do
      before do
        %w[doc-a doc-b doc-c].each do |id|
          stub_document(id, document_type: "profile_picture")
        end
      end

      it "raises NoPaystubsError" do
        expect { subject.generate }.to raise_error(described_class::NoPaystubsError)
      end
    end

    context "when an Argyle fetch fails" do
      before do
        stub_document("doc-a")
        stub_file("https://example.test/doc-a")
        stub_document("doc-b")
        allow(argyle_service)
          .to receive(:fetch_payroll_document_file)
          .with(file_url: "https://example.test/doc-b")
          .and_raise(Faraday::ServerError.new("boom"))
        stub_document("doc-c")
        stub_file("https://example.test/doc-c")
      end

      it "raises so the job retries the whole bundle" do
        expect { subject.generate }.to raise_error(Faraday::ServerError)
      end
    end

    context "with an image content type" do
      let(:image_bytes) { "\x89PNG\r\n\x1a\n".b + ("\x00" * 16) }

      before do
        %w[doc-a doc-b doc-c].each do |id|
          stub_document(id)
        end
        # First doc is an image — wicked_pdf should be invoked to wrap it.
        stub_file("https://example.test/doc-a", bytes: image_bytes, content_type: "image/png")
        stub_file("https://example.test/doc-b")
        stub_file("https://example.test/doc-c")

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
        stub_document("doc-a")
        stub_file("https://example.test/doc-a", content_type: "application/zip", bytes: "PK\x03\x04")
        stub_document("doc-b")
        stub_file("https://example.test/doc-b")
        stub_document("doc-c")
        stub_file("https://example.test/doc-c")
      end

      it "skips the unsupported doc and continues" do
        allow(Rails.logger).to receive(:warn)
        result = subject.generate
        expect(result).to be_a(described_class::Result)
        expect(Rails.logger).to have_received(:warn).with(/unsupported content-type=application\/zip/)
      end
    end
  end
end
