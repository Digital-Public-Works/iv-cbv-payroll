class Report::ClientCommentComponent < ViewComponent::Base
  def initialize(cbv_flow:, account_id:)
    @cbv_flow = cbv_flow
    @account_id = account_id
  end

  def comment
    @cbv_flow.additional_information.dig(@account_id, "comment")
  end

  private

  def chat_icon_path
    "M20 2H4c-1.1 0-1.99.9-1.99 2L2 22l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zM6 9h12v2H6V9zm8 5H6v-2h8v2zm4-6H6V6h12v2z"
  end
end
