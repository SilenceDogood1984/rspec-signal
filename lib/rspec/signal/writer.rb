# frozen_string_literal: true

require "fileutils"
require "tempfile"

module RSpec
  module Signal
    # Puts artifacts on disk.
    #
    # A run with no failures removes artifacts from previous runs, so an agent
    # can never be handed a stale report that describes failures you already
    # fixed.
    class Writer
      SIGNAL   = "signal.md"
      JSON     = "signal.json"
      FULL     = "full.txt"
      MANAGED  = [SIGNAL, JSON, FULL].freeze

      Result = Struct.new(:summary_path, :written, :cleaned, keyword_init: true)

      def initialize(config)
        @config = config
      end

      def dir
        @config.output_path
      end

      def write(report)
        return clean unless report.reportable?

        FileUtils.mkdir_p(dir)
        write_gitignore

        rendered = render_artifacts(report)
        publish(rendered)
      end

      # Invalidating is deliberately separate from rendering. Callers do this
      # at the beginning of a run, so an abort before #write cannot make the
      # preceding run look current. History uses different names and is never
      # included in MANAGED.
      def invalidate_current!
        remove(MANAGED)
      end

      # Relative to the project root when possible, because that is what you
      # type and what an agent resolves.
      def relative(path)
        root = "#{@config.root}/"
        path.start_with?(root) ? path[root.length..] : path
      end

      private

      def render_artifacts(report)
        artifacts = { SIGNAL => Reporters::Markdown.new(report, @config).render }
        artifacts[JSON] = Reporters::JsonReport.new(report, @config).render if @config.write_json
        artifacts[FULL] = Reporters::FullOutput.new(report, @config).render if @config.write_full
        artifacts
      end

      # signal.md is the publication marker. Supporting artifacts are moved
      # first and the marker last, so its presence always identifies a fully
      # published generation. All content is staged beside its destination so
      # rename remains on the same filesystem.
      def publish(rendered)
        staged = stage(rendered)
        cleaned = invalidate_current!
        published = []
        publication_order(rendered.keys).each do |name|
          File.rename(staged.fetch(name).path, File.join(dir, name))
          published << File.join(dir, name)
        end
        Result.new(summary_path: File.join(dir, SIGNAL), written: published, cleaned: cleaned)
      ensure
        staged&.each_value(&:close!)
      end

      def stage(rendered)
        staged = {}
        rendered.each do |name, contents|
          temporary = Tempfile.new([".#{name}", ".tmp"], dir)
          temporary.binmode
          temporary.write(contents)
          temporary.flush
          temporary.fsync
          staged[name] = temporary
        end
        staged
      rescue StandardError
        temporary&.close!
        staged&.each_value(&:close!)
        raise
      end

      def publication_order(names)
        names.reject { |name| name == SIGNAL } + [SIGNAL]
      end

      def clean
        Result.new(summary_path: nil, written: [], cleaned: invalidate_current!)
      end

      def remove(names)
        names.filter_map do |name|
          path = File.join(dir, name)
          next unless File.file?(path)

          File.delete(path)
          path
        end
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
