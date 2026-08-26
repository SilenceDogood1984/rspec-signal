# frozen_string_literal: true

RSpec.describe RSpec::Signal::Symptoms do
  let(:config) { signal_config }

  # The extractors read a failure's message; the backtrace is irrelevant to
  # them, so every subject here uses the same plain one.
  def symptom_for(message, exception_class: "RSpec::Expectations::ExpectationNotMetError")
    build_failure(config: config, backtrace: Backtraces.expectation_not_met,
                  exception_class: exception_class, message: message).symptom
  end

  describe "HTTP status mismatches" do
    it "keys on the status that actually came back" do
      symptom = symptom_for(Messages.http_status(expected: 200, actual: 404))

      expect(symptom.kind).to eq(:http_status)
      expect(symptom.key).to eq("http-status:404")
      expect(symptom.detail).to eq("expected 200, got 404")
    end

    it "reads the same status out of every wording rspec-rails uses" do
      keys = [Messages.http_status(expected: 200, actual: 404),
              Messages.http_status_class(expected: "redirect", actual: 404),
              ["expected the response to have status code :ok (200) but it was :not_found (404)"],
              ["Expected response to be a <200: OK>, but was a <404: Not Found>"],
              ["expected response status 200, got 404"]].map { |message| symptom_for(message).key }

      expect(keys).to all(eq("http-status:404"))
    end

    it "keeps the expected side in the detail, so a cluster can show the variants" do
      symptom = symptom_for(Messages.http_status_class(expected: "redirect", actual: 404))

      expect(symptom.detail).to eq("expected redirect, got 404")
    end

    it "names the status where it recognises it" do
      expect(symptom_for(Messages.http_status(actual: 404)).label).to eq("unexpected 404 (Not Found) responses")
    end

    it "keeps different actual statuses apart" do
      first = symptom_for(Messages.http_status(expected: 200, actual: 404))
      second = symptom_for(Messages.http_status(expected: 200, actual: 500))

      expect(first.key).not_to eq(second.key)
    end

    it "recognises generic expected/got output only for a response status expression" do
      symptom = symptom_for(["Failure/Error: expect(response.status).to eq(422)", "expected: 422", "got: 404"])

      expect(symptom.key).to eq("http-status:404")
      expect(symptom.detail).to eq("expected 422, got 404")
    end

    it "does not treat arbitrary three-digit comparisons as HTTP statuses" do
      symptom = symptom_for(["Failure/Error: expect(reader.page_count).to eq(422)", "expected: 422", "got: 404"])

      expect(symptom).to be_nil
    end
  end

  describe "missing selectors" do
    it "recognises Capybara's `find` wording" do
      symptom = symptom_for(Messages.element_not_found('[data-testid="reader-progress"] span'),
                            exception_class: "Capybara::ElementNotFound")

      expect(symptom.kind).to eq(:selector)
      expect(symptom.key).to eq('selector:css:[data-testid="reader-progress"] span')
    end

    it "gives `have_css` the same key, though it is a different exception" do
      selector = '[data-testid="reader-progress"] span'
      found = symptom_for(Messages.element_not_found(selector), exception_class: "Capybara::ElementNotFound")
      matched = symptom_for(Messages.no_matches(selector))

      expect(matched.key).to eq(found.key)
    end

    it "keeps different selectors apart" do
      first = symptom_for(Messages.element_not_found("#reader-shelf"), exception_class: "Capybara::ElementNotFound")
      second = symptom_for(Messages.element_not_found("#checkout-button"),
                           exception_class: "Capybara::ElementNotFound")

      expect(first.key).not_to eq(second.key)
    end

    it "recognises missing page text" do
      symptom = symptom_for(['expected to find text "Finished" in "Reader"'])

      expect(symptom.kind).to eq(:missing_text)
    end
  end

  describe "Rails and ActiveRecord shapes" do
    it "keys a routing error on the route, with identifiers masked" do
      first = symptom_for(Messages.routing_error("/readers/48213/progress"),
                          exception_class: "ActionController::RoutingError")
      second = symptom_for(Messages.routing_error("/readers/91055/progress"),
                           exception_class: "ActionController::RoutingError")

      expect(first.key).to eq(second.key)
      expect(first.key).to eq('route:[GET] "/readers/:id/progress"')
    end

    it "keeps different routes apart" do
      first = symptom_for(Messages.routing_error("/readers/1/progress"),
                          exception_class: "ActionController::RoutingError")
      second = symptom_for(Messages.routing_error("/checkouts/1"),
                           exception_class: "ActionController::RoutingError")

      expect(first.key).not_to eq(second.key)
    end

    it "keys a missing record on the model" do
      symptom = symptom_for(["Couldn't find User with 'id'=48213"],
                            exception_class: "ActiveRecord::RecordNotFound")

      expect(symptom.key).to eq("record-not-found:User")
    end

    it "keeps different models apart" do
      user = symptom_for(["Couldn't find User with 'id'=1"], exception_class: "ActiveRecord::RecordNotFound")
      order = symptom_for(["Couldn't find Order with 'id'=1"], exception_class: "ActiveRecord::RecordNotFound")

      expect(user.key).not_to eq(order.key)
    end

    it "keys a schema error on the column that is missing" do
      symptom = symptom_for(['PG::UndefinedColumn: ERROR:  column "readers.progress" does not exist'],
                            exception_class: "ActiveRecord::StatementInvalid")

      expect(symptom.key).to eq("schema:column:readers.progress")
    end

    it "keys a validation failure on the sentence" do
      symptom = symptom_for(["ActiveRecord::RecordInvalid:", "  Validation failed: Email has already been taken"],
                            exception_class: "ActiveRecord::RecordInvalid")

      expect(symptom.key).to eq("validation:email has already been taken")
    end
  end

  describe "Ruby-level errors" do
    it "keys an undefined method on the method and the receiver" do
      symptom = symptom_for(["NoMethodError:", "  undefined method 'progress' for nil"],
                            exception_class: "NoMethodError")

      expect(symptom.key).to eq("undefined-method:progress:nil")
    end

    it "reads both the old and the new Ruby wording" do
      old = symptom_for(["undefined method `progress' for nil:NilClass"], exception_class: "NoMethodError")
      new = symptom_for(["undefined method 'progress' for nil"], exception_class: "NoMethodError")

      expect(new.key).to eq(old.key)
    end

    it "keeps different missing methods apart" do
      first = symptom_for(["undefined method 'progress' for nil"], exception_class: "NoMethodError")
      second = symptom_for(["undefined method 'title' for nil"], exception_class: "NoMethodError")

      expect(first.key).not_to eq(second.key)
    end

    it "keys an uninitialized constant on the constant" do
      symptom = symptom_for(["uninitialized constant Reader::Progress"], exception_class: "NameError")

      expect(symptom.key).to eq("missing-constant:Reader::Progress")
    end
  end

  describe "the exception-class fallback" do
    it "fires for a namespaced class with nothing finer to go on" do
      symptom = symptom_for(["Connection refused - connect(2) for 127.0.0.1:5432"],
                            exception_class: "Errno::ECONNREFUSED")

      expect(symptom.key).to eq("exception:Errno::ECONNREFUSED")
    end

    it "refuses a bare class, which says nothing about cause" do
      expect(symptom_for(["boom"], exception_class: "RuntimeError")).to be_nil
      expect(symptom_for(["wrong number of arguments"], exception_class: "ArgumentError")).to be_nil
    end

    it "refuses RSpec's own expectation errors, however they are namespaced" do
      symptom = symptom_for(Messages.comparison(expected: 3, actual: 4))

      expect(symptom).to be_nil
    end

    # Otherwise an ElementNotFound whose message we could not parse would drag
    # every other unparsed selector into one meaningless cluster.
    it "refuses a class an earlier extractor is responsible for" do
      symptom = symptom_for(["Capybara::ElementNotFound:", "  something we do not recognise"],
                            exception_class: "Capybara::ElementNotFound")

      expect(symptom).to be_nil
    end
  end

  describe "failures with no diagnostic characteristic at all" do
    it "produces no symptom for an ordinary comparison" do
      expect(symptom_for(Messages.comparison(expected: "true", actual: "false"))).to be_nil
    end

    it "produces no symptom for a bare message" do
      expect(symptom_for(["boom"], exception_class: "RuntimeError")).to be_nil
    end

    it "survives a message it cannot read at all" do
      expect(symptom_for([])).to be_nil
    end
  end
end
