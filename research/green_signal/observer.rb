# frozen_string_literal: true

# EXPERIMENTAL -- research spike, not part of the rspec-signal gem.
#
# Records normalized runtime facts about every RSpec example so that
# `analyze.rb` can ask: "this example passed, but should we trust the pass?"
#
#   bundle exec rspec -r /abs/path/research/green_signal/observer.rb
#
# It only observes. One JSON line per example goes to $GREEN_SIGNAL_OUT
# (default tmp/green_signal/facts.jsonl). Nothing here changes what the
# application returns, and nothing is wired into rspec-signal itself.
#
# Sources, in order of preference:
#   official notifications  start_processing / process_action / halted_callback /
#                           redirect_to (ActionController), sql / transaction
#                           (ActiveRecord), render_* (ActionView), *.active_job,
#                           Rails.error, Rails.logger.broadcast_to
#   TracePoint              :raise / :rescue / :thread_end (Ruby 3.3+ for :rescue)
#   prepends (4 methods)    rescue_with_handler and send_action on controllers;
#                           Integration::Session#process; rspec-expectations'
#                           Positive/NegativeExpectationHandler.handle_matcher
#
# Ablations: GREEN_SIGNAL_DISABLE=tracepoint,expectations,sql,render,logs,body
require "json"
require "fileutils"
require "logger"
require "cgi"

module GreenSignal
  MAX_LIST = 25
  MAX_TEXT = 200
  MAX_JSON_BYTES = 512_000
  ROLE_ATTRIBUTES = %w[role roles admin is_admin kind type author premium plan].freeze
  ERROR_TEXT = /
    \b(?:NoMethodError|NameError|ArgumentError|TypeError|ZeroDivisionError|KeyError|
    ActiveRecord::[A-Z]\w+|ActionController::[A-Z]\w+|ActionView::Template::Error)\b
    |undefined\smethod\s[`'‘]|undefined\slocal\svariable|uninitialized\sconstant|stack\slevel\stoo\sdeep
  /x.freeze
  JSON_ERROR_STATUSES = %w[error fail failed failure].freeze
  WRITE_VERBS = %w[INSERT UPDATE DELETE].freeze
  # One "Extracted source (around line N)" block of Rails' debug exception page.
  SOURCE_EXTRACT = %r{<div class="source[^"]*" id="frame-source-.*?</table>\s*</div>\s*</div>}m.freeze

  class << self
    attr_reader :current, :costs

    def disabled?(part)
      @disabled ||= ENV.fetch("GREEN_SIGNAL_DISABLE", "").split(",").map(&:strip)
      @disabled.include?(part)
    end

    # ---- lifecycle -----------------------------------------------------------

    def boot!(rspec_config)
      @costs = Hash.new(0)
      @counts = Hash.new(0)
      @examples = {}
      @thread_pending = {}.compare_by_identity
      @thread_deaths = {}.compare_by_identity
      @current = nil
      out = ENV.fetch("GREEN_SIGNAL_OUT", "tmp/green_signal/facts.jsonl")
      FileUtils.mkdir_p(File.dirname(out))
      @out_path = out
      @out = File.open(out, "w")
      @out.sync = false
      rspec_config.around(:each) { |example| GreenSignal.around_example(example) }
      rspec_config.before(:suite) { GreenSignal.install! }
      rspec_config.after(:suite) { GreenSignal.finish! }
    end

    def install!
      @root = defined?(::Rails) && ::Rails.respond_to?(:root) && ::Rails.root ? ::Rails.root.to_s : Dir.pwd
      @root_prefix = "#{@root}/"
      @app_prefixes = %w[app lib].map { |dir| File.join(@root, dir, "") }
      @spec_prefixes = %w[spec test].map { |dir| File.join(@root, dir, "") }
      @hook_sites = hook_sites
      ::RSpec.configuration.reporter.register_listener(Listener.new, :example_finished)
      install_expectation_probe unless disabled?("expectations")
      install_tracepoint unless disabled?("tracepoint")
      install_rails if defined?(::ActiveSupport::Notifications)
    end

    def finish!
      @tracepoint&.disable
      @out&.close
      meta = { "costs_ms" => @costs.transform_values { |ns| (ns / 1_000_000.0).round(1) },
               "counts" => @counts, "examples" => @written.to_i }
      File.write("#{@out_path}.meta.json", JSON.pretty_generate(meta))
    end

    def around_example(example)
      started = clock
      facts = new_facts
      @examples[example.id] = facts
      @current = facts
      example.run
    ensure
      @current = nil
      @thread_deaths.clear
      facts["duration_ms"] = ((clock - started) / 1_000_000.0).round(2) if facts
    end

    def example_finished(example)
      facts = @examples.delete(example.id)
      return unless facts

      timed(:serialize) { write(example, facts) }
    end

    # ---- facts ---------------------------------------------------------------

    def new_facts
      { "issued" => [], "requests" => [], "db_outside" => new_db, "jobs" => [], "app_rescues" => [],
        "logs" => [], "error_reports" => [], "thread_deaths" => [], "expectations" => [],
        "expectation_count" => 0, "mock_expectations" => 0, "templates_outside" => [] }
    end

    def new_db
      { "select" => 0, "insert" => 0, "update" => 0, "delete" => 0, "begin" => 0, "commit" => 0,
        "rollback" => 0, "tx_rollback" => 0, "tables_written" => {} }
    end

    def write(example, facts)
      metadata = example.metadata
      result = example.execution_result
      described = metadata[:described_class]
      record = {
        "id" => example.id, "location" => rel(metadata[:location].to_s),
        "description" => example.description, "full_description" => example.full_description,
        "type" => metadata[:type]&.to_s, "described_class" => described.is_a?(Module) ? described.name : nil,
        "status" => result.status.to_s,
        "exception" => example.exception && example.exception.class.name
      }.merge(facts)
      record.delete("_last")
      record.delete("_rescued")
      [*record["requests"].map { |request| request["db"] }, record["db_outside"]].compact.each do |db|
        db["writes_kept"] = db["writes_kept"].to_i + Array(db.delete("_tx")).sum
        db.delete("_last_write")
      end
      @out.puts(JSON.generate(record))
      @written = @written.to_i + 1
    rescue StandardError => e
      warn "green_signal: could not write #{example.id}: #{e.class}: #{e.message}"
    end

    # The open controller request on this thread, if any.
    def open_request
      Thread.current[:__green_signal_requests]&.last
    end

    def open_issued
      Thread.current[:__green_signal_issued]&.last
    end

    def bucket_for(key)
      request = open_request
      return request[key] ||= [] if request

      @current[key]
    end

    def push_limited(list, item)
      list << item if list.size < MAX_LIST
    end

    # ---- HTTP: what the test issued ------------------------------------------

    def issue_start(method, path)
      return unless @current

      timed(:issue) do
        site = call_site(caller_locations(1, 150))
        issued = { "method" => method.to_s.upcase, "path" => path.to_s[0, MAX_TEXT], "controllers" => 0 }.merge(site)
        push_limited(@current["issued"], issued)
        (Thread.current[:__green_signal_issued] ||= []) << issued
      end
    end

    def issue_finish(session)
      stack = Thread.current[:__green_signal_issued]
      issued = stack&.pop
      return unless issued && @current

      response = session.response
      issued["status"] = response&.status
      issued["location"] = path_of(response&.location)
      describe_issued_body(issued, response) if response && !disabled?("body")
    rescue StandardError
      nil
    end

    # The body the example will actually assert against -- which, when an
    # exception escaped, middleware rendered rather than any controller.
    def describe_issued_body(issued, response)
      last = (@current["_last"] ||= {})
      last.delete("json") if issued["controllers"].zero?
      return unless response.media_type.to_s.include?("html")

      body = response.body.to_s
      last["body"] = body
      last["status"] = response.status
      title = body[%r{<title[^>]*>(.*?)</title>}im, 1]
      issued["title"] = title.strip[0, 120] if title
      if title.to_s.include?("Exception caught")
        issued["exception_page"] = true
        last["page_text"] = body.gsub(SOURCE_EXTRACT, "")
      else
        last.delete("page_text")
      end
    end

    # True when a literal the example looked for is on the exception page only
    # because the page prints source code (the spec's, or the app's).
    def source_echo?(description)
      last = @current["_last"] || {}
      literal = description.to_s[/"((?:[^"\\]|\\.){4,})"/, 1] or return false
      literal = literal.gsub('\\"', '"')
      forms = [literal, CGI.escapeHTML(literal)]
      forms.any? { |form| last["body"].to_s.include?(form) } && forms.none? { |form| last["page_text"].to_s.include?(form) }
    end

    # Phase and spec line of the code that issued a request, read from the
    # rspec-core frames just outside it -- the same idea as rspec-signal's
    # Causal::Phase, reimplemented here so this file stands alone.
    def call_site(locations)
      site = { "phase" => "unknown" }
      locations.each do |location|
        path = location.absolute_path || location.path.to_s
        if spec_path?(path)
          key = path.end_with?("_spec.rb") ? "spec_site" : "helper_site"
          site[key] ||= "#{rel(path)}:#{location.lineno}" unless site["spec_site"]
        elsif (core = path[%r{/(?:rspec-core-[^/]+/lib/rspec/core|lib/rspec/core)/(\w+\.rb)\z}, 1])
          site["let"] = true if core == "memoized_helpers.rb"
          phase = rspec_phase(core, path, location)
          next unless phase

          site["phase"] = phase
          break
        end
      end
      site
    end

    def rspec_phase(core, path, location)
      return "body" if core == "example.rb" && location.label.to_s.end_with?("block in run", "Example#run")
      return nil unless core == "hooks.rb"

      @hook_sites.each do |name, file, line|
        return name if file == path && location.lineno.between?(line, line + 4)
      end
      nil
    end

    def hook_sites
      { "before" => %i[BeforeHook run], "after" => %i[AfterHook run], "around" => %i[AroundHook execute_with] }
        .filter_map do |name, (klass, method)|
          file, line = ::RSpec::Core::Hooks.const_get(klass).instance_method(method).source_location
          [name, File.expand_path(file), line]
        rescue StandardError
          nil
        end
    end

    # ---- HTTP: what the controller did ---------------------------------------

    def on_start_processing(payload)
      return unless @current

      issued = open_issued
      issued["controllers"] += 1 if issued
      request = {
        "controller" => payload[:controller], "action" => payload[:action], "format" => payload[:format]&.to_s,
        "method" => payload[:method], "path" => payload[:path].to_s[0, MAX_TEXT],
        "issued_index" => issued && @current["issued"].index(issued),
        "action_reached" => false, "db" => new_db
      }
      push_limited(@current["requests"], request)
      (Thread.current[:__green_signal_requests] ||= []) << request
    end

    def on_process_action(payload)
      request = Thread.current[:__green_signal_requests]&.pop
      return unless request && @current

      request["status"] = payload[:status]
      if (error = payload[:exception_object])
        request["exception"] = describe_exception(error)
      end
      response = payload[:response]
      http_request = payload[:request]
      request["location"] = path_of(response&.location) if response && (300..399).cover?(response.status.to_i)
      describe_body(request, response) if readable_body?(response, http_request) && !disabled?("body")
      describe_controller_state(request, http_request&.controller_instance, http_request)
    end

    def on_halted(payload)
      request = open_request
      return unless request

      filter = payload[:filter]
      request["halted_by"] = filter.is_a?(Symbol) || filter.is_a?(String) ? filter.to_s : filter.class.name
    end

    def on_unpermitted(payload)
      request = open_request
      return unless request

      keys = Array(payload[:keys]).map(&:to_s)
      request["unpermitted"] = (Array(request["unpermitted"]) | keys).first(MAX_LIST)
    end

    def on_action_reached
      request = open_request
      request["action_reached"] = true if request
    end

    def on_rescue_from(controller, exception, handler)
      request = open_request
      return unless request

      item = describe_exception(exception).merge("handler" => declared_handler(controller, exception) ||
                                                              describe_handler(handler),
                                                 "controller" => controller.class.name)
      push_limited(request["rescued"] ||= [], item)
    end

    # The rescue_from declaration that matched, as the developer wrote it.
    def declared_handler(controller, exception)
      controller.class.rescue_handlers.reverse_each do |class_name, handler|
        klass = class_name.is_a?(Module) ? class_name : Object.const_get(class_name.to_s)
        next unless exception.is_a?(klass)

        return "rescue_from #{klass.name} => #{handler.is_a?(Symbol) ? handler : describe_handler(handler)}"
      rescue NameError
        next
      end
      nil
    end

    def describe_handler(handler)
      case handler
      when Method, UnboundMethod then handler.name.to_s
      when Proc
        file, line = handler.source_location
        file ? "block at #{rel(file)}:#{line}" : "block"
      else handler.class.name
      end
    rescue StandardError
      nil
    end

    # Never touch streaming or file bodies: reading them could block or load a file.
    def readable_body?(response, http_request)
      return false unless response
      return false if defined?(::ActionController::Live) && http_request&.controller_instance.is_a?(::ActionController::Live)

      response.media_type.to_s.match?(/json|html|text/)
    rescue StandardError
      false
    end

    def describe_body(request, response)
      media = response.media_type.to_s
      body = response.body.to_s
      request["media_type"] = media
      request["body_bytes"] = body.bytesize
      @current["_last"] = { "body" => body, "status" => response.status }
      if media.include?("json") && body.bytesize <= MAX_JSON_BYTES
        json = JSON.parse(body)
        @current["_last"]["json"] = json
        error = json_error(json)
        request["json_error"] = error if error
      elsif media.include?("html")
        title = body[%r{<title[^>]*>(.*?)</title>}im, 1]
        request["html_title"] = title.strip[0, 120] if title
        leaked = body[ERROR_TEXT]
        request["error_text"] = leaked if leaked
      end
    rescue JSON::ParserError
      request["json_unparseable"] = true
    rescue StandardError
      nil
    end

    def json_error(json)
      return nil unless json.is_a?(Hash)

      %w[error errors].each do |key|
        value = json[key]
        next if value.nil? || value == false || (value.respond_to?(:empty?) && value.empty?)

        return { "key" => key, "value" => value.to_s[0, MAX_TEXT] }
      end
      return { "key" => "success", "value" => "false" } if json["success"] == false
      return { "key" => "ok", "value" => "false" } if json["ok"] == false
      return { "key" => "status", "value" => json["status"] } if JSON_ERROR_STATUSES.include?(json["status"])

      nil
    end

    def describe_controller_state(request, controller, http_request)
      return unless controller

      actor, source = actor_of(controller)
      request["actor"] = actor
      request["actor_source"] = source
      flash = http_request.respond_to?(:flash_hash) ? http_request.flash_hash : nil
      request["flash"] = flash.to_hash.transform_values { |value| value.to_s[0, 120] } if flash && !flash.empty?
    rescue StandardError
      nil
    end

    # Read without side effects: the memoized instance variable, or a stub
    # rspec-mocks put in place. Never calls a real `current_user`.
    def actor_of(controller)
      if controller.instance_variable_defined?(:@current_user)
        [describe_actor(controller.instance_variable_get(:@current_user)), "ivar"]
      elsif stubbed?(controller, :current_user)
        [describe_actor(controller.send(:current_user)), "stub"]
      else
        [nil, "unknown"]
      end
    end

    def stubbed?(object, name)
      return false unless object.respond_to?(name, true)

      file = object.method(name).source_location&.first.to_s
      file.include?("rspec-mocks") || file.include?("/lib/rspec/mocks/")
    end

    def describe_actor(user)
      return nil if user.nil?

      attributes = user.respond_to?(:attributes) ? user.attributes.slice(*ROLE_ATTRIBUTES) : {}
      { "class" => user.class.name, "id" => user.respond_to?(:id) ? user.id : nil, "attrs" => attributes }
    rescue StandardError
      { "class" => user.class.name }
    end

    # ---- templates, SQL, jobs ------------------------------------------------

    def on_render(name, payload)
      return unless @current

      request = open_request
      if name == "render_template.action_view"
        template = template_name(payload[:identifier])
        request ? push_limited(request["templates"] ||= [], template) : push_limited(@current["templates_outside"], template)
        request["layout"] = payload[:layout] if request && payload[:layout]
      elsif request
        request["partials"] = request["partials"].to_i + 1
      end
    end

    def template_name(identifier)
      identifier.to_s.sub(%r{\A.*?/app/views/}, "").sub(%r{\A.*/gems/}, "gem:")
    end

    def on_sql(payload)
      return unless @current
      return if payload[:cached] || payload[:name] == "SCHEMA"

      sql = payload[:sql].to_s
      verb = sql[/\A\s*(\w+)/, 1].to_s.upcase
      db = (open_request || {})["db"] || @current["db_outside"]
      case verb
      when "SELECT", "WITH" then db["select"] += 1
      when *WRITE_VERBS
        return if payload[:exception] # a statement that raised wrote nothing

        db[verb.downcase] += 1
        count_write(db)
        table = sql[/\A\s*(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+[`"]?([\w.]+)/i, 1]
        db["tables_written"][table] = db["tables_written"].fetch(table, 0) + 1 if table
        db["_last_write"] = "#{verb} #{table}"
      when "BEGIN", "SAVEPOINT"
        db["begin"] += 1
        (db["_tx"] ||= []) << 0
      when "COMMIT", "RELEASE"
        db["commit"] += 1
        count_write(db, Array(db["_tx"]).pop.to_i)
      when "ROLLBACK"
        db["rollback"] += 1
        db["writes_rolled_back"] = db["writes_rolled_back"].to_i + Array(db["_tx"]).pop.to_i
        note_rollback(db)
      end
    end

    # Writes are credited to the innermost open savepoint; a RELEASE hands
    # them to the enclosing level, a ROLLBACK discards them.
    def count_write(db, count = 1)
      stack = db["_tx"]
      if stack.nil? || stack.empty?
        db["writes_kept"] = db["writes_kept"].to_i + count
      else
        stack[-1] += count
      end
    end

    # What preceded a rollback: the last exception raised on this thread and
    # the last table written. Evidence for a reader, not a causal claim.
    def note_rollback(db)
      return unless open_request

      error = Thread.current[:__green_signal_last_raise]
      cause = { "after_raise" => error && "#{error.class}: #{error.message.to_s.lines.first.to_s.strip[0, 120]}",
                "last_write" => db["_last_write"] }
      push_limited(db["rollback_context"] ||= [], cause)
    end

    def on_transaction(payload)
      request = open_request
      request["db"]["tx_rollback"] += 1 if request && payload[:outcome] == :rollback
    end

    def on_job(name, payload)
      return unless @current

      job = payload[:job]
      error = payload[:error] || payload[:exception_object]
      return if name == "perform_start.active_job"

      item = { "event" => name.delete_suffix(".active_job"), "job" => job&.class&.name }
      item["error"] = describe_exception(error) if error
      push_limited(bucket_for("jobs"), item)
    end

    # ---- logs and Rails.error -------------------------------------------------

    def on_log(severity, message)
      return unless @current

      text = message.is_a?(Exception) ? "#{message.class}: #{message.message}" : message.to_s
      push_limited(bucket_for("logs"), { "severity" => ::Logger::SEV_LABEL[severity] || severity.to_s,
                                          "message" => text.strip[0, MAX_TEXT] })
    end

    def on_error_report(error, handled, severity, source)
      return unless @current

      item = describe_exception(error).merge("handled" => handled, "severity" => severity.to_s,
                                             "source" => source.to_s)
      push_limited(bucket_for("error_reports"), item)
    end

    # ---- exceptions seen by TracePoint ---------------------------------------

    def on_tracepoint(trace)
      case trace.event
      when :raise then on_raise(trace.raised_exception)
      when :rescue then on_rescue(trace.raised_exception, trace.path, trace.lineno)
      when :thread_end then on_thread_end
      end
    end

    def on_raise(exception)
      Thread.current[:__green_signal_last_raise] = exception if @current
      if (death = @thread_deaths[exception])
        death["propagated"] = true # Thread#join re-raised it in another thread
      end
      if (rescued = @current&.dig("_rescued", exception))
        rescued["reraised"] = true
      end
      cause = exception.cause
      rescued_cause = cause && @current&.dig("_rescued", cause)
      rescued_cause["wrapped_as"] = exception.class.name if rescued_cause
      @thread_pending[Thread.current] = [exception, @current] unless Thread.current == Thread.main || !@current
    end

    def on_rescue(exception, path, line)
      pending = @thread_pending[Thread.current]
      @thread_pending.delete(Thread.current) if pending && pending.first.equal?(exception)
      return unless @current && app_path?(path)

      seen = (@current["_rescued"] ||= {}.compare_by_identity)
      return if seen.key?(exception)

      item = describe_exception(exception).merge("rescued_at" => "#{rel(path)}:#{line}")
      seen[exception] = item
      push_limited(bucket_for("app_rescues"), item)
    end

    def on_thread_end
      exception, facts = @thread_pending.delete(Thread.current)
      return unless exception && facts

      item = describe_exception(exception).merge("thread" => rel(Thread.current.inspect[%r{ (/\S+:\d+)}, 1]))
      @thread_deaths[exception] = item
      push_limited(facts["thread_deaths"], item)
    end

    def describe_exception(exception)
      backtrace = Array(exception.backtrace)
      { "class" => exception.class.name, "message" => exception.message.to_s.lines.first.to_s.strip[0, MAX_TEXT],
        "raised_at" => raised_at(backtrace), "origin" => origin(backtrace) }
    rescue StandardError
      { "class" => exception.class.name }
    end

    def raised_at(backtrace)
      frame = backtrace.find { |line| app_path?(line) } || backtrace.first
      frame && rel(frame.sub(/:in .*\z/, ""))
    end

    # Who put the exception there: the test (a double's and_raise, or spec
    # code), the application, or a library.
    def origin(backtrace)
      head = backtrace.first(8)
      return "test_double" if head.any? { |line| line.include?("/rspec-mocks") || line.include?("/lib/rspec/mocks/") }

      first_party = backtrace.find { |line| line.start_with?(@root_prefix) }
      return "library" unless first_party
      return "spec" if spec_path?(first_party)

      "app"
    end

    # ---- expectations ---------------------------------------------------------

    def on_expectation(handler, actual, matcher, passed)
      return unless @current

      @current["expectation_count"] += 1
      name = matcher.class.name.to_s
      @current["mock_expectations"] += 1 if name.start_with?("RSpec::Mocks::")
      return if @current["expectations"].size >= MAX_LIST

      description = begin
        matcher.respond_to?(:description) ? matcher.description.to_s[0, MAX_TEXT] : nil
      rescue StandardError, NotImplementedError
        nil
      end
      entry = {
        "matcher" => name, "negated" => handler.name.to_s.include?("Negative"), "passed" => passed,
        "description" => description, "actual" => classify_actual(actual),
        "after_request" => @current["issued"].size
      }
      entry["source_echo"] = true if entry["actual"] == "response.body" && @current.dig("_last", "page_text") &&
                                     source_echo?(description)
      @current["expectations"] << entry
    end

    def classify_actual(actual)
      last = @current["_last"] || {}
      case actual
      when Proc then "block"
      when String
        return "response.body" if last["body"] && actual.length == last["body"].length && actual == last["body"]

        "string"
      when Hash, Array then last.key?("json") && actual == last["json"] ? "parsed_body" : actual.class.name
      when Integer then actual == last["status"] ? "status" : "integer"
      else
        name = actual.class.name.to_s
        return "response" if name.end_with?("TestResponse")
        return "record:#{name}" if defined?(::ActiveRecord::Base) && actual.is_a?(::ActiveRecord::Base)

        name
      end
    rescue StandardError
      "unknown"
    end

    # ---- installation ---------------------------------------------------------

    def install_expectation_probe
      return unless defined?(::RSpec::Expectations::PositiveExpectationHandler)

      ::RSpec::Expectations::PositiveExpectationHandler.singleton_class.prepend(ExpectationProbe)
      ::RSpec::Expectations::NegativeExpectationHandler.singleton_class.prepend(ExpectationProbe)
    end

    def install_tracepoint
      return unless TracePoint.respond_to?(:new)

      events = %i[raise thread_end]
      events << :rescue if RUBY_VERSION >= "3.3"
      @tracepoint = TracePoint.new(*events) do |trace|
        next unless @current || !@thread_pending.empty? || !@thread_deaths.empty?

        timed(:tracepoint) { on_tracepoint(trace) }
      end
      @tracepoint.enable
    end

    def install_rails
      notifications = ::ActiveSupport::Notifications
      subscribe(notifications, "start_processing.action_controller", :controller) { |_n, payload| on_start_processing(payload) }
      subscribe(notifications, "process_action.action_controller", :controller) { |_n, payload| on_process_action(payload) }
      subscribe(notifications, "halted_callback.action_controller", :controller) { |_n, payload| on_halted(payload) }
      subscribe(notifications, "unpermitted_parameters.action_controller", :controller) do |_n, payload|
        on_unpermitted(payload)
      end
      unless disabled?("render")
        subscribe(notifications, /\Arender_(?:template|partial|collection)\.action_view\z/, :render) do |name, payload|
          on_render(name, payload)
        end
      end
      unless disabled?("sql")
        subscribe(notifications, "sql.active_record", :sql) { |_n, payload| on_sql(payload) }
        subscribe(notifications, "transaction.active_record", :sql) { |_n, payload| on_transaction(payload) }
      end
      subscribe(notifications, /\.active_job\z/, :job) { |name, payload| on_job(name, payload) }
      install_controller_probes
      install_integration_probe
      install_error_subscriber
      install_log_recorder unless disabled?("logs")
    end

    def subscribe(notifications, pattern, cost)
      notifications.subscribe(pattern) do |name, _start, _finish, _id, payload|
        next unless @current

        timed(cost) { yield(name, payload) }
      rescue StandardError => e
        @counts["observer_errors"] += 1
        warn "green_signal: #{name}: #{e.class}: #{e.message}" if ENV["GREEN_SIGNAL_DEBUG"]
      end
    end

    def install_controller_probes
      ::ActiveSupport.on_load(:action_controller) { prepend(GreenSignal::ControllerProbe) }
    end

    def install_integration_probe
      return unless defined?(::ActionDispatch::Integration::Session)

      ::ActionDispatch::Integration::Session.prepend(IntegrationProbe)
    end

    def install_error_subscriber
      return unless defined?(::Rails) && ::Rails.respond_to?(:error)

      ::Rails.error.subscribe(ErrorSubscriber.new)
    end

    def install_log_recorder
      logger = defined?(::Rails) && ::Rails.logger
      logger.broadcast_to(LogRecorder.new) if logger.respond_to?(:broadcast_to)
    end

    # ---- paths and clocks ---------------------------------------------------------

    def app_path?(path)
      path = path.to_s
      @app_prefixes.any? { |prefix| path.start_with?(prefix) }
    end

    def spec_path?(path)
      path = path.to_s
      @spec_prefixes.any? { |prefix| path.start_with?(prefix) }
    end

    def rel(path)
      path.to_s.start_with?(@root_prefix.to_s) ? path.to_s[@root_prefix.length..] : path.to_s.sub(%r{\A\./}, "")
    end

    def path_of(location)
      return nil if location.nil?

      location.to_s.sub(%r{\Ahttps?://[^/]+}, "")[0, MAX_TEXT]
    end

    def clock
      Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
    end

    def timed(category)
      started = clock
      yield
    ensure
      @costs[category] += clock - started
    end
  end

  # rspec-core calls this once the status is final.
  class Listener
    def example_finished(notification)
      GreenSignal.example_finished(notification.example)
    end
  end

  # Passing expectations publish nothing; this is the only place to see them.
  module ExpectationProbe
    def handle_matcher(actual, initial_matcher, *rest, &block)
      result = super
      GreenSignal.timed(:expectation) { GreenSignal.on_expectation(self, actual, initial_matcher, true) }
      result
    rescue ::Exception # rubocop:disable Lint/RescueException -- re-raised untouched
      GreenSignal.on_expectation(self, actual, initial_matcher, false)
      raise
    end
  end

  # rescue_from handlers run inside Instrumentation#process_action, so a
  # rescued exception never reaches any notification payload.
  module ControllerProbe
    def rescue_with_handler(exception, *rest, **options)
      handler = begin
        handler_for_rescue(exception)
      rescue StandardError
        nil
      end
      GreenSignal.on_rescue_from(self, exception, handler) if handler && GreenSignal.current
      super
    end

    def send_action(*args, &block)
      GreenSignal.on_action_reached if GreenSignal.current
      super
    end
  end

  # What the test itself asked for, before routing decides anything.
  module IntegrationProbe
    def process(method, path, *args, **kwargs, &block)
      GreenSignal.issue_start(method, path)
      super
    ensure
      GreenSignal.issue_finish(self)
    end
  end

  # Rails.error.subscribe target.
  class ErrorSubscriber
    def report(error, handled:, severity:, context: {}, source: nil)
      GreenSignal.on_error_report(error, handled, severity, source)
    end
  end

  # Joins Rails.logger's broadcast; keeps WARN and above for the current example.
  class LogRecorder < ::Logger
    def initialize
      super(nil)
      self.level = ::Logger::WARN
    end

    def add(severity, message = nil, progname = nil)
      return true if severity.nil? || severity < level || GreenSignal.current.nil?

      message = block_given? ? yield : progname if message.nil?
      GreenSignal.on_log(severity, message)
      true
    end
  end
end

GreenSignal.boot!(RSpec.configuration) if defined?(RSpec) && RSpec.respond_to?(:configure) && ENV["GREEN_SIGNAL"] != "0"
