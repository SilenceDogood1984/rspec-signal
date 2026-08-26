# frozen_string_literal: true

RSpec.describe RSpec::Signal::Backtrace::Classifier do
  def kind_of(line, config: signal_config)
    parse_frames([line], config: config).first.kind
  end

  describe "framework frames" do
    {
      "rspec-core" => "/usr/local/bundle/gems/rspec-core-3.13.6/lib/rspec/core/example.rb:263:in `run'",
      "rspec-rails" => "/usr/local/bundle/gems/rspec-rails-8.0.4/lib/rspec/rails/adapters.rb:71:in `run'",
      "rspec-expectations" =>
        "/usr/local/bundle/gems/rspec-expectations-3.13.5/lib/rspec/expectations/handler.rb:40:in `x'",
      "rspec-mocks" => "/usr/local/bundle/gems/rspec-mocks-3.13.8/lib/rspec/mocks/proxy.rb:11:in `x'",
      "bundler" => "/usr/local/bundle/gems/bundler-2.6.9/lib/bundler/cli/exec.rb:59:in `load'",
      "thor" => "/usr/local/bundle/gems/thor-1.3.2/lib/thor/command.rb:28:in `run'",
      "rake" => "/usr/local/bundle/gems/rake-13.2.1/lib/rake/task.rb:281:in `execute'",
      "bin/rspec" => "/usr/local/bundle/bin/rspec:25:in `<top (required)>'",
      "bin/bundle" => "/usr/local/bin/bundle:25:in `<main>'",
      "kernel_require" => "<internal:/usr/local/lib/ruby/3.3.0/rubygems/core_ext/kernel_require.rb>:136:in `require'",
      "minitest" => "/usr/local/bundle/gems/minitest-5.25.4/lib/minitest/test.rb:94:in `run'",
      "simplecov" => "/usr/local/bundle/gems/simplecov-0.22.0/lib/simplecov.rb:100:in `start'"
    }.each do |label, line|
      it "treats #{label} as framework plumbing" do
        expect(kind_of(line)).to eq(:framework)
      end
    end
  end

  describe "library frames" do
    # These can genuinely explain what operation failed, so they are never
    # classified as plumbing even though most get collapsed anyway.
    {
      "capybara" => "/usr/local/bundle/gems/capybara-3.40.0/lib/capybara/node/finders.rb:60:in `find'",
      "activerecord" => "/usr/local/bundle/gems/activerecord-8.0.4/lib/active_record/validations.rb:80:in `x'",
      "rack" => "/usr/local/bundle/gems/rack-3.1.8/lib/rack/sendfile.rb:110:in `call'",
      "stdlib" => "/usr/local/lib/ruby/3.3.0/json/common.rb:216:in `parse'"
    }.each do |label, line|
      it "treats #{label} as library code" do
        expect(kind_of(line)).to eq(:external)
      end
    end
  end

  describe "project frames" do
    it "recognises application, lib and spec code" do
      expect(kind_of("/srv/app/app/models/user.rb:1:in `x'")).to eq(:project)
      expect(kind_of("/srv/app/lib/invoicer.rb:1:in `x'")).to eq(:project)
      expect(kind_of("./spec/models/user_spec.rb:1:in `x'")).to eq(:project)
    end

    # A checkout directory can contain any substring, including gem names.
    it "is not fooled by a project directory that looks like a gem" do
      config = signal_config(project_root: "/home/dev/rspec-signal-demo")

      expect(kind_of("/home/dev/rspec-signal-demo/lib/thing.rb:1:in `x'", config: config)).to eq(:project)
      expect(kind_of("/home/dev/rspec-signal-demo/spec/thing_spec.rb:1:in `x'", config: config)).to eq(:project)
    end

    it "still treats project binstubs as plumbing" do
      expect(kind_of("/srv/app/bin/rspec:15:in `<main>'")).to eq(:framework)
      expect(kind_of("/srv/app/bin/bundle:25:in `<main>'")).to eq(:framework)
    end
  end

  describe "configurability" do
    it "lets a project mark its own code as plumbing" do
      config = signal_config(ignore_patterns: [%r{/lib/my_test_harness/}])

      expect(kind_of("/srv/app/lib/my_test_harness/runner.rb:1:in `x'", config: config)).to eq(:framework)
    end

    it "lets a project add framework patterns for third-party code" do
      config = signal_config(framework_patterns: [%r{/vendor_test_runner-}])

      expect(kind_of("/usr/local/bundle/gems/vendor_test_runner-1.0/lib/x.rb:1:in `y'", config: config))
        .to eq(:framework)
    end

    it "lets a project widen what counts as first party" do
      config = signal_config(extra_first_party: ["/srv/engines/billing"])

      expect(kind_of("/srv/engines/billing/app/models/invoice.rb:1:in `x'", config: config)).to eq(:project)
    end
  end
end
