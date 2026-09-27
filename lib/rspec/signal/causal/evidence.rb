# frozen_string_literal: true

require "digest"

module RSpec
  module Signal
    # Experimental causal-evidence layer. See docs/design/causal-failure-intelligence.md.
    #
    # Everything under this namespace is removable: delete the directory, the
    # relationships reporter, and the few lines that call into it.
    module Causal
      # Structural facts about one failure, captured before backtrace reduction
      # throws the evidence away. Plain data: it serializes into worker payloads
      # so the parallel merger reasons over the same facts a serial run does.
      #
      #   phase         "setup" | "body" | "teardown" | "outside" | "unknown"
      #   phase_detail  "before(:context) hook", "before hook", "after hook",
      #                 "around hook", "let", or nil
      #   body_reached  true / false, or nil when it cannot be known
      #   site          the first-party line of the hook or `let` that failed
      #   origin        innermost first-party frame, spec suite included
      #   origin_kind   "app" | "support" | "spec"
      #   link_key      identity of the *underlying* exception: innermost cause
      #                 class, normalized message and origin. nil for assertion
      #                 failures, which never link on origin.
      #   wrapped       the innermost cause's class when the failure wraps one
      #   entities      missing definitions read from exception attributes
      #   identities    one token per exception object in the chain
      Evidence = Struct.new(:phase, :phase_detail, :body_reached, :site, :origin, :origin_kind,
                            :link_key, :wrapped, :entities, :identities, :file, :type,
                            keyword_init: true) do
        def to_h
          super.transform_keys(&:to_s).reject { |_, value| value.nil? || value == [] }
        end

        def self.from_h(data)
          return nil unless data.is_a?(Hash)

          new(**members.to_h { |name| [name, data[name.to_s]] }).tap do |evidence|
            evidence.entities = Array(evidence.entities)
            evidence.identities = Array(evidence.identities)
          end
        end
      end

      # Reads {Evidence} out of an exception and its parsed frames.
      #
      # Nothing here guesses. Every field is either read from a Ruby exception
      # attribute, from a frame RSpec itself put on the stack, or left nil.
      module Capture
        ASSERTION = /\ARSpec::(?:Expectations|Mocks)::|\ARSpec::Core::MultipleExceptionError/.freeze
        SPEC_FILE = /_(?:spec|test)\.rb\z/.freeze
        TEST_TREE = %r{\A(?:spec|test)/}.freeze
        MAX_CAUSES = 3
        MAX_CAUSE_FRAMES = 60

        module_function

        # @param exception [Exception]
        # @param frames [Array<Backtrace::Frame>] the full parsed backtrace
        # @param identities [Hash] compare_by_identity map shared across a run
        def call(exception, frames:, config:, identities:, example: nil)
          chain = chain(exception)
          phase, detail, reached, site = Phase.call(frames)
          origin = frames.find(&:project?)
          Evidence.new(
            phase: phase, phase_detail: detail, body_reached: reached, site: site&.location,
            origin: origin&.location, origin_kind: origin && origin_kind(origin),
            link_key: link_key(chain, origin, config),
            wrapped: chain.size > 1 ? class_name(chain.last) : nil,
            entities: chain.flat_map { |error| Entities.call(error, config) }.uniq,
            identities: chain.map { |error| identities[error] ||= "e#{identities.size + 1}" },
            **location_of(example)
          )
        end

        def location_of(example)
          example ? { file: file_of(example), type: type_of(example) } : {}
        end

        def chain(exception)
          chain = [exception]
          while (cause = chain.last.cause) && chain.none? { |seen| seen.equal?(cause) } && chain.size <= MAX_CAUSES
            chain << cause
          end
          chain
        end

        def origin_kind(frame)
          path = frame.display_path.to_s
          return "spec" if SPEC_FILE.match?(path)
          return "support" if TEST_TREE.match?(path)

          "app"
        end

        # Failures link on origin only when the *underlying* exception is the
        # same class, with the same normalized message, raised at the same
        # first-party line. That relates a wrapped exception to its bare
        # twin; it deliberately does not relate two different messages that
        # happen to leave one chokepoint.
        #
        # The exception's own message is used, never RSpec's rendering of it:
        # the rendering opens with the failing source line, which differs at
        # every call site.
        def link_key(chain, origin, config)
          innermost = chain.last
          name = class_name(innermost)
          return nil if ASSERTION.match?(class_name(chain.first)) || ASSERTION.match?(name)

          location = chain.size == 1 ? origin&.location : cause_origin(innermost, config)
          return nil unless location

          text = Message.new(innermost.message.to_s.split("\n").first(5), redactor: config.redactor,
                                                                          project: config.project,
                                                                          html_threshold: nil).normalized
          Digest::SHA256.hexdigest([name, text, location].join("\0"))[0, 12]
        end

        def cause_origin(error, config)
          frames = Backtrace::Parser.parse(Array(error.backtrace).first(MAX_CAUSE_FRAMES), config.classifier)
          frames.find(&:project?)&.location
        end

        def file_of(example)
          example.metadata[:rerun_file_path].to_s.sub(%r{\A\./}, "")
        rescue StandardError
          nil
        end

        def type_of(example)
          example.metadata[:type]&.to_s
        rescue StandardError
          nil
        end

        def class_name(error)
          name = error.class.name.to_s
          name.empty? ? "(anonymous error class)" : name
        end
      end
    end
  end
end
