# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "parallel_tests", ">= 4.0", group: %i[development test]
gem "rake", "~> 13.0"
gem "rubocop", "~> 1.66"
gem "rubocop-rspec", "~> 3.0"

# CI pins this to check the oldest supported RSpec as well as the newest.
rspec_version = ENV.fetch("RSPEC_VERSION", nil)
gem "rspec", rspec_version ? "~> #{rspec_version}.0" : ">= 3.10"
