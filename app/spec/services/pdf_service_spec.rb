require "rails_helper"

RSpec.describe PdfService do
  let(:language)          { :en }
  let(:cbv_flow)          { instance_double("CbvFlow") }
  let(:aggregator_report) { instance_double("AggregatorReport") }
  let(:current_agency)    { instance_double("CurrentAgency") }

  subject(:service) { described_class.new(language: language) }

  let(:controller_double) { instance_double("Cbv::SubmitsController") }
  let(:html_content)      { "<html><body>PDF HTML</body></html>" }

  before do
    allow(Cbv::SubmitsController).to receive(:new).and_return(controller_double)
    allow(controller_double).to receive(:instance_variable_set)
    allow(controller_double).to receive(:render_to_string).and_return(html_content)

    allow(I18n).to receive(:with_locale).and_wrap_original do |orig, *args, &block|
      expect(args.first).to eq(language)
      block.call
    end
  end

  describe "#generate" do
    context "when PDF generation succeeds" do
      let(:pdf_binary)  { "%PDF-1.4 FAKEPDFDATA" }
      let(:page_count)  { 3 }
      let(:pdf_reader)  { instance_double(PDF::Reader, page_count: page_count) }
      let(:wicked_pdf)  { instance_double(WickedPdf) }

      before do
        allow(WickedPdf).to receive(:new).and_return(wicked_pdf)
        allow(wicked_pdf).to receive(:pdf_from_string)
                               .with(html_content)
                               .and_return(pdf_binary)

        allow(PDF::Reader).to receive(:new)
                                .with(instance_of(StringIO))
                                .and_return(pdf_reader)
      end

      it "returns a PdfGenerationResult with the expected attributes" do
        result = service.generate(cbv_flow, aggregator_report, current_agency)

        expect(result).to be_a(described_class::PdfGenerationResult)
        expect(result.content).to eq(pdf_binary)
        expect(result.html).to eq(html_content)
        expect(result.page_count).to eq(page_count)
        expect(result.file_size).to eq(pdf_binary.bytesize)
      end

      it "renders the template with the expected locals and assigns" do
        service.generate(cbv_flow, aggregator_report, current_agency)

        expected_variables = {
          is_caseworker: true,
          cbv_flow: cbv_flow,
          aggregator_report: aggregator_report,
          has_consent: true,
          current_agency: current_agency
        }

        expect(controller_double).to have_received(:instance_variable_set)
                                       .with(:@cbv_flow, cbv_flow)

        expect(controller_double).to have_received(:render_to_string).with(
          template: "cbv/submits/show",
          formats:  [ :pdf ],
          layout:   "layouts/pdf",
          locals:   expected_variables,
          assigns:  expected_variables
        )
      end
    end

    context "when WickedPdf returns empty content" do
      let(:wicked_pdf) { instance_double(WickedPdf) }
      let(:logger)     { instance_double(Logger, debug: nil, error: nil) }

      before do
        allow(WickedPdf).to receive(:new).and_return(wicked_pdf)
        allow(wicked_pdf).to receive(:pdf_from_string).and_return("")
        allow(Rails).to receive(:logger).and_return(logger)
      end

      it "logs an error and returns nil" do
        result = service.generate(cbv_flow, aggregator_report, current_agency)

        expect(result).to be_nil
        expect(logger).to have_received(:debug).with(/PDF content generated/)
        expect(logger).to have_received(:error).with("PDF content is empty or nil")
      end
    end

    context "when an error is raised during PDF generation" do
      let(:wicked_pdf) { instance_double(WickedPdf) }
      let(:logger)     { instance_double(Logger, debug: nil, error: nil) }

      before do
        allow(WickedPdf).to receive(:new).and_return(wicked_pdf)
        allow(wicked_pdf).to receive(:pdf_from_string)
                               .and_raise(StandardError.new("boom"))
        allow(Rails).to receive(:logger).and_return(logger)
      end

      it "logs the error and returns nil" do
        result = service.generate(cbv_flow, aggregator_report, current_agency)

        expect(result).to be_nil
        expect(logger).to have_received(:error).with("Error generating PDF: boom")
      end
    end
  end

  describe PdfService::PdfGenerationResult do
    it "exposes its attributes" do
      content    = "pdf-bytes"
      html       = "<html>stuff</html>"
      page_count = 5
      file_size  = 1234

      result = described_class.new(content, html, page_count, file_size)

      expect(result.content).to eq(content)
      expect(result.html).to eq(html)
      expect(result.page_count).to eq(page_count)
      expect(result.file_size).to eq(file_size)
    end
  end
end
