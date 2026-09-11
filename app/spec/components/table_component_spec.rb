# frozen_string_literal: true

require "rails_helper"

RSpec.describe TableComponent, type: :component do
  include ViewComponent::TestHelpers

  subject(:result) do
    table = described_class.new(attributes: table_attributes)
    rows.each do |row_data|
      table.with_row do |row|
        row.with_data_cell.with_content(row_data)
      end
    end
    render_inline(table)
  end

  let(:table_attributes) { {} }
  let(:rows) { [] }
  let(:base_class) { "usa-table usa-table--borderless width-full" }


  context "when no rows are provided" do
    it "does not render the table" do
      result = render_inline(described_class.new)
      expect(result.to_html).to be_empty
    end
  end

  context "when at least one row is provided" do
    let (:rows) { [ "Cell content" ] }

    it "renders a <table> element" do
      expect(result.css("table")).to be_present
      expect(result.text).to include("Cell content")
    end
  end

  context "when table attributes are provided" do
    let(:rows) { [ "Cell content" ] }
    let(:table_attributes) { { "data-testid" => "test" } }

    it "renders with assigned attributes" do
      expect(result.css('table[data-testid="test"]')).to be_present
    end
  end

  context "thead rendering" do
    subject(:result) do
      table = described_class.new
      table.with_row { |row| row.with_data_cell.with_content("Cell content") }
      table.with_header { "Header content" } if with_header
      table.with_subheader_row do |row|
        row.with_data_cell(is_header: true).with_content("Month")
      end if with_subheader_row
      render_inline(table)
    end

    let(:with_header) { false }
    let(:with_subheader_row) { false }

    context "when only header is provided" do
      let(:with_header) { true }

      it "wraps the header in exactly one non-empty <tr>" do
        rows = result.css("thead > tr")
        expect(rows.length).to eq(1)
        expect(rows.first.text).to include("Header content")
      end
    end

    context "when only subheader_row is provided" do
      let(:with_subheader_row) { true }

      it "does not render a leading empty <tr> before the subheader row" do
        rows = result.css("thead > tr")
        expect(rows.length).to eq(1)
        expect(rows.first.text.strip).not_to be_empty
        expect(rows.first.text).to include("Month")
      end
    end

    context "when neither header nor subheader_row is provided" do
      it "does not render a <thead> at all" do
        expect(result.css("thead")).to be_empty
      end
    end
  end
end
