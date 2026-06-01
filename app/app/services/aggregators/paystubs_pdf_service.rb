# frozen_string_literal: true

require "combine_pdf"
require "pdf-reader"

# Builds a single combined PDF containing every paystub document linked
# from the report's paystubs (Argyle only — see DEV_NOTES.md). Documents
# are fetched in parallel, filtered to document_type == "paystub", and
# merged in pay_date order.
module Aggregators
  class PaystubsPdfService
    MAX_PARALLEL = 8
    SUPPORTED_DOCUMENT_TYPE = "paystub"
    SUPPORTED_IMAGE_PREFIX = "image/"
    SUPPORTED_PDF_PREFIX = "application/pdf"

    Result = Struct.new(:content, :page_count, :file_size, keyword_init: true)

    class NoPaystubsError < StandardError; end

    def initialize(cbv_flow:, aggregator_report:, argyle_service:)
      @cbv_flow = cbv_flow
      @aggregator_report = aggregator_report
      @argyle_service = argyle_service
    end

    def generate
      refs = collect_document_refs
      raise NoPaystubsError, "no paystubs have a backing payroll_document" if refs.empty?

      docs = fetch_documents_parallel(refs)
      pdf_parts = docs.filter_map { |d| normalize_to_pdf(d) }
      raise NoPaystubsError, "no paystub documents survived filtering" if pdf_parts.empty?

      merged = merge(pdf_parts)
      Result.new(content: merged, page_count: page_count(merged), file_size: merged.bytesize)
    end

    private

    def collect_document_refs
      refs = []
      @aggregator_report.paystubs.each do |paystub|
        if paystub.payroll_document_id.blank?
          Rails.logger.warn(
            "PaystubsPdfService: paystub #{paystub.id} has no payroll_document; skipping"
          )
          next
        end
        refs << {
          paystub_id: paystub.id,
          document_id: paystub.payroll_document_id,
          pay_date: paystub.pay_date
        }
      end
      refs.sort_by { |r| r[:pay_date].to_s }
    end

    def fetch_documents_parallel(refs)
      pool = Concurrent::FixedThreadPool.new([ refs.size, MAX_PARALLEL ].min)
      promises = refs.map do |ref|
        Concurrent::Promises.future_on(pool) { fetch_single(ref) }
      end
      Concurrent::Promises.zip(*promises).value!
    ensure
      pool&.shutdown
      pool&.wait_for_termination(10)
    end

    def fetch_single(ref)
      doc_json = @argyle_service.fetch_payroll_document_api(id: ref[:document_id])
      if doc_json["document_type"] != SUPPORTED_DOCUMENT_TYPE
        Rails.logger.warn(
          "PaystubsPdfService: skipping payroll_document #{ref[:document_id]} " \
          "(type=#{doc_json['document_type']}); only #{SUPPORTED_DOCUMENT_TYPE} is supported"
        )
        return nil
      end

      file_url = doc_json["file_url"]
      if file_url.blank?
        Rails.logger.warn(
          "PaystubsPdfService: payroll_document #{ref[:document_id]} has no file_url; skipping"
        )
        return nil
      end

      bytes, content_type = @argyle_service.fetch_payroll_document_file(file_url: file_url)
      { bytes: bytes, content_type: content_type.to_s, pay_date: ref[:pay_date] }
    end

    def normalize_to_pdf(doc)
      return nil unless doc

      case doc[:content_type]
      when ->(ct) { ct.start_with?(SUPPORTED_PDF_PREFIX) }
        doc[:bytes]
      when ->(ct) { ct.start_with?(SUPPORTED_IMAGE_PREFIX) }
        image_to_pdf(doc[:bytes], doc[:content_type])
      else
        Rails.logger.warn(
          "PaystubsPdfService: skipping document with unsupported content-type=#{doc[:content_type]}"
        )
        nil
      end
    end

    def image_to_pdf(bytes, content_type)
      data_uri = "data:#{content_type};base64,#{Base64.strict_encode64(bytes)}"
      html = <<~HTML
        <html>
          <head>
            <style>
              @page { margin: 0; }
              body { margin: 0; padding: 0; }
              img { width: 100%; height: 100vh; object-fit: contain; display: block; }
            </style>
          </head>
          <body><img src="#{data_uri}" /></body>
        </html>
      HTML
      pdf = WickedPdf.new.pdf_from_string(html)
      return nil if pdf.blank?
      pdf
    rescue => e
      Rails.logger.warn("PaystubsPdfService: image wrap failed (#{e.class}: #{e.message}); skipping page")
      nil
    end

    def merge(pdf_parts)
      combined = CombinePDF.new
      pdf_parts.each { |bytes| combined << CombinePDF.parse(bytes) }
      combined.to_pdf
    end

    def page_count(bytes)
      PDF::Reader.new(StringIO.new(bytes)).page_count
    rescue => e
      Rails.logger.warn("PaystubsPdfService: page count failed: #{e.class}: #{e.message}")
      0
    end
  end
end
