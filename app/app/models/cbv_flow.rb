class CbvFlow < ApplicationRecord
  has_many :payroll_accounts, dependent: :destroy
  has_many :cbv_flow_transmissions, dependent: :destroy
  belongs_to :cbv_flow_invitation, optional: true
  belongs_to :cbv_applicant, optional: true
  validates :client_agency_id, inclusion: { in: ->(_) { ClientAgencyConfig.instance.client_agency_ids } }

  accepts_nested_attributes_for :cbv_applicant

  scope :incomplete, -> { where(confirmation_code: nil) }
  scope :completed, -> { where.not(confirmation_code: nil) }

  include Redactable
  has_redactable_fields(
    end_user_id: :uuid,
    additional_information: :object
  )

  def complete?
    confirmation_code.present?
  end

  # has the landing page for generic been passed, either because there was nothing
  # configured there or because the user entered the required values
  def landing_page_completed?
    landing_page_completed_at.present?
  end

  def complete_landing_page_step!
    return if landing_page_completed?

    update!(landing_page_completed_at: Time.current)
  end

  # this is 'true' if the user has entered data, or there was no data to enter and the user bypassed the page.
  def applicant_information_completed?
    applicant_information_completed_at.present?
  end

  def complete_applicant_information_step!
    return if applicant_information_completed?

    update!(applicant_information_completed_at: Time.current)
  end

  # Payroll accounts whose sync is over but still need to run useful report validator after collecting data
  def payroll_accounts_awaiting_validation
    payroll_accounts
      .includes(:webhook_events)
      .select { |account| account.has_fully_synced? && account.report_unknown? }
  end

  def self.create_from_invitation(cbv_flow_invitation, device_id, generic: false)
    create(
      cbv_flow_invitation: cbv_flow_invitation,
      cbv_applicant: cbv_flow_invitation.cbv_applicant,
      client_agency_id: cbv_flow_invitation.client_agency_id,
      device_id: device_id,
      generic: generic
    )
  end

  def self.create_without_invitation(client_agency_id, device_id)
    create(
      cbv_applicant: CbvApplicant.create(client_agency_id: client_agency_id),
      client_agency_id: client_agency_id,
      device_id: device_id
    )
  end

  # Accounts whose data is known to be usable: the sync produced what we need and
  # the report passed validation.
  def accounts_with_required_data
    payroll_accounts.includes(:webhook_events).select(&:usable?)
  end

  # all the jobs that we don't know are usable yet, but have finished sync
  def accounts_presumed_usable
    payroll_accounts.includes(:webhook_events).select(&:presumed_usable?)
  end

  # returns true if not *all* items are deemed to be not useful
  def has_presumed_usable_account?
    accounts_presumed_usable.any?
  end

  def fully_synced_payroll_accounts
    payroll_accounts.includes(:webhook_events).select { |account| account.has_fully_synced? }
  end

  # sharable generic link
  def to_generic_url(origin: nil)
    client_agency = ClientAgencyConfig.instance[client_agency_id]
    raise ArgumentError.new("Client Agency #{client_agency_id} not found") unless client_agency
    return nil unless AutoInvitationService.available_for?(client_agency_id)
    return nil if client_agency.agency_domain.blank?

    url_params = {
      host: client_agency.agency_domain,
      protocol: Rails.env.development? ? "http" : "https",
      locale: I18n.locale
    }
    url_params[:origin] = origin if origin.present?

    Rails.application.routes.url_helpers.start_url(url_params)
  end
end
