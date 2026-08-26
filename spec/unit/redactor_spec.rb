# frozen_string_literal: true

RSpec.describe RSpec::Signal::Redactor do
  subject(:redactor) { described_class.new }

  def scrub(text) = redactor.call(text)

  describe "credentials it removes" do
    {
      "a bearer header" => ["Authorization: Bearer abc123def456ghi", "Bearer"],
      "a basic header" => ["Authorization: Basic dXNlcjpwYXNz", "Basic"],
      "a hash password" => ['{"password" => "hunter2"}', "password"],
      "a symbol-key secret" => ['api_key: "sk_live_51H8xQ2abcdef"', "api_key"],
      "a bare assignment" => ["token = ghp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "token"],
      "a query parameter" => ["https://api.test/v1?access_token=SEKRET&page=2", "access_token"],
      "url userinfo" => ["https://admin:s3cret@internal.test/health", "admin"]
    }.each do |label, (input, kept)|
      it "redacts #{label} while keeping enough context to know what was removed" do
        result = scrub(input)

        expect(result).to include(described_class::PLACEHOLDER)
        expect(result).to include(kept)
      end
    end

    {
      "an AWS access key id" => "AKIAIOSFODNN7EXAMPLE",
      "a GitHub token" => "ghp_1234567890abcdefghijklmnopqrstuvwxyz",
      "a GitHub fine-grained token" => "github_pat_11ABCDEFG0abcdefghijklmnop",
      "a Slack token" => "xoxb-123456789012-abcdefghijkl",
      "a Stripe live key" => "sk_live_51H8xQ2abcdefghij",
      "a GitLab token" => "glpat-abcdefghij1234567890",
      "a JWT" => "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0In0.dBjftJeZ4CVPmB92K27uhbUJU1p1r_wW1g"
    }.each do |label, secret|
      it "redacts #{label} anywhere it appears" do
        expect(scrub("value was #{secret} yesterday")).not_to include(secret)
      end
    end

    it "redacts a PEM private key block" do
      pem = "-----BEGIN RSA PRIVATE KEY-----\nMIIEow==\n-----END RSA PRIVATE KEY-----"

      expect(scrub("key: #{pem}")).not_to include("MIIEow==")
    end
  end

  describe "diagnostic content it must not destroy" do
    [
      "expected 3 items, got 4",
      'expected: "Ada Lovelace"',
      "undefined method `password_digest' for nil",
      "Unable to find css \"#reader-shelf\"",
      "app/models/user.rb:42:in `authenticate'",
      "Validation failed: Email has already been taken",
      "https://example.test/users/12/edit"
    ].each do |text|
      it "leaves #{text.inspect} untouched" do
        expect(scrub(text)).to eq(text)
      end
    end
  end

  describe "configuration" do
    it "can be turned off entirely" do
      redactor = described_class.new(enabled: false)

      expect(redactor.call("password: 'hunter2'")).to eq("password: 'hunter2'")
    end

    it "accepts extra patterns" do
      redactor = described_class.new(extra_patterns: [/INTERNAL-[A-Z0-9]+/])

      expect(redactor.call("id INTERNAL-99XY here")).to eq("id #{described_class::PLACEHOLDER} here")
    end

    it "accepts a custom filter that runs last" do
      redactor = described_class.new(filter: ->(text) { text.gsub("Ada", "***") })

      expect(redactor.call("Ada Lovelace")).to eq("*** Lovelace")
    end
  end

  it "handles nil" do
    expect(scrub(nil)).to be_nil
  end
end
