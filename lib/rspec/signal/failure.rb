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

      def to_h
        {
          description: description,
          location: spec_location,
          rerun: rerun,
          id: example_id,
          exception: exception_class,
          message: message.body,
          trace: reduced.entries.map(&:to_h),
          omitted_frames: reduced.omitted_count,
          diagnostics: diagnostics,
          symptom: symptom&.to_h
        }.reject { |_, value| value.nil? || (value.respond_to?(:empty?) && value.empty?) }
      end
    end
  end
end
