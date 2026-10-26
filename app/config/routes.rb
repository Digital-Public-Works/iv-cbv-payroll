
require "constraints/configured_agency_constraint"
require "constraints/client_agency_id_constraint"

Rails.application.routes.draw do
  devise_for :users,
    controllers: {
      sessions:           "users/sessions"
    }

  devise_scope :user do
    delete "sign_out", to: "devise/sessions#destroy", as: :destroy_user_session
  end

  # redirect any subdomain that is not a configured agency to the base domain
  constraints(lambda { |req|
    base = ENV["DOMAIN_NAME"].to_s
    host = req.host.to_s

    # only consider hosts under the base domain
    next false if base.blank?
    next false unless host.end_with?(base)
    # don't redirect apex
    next false if host == base

    # extract leftmost subdomain label before the base
    sub = host.delete_suffix(".#{base}").split(".").reject(&:empty?).first

    # redirect if it's www or not a configured agency
    sub == "www" || !ConfiguredAgencyConstraint.new.matches?(req)
  }) do
    match "(*path)", to: redirect(status: 302) { |params, req|
      base = ENV["DOMAIN_NAME"]
      path = params[:path].to_s
      qs   = req.query_string.present? ? "?#{req.query_string}" : ""
      port = req.port && ![ 80, 443 ].include?(req.port) ? ":#{req.port}" : ""
      "#{req.scheme}://#{base}#{port}/#{path}#{qs}"
    }, via: :all
  end

  scope "(:locale)", locale: /#{I18n.available_locales.join("|")}/, format: "html"  do
    # Your application routes go here
    root "pages#home"

    get "/health", to: "health_check#ok"
    get "/health/test_queueing", to: "health_check#test_queueing"
    get "/health/test_rendering", to: "health_check#test_rendering"
    get "/help", to: "help#index", as: :help
    get "/help/:topic", to: "help#show", as: :help_topic
    get "/maintenance", to: "maintenance#show"
    # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

    # Feedback CTA
    get "/feedback", to: "feedbacks#show", as: :feedbacks

    # generic link. gets partner via subdomain, creates invitation or finds invitation via device_id.
    get "/start", to: "cbv/generic_links#show"

    # Tokenized links
    get "/start/:token", to: "cbv/entries#show", as: :start_flow, token: /[^\/]+/

    scope "/cbv", as: :cbv_flow, module: :cbv do
      resource :entry, only: %i[show create]
      resource :employer_search, only: %i[show]
      resource :synchronizations, only: %i[show update]
      resource :synchronization_failures, only: %i[show]
      resource :validation_failures, only: %i[show]
      resource :summary, only: %i[show update]
      resource :submit, only: %i[show update], format: %i[html pdf]
      resource :missing_results, only: %i[show]
      resource :success, only: %i[show]
      resource :add_job, only: %i[show create]
      resource :other_job, only: %i[show update]
      resource :payment_details, only: %i[show update]
      resource :expired_invitation, only: %i[show]
      resource :applicant_information, only: %i[show update]
      resource :landing_page, only: %i[show update]

      # Session management
      post "session/refresh", to: "sessions#refresh", as: :session_refresh
      get "session/end", to: "sessions#end", as: :session_end
      get "session/timeout", to: "sessions#timeout", as: :session_timeout

      # Preview routes (non-production only)
      scope "/preview", as: :preview do
        root to: "preview#entry"
        get "employer_search", to: "preview#employer_search"
        get "entry", to: "preview#entry"
        get "applicant_information", to: "preview#applicant_information"
        get "landing_page", to: "preview#landing_page"
        get "add_job", to: "preview#add_job"
        get "other_job", to: "preview#other_job"
        get "expired_invitation", to: "preview#expired_invitation"
        get "session_timeout", to: "preview#session_timeout"
        get "success", to: "preview#success"
        get "synchronizations", to: "preview#synchronizations"
        get "synchronization_failures", to: "preview#synchronization_failures"
        get "validation_failures", to: "preview#validation_failures"
        get "payment_details", to: "preview#payment_details"
        get "summary", to: "preview#summary"
        get "missing_results", to: "preview#missing_results"
        get "submit", to: "preview#submit", defaults: { format: :html }
        get "submit.pdf", to: "preview#submit", defaults: { format: :pdf }
        get "submit_pdf_as_html", to: "preview#submit_pdf_as_html"
        get "paystubs.pdf", to: "preview#paystubs", defaults: { format: :pdf }
        get "paystubs_pdf_as_html", to: "preview#paystubs_pdf_as_html"
        get "transmitted_json", to: "preview#transmitted_json"
        get "sync_playground", to: "preview/sync_playground#show"
        post "sync_playground/webhook", to: "preview/sync_playground#webhook", as: :sync_playground_webhook
        patch "sync_playground/poll", to: "preview/sync_playground#poll", as: :sync_playground_poll
      end
    end

    # Caseworker portal, scoped per partner. The client_agency_id segment is
    # validated dynamically per request against the database (see
    # ClientAgencyIdConstraint) rather than enumerating partners into the route
    # table at boot.
    scope "/:client_agency_id", module: :caseworker, constraints: ClientAgencyIdConstraint.new do
      get "/sso", to: redirect("/%{client_agency_id}") # Temporary: Remove once people get used to going to /:client_agency_id as the login destination.
      root to: "entries#index", as: :new_user_session

      resource :dashboard, only: %i[show], as: :caseworker_dashboard
      resources :cbv_flow_invitations, only: %i[new create], as: :invitations, path: :invitations
    end
  end

  namespace :webhooks do
    namespace :pinwheel do
      resources :events, only: :create
    end

    namespace :argyle do
      resources :events, only: :create
    end
  end

  namespace :api do
    scope :v1 do
      post "/invitations", to: "invitations#create"
    end

    scope :pinwheel do
      post "/tokens" => "pinwheel#create_token"
    end

    scope :argyle do
      post "/tokens" => "argyle#create"
    end

    scope :events do
      post :user_action, to: "user_events#user_action"
    end

    # DEV/TEST ONLY: Load testing session generation
    scope :load_test do
      post "/sessions", to: "load_test_sessions#create"
    end

    # these routes only exist if there is a ADMIN_API_SERVICE_SECRET value in the env configuration
    constraints(->(_req) { AdminApi::Config.enabled? }) do
      namespace :admin do
        namespace :v1 do
          get "schema", to: "schema#show"
          get "export", to: "exports#index"
          post "partners/import", to: "imports#create"

          resources :partners, only: [ :index, :show, :create, :update ], param: :partner_id do
            member do
              post :validate
              post :diff
              get :export
              post :promote_settings
              put :transmission_methods, to: "transmission_methods#update"
              post "transmission_methods/:method_type/check", to: "transmission_methods#check", as: :check_transmission_method
            end
          end
        end
      end
    end
  end

  match "/404", to: "pages#error_404", via: :all
  match "/500", to: "pages#error_500", via: :all

  # CSP violation reporting endpoint
  post "/csp-reports", to: "csp_reports#create"
end
