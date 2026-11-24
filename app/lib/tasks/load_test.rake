namespace :load_test do
  confirm = lambda do |auto_confirm, prompt|
    next true if auto_confirm == "true"

    print "#{prompt} (y/n): "
    STDIN.gets.to_s.chomp.downcase == "y"
  end

  # Applicants from the given ids that no flow or invitation references anymore.
  orphaned_applicants = lambda do |applicant_ids|
    CbvApplicant
      .where(id: applicant_ids)
      .where.not(id: CbvFlow.where.not(cbv_applicant_id: nil).select(:cbv_applicant_id))
      .where.not(id: CbvFlowInvitation.where.not(cbv_applicant_id: nil).select(:cbv_applicant_id))
  end

  # Delete the CBV flows created by POST /api/load_test/sessions.
  #
  # Only flows tagged with Api::LoadTestSessionsController::LOAD_TEST_DEVICE_ID
  # are touched, so real demo data in the same partner is left alone.
  #
  # Usage:
  #   bin/rails load_test:cleanup_sessions          # prompts before deleting
  #   bin/rails load_test:cleanup_sessions[true]    # no prompt
  desc "Delete CBV flows created by the load-test session endpoint"
  task :cleanup_sessions, [ :auto_confirm ] => :environment do |_t, args|
    flows = CbvFlow.where(device_id: Api::LoadTestSessionsController::LOAD_TEST_DEVICE_ID)
    count = flows.count
    puts "Found #{count} load-test flows"
    next if count.zero?
    next puts("Cancelled") unless confirm.call(args[:auto_confirm], "Delete these flows?")

    flows.in_batches(of: 500) do |batch|
      ActiveRecord::Base.transaction do
        flow_ids = batch.pluck(:id)
        applicant_ids = batch.where.not(cbv_applicant_id: nil).pluck(:cbv_applicant_id)
        # with_discarded: soft-deleted accounts still reference the flow.
        accounts = PayrollAccount.with_discarded.where(cbv_flow_id: flow_ids)
        account_ids = accounts.pluck(:id)

        WebhookEvent.where(payroll_account_id: account_ids).delete_all
        accounts.delete_all
        CbvFlowTransmission.where(cbv_flow_id: flow_ids).delete_all
        CbvFlow.where(id: flow_ids).delete_all
        # Each load-test flow gets its own applicant; delete it once orphaned.
        orphaned_applicants.call(applicant_ids).delete_all
      end
    end

    puts "✓ Deleted #{count} load-test flows"
  end

  # Delete invitations created by loadTestAPI.js (POST /api/v1/invitations).
  #
  # The API test authenticates as one user, so cleanup is scoped to that user's
  # invitations created at or after `since`. Use a dedicated load-test API user
  # so this cannot match real invitations. Invitations that have been opened
  # (have a CBV flow) are skipped.
  #
  # Usage:
  #   bin/rails 'load_test:cleanup_invitations[loadtest@example.com,2026-11-12 09:00]'
  #   bin/rails 'load_test:cleanup_invitations[loadtest@example.com,2026-11-12 09:00,true]'
  desc "Delete invitations created by the load-test API user since a given time"
  task :cleanup_invitations, [ :user_email, :since, :auto_confirm ] => :environment do |_t, args|
    abort "user_email and since are required" if args[:user_email].blank? || args[:since].blank?

    user = User.find_by(email: args[:user_email])
    abort "No user with email #{args[:user_email]}" unless user
    since = Time.zone.parse(args[:since]) or abort("Could not parse since: #{args[:since]}")

    invitations = CbvFlowInvitation
      .where(user_id: user.id)
      .where(created_at: since..)
      .where.not(id: CbvFlow.where.not(cbv_flow_invitation_id: nil).select(:cbv_flow_invitation_id))
    count = invitations.count
    puts "Found #{count} invitations from #{user.email} (#{user.client_agency_id}) since #{since}"
    next if count.zero?
    next puts("Cancelled") unless confirm.call(args[:auto_confirm], "Delete these invitations?")

    invitations.in_batches(of: 1000) do |batch|
      ActiveRecord::Base.transaction do
        applicant_ids = batch.where.not(cbv_applicant_id: nil).pluck(:cbv_applicant_id)
        batch.delete_all
        orphaned_applicants.call(applicant_ids).delete_all
      end
    end

    puts "✓ Deleted #{count} invitations"
  end
end
