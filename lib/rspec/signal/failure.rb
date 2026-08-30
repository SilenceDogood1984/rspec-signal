# frozen_string_literal: true

module RSpec
  module Signal
    # One failed example, normalized and reduced. Pure data -- it knows nothing
    # about RSpec, so every downstream stage is trivially testable.
    class Failure
      attr_reader :description, :spec_location, :rerun, :example_id,
                  :exception_class, :message, :reduced, :frames,
                  :diagnostics, :shared_group_locations, :raw

      def initialize(description:, spec_location:, exception_class:, message:, reduced:, frames:,
                     rerun: nil, example_id: nil, diagnostics: {}, shared_group_locations: [],
                     raw: nil, fingerprint: nil)
        @description = description
        @spec_location = spec_location
        @exception_class = exception_class
        @message = message
        @reduced = reduced
        @frames = frames
        @rerun = rerun || spec_location
        @example_id = example_id
        @diagnostics = diagnostics
        @shared_group_locations = shared_group_locations
        @raw = raw
        @fingerprint = fingerprint
      end

      # The argument that reruns exactly this example and nothing else.
      # RSpec's example id when we have one; the location, which selects every
      # example defined on that line, only as a fallback.
      def rerun_argument
        example_id || rerun
      end

      # The first-party frames worth attributing this failure to, innermost
      # first and excluding the spec suite itself. This is what the
      # cross-signature code-path analysis indexes on.
      def application_frames(limit = nil)
        frames = reduced.project_frames.reject { |frame| Fingerprint.spec_frame?(frame) }
        limit ? frames.first(limit) : frames
      end

      def fingerprint
        @fingerprint ||= Fingerprint.for(
          exception_class: exception_class,
          message: message.normalized,
          frames: frames,
          fallback_location: spec_location
        )
      end

      # The one diagnostic characteristic this failure clusters on, if any.
      # `nil` is the common and safe answer.
      def symptom
        return @symptom if defined?(@symptom)

        @symptom = Symptoms.for(self)
      end

      # @param max_message_lines [Integer] mirrors `config.max_message_lines`
      # @param max_diff_lines [Integer] mirrors `config.max_diff_lines`
      def to_h(max_message_lines: 30, max_diff_lines: 20)
        {
          description: description,
          location: spec_location,
          rerun: rerun,
          id: example_id,
          exception: exception_class,
          message: message.body(max_lines: max_message_lines, max_diff_lines: max_diff_lines),
          trace: reduced.entries.map(&:to_h),
          omitted_frames: reduced.omitted_count,
          diagnostics: diagnostics,
          shared_groups: shared_group_locations,
          symptom: symptom&.to_h
        }.reject { |_, value| value.nil? || (value.respond_to?(:empty?) && value.empty?) }
      end
    end
  end
end
