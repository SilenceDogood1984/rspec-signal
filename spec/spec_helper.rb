# frozen_string_literal: true

require "rspec/signal"
require "tmpdir"
require "fileutils"

require_relative "fixtures/backtraces"
require_relative "fixtures/messages"
require_relative "support/builders"

RSpec.configure do |config|
  config.expect_with(:rspec) { |expectations| expectations.include_chain_clauses_in_custom_matcher_descriptions = true }
  config.mock_with(:rspec) { |mocks| mocks.verify_partial_doubles = true }
  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!
  config.warnings = false
  config.order = :random
  Kernel.srand config.seed

  config.include Builders
end
