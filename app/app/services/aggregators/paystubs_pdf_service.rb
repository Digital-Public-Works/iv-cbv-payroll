# frozen_string_literal: true

require "combine_pdf"

# Builds a single combined PDF of payout-statement documents for all accounts
# on the CBV flow (Argyle only). Documents are fetched via the payroll-documents
# list endpoint filtered by account ID, then merged in available_date order
# with accounts grouped most-recent-first.
module Aggregators
  class PaystubsPdfService
    MAX_PARALLEL = 3
    SUPPORTED_DOCUMENT_TYPE = "payout-statement"
    SUPPORTED_IMAGE_PREFIX = "image/"
    SUPPORTED_PDF_PREFIX = "application/pdf"

    Result = Struct.new(:content, :page_count, :file_size, keyword_init: true)

    class NoPaystubsError < StandardError; end

    def initialize(cbv_flow:, argyle_service:, current_agency: nil, aggregator_report: nil)
      @cbv_flow = cbv_flow
      @argyle_service = argyle_service
      @current_agency = current_agency
      @aggregator_report = aggregator_report
    end

    def generate
      refs = collect_document_refs
      raise NoPaystubsError, "no payout statement documents found for any account" if refs.empty?

      docs = fetch_documents_parallel(refs)
      pdf_parts = docs.filter_map { |d| normalize_to_pdf(d) }
      raise NoPaystubsError, "no paystub documents survived normalization" if pdf_parts.empty?

      merged = merge(pdf_parts)

      if @current_agency.present? && @aggregator_report.present?
        if (cover = generate_caseworker_cover)
          merged = prepend_pdf(cover, merged)
        end
      end

      Result.new(content: merged, page_count: page_count(merged), file_size: merged.bytesize)
    end

    private

    def accounts_for_service
      @cbv_flow.payroll_accounts.pluck(:aggregator_account_id).compact
    end

    def collect_document_refs
      refs = []
      accounts_for_service.each do |account_id|
        @argyle_service.fetch_payroll_documents_api(account: account_id)["results"]
          .select { |d| d["document_type"] == SUPPORTED_DOCUMENT_TYPE && d["file_url"].present? }
          .each do |doc|
            refs << {
              document_id: doc["id"],
              file_url: doc["file_url"],
              available_date: doc["available_date"],
              account_id: account_id
            }
          end
      end

      refs.group_by { |r| r[:account_id] }
          .transform_values { |group|
            group.sort_by { |r| r[:available_date].present? ? Time.parse(r[:available_date]) : Time.at(0) }
          }
          .sort_by { |_, group|
            group.last[:available_date].present? ? Time.parse(group.last[:available_date]) : Time.at(0)
          }
          .reverse
          .flat_map { |_, group| group }
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
      bytes, content_type = @argyle_service.fetch_payroll_document_file(file_url: ref[:file_url])
      { bytes: bytes, content_type: content_type.to_s }
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

    def generate_caseworker_cover
      employer_names = collect_employer_names
      controller = Cbv::SubmitsController.new
      controller.instance_variable_set(:@current_agency, @current_agency)

      html = controller.render_to_string(
        template: "aggregators/paystubs_pdf/caseworker_cover",
        formats: [ :pdf ],
        layout: "layouts/pdf",
        locals: {
          current_agency: @current_agency,
          cbv_flow: @cbv_flow,
          aggregator_report: @aggregator_report,
          employer_names: employer_names
        }
      )

      WickedPdf.new.pdf_from_string(html).presence
    rescue => e
      Rails.logger.warn("PaystubsPdfService: caseworker cover generation failed (#{e.class}: #{e.message}); skipping")
      nil
    end

    def collect_employer_names
      @aggregator_report.summarize_by_employer
        .select { |_, summary| summary[:paystubs]&.any? { |p| p.payroll_document_id.present? } }
        .filter_map { |_, summary| summary[:employment]&.employer_name }
    end

    def prepend_pdf(front_bytes, back_bytes)
      target = CombinePDF.new
      target << CombinePDF.parse(front_bytes)
      target << CombinePDF.parse(back_bytes)
      target.to_pdf
    end

    def merge(pdf_parts)
      target = CombinePDF.new
      pdf_parts.each { |bytes| target << CombinePDF.parse(bytes) }
      target.to_pdf
    end

    def page_count(bytes)
      CombinePDF.parse(bytes).pages.count
    rescue => e
      Rails.logger.warn("PaystubsPdfService: page count failed: #{e.class}: #{e.message}")
      0
    end
  end
end
