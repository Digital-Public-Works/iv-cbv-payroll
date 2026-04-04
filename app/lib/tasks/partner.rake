namespace :partner do
  desc "create API production user for a partner"
  task :create_api_access_token, [ :partner_id ] => :environment do |_t, args|
    partner_id = args.fetch(:partner_id)
    user = User.find_or_create_by(
      email: "ffs-eng+#{partner_id}@digitalpublicworks.org",
      client_agency_id: partner_id
    )

    user.update(is_service_account: true)
    access_token = user.api_access_tokens.first || user.api_access_tokens.create

    Rails.logger.info "User #{user.id} (#{user.email}) created, with API access token: #{access_token.access_token}"
  end

  desc "deliver csv summary of cases sent to a partner"
  task :deliver_csv_reports, [ :partner_id ] => :environment do |_t, args|
    partner_id = args.fetch(:partner_id)
    agency = ClientAgencyConfig.instance[partner_id]
    config = agency.transmission_method_configuration.with_indifferent_access
    unless config.fetch("csv_summary_reports_enabled", true)
      Rails.logger.info "#{partner_id} CSV summary delivery disabled, not enqueuing job"
      next
    end

    now = Time.find_zone(agency.timezone).now
    start_time = now.yesterday.change(hour: 8)
    end_time = now.change(hour: 8)
    ReportDelivererJob.perform_later(partner_id, start_time, end_time)
  end

  desc "backfill agency name matches for a partner"
  task :backfill_agency_name_matches, [ :partner_id ] => :environment do |_t, args|
    partner_id = args.fetch(:partner_id)
    Rails.logger.info "Backfilling agency name matches for #{partner_id}:"
    CbvFlow
      .completed
      .unredacted
      .where(client_agency_id: partner_id)
      .find_each do |cbv_flow|
      Rails.logger.info "  CbvFlow id = #{cbv_flow.id}"
      MatchAgencyNamesJob.perform_now(cbv_flow.id)
    end
  end

  desc "redact case numbers for a partner"
  task :redact_case_numbers, [ :partner_id ] => :environment do |_t, args|
    partner_id = args.fetch(:partner_id)
    Rails.logger.info "Redacting case-numbers for #{partner_id}..."
    DataRetentionService.redact_case_numbers_by_agency(partner_id)
  end
end
