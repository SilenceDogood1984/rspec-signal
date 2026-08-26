# frozen_string_literal: true

module RSpec
  module Signal
    module Symptoms
      # A DOM node or piece of page text Capybara could not find.
      #
      # The same selector missing from four pages is one missing partial, one
      # renamed `data-testid`, one component that never mounted. Capybara says
      # so two different ways depending on whether you used `find` or
      # `have_css`, and those two produce different exception classes and
      # different messages, so they are correctly different signatures -- but
      # they are obviously the same symptom.
      #
      # The selector itself is the cluster key, compared exactly. Two different
      # selectors never meet.
      module Selector
        TYPES = "css|xpath|field|link or button|link|button|select box|checkbox|" \
                "radio button|file field|fillable field|element|selector|table"
        # The selector as Capybara printed it: inspected, or a bare token.
        TARGET = /"(?:[^"\\]|\\.)*"|\S+/
        VISIBILITY = "(?:visible |invisible )?"

        # `find(...)` and friends raise Capybara::ElementNotFound.
        UNABLE = /Unable to find #{VISIBILITY}(?<type>#{TYPES})\s+(?<target>#{TARGET})/i
        # `expect(page).to have_css(...)` fails the matcher instead, with a
        # different class and a different sentence for the same missing node.
        NO_MATCHES = Regexp.new("expected to find #{VISIBILITY}(?<type>#{TYPES})\\s+(?<target>#{TARGET})" \
                                ".{0,200}?but there were no matches", Regexp::IGNORECASE)
        # Page text is not a selector, but it goes missing for the same reasons.
        TEXT = /(?:Unable to find|expected to find) text (?<target>#{TARGET})/i

        module_function

        def call(_failure, text)
          match = NO_MATCHES.match(text) || UNABLE.match(text)
          return missing_text(text) unless match

          target = unquote(match[:target])
          return nil if target.empty?

          type = match[:type].to_s.downcase
          Symptom.new(kind: :selector, key: "selector:#{type}:#{target}",
                      label: "missing #{type} selector `#{safe(target)}`",
                      detail: "no match for #{type} #{target}")
        end

        def missing_text(text)
          match = TEXT.match(text)
          return nil unless match

          target = unquote(match[:target])
          return nil if target.empty?

          Symptom.new(kind: :missing_text, key: "text:#{target}",
                      label: "missing page text `#{safe(target)}`",
                      detail: "page did not contain \"#{target}\"")
        end

        # Capybara prints the selector with `inspect`, so a `[data-testid="x"]`
        # arrives with its inner quotes escaped.
        def unquote(raw)
          text = raw.to_s
          text = text[1..-2].to_s.gsub('\\"', '"').gsub("\\\\", "\\") if text.start_with?('"')
          text.gsub(/\s+/, " ").strip
        end

        def safe(target) = target.tr("`", "'")
      end
    end
  end
end
