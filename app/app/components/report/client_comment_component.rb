class Report::ClientCommentComponent < ViewComponent::Base
  def initialize(cbv_flow:, account_id:)
    @cbv_flow = cbv_flow
    @account_id = account_id
  end

  def comment
    @cbv_flow.additional_information.dig(@account_id, "comment")
  end
end
