# frozen_string_literal: true

require "json"

module RSpec
  module Signal
    module Reporters
      # Machine-readable twin of the Markdown report, for tooling and CI.
      class JsonReport
        def initialize(report, config = nil)
          @report = report
          @config = config
        end

        def render
          "#{JSON.pretty_generate(@report.to_h(@config))}\n"
        end
      end
    end
  end
end
