require 'rails_helper'

RSpec.describe CbvFlowInvitation, type: :model do
  let(:valid_attributes) do
    attributes_for(:cbv_flow_invitation, :sandbox).merge(user: create(:user, client_agency_id: "sandbox"), cbv_applicant: create(:cbv_applicant, :sandbox))
  end
  let(:invalid_email_no_tld) { "johndoe@gmail" }
  let(:valid_email) { "johndoe@gmail.com" }

  describe "callbacks" do
    context "before_create" do
      let(:current_time) { Time.utc(2025, 6, 17, 1, 0, 0) }

      before { travel_to(current_time) }

      it "sets expires_at based on created_at" do
        invitation = CbvFlowInvitation.new(valid_attributes)
        invitation.save!
        expect(invitation.created_at).to eq(current_time)
        # Saved in the database as UTC, so this will show as 4 hours later than we expect
        expect(invitation.expires_at).to have_attributes(
                                           hour: 3,
                                           min: 59,
                                           sec: 59,
                                           month: 7,
                                           day: 1,
                                           )
      end
    end
  end

  describe "validations" do
    context "for all invitations" do
      context "validates email addresses" do
        context "when email address is valid" do
          valid_email_addresses = %w[johndoe@gmail.com johndoe@example.com.au johndoe@example.com,johndoe@example.com.au]
          valid_email_addresses.each do |email|
            it "#{email} is valid" do
              invitation = CbvFlowInvitation.new(valid_attributes.merge(email_address: email))
              expect(invitation).to be_valid
            end
          end
        end

        context "when email address is invalid" do
          invalid_email_addresses = %w[johndoe@gmail johndoe@gmail..com johndoe@gmail.com..com johndoe@gmail\ .\ com]
          invalid_email_addresses.each do |email|
            it "determines #{email} is invalid" do
              invitation = CbvFlowInvitation.new(valid_attributes.merge(email_address: email))
              expect(invitation).not_to be_valid
              expect(invitation.errors[:email_address]).to include(
                I18n.t('activerecord.errors.models.cbv_flow_invitation.attributes.email_address.invalid_format')
              )
            end
          end
        end
      end

      it "requires email_address" do
        invitation = CbvFlowInvitation.new(valid_attributes.merge(email_address: nil))
        expect(invitation).not_to be_valid
        expect(invitation.errors[:email_address]).to include(
          I18n.t('activerecord.errors.models.cbv_flow_invitation.attributes.email_address.invalid_format'),
        )
      end

      it "validates email_address format" do
        invitation = CbvFlowInvitation.new(valid_attributes.merge(email_address: "invalid_email"))
        expect(invitation).not_to be_valid
        expect(invitation.errors[:email_address]).to include(
          I18n.t('activerecord.errors.models.cbv_flow_invitation.attributes.email_address.invalid_format')
        )
      end

      context "validates expiration params" do
        let(:invitation) { build(:cbv_flow_invitation, :sandbox, expiration_date: expiration_date, expiration_days: expiration_days) }
        let(:expiration_date) { nil }
        let(:expiration_days) { nil }

        subject { invitation }

        context "when expiration_date and expiration_days are both present" do
          let(:expiration_date) { (Time.current + 10.day).iso8601 }
          let(:expiration_days) { 10 }

          it { is_expected.not_to be_valid }
        end

        context "when expiration_date is in the past" do
          let(:expiration_date) { (Time.current - 10.day).iso8601 }

          it { is_expected.not_to be_valid }
        end

        context "when expiration_date is more than one year in the future" do
          let(:expiration_date) { (Time.current + 367.days).iso8601 }

          it { is_expected.not_to be_valid }
        end

        context "when expiration_days is more than one year in the future" do
          let(:expiration_days) { 367 }

          it { is_expected.not_to be_valid }
        end

        context "when expiration_date is in the wrong format" do
          let(:expiration_date) { "less than one year from now" }

          it { is_expected.not_to be_valid }
        end

        context "when expiration_days is not an integer" do
          let(:expiration_days) { "fifty" }

          it { is_expected.not_to be_valid }
        end
      end
    end
  end

  describe "#expired?" do
    let(:client_agency_id) { "sandbox" }
    let(:invitation_valid_days) { 14 }
    let(:invitation) do
      create(:cbv_flow_invitation, valid_attributes.merge(
        client_agency_id: client_agency_id,
        created_at: invitation_sent_at
      ))
    end
    let(:now) { invitation_sent_at }
    let(:agency_time_zone) { "America/New_York" }

    before do
      agency_config = Rails.application.config.client_agencies[client_agency_id]
      allow(agency_config)
        .to receive(:invitation_valid_days)
        .and_return(invitation_valid_days)

      allow(agency_config)
        .to receive(:timezone).and_return(agency_time_zone)

      travel_to(now)
    end

    around do |example|
      Time.use_zone(agency_time_zone) { example.run }
    end

    subject { invitation.expired? }

    context "within the validity window" do
      let(:invitation_sent_at)    { Time.zone.local(2024, 8,  1, 12, 0, 0) }
      let(:snap_application_date) { Time.zone.local(2024, 8,  1, 12, 0, 0) }
      let(:now)                   { Time.zone.local(2024, 8, 14, 12, 0, 0) }

      it { is_expected.to eq(false) }

      context "when the invitation was redacted" do
        # This should only happen when redaction is triggered manually, since
        # the automatic redaction should wait until the invitation has
        # already expired.
        before do
          invitation.redact!
        end

        it { is_expected.to eq(true) }
      end
    end

    context "before 11:59pm ET on the 14th day after the invitation was sent" do
      let(:invitation_sent_at)    { Time.zone.local(2024, 8,  1, 12, 0, 0) }
      let(:now)                   { Time.zone.local(2024, 8,  15, 23, 0, 0) }

      it {
        puts "expires_at: #{invitation.expires_at}"
        puts "now: #{now}"
        is_expected.to eq(false) }
    end

    context "after 11:59pm ET on the day of the validity window" do
      let(:invitation_sent_at) { Time.zone.local(2024, 8, 1, 12, 0, 0) }
      let(:now)                { Time.zone.local(2024, 8, 16, 0, 1, 0) }

      it { is_expected.to eq(true) }
    end
  end

  describe "#expires_at_local" do
    let(:client_agency_id) { "sandbox" }
    let(:invitation_valid_days) { 14 }
    let(:invitation) do
      create(:cbv_flow_invitation, valid_attributes.merge(
        client_agency_id: client_agency_id,
        created_at: invitation_sent_at
      ))
    end
    let(:agency_time_zone) { Rails.application.config.client_agencies[client_agency_id].timezone }
    let(:invitation_sent_at) { Time.use_zone(agency_time_zone) { Time.zone.local(2024, 8,  1, 12, 0, 0) } }

    before do
      agency_config = Rails.application.config.client_agencies[client_agency_id]
      allow(agency_config)
        .to receive(:invitation_valid_days).and_return(invitation_valid_days)

      allow(agency_config)
        .to receive(:timezone).and_return(agency_time_zone)

      travel_to(invitation_sent_at)
    end

    around do |example|
      Time.use_zone(agency_time_zone) { example.run }
    end

    it "returns the end of the day the 14th day after the invitation was sent" do
      expect(invitation.expires_at_local).to have_attributes(
        hour: 23,
        min: 59,
        sec: 59,
        month: 8,
        day: 15
      )
    end
  end

  describe "#to_url" do
    let(:invitation) { create(:cbv_flow_invitation, client_agency_id: "sandbox", language: "en") }

    before do
      stub_client_agency_config_value("sandbox", "agency_domain", "sandbox")
    end

    it "returns URL with token and locale" do
      expected_url = "https://sandbox.#{ENV["DOMAIN_NAME"]}/en/start/#{invitation.auth_token}"
      expect(invitation.to_url).to eq("#{expected_url}?")
    end
  end

  describe "foreign key constraints" do
    context "has an associated user" do
      it "has an associated user email" do
        invitation = create(:cbv_flow_invitation)
        expect(invitation.user.email).to be_a(String)
      end
    end
  end

  describe '#at_flow_limit?' do
    let(:user) { create(:user) }
    let(:cbv_applicant) { create(:cbv_applicant) }
    let(:invitation) do
      create(:cbv_flow_invitation,
             user: user,
             cbv_applicant: cbv_applicant,
             client_agency_id: 'sandbox'
      )
    end

    context 'when invitation has no flows' do
      it 'returns false' do
        expect(invitation.at_flow_limit?).to be false
      end
    end

    context 'when invitation has fewer than MAX_FLOWS_PER_INVITATION flows' do
      before do
        create_list(:cbv_flow, 99, cbv_flow_invitation: invitation, cbv_applicant: cbv_applicant)
      end

      it 'returns false' do
        expect(invitation.at_flow_limit?).to be false
      end
    end

    context 'when invitation has exactly MAX_FLOWS_PER_INVITATION flows' do
      before do
        create_list(:cbv_flow, 100, cbv_flow_invitation: invitation, cbv_applicant: cbv_applicant)
      end

      it 'returns true' do
        expect(invitation.at_flow_limit?).to be true
      end
    end

    context 'when invitation has more than MAX_FLOWS_PER_INVITATION flows' do
      before do
        create_list(:cbv_flow, 101, cbv_flow_invitation: invitation, cbv_applicant: cbv_applicant)
      end

      it 'returns true' do
        expect(invitation.at_flow_limit?).to be true
      end
    end
  end

  describe "uniquness constraints" do
    let(:invitation1) { create(:cbv_flow_invitation, client_agency_id: "sandbox", language: "en") }
    let(:invitation2) { create(:cbv_flow_invitation, client_agency_id: "sandbox", language: "en") }

    it "is able to create two invitations" do
      expect {
        invitation1
        invitation2
      }.to change(CbvFlowInvitation, :count).by(2)
    end
  end

  describe "#normalize_language" do
    it "downcases the language" do
      invitation = build(:cbv_flow_invitation, valid_attributes.merge(language: "EN"))
      invitation.validate
      expect(invitation.language).to eq("en")
    end
  end

  describe ".unstarted" do
    let!(:invitation_without_flows) { create(:cbv_flow_invitation, valid_attributes) }
    let!(:invitation_with_flow) do
      create(:cbv_flow_invitation, valid_attributes).tap do |inv|
        create(:cbv_flow, cbv_flow_invitation: inv)
      end
    end

    it "returns invitations with no flows" do
      expect(CbvFlowInvitation.unstarted).to include(invitation_without_flows)
      expect(CbvFlowInvitation.unstarted).not_to include(invitation_with_flow)
    end
  end
end
