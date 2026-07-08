# frozen_string_literal: true

# Routing constraint that validates the `:client_agency_id` URL segment at
# request time instead of baking the set of known partners into the route table
# at boot.
class ClientAgencyIdConstraint
  def matches?(request)
    client_agency_id = request.path_parameters[:client_agency_id]
    client_agency_id.present? && ClientAgencyConfig.instance[client_agency_id].present?
  end
end
