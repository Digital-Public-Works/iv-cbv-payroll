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

  # Manually redact all instances of a specific identifier for a partner.
  # The partner identifier is not unique per partner (could have created
  # more than one invitation for a single applicant). Used for partner
  # right-to-erasure requests.
  def self.manually_redact_by_partner_identifier!(client_agency_id, partner_identifier)
    applicants = CbvApplicant.where(
      client_agency_id: client_agency_id,
      partner_identifier: partner_identifier
    )
    raise ActiveRecord::RecordNotFound, "No CbvApplicant found for client_agency_id=#{client_agency_id.inspect} partner_identifier=#{partner_identifier.inspect}" if applicants.empty?

    service = new
    applicants.find_each do |applicant|
      applicant.cbv_flows.each { |cbv_flow| service.send(:redact_cbv_flow, cbv_flow) }
    end
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

  # Redact an invitation + its applicant. Used by both #redact_invitations
  # (primary) and the invitation-backstop path. Wrapped to share the prod
  # error-swallow semantics consistently.
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
  def redact_cbv_flow(cbv_flow)
    delete_argyle_user(cbv_flow.client_agency_id, cbv_flow.argyle_user_id) if cbv_flow.argyle_user_id.present?

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
  def delete_argyle_user(client_agency_id, argyle_user_id)
    argyle_environment = ClientAgencyConfig.instance[client_agency_id].argyle_environment
    argyle = Aggregators::Sdk::ArgyleService.new(argyle_environment)
    argyle.delete_user(argyle_user_id: argyle_user_id)
  rescue Faraday::ResourceNotFound
    Rails.logger.info "Argyle User #{argyle_user_id} already deleted"
  rescue => ex
    raise ex unless Rails.env.production?

    Rails.logger.error "Unable to delete Argyle User #{argyle_user_id} - #{ex.message}"
    GenericEventTracker.new.track("DataRedactionFailure", nil, { argyle_user_id: argyle_user_id })
  end
end
