# Suppress chatty INFO-level output in `bin/dev` — keeps the foreman console
# focused on requests + errors. Production/test behavior is unchanged.
return unless Rails.env.development?

Rails.application.config.after_initialize do
  # ActiveJob notifications: drops "Performing X / Performed X" + "Enqueued X"
  # lines fired by MixpanelEventTrackingJob, CaseWorkerTransmitterJob,
  # CsvToSftpReportDelivererJob, NewRelicEventTrackingJob, etc.
  ActiveJob::Base.logger = Logger.new(File::NULL)

  # Shoryuken's polling/receive-loop chatter from the worker process.
  if defined?(Shoryuken)
    Shoryuken.logger.level = Logger::WARN
  end

  # NewRelic agent's own log level is controlled by `log_level` in
  # config/newrelic.yml (set to `error` for the development env). The
  # AgentLogger doesn't expose a runtime `level=` setter the way stdlib
  # Logger does, so all NewRelic quieting happens via that YAML.
end
