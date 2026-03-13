require "rails_helper"

RSpec.describe ClientAgency do
  context "invalid config" do
    describe "#initialize" do
      context "missing id" do
        let(:partner_config) do
          PartnerConfig.new(
            partner_id: '',
            name: 'Foo Agency Name',
            timezone: 'America/Los_Angeles,',
            argyle_environment: 'foo',
            transmission_method: 'shared_email'
          )
        end

        it "raises an error" do
          expect do
            ClientAgencyConfig::ClientAgency.new(partner_config)
          end.to raise_error(ArgumentError, "Client Agency missing id")
        end
      end

      context "missing agency name" do
        let(:partner_config) do
          PartnerConfig.new(
            partner_id: 'foo',
            name: '',
            timezone: 'America/Los_Angeles,',
            argyle_environment: 'foo',
            transmission_method: 'shared_email'
          )
        end

        it "raises an error" do
          expect do
            ClientAgencyConfig::ClientAgency.new(partner_config)
          end.to raise_error(ArgumentError, "Client Agency foo missing required attribute `name`")
        end
      end

      context "missing timezone" do
        let(:sample_config) do
          PartnerConfig.new(
            partner_id: 'foo',
            name: 'foo',
            timezone: '',
            argyle_environment: 'foo'
          )
        end

        it "raises an error" do
          expect do
            ClientAgencyConfig::ClientAgency.new(sample_config)
          end.to raise_error(ArgumentError, "Client Agency foo missing required attribute `timezone`")
        end
      end

      context "incorrect pay income w2 configuration" do
        let(:sample_config) do
          PartnerConfig.new(
            partner_id: 'foo',
            name: 'foo',
            timezone: 'America/Los_Angeles',
            argyle_environment: 'foo',
            pay_income_days_w2: 0,
            pay_income_days_gig: 182
          )
        end

        it "raises an error" do
          expect do
            ClientAgencyConfig::ClientAgency.new(sample_config)
          end.to raise_error(ArgumentError, "Client Agency foo invalid value for pay_income_days.w2")
        end
      end

      context "incorrect pay income gig configuration" do
        let(:sample_config) do
          PartnerConfig.new(
            partner_id: 'foo',
            name: 'foo',
            timezone: 'America/Los_Angeles',
            argyle_environment: 'foo',
            pay_income_days_w2: 90,
            pay_income_days_gig: 0
          )
        end

        it "raises an error" do
          expect do
            ClientAgencyConfig::ClientAgency.new(sample_config)
          end.to raise_error(ArgumentError, "Client Agency foo invalid value for pay_income_days.gig")
        end
      end

      context "missing transmission method" do
        let(:sample_config) do
          PartnerConfig.new(
            partner_id: 'foo',
            name: 'foo',
            timezone: 'America/Los_Angeles',
            argyle_environment: 'foo',
            transmission_method: '',
            pay_income_days_w2: 90,
            pay_income_days_gig: 182
          )
        end

        it "raises an error" do
          expect do
            ClientAgencyConfig::ClientAgency.new(sample_config)
          end.to raise_error(ArgumentError, "Client Agency foo missing required attribute `transmission_method`")
        end
      end
    end
  end
end
