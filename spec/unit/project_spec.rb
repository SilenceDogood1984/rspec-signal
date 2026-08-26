# frozen_string_literal: true

RSpec.describe RSpec::Signal::Project do
  subject(:project) { described_class.new(root: "/srv/app") }

  describe "#first_party?" do
    it "accepts application code" do
      expect(project).to be_first_party("/srv/app/app/models/user.rb")
      expect(project).to be_first_party("/srv/app/lib/invoicer.rb")
      expect(project).to be_first_party("/srv/app/spec/models/user_spec.rb")
    end

    it "accepts relative paths as RSpec emits them" do
      expect(project).to be_first_party("./spec/models/user_spec.rb")
      expect(project).to be_first_party("spec/models/user_spec.rb")
    end

    it "rejects installed gems" do
      expect(project).not_to be_first_party("/usr/local/bundle/gems/capybara-3.40.0/lib/capybara.rb")
    end

    it "rejects gems vendored inside the project" do
      expect(project).not_to be_first_party("/srv/app/vendor/bundle/ruby/3.3.0/gems/rack-3.1.8/lib/rack.rb")
    end

    it "rejects node_modules and tmp" do
      expect(project).not_to be_first_party("/srv/app/node_modules/foo/index.rb")
      expect(project).not_to be_first_party("/srv/app/tmp/cache/thing.rb")
    end

    it "accepts explicitly configured extra roots, such as a sibling engine" do
      project = described_class.new(root: "/srv/app", extra_first_party: ["/srv/engines/billing"])

      expect(project).to be_first_party("/srv/engines/billing/app/models/invoice.rb")
    end

    it "treats a local engine inside the project as first party" do
      expect(project).to be_first_party("/srv/app/engines/billing/app/models/invoice.rb")
    end
  end

  describe "#display_path" do
    it "makes project paths relative" do
      expect(project.display_path("/srv/app/app/models/user.rb")).to eq("app/models/user.rb")
    end

    it "strips the gem version" do
      expect(project.display_path("/usr/local/bundle/gems/capybara-3.40.0/lib/capybara/node/finders.rb"))
        .to eq("capybara/node/finders.rb")
    end

    it "does not repeat the gem name in two spellings" do
      expect(project.display_path("/usr/local/bundle/gems/activerecord-8.0.4/lib/active_record/validations.rb"))
        .to eq("activerecord/validations.rb")
      expect(project.display_path("/usr/local/bundle/gems/rspec-core-3.13.6/lib/rspec/core/example.rb"))
        .to eq("rspec-core/example.rb")
    end

    it "keeps a meaningful sub-namespace" do
      expect(project.display_path("/usr/local/bundle/gems/actionpack-8.0.4/lib/action_controller/metal.rb"))
        .to eq("actionpack/action_controller/metal.rb")
    end

    it "handles git-sourced gems" do
      expect(project.display_path("/usr/local/bundle/bundler/gems/some_gem-4f2a1c9b7e30/lib/some_gem/thing.rb"))
        .to eq("some_gem/thing.rb")
    end

    it "labels the standard library" do
      expect(project.display_path("/usr/local/lib/ruby/3.3.0/json/common.rb")).to eq("ruby/json/common.rb")
    end

    it "leaves unknown absolute paths alone" do
      expect(project.display_path("/opt/weird/thing.rb")).to eq("/opt/weird/thing.rb")
    end
  end

  describe "#gem_name" do
    it "extracts the gem a frame belongs to" do
      expect(project.gem_name("/usr/local/bundle/gems/capybara-3.40.0/lib/capybara.rb")).to eq("capybara")
    end

    it "returns nil for project code" do
      expect(project.gem_name("/srv/app/app/models/user.rb")).to be_nil
    end
  end
end
