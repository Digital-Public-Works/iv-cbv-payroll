class AddApplicantInformationCompletedAtToCbvFlows < ActiveRecord::Migration[8.1]
  def change
    # Gate for the applicant-information step. Set once the step has been passed,
    # whether the page was rendered or skipped because nothing was missing.
    # UsefulReportValidator results are not acted on until this is present.
    #
    # if_not_exists: an earlier draft of AddGenericFlowFieldsToCbvFlows added
    # this column, so some local databases already have it.
    add_column :cbv_flows, :applicant_information_completed_at, :datetime, if_not_exists: true
  end
end
