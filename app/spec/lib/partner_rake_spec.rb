require "rails_helper"

RSpec.describe "partner.rake" do
  before do
    ActiveJob::Base.queue_adapter = :test
  end

  %w[az_des pa_dhs].each do |partner_id|
    describe "partner:deliver_csv_reports[#{partner_id}]" do
      before do
        Rake::Task["partner:deliver_csv_reports"].reenable
      end

      it "does not enqueue the job when csv_summary_reports_enabled is false" do
        agency = ClientAgencyConfig.instance[partner_id]
        allow(agency).to receive(:transmission_method_configuration).and_return(
          { "csv_summary_reports_enabled" => false }.with_indifferent_access
        )

        expect { Rake::Task["partner:deliver_csv_reports"].invoke(partner_id) }.
          not_to have_enqueued_job(ReportDelivererJob)
      end

      it "enqueues the job when csv_summary_reports_enabled is true" do
        agency = ClientAgencyConfig.instance[partner_id]
        allow(agency).to receive(:transmission_method_configuration).and_return(
          { "csv_summary_reports_enabled" => true }.with_indifferent_access
        )

        expect { Rake::Task["partner:deliver_csv_reports"].invoke(partner_id) }.
          to have_enqueued_job(ReportDelivererJob)
      end
    end
  end
end
