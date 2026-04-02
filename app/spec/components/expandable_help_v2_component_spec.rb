# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExpandableHelpV2Component, type: :component do
  let(:required_params) do
    {
      id: "test-help",
      trigger_label: "How do I find this?",
      element_name: "ApplicantClickedHelpAccordionOnPage"
    }
  end
  let(:additional_params) { {} }
  let(:params) { required_params.merge(additional_params) }

  context "with minimal params" do
    it "renders the trigger button with label" do
      render_inline(described_class.new(**params)) { "Help content here" }

      button = page.find(:css, "button.usa-accordion__button")
      expect(button).to have_text("How do I find this?")
    end

    it "renders collapsed by default" do
      render_inline(described_class.new(**params)) { "Help content here" }

      button = page.find(:css, "button.usa-accordion__button")
      expect(button["aria-expanded"]).to eq("false")
    end

    it "renders the content block" do
      render_inline(described_class.new(**params)) { "Help content here" }

      expect(page).to have_css(".usa-summary-box__text", text: "Help content here", visible: :all)
    end

    it "sets up aria-controls with matching content id" do
      render_inline(described_class.new(**params)) { "Help content here" }

      button = page.find(:css, "button.usa-accordion__button")
      content = page.find(:css, ".usa-accordion__content", visible: :all)

      expect(button["aria-controls"]).to eq("test-help-content")
      expect(content["id"]).to eq("test-help-content")
    end

    it "includes click tracking data attributes" do
      render_inline(described_class.new(**params)) { "Help content here" }

      button = page.find(:css, "button.usa-accordion__button")
      expect(button["data-action"]).to include("click->click-tracker#track")
      expect(button["data-element-type"]).to eq("expandable_help_accordion")
      expect(button["data-element-name"]).to eq("ApplicantClickedHelpAccordionOnPage")
    end

    it "attaches the accordion controller and action" do
      render_inline(described_class.new(**params)) { "Help content here" }

      accordion = page.find(:css, ".usa-accordion")
      button = page.find(:css, "button.usa-accordion__button")
      expect(accordion["data-controller"]).to include("accordion")
      expect(button["data-action"]).to include("click->accordion#setContentExpansion")
    end

    context "with margin_class" do
      it "uses margin-top-2 by default" do
        render_inline(described_class.new(**params)) { "Help content here" }

        expect(page).to have_css(".usa-accordion.margin-top-2")
      end

      it "uses custom margin class when provided" do
        render_inline(described_class.new(**params, margin_class: "margin-top-3")) { "Help content here" }

        expect(page).to have_css(".usa-accordion.margin-top-3")
      end
    end
  end

  context "when a heading is used" do
    let(:additional_params) { { heading: "Finding your information" } }

    it "renders the heading in the summary box" do
      render_inline(described_class.new(**params)) { "Help content here" }

      expect(page).to have_css(".usa-summary-box__heading", text: "Finding your information", visible: :all)
    end

    it "sets up aria-labelledby with matching heading id" do
      render_inline(described_class.new(**params)) { "Help content here" }

      summary_box = page.find(:css, ".usa-summary-box", visible: :all)
      heading = page.find(:css, ".usa-summary-box__heading", visible: :all)

      expect(summary_box["aria-labelledby"]).to eq("test-help-heading")
      expect(heading["id"]).to eq("test-help-heading")
    end
  end

  context "with additional data attributes" do
      let(:additional_params) do
        { data_options:
            { controller: "other-controller",
              "other-controller-target": "myHelpAccordion" }
        }
      end

      it "still renders the accordion controller and action" do
        render_inline(described_class.new(**params)) { "Help content here" }

        accordion = page.find(:css, ".usa-accordion")
        expect(accordion["data-controller"]).to include("accordion")
      end

      it "also includes other data attributes" do
        render_inline(described_class.new(**params)) { "Help content here" }

        accordion = page.find(:css, ".usa-accordion")
        expect(accordion["data-controller"]).to include("other-controller")
        expect(accordion["data-other-controller-target"]).to eq("myHelpAccordion")
      end
    end
end
