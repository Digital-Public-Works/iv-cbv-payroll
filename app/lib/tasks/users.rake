namespace :users do
  # bin/rails 'users:create_api_token[pa_dhs]'
  # Refuses if the partner already has an active token (one per partner).
  desc "Creates an API token for a client agency, and user if necessary."
  task :create_api_token, [ :client_agency_id ] => [ :environment ] do |_, args|
    client_agency_id = args[:client_agency_id]

    token = AdminApi::ApiTokens.new(client_agency_id).create
    Rails.logger.info "#{token[:user_email]} has new API token: #{token[:access_token]}"
  rescue AdminApi::Errors::Conflict => e
    abort e.message
  end

  # bin/rails 'users:promote_to_service_account[2]'
  desc "Promote an existing account to service account status, returning an access token"
  task :promote_to_service_account, [ :user_id ] => [ :environment ] do |_, args|
    user_id = args[:user_id]
    user = User.find(user_id)

    tokens = AdminApi::ApiTokens.new(user.client_agency_id)
    User.transaction do
      user.update!(is_service_account: true)
      token = tokens.create(user: user)
      Rails.logger.info "User #{user_id} (#{user.email}) is now a service account: #{token[:access_token]}"
    end
  rescue AdminApi::Errors::Conflict => e
    abort "#{e.message} (user #{user_id} left unchanged)"
  end

  # bin/rails 'users:demote_service_account[2]'
  desc "Demote an existing account, deleting all associated access tokens"
  task :demote_service_account, [ :user_id ] => [ :environment ] do |_, args|
    user_id = args[:user_id]
    user = User.find(user_id)

    if user && user.update(is_service_account: false)
      user.api_access_tokens.update_all(deleted_at: Time.now)

      Rails.logger.info "User #{user_id} (#{user.email}) is no longer a service account."
    end
  end
end
