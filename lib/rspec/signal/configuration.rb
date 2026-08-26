# frozen_string_literal: true

module RSpec
  module Signal
    # Everything tunable, with defaults chosen to need no tuning.
    class Configuration
      # Where artifacts are written, relative to the project root unless absolute.
      attr_accessor :output_dir

      # Backtrace reduction budgets.
      attr_accessor :max_frames, :max_external_context, :max_project_frames, :fallback_frames

      # Message budgets. `max_html_chars` is the smallest HTML blob replaced by
      # a summary; `reduce_html` turns that off entirely.
      attr_accessor :max_message_lines, :max_diff_lines, :reduce_html, :max_html_chars

      # Report budgets. `max_affected_examples` caps the per-group list of other
      # failing examples; `max_groups` caps how many signatures are rendered in
      # full (nil means all).
      attr_accessor :max_affected_examples, :max_groups

      # Related-failure clustering. `relate_failures` turns the whole layer off;
      # the budgets cap how much of it reaches the Markdown report.
      attr_accessor :relate_failures, :max_clusters, :max_cluster_specs

      # Secret scrubbing.
      attr_accessor :redact, :redaction_patterns, :redaction_filter

      # Artifacts.
      attr_accessor :write_json, :write_full, :write_gitignore

      # Behaviour.
      attr_accessor :enabled, :terminal_summary, :capture_capybara, :capture_page_html

      # Classification.
      attr_accessor :project_root, :extra_first_party, :framework_patterns, :ignore_patterns

      def initialize
        default_budgets
        default_artifacts
        default_classification

        @output_dir       = ENV.fetch("RSPEC_SIGNAL_OUTPUT_DIR", "tmp/rspec-signal")
        @enabled          = !truthy?(ENV.fetch("RSPEC_SIGNAL_DISABLE", nil))
        @terminal_summary = true
      end

      def enabled? = !!@enabled
      def redact?  = !!@redact

      # Nil means "leave HTML alone", which is what {Message} expects.
      def html_threshold = reduce_html ? max_html_chars : nil

      def root
        @root ||= File.expand_path(@project_root || default_root)
      end

      def output_path
        @output_path ||= File.expand_path(@output_dir, root)
      end

      def project
        @project ||= Project.new(root: root, extra_first_party: extra_first_party)
      end

      def redactor
        @redactor ||= Redactor.new(
          enabled: redact?,
          extra_patterns: redaction_patterns,
          filter: redaction_filter
        )
      end

      def classifier
        @classifier ||= Backtrace::Classifier.new(
          project: project,
          framework_patterns: framework_patterns,
          ignore_patterns: ignore_patterns
        )
      end

      def reducer
        @reducer ||= Backtrace::Reducer.new(
          max_frames: max_frames,
          max_external_context: max_external_context,
          max_project_frames: max_project_frames,
          fallback_frames: fallback_frames
        )
      end

      # Memoized collaborators must be rebuilt if the user reconfigures.
      def reset_memoized!
        @root = @output_path = @project = @redactor = @classifier = @reducer = nil
        self
      end

      private

      def default_budgets
        @max_frames            = 12
        @max_external_context  = 3
        @max_project_frames    = 8
        @fallback_frames       = 6
        @max_message_lines     = 30
        @max_diff_lines        = 20
        @max_html_chars        = Message::DEFAULT_HTML_THRESHOLD
        @max_affected_examples = 25
        @max_groups            = nil
        @max_clusters          = 10
        @max_cluster_specs     = 6
      end

      def default_artifacts
        @reduce_html        = true
        @relate_failures    = true
        @redact             = true
        @redaction_patterns = []
        @redaction_filter   = nil
        @write_json         = true
        @write_full         = false
        @write_gitignore    = true
        @capture_capybara   = true
        @capture_page_html  = false
      end

      def default_classification
        @project_root       = nil
        @extra_first_party  = []
        @framework_patterns = Backtrace::Classifier::DEFAULT_FRAMEWORK_PATTERNS.dup
        @ignore_patterns    = Backtrace::Classifier::DEFAULT_IGNORE_PATTERNS.dup
      end

      def default_root
        return ::Rails.root.to_s if defined?(::Rails) && ::Rails.respond_to?(:root) && ::Rails.root

        Dir.pwd
      end

      def truthy?(value)
        %w[1 true yes on].include?(value.to_s.strip.downcase)
      end
    end
  end
end
