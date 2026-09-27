# frozen_string_literal: true

module RSpec
  module Signal
    module Reporters
      # Words for the experimental relationship analysis ({Causal::Analysis}):
      # a few terminal lines, a short Markdown section, and the `analysis`
      # block of `signal.json`.
      #
      # Every sentence is built from one evidence item, so nothing is said that
      # the analysis did not measure. There is no wording for a cause; there is
      # wording for "these failures share this origin" and for "these failures
      # are concentrated here".
      class Relationships
        MAX_TERMINAL_GROUPS = 3
        MAX_MARKDOWN_GROUPS = 8

        HEADING = "Relationships between signatures (experimental):"

        LEGEND = "Relationships between the signatures below, from structural evidence only. " \
                 "CAUSAL: every member shares one exception object, one underlying exception at one line, " \
                 "one missing definition, or one failing setup step -- a shared origin, not a named root cause. " \
                 "SCOPE: failures concentrated in one place; a fact about where, not why. " \
                 "INDEPENDENT: no relationship found, which is not the same as unrelated. " \
                 "Every failure is classified into exactly one group; that is bookkeeping, not a diagnosis."

        # @param analysis [Causal::Analysis]
        # @param signature_positions [Hash{String => Integer}] digest => section number
        def initialize(analysis, signature_positions = {})
          @analysis = analysis
          @positions = signature_positions
        end

        # @return [Array<String>] empty when there is nothing beyond the signatures
        def terminal_lines
          return [] unless @analysis.informative?

          shown = related.first(MAX_TERMINAL_GROUPS)
          lines = [HEADING] + shown.flat_map do |relation|
            [header(relation), *describe(relation).first(2).map do |line|
              "  #{line}"
            end]
          end
          hidden = related.size - shown.size
          lines << "(#{hidden} more related #{plural(hidden, "group")} in signal.json)" if hidden.positive?
          lines << independent_line if independent_failures.positive?
          lines << accounting_line
        end

        def markdown
          return nil unless @analysis.informative?

          blocks = related.first(MAX_MARKDOWN_GROUPS).map { |relation| markdown_block(relation) }
          blocks << "- #{independent_line}" if independent_failures.positive?
          ["## Relationships (experimental)", "", LEGEND, "", *blocks.flat_map { |block| [block, ""] },
           accounting_line].join("\n")
        end

        def to_h
          {
            "experimental" => true,
            "classified" => classified_h,
            "groups" => @analysis.relations.each_with_index.map { |relation, index| relation_h(relation, index + 1) },
            "hints" => @analysis.hints
          }
        end

        private

        def related
          @related ||= @analysis.relations.reject { |relation| relation.kind == :independent }
        end

        def independent_failures
          @analysis.count(:independent)
        end

        def header(relation)
          confidence = relation.confidence ? " · #{relation.confidence.upcase}" : ""
          "#{relation.kind.to_s.upcase}#{confidence} · #{quantity(relation.failures, "failure")} in " \
            "#{quantity(relation.units.size, "signature")}"
        end

        def independent_line
          units = @analysis.relations.count { |relation| relation.kind == :independent }
          "INDEPENDENT · #{quantity(independent_failures, "failure")} in #{quantity(units, "signature")} " \
            "(no relationship found)"
        end

        # Every failure is in exactly one group. This counts that bookkeeping;
        # it says nothing about how many root causes there are.
        def accounting_line
          line = "#{@analysis.accounted}/#{@analysis.expected} failures classified: " \
                 "#{@analysis.count(:causal)} causal, #{@analysis.count(:scope)} scope, " \
                 "#{independent_failures} independent"
          missing = @analysis.not_captured
          missing.positive? ? "#{line}; #{missing} not captured (see RSpec's output)" : line
        end

        # The sentences for one group, strongest evidence first.
        def describe(relation)
          return [concentration(relation.scope)] if relation.kind == :scope

          sentences = relation.evidence.filter_map { |item| sentence(item) }.uniq
          sentences << "raised at #{origins(relation).join(", ")}" if origins(relation).any? && sentences.size < 2
          sentences
        end

        def sentence(item)
          case item["type"]
          when "shared_exception_object" then "#{item["detail"]} (RSpec shares a before(:context) failure)"
          when "missing_entity" then entity_sentence(item)
          when "outside_examples" then "same error while loading #{quantity(item["file_count"], "spec file")}; " \
                                       "no example in them ran"
          when "same_underlying_exception" then underlying_sentence(item)
          when "setup_failure" then "failed during setup (#{item["phase_detail"]}#{site(item)}); " \
                                    "example body never reached"
          when "failed_in_let" then "failed while evaluating a `let`#{site(item)}"
          when "setup_code" then "failed in setup code (#{item["phase_detail"]})#{site(item)}"
          when "teardown_failure" then "failed during teardown (after hook#{site(item)}); example body completed"
          end
        end

        def entity_sentence(item)
          case item["kind"]
          when "env" then "missing ENV key #{item["name"]} (KeyError raised by ENV itself)"
          when "const" then "missing constant #{item["name"]} (NameError#name)"
          when "method" then "method #{item["name"]} not callable (NoMethodError on a class defined in this project)"
          end
        end

        def underlying_sentence(item)
          raised_as = Array(item["raised_as"]) - [item["exception"]]
          wrapped = raised_as.empty? ? "" : ", also raised wrapped as #{raised_as.join(", ")}"
          "same underlying #{item["exception"]} at #{item["origin"]}#{wrapped}"
        end

        def site(item)
          sites = Array(item["sites"])
          return "" if sites.empty?

          " at #{sites.first}#{" and #{sites.size - 1} more" if sites.size > 1}"
        end

        def concentration(scope)
          place = scope["dimension"] == "type" ? "in type: :#{scope["value"]} examples" : "in #{scope["value"]}"
          "failure concentration: #{scope["failed"]}/#{scope["examples"]} examples failed #{place}; " \
            "#{scope["failed_elsewhere"]}/#{scope["examples_elsewhere"]} elsewhere"
        end

        def origins(relation)
          relation.units.flat_map(&:evidence).filter_map(&:origin).uniq.first(3)
        end

        def markdown_block(relation)
          lines = ["- **#{header(relation)}**"]
          describe(relation).each { |sentence| lines << "  - #{sentence}" }
          lines << "  - Signatures: #{signature_refs(relation)}"
          lines << "  - Verify: `#{verify(relation)}`" if relation.kind == :causal
          lines.join("\n")
        end

        def signature_refs(relation)
          relation.units.map do |unit|
            position = @positions[unit.key]
            position ? "##{position}" : "`#{unit.representative.rerun}`"
          end.join(", ")
        end

        def verify(relation)
          Rerun.command([relation.units.first.representative.rerun_argument])
        end

        def classified_h
          { "failures" => @analysis.accounted, "expected" => @analysis.expected,
            "causal" => @analysis.count(:causal), "scope" => @analysis.count(:scope),
            "independent" => independent_failures, "not_captured" => @analysis.not_captured }
        end

        def relation_h(relation, number)
          {
            "id" => "G#{number}", "kind" => relation.kind.to_s, "confidence" => relation.confidence,
            "failures" => relation.failures, "summary" => describe(relation),
            "evidence" => relation.evidence, "scope" => relation.scope,
            "members" => relation.units.map { |unit| member_h(unit) },
            "verify" => relation.kind == :causal ? verify(relation) : nil,
            "experiment" => relation.kind == :causal ? nil : experiment(relation)
          }.compact
        end

        def member_h(unit)
          evidence = unit.evidence.first
          {
            (unit.outside ? "outside" : "signature") => unit.key.delete_prefix("outside:"),
            "failures" => unit.size, "exception" => unit.exception_class,
            "ids" => unit.failures.map(&:rerun_argument).uniq.first(10),
            "phase" => evidence && phase_h(unit), "origin" => evidence&.origin,
            "origin_kind" => evidence&.origin_kind, "entities" => unit.evidence.flat_map(&:entities).uniq
          }.reject { |_, value| value.nil? || value == [] }
        end

        def phase_h(unit)
          phases = unit.evidence.map { |item| [item.phase, item.phase_detail, item.body_reached] }.uniq
          return { "phase" => "mixed" } if phases.size > 1

          phase, detail, reached = phases.first
          { "phase" => phase, "detail" => detail, "body_reached" => reached }.compact
        end

        # What would tell an unrelated-looking failure apart from one that only
        # fails after something else ran.
        def experiment(relation)
          argument = relation.units.first.representative.rerun_argument
          "Rerun alone: #{Rerun.command([argument])}. If it passes alone, it depends on examples " \
            "that ran before it (try `--bisect` with the same seed)."
        end

        def quantity(count, word)
          "#{count} #{plural(count, word)}"
        end

        def plural(count, word)
          count == 1 ? word : "#{word}s"
        end
      end
    end
  end
end
