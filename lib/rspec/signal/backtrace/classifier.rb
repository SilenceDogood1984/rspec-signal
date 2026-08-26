# frozen_string_literal: true

module RSpec
  module Signal
    module Backtrace
      # Decides whether a frame is project code, meaningful library code, or
      # pure test-runner / CLI plumbing.
      #
      # The framework list is deliberately narrow: it contains only code that
      # *runs* tests, loads files, or dispatches a CLI. Application libraries
      # (ActiveRecord, Capybara, Rack, Net::HTTP, ...) are never framework, even
      # though most of their frames still get collapsed by the reducer — they can
      # legitimately explain what operation failed.
      class Classifier
        DEFAULT_FRAMEWORK_PATTERNS = [
          # RSpec itself, however it is vendored
          %r{/lib/rspec/(?:core|support|expectations|mocks|matchers|rails|its|retry)[./]},
          %r{/rspec-(?:core|support|expectations|mocks|rails|its|retry)-[^/]+/},
          %r{/lib/rspec/signal[./]},
          %r{/lib/rspec_junit_formatter[./]},
          # Bundler / RubyGems / CLI plumbing
          %r{/lib/bundler/},
          %r{/bundler-[^/]+/},
          %r{/lib/rubygems/},
          %r{/rubygems/core_ext/kernel_require\.rb},
          %r{/bundled_gems\.rb},
          %r{/thor-[^/]+/}, %r{/lib/thor/},
          %r{/rake-[^/]+/}, %r{/lib/rake/},
          # Ruby internals
          /\A<internal:/,
          %r{/lib/ruby/[^/]+/bundled_gems\.rb},
          # Other test-runner plumbing
          %r{/minitest[-/]}, %r{/lib/minitest/},
          %r{/spring-[^/]+/}, %r{/simplecov[-/]}, %r{/simplecov-html[-/]},
          %r{/parallel_tests-[^/]+/}, %r{/knapsack[-_]},
          %r{/railties-[^/]+/lib/rails/(?:commands|test_unit|app_loader)},
          %r{/lib/rails/(?:commands|test_unit|app_loader)}
        ].freeze

        # Checked *before* first-party detection. Binstubs live inside the
        # project but are still pure plumbing, and anything a user adds here is
        # taken as authoritative about their own repository.
        DEFAULT_IGNORE_PATTERNS = [
          %r{(?:\A|/)(?:bin|exe|\.bundle/bin)/(?:rspec|bundle|rake|spring)(?:\.\w+)?\z},
          # Ruby pseudo-frames: the `-e` script, eval, irb, VM internals.
          /\A-e\z/,
          /\A\((?:eval|irb)[^)]*\)\z/,
          /\A<internal:/
        ].freeze

        def initialize(project:, framework_patterns: DEFAULT_FRAMEWORK_PATTERNS,
                       ignore_patterns: DEFAULT_IGNORE_PATTERNS)
          @project = project
          @framework_patterns = framework_patterns
          @ignore_patterns = ignore_patterns
        end

        # Mutates the frame in place with :kind, :display and :gem_name.
        def call(frame)
          absolute = @project.absolutize(frame.path)
          frame.display_path = @project.display_path(frame.path)
          frame.gem_name = @project.gem_name(frame.path)
          frame.kind = classify(frame, absolute)
          frame
        end

        private

        # First-party beats the built-in framework list. Code inside the
        # repository is always something the agent can open and fix, and a
        # project directory can easily contain a substring that looks like a gem
        # name -- a checkout at ~/src/rspec-signal-demo must not have every one
        # of its own frames thrown away.
        def classify(frame, absolute)
          return :framework if matches?(@ignore_patterns, absolute, frame.path)
          return :project if @project.first_party?(frame.path)
          return :framework if matches?(@framework_patterns, absolute, frame.path)

          :external
        end

        def matches?(patterns, absolute, path)
          patterns.any? { |pattern| pattern.match?(absolute) || pattern.match?(path) }
        end
      end
    end
  end
end
