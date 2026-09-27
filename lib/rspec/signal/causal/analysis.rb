# frozen_string_literal: true

module RSpec
  module Signal
    module Causal
      # One exact signature, or one set of identical errors outside examples.
      # Signatures stay authoritative: this layer relates them, never re-cuts
      # them.
      Unit = Struct.new(:key, :failures, :outside, :position, keyword_init: true) do
        def size
          failures.size
        end

        def evidence
          failures.map(&:evidence).compact
        end

        def representative
          failures.first
        end

        def exception_class
          representative.exception_class
        end
      end

      # A classified set of units.
      #
      #   causal       structural evidence that the members share an origin.
      #                Always "high": nothing weaker is allowed to form one.
      #   scope        failures unusually concentrated in one file or one
      #                `type:`. A fact about where, never a claim about why.
      #   independent  no relationship found. Not "proven unrelated".
      Relation = Struct.new(:kind, :units, :evidence, :scope, keyword_init: true) do
        def initialize(**)
          super
          self.evidence ||= []
        end

        def failures
          units.sum(&:size)
        end

        def confidence
          kind == :causal ? "high" : nil
        end
      end

      # Relates signatures by structural evidence and reports how much of the
      # run it has classified. No weights, no similarity, no model: every
      # relationship is an equality between facts read from the run.
      class Analysis
        # The three structural relations, in the order their evidence is shown.
        LINKS = { identities: "shared_exception_object", link_key: "same_underlying_exception",
                  entities: "missing_entity" }.freeze

        SETUP = [["setup", "before(:context) hook"], ["setup", "before hook"], %w[body let]].freeze

        EVIDENCE_ORDER = %w[shared_exception_object missing_entity outside_examples same_underlying_exception
                            setup_failure setup_code failed_in_let teardown_failure].freeze

        attr_reader :relations, :hints, :expected

        def self.call(report)
          outside = Grouper.call(report.outside_example_failures)
          units = report.groups.map { |group| unit(group, false) } + outside.map { |group| unit(group, true) }
          units.each_with_index { |unit, index| unit.position = index }
          new(units, census: report.census,
                     expected: report.failure_count + report.errors_outside_examples)
        end

        def self.unit(group, outside)
          key = outside ? "outside:#{group.fingerprint.digest}" : group.fingerprint.digest
          Unit.new(key: key, failures: group.failures, outside: outside)
        end

        def initialize(units, census:, expected:)
          @units = units
          @census = census
          @expected = expected
          @hints = []
          causal, residual = relate
          scoped, independent = ScopeAnalysis.call(residual, @census)
          @relations = causal + scoped + independent.map { |unit| Relation.new(kind: :independent, units: [unit]) }
          @hints.concat(same_origin_hints)
          @hints.concat(reused_instance_hints)
        end

        def accounted
          @relations.sum(&:failures)
        end

        def count(kind)
          @relations.select { |relation| relation.kind == kind }.sum(&:failures)
        end

        def not_captured
          [@expected - accounted, 0].max
        end

        # Whether there is anything to say beyond the signatures themselves.
        def informative?
          @relations.any? { |relation| relation.kind != :independent }
        end

        private

        # ---- causal ------------------------------------------------------

        def relate
          links = structural_links
          parent = @units.map(&:position)
          links.map(&:first).each { |units| units.each_cons(2) { |a, b| union(parent, a.position, b.position) } }

          causal, residual = components(parent, links).partition { |members, evidence| causal?(members, evidence) }
          relations = causal.map { |members, evidence| Relation.new(kind: :causal, units: members, evidence: evidence) }
          [relations.sort_by { |relation| [-relation.failures, relation.units.first.position] },
           residual.flat_map(&:first)]
        end

        # [units, evidence] for every value of a linking field that more than
        # one unit carries.
        def structural_links
          LINKS.flat_map do |field, type|
            shared(field).map { |value, units| [units, link_evidence(type, value, units)] }
          end
        end

        def components(parent, links)
          @units.group_by { |unit| find(parent, unit.position) }.values.map do |members|
            [members, component_evidence(members, links)]
          end
        end

        # Several related signatures always form a group. One signature forms
        # one only when it carries a fact beyond its own fingerprint.
        def causal?(members, evidence)
          members.size > 1 || (members.first.size > 1 && !evidence.empty?)
        end

        # Values of one evidence field carried by more than one unit.
        def shared(field)
          index = Hash.new { |hash, key| hash[key] = [] }
          @units.each { |unit| linkable(unit, field).each { |value| index[value] << unit } }
          index.select { |_, units| units.size > 1 }
        end

        def linkable(unit, field)
          evidence = field == :identities ? unit.evidence.select { |item| context_hook?(item) } : unit.evidence
          evidence.flat_map { |item| Array(item.public_send(field)) }.uniq
        end

        def component_evidence(members, links)
          linked = links.select { |units, _| members.include?(units.first) }.map(&:last)
          dedupe(linked + members.flat_map { |unit| facts(unit) })
        end

        def link_evidence(type, value, units)
          case type
          when "missing_entity" then entity_evidence(value)
          when "same_underlying_exception" then underlying_evidence(units)
          else { "type" => type, "detail" => "one exception object reached #{units.sum(&:size)} examples" }
          end
        end

        def underlying_evidence(units)
          wrapped = units.flat_map(&:evidence).map(&:wrapped).compact.uniq
          classes = units.map(&:exception_class).uniq
          { "type" => "same_underlying_exception", "exception" => wrapped.first || classes.first,
            "raised_as" => classes, "origin" => units.flat_map(&:evidence).map(&:origin).compact.first }.compact
        end

        def entity_evidence(value)
          kind, name = value.split(":", 2)
          { "type" => "missing_entity", "entity" => value, "kind" => kind, "name" => name }
        end

        # RSpec shares one exception object between examples in exactly one
        # case: a before(:context) hook failed. Any other sharing is an
        # exception *instance* being reused -- and Ruby keeps the first raise's
        # backtrace when an instance is raised again, so nothing about it can
        # be trusted as "raised once". That is a hint, never a link.
        def context_hook?(evidence)
          evidence.phase_detail == "before(:context) hook"
        end

        def reused_instance_hints
          carriers = Hash.new { |hash, key| hash[key] = [] }
          @units.reject(&:outside).each do |unit|
            unit.evidence.reject { |item| context_hook?(item) }.each do |item|
              item.identities.each { |token| carriers[token] << unit.key }
            end
          end
          carriers.select { |_, owners| owners.size > 1 }.map do |_, owners|
            { "type" => "reused_exception_instance", "signatures" => owners.uniq,
              "detail" => "one exception instance was reported by #{owners.size} examples outside a " \
                          "before(:context) hook; Ruby keeps the first raise's backtrace, so its origin may be stale" }
          end.uniq
        end

        # Facts a single unit carries beyond its fingerprint, when every one of
        # its failures carries them.
        def facts(unit)
          return outside_facts(unit) if unit.outside

          evidence = unit.evidence
          return [] if evidence.empty? || evidence.size < unit.size

          common = evidence.map(&:entities).reduce(:&) || []
          shared_object_facts(unit, evidence) + phase_facts(evidence) + common.map { |value| entity_evidence(value) }
        end

        def shared_object_facts(unit, evidence)
          tokens = evidence.select { |item| context_hook?(item) }.flat_map(&:identities)
          return [] if tokens.uniq.size == tokens.size

          [{ "type" => "shared_exception_object", "detail" => "one exception object reached #{unit.size} examples" }]
        end

        # Only when every member failed in a phase that says the same thing. A
        # signature failing partly in setup and partly in the body gets none.
        def phase_facts(evidence)
          phases = evidence.map { |item| [item.phase, item.phase_detail] }.uniq
          type = phase_fact(phases)
          return [] unless type

          reached = { "teardown_failure" => true, "failed_in_let" => true, "setup_failure" => false }[type]
          [{ "type" => type, "body_reached" => reached, "phase_detail" => phases.map(&:last).join(", "),
             "sites" => evidence.map(&:site).compact.uniq.first(3) }.compact]
        end

        def phase_fact(phases)
          return "teardown_failure" if phases == [["teardown", "after hook"]]
          return "failed_in_let" if phases == [%w[body let]]
          return nil unless (phases - SETUP).empty?

          phases.include?(%w[body let]) ? "setup_code" : "setup_failure"
        end

        def outside_facts(unit)
          return [] if unit.size < 2

          files = unit.failures.map(&:rerun).uniq
          [{ "type" => "outside_examples", "files" => files.first(5), "file_count" => files.size,
             "detail" => "the same error was raised outside any example #{unit.size} times" }]
        end

        def dedupe(evidence)
          evidence.uniq { |item| [item["type"], item["entity"], item["phase_detail"]] }
                  .sort_by { |item| EVIDENCE_ORDER.index(item["type"]) || EVIDENCE_ORDER.size }
        end

        def find(parent, index)
          parent[index] = find(parent, parent[index]) unless parent[index] == index
          parent[index]
        end

        def union(parent, first, second)
          a = find(parent, first)
          b = find(parent, second)
          parent[[a, b].max] = [a, b].min unless a == b
        end

        # ---- hints -------------------------------------------------------

        # Two unrelated units raising the same class from the same first-party
        # line, with different messages. Worth knowing; not worth merging --
        # a chokepoint raises for many reasons.
        def same_origin_hints
          grouped = Hash.new { |hash, key| hash[key] = [] }
          @units.reject(&:outside).each do |unit|
            evidence = unit.evidence.first
            next unless evidence&.origin && evidence.link_key

            grouped[[unit.exception_class, evidence.origin]] << unit
          end
          grouped.filter_map do |(exception, origin), units|
            next if units.size < 2 || same_relation?(units)

            { "type" => "same_origin_different_message", "exception" => exception, "origin" => origin,
              "signatures" => units.map(&:key) }
          end
        end

        def same_relation?(units)
          owner = units.map { |unit| @relations.index { |relation| relation.units.include?(unit) } }
          owner.uniq.size == 1 && @relations[owner.first].kind == :causal
        end
      end
    end
  end
end
