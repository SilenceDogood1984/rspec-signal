# frozen_string_literal: true

require "json"
require "fileutils"
require "time"

module RSpec
  module Signal
    # A short, deliberately boring record of recent runs, so that a run can say
    # what changed rather than describing itself as if it were the first.
    #
    # Signature digests and counts contain no messages or source. Selection
    # entries add only a digest and normalized scope details so a developer can
    # diagnose why two runs did not compare. The file stays
    # small by construction and is capped at {MAX_RUNS}.
    #
    # It survives a green run on purpose: "42 failures became 0" is the most
    # valuable comparison there is, and the run that deletes the report is
    # exactly the run that should be able to say it.
    #
    # Every operation is best effort. A missing, unreadable or corrupt history
    # simply means this run has nothing to compare against, which is the
    # behaviour of every run before this feature existed.
    class History
      FILE = "history.json"
      # 3 adds selection identity. Older runs cannot safely be compared because
      # they did not record which examples their signatures represent.
      SCHEMA = 3
      MAX_RUNS = 10

      def initialize(config)
        @config = config
      end

      def path
        File.join(@config.output_path, FILE)
      end

      # @return [Comparison, nil]
      def compare(report, run_id:)
        return nil unless report.selection

        previous = runs.reverse.find do |entry|
          report.selection.equivalent?(Selection.from_h(entry["selection"]))
        end
        return nil unless previous

        Comparison.new(previous: previous, current: snapshot(report, run_id: run_id))
      rescue StandardError
        nil
      end

      # Appends this run and trims the file to the most recent {MAX_RUNS}.
      def record(report, run_id:)
        entry = snapshot(report, run_id: run_id)
        kept = (runs + [entry]).last(MAX_RUNS)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, "#{JSON.pretty_generate({ "schema" => SCHEMA, "runs" => kept })}\n")
        entry
      rescue StandardError
        nil
      end

      def runs
        @runs ||= load
      end

      private

      def load
        return [] unless File.file?(path)

        document = JSON.parse(File.read(path))
        return [] unless document.is_a?(Hash) && document["schema"] == SCHEMA

        Array(document["runs"]).grep(Hash)
      rescue StandardError
        []
      end

      def snapshot(report, run_id:)
        {
          "run_id" => run_id,
          "at" => Time.now.utc.iso8601,
          "examples" => report.example_count,
          "failures" => report.failure_count,
          "selection" => report.selection&.to_h,
          "signatures" => report.groups.map { |group| signature_h(group) }
        }
      end

      def signature_h(group)
        {
          "digest" => group.fingerprint.digest,
          "loose" => group.fingerprint.loose_digest,
          "exception" => group.exception_class,
          "count" => group.size
        }
      end
    end
  end
end
