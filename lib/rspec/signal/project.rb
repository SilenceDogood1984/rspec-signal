# frozen_string_literal: true

module RSpec
  module Signal
    # Knows which paths belong to the project under test ("first party") and how
    # to render any path compactly.
    #
    # First-party means: the host application's own code, plus code from gems
    # that are developed alongside it (Bundler `path:` sources, local Rails
    # engines). Those are things the agent can actually open and edit.
    class Project
      # Directories that live inside the project root but are not project code.
      VENDORED = %w[
        vendor/bundle vendor/cache vendor/ruby .bundle node_modules
        tmp/ .git/ coverage/
      ].freeze

      # Matches ".../gems/capybara-3.40.0/lib/capybara/node/finders.rb".
      #
      # The leading `.*/` is greedy on purpose: a RubyGems install path contains
      # "/gems/" twice ("/lib/ruby/gems/3.3.0/gems/capybara-3.40.0/..."), and it
      # is the last one that introduces the gem.
      GEM_PATH = %r{
        \A.*/(?:gems|bundler/gems)/
        (?<name>[A-Za-z0-9_.-]+?)
        # A release version, or the short SHA Bundler uses for git sources.
        (?:-(?<version>\d[\w.]*(?:-[a-z0-9]+)?|[0-9a-f]{12,40}))?
        /(?<rest>.*)\z
      }x

      # Matches ".../lib/ruby/3.3.0/json/common.rb" and ".../ruby/3.3.0/x86_64-linux/..."
      STDLIB_PATH = %r{/lib/ruby/(?:\d+\.\d+\.\d+|site_ruby|vendor_ruby)/(?:[a-z0-9_]+-[a-z0-9_-]+/)?(?<rest>.*)\z}

      attr_reader :root

      # @param root [String] absolute path to the project root
      # @param extra_first_party [Array<String>] additional absolute path prefixes
      #   to treat as first party (e.g. a sibling engine checkout)
      def initialize(root: Dir.pwd, extra_first_party: [])
        @root = File.expand_path(root)
        @root_prefix = "#{@root}/"
        @extra = extra_first_party.map { |p| "#{File.expand_path(p)}/" }
        @cache = {}
      end

      # Absolute path prefixes of Bundler `path:` gems (local gems and engines).
      # Discovered lazily and defensively: any Bundler problem simply means we
      # fall back to plain root-relative detection.
      def local_gem_prefixes
        @local_gem_prefixes ||= discover_local_gem_prefixes
      end

      def first_party?(path)
        return false if path.nil? || path.empty?

        @cache[path] ||= compute_first_party(path)
      end

      # A short, stable, human/agent readable rendering of a path.
      #
      #   /app/spec/models/user_spec.rb          -> spec/models/user_spec.rb
      #   .../gems/capybara-3.40.0/lib/capybara/node/finders.rb -> capybara/node/finders.rb
      #   .../lib/ruby/3.3.0/json/common.rb      -> ruby/json/common.rb
      def display_path(path)
        return path if path.nil? || path.empty?

        absolute = absolutize(path)
        return relative_to_root(absolute) if under?(absolute, @root_prefix) || first_party?(path)

        if (m = GEM_PATH.match(absolute))
          return "#{m[:name]}/#{strip_redundant_prefix(m[:name], m[:rest].sub(%r{\Alib/}, ""))}"
        end

        if (stdlib = STDLIB_PATH.match(absolute))
          return "ruby/#{stdlib[:rest]}"
        end

        relative_to_root(absolute)
      end

      # The gem a path belongs to, or nil.
      def gem_name(path)
        m = GEM_PATH.match(absolutize(path))
        m && m[:name]
      end

      def absolutize(path)
        stripped = path.to_s.sub(%r{\A\./}, "")
        # Ruby emits pseudo-frames that are not file paths at all: "<internal:...>",
        # "-e", "(eval)", "(irb)". Joining those to the project root would wrongly
        # make them look first party.
        return stripped if stripped.start_with?("/", "<", "-", "(")

        File.join(@root, stripped)
      end

      def relative_to_root(absolute)
        return absolute[@root_prefix.length..] if under?(absolute, @root_prefix)

        absolute
      end

      private

      # "activerecord" + "active_record/validations.rb" -> "validations.rb", so the
      # rendered frame reads `activerecord/validations.rb` rather than repeating
      # the gem name in two spellings. Only leading *directory* segments that
      # spell out the gem name are removed.
      def strip_redundant_prefix(gem_name, rest)
        segments = rest.split("/")
        dirs = segments[0..-2] || []
        target = normalize_gem_name(gem_name)

        dirs.size.downto(1) do |count|
          return segments[count..].join("/") if normalize_gem_name(dirs[0, count].join) == target
        end

        rest
      end

      def normalize_gem_name(name) = name.to_s.delete("-_")

      def compute_first_party(path)
        absolute = absolutize(path)

        if under?(absolute, @root_prefix)
          relative = absolute[@root_prefix.length..]
          return false if VENDORED.any? { |d| relative.start_with?(d) }
          # A gem unpacked anywhere under the root is still vendored code.
          return false if GEM_PATH.match?(absolute)

          return true
        end

        @extra.any? { |p| under?(absolute, p) } ||
          local_gem_prefixes.any? { |p| under?(absolute, p) }
      end

      def under?(absolute, prefix)
        absolute.start_with?(prefix)
      end

      def discover_local_gem_prefixes
        return [] unless defined?(::Bundler)

        ::Bundler.load.specs.filter_map do |gem_spec|
          source = gem_spec.source
          next unless source.class.name.to_s.include?("Source::Path")
          next unless gem_spec.full_gem_path

          "#{File.expand_path(gem_spec.full_gem_path)}/"
        end.uniq
      rescue StandardError, ::LoadError
        []
      end
    end
  end
end
