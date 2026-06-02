require "rails_helper"

RSpec.describe Report::ClientCommentComponent, type: :component do
  let(:cbv_flow) { create(:cbv_flow, additional_information: additional_information) }
  let(:account_id) { "1234" }

  context "when there is no user provided comment" do
    let(:additional_information) { {} }

    it "does not render" do
      render_inline(described_class.new(cbv_flow: cbv_flow, account_id: account_id))
      expect(page).not_to have_text("Client Comments")
      expect(page.text).to be_empty
    end
  end

  context "when the comment is blank" do
    let(:additional_information) { { account_id => { "comment" => "" } } }

    it "does not render" do
      render_inline(described_class.new(cbv_flow: cbv_flow, account_id: account_id))
      expect(page).not_to have_text("Client Comments")
      expect(page.text).to be_empty
    end
  end

  context "when there is a user provided comment" do
    let(:comment_text) { "This is an important comment." }
    let(:additional_information) { { account_id.to_sym => { comment: comment_text } } }

    before do
      render_inline(described_class.new(cbv_flow: cbv_flow, account_id: account_id))
    end

    it "renders the user provided comment" do
      expect(page).to have_text(comment_text)
    end

    it "renders the client comment header and description" do
      expect(page).to have_text("Client Comments")
      expect(page).to have_text("Additional information provided by the client")
    end
  end
end
