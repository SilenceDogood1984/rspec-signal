# frozen_string_literal: true

module RSpec
  module Signal
    module Backtrace
      # One parsed backtrace line.
      #
      # `kind` is one of:
      #   :project   - first-party code the agent can open and edit
      #   :external  - third-party library code (may explain the failing operation)
      #   :framework - test-runner / loader / CLI plumbing that never explains a bug
      Frame = Struct.new(:raw, :path, :line, :label, :kind, :display_path, :gem_name, keyword_init: true) do
        def project?    = kind == :project
        def external?   = kind == :external
        def framework?  = kind == :framework

        def location
          line ? "#{display_path}:#{line}" : display_path
        end

        def to_s
          label && !label.empty? ? "#{location} in `#{label}'" : location
        end

        def to_h
          { location: location, label: label, kind: kind.to_s, gem: gem_name }.compact
        end
      end
    end
  end
end
