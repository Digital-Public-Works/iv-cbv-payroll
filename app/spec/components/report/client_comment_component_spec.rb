require "rails_helper"

RSpec.describe Report::ClientCommentComponent, type: :component do
  let(:cbv_flow) { create(:cbv_flow, additional_information: additional_information) }
  let(:account_id) { "1234" }

  before do
    render_inline(described_class.new(cbv_flow: cbv_flow, account_id: account_id))
  end

  context "when there is no user provided comment" do
    let(:additional_information) { {} }

    it "renders a default message" do
      expect(page).to have_text("None")
    end

    it "renders the client comment description" do
      expect(page).to have_text("Client Comments")
      expect(page).to have_text("Additional information provided by the client")
    end
  end

  context "when there is a user provided comment" do
    let(:comment_text) { "This is an important comment." }
    let(:additional_information) { { account_id.to_sym => { comment: comment_text } } }

    it "renders the user provided comment" do
      expect(page).to have_text(comment_text)
    end
  end
end
