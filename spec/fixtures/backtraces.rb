# frozen_string_literal: true

# Realistic synthetic backtraces.
#
# These are modelled on real Rails/Capybara output: absolute paths, the same
# gem layout Bundler produces, and the same runaway tail of rspec-core hook and
# runner frames that makes real failure output unusable.
module Backtraces
  ROOT = "/srv/app"
  GEMS = "/usr/local/bundle/gems"

  module_function

  def app(path, line, label) = "#{ROOT}/#{path}:#{line}:in `#{label}'"

  def gem(name, version, path, line, label) = "#{GEMS}/#{name}-#{version}/lib/#{path}:#{line}:in `#{label}'"

  # The tail every RSpec failure drags along: hooks, the runner, the reporter,
  # Bundler and the CLI. Sixty-odd frames of pure plumbing.
  def rspec_tail
    frames = []
    frames.concat([
                    gem("rspec-core", "3.13.6", "rspec/core/example.rb", 263, "instance_exec"),
                    gem("rspec-core", "3.13.6", "rspec/core/example.rb", 263, "block in run"),
                    gem("rspec-core", "3.13.6", "rspec/core/example.rb", 511,
                        "block in with_around_and_singleton_context_hooks"),
                    gem("rspec-core", "3.13.6", "rspec/core/example.rb", 468, "block in with_around_example_hooks"),
                    gem("rspec-core", "3.13.6", "rspec/core/hooks.rb", 486, "block in run"),
                    gem("rspec-core", "3.13.6", "rspec/core/hooks.rb", 626, "run_around_example_hooks_for"),
                    gem("rspec-core", "3.13.6", "rspec/core/hooks.rb", 486, "run"),
                    gem("rspec-rails", "8.0.4", "rspec/rails/example/system_example_group.rb", 171,
                        "block in <module:SystemExampleGroup>"),
                    gem("rspec-core", "3.13.6", "rspec/core/example.rb", 468, "with_around_example_hooks"),
                    gem("rspec-core", "3.13.6", "rspec/core/example.rb", 511,
                        "with_around_and_singleton_context_hooks"),
                    gem("rspec-core", "3.13.6", "rspec/core/example.rb", 259, "run"),
                    gem("rspec-core", "3.13.6", "rspec/core/example_group.rb", 646, "block in run_examples"),
                    gem("rspec-core", "3.13.6", "rspec/core/example_group.rb", 642, "map"),
                    gem("rspec-core", "3.13.6", "rspec/core/example_group.rb", 642, "run_examples"),
                    gem("rspec-core", "3.13.6", "rspec/core/example_group.rb", 607, "run"),
                    gem("rspec-core", "3.13.6", "rspec/core/example_group.rb", 608, "block in run"),
                    gem("rspec-core", "3.13.6", "rspec/core/example_group.rb", 608, "map"),
                    gem("rspec-core", "3.13.6", "rspec/core/example_group.rb", 608, "run"),
                    gem("rspec-core", "3.13.6", "rspec/core/runner.rb", 121, "block (3 levels) in run_specs"),
                    gem("rspec-core", "3.13.6", "rspec/core/runner.rb", 121, "map"),
                    gem("rspec-core", "3.13.6", "rspec/core/runner.rb", 121, "block (2 levels) in run_specs"),
                    gem("rspec-core", "3.13.6", "rspec/core/configuration.rb", 2098, "with_suite_hooks"),
                    gem("rspec-core", "3.13.6", "rspec/core/runner.rb", 116, "block in run_specs"),
                    gem("rspec-core", "3.13.6", "rspec/core/reporter.rb", 74, "report"),
                    gem("rspec-core", "3.13.6", "rspec/core/runner.rb", 115, "run_specs"),
                    gem("rspec-core", "3.13.6", "rspec/core/runner.rb", 89, "run"),
                    gem("rspec-core", "3.13.6", "rspec/core/runner.rb", 71, "run"),
                    gem("rspec-core", "3.13.6", "rspec/core/runner.rb", 45, "invoke"),
                    "#{GEMS}/rspec-core-3.13.6/exe/rspec:4:in `<top (required)>'",
                    "/usr/local/bundle/bin/rspec:25:in `load'",
                    "/usr/local/bundle/bin/rspec:25:in `<top (required)>'",
                    gem("bundler", "2.6.9", "bundler/cli/exec.rb", 59, "load"),
                    gem("bundler", "2.6.9", "bundler/cli/exec.rb", 59, "kernel_load"),
                    gem("bundler", "2.6.9", "bundler/cli/exec.rb", 23, "run"),
                    gem("bundler", "2.6.9", "bundler/cli.rb", 492, "exec"),
                    gem("thor", "1.3.2", "thor/command.rb", 28, "run"),
                    gem("thor", "1.3.2", "thor/invocation.rb", 127, "invoke_command"),
                    gem("thor", "1.3.2", "thor.rb", 538, "dispatch"),
                    gem("bundler", "2.6.9", "bundler/cli.rb", 35, "dispatch"),
                    gem("thor", "1.3.2", "thor/base.rb", 584, "start"),
                    gem("bundler", "2.6.9", "bundler/cli.rb", 29, "start"),
                    "#{GEMS}/bundler-2.6.9/exe/bundle:28:in `block in <top (required)>'",
                    "#{GEMS}/bundler-2.6.9/exe/bundle:20:in `<top (required)>'",
                    "/usr/local/bin/bundle:25:in `load'",
                    "/usr/local/bin/bundle:25:in `<main>'"
                  ])
    # RSpec really does repeat hook frames this many times on system specs.
    12.times do |i|
      frames.insert(6 + i, gem("rspec-core", "3.13.6", "rspec/core/hooks.rb", 626 + i, "run_around_example_hooks_for"))
    end
    frames
  end

  # A Capybara element lookup that failed inside a system spec.
  def capybara_element_not_found(spec: "spec/system/reader_self_reading_integrity_spec.rb", line: 104)
    [
      gem("capybara", "3.40.0", "capybara/node/finders.rb", 312, "synced_resolve"),
      gem("capybara", "3.40.0", "capybara/node/base.rb", 84, "synchronize"),
      gem("capybara", "3.40.0", "capybara/node/finders.rb", 301, "block in synced_resolve"),
      gem("capybara", "3.40.0", "capybara/node/finders.rb", 60, "find"),
      gem("capybara", "3.40.0", "capybara/session.rb", 774, "block (2 levels) in <class:Session>"),
      gem("capybara", "3.40.0", "capybara/dsl.rb", 52, "block (2 levels) in <module:DSL>"),
      app(spec, line, "block (3 levels) in <top (required)>")
    ] + rspec_tail
  end

  # An ActiveRecord validation failure raised through application service code.
  def active_record_invalid(service: "app/services/subscription_creator.rb", service_line: 42,
                            spec: "spec/models/subscription_spec.rb", spec_line: 18)
    [
      gem("activerecord", "8.0.4", "active_record/validations.rb", 80, "raise_validation_error"),
      gem("activerecord", "8.0.4", "active_record/validations.rb", 55, "save!"),
      gem("activerecord", "8.0.4", "active_record/transactions.rb", 313, "block in save!"),
      gem("activerecord", "8.0.4", "active_record/transactions.rb", 373, "block in with_transaction_returning_status"),
      gem("activerecord", "8.0.4", "active_record/connection_adapters/abstract/transaction.rb", 606,
          "within_new_transaction"),
      gem("activerecord", "8.0.4", "active_record/transactions.rb", 370, "with_transaction_returning_status"),
      gem("activerecord", "8.0.4", "active_record/transactions.rb", 313, "save!"),
      app(service, service_line, "create!"),
      app("app/services/subscription_creator.rb", 12, "call"),
      app(spec, spec_line, "block (3 levels) in <top (required)>")
    ] + rspec_tail
  end

  # A plain matcher failure: rspec-expectations raises, the spec line is next.
  def expectation_not_met(spec: "spec/models/user_spec.rb", line: 27)
    [
      gem("rspec-expectations", "3.13.5", "rspec/expectations/fail_with.rb", 39, "fail_with"),
      gem("rspec-expectations", "3.13.5", "rspec/expectations/handler.rb", 40, "handle_failure"),
      gem("rspec-expectations", "3.13.5", "rspec/expectations/handler.rb", 51, "block in handle_matcher"),
      gem("rspec-expectations", "3.13.5", "rspec/expectations/handler.rb", 27, "with_matcher"),
      gem("rspec-expectations", "3.13.5", "rspec/expectations/handler.rb", 48, "handle_matcher"),
      gem("rspec-expectations", "3.13.5", "rspec/expectations/expectation_target.rb", 65, "to"),
      app(spec, line, "block (3 levels) in <top (required)>")
    ] + rspec_tail
  end

  # A pure Ruby project: no Rails, no Capybara, application code raising.
  def pure_ruby(lib: "lib/invoicer/calculator.rb", lib_line: 31, spec: "spec/calculator_spec.rb", spec_line: 14)
    [
      app(lib, lib_line, "apply_discount"),
      app("lib/invoicer/calculator.rb", 12, "total"),
      app(spec, spec_line, "block (2 levels) in <top (required)>")
    ] + rspec_tail
  end

  # Everything is framework: nothing survives the normal rules.
  def framework_only
    rspec_tail
  end

  # A failure entirely inside third-party code, with no first-party frame at all.
  def library_only
    [
      gem("net-http", "0.6.0", "net/http.rb", 1610, "connect"),
      gem("net-http", "0.6.0", "net/http.rb", 1587, "do_start"),
      gem("net-http", "0.6.0", "net/http.rb", 1576, "start"),
      gem("faraday", "2.12.0", "faraday/adapter/net_http.rb", 112, "perform_request")
    ] + rspec_tail
  end

  # Application code sandwiched between gem layers, with an unrelated gem-only
  # run in the middle that touches no first-party code.
  def rack_middleware_stack(spec: "spec/requests/checkout_spec.rb", spec_line: 55)
    [
      app("app/controllers/checkout_controller.rb", 22, "create"),
      gem("actionpack", "8.0.4", "action_controller/metal/basic_implicit_render.rb", 6, "send_action"),
      gem("actionpack", "8.0.4", "abstract_controller/base.rb", 226, "process_action"),
      gem("actionpack", "8.0.4", "action_controller/metal/rendering.rb", 193, "process_action"),
      gem("actionpack", "8.0.4", "abstract_controller/callbacks.rb", 261, "block in process_action"),
      gem("activesupport", "8.0.4", "active_support/callbacks.rb", 121, "block in run_callbacks"),
      app("app/controllers/concerns/authentication.rb", 18, "require_login"),
      gem("activesupport", "8.0.4", "active_support/callbacks.rb", 130, "block in run_callbacks"),
      gem("activesupport", "8.0.4", "active_support/callbacks.rb", 141, "run_callbacks"),
      gem("actionpack", "8.0.4", "abstract_controller/callbacks.rb", 260, "process_action"),
      gem("rack", "3.1.8", "rack/session/abstract/id.rb", 272, "context"),
      gem("rack", "3.1.8", "rack/sendfile.rb", 110, "call"),
      gem("railties", "8.0.4", "rails/engine.rb", 535, "call"),
      gem("rack-test", "2.1.0", "rack/test.rb", 342, "process_request"),
      app(spec, spec_line, "block (3 levels) in <top (required)>")
    ] + rspec_tail
  end

  # Repeated frames, as produced by runaway recursion.
  def recursive(depth: 200)
    (Array.new(depth) { app("app/models/tree_node.rb", 14, "descendants") } +
      [app("spec/models/tree_node_spec.rb", 9, "block (2 levels) in <top (required)>")]) + rspec_tail
  end
end
