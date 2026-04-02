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
  describe '.hours_computed' do
    context 'when Argyle provides hours directly' do
      it 'uses the provided hours' do
        gross_pay_list = [
          { "type" => "base", "hours" => "40", "rate" => "10.00", "amount" => "400.00" }
        ]
        expect(described_class.hours_computed("80.00", gross_pay_list)).to eq(80.0)
      end
    end

    context 'when Argyle hours is null (synthetic calculation)' do
      it 'returns base hours when there is no overtime' do
        gross_pay_list = [
          { "type" => "base", "hours" => "40", "rate" => "15.00", "amount" => "600.00" }
        ]
        expect(described_class.hours_computed(nil, gross_pay_list)).to eq(40.0)
      end

      it 'includes OT hours when OT rate exceeds the base rate (true overtime, e.g. 1.5x)' do
        gross_pay_list = [
          { "type" => "base", "hours" => "40", "rate" => "10.00", "amount" => "400.00" },
          { "type" => "overtime", "hours" => "2", "rate" => "15.00", "amount" => "30.00" }
        ]
        # OT rate ($15) > base rate ($10), so 2 OT hours are real worked hours
        expect(described_class.hours_computed(nil, gross_pay_list)).to eq(42.0)
      end

      it 'excludes OT hours when OT rate is a supplemental bonus (e.g. +$1/hr for Sunday)' do
        gross_pay_list = [
          { "type" => "base", "hours" => "40", "rate" => "15.00", "amount" => "600.00" },
          { "type" => "overtime", "hours" => "8", "rate" => "1.00", "amount" => "8.00" }
        ]
        # OT rate ($1) < base rate ($15), so these hours are supplemental, not additional
        expect(described_class.hours_computed(nil, gross_pay_list)).to eq(40.0)
      end

      it 'uses federal minimum wage as floor when base rate is very low' do
        gross_pay_list = [
          { "type" => "base", "hours" => "40", "rate" => "5.00", "amount" => "200.00" },
          { "type" => "overtime", "hours" => "5", "rate" => "6.00", "amount" => "30.00" }
        ]
        # Base rate ($5) < federal min wage ($7.25), so threshold is $7.25
        # OT rate ($6) < $7.25, so OT hours are NOT included
        expect(described_class.hours_computed(nil, gross_pay_list)).to eq(40.0)
      end

      it 'includes OT hours when rate exceeds federal minimum wage floor' do
        gross_pay_list = [
          { "type" => "base", "hours" => "40", "rate" => "5.00", "amount" => "200.00" },
          { "type" => "overtime", "hours" => "5", "rate" => "8.00", "amount" => "40.00" }
        ]
        # Base rate ($5) < federal min wage ($7.25), threshold is $7.25
        # OT rate ($8) > $7.25, so OT hours ARE included
        expect(described_class.hours_computed(nil, gross_pay_list)).to eq(45.0)
      end

      it 'calculates effective rate from amount/hours when rate is missing' do
        gross_pay_list = [
          { "type" => "base", "hours" => "40", "rate" => nil, "amount" => "400.00" },
          { "type" => "overtime", "hours" => "4", "rate" => nil, "amount" => "60.00" }
        ]
        # Base effective rate = 400/40 = $10/hr
        # OT effective rate = 60/4 = $15/hr
        # $15 > $10, so OT hours are real worked hours
        expect(described_class.hours_computed(nil, gross_pay_list)).to eq(44.0)
      end

      # NOTE: Using max of non-OT category hours as the base may need product review.
      # E.g., if someone has 30 hours holiday and 8 hours base, max would pick 30.
      # This matches pre-existing behavior from hours_computed before this feature.
      it 'handles multiple base types and uses the lowest rate as threshold' do
        gross_pay_list = [
          { "type" => "base", "hours" => "30", "rate" => "20.00", "amount" => "600.00" },
          { "type" => "holiday", "hours" => "8", "rate" => "10.00", "amount" => "80.00" },
          { "type" => "overtime", "hours" => "5", "rate" => "15.00", "amount" => "75.00" }
        ]
        # Lowest base rate is $10 (holiday), OT rate is $15 > $10, so OT hours included
        # Base hours = max(30, 8) = 30
        expect(described_class.hours_computed(nil, gross_pay_list)).to eq(35.0)
      end

      it 'handles mixed OT items where some are worked and some are supplemental' do
        gross_pay_list = [
          { "type" => "base", "hours" => "40", "rate" => "10.00", "amount" => "400.00" },
          { "type" => "overtime", "hours" => "5", "rate" => "15.00", "amount" => "75.00" },
          { "type" => "overtime", "hours" => "8", "rate" => "2.00", "amount" => "16.00" }
        ]
        # First OT ($15) > base ($10): 5 hours are real worked hours
        # Second OT ($2) < base ($10): 8 hours are supplemental
        expect(described_class.hours_computed(nil, gross_pay_list)).to eq(45.0)
      end

      it 'returns base hours when OT items have no hours' do
        gross_pay_list = [
          { "type" => "base", "hours" => "40", "rate" => "10.00", "amount" => "400.00" },
          { "type" => "overtime", "hours" => nil, "rate" => "15.00", "amount" => "75.00" }
        ]
        expect(described_class.hours_computed(nil, gross_pay_list)).to eq(40.0)
      end

      # NOTE: Product requirements question — when there are only overtime items
      # and no base hours, we return nil (no total hours). This may need review.
      it 'returns nil when no base hours exist' do
        gross_pay_list = [
          { "type" => "overtime", "hours" => "5", "rate" => "15.00", "amount" => "75.00" }
        ]
        expect(described_class.hours_computed(nil, gross_pay_list)).to be_nil
      end

      it 'handles OT with no rate and no amount gracefully' do
        gross_pay_list = [
          { "type" => "base", "hours" => "40", "rate" => "10.00", "amount" => "400.00" },
          { "type" => "overtime", "hours" => "5", "rate" => nil, "amount" => nil }
        ]
        # Cannot determine OT rate, so OT hours are not included
        expect(described_class.hours_computed(nil, gross_pay_list)).to eq(40.0)
      end
    end
  end

  describe '.overtime_worked_hours' do
    it 'returns 0.0 when there are no overtime items' do
      gross_pay_list = [
        { "type" => "base", "hours" => "40", "rate" => "10.00", "amount" => "400.00" }
      ]
      expect(described_class.overtime_worked_hours(gross_pay_list)).to eq(0.0)
    end

    # When no base items exist, the federal minimum wage is used as the rate threshold.
    # OT items below that threshold are assumed to be supplemental, even without base hours.
    it 'returns 0.0 when no base items exist to compare against and OT rate is below min wage' do
      gross_pay_list = [
        { "type" => "overtime", "hours" => "5", "rate" => "5.00", "amount" => "25.00" }
      ]
      expect(described_class.overtime_worked_hours(gross_pay_list)).to eq(0.0)
    end

    it 'returns OT hours when no base items exist but OT rate exceeds min wage' do
      gross_pay_list = [
        { "type" => "overtime", "hours" => "5", "rate" => "10.00", "amount" => "50.00" }
      ]
      expect(described_class.overtime_worked_hours(gross_pay_list)).to eq(5.0)
    end
  end

  describe '.implied_rate' do
    it 'returns the explicit rate when present' do
      pay_item = { "rate" => "15.50", "hours" => "40", "amount" => "500.00" }
      expect(described_class.implied_rate(pay_item)).to eq(15.50)
    end

    it 'calculates rate from amount/hours when rate is missing' do
      pay_item = { "rate" => nil, "hours" => "40", "amount" => "600.00" }
      expect(described_class.implied_rate(pay_item)).to eq(15.0)
    end

    it 'returns nil when rate, hours, and amount are all missing' do
      pay_item = { "rate" => nil, "hours" => nil, "amount" => nil }
      expect(described_class.implied_rate(pay_item)).to be_nil
    end

    it 'returns nil when hours is zero (avoid division by zero)' do
      pay_item = { "rate" => nil, "hours" => "0", "amount" => "100.00" }
      expect(described_class.implied_rate(pay_item)).to be_nil
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
