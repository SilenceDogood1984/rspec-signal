# frozen_string_literal: true

module RSpec
  module Signal
    module Symptoms
      # A route that does not exist -- the usual thing sitting behind a suite
      # full of unexplained 404s.
      module Route
        NO_ROUTE = /No route matches (?<target>\[[A-Z]+\]\s*"[^"]*"|\{[^}]*\})/
        # `reader_progress_path` after the route was renamed or removed.
        HELPER = /undefined (?:local variable or method|method) [`'"](?<helper>\w+_(?:path|url))['"`]/

        module_function

        def call(_failure, text)
          match = NO_ROUTE.match(text)
          return helper(text) unless match

          target = normalize(match[:target])
          Symptom.new(kind: :route, key: "route:#{target}",
                      label: "no route matches `#{target}`", detail: "no route matches #{target}")
        end

        def helper(text)
          match = HELPER.match(text)
          return nil unless match

          name = match[:helper]
          Symptom.new(kind: :route_helper, key: "route-helper:#{name}",
                      label: "undefined route helper `#{name}`", detail: "undefined `#{name}`")
        end

        # `/readers/48213/progress` and `/readers/91055/progress` are the same
        # missing route, so identifier-shaped segments become `:id`.
        def normalize(target)
          target.to_s
                .gsub(%r{/\d+(?=/|"|\z)}, "/:id")
                .gsub(%r{/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(?=/|"|\z)}i, "/:id")
                .gsub(/\s+/, " ")
                .strip
        end
      end
    end
  end
end
