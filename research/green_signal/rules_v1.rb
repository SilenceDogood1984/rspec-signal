# frozen_string_literal: true

# FROZEN: the rule set used for the first real-repository run (findings v1).
# Kept only so those numbers can be reproduced: `analyze.rb --rules v1`.

# EXPERIMENTAL -- research spike. Deterministic rules over observer facts.
#
# Every rule pairs one runtime fact with what the example's own assertions
# constrained. A finding is *suppressed* -- counted, not shown -- when the
# example demonstrably asserted the unusual outcome itself. Nothing here
# reads the truth file, and nothing calls a model.
module GreenSignalV1
  Finding = Struct.new(:rule, :confidence, :example, :request, :evidence, :why, :suppressed, keyword_init: true) do
    def shown?
      suppressed.nil? && confidence != "LOW"
    end

    def to_h
      super.transform_keys(&:to_s)
    end
  end

  # What the example's passing expectations actually pinned down.
  class AssertionContext
    STATUS_WORDS = {
      "successful" => "2xx", "success" => "2xx", "ok" => "200", "created" => "201", "accepted" => "202",
      "no content" => "204", "redirect" => "3xx", "bad request" => "400", "unauthorized" => "401",
      "forbidden" => "403", "not found" => "404", "missing" => "404", "conflict" => "409", "gone" => "410",
      "unprocessable" => "422", "unprocessable entity" => "422", "unprocessable content" => "422",
      "client error" => "4xx", "server error" => "5xx", "error" => "5xx"
    }.freeze

    attr_reader :expectations

    def initialize(facts)
      @expectations = Array(facts["expectations"]).select { |e| e["passed"] }
      @count = facts["expectation_count"].to_i
    end

    def count
      @count
    end

    def descriptions
      @descriptions ||= @expectations.map { |e| e["description"].to_s }
    end

    # "2xx", "3xx", "404", ... one per status assertion.
    def statuses
      @statuses ||= @expectations.filter_map { |e| status_of(e) }
    end

    def status_of(expectation)
      text = expectation["description"].to_s
      if expectation["matcher"].to_s.include?("HaveHttpStatus")
        text[/\((\d{3}|[1-5]xx)\)/, 1] || text[/status code (\d{3})/, 1]
      elsif expectation["matcher"].to_s.end_with?("BePredicate") && expectation["actual"] == "response"
        STATUS_WORDS[text.sub(/\Abe /, "").tr("_", " ")]
      elsif expectation["actual"] == "status"
        text[/\b(\d{3})\b/, 1]
      end
    end

    def covers?(asserted, code)
      return asserted == code.to_s if asserted =~ /\A\d{3}\z/

      asserted[0] == code.to_s[0]
    end

    def asserted_status?(code)
      statuses.any? { |asserted| covers?(asserted, code) }
    end

    # The example expected *this* failure-looking status.
    def asserted_failure_status?(code)
      code.to_i >= 400 && asserted_status?(code)
    end

    def asserted_success?
      statuses.any? { |asserted| asserted.start_with?("2") }
    end

    def redirect_targets
      @redirect_targets ||= @expectations.filter_map do |e|
        next unless e["matcher"].to_s.include?("RedirectTo")

        e["description"].to_s[/redirect to "([^"]*)"/, 1].to_s.sub(%r{\Ahttps?://[^/]+}, "")
      end
    end

    def asserted_redirect_to?(location)
      return false if location.nil?

      target = location.split("?").first
      redirect_targets.any? { |asserted| asserted.split("?").first == target }
    end

    # Quoted literals in passing expectation descriptions: include "x", eq "x".
    def expected_strings
      @expected_strings ||= descriptions.flat_map { |text| text.scan(/"((?:[^"\\]|\\.){2,})"/).flatten }
    end

    def mentions?(text)
      needle = text.to_s.downcase.strip
      return false if needle.length < 3

      descriptions.any? { |d| d.downcase.include?(needle) } || expected_strings.any? { |s| needle.include?(s.downcase) }
    end

    def change_matchers(negated:)
      @expectations.select { |e| e["matcher"].to_s.end_with?("::Change") && e["negated"] == negated }
    end

    def any_change?
      @expectations.any? { |e| e["matcher"].to_s.end_with?("::Change") }
    end

    def summary
      return "no expectations" if @count.zero?

      list = descriptions.reject(&:empty?).uniq.first(3).map { |d| d[0, 70] }
      more = @count > list.size ? " (+#{@count - list.size} more)" : ""
      "#{list.join("; ")}#{more}"
    end
  end

  # The rules. Each returns zero or more findings for one passed example.
  class Rules
    PROGRAMMING_ERRORS = %w[NoMethodError NameError TypeError ArgumentError ZeroDivisionError KeyError
                            NotImplementedError FrozenError LocalJumpError SystemStackError IndexError].freeze
    AUTHENTICATION = /authenticat|sign_?in|log_?in|logged_in|require_(?:user|login|session)|session/i.freeze
    ERROR_TEMPLATE = %r{(?:\A|/)(?:errors?|error_pages?|exceptions?)/|(?:\A|/)_?(?:not_found|404|500|422|error|fallback|unavailable)\.}.freeze
    MUTATING = %w[POST PUT PATCH DELETE].freeze
    MUTATION_WORDS = /\b(?:creat|updat|sav|delet|destroy|remov|archiv|import|add|chang|edit|renam)\w*/i.freeze

    def initialize(root: nil)
      @root = root
    end

    def call(facts)
      return [] unless facts["status"] == "passed"

      @facts = facts
      @ctx = AssertionContext.new(facts)
      @findings = []
      requests.each_with_index { |request, index| request_rules(request, index) }
      example_rules
      @findings
    end

    private

    attr_reader :ctx

    def requests
      Array(@facts["requests"])
    end

    def issued
      Array(@facts["issued"])
    end

    def issued_for(request)
      index = request["issued_index"]
      index && issued[index]
    end

    # Setup: issued from a before/let hook, or by a helper, and not the last
    # thing the example asked for.
    def setup?(request)
      origin = issued_for(request)
      return false unless origin

      last = origin.equal?(issued.last)
      %w[before around].include?(origin["phase"]) || (origin["helper_site"] && !last)
    end

    def subject_request
      requests.reverse.find { |request| !setup?(request) }
    end

    def request_rules(request, _index)
      return setup_rules(request) if setup?(request)

      auth_halt(request)
      rescued(request)
      swallowed(Array(request["app_rescues"]), request)
      rollback(request)
      error_payload(request)
      error_text(request)
      error_template(request)
      jobs(Array(request["jobs"]), request)
      escaped(request)
    end

    def example_rules
      swallowed(Array(@facts["app_rescues"]), nil)
      jobs(Array(@facts["jobs"]), nil)
      thread_deaths
      no_controller
      no_mutation
      no_assertions
      actor_hint
      logged_error
    end

    # ---- rules ----------------------------------------------------------------

    def auth_halt(request)
      filter = request["halted_by"] or return
      kind = AUTHENTICATION.match?(filter) ? "authentication" : "authorization/guard"
      reason = outcome_asserted(request)
      add("GREEN_AUTH_HALT", "HIGH", request, reason,
          ["before_action :#{filter} halted the request (#{kind}); #{request["controller"]}##{request["action"]} never ran",
           "response: #{outcome(request)}; actor: #{actor(request)}"],
          "the example passed without the action under test executing")
    end

    def setup_rules(request)
      failed = request["halted_by"] || request["status"].to_i >= 400
      return unless failed && requests.last && !requests.last.equal?(request)

      origin = issued_for(request)
      site = origin["helper_site"] || origin["spec_site"]
      add("GREEN_SETUP_REQUEST_FAILED", "MEDIUM", request, nil,
          ["setup request from #{site} (#{origin["phase"]}) returned #{outcome(request)}" \
           "#{" halted by :#{request["halted_by"]}" if request["halted_by"]}"],
          "later requests in this example ran without the state this setup was meant to create")
    end

    def rescued(request)
      Array(request["rescued"]).each do |error|
        status = request["status"].to_i
        reason = injected(error) || outcome_asserted(request) || mentioned(error)
        confidence = status.between?(200, 299) ? "HIGH" : "MEDIUM"
        add("GREEN_RESCUED_EXCEPTION", confidence, request, reason,
            ["#{error["class"]} \"#{error["message"]}\" raised at #{error["raised_at"]}",
             "handled by #{error["handler"]}; response: #{outcome(request)}#{templates(request)}"],
            "an exception was converted into an ordinary response; the example #{asserted_phrase}")
      end
    end

    def swallowed(errors, request)
      errors.each do |error|
        next if error["reraised"] || error["wrapped_as"]

        reason = injected(error) || failure_asserted(request) || mentioned(error)
        logged = logs_for(request).any? { |log| log["message"].include?(error["class"].split("::").last) }
        confidence = PROGRAMMING_ERRORS.include?(error["class"]) || logged ? "HIGH" : "MEDIUM"
        add("GREEN_SWALLOWED_EXCEPTION", confidence, request, reason,
            ["#{error["class"]} \"#{error["message"]}\" raised at #{error["raised_at"]}",
             "rescued at #{error["rescued_at"]} and not re-raised#{"; the app logged it as an error" if logged}",
             request ? "response: #{outcome(request)}" : "outside any request"].compact,
            "application code swallowed an exception during a passing example")
      end
    end

    def rollback(request)
      db = request["db"] || {}
      rolled = [db["rollback"].to_i, db["tx_rollback"].to_i].max
      return if rolled.zero? || request["status"].to_i >= 400

      reason = failure_asserted(request)
      contexts = Array(db["rollback_context"]).map { |c| "after #{c["after_raise"] || "no exception"} (last write: #{c["last_write"] || "none"})" }.uniq
      add("GREEN_ROLLBACK", "HIGH", request, reason,
          ["#{rolled} transaction rollback(s) inside the request after #{writes(db)}",
           *contexts.first(2).map { |c| "rollback #{c}" },
           "response: #{outcome(request)}#{flash(request)}"],
          "the request looked successful but its database work was rolled back")
    end

    def error_payload(request)
      error = request["json_error"] or return
      return if request["status"].to_i >= 400

      reason = ("the example asserted the error content" if ctx.mentions?(error["value"]) ||
                                                          ctx.descriptions.any? { |d| d.include?("\"#{error["key"]}\"") })
      add("GREEN_ERROR_PAYLOAD", "HIGH", request, reason,
          ["#{request["status"]} #{request["media_type"]} body has \"#{error["key"]}\": #{error["value"].inspect}"],
          "a successful status carried a conventional error object; the example #{asserted_phrase}")
    end

    def error_text(request)
      text = request["error_text"] or return
      return if request["status"].to_i >= 400

      add("GREEN_ERROR_TEXT", "MEDIUM", request, mentioned("class" => text),
          ["#{request["status"]} HTML response contains #{text.inspect}"],
          "a successful page displays exception text")
    end

    def error_template(request)
      return if request["status"].to_i >= 400

      template = Array(request["templates"]).find { |name| ERROR_TEMPLATE.match?(name) } or return
      reason = ("the example asserted text from #{template}" if template_text_asserted?(template)) || mentioned("class" => template)
      add("GREEN_ERROR_TEMPLATE", "HIGH", request, reason,
          ["#{request["controller"]}##{request["action"]} rendered #{template} with #{request["status"]}"],
          "an error/fallback template was served with a success status; the example #{asserted_phrase}")
    end

    def jobs(events, request)
      events.each do |event|
        error = event["error"] or next
        next if event["event"] == "enqueue" # the same error, reported again by the enqueue wrapper
        # A perform error that escaped the request was not quiet: the escape rules cover it.
        next if event["event"] == "perform" && request && request["exception"]

        add("GREEN_JOB_FAILURE", "HIGH", request, injected(error) || failure_asserted(request) || mentioned(error),
            ["#{event["job"]} #{event["event"]}: #{error["class"]} \"#{error["message"]}\" (raised at #{error["raised_at"]})"],
            "a background job failed and was #{event["event"] == "discard" ? "discarded" : "retried/stopped"} quietly")
      end
    end

    def escaped(request)
      error = request["exception"] or return
      origin = issued_for(request) or return
      if origin["status"].nil?
        # No response: the exception reached the example, which still passed.
        raised = ctx.expectations.any? { |e| e["matcher"].to_s.end_with?("RaiseError") }
        add("GREEN_EXAMPLE_RESCUED", "MEDIUM", request,
            injected(error) || ("the example asserted raise_error" if raised) || mentioned(error),
            ["#{error["class"]} \"#{error["message"]}\" escaped #{request["controller"]}##{request["action"]} " \
             "and reached the example (#{origin["spec_site"]}), which did not fail"],
            "spec code rescued an exception from the request instead of asserting it")
        return
      end
      return if ctx.asserted_failure_status?(origin["status"])

      add("GREEN_EXCEPTION_RENDERED", "MEDIUM", request, injected(error) || mentioned(error),
          ["#{error["class"]} escaped #{request["controller"]}##{request["action"]}; middleware answered #{origin["status"]}"],
          "an exception became an HTTP response the example did not pin down")
    end

    def thread_deaths
      Array(@facts["thread_deaths"]).each do |death|
        next if death["propagated"]

        add("GREEN_THREAD_DIED", "HIGH", nil, injected(death) || mentioned(death),
            ["thread started at #{death["thread"]} died with #{death["class"]} \"#{death["message"]}\"",
             "raised at #{death["raised_at"]}; never joined, so the example could not see it"],
            "work in another thread failed while the example passed")
      end
    end

    def no_controller
      issued.each do |origin|
        next unless origin["controllers"].to_i.zero? && origin["status"]

        routing = logs_for(nil).find { |log| log["message"].include?("RoutingError") }
        confidence = origin["status"].to_i == 404 ? "MEDIUM" : "LOW"
        add("GREEN_NO_CONTROLLER", confidence, nil, nil,
            ["#{origin["method"]} #{origin["path"]} (#{origin["spec_site"]}) reached no controller; answered #{origin["status"]}",
             routing ? "logged: #{routing["message"]}" : "served by middleware or a Rack endpoint"],
            "the status came from routing/middleware, not from application code")
      end
    end

    def no_mutation
      request = subject_request or return
      return unless MUTATING.include?(request["method"]) && request["action_reached"] && !request["halted_by"]
      return if request["status"].to_i >= 400 || writes_total(request["db"]).positive? || Array(request["jobs"]).any?
      return if ctx.any_change?

      unpermitted = Array(request["unpermitted"])
      hint = @facts["full_description"].to_s[MUTATION_WORDS]
      evidence = ["#{request["method"]} #{request["path"]} -> #{outcome(request)}#{flash(request)}; 0 rows written"]
      evidence << "strong parameters dropped: #{unpermitted.join(", ")}" if unpermitted.any?
      evidence << "description says #{hint.inspect} (low-confidence hint)" if hint
      add("GREEN_NO_MUTATION", unpermitted.any? ? "MEDIUM" : "LOW", request, nil, evidence,
          "a mutating request wrote nothing and the example asserted no change")
    end

    def no_assertions
      return unless ctx.count.zero?

      request_like = %w[request controller].include?(@facts["type"]) || requests.any?
      add("GREEN_NO_ASSERTIONS", request_like ? "MEDIUM" : "LOW", nil, nil,
          ["0 expectations ran (#{requests.size} request(s) issued)"],
          "the example can only fail by raising")
    end

    def actor_hint
      request = subject_request or return
      description = @facts["description"].to_s # the example's own words, not its groups'
      attrs = request.dig("actor", "attrs") || {}
      role_says_admin = attrs["admin"] == true || attrs["role"].to_s == "admin"
      if description.match?(/\badmins?\b/i) && request["actor"] && attrs.any? && !role_says_admin
        add("HINT_ACTOR_MISMATCH", "LOW", request, nil,
            ["description mentions admin; request ran as #{actor(request)}"], "low-confidence: from the description")
      elsif description.match?(/\b(?:guests?|anonymous|signed[- ]out|logged[- ]out|unauthenticated|visitors?)\b/i) && request["actor"]
        add("HINT_ACTOR_MISMATCH", "LOW", request, nil,
            ["description suggests no user; request ran as #{actor(request)}"], "low-confidence: from the description")
      end
    end

    # Only errors no observed exception explains: a log line that names an
    # exception already seen (rescued, swallowed, job, thread) is that exception.
    def logged_error
      return if @findings.any? { |finding| finding.suppressed.nil? }

      known = observed_exception_names
      requests.each do |request|
        next if setup?(request)

        Array(request["logs"]).each do |log|
          next unless %w[ERROR FATAL].include?(log["severity"])
          next if known.any? { |name| log["message"].include?(name) }

          add("GREEN_LOGGED_ERROR", "MEDIUM", request, failure_asserted(request) || mentioned("class" => log["message"]),
              ["#{log["severity"]}: #{log["message"]}", "response: #{outcome(request)}"],
              "the application logged an error during a passing request")
        end
      end
    end

    def observed_exception_names
      lists = requests.flat_map { |r| Array(r["rescued"]) + Array(r["app_rescues"]) + Array(r["jobs"]).filter_map { |j| j["error"] } }
      lists += Array(@facts["app_rescues"]) + Array(@facts["thread_deaths"]) + Array(@facts["jobs"]).filter_map { |j| j["error"] }
      lists.flat_map { |error| [error["class"].to_s, error["class"].to_s.split("::").last] }.reject(&:empty?).uniq
    end

    # ---- suppression reasons ----------------------------------------------------
    #
    # Two strengths. `outcome_asserted` accepts the redirect target, because a
    # halt or a rescue handler *chooses* that target. `failure_asserted` does
    # not: a rollback or a swallowed error usually redirects exactly where
    # success does, so only an assertion that distinguishes failure counts.

    def injected(error)
      case error["origin"]
      when "test_double" then "the exception was injected by a test double (and_raise)"
      when "spec" then "the exception was raised by spec code"
      end
    end

    def outcome_asserted(request)
      if ctx.asserted_redirect_to?(request["location"])
        "the example asserted redirect_to #{request["location"]}"
      elsif ctx.asserted_failure_status?(request["status"])
        "the example asserted status #{request["status"]}"
      else
        flash_asserted(request)
      end
    end

    FAILURE_FLASH = %w[alert error danger warning].freeze

    def failure_asserted(request)
      return "the example asserted that nothing changed" if ctx.change_matchers(negated: true).any?
      return nil unless request
      return "the example asserted status #{request["status"]}" if ctx.asserted_failure_status?(request["status"])

      values = (request["flash"] || {}).select { |key, _| FAILURE_FLASH.include?(key) }.values
      hit = values.find { |value| ctx.expected_strings.include?(value) }
      "the example asserted the failure flash #{hit.inspect}" if hit
    end

    def flash_asserted(request)
      values = (request["flash"] || {}).values
      hit = values.find { |value| ctx.expected_strings.include?(value) }
      "the example asserted the flash #{hit.inspect}" if hit
    end

    def mentioned(error)
      name = error["class"].to_s.split("::").last
      "the example's assertions mention #{name}" if name && ctx.mentions?(name)
    end

    def template_text_asserted?(template)
      return false unless @root

      path = File.join(@root, "app/views", template)
      return false unless File.file?(path)

      source = File.read(path)
      ctx.expected_strings.any? { |text| source.include?(text) }
    end

    # ---- rendering helpers ---------------------------------------------------------

    def add(rule, confidence, request, suppressed, evidence, why)
      @findings << Finding.new(
        rule: rule, confidence: confidence, suppressed: suppressed, evidence: evidence, why: why,
        example: { "id" => @facts["id"], "location" => @facts["location"], "description" => @facts["full_description"],
                   "type" => @facts["type"], "asserted" => ctx.summary },
        request: request && "#{request["method"]} #{request["path"]} -> #{request["controller"]}##{request["action"]}"
      )
    end

    def asserted_phrase
      ctx.count.zero? ? "made no assertions" : "asserted only: #{ctx.summary}"
    end

    def outcome(request)
      status = request["status"] || "?"
      request["location"] ? "#{status} -> #{request["location"]}" : status.to_s
    end

    def actor(request)
      return "unknown" if request["actor_source"] == "unknown"

      actor = request["actor"] or return "anonymous"
      attrs = (actor["attrs"] || {}).map { |key, value| "#{key}=#{value}" }.join(" ")
      "#{actor["class"]}##{actor["id"]}#{" (#{attrs})" unless attrs.empty?}"
    end

    def templates(request)
      list = Array(request["templates"])
      list.empty? ? "" : "; rendered #{list.join(", ")}"
    end

    def flash(request)
      entries = (request["flash"] || {}).map { |key, value| "#{key}: #{value.inspect}" }
      entries.empty? ? "" : " (flash #{entries.join(", ")})"
    end

    def writes(db)
      parts = %w[insert update delete].filter_map { |verb| "#{db[verb]} #{verb}" if db[verb].to_i.positive? }
      parts.empty? ? "no writes" : parts.join(", ")
    end

    def writes_total(db)
      %w[insert update delete].sum { |verb| db.to_h[verb].to_i }
    end

    def logs_for(request)
      Array(request ? request["logs"] : @facts["logs"])
    end
  end
end
