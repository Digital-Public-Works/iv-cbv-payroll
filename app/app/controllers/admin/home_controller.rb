# Agency sitemap: shown on the bare domain (no partner subdomain), linking to
# each configured agency's portal. Every other admin page requires an agency
# inferred from the subdomain.
class Admin::HomeController < Admin::BaseController
  skip_before_action :require_agency!

  def index
    @agencies = agency_config.client_agency_ids
      .map { |id| agency_config[id] }
      .compact
      .select { |agency| agency.agency_domain.present? }
  end
end
