# frozen_string_literal: true

# EXPERIMENTAL -- research spike. Deterministic rules over observer facts (v2.1).
#
# Every rule pairs one runtime fact with what the example's own assertions
# constrained. A finding is *suppressed* -- counted, not shown -- when the
# example demonstrably asserted the unusual outcome itself, or when the
# application itself reported the failure to the user. Nothing here reads the
# truth file, and nothing calls a model.
#
# v2.1 differs from rules_v1.rb only by changes measured on the first real
# repository run (see docs/research/green-suite-signal-spike.md, "Calibration").
module GreenSignal
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
    REGEX_LITERAL = %r{(?<![\w"])/((?:[^/\\\n]|\\.){2,})/[imx]*}.freeze

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

    # "2xx", "3xx", "404", ... from positive status assertions.
    def statuses
      @statuses ||= @expectations.reject { |e| e["negated"] }.flat_map { |e| statuses_of(e) }
    end

    # `not_to have_http_status(:ok)` and friends: the example expected failure.
    def expects_non_success?
      @expectations.select { |e| e["negated"] }.flat_map { |e| statuses_of(e) }.any? { |code| code.start_with?("2") }
    end

    def statuses_of(expectation)
      text = expectation["description"].to_s
      matcher = expectation["matcher"].to_s
      if matcher.include?("HaveHttpStatus") || (matcher.include?("Compound") && text.start_with?("respond with"))
        codes = text.scan(/\((\d{3}|[1-5]xx)\)/).flatten
        codes.empty? ? text.scan(/status code (\d{3})/).flatten : codes
      elsif matcher.end_with?("BePredicate") && expectation["actual"] == "response"
        [STATUS_WORDS[text.sub(/\Abe /, "").tr("_", " ")]].compact
      elsif expectation["actual"] == "status"
        text.scan(/\b(\d{3})\b/).flatten
      else
        []
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

    def redirect_targets
      @redirect_targets ||= @expectations.filter_map do |e|
        next if e["negated"]

        text = e["description"].to_s
        target = text[/\Aredirect to "([^"]*)"/, 1] || text[/\Ahave current path "([^"]*)"/, 1]
        target&.sub(%r{\Ahttps?://[^/]+}, "")
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

    def expected_patterns
      @expected_patterns ||= descriptions.flat_map { |text| text.scan(REGEX_LITERAL).flatten }.filter_map do |source|
        Regexp.new(source, Regexp::IGNORECASE)
      rescue RegexpError
        nil
      end
    end

    def mentions?(text)
      needle = text.to_s.downcase.strip
      return false if needle.length < 3

      descriptions.any? { |d| d.downcase.include?(needle) } ||
        expected_strings.any? { |s| s.length >= 4 && needle.include?(s.downcase) } ||
        expected_patterns.any? { |pattern| pattern.match?(needle) }
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
  class Rules # rubocop:disable Metrics/ClassLength
    PROGRAMMING_ERRORS = %w[NoMethodError NameError TypeError ArgumentError ZeroDivisionError KeyError
                            NotImplementedError FrozenError LocalJumpError SystemStackError IndexError].freeze
    AUTHENTICATION = /authenticat|sign_?in|log_?in|logged_in|require_(?:user|login|session)|session/i.freeze
    SIGN_IN_CONTROLLER = /Session|Login|Omniauth|Callbacks|Auth/i.freeze
    # Words that say the example *means* to be signed out. Used only to lower
    # confidence, never to raise it.
    SIGNED_OUT_WORDS = /\b(?:unauthenticated|un-authenticated|signed[- ]out|logged[- ]out|not (?:signed|logged) in|
                         anonymous|guests?|visitors?|without (?:a )?(?:login|session|signing in)|
                         requires? (?:a )?(?:login|sign[- ]in|authentication))\b/xi.freeze
    ERROR_TEMPLATE = %r{(?:\A|/)(?:errors?|error_pages?|exceptions?)/|(?:\A|/)_?(?:not_found|404|500|422|error|fallback|unavailable)\.}.freeze
    MUTATING = %w[POST PUT PATCH DELETE].freeze
    MUTATION_WORDS = /\b(?:creat|updat|sav|delet|destroy|remov|archiv|import|add|chang|edit|renam)\w*/i.freeze
    FAILURE_FLASH = %w[alert error danger warning].freeze

    def initialize(root: nil)
      @root = root
    end

    def call(facts)
      return [] unless facts["status"] == "passed"

      @facts = facts
      @ctx = AssertionContext.new(facts)
      @findings = []
      requests.each { |request| request_rules(request) }
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

    def request_rules(request)
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
      exception_page
      no_controller
      no_mutation
      no_assertions
      actor_hint
      logged_error
    end

    # ---- rules ----------------------------------------------------------------

    # HIGH only when the example tried to authenticate and was still stopped
    # at authentication; an anonymous example halting there may be the very
    # thing it tests.
    def auth_halt(request)
      filter = request["halted_by"] or return
      kind = AUTHENTICATION.match?(filter) && request["actor"].nil? ? "authentication" : "authorization/guard"
      reason = outcome_asserted(request) || failure_asserted(request)
      attempted = attempted_sign_in?(request)
      confidence = kind == "authentication" && attempted ? "HIGH" : "MEDIUM"
      evidence = ["before_action :#{filter} halted the request (#{kind}); #{request["controller"]}##{request["action"]} never ran",
                  "response: #{outcome(request)}; actor: #{actor(request)}"]
      evidence << "an earlier request in this example signed in / set up a user" if attempted
      if !attempted && kind == "authentication" && (words = @facts["description"].to_s[SIGNED_OUT_WORDS])
        confidence = "LOW"
        evidence << "lowered: the description says #{words.inspect}"
      end
      add("GREEN_AUTH_HALT", confidence, request, reason, evidence,
          "the example passed without the action under test executing")
    end

    def attempted_sign_in?(request)
      earlier = requests.take_while { |other| !other.equal?(request) }
      earlier.any? { |other| other["actor"] || (other["method"] != "GET" && SIGN_IN_CONTROLLER.match?(other["controller"].to_s)) } ||
        requests.any? { |other| other["actor_source"] == "stub" }
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
        reason = injected(error) || outcome_asserted(request) || expected_rejection(request) || mentioned(error)
        confidence = status.between?(200, 299) ? "HIGH" : "MEDIUM"
        add("GREEN_RESCUED_EXCEPTION", confidence, request, reason,
            ["#{error["class"]} \"#{error["message"]}\" raised at #{error["raised_at"]}",
             "handled by #{error["handler"]}; response: #{outcome(request)}#{templates(request)}"],
            "an exception was converted into an ordinary response; the example #{asserted_phrase}")
      end
    end

    # Domain exceptions rescued by application code were, on the first real
    # suite, all deliberate control flow; programming errors never are.
    def swallowed(errors, request)
      errors.each do |error|
        next if error["reraised"] || error["wrapped_as"]

        reason = injected(error) || failure_asserted(request) || app_reported_failure(request) || mentioned(error)
        logged = logs_for(request).any? { |log| log["message"].include?(error["class"].split("::").last) }
        confidence = PROGRAMMING_ERRORS.include?(error["class"]) || logged ? "HIGH" : "LOW"
        add("GREEN_SWALLOWED_EXCEPTION", confidence, request, reason,
            ["#{error["class"]} \"#{error["message"]}\" raised at #{error["raised_at"]}",
             "rescued at #{error["rescued_at"]} and not re-raised#{"; the app logged it as an error" if logged}",
             request ? "response: #{outcome(request)}" : "outside any request"].compact,
            "application code swallowed an exception during a passing example")
      end
    end

    # Only a rollback that threw away writes, while the response said nothing
    # failed. HIGH when no write of the request survived.
    def rollback(request)
      db = request["db"] || {}
      lost = db["writes_rolled_back"].to_i
      return if lost.zero? || request["status"].to_i >= 400

      kept = db["writes_kept"].to_i
      reason = failure_asserted(request) || app_reported_failure(request)
      contexts = Array(db["rollback_context"]).map { |c| "after #{c["after_raise"] || "no exception"}" }.uniq
      add("GREEN_ROLLBACK", kept.zero? ? "HIGH" : "MEDIUM", request, reason,
          ["#{lost} write(s) rolled back, #{kept} kept, inside the request",
           *contexts.first(2).map { |c| "rollback #{c}" },
           "response: #{outcome(request)}#{flash(request)}"],
          "the request looked successful but its database work was discarded")
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

    # Quiet means nobody downstream sees it: discard_on, or a perform error a
    # request swallowed. An error escaping perform reaches whoever performed
    # the job (the queue backend in production); a scheduled retry is design.
    def jobs(events, request)
      events.each do |event|
        error = event["error"] or next
        kind = event["event"]
        next if kind == "enqueue" || kind == "retry_stopped" # reported again by the wrapper / re-raised
        next if kind == "perform" && (request.nil? || request["exception"])

        confidence = kind == "enqueue_retry" ? "LOW" : "HIGH"
        add("GREEN_JOB_FAILURE", confidence, request, injected(error) || failure_asserted(request) || mentioned(error),
            ["#{event["job"]} #{kind}: #{error["class"]} \"#{error["message"]}\" (raised at #{error["raised_at"]})"],
            "a background job failed and was #{kind == "discard" ? "discarded" : "swallowed or retried"} quietly")
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
      return if origin["exception_page"] && body_checks_after(origin).any? # exception_page says it better
      return if ctx.asserted_failure_status?(origin["status"])

      add("GREEN_EXCEPTION_RENDERED", "MEDIUM", request, injected(error) || mentioned(error),
          ["#{error["class"]} \"#{error["message"]}\" escaped #{request["controller"]}##{request["action"]}; " \
           "middleware answered #{origin["status"]}"],
          "an exception became an HTTP response the example did not pin down")
    end

    # Rails >= 7.1 test default (show_exceptions = :rescuable) renders the
    # debug exception page, which prints source extracts of every application
    # frame -- including the spec lines around the request. A body assertion
    # can then be satisfied by the spec's own source.
    def exception_page
      issued.each_with_index do |origin, index|
        next unless origin["exception_page"]

        checks = body_checks_after(origin, index)
        # `not_to include(secret)` on an asserted 404 is what the example meant.
        checks = checks.reject { |check| check["negated"] } if ctx.asserted_failure_status?(origin["status"])
        next if checks.empty?

        request = requests.find { |r| r["issued_index"] == index }
        echoed = checks.select { |check| check["source_echo"] }
        evidence = ["#{origin["method"]} #{origin["path"]} (#{origin["spec_site"]}) answered #{origin["status"]} " \
                    "with Rails' exception page (#{origin["title"].inspect})",
                    "#{checks.size} passing body assertion(s) ran against that page: " \
                    "#{checks.map { |c| c["description"].to_s[0, 60] }.join("; ")}"]
        if echoed.any?
          evidence << "#{echoed.size} of them match only inside the page's printed source code, " \
                      "not anything the application rendered"
        end
        error = request && request["exception"]
        evidence << "exception: #{error["class"]} \"#{error["message"]}\" at #{error["raised_at"]}" if error
        add("GREEN_EXCEPTION_PAGE", "HIGH", request, nil, evidence,
            "the example's content assertions were checked against an error page, not the page under test")
      end
    end

    def body_checks_after(origin, index = issued.index(origin))
      ctx.expectations.select { |e| e["after_request"] == index.to_i + 1 && e["actual"] == "response.body" }
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

    # Router 404s were, on the first real suite, all route-retirement tests.
    def no_controller
      issued.each do |origin|
        next unless origin["controllers"].to_i.zero? && origin["status"]

        routing = logs_for(nil).find { |log| log["message"].include?("RoutingError") }
        add("GREEN_NO_CONTROLLER", "LOW", nil, nil,
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
      add("GREEN_NO_MUTATION", unpermitted.any? ? "MEDIUM" : "LOW", request, app_reported_failure(request), evidence,
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
          next if observed_exception_messages.any? { |message| log["message"].include?(message) }

          add("GREEN_LOGGED_ERROR", "MEDIUM", request, failure_asserted(request) || mentioned("class" => log["message"]),
              ["#{log["severity"]}: #{log["message"]}", "response: #{outcome(request)}"],
              "the application logged an error during a passing request")
        end
      end
    end

    def observed_exceptions
      lists = requests.flat_map { |r| Array(r["rescued"]) + Array(r["app_rescues"]) + Array(r["jobs"]).filter_map { |j| j["error"] } }
      lists += requests.filter_map { |r| r["exception"] }
      lists + Array(@facts["app_rescues"]) + Array(@facts["thread_deaths"]) + Array(@facts["jobs"]).filter_map { |j| j["error"] }
    end

    def observed_exception_messages
      observed_exceptions.map { |error| error["message"].to_s }.select { |message| message.length >= 6 }.uniq
    end

    def observed_exception_names
      lists = requests.flat_map { |r| Array(r["rescued"]) + Array(r["app_rescues"]) + Array(r["jobs"]).filter_map { |j| j["error"] } }
      lists += requests.filter_map { |r| r["exception"] }
      lists += Array(@facts["app_rescues"]) + Array(@facts["thread_deaths"]) + Array(@facts["jobs"]).filter_map { |j| j["error"] }
      lists.flat_map { |error| [error["class"].to_s, error["class"].to_s.split("::").last] }.reject(&:empty?).uniq
    end

    # ---- suppression reasons ----------------------------------------------------
    #
    # Two strengths. `outcome_asserted` accepts the redirect target, because a
    # halt or a rescue handler *chooses* that target. `failure_asserted` does
    # not: a rollback or a swallowed error usually redirects exactly where
    # success does, so only an assertion that distinguishes failure counts.
    # `app_reported_failure` is the application's own signal, not the test's.

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

    # A non-success response the example asserted as non-success.
    def expected_rejection(request)
      status = request["status"].to_i
      return nil if status < 300

      if ctx.expects_non_success?
        "the example asserted the response was not a success"
      elsif ctx.asserted_status?(status)
        "the example asserted a #{status / 100}xx response"
      end
    end

    def failure_asserted(request)
      return "the example asserted that nothing changed" if ctx.change_matchers(negated: true).any?
      return nil unless request
      return "the example asserted status #{request["status"]}" if ctx.asserted_failure_status?(request["status"])

      values = (request["flash"] || {}).select { |key, _| FAILURE_FLASH.include?(key) }.values
      hit = values.find { |value| flash_matches?(value) }
      "the example asserted the failure flash #{hit.inspect}" if hit
    end

    def app_reported_failure(request)
      return nil unless request
      return "the application answered #{request["status"]}" if request["status"].to_i >= 400

      alert = (request["flash"] || {}).find { |key, _| FAILURE_FLASH.include?(key) }
      "the application told the user it failed (flash #{alert[0]}: #{alert[1].inspect})" if alert
    end

    def flash_asserted(request)
      hit = (request["flash"] || {}).values.find { |value| flash_matches?(value) }
      "the example asserted the flash #{hit.inspect}" if hit
    end

    def flash_matches?(value)
      ctx.expected_strings.any? { |text| text == value || (text.length >= 8 && value.include?(text)) }
    end

    def mentioned(error)
      name = error["class"].to_s.split("::").last
      return "the example's assertions mention #{name}" if name && ctx.mentions?(name)

      message = error["message"].to_s.downcase
      quoted = ctx.expected_strings.find { |text| text.length >= 4 && message.include?(text.downcase) } ||
               ctx.expected_patterns.find { |pattern| pattern.match?(message) }&.source
      "the example's assertions quote the exception's message (#{quoted.inspect})" if quoted
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

    def writes_total(db)
      %w[insert update delete].sum { |verb| db.to_h[verb].to_i }
    end

    def logs_for(request)
      Array(request ? request["logs"] : @facts["logs"])
    end
  end
end
