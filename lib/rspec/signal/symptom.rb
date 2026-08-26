# frozen_string_literal: true

module RSpec
  module Signal
    # One strong diagnostic characteristic pulled out of a failure message.
    #
    # Symptoms are what the looser "related failures" layer clusters on, and
    # they are deliberately narrow. Every extractor is anchored on a specific
    # phrase produced by a specific library -- an HTTP status mismatch, a
    # missing selector, a route that does not exist -- never on two messages
    # merely resembling each other. A failure that matches nothing has no
    # symptom and joins no cluster, which is the safe direction to be wrong in.
    #
    #   kind    :http_status, :selector, ...  -- which extractor fired
    #   key     the cluster identity; equal keys mean "same symptom"
    #   label   the cluster heading, already human-readable
    #   detail  this failure's own wording of the symptom, for the symptom list
    Symptom = Struct.new(:kind, :key, :label, :detail, keyword_init: true) do
      def to_h = { kind: kind, key: key, label: label, detail: detail }
    end
  end
end
