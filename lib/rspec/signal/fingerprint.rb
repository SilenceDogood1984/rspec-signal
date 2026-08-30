# frozen_string_literal: true

require "digest"

module RSpec
  module Signal
    # A deterministic identity for a failure, used to collapse repeats.
    #
    # Four components, in decreasing order of how often they matter:
    #
    #   exception_class   ArgumentError, Capybara::ElementNotFound, ...
    #   message           normalized (ids, addresses, timestamps and paths masked)
    #   culprit           innermost frame that is not test-runner plumbing --
    #                     the code that actually raised
    #   app_context       innermost first-party frame outside the spec suite --
    #                     nil for pure matcher failures, decisive when two
    #                     different call sites produce the same error
    #
    # Notably absent: the example description and the example's own location.
    # Fourteen specs that all trip over the same missing DOM node are one
    # problem, not fourteen.
    Fingerprint = Struct.new(:exception_class, :message, :culprit, :app_context, keyword_init: true)

    # Constants inside a `Struct.new` block would land on the enclosing module,
    # so define this one explicitly.
    Fingerprint::DEFAULT_SPEC_PATTERNS = [%r{\Aspec/}, %r{\Atest/}, /_spec\.rb\z/, /_test\.rb\z/].freeze

    # Construction and rendering for the fingerprint value object above.
    class Fingerprint
      def self.for(exception_class:, message:, frames:, fallback_location:, spec_patterns: DEFAULT_SPEC_PATTERNS)
        significant = frames.reject(&:framework?)
        culprit = significant.first
        app_context = significant.find do |frame|
          frame.project? && !spec_frame?(frame, spec_patterns)
        end

        new(
          exception_class: exception_class.to_s,
          message: message.to_s,
          culprit: culprit&.location || fallback_location,
          app_context: app_context&.location
        )
      end

      # Whether a frame belongs to the spec suite rather than the application.
      # Shared by fingerprinting and by the code-path analysis, which both need
      # to look past the example that happened to trip over the bug.
      def self.spec_frame?(frame, spec_patterns = DEFAULT_SPEC_PATTERNS)
        spec_patterns.any? { |pattern| pattern.match?(frame.display_path) }
      end

      # A line-number-independent identity: the exception and its normalized
      # message, without the frames. Two runs of the same broken code report
      # the same digest even after an edit shifts the raise site, which is what
      # lets a run comparison tell "moved" apart from "fixed, and a new one".
      def loose_digest
        @loose_digest ||= Digest::SHA256.hexdigest([exception_class, message].join("\0"))[0, 12]
      end

      # Joined on NUL so that shifting text from one component into the next
      # cannot produce the same digest.
      def digest
        @digest ||= Digest::SHA256.hexdigest(to_a.join("\0"))[0, 12]
      end

      def to_h
        { exception: exception_class, culprit: culprit, app_context: app_context, digest: digest }.compact
      end
    end
  end
end
