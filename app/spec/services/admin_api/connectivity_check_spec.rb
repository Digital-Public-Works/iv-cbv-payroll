require "rails_helper"

RSpec.describe AdminApi::ConnectivityCheck do
  let(:partner) { PartnerConfig.find_by!(partner_id: "sandbox") }

  def method_with(type, configs)
    method = partner.partner_transmission_methods.create!(method_type: type)
    configs.each { |key, value| method.partner_transmission_configs.create!(key: key, value: value, is_encrypted: key == "password") }
    method
  end

  describe "sftp" do
    let(:method) { method_with("sftp", "url" => "sftp.example.org", "user" => "agency", "password" => "pw", "path_prefix" => "inbox") }
    let(:sftp) { instance_double(Net::SFTP::Session, connect!: true, stat!: true, close_channel: true) }

    it "connects, authenticates and stats path_prefix" do
      session = instance_double(Net::SSH::Connection::Session)
      allow(Net::SSH).to receive(:start).and_yield(session)
      allow(Net::SFTP::Session).to receive(:new).with(session).and_return(sftp)

      result = described_class.call(method)

      expect(Net::SSH).to have_received(:start).with("sftp.example.org", "agency", hash_including(password: "pw", port: 22))
      expect(result).to include(ok: true, kind: "handshake")
      expect(sftp).to have_received(:stat!).with("inbox")
      expect(result[:detail]).not_to include("pw")
    end

    it "reports an authentication failure" do
      allow(Net::SSH).to receive(:start).and_raise(Net::SSH::AuthenticationFailed, "Authentication failed for user agency@sftp.example.org")

      expect(described_class.call(method)).to include(ok: false, kind: "handshake", detail: a_string_including("AuthenticationFailed"))
    end
  end

  describe "unencrypted_s3" do
    it "calls HeadBucket" do
      method = method_with("unencrypted_s3", "bucket" => "reports", "region" => "us-east-1", "path_prefix" => "")
      s3 = instance_double(S3Service, head_bucket: true)
      allow(S3Service).to receive(:new).and_return(s3)

      expect(described_class.call(method)).to include(ok: true, kind: "handshake", detail: a_string_including("reports"))
    end

    it "fails without a bucket" do
      method = method_with("unencrypted_s3", "path_prefix" => "")

      expect(described_class.call(method)).to include(ok: false, detail: "No bucket configured")
    end
  end

  describe "encrypted_s3" do
    it "fails when public_key isn't a GPG key" do
      method = method_with("encrypted_s3", "bucket" => "reports", "public_key" => "not a key", "path_prefix" => "")

      expect(described_class.call(method)).to include(ok: false)
    end
  end

  describe "webhook" do
    let(:method) { method_with("webhook", "webhook_url" => "https://partner.example.org/hook", "api_key" => "k") }

    it "sends OPTIONS and reports reachability" do
      stub_request(:options, "https://partner.example.org/hook").to_return(status: 204)

      expect(described_class.call(method)).to include(ok: true, kind: "reachability", detail: a_string_including("OPTIONS", "204"))
    end

    it "falls back to HEAD when OPTIONS isn't allowed" do
      stub_request(:options, "https://partner.example.org/hook").to_return(status: 405)
      stub_request(:head, "https://partner.example.org/hook").to_return(status: 200)

      expect(described_class.call(method)).to include(ok: true, detail: a_string_including("HEAD", "200"))
    end

    it "fails on a server error or no answer" do
      stub_request(:options, "https://partner.example.org/hook").to_return(status: 503)
      expect(described_class.call(method)).to include(ok: false)

      stub_request(:options, "https://partner.example.org/hook").to_timeout
      expect(described_class.call(method)).to include(ok: false, kind: "reachability")
    end

    it "never posts a delivery" do
      stub_request(:options, "https://partner.example.org/hook").to_return(status: 204)
      described_class.call(method)

      expect(a_request(:post, "https://partner.example.org/hook")).not_to have_been_made
    end
  end

  it "doesn't check shared email" do
    method = method_with("shared_email", "email" => "x@example.org")

    expect(described_class.call(method)).to include(ok: false, kind: "not_applicable")
  end
end
