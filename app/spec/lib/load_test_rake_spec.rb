require "rails_helper"

RSpec.describe "load_test.rake", type: :task do
  let(:load_test_device_id) { Api::LoadTestSessionsController::LOAD_TEST_DEVICE_ID }

  before do
    allow($stdout).to receive(:puts)
    allow($stdout).to receive(:print)
  end

  describe "load_test:cleanup_sessions" do
    before { Rake::Task["load_test:cleanup_sessions"].reenable }

    let!(:load_test_flow) do
      create(:cbv_flow, device_id: load_test_device_id).tap do |flow|
        account = create(:payroll_account, :argyle, cbv_flow: flow)
        create(:webhook_event, payroll_account: account)
        # Discarded (soft-deleted) accounts are hidden by PayrollAccount's
        # default scope but still hold the foreign key to the flow.
        create(:payroll_account, :argyle, cbv_flow: flow).discard!
      end
    end
    let!(:real_flow) { create(:cbv_flow, device_id: "real-device") }

    it "deletes only load-test flows and their dependent rows" do
      applicant_id = load_test_flow.cbv_applicant_id

      Rake::Task["load_test:cleanup_sessions"].invoke("true")

      expect(CbvFlow.exists?(load_test_flow.id)).to be(false)
      expect(PayrollAccount.with_discarded.where(cbv_flow_id: load_test_flow.id)).to be_empty
      expect(CbvApplicant.exists?(applicant_id)).to be(false)
      expect(CbvFlow.exists?(real_flow.id)).to be(true)
      expect(CbvApplicant.exists?(real_flow.cbv_applicant_id)).to be(true)
    end

    it "deletes nothing when not confirmed" do
      allow($stdin).to receive(:gets).and_return("n\n")

      Rake::Task["load_test:cleanup_sessions"].invoke

      expect(CbvFlow.exists?(load_test_flow.id)).to be(true)
    end
  end

  describe "load_test:cleanup_invitations" do
    before { Rake::Task["load_test:cleanup_invitations"].reenable }

    let(:load_test_user) { create(:user) }
    let(:since) { 1.hour.ago }
    let!(:new_invitation) { create(:cbv_flow_invitation, user: load_test_user) }
    let!(:old_invitation) { create(:cbv_flow_invitation, user: load_test_user, created_at: 2.hours.ago) }
    let!(:other_user_invitation) { create(:cbv_flow_invitation) }
    let!(:opened_invitation) do
      create(:cbv_flow_invitation, user: load_test_user).tap do |invitation|
        create(:cbv_flow, cbv_flow_invitation: invitation, cbv_applicant: invitation.cbv_applicant)
      end
    end

    it "deletes the user's unopened invitations created since the given time" do
      applicant_id = new_invitation.cbv_applicant_id

      Rake::Task["load_test:cleanup_invitations"].invoke(load_test_user.email, since.iso8601, "true")

      expect(CbvFlowInvitation.exists?(new_invitation.id)).to be(false)
      expect(CbvApplicant.exists?(applicant_id)).to be(false)
      expect(CbvFlowInvitation.exists?(old_invitation.id)).to be(true)
      expect(CbvFlowInvitation.exists?(other_user_invitation.id)).to be(true)
      expect(CbvFlowInvitation.exists?(opened_invitation.id)).to be(true)
    end
  end
end
