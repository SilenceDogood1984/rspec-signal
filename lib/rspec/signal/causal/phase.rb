# frozen_string_literal: true

module RSpec
  module Signal
    module Causal
      # Which part of an example a failure happened in, read from the
      # rspec-core frames just outside the failing code. See {.call}.
      module Phase
        CORE_FILE = %r{/lib/rspec/core/(\w+\.rb)\z}.freeze

        # The hook methods RSpec runs a failing hook's block from. Resolved from
        # the loaded rspec-core rather than hardcoded, so line numbers moving
        # between releases cannot misclassify a frame.
        HOOKS = {
          "before hook" => %i[BeforeHook run],
          "after hook" => %i[AfterHook run],
          "around hook" => %i[AroundHook execute_with]
        }.freeze

        module_function

        # Where the failure happened relative to the example, read from the
        # rspec-core frames just outside the failing code:
        #
        #   Example#instance_exec -> Example#run            example body
        #   Example#instance_exec -> BeforeHook#run         before(:each)
        #   Example#instance_exec -> AfterHook#run          after(:each)
        #   BasicObject#instance_exec -> BeforeHook#run     before(:context)
        #                                                   (no Example involved)
        #
        # A `let` raising from inside the body is still the body: it began.
        def call(frames)
          core = frames.each_with_index.filter_map { |frame, index| [frame, index] if core_file(frame) }
          anchor = core.index { |frame, _| %w[example.rb hooks.rb].include?(core_file(frame)) }
          return ["unknown", nil, nil, nil] unless anchor

          anchor_frame, anchor_index = core[anchor]
          memoized = core.first(anchor).any? { |frame, _| core_file(frame) == "memoized_helpers.rb" }
          caller = core.drop(anchor).map(&:first).find { |frame| !frame.label.to_s.end_with?("instance_exec") }
          site = site(frames, anchor_index, memoized)
          classify(caller, core_file(anchor_frame) == "hooks.rb", memoized) + [site]
        end

        def classify(caller, context, memoized)
          return ["unknown", nil, nil] unless caller
          return ["body", memoized ? "let" : nil, true] if body_frame?(caller)

          case hook_kind(caller)
          when "before hook" then context ? ["setup", "before(:context) hook", false] : ["setup", "before hook", false]
          when "after hook" then ["teardown", "after hook", true]
          when "around hook" then ["unknown", "around hook", nil]
          else ["unknown", nil, nil]
          end
        end

        def body_frame?(frame)
          core_file(frame) == "example.rb" && /block in (?:\S+#)?run\z/.match?(frame.label.to_s)
        end

        def hook_kind(frame)
          return nil unless core_file(frame) == "hooks.rb"

          label = frame.label.to_s
          by_label = HOOKS.find { |_, (klass, method)| label.include?("#{klass}##{method}") }
          return by_label.first if by_label

          path = File.expand_path(frame.path)
          hook_sites.find { |_, file, line| file == path && frame.line.to_i.between?(line, line + 3) }&.first
        end

        def hook_sites
          @hook_sites ||= HOOKS.filter_map do |name, (klass, method)|
            file, line = ::RSpec::Core::Hooks.const_get(klass).instance_method(method).source_location
            [name, File.expand_path(file), line]
          rescue StandardError
            nil
          end
        end

        # The first-party line that *is* the failing hook or `let`: the frame
        # just inside the memoized helper for a `let`, and the outermost
        # first-party frame inside the runner otherwise.
        def site(frames, anchor_index, memoized)
          inner = frames.first(anchor_index)
          if memoized
            helper = inner.index { |frame| core_file(frame) == "memoized_helpers.rb" }
            return inner.first(helper.to_i).reverse.find(&:project?)
          end
          inner.reverse.find(&:project?)
        end

        def core_file(frame)
          frame.path.to_s[CORE_FILE, 1]
        end
      end
    end
  end
end
