require 'rails_helper'

RSpec.describe S3Service do
  let(:tmp_directory) { Rails.root.join('tmp') }
  let(:file_content) { "This is a test file content" }
  let(:file_name) { 'outfiles/example.tar.gz' }
  let(:file_path) { tmp_directory.join('test_file.txt').to_s }
  let(:s3_client) { instance_double(Aws::S3::Client, put_object: nil) }

  before do
    File.write(file_path, file_content)
  end

  after do
    File.delete(file_path) if File.exist?(file_path)
  end

  describe '#upload_file' do
    context 'when the config provides an access key and secret' do
      let(:config) do
        {
          "bucket" => "test-bucket",
          "region" => "us-east-2",
          "aws_access_key_id" => "AKIATESTKEY",
          "aws_secret_access_key" => "test-secret"
        }
      end

      it 'authenticates with those credentials and uploads to the configured bucket' do
        expect(Aws::S3::Client).to receive(:new).with({
          region: "us-east-2",
          access_key_id: "AKIATESTKEY",
          secret_access_key: "test-secret"
        }).and_return(s3_client)

        expect(s3_client).to receive(:put_object).with(
          bucket: "test-bucket",
          key: file_name,
          body: instance_of(File)
        )

        S3Service.new(config).upload_file(file_path, file_name)
      end
    end

    context 'when the config has no access key or secret' do
      let(:config) do
        {
          "bucket" => "test-bucket",
          "region" => "us-east-2"
        }
      end

      it 'lets the AWS SDK fall back to the default credential chain' do
        expect(Aws::S3::Client).to receive(:new).with({ region: "us-east-2" }).and_return(s3_client)

        expect(s3_client).to receive(:put_object).with(
          bucket: "test-bucket",
          key: file_name,
          body: instance_of(File)
        )

        S3Service.new(config).upload_file(file_path, file_name)
      end
    end

    context 'when the config has no region' do
      let(:config) { { "bucket" => "test-bucket" } }

      it 'omits region so the SDK resolves it from the environment' do
        expect(Aws::S3::Client).to receive(:new).with({}).and_return(s3_client)
        expect(s3_client).to receive(:put_object)

        S3Service.new(config).upload_file(file_path, file_name)
      end
    end

    context 'when only an access key is provided without a secret' do
      let(:config) do
        {
          "bucket" => "test-bucket",
          "region" => "us-east-1",
          "aws_access_key_id" => "AKIATESTKEY"
        }
      end

      it 'does not pass partial credentials to the SDK' do
        expect(Aws::S3::Client).to receive(:new).with({ region: "us-east-1" }).and_return(s3_client)
        expect(s3_client).to receive(:put_object)

        S3Service.new(config).upload_file(file_path, file_name)
      end
    end
  end
end
