return unless Rails.env.local?

require "aws-sdk-core"

# make it so local dev does not need an aws login
Aws.config[:token_provider] = nil
