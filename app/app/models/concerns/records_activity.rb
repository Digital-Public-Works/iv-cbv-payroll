# record cloudwatch metric for autscaling use
module RecordsActivity
  extend ActiveSupport::Concern

  included do
    after_create_commit { ActivityCloudWatchMetrics.record }
  end
end
