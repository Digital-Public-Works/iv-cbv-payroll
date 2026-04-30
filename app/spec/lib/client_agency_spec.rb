require "rails_helper"

RSpec.describe ClientAgency do
  context "invalid config" do
    describe "#initialize" do
      context "missing id" do
        let(:partner_config) do
          pc = PartnerConfig.create!(
            partner_id: 'test_missing_id',
            name: 'Foo Agency Name',
            timezone: 'America/Los_Angeles',
            argyle_environment: 'foo',
            pay_income_days_w2: 90,
            pay_income_days_gig: 182
          )
          pc.partner_transmission_methods.create!(method_type: :shared_email)
          pc.update_column(:partner_id, '')
          pc.reload
        end

        it "raises an error" do
          expect do
            ClientAgencyConfig::ClientAgency.new(partner_config)
          end.to raise_error(ArgumentError, "Client Agency missing id")
        end
      end

      context "missing agency name" do
        let(:partner_config) do
          pc = PartnerConfig.create!(
            partner_id: 'test_missing_name',
            name: 'placeholder',
            timezone: 'America/Los_Angeles',
            argyle_environment: 'foo',
            pay_income_days_w2: 90,
            pay_income_days_gig: 182
          )
          pc.partner_transmission_methods.create!(method_type: :shared_email)
          pc.update_column(:name, '')
          pc.reload
        end

        it "raises an error" do
          expect do
            ClientAgencyConfig::ClientAgency.new(partner_config)
          end.to raise_error(ArgumentError, /missing required attribute `name`/)
        end
      end

      context "missing timezone" do
        let(:sample_config) do
          pc = PartnerConfig.create!(
            partner_id: 'test_missing_tz',
            name: 'foo',
            timezone: 'placeholder',
            argyle_environment: 'foo',
            pay_income_days_w2: 90,
            pay_income_days_gig: 182
          )
          pc.partner_transmission_methods.create!(method_type: :shared_email)
          pc.update_column(:timezone, '')
          pc.reload
        end

        it "raises an error" do
          expect do
            ClientAgencyConfig::ClientAgency.new(sample_config)
          end.to raise_error(ArgumentError, /missing required attribute `timezone`/)
        end
      end

      context "incorrect pay income w2 configuration" do
        let(:sample_config) do
          pc = PartnerConfig.create!(
            partner_id: 'test_bad_w2',
            name: 'foo',
            timezone: 'America/Los_Angeles',
            argyle_environment: 'foo',
            pay_income_days_w2: 0,
            pay_income_days_gig: 182
          )
          pc.partner_transmission_methods.create!(method_type: :shared_email)
          pc
        end

        it "raises an error" do
          expect do
            ClientAgencyConfig::ClientAgency.new(sample_config)
          end.to raise_error(ArgumentError, "Client Agency test_bad_w2 invalid value for pay_income_days.w2")
        end
      end

      context "incorrect pay income gig configuration" do
        let(:sample_config) do
          pc = PartnerConfig.create!(
            partner_id: 'test_bad_gig',
            name: 'foo',
            timezone: 'America/Los_Angeles',
            argyle_environment: 'foo',
            pay_income_days_w2: 90,
            pay_income_days_gig: 0
          )
          pc.partner_transmission_methods.create!(method_type: :shared_email)
          pc
        end

        it "raises an error" do
          expect do
            ClientAgencyConfig::ClientAgency.new(sample_config)
          end.to raise_error(ArgumentError, "Client Agency test_bad_gig invalid value for pay_income_days.gig")
        end
      end

      context "missing transmission method" do
        let(:sample_config) do
          PartnerConfig.create!(
            partner_id: 'test_no_tm',
            name: 'foo',
            timezone: 'America/Los_Angeles',
            argyle_environment: 'foo',
            pay_income_days_w2: 90,
            pay_income_days_gig: 182
          )
          # No transmission methods created
        end

        it "raises an error" do
          expect do
            ClientAgencyConfig::ClientAgency.new(sample_config)
          end.to raise_error(ArgumentError, "Client Agency test_no_tm must have at least one transmission method configured")
        end
      end
    end
  end
end
