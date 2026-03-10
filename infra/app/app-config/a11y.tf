module "a11y_config" {
  source                          = "./env-config"
  project_name                    = local.project_name
  app_name                        = local.app_name
  default_region                  = module.project_config.default_region
  environment                     = "a11y"
  network_name                    = "demo"
  domain_name                     = "a11y.divt.app"
  enable_https                    = true
  has_database                    = local.has_database
  has_incident_management_service = local.has_incident_management_service

  # Setting minimum threshold to 0 capacity because this should only incur
  # charges when the ECS container is connected.  This saves operational overhead
  # from needed to destroy the DB every time we spin up and down the instance.
  # https://aws.amazon.com/blogs/database/introducing-scaling-to-0-capacity-with-amazon-aurora-serverless-v2/
  database_serverless_min_capacity = 0.5
  database_serverless_max_capacity = 1.0

  # These numbers are a starting point based on this article
  # Update the desired instance size and counts based on the project's specific needs
  # https://conchchow.medium.com/aws-ecs-fargate-compute-capacity-planning-a5025cb40bd0
  service_cpu                    = 1024
  service_memory                 = 4096
  service_desired_instance_count = 1

  # Create DNS records for these `additional_domains` in the default hosted
  # zone (this is necessary to support CBV agency subdomains).
  # NOTE: "*.divt.app" is shared with demo, created only in demo config
  additional_domains = ["*.a11y.divt.app"]

  # Enable and configure identity provider.
  enable_identity_provider = local.enable_identity_provider

  # Support local development against the dev instance.
  extra_identity_provider_callback_urls = ["http://localhost"]
  extra_identity_provider_logout_urls   = ["http://localhost"]

  # Enables ECS Exec access for debugging or jump access.
  # See https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-exec.html
  # Defaults to `false`. Uncomment the next line to enable.
  enable_command_execution = true

  # NewRelic configuration for metrics
  newrelic_account_id = "4619676"
}
