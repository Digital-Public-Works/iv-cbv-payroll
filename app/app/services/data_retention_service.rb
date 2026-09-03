# Redaction logic

# Invitations are redacted on the next run after their expiration date, which defaults to 10.
# This does man that PII in invitation *may* stay around for 366 days, if a max duration expiration invite is created.

# All cbv flows are redacted on the next run after 7 days, so data may stay around for up to 8 days. argyle connections
# are deleted as part of this redaction.

# there is an 'oops we missed something' at 15 days, and this raises alerts so we can find out what caused it

class DataRetentionService
  # CBV flow recation timeframe
  REDACT_CBV_FLOWS_AFTER = 7.days

  # backstop for anything that was orphaned or not caught when it should have been.
  # note: invitations have their own logic and this backstop is not used for them. the backstop should never find
  # anything, and will log if it does
  REDACT_BACKSTOP = 15.days

  def redact_all!
    redact_invitations
    redact_cbv_flows
    redact_backstop!
  end

  # redact invitations that are past their expiration date. does not redact invitations that have
  # a flow - those are caught and redacted in the cbv flow redaction
  def redact_invitations
    CbvFlowInvitation
      .unstarted
      .unredacted
      .where("expires_at < ?", Time.current)
      .find_each do |cbv_flow_invitation|
        redact_invitation_and_applicant(cbv_flow_invitation)
      end
  end

  # redact flow, delete argyle connections, redact associated records
  def redact_cbv_flows
    CbvFlow
      .unredacted
      .where("created_at < ?", REDACT_CBV_FLOWS_AFTER.ago)
      .includes(:cbv_flow_invitation, :cbv_applicant, :payroll_accounts)
      .find_each do |cbv_flow|
        redact_cbv_flow(cbv_flow)
      end
  end

  # Backstop sweep. Catches non-invitation records older than REDACT_BACKSTOP.
  # A catch here indicates the primary rule failed for that record -- each
  # catch emits a triple-channel warning before redacting, so operators can
  # investigate.
  #
  # Scope (application tier, non-invitation):
  # - CbvFlow rows that escaped #redact_cbv_flows
  # - CbvApplicant rows whose associations are all redacted (or absent) but
  #   the applicant itself was missed by cascade. Applicants with at least
  #   one unredacted association are out of scope -- the association's own
  #   lifecycle drives the applicant's redaction.
  #
  # NOT in scope:
  # - Invitations (variable lifetime up to 366 days; see #redact_invitations).
  # - Infra tier (Aurora PITR, AWS Backup vault, CloudWatch, ALB access logs)
  #   -- handled by AWS retention config.
  def redact_backstop!
    redact_backstop_cbv_flows
    redact_backstop_applicants
  end

  # The set of internal row ids that one manual erasure touches. Used for dry run + verification.
  ManualErasureScope = Struct.new(
    :client_agency_id,
    :applicant_ids,
    :cbv_flow_ids,
    :invitation_ids,
    :payroll_account_ids,
    keyword_init: true
  ) do
    def empty?
      applicant_ids.empty?
    end

    def counts
      {
        applicants: applicant_ids.size,
        cbv_flows: cbv_flow_ids.size,
        invitations: invitation_ids.size,
        payroll_accounts: payroll_account_ids.size
      }
    end
  end

  # Non-destructive. Resolves a partner identifier to the row ids a manual
  # erasure would touch. This will not resolve after redaction, as partner identifier is redacted.
  def self.resolve_manual_erasure(client_agency_id, partner_identifier)
    applicant_ids = CbvApplicant
      .where(client_agency_id: client_agency_id, partner_identifier: partner_identifier)
      .pluck(:id)

    if applicant_ids.empty?
      raise ActiveRecord::RecordNotFound,
        "No CbvApplicant found in client_agency_id=#{client_agency_id.inspect} " \
        "for the supplied partner_identifier (value omitted from this message)"
    end

    erasure_scope(client_agency_id, applicant_ids)
  end

  # Non-destructive. Same shape as .resolve_manual_erasure, built from ids the
  # caller already holds. Ids are re-scoped to the agency, so an id belonging to
  # another agency is dropped rather than redacted by mistake.
  def self.erasure_scope(client_agency_id, applicant_ids)
    applicant_ids = CbvApplicant
      .where(client_agency_id: client_agency_id, id: Array(applicant_ids))
      .pluck(:id)
      .sort

    cbv_flow_ids = CbvFlow.where(cbv_applicant_id: applicant_ids).pluck(:id).sort

    # Every invitation that must end up redacted: those hanging off the
    # applicants directly (including ones that were never opened, which have no
    # flow) plus any reached through a flow.
    invitation_ids = (
      CbvFlowInvitation.where(cbv_applicant_id: applicant_ids).pluck(:id) +
      CbvFlow.where(id: cbv_flow_ids).pluck(:cbv_flow_invitation_id)
    ).compact.uniq.sort

    payroll_account_ids = PayrollAccount
      .with_discarded
      .where(cbv_flow_id: cbv_flow_ids)
      .pluck(:id)
      .sort

    ManualErasureScope.new(
      client_agency_id: client_agency_id,
      applicant_ids: applicant_ids,
      cbv_flow_ids: cbv_flow_ids,
      invitation_ids: invitation_ids,
      payroll_account_ids: payroll_account_ids
    )
  end

  # Redact every record belonging to the given CbvApplicant ids. Irreversible.
  #
  # Safe to re-run with the same ids: redaction overwrites columns with fixed
  # replacement values and never rewrites the ids themselves, so a retry after a
  # partial failure reaches exactly the same rows. This is why the destructive
  # step takes ids rather than the partner identifier -- redacting by identifier
  # destroys the only handle on the records it failed to redact.
  #
  # Returns { scope:, attempted:, argyle: }. `attempted` counts the records this
  # run TRIED to redact, not the ones it succeeded on: in production the
  # underlying redaction reports failures rather than raising. Use
  # .verify_erasure for the outcome.
  def self.redact_applicant_ids!(client_agency_id, applicant_ids)
    scope = erasure_scope(client_agency_id, applicant_ids)

    if scope.empty?
      raise ActiveRecord::RecordNotFound,
        "No CbvApplicant in client_agency_id=#{client_agency_id.inspect} " \
        "matched ids #{Array(applicant_ids).inspect}"
    end

    service = new
    attempted = { applicants: 0, cbv_flows: 0, invitations_without_flows: 0 }
    argyle = Hash.new(0)

    CbvApplicant.where(id: scope.applicant_ids).find_each do |applicant|
      attempted[:applicants] += 1

      applicant.cbv_flows.each do |cbv_flow|
        attempted[:cbv_flows] += 1
        argyle[service.redact_cbv_flow(cbv_flow)] += 1
      end

      # An invitation that was created but never opened has no flow, so the loop
      # above never reaches it and the erasure request would be silently
      # unsatisfied.
      applicant.cbv_flow_invitations.each do |invitation|
        next if invitation.cbv_flows.any?

        attempted[:invitations_without_flows] += 1
        service.redact_invitation_and_applicant(invitation)
      end
    end

    { scope: scope, attempted: attempted, argyle: argyle }
  end

  # Non-destructive. Re-reads every row in the scope and reports how many carry a
  # redacted_at stamp, as { key => [ redacted, expected ] }.
  #
  # Invitations and payroll accounts are counted in their own right rather than
  # inferred from the flow count. A never-opened invitation is redacted on a
  # separate code path, and in production a failure there is reported rather than
  # raised -- so an applicant that also has a flow would otherwise show as fully
  # redacted while its unopened invitation still held an email address and auth
  # token.
  def self.verify_erasure(scope)
    {
      applicants: [
        CbvApplicant.where(id: scope.applicant_ids).redacted.count,
        scope.applicant_ids.size
      ],
      cbv_flows: [
        CbvFlow.where(id: scope.cbv_flow_ids).redacted.count,
        scope.cbv_flow_ids.size
      ],
      invitations: [
        CbvFlowInvitation.where(id: scope.invitation_ids).redacted.count,
        scope.invitation_ids.size
      ],
      payroll_accounts: [
        PayrollAccount.with_discarded.where(id: scope.payroll_account_ids).where.not(redacted_at: nil).count,
        scope.payroll_account_ids.size
      ]
    }
  end

  def self.erasure_verified?(verification)
    verification.values.all? { |redacted, expected| redacted >= expected }
  end

  # Redact an invitation + its applicant. Used by #redact_invitations (primary),
  # the invitation-backstop path, and the manual erasure path. Wrapped to share
  # the prod error-swallow semantics consistently.
  #
  # Public rather than private: the manual erasure path is a legitimate caller,
  # and reaching it through #send would break silently on a rename.
  def redact_invitation_and_applicant(cbv_flow_invitation)
    cbv_flow_invitation.redact!
    cbv_flow_invitation.cbv_applicant&.redact!
  rescue => ex
    raise ex unless Rails.env.production?

    report_redaction_failure(ex,
      cbv_flow_invitation_id: cbv_flow_invitation.id,
      client_agency_id: cbv_flow_invitation.client_agency_id
    )
  end

  # Do all redaction necessary on a cbv_flow. Argyle user deletion runs
  # first; if it fails for non-404 reasons, prod swallows + reports.
  # Local cascade: invitation -> applicant -> payroll_accounts -> flow,
  # with the flow's redacted_at stamped last so a partial failure leaves
  # the flow eligible to retry on the next daily sweep.
  #
  # Returns the Argyle deletion outcome (:deleted, :already_deleted,
  # :not_applicable or :failed). Argyle is a third party: a failure there leaves
  # nothing in our own tables for .verify_erasure to find, so the manual path
  # needs the outcome reported back rather than only logged.
  def redact_cbv_flow(cbv_flow)
    argyle_outcome =
      if cbv_flow.argyle_user_id.present?
        delete_argyle_user(cbv_flow.client_agency_id, cbv_flow.argyle_user_id)
      else
        :not_applicable
      end

    begin
      cbv_flow.cbv_flow_invitation.redact! if cbv_flow.cbv_flow_invitation.present?
      cbv_flow.cbv_applicant&.redact!
      cbv_flow.payroll_accounts.with_discarded.each(&:redact!) # Do not scope to kept records, all accounts should be redacted
      cbv_flow.redact!
    rescue => ex
      raise ex unless Rails.env.production?

      report_redaction_failure(ex,
        cbv_flow_id: cbv_flow.id,
        client_agency_id: cbv_flow.client_agency_id
      )
    end

    argyle_outcome
  end

  private

  # Backstop: CbvFlows older than 30 days that escaped #redact_cbv_flows.
  def redact_backstop_cbv_flows
    CbvFlow
      .unredacted
      .where("created_at < ?", REDACT_BACKSTOP.ago)
      .includes(:cbv_flow_invitation, :cbv_applicant, :payroll_accounts)
      .find_each do |cbv_flow|
        report_backstop_hit("CbvFlow",
          cbv_flow_id: cbv_flow.id,
          client_agency_id: cbv_flow.client_agency_id,
          created_at: cbv_flow.created_at
        )
        redact_cbv_flow(cbv_flow)
      end
  end

  # Backstop: CbvApplicants older than REDACT_BACKSTOP whose associations
  # are all redacted (or absent). An applicant with at least one unredacted
  # association (invitation OR flow) is NOT caught here -- that association
  # is driving its own redaction lifecycle. This prevents a false-positive
  # when an applicant is tied to a long-lived invitation (up to 366 days).
  def redact_backstop_applicants
    CbvApplicant
      .unredacted
      .where("created_at < ?", REDACT_BACKSTOP.ago)
      .where.not(id: CbvFlowInvitation.unredacted.select(:cbv_applicant_id))
      .where.not(id: CbvFlow.unredacted.select(:cbv_applicant_id))
      .find_each do |applicant|
        report_backstop_hit("CbvApplicant",
          cbv_applicant_id: applicant.id,
          client_agency_id: applicant.client_agency_id,
          created_at: applicant.created_at
        )
        begin
          applicant.redact!
        rescue => ex
          raise ex unless Rails.env.production?

          report_redaction_failure(ex,
            cbv_applicant_id: applicant.id,
            client_agency_id: applicant.client_agency_id
          )
        end
      end
  end

  # Backstop warning. Hitting the backstop means a primary rule failed
  # for this record -- emit on all three channels (log + NewRelic + Mixpanel-equivalent)
  # so operators see it across whichever surface they monitor.
  def report_backstop_hit(model_name, context)
    age_days = context[:created_at] ? ((Time.current - context[:created_at]) / 1.day).round(1) : nil
    msg = "DataRetention backstop hit: #{model_name} not redacted by primary rule (age_days=#{age_days || 'unknown'}, #{context.inspect})"

    Rails.logger.warn(msg)
    NewRelic::Agent.notice_error(StandardError.new(msg), custom_params: context.merge(model: model_name, age_days: age_days)) if defined?(NewRelic::Agent)
    GenericEventTracker.new.track("DataRedactionBackstopHit", nil, context.merge(model: model_name, age_days: age_days))
  end

  # Ensure a redaction failure is sent to NR as an error, and to mixpanel as an event
  def report_redaction_failure(ex, context)
    Rails.logger.error "Data redaction failed (#{context.inspect}): #{ex.class}: #{ex.message}"
    NewRelic::Agent.notice_error(ex, custom_params: context) if defined?(NewRelic::Agent)
    GenericEventTracker.new.track("DataRedactionFailure", nil, context.merge(error: ex.message))
  end

  # use Argyle api to delete the user and all associated data.
  # A 404 is expected if the user was already deleted by a previous run.
  #
  # Returns :deleted, :already_deleted or :failed so callers can report the
  # outcome. Argyle holds data outside our database, so a failure here is
  # invisible to any check that only re-reads our own rows.
  def delete_argyle_user(client_agency_id, argyle_user_id)
    argyle_environment = ClientAgencyConfig.instance[client_agency_id].argyle_environment
    argyle = Aggregators::Sdk::ArgyleService.new(argyle_environment)
    argyle.delete_user(argyle_user_id: argyle_user_id)
    :deleted
  rescue Faraday::ResourceNotFound
    Rails.logger.info "Argyle User #{argyle_user_id} already deleted"
    :already_deleted
  rescue => ex
    raise ex unless Rails.env.production?

    Rails.logger.error "Unable to delete Argyle User #{argyle_user_id} - #{ex.message}"
    GenericEventTracker.new.track("DataRedactionFailure", nil, { argyle_user_id: argyle_user_id })
    :failed
  end
end
