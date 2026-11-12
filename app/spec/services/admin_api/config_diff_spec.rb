require "rails_helper"

RSpec.describe AdminApi::ConfigDiff do
  let(:credentials) do
    {
      "argyle_environment" => "sandbox",
      "transmission_methods" => [
        { "method_type" => "sftp", "configs" => [
          { "key" => "url", "value" => "a.example.org", "encrypted" => false },
          { "key" => "password", "value" => "hunter2", "encrypted" => true }
        ] }
      ]
    }
  end

  def with_password(value, extra: [])
    credentials.deep_dup.tap do |c|
      c["transmission_methods"][0]["configs"][1]["value"] = value
      c["transmission_methods"][0]["configs"].concat(extra)
    end
  end

  it "reports secret changes as markers only" do
    after = with_password("correct-horse", extra: [ { "key" => "api_token", "value" => "tok-123", "encrypted" => true } ])
    diff = described_class.call({ credentials: credentials }, { credentials: after })

    json = diff.to_json
    %w[hunter2 correct-horse tok-123].each { |secret| expect(json).not_to include(secret) }
    expect(diff[:credentials][:transmission_methods][0][:keys]).to eq([
      { key: "api_token", change: "added", secret: true },
      { key: "password", change: "changed", secret: true }
    ])
  end

  it "treats a kept secret as unchanged" do
    diff = described_class.call({ credentials: credentials }, { credentials: with_password("$ENCRYPTED") }, kept: Set.new([ %w[sftp password] ]))

    expect(described_class.empty?(diff)).to be(true)
  end

  it "ignores order where it isn't meaningful, and respects it in usage lists" do
    settings = {
      "name" => "A",
      "application_attributes" => [ { "name" => "b" }, { "name" => "a" } ],
      "invitation_attributes" => [ { "name" => "a", "required" => true }, { "name" => "b", "required" => false } ],
      "translations" => { "es" => { "k" => "v" }, "en" => { "k" => "v" } }
    }
    reordered = settings.merge(
      "application_attributes" => settings["application_attributes"].reverse,
      "translations" => { "en" => { "k" => "v" }, "es" => { "k" => "v" } }
    )
    expect(described_class.empty?(described_class.call({ settings: settings }, { settings: reordered }))).to be(true)

    swapped = settings.merge("invitation_attributes" => settings["invitation_attributes"].reverse)
    expect(described_class.call({ settings: settings }, { settings: swapped })[:settings][:attribute_usages].size).to eq(1)
  end

  it "lists deletes" do
    diff = described_class.call(
      { settings: { "application_attributes" => [ { "name" => "a" } ], "translations" => { "en" => { "k" => "v" } } }, credentials: credentials },
      { settings: { "application_attributes" => [], "translations" => {} }, credentials: credentials.merge("transmission_methods" => []) }
    )

    expect(diff[:deletes]).to contain_exactly(
      { section: "application_attributes", name: "a" },
      { section: "translations", name: "en: k" },
      { section: "transmission_methods", name: "sftp" }
    )
  end
end
