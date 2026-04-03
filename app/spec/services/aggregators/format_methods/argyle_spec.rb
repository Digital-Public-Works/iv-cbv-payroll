require 'rails_helper'
require 'rails_helper'

RSpec.describe Aggregators::FormatMethods::Argyle, type: :service do
  describe '.format_employment_status' do
    it 'returns "employed" for "active"' do
      expect(described_class.format_employment_status("active")).to eq("employed")
    end

    it 'returns "furloughed" for "inactive"' do
      expect(described_class.format_employment_status("inactive")).to eq("inactive")
    end

    it 'returns the original status for other values' do
      expect(described_class.format_employment_status("terminated")).to eq("terminated")
    end

    it 'returns nil for nil input' do
      expect(described_class.format_employment_status(nil)).to be_nil
    end
  end

  describe '.format_date' do
    it 'formats date correctly' do
      expect(described_class.format_date("2025-03-06T12:34:56Z")).to eq("2025-03-06")
    end

    it 'returns nil for nil input' do
      expect(described_class.format_date(nil)).to be_nil
    end
  end

  describe '.format_currency' do
    it 'converts string amount to the number of cents' do
      expect(described_class.format_currency("123.45")).to eq(12345)
    end

    it 'returns nil for nil input' do
      expect(described_class.format_currency(nil)).to be_nil
    end
  end

  describe '.hours_by_earning_category' do
    let(:gross_pay_list) do
      [
        { "type" => "regular", "hours" => "40" },
        { "type" => "overtime", "hours" => "5" },
        { "type" => "regular", "hours" => "35" }
      ]
    end

    it 'groups and sums hours by earning category' do
      result = described_class.hours_by_earning_category(gross_pay_list)
      expect(result).to eq({ "regular" => 75.0, "overtime" => 5.0 })
    end

    it 'ignores entries without hours' do
      gross_pay_list.append({ "type" => "bonus", "hours" => nil })
      result = described_class.hours_by_earning_category(gross_pay_list)
      expect(result).to eq({ "regular" => 75.0, "overtime" => 5.0 })
    end
  end
  describe '.format_employer_address' do
    it 'handles nil paystub' do
      a_paystub_json = nil
      expect(described_class.format_employer_address(a_paystub_json)).to be_nil
    end
    it 'handles nil employer_address' do
      a_paystub_json = {
        "employer_address" => nil
      }
      expect(described_class.format_employer_address(a_paystub_json)).to be_nil
    end
    it 'formats address properly without line2' do
      a_paystub_json = {
        "employer_address" => {
        "line1" =>  "123 Main St",
        "line2" => nil,
        "city" => "Anytown",
        "state" => "NY",
        "postal_code" => "12345"
        }
      }
      expect(described_class.format_employer_address(a_paystub_json)).to eq("123 Main St, Anytown, NY 12345")
    end

    it 'formats address properly with line2' do
      a_paystub_json = {
        "employer_address" => {
          "line1" =>  "123 Main St",
          "line2" => "Unit 2",
          "city" => "Anytown",
          "state" => "NY",
          "postal_code" => "12345"
        }
      }
      expect(described_class.format_employer_address(a_paystub_json)).to eq("123 Main St, Unit 2, Anytown, NY 12345")
    end
  end

  describe ".format_mileage" do
    it "nil distance is nil" do
      subject = described_class.format_mileage(nil)
      expect(subject).to be_nil


      subject = described_class.format_mileage("")
      expect(subject).to be_nil
    end

    it "'3.4' miles is 3.40 miles" do
      subject = described_class.format_mileage("3.4", "miles")
      expect(subject.class).to eq(Float)
      expect(subject).to eq(3.4)
    end

    it "'3.4' km is 2.11 miles" do
      subject = described_class.format_mileage("3.4", "km")
      expect(subject.class).to eq(Float)
      expect(subject.round(2)).to eq(2.11)
    end
  end

  describe ".employment_type" do
    context "when employment_type is 'contractor'" do
      let(:employment_type) { "contractor" }

      it "returns :gig" do
        expect(described_class.employment_type(employment_type))
          .to eq(:gig)
      end
    end

    context "when employment_type is not 'contractor'" do
      let(:employment_type) { "full-time" }

      it "returns :w2" do
        expect(described_class.employment_type(employment_type))
          .to eq(:w2)
      end
    end
  end

  describe ".paystub_implied_base_rate" do
    it "retrieves the rate_implied if it is present" do
      paystub_response = {
        "gross_pay_list_totals" => {
          "base" => {
            "rate_implied" => "30.2900"
          }
        }
      }

      expect(described_class.paystub_implied_base_rate_in_dollars(paystub_response)).to eq(30.29)
    end

    it "returns nil if gross_pay_list_totals is nil" do
      paystub_response = {
        "gross_pay_list_totals" => nil
      }

      expect(described_class.paystub_implied_base_rate_in_dollars(paystub_response)).to be_nil
    end

    it "returns nil if base is nil" do
      paystub_response = {
        "gross_pay_list_totals" => {
          "base" => nil
        }
      }

      expect(described_class.paystub_implied_base_rate_in_dollars(paystub_response)).to be_nil
    end

    it "returns nil if rate_implied is nil" do
      paystub_response = {
        "gross_pay_list_totals" => {
          "base" => {
            "rate_implied" => nil
          }
        }
      }

      expect(described_class.paystub_implied_base_rate_in_dollars(paystub_response)).to be_nil
    end

    it "returns 0 if rate_implied is 0" do
      paystub_response = {
        "gross_pay_list_totals" => {
          "base" => {
            "rate_implied" => "00.0000"
          }
        }
      }

      expect(described_class.paystub_implied_base_rate_in_dollars(paystub_response)).to be(0.00)
    end

    it "returns nil if rate_implied is an empty string" do
      paystub_response = {
        "gross_pay_list_totals" => {
          "base" => {
            "rate_implied" => ""
          }
        }
      }

      expect(described_class.paystub_implied_base_rate_in_dollars(paystub_response)).to be_nil
    end
  end

  describe ".total_hours_match?" do
    let(:response_body_hours) { "80.00" }
    let(:synthetic_total_hours) { "80.0000" }

    context "when the response body hours and synthetic total hours are equal" do
      it "returns true" do
        expect(described_class.total_hours_match?(response_body_hours, synthetic_total_hours)).to be true
      end
    end

    context "when the response body hours and synthetic total hours are within 0.01" do
      let(:synthetic_total_hours) { "79.9905" }

      it "returns true" do
        expect(described_class.total_hours_match?(response_body_hours, synthetic_total_hours)).to be true
      end
    end

    context "when the response body hours and synthetic total hours are not within 0.01" do
      let(:synthetic_total_hours) { "79.9900" }

      it "returns false" do
        expect(described_class.total_hours_match?(response_body_hours, synthetic_total_hours)).to be false
      end
    end
  end
end
