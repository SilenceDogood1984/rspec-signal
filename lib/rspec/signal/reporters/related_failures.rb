# frozen_string_literal: true

module RSpec
  module Signal
    module Reporters
      # The "Related failures" section of the Markdown report.
      #
      # The second, looser grouping layer. A signature says "these failures are
      # the same failure"; a cluster says only "these share one strong
      # diagnostic symptom, so look at them together". The section says so in
      # those words, because the difference is the whole point: a reader who
      # takes a cluster for a root cause has been misled.
      #
      # Kept to a few lines per cluster. This layer exists to save the reader
      # from reading thirty-five signature sections, and it would be a poor
      # trade if it cost thirty-five sections' worth of prose to do it.
      class RelatedFailures
        MAX_SYMPTOMS = 4
        MAX_SIGNATURES = 8

        PREAMBLE = "Failures sharing one diagnostic symptom across more than one signature. " \
                   "Weaker than a signature: a likely common cause, not a proven identical failure. " \
                   "The signatures below remain authoritative."

        # @param clusters [Array<Cluster>]
        # @param signature_positions [Hash{String => Integer}] digest => index in the report
        def initialize(clusters, signature_positions, config)
          @clusters = clusters
          @signature_positions = signature_positions
          @config = config
        end

        # @return [String, nil] nil when nothing relates, so the section vanishes
        def render
          return nil if shown.empty?

          blocks = shown.each_with_index.map { |cluster, position| block(cluster, position + 1) }
          blocks << truncation_note if hidden.positive?
          [["## Related failures", "", PREAMBLE].join("\n"), *blocks].join("\n\n")
        end

        private

        def shown
          @shown ||= @config.max_clusters ? @clusters.first(@config.max_clusters) : @clusters
        end

        def hidden = @clusters.size - shown.size

        def truncation_note
          "_#{hidden} further related #{plural(hidden, "cluster")} not rendered (see `signal.json`)._"
        end

        def block(cluster, position)
          lines = [heading(cluster, position), ""]
          # Only worth a line when the symptom took more than one wording: with
          # one, the heading already said it.
          lines << "- Symptoms: #{symptoms(cluster)}" if cluster.symptom_counts.size > 1
          lines << "- Specs: #{specs(cluster)}"
          lines << "- Signatures: #{signatures(cluster)}"
          lines.join("\n")
        end

        def heading(cluster, position)
          "### R#{position}. #{sentence(cluster.label)} -- " \
            "#{cluster.size} #{plural(cluster.size, "example")} across " \
            "#{cluster.signature_count} #{plural(cluster.signature_count, "signature")}"
        end

        def symptoms(cluster)
          listing(cluster.symptom_counts.keys, MAX_SYMPTOMS, cluster.symptom_counts) do |detail, count|
            "`#{one_line(detail)}`#{" (#{count})" if count}"
          end
        end

        def specs(cluster)
          listing(cluster.spec_files, @config.max_cluster_specs) { |path, _| "`#{path}`" }
        end

        def signatures(cluster)
          positions = cluster.signatures.filter_map { |digest| @signature_positions[digest] }.sort
          listing(positions, MAX_SIGNATURES) { |position, _| "##{position}" }
        end

        def listing(items, limit, counts = nil)
          visible = items.first(limit)
          rendered = visible.map { |item| yield(item, counts&.fetch(item, nil)) }
          remaining = items.size - visible.size
          rendered << "and #{remaining} more" if remaining.positive?
          rendered.join(", ")
        end

        def one_line(text) = text.to_s.gsub(/\s+/, " ").strip

        def sentence(text) = text.to_s.sub(/\A[a-z]/, &:upcase)

        def plural(count, word) = count == 1 ? word : "#{word}s"
      end
    end
  end
end
