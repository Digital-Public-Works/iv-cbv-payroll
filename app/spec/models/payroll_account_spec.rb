require "rails_helper"

RSpec.describe PayrollAccount, type: :model do
  describe "report status of a failed sync" do
    let(:payroll_account) { create(:payroll_account, :argyle, synchronization_status: :succeeded, report_status: :useful) }

    it "becomes not useful when the sync fails" do
      payroll_account.update!(synchronization_status: :failed)

      expect(payroll_account.reload).to be_report_not_useful
    end

    it "cannot be saved as useful while the sync is failed" do
      payroll_account.update!(synchronization_status: :failed)
      payroll_account.update!(report_status: :useful)

      expect(payroll_account.reload).to be_report_not_useful
    end

    it "is left alone when the sync has not failed" do
      payroll_account.update!(synchronization_status: :in_progress)

      expect(payroll_account.reload).to be_report_useful
    end
  end
end
