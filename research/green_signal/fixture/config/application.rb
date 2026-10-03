# frozen_string_literal: true

require "rails"
require "active_model/railtie"
require "active_record/railtie"
require "active_job/railtie"
require "action_controller/railtie"
require "action_view/railtie"

module Fixture
  # The smallest Rails application that has authentication, authorization,
  # rescue_from, transactions, jobs and templates -- the places a green
  # request spec can quietly be green for the wrong reason.
  class Application < Rails::Application
    config.load_defaults 8.0
    config.root = File.expand_path("..", __dir__)
    config.eager_load = false
    config.secret_key_base = "green-signal-fixture-#{"x" * 40}"
    config.hosts.clear
    %w[log tmp].each { |dir| FileUtils.mkdir_p(File.join(root, dir)) } # both are git-ignored
    config.logger = ActiveSupport::Logger.new(File.join(root, "log", "test.log"))
    config.log_level = :info
    config.active_support.deprecation = :stderr
    config.action_controller.allow_forgery_protection = false
    # What `rails new` writes into config/environments/test.rb.
    config.consider_all_requests_local = true
    config.action_dispatch.show_exceptions = :rescuable
    config.active_job.queue_adapter = :inline
    config.autoload_paths << root.join("app/services")
  end
end
