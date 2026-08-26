# frozen_string_literal: true

require "json"

module RSpec
  module Signal
    # Rehydrates worker JSON and performs grouping once, over the complete run.
    class ParallelMerger
      Result = Struct.new(:report, :workers, :missing, :write_result, keyword_init: true)

      def initialize(registry:, config: RSpec::Signal.configuration)
        @registry = registry
        @config = config
      end

      def call
        paths = Dir[File.join(@registry, "*.path")].map { |file| File.read(file).strip }
        documents, missing = paths.partition { |path| File.file?(path) }
        payloads = documents.map { |path| JSON.parse(File.read(path)) }
        validate_configuration!(payloads)
        apply_configuration(payloads.first&.fetch("configuration", {}))
        report = aggregate(payloads)
        Result.new(
          report: report,
          workers: payloads.size,
          missing: missing,
          write_result: Writer.new(@config).write(report)
        )
      end

      private

      def aggregate(payloads)
        summaries = payloads.map { |payload| payload.fetch("summary", {}) }
        Report.new(
          failures: load_failures(payloads),
          example_count: sum(summaries, "examples"), failure_count: sum(summaries, "failures"),
          pending_count: sum(summaries, "pending"),
          duration: summaries.filter_map { |item| item["duration_seconds"] }.max,
          environment: payloads.first&.fetch("environment", {}) || {},
          errors_outside_examples: sum(summaries, "errors_outside_examples"), relate_failures: @config.relate_failures
        )
      end

      def load_failures(payloads)
        payloads.flat_map do |payload|
          payload.fetch("failures", []).map { |failure| load_failure(failure) }
        end
      end

      def load_failure(data)
        entries = data.fetch("trace", []).map { |entry| load_entry(entry) }
        frames = entries.select(&:frame?)
        reduced = Backtrace::Reduced.new(entries: entries, total: frames.size + data.fetch("omitted_frames", 0),
                                         omitted: { serialized: data.fetch("omitted_frames", 0) })
        fingerprint = data["fingerprint"] || {}
        Failure.new(**failure_attributes(data, reduced, frames), fingerprint: load_fingerprint(fingerprint))
      end

      def failure_attributes(data, reduced, frames)
        { description: data.fetch("description"), spec_location: data.fetch("location"),
          rerun: data["rerun"], example_id: data["id"], exception_class: data.fetch("exception"),
          message: load_message(data.fetch("message", [])), reduced: reduced, frames: frames,
          diagnostics: data.fetch("diagnostics", {}), raw: data["raw"] }
      end

      def load_fingerprint(data)
        Fingerprint.new(exception_class: data["exception"], message: "worker", culprit: data["culprit"],
                        app_context: data["app_context"]).tap do |fingerprint|
          fingerprint.instance_variable_set(:@digest, data["digest"])
        end
      end

      def load_entry(entry)
        return Backtrace::Gap.new(count: entry.fetch("omitted"), kind: entry.fetch("kind").to_sym) if entry["omitted"]

        location = entry.fetch("location")
        match = location.match(/\A(.+):(\d+)\z/)
        path, line = match ? match.captures : [location, nil]
        Backtrace::Frame.new(raw: location, path: path, display_path: path, line: line&.to_i,
                             label: entry["label"], kind: entry.fetch("kind").to_sym, gem_name: entry["gem"])
      end

      def load_message(lines)
        Message.new(lines, redactor: @config.redactor, project: @config.project, html_threshold: nil)
      end

      def sum(items, key)
        number = items.sum { |item| item.fetch(key, 0).to_f }
        (number % 1).zero? ? number.to_i : number
      end

      def validate_configuration!(payloads)
        configurations = payloads.map { |payload| payload.fetch("configuration", {}) }.uniq
        return if configurations.size <= 1

        raise ArgumentError, "workers reported inconsistent rspec-signal configuration"
      end

      def apply_configuration(values)
        values.each { |name, value| @config.public_send("#{name}=", value) if @config.respond_to?("#{name}=") }
        @config.reset_memoized!
      end
    end
  end
end
