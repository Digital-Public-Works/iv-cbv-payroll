# frozen_string_literal: true

require "rails_helper"

RSpec.describe LinkWithIconComponent, type: :component do
  describe '#link_with_icon' do
    let(:result) { render_inline(described_class.new('View Details', url: '/details')) }

    it 'outputs a link with link styling' do
      expect(result).to have_element(:a, href: '/details', class: 'usa-link')
      expect(result).to have_text('View Details')
    end

    context 'without url option' do
      it 'raises an ArgumentError' do
        expect { described_class.new('View Details') }.to raise_error(ArgumentError)
      end
    end

    context 'with icon' do
      let(:result) { render_inline(described_class.new('View Details', url: '/details', icon: 'file_download')) }

      it 'outputs a link with icon' do
        expect(result).to have_element(:a, href: '/details', class: 'usa-link')
        expect(result).to have_element(:svg, class: 'usa-icon')
        expect(result).to have_element(:use, href: /.svg#file_download/)
      end

      it 'defaults to leading icon position' do
        expect(result).to have_element(:svg, class: 'usa-icon')
        # The icon should appear before the text in the DOM
        expect(result.to_html).to match(/<svg.*usa-icon.*>.*<\/svg>.*View Details/m)
      end
    end

    context 'with leading icon position' do
      let(:result) { render_inline(described_class.new('Download', url: '/download', icon: 'file_download', icon_position: :leading)) }

      it 'renders icon before text' do
        expect(result).to have_element(:svg, class: 'usa-icon')
        expect(result.to_html).to match(/<svg.*usa-icon.*>.*<\/svg>.*Download/m)
      end
    end

    context 'with trailing icon position' do
      let(:result) { render_inline(described_class.new('Download', url: '/download', icon: 'file_download', icon_position: :trailing)) }

      it 'renders icon after text' do
        expect(result).to have_element(:svg, class: 'usa-icon')
        expect(result.to_html).to match(/Download.*<svg.*usa-icon.*>.*<\/svg>/m)
      end
    end

    context 'with variant' do
      let(:result) { render_inline(described_class.new('Cancel', url: '/cancel', variant: 'unstyled')) }

      it 'adds variant class' do
        expect(result).to have_element(:a, class: 'usa-link usa-link--unstyled')
      end
    end

    context 'with multiple variants' do
      let(:result) { render_inline(described_class.new('Edit', url: '/edit', variant: %w[secondary outline])) }

      it 'adds multiple variant classes' do
        expect(result).to have_element(:a, class: 'usa-link usa-link--secondary usa-link--outline')
      end
    end

    context 'with custom class' do
      let(:result) { render_inline(described_class.new('Download', url: '/download', class: 'download-link')) }

      it 'adds custom class to link' do
        expect(result).to have_element(:a, class: 'usa-link download-link')
      end
    end

    context 'with icon and variant' do
      let(:result) { render_inline(described_class.new('Download', url: '/download', icon: 'file_download', variant: 'accent_cool')) }

      it 'outputs link with both icon and variant styling' do
        expect(result).to have_element(:a, href: '/download', class: 'usa-link usa-link--accent-cool')
        expect(result).to have_element(:use, href: /.svg#file_download/)
      end
    end

    context 'with icon, variant, and trailing position' do
      let(:result) { render_inline(described_class.new('Download', url: '/download', icon: 'file_download', variant: 'accent_cool', icon_position: :trailing)) }

      it 'outputs link with trailing icon and variant styling' do
        expect(result).to have_element(:a, href: '/download', class: 'usa-link usa-link--accent-cool')
        expect(result).to have_element(:use, href: /.svg#file_download/)
        expect(result.to_html).to match(/Download.*<svg.*usa-icon.*>.*<\/svg>/m)
      end
    end

    context 'with underscored variant name' do
      let(:result) { render_inline(described_class.new('Test', url: '/test', variant: 'accent_warm')) }

      it 'converts underscores to dashes in CSS class' do
        expect(result).to have_element(:a, class: 'usa-link usa-link--accent-warm')
      end
    end

    context 'without icon but with icon_position' do
      let(:result) { render_inline(described_class.new('Text Only', url: '/text', icon_position: :trailing)) }

      it 'renders only text without icon' do
        expect(result).to have_text('Text Only')
        expect(result).not_to have_element(:svg, class: 'usa-icon')
      end
    end

    context 'when target is _blank' do
      let(:result) { render_inline(described_class.new('Learn more', url: '/details', target: '_blank')) }

      it 'defaults to the launch icon' do
        expect(result).to have_element(:use, href: /.svg#launch/)
      end

      it 'renders a visually-hidden "Opens in a new tab" span' do
        expect(result).to have_element(:span, class: 'usa-sr-only', text: 'Opens in a new tab')
      end
    end

    context 'when target is _blank and an explicit icon is given' do
      let(:result) { render_inline(described_class.new('Download', url: '/f.pdf', icon: 'file_download', target: '_blank')) }

      it 'keeps the explicit icon instead of overriding it with launch' do
        expect(result).to have_element(:use, href: /.svg#file_download/)
        expect(result).not_to have_element(:use, href: /.svg#launch/)
      end

      it 'still renders the sr-only "Opens in a new tab" text' do
        expect(result).to have_element(:span, class: 'usa-sr-only', text: 'Opens in a new tab')
      end
    end

    context 'when target is _blank and icon: false is given' do
      let(:result) { render_inline(described_class.new('Visit site', url: '/x', icon: false, target: '_blank')) }

      it 'renders no icon' do
        expect(result).not_to have_element(:svg, class: 'usa-icon')
      end

      it 'still renders the sr-only "Opens in a new tab" text' do
        expect(result).to have_element(:span, class: 'usa-sr-only', text: 'Opens in a new tab')
      end
    end

    context 'without target _blank' do
      let(:result) { render_inline(described_class.new('Internal link', url: '/internal')) }

      it 'does not render the sr-only "Opens in a new tab" text' do
        expect(result).not_to have_text('Opens in a new tab')
      end
    end
  end
end
