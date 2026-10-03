# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "../config/environment"
require "rspec/rails"

ActiveRecord::Migration.verbose = false
load Rails.root.join("db/schema.rb")

Dir[Rails.root.join("spec/support/**/*.rb")].each { |file| require file }

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.include SignInHelper, type: :request
end
