# partners can have attributes defined, and this is how to determine where those attributes appear.
class PartnerAttributeUsage < ApplicationRecord
  # attributes for when an invitation is created
  INVITATION = "invitation".freeze
  # attributes to ask for on the user input page post-payroll data sync
  APPLICANT_INPUT_PAGE = "applicant_input_page".freeze
  CONTEXTS = [ INVITATION, APPLICANT_INPUT_PAGE ].freeze

  belongs_to :partner_config

  validates :context, inclusion: { in: CONTEXTS }
  validates :name, presence: true, uniqueness: {
    scope: [ :partner_config_id, :context ],
    message: "should be unique per partner and context"
  }

  scope :ordered, -> { order(:position, :id) }
  scope :for_context, ->(context) { where(context: context.to_s) }
end
