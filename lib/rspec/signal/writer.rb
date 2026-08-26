# frozen_string_literal: true

require "fileutils"

module RSpec
  module Signal
    # Puts artifacts on disk.
    #
    # A run with no failures removes artifacts from previous runs, so an agent
    # can never be handed a stale report that describes failures you already
    # fixed.
    class Writer
      SIGNAL   = "signal.md"
      SUMMARY  = "summary.md"
      JSON     = "signal.json"
      FULL     = "full.txt"
      MANAGED  = [SIGNAL, SUMMARY, JSON, FULL].freeze

      Result = Struct.new(:summary_path, :written, :cleaned, keyword_init: true)

      def initialize(config)
        @config = config
      end

      def dir = @config.output_path

      def write(report)
        return clean if report.failures.empty? && report.errors_outside_examples.zero?

        FileUtils.mkdir_p(dir)
        write_gitignore

        written = []
        markdown = Reporters::Markdown.new(report, @config).render
        written << write_file(SIGNAL, markdown)
        # Cheap compatibility for users and CI jobs created before signal.md
        # became the primary agent-facing artifact.
        written << write_file(SUMMARY, markdown)
        written << write_file(JSON, Reporters::JsonReport.new(report, @config).render) if @config.write_json
        written << write_file(FULL, Reporters::FullOutput.new(report, @config).render) if @config.write_full

        stale = MANAGED - written.map { |path| File.basename(path) }
        Result.new(summary_path: File.join(dir, SIGNAL), written: written, cleaned: remove(stale))
      end

      # Relative to the project root when possible, because that is what you
      # type and what an agent resolves.
      def relative(path)
        root = "#{@config.root}/"
        path.start_with?(root) ? path[root.length..] : path
      end

      private

      def clean
        Result.new(summary_path: nil, written: [], cleaned: remove(MANAGED))
      end

      def remove(names)
        names.filter_map do |name|
          path = File.join(dir, name)
          next unless File.file?(path)

          File.delete(path)
          path
        end
      end

      def write_file(name, contents)
        path = File.join(dir, name)
        File.write(path, contents)
        path
      end

      # Failure artifacts routinely contain application data. Keeping them out of
      # version control by default is cheap insurance.
      def write_gitignore
        return unless @config.write_gitignore

        path = File.join(dir, ".gitignore")
        return if File.exist?(path)

        File.write(path, "# Written by rspec-signal. Artifacts can contain application data.\n*\n")
      end
    end
  end
end
