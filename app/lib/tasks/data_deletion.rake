namespace :data_deletion do
  desc "Redact data that is older than our retention policy"
  task redact_all: :environment do
    service = DataRetentionService.new
    service.redact_all!
  end

  # ---------------------------------------------------------------------------
  # Manual right-to-erasure. See docs/app/runbooks/manual-redaction.md
  #
  #   1. data_deletion:resolve[pa_dhs,ABC1234]   non-destructive; prints row ids
  #   2. data_deletion:redact_ids[pa_dhs,41,42]  irreversible; takes only row ids
  #
  # Two steps on purpose. The split keeps the partner identifier out of the
  # destructive invocation -- and therefore out of that command's shell history,
  # CI output and the ECS RunTask override AWS records -- and it makes a retry
  # after a partial failure possible: CbvApplicant#redact! overwrites
  # partner_identifier, so step 1 cannot be repeated once it has succeeded, but
  # step 2 can be re-run from the same ids as often as needed.
  #
  # Both tasks write to stdout rather than Rails.logger: outside production the
  # logger writes to log/<env>.log where an operator would not see it, and in
  # production the container's stdout is captured to CloudWatch anyway.
  # ---------------------------------------------------------------------------

  desc "Resolve a partner identifier to the row ids a manual erasure would touch (non-destructive)"
  task :resolve, [ :client_agency_id, :partner_identifier ] => :environment do |_task, args|
    client_agency_id = args[:client_agency_id].to_s.strip
    partner_identifier = args[:partner_identifier].to_s.strip

    if client_agency_id.empty? || partner_identifier.empty?
      abort "Usage: rake 'data_deletion:resolve[client_agency_id,partner_identifier]' " \
            "(rake splits bracket arguments on commas, so an identifier containing a comma cannot be passed this way)"
    end

    unless ClientAgencyConfig.instance.client_agency_ids.include?(client_agency_id)
      abort "Unknown client_agency_id #{client_agency_id.inspect}"
    end

    begin
      scope = DataRetentionService.resolve_manual_erasure(client_agency_id, partner_identifier)
    rescue ActiveRecord::RecordNotFound => ex
      abort "resolve: #{ex.message}. Nothing was changed."
    end

    # Row ids are safe to print: they are internal, contain no applicant data,
    # and survive redaction -- which is what makes step 2 and the after-the-fact
    # verification possible without writing the identifier down anywhere.
    puts "resolve: agency=#{client_agency_id} #{scope.counts.map { |k, v| "#{k}=#{v}" }.join(' ')}"
    puts "resolve: applicant_ids=#{scope.applicant_ids.inspect}"
    puts "resolve: cbv_flow_ids=#{scope.cbv_flow_ids.inspect}"
    puts "resolve: invitation_ids=#{scope.invitation_ids.inspect}"
    puts "resolve: payroll_account_ids=#{scope.payroll_account_ids.inspect}"
    puts "resolve: record these ids in the erasure ticket NOW -- redaction overwrites " \
         "the partner identifier, so this lookup cannot be repeated afterwards."
    puts "resolve: next step -> data_deletion:redact_ids[#{client_agency_id},#{scope.applicant_ids.join(',')}]"
  end

  desc "Redact every record under the given CbvApplicant ids -- irreversible (ids come from data_deletion:resolve)"
  task :redact_ids, [ :client_agency_id ] => :environment do |_task, args|
    client_agency_id = args[:client_agency_id].to_s.strip
    raw_ids = args.extras.map { |id| id.to_s.strip }.reject(&:empty?)

    if client_agency_id.empty? || raw_ids.empty?
      abort "Usage: rake 'data_deletion:redact_ids[client_agency_id,applicant_id,...]' " \
            "(applicant ids come from data_deletion:resolve)"
    end

    unless ClientAgencyConfig.instance.client_agency_ids.include?(client_agency_id)
      abort "Unknown client_agency_id #{client_agency_id.inspect}"
    end

    # Guard against an operator pasting the partner identifier into the
    # destructive step out of habit. Keeping it out of this invocation is the
    # entire reason the task is split in two.
    malformed = raw_ids.reject { |id| id.match?(/\A\d+\z/) }
    if malformed.any?
      abort "redact_ids: expected numeric CbvApplicant ids, got #{malformed.size} non-numeric argument(s). " \
            "Pass the applicant_ids printed by data_deletion:resolve -- never the partner identifier."
    end

    applicant_ids = raw_ids.map(&:to_i)

    begin
      result = DataRetentionService.redact_applicant_ids!(client_agency_id, applicant_ids)
    rescue ActiveRecord::RecordNotFound => ex
      abort "redact_ids: #{ex.message}. Nothing was changed."
    end

    scope = result[:scope]
    attempted = result[:attempted]
    argyle = result[:argyle]
    verification = DataRetentionService.verify_erasure(scope)

    skipped = applicant_ids - scope.applicant_ids
    if skipped.any?
      puts "redact_ids: WARNING #{skipped.size} id(s) were not found in #{client_agency_id} and were skipped: #{skipped.inspect}"
    end

    puts "redact_ids: agency=#{client_agency_id} applicant_ids=#{scope.applicant_ids.inspect}"

    # ATTEMPTED and VERIFIED are different kinds of number and are labelled as
    # such. In production the redaction path reports failures rather than
    # raising, so ATTEMPTED is a count of intent; only VERIFIED is an outcome.
    puts "redact_ids: ATTEMPTED #{attempted.map { |k, v| "#{k}=#{v}" }.join(' ')}"
    puts "redact_ids: ARGYLE #{%i[deleted already_deleted not_applicable failed].map { |k| "#{k}=#{argyle[k]}" }.join(' ')}"
    puts "redact_ids: VERIFIED #{verification.map { |k, (got, want)| "#{k}=#{got}/#{want}" }.join(' ')}"

    problems = []
    problems << "some records were not redacted" unless DataRetentionService.erasure_verified?(verification)
    problems << "#{argyle[:failed]} Argyle user deletion(s) failed" if argyle[:failed].to_i.positive?

    if problems.any?
      abort "redact_ids: INCOMPLETE -- #{problems.join('; ')}. " \
            "Check New Relic for DataRedactionFailure, then re-run this exact command; repeating it is safe."
    end

    puts "redact_ids: COMPLETE -- every record in scope verified redacted. " \
         "Record the ids above against the erasure request before closing it out."
  end
end
